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

/// Lightweight request log entry (kept for compatibility without main-thread JSON serialization).
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

class _CachedGetEntry {
  _CachedGetEntry(this.data, this.storedAt);
  final dynamic data;
  final DateTime storedAt;
}

/// Single HTTP client for the shared NestJS API (`https://pos.hrpocket.in/api/v1`).
/// - Persists `jewellery_session` & `jewellery_csrf` cookies across restarts.
/// - Deduplicates concurrent identical GETs and caches read responses briefly in RAM,
///   automatically invalidating on every write (`POST`, `PUT`, `PATCH`, `DELETE`, `uploadBytes`).
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

  /// CSRF token handed out in a response header or cookie.
  String? csrfHeaderToken;

  /// Retained for backward compatibility; no longer pretty-printed per call.
  final List<ApiLogEntry> log = [];

  static const Duration _kGetCacheTtl = Duration(seconds: 10);
  final Map<String, _CachedGetEntry> _getCache = <String, _CachedGetEntry>{};
  final Map<String, Future<dynamic>> _inflightGets = <String, Future<dynamic>>{};

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
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
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
    invalidateCache();
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  void _recordFast(
    String method,
    String path,
    int? status,
    String summary,
    int durationMs,
  ) {
    log.insert(
      0,
      ApiLogEntry(
        method,
        path,
        status,
        summary,
        'Base URL: ${_dio.options.baseUrl}',
        durationMs: durationMs,
      ),
    );
    if (log.length > 40) log.removeLast();
  }

  /// Clears cached GET responses (called automatically on all mutations and context switches).
  void invalidateCache([String? pathPrefix]) {
    if (pathPrefix == null || pathPrefix.isEmpty) {
      _getCache.clear();
      return;
    }
    _getCache.removeWhere((k, _) => k.contains('|$pathPrefix'));
  }

  Future<void> clearSession() async {
    invalidateCache();
    _inflightGets.clear();
    await jar.deleteAll();
    csrfHeaderToken = null;
  }

  String _cacheKey(String path, Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) {
      return '${_dio.options.baseUrl}|$path';
    }
    final keys = query.keys.toList()..sort();
    final qStr = keys.map((k) => '$k=${query[k]}').join('&');
    return '${_dio.options.baseUrl}|$path?$qStr';
  }

  bool _isCacheableGet(String path) {
    if (path.startsWith('/auth/') || path.startsWith('/health/')) return false;
    return true;
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? query,
    bool quiet = false,
    bool forceRefresh = false,
  }) {
    if (!_isCacheableGet(path)) {
      return _send('GET', path, query: query, quiet: quiet);
    }
    final key = _cacheKey(path, query);
    if (!forceRefresh) {
      final hit = _getCache[key];
      if (hit != null &&
          DateTime.now().difference(hit.storedAt) < _kGetCacheTtl) {
        return Future<dynamic>.value(hit.data);
      }
      final inflight = _inflightGets[key];
      if (inflight != null) return inflight;
    } else {
      _getCache.remove(key);
    }

    final fut = _send('GET', path, query: query, quiet: quiet).then((data) {
      if (_getCache.length >= 64) {
        _getCache.remove(_getCache.keys.first);
      }
      _getCache[key] = _CachedGetEntry(data, DateTime.now());
      return data;
    }).whenComplete(() {
      _inflightGets.remove(key);
    });

    _inflightGets[key] = fut;
    return fut;
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) async {
    try {
      final res = await _send(
        'POST',
        path,
        body: body ?? const {},
        idempotencyKey:
            idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );
      return res;
    } finally {
      invalidateCache();
    }
  }

  Future<dynamic> put(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) async {
    try {
      final res = await _send(
        'PUT',
        path,
        body: body ?? const {},
        idempotencyKey:
            idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );
      return res;
    } finally {
      invalidateCache();
    }
  }

  Future<dynamic> patch(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) async {
    try {
      final res = await _send(
        'PATCH',
        path,
        body: body ?? const {},
        idempotencyKey:
            idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );
      return res;
    } finally {
      invalidateCache();
    }
  }

  Future<dynamic> delete(
    String path, {
    Object? body,
    String? idempotencyKey,
    bool idempotent = false,
  }) async {
    try {
      final res = await _send(
        'DELETE',
        path,
        body: body,
        idempotencyKey:
            idempotencyKey ?? (idempotent ? const Uuid().v4() : null),
      );
      return res;
    } finally {
      invalidateCache();
    }
  }

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
          final m = asMap(
            parsed is Map && parsed.containsKey('data')
                ? parsed['data']
                : parsed,
          );
          final b64 =
              '${m['contentBase64'] ?? m['base64'] ?? m['dataUrl'] ?? ''}'
                  .trim();
          if (b64.isEmpty) return null;
          final comma = b64.indexOf(',');
          return base64Decode(comma >= 0 ? b64.substring(comma + 1) : b64);
        } catch (_) {
          return null;
        }
      }
      return Uint8List.fromList(data);
    } on DioException {
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
  }) async {
    final form = FormData.fromMap({
      if (extraFields != null) ...extraFields,
      fieldName: MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: DioMediaType.parse(mimeType),
      ),
    });
    try {
      return await _send(
        method.toUpperCase(),
        path,
        body: form,
        idempotencyKey: idempotent ? const Uuid().v4() : null,
      );
    } finally {
      invalidateCache();
    }
  }

  // ---- CSRF & Origin header echo ----

  static final _csrfName =
      RegExp(r'(csrf|xsrf)', caseSensitive: false);
  static final _setCookieCsrf = RegExp(
    r'(?:jewellery_csrf|[A-Za-z0-9_-]*(?:csrf|xsrf)[A-Za-z0-9_-]*)=([^;\s]+)',
    caseSensitive: false,
  );

  Future<List<Cookie>> _cookies() async {
    if (kIsWeb) return const [];
    try {
      final uri = Uri.parse(_dio.options.baseUrl);
      final rootUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/',
      );
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
          csrfHeaderToken = Uri.decodeComponent(c.value);
        } catch (_) {
          csrfHeaderToken = c.value;
        }
        return csrfHeaderToken;
      }
    }
    return null;
  }

  String? _originForBaseUrl({bool forceForHttp = false}) {
    if (kIsWeb) return null;
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
      if (v != null && v.isNotEmpty) {
        csrfHeaderToken = v;
        return;
      }
    }
    final setCookies = h['set-cookie'];
    if (setCookies != null) {
      for (final sc in setCookies) {
        final m = _setCookieCsrf.firstMatch(sc);
        if (m != null && m.group(1) != null && m.group(1)!.isNotEmpty) {
          try {
            csrfHeaderToken = Uri.decodeComponent(m.group(1)!);
          } catch (_) {
            csrfHeaderToken = m.group(1)!;
          }
        }
      }
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
    bool quiet = false,
  }) async {
    try {
      return await _sendOnce(
        method,
        path,
        query: query,
        body: body,
        idempotencyKey: idempotencyKey,
        quiet: quiet,
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
          quiet: quiet,
        );
      }
      if (e.code == 'CSRF_REJECTED' && method != 'GET' && await _probeCsrf()) {
        return _sendOnce(
          method,
          path,
          query: query,
          body: body,
          idempotencyKey: idempotencyKey,
          quiet: quiet,
        );
      }
      rethrow;
    }
  }

  Future<bool> _probeCsrf() async {
    final before = csrfHeaderToken;
    csrfHeaderToken = null;
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
    final sw = Stopwatch()..start();
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: method == 'GET' ? null : body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      sw.stop();
      _learnFromHeaders(res.headers);
      _recordFast(
        method,
        path,
        res.statusCode,
        '${res.statusCode ?? 200} OK',
        sw.elapsedMilliseconds,
      );
      final b = res.data;
      if (b is Map && b.containsKey('data')) return b['data'];
      return b;
    } on DioException catch (e) {
      sw.stop();
      final status = e.response?.statusCode;
      final b = e.response?.data;
      _learnFromHeaders(e.response?.headers);
      var code = 'NETWORK';
      var msg =
          'Unable to reach ${Uri.tryParse(_dio.options.baseUrl)?.host ?? 'the server'}. Check your network or server URL.';
      if (b is Map && b['error'] is Map) {
        code = '${b['error']['code'] ?? 'ERROR'}';
        msg =
            '${b['error']['message'] ?? 'The request could not be completed.'}';
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
      _recordFast(method, path, status, '$code: $msg', sw.elapsedMilliseconds);
      if (status == 401 &&
          !quiet &&
          path != '/auth/login' &&
          path != '/auth/mfa/login') {
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
