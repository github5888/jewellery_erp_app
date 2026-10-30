import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

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
  ApiLogEntry(this.method, this.path, this.status, this.body, this.note) : at = DateTime.now();
  final String method, path, body, note;
  final int? status;
  final DateTime at;
  bool get ok => status != null && status! >= 200 && status! < 300;
}

/// Single HTTP client for the shared NestJS API.
/// - Persists the session cookie (survives app restarts).
/// - Echoes the CSRF token (cookie or header) on write requests.
/// - Unwraps `{ data, meta }` and maps `{ error }` to [ApiException].
/// - Never converts numbers: decimals stay strings.
class ApiClient {
  ApiClient._(this._dio, this.jar);

  final Dio _dio;
  final PersistCookieJar jar;
  VoidCallback? onUnauthorized;

  /// Bearer token, if the server ever returns one at login.
  String? bearer;

  /// CSRF token handed out in a response header, if the server does that.
  String? csrfHeaderToken;

  /// Last 40 responses, newest first.
  final List<ApiLogEntry> log = [];

  static String defaultBaseUrl() => 'http://192.168.1.8:3000/api/v1';

  static Future<ApiClient> create(String baseUrl) async {
    final dir = await getApplicationDocumentsDirectory();
    final jar = PersistCookieJar(storage: FileStorage('${dir.path}/.cookies'));
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 25),
      headers: {'Accept': 'application/json'},
    ));
    dio.interceptors.add(CookieManager(jar));
    return ApiClient._(dio, jar);
  }

  String get baseUrl => _dio.options.baseUrl;
  void setBaseUrl(String url) => _dio.options.baseUrl = url;

  Future<void> clearSession() async {
    await jar.deleteAll();
    csrfHeaderToken = null;
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, String? idempotencyKey}) =>
      _send('POST', path, body: body ?? const {}, idempotencyKey: idempotencyKey);

  // ---- CSRF + diagnostics ----

  static final _csrfName = RegExp(r'csrf|xsrf', caseSensitive: false);

  Future<List<dynamic>> _cookies() async {
    try {
      return await jar.loadForRequest(Uri.parse(_dio.options.baseUrl));
    } catch (_) {
      return const [];
    }
  }

  Future<String?> _csrfToken() async {
    if (csrfHeaderToken != null) return csrfHeaderToken;
    for (final c in await _cookies()) {
      if (_csrfName.hasMatch('${c.name}')) {
        final v = '${c.value}';
        try {
          return Uri.decodeComponent(v);
        } catch (_) {
          return v;
        }
      }
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

  Future<void> _record(String method, String path, int? status, Object? body,
      {required Iterable<String> sent, Headers? reply}) async {
    String text;
    try {
      text = body is String ? body : const JsonEncoder.withIndent('  ').convert(body);
    } catch (_) {
      text = '$body';
    }
    if (text.length > 8000) text = '${text.substring(0, 8000)}\n... (cut)';
    final jarNames = (await _cookies()).map((c) => '${c.name}').toList();
    final note = 'Sent headers: ${sent.join(', ')}\n'
        'Cookies in jar: ${jarNames.isEmpty ? '(none)' : jarNames.join(', ')}\n'
        'Reply headers: ${reply == null ? '(none)' : reply.map.keys.join(', ')}';
    log.insert(0, ApiLogEntry(method, path, status, text, note));
    if (log.length > 40) log.removeLast();
    debugPrint('[API] $method $path -> ${status ?? 'no response'}');
  }

  /// Sends the request. If the server answers CSRF_REJECTED and we have no
  /// token yet, look for one on common token endpoints and retry once.
  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    String? idempotencyKey,
  }) async {
    try {
      return await _sendOnce(method, path, query: query, body: body, idempotencyKey: idempotencyKey);
    } on ApiException catch (e) {
      if (e.code == 'CSRF_REJECTED' && method != 'GET' && await _probeCsrf()) {
        return _sendOnce(method, path, query: query, body: body, idempotencyKey: idempotencyKey);
      }
      rethrow;
    }
  }

  Future<bool> _probeCsrf() async {
    final before = await _csrfToken();
    for (final p in const ['/auth/csrf', '/csrf', '/session/csrf', '/csrf-token']) {
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
  }) async {
    final headers = <String, dynamic>{
      if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
      if (bearer != null) 'Authorization': 'Bearer $bearer',
    };
    if (method != 'GET') {
      final t = await _csrfToken();
      if (t != null) {
        headers['X-CSRF-Token'] = t;
        headers['X-XSRF-TOKEN'] = t;
      }
    }
    try {
      final res = await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: query,
        options: Options(method: method, headers: headers),
      );
      _learnFromHeaders(res.headers);
      final b = res.data;
      await _record(method, path, res.statusCode, b, sent: headers.keys, reply: res.headers);
      if (b is Map && b.containsKey('data')) return b['data'];
      return b;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final b = e.response?.data;
      _learnFromHeaders(e.response?.headers);
      await _record(method, path, status, b ?? '${e.type.name}: ${e.message}',
          sent: headers.keys, reply: e.response?.headers);
      var code = 'NETWORK';
      var msg = "Can't reach the server. Check your connection and the server address.";
      if (b is Map && b['error'] is Map) {
        code = '${b['error']['code'] ?? 'ERROR'}';
        msg = '${b['error']['message'] ?? 'Something went wrong.'}';
      } else if (status != null) {
        code = 'HTTP_$status';
        msg = status >= 500
            ? 'The server had a problem. Try again in a moment.'
            : 'The request was rejected ($status).';
      } else if (e.type == DioExceptionType.receiveTimeout || e.type == DioExceptionType.connectionTimeout) {
        code = 'TIMEOUT';
        msg = 'The server took too long to respond. Try again.';
      }
      if (status == 401 && !quiet) onUnauthorized?.call();
      throw ApiException(code, msg, status: status);
    }
  }
}

// ---- Tolerant response helpers (list shape differs per endpoint) ----

Map<String, dynamic> asMap(dynamic d) {
  if (d is Map) return Map<String, dynamic>.from(d);
  if (d is List && d.isNotEmpty && d.first is Map) {
    return Map<String, dynamic>.from(d.first as Map);
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asList(dynamic d) {
  dynamic l = d;
  if (d is Map) {
    l = d['items'] ?? d['rows'] ?? d['results'] ?? d['data'];
    l ??= d.values.firstWhere((v) => v is List, orElse: () => const []);
  }
  if (l is! List) return const [];
  return l.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
}
