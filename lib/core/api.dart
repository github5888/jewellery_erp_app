import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'build.dart';

/// Error in the backend envelope: { error: { code, message } }
class ApiException implements Exception {
  ApiException(this.code, this.message, {this.status});
  final String code;
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// One recorded request, shown in the API inspector. Request bodies and
/// cookie/token VALUES are never stored: only the response and header NAMES.
class ApiLogEntry {
  ApiLogEntry(
    this.method,
    this.path,
    this.status,
    this.body,
    this.note, {
    this.durationMs,
  }) : at = DateTime.now();
  final String method, path, body, note;
  final int? status;
  final int? durationMs;
  final DateTime at;
  bool get ok => status != null && status! >= 200 && status! < 300;
  String get summary => body;
}

/// Single HTTP client for the shared NestJS API (`https://pos.hrpocket.in/api/v1`).
/// - Persists `jewellery_session` & `jewellery_csrf` cookies across restarts.
/// - Echoes `x-csrf-token` and allowed `Origin` header on write requests to pass `CsrfGuard`.
/// - Unwraps `{ data, meta }` and maps `{ error: { code, message } }` to [ApiException].
/// - Preserves high-precision decimal strings without float conversion.
class ApiClient extends ChangeNotifier {
  ApiClient._(this._dio, this.jar);

  factory ApiClient.inMemory({String baseUrl = kProductionApiUrl}) {
    final jar = CookieJar();
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: const {'Accept': 'application/json'},
    ));
    return ApiClient._(dio, jar);
  }

  final Dio _dio;
  final CookieJar jar;
  VoidCallback? onUnauthorized;

  /// Bearer token, if the server ever returns one at login.
  String? bearer;

  /// CSRF token handed out in a response header, if provided.
  String? csrfHeaderToken;

  /// Last 50 responses, newest first.
  final List<ApiLogEntry> log = [];

  static String defaultBaseUrl() => kProductionApiUrl;

  static Future<ApiClient> create(String baseUrl) async {
    late final CookieJar jar;
    if (kIsWeb) {
      jar = CookieJar();
    } else {
      final dir = await getApplicationDocumentsDirectory();
      jar = PersistCookieJar(storage: FileStorage('${dir.path}/.cookies'));
    }
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 14),
      receiveTimeout: const Duration(seconds: 28),
      headers: const {'Accept': 'application/json'},
      extra: kIsWeb ? const {'withCredentials': true} : const {},
    ));
    if (!kIsWeb) {
      dio.interceptors.add(CookieManager(jar));
    }
    return ApiClient._(dio, jar);
  }

  String get baseUrl => _dio.options.baseUrl;
  void setBaseUrl(String url) {
    _dio.options.baseUrl = url;
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  Future<void> clearSession() async {
    await jar.deleteAll();
    csrfHeaderToken = null;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) =>
      _send(
        'POST',
        path,
        body: body ?? const {},
        idempotencyKey: idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );

  Future<dynamic> put(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) =>
      _send(
        'PUT',
        path,
        body: body ?? const {},
        idempotencyKey: idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );

  Future<dynamic> patch(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) =>
      _send(
        'PATCH',
        path,
        body: body ?? const {},
        idempotencyKey: idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );

  Future<dynamic> delete(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) =>
      _send(
        'DELETE',
        path,
        body: body,
        idempotencyKey: idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );

  /// Fetches private binary bytes (e.g. `/organization/invoice-profile/logo`)
  /// using the active session cookie jar. Returns `null` if 404 / no content.
  Future<Uint8List?> getBytes(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final headers = <String, dynamic>{
      if (bearer != null) 'Authorization': 'Bearer $bearer',
      'Accept': 'image/*, application/octet-stream, application/json',
    };
    try {
      final res = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(
          headers: headers,
          responseType: ResponseType.bytes,
        ),
      );
      _learnFromHeaders(res.headers);
      final data = res.data;
      if (data == null || data.isEmpty) return null;
      final ct = (res.headers.value('content-type') ?? '').toLowerCase();
      if (ct.contains('application/json')) {
        try {
          final parsed = jsonDecode(utf8.decode(data));
          final m = asMap(parsed is Map && parsed.containsKey('data') ? parsed['data'] : parsed);
          final b64 = '${m['contentBase64'] ?? m['base64'] ?? m['dataUrl'] ?? ''}'.trim();
          if (b64.isEmpty) return null;
          final comma = b64.indexOf(',');
          return base64Decode(comma >= 0 ? b64.substring(comma + 1) : b64);
        } catch (_) {
          return null;
        }
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 204) {
        return null;
      }
      return null;
    }
  }

  /// Uploads a binary image/file (`PNG`, `JPEG`, `WebP`) via `multipart/form-data`
  /// with full CSRF + Origin headers.
  Future<dynamic> uploadBytes(
    String method,
    String path, {
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String fieldName = 'file',
    Map<String, dynamic>? extraFields,
    bool idempotent = true,
  }) {
    final form = FormData.fromMap({
      if (extraFields != null) ...extraFields,
      fieldName: MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    return _send(
      method,
      path,
      body: form,
      idempotencyKey: idempotent ? const Uuid().v4() : null,
    );
  }

  /// Downloads raw image bytes from a direct `https://` URL without sending
  /// private ERP session cookies or bearer headers to external hosts.
  Future<Uint8List> fetchExternalBytes(String url) async {
    final trimmed = url.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) {
      throw ApiException('INVALID_URL', 'Enter a valid https:// image URL.');
    }
    final plain = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        responseType: ResponseType.bytes,
        followRedirects: true,
      ),
    );
    try {
      final res = await plain.getUri<List<int>>(uri);
      final data = res.data;
      if (data == null || data.isEmpty) {
        throw ApiException('EMPTY_IMAGE', 'The image URL returned an empty response.');
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw ApiException(
        'IMAGE_FETCH_FAILED',
        e.message ?? 'Unable to download image from URL (${e.response?.statusCode ?? 'network error'}).',
      );
    } finally {
      plain.close();
    }
  }

  // ---- CSRF, Origin & diagnostics ----

  static final _csrfName = RegExp(r'csrf|xsrf', caseSensitive: false);

  Future<List<Cookie>> _cookies() async {
    if (kIsWeb) return const [];
    try {
      final uri = Uri.parse(_dio.options.baseUrl);
      final rootUri = Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null, path: '/');
      final list = await jar.loadForRequest(uri);
      if (list.isNotEmpty) return list;
      return await jar.loadForRequest(rootUri);
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> cookieNames() async =>
      (await _cookies()).map((c) => c.name).toSet().toList();

  Future<String?> _csrfToken() async {
    if (csrfHeaderToken != null && csrfHeaderToken!.isNotEmpty) {
      return csrfHeaderToken;
    }
    for (final c in await _cookies()) {
      if (c.name == 'jewellery_csrf' || _csrfName.hasMatch(c.name)) {
        try {
          return Uri.decodeComponent(c.value);
        } catch (_) {
          return c.value;
        }
      }
    }
    return null;
  }

  String? _originForBaseUrl({bool forceForHttp = false}) {
    if (kIsWeb) return null; // Browser sets Origin automatically.
    final uri = Uri.tryParse(_dio.options.baseUrl);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.scheme == 'https' || forceForHttp) {
      return uri.origin;
    }
    return null;
  }

  void _learnFromHeaders(Headers? h) {
    if (h == null) return;
    for (final n in const ['x-csrf-token', 'x-xsrf-token', 'csrf-token']) {
      final v = h.value(n);
      if (v != null && v.isNotEmpty) csrfHeaderToken = v;
    }
  }

  Future<void> _record(
    String method,
    String path,
    int? status,
    Object? body, {
    required Iterable<String> sent,
    Headers? reply,
    int? durationMs,
  }) async {
    String text;
    try {
      if (body == null || (body is String && body.isEmpty)) {
        text = '(204 No Content)';
      } else {
        text = body is String ? body : const JsonEncoder.withIndent('  ').convert(body);
      }
    } catch (_) {
      text = '$body';
    }
    if (text.length > 8000) text = '${text.substring(0, 8000)}\n... (truncated)';
    final jarNames = await cookieNames();
    final note = 'Sent headers: ${sent.isEmpty ? '(default)' : sent.join(', ')}\n'
        'Cookies in jar: ${jarNames.isEmpty ? (kIsWeb ? '(browser-managed)' : '(none)') : jarNames.join(', ')}\n'
        'Reply headers: ${reply == null ? '(none)' : reply.map.keys.join(', ')}';
    log.insert(0, ApiLogEntry(method, path, status, text, note, durationMs: durationMs));
    if (log.length > 50) log.removeLast();
    notifyListeners();
    debugPrint('[API] $method $path -> ${status ?? 'no response'} (${durationMs ?? 0}ms)');
  }

  /// Sends the request. Automatically handles `ORIGIN_REJECTED` (on local HTTP setups
  /// running with production NODE_ENV) and `CSRF_REJECTED` token refresh.
  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    try {
      return await _sendOnce(
        method,
        path,
        query: query,
        body: body,
        idempotencyKey: idempotencyKey,
      );
    } on ApiException catch (e) {
      if (e.code == 'ORIGIN_REJECTED' && method != 'GET' && !kIsWeb) {
        return _sendOnce(
          method,
          path,
          query: query,
          body: body,
          idempotencyKey: idempotencyKey,
          forceOrigin: true,
        );
      }
      if (e.code == 'CSRF_REJECTED' && method != 'GET' && await _probeCsrf()) {
        return _sendOnce(
          method,
          path,
          query: query,
          body: body,
          idempotencyKey: idempotencyKey,
        );
      }
      rethrow;
    }
  }

  Future<bool> _probeCsrf() async {
    final before = await _csrfToken();
    for (final p in const ['/session', '/auth/csrf', '/csrf']) {
      try {
        final d = asMap(await _sendOnce('GET', p, quiet: true));
        for (final k in const ['csrfToken', 'csrf', 'xsrfToken', 'token']) {
          final v = d[k];
          if (v is String && v.isNotEmpty) csrfHeaderToken = v;
        }
      } catch (_) {}
    }
    final after = await _csrfToken();
    return after != null && after != before;
  }

  Future<dynamic> _sendOnce(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
    bool quiet = false,
    bool forceOrigin = false,
  }) async {
    final sw = Stopwatch()..start();
    final headers = <String, dynamic>{
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      if (bearer != null) 'Authorization': 'Bearer $bearer',
    };
    if (method != 'GET') {
      final origin = _originForBaseUrl(forceForHttp: forceOrigin);
      if (origin != null) {
        headers['Origin'] = origin;
      }
      final t = await _csrfToken();
      if (t != null && t.isNotEmpty) {
        headers['x-csrf-token'] = t;
        headers['X-XSRF-TOKEN'] = t;
      }
    }
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: method == 'GET' ? null : body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      sw.stop();
      _learnFromHeaders(res.headers);
      final b = res.data;
      await _record(
        method,
        path,
        res.statusCode,
        b,
        sent: headers.keys,
        reply: res.headers,
        durationMs: sw.elapsedMilliseconds,
      );
      if (b is Map && b.containsKey('data')) return b['data'];
      return b;
    } on DioException catch (e) {
      sw.stop();
      final status = e.response?.statusCode;
      final b = e.response?.data;
      _learnFromHeaders(e.response?.headers);
      await _record(
        method,
        path,
        status,
        b ?? '${e.type.name}: ${e.message}',
        sent: headers.keys,
        reply: e.response?.headers,
        durationMs: sw.elapsedMilliseconds,
      );
      var code = 'NETWORK';
      var msg = 'Unable to reach ${Uri.tryParse(_dio.options.baseUrl)?.host ?? 'the server'}. Check your network or server URL.';
      if (b is Map && b['error'] is Map) {
        code = '${b['error']['code'] ?? 'ERROR'}';
        msg = '${b['error']['message'] ?? 'The request could not be completed.'}';
      } else if (status != null) {
        code = 'HTTP_$status';
        msg = status >= 500
            ? 'Server error ($status). Please retry in a moment.'
            : 'Request rejected ($status).';
      } else if (e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionTimeout) {
        code = 'TIMEOUT';
        msg = 'Gateway timed out waiting for a response. Please retry.';
      }
      if (status == 401 && !quiet && path != '/auth/login' && path != '/auth/mfa/login') {
        onUnauthorized?.call();
      }
      throw ApiException(code, msg, status: status);
    }
  }
}

// ---- Tolerant envelope & workspace extractors ----

Map<String, dynamic> asMap(dynamic d) {
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is List && d.isNotEmpty && d.first is Map) {
    return Map<String, dynamic>.from(d.first as Map);
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asList(dynamic d, {List<String> keys = const []}) {
  dynamic l = d;
  if (d is Map) {
    for (final k in keys) {
      if (d[k] is List) {
        l = d[k];
        break;
      }
    }
    if (l is Map) {
      l = d['items'] ?? d['rows'] ?? d['results'] ?? d['data'];
      l ??= d.values.firstWhere((v) => v is List, orElse: () => const []);
    }
  }
  if (l is! List) return const [];
  return l.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
}

int asInt(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v != null) {
    final parsed = int.tryParse(v.toString().trim());
    if (parsed != null) return parsed;
  }
  return fallback;
}
