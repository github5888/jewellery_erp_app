import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'showrooms.dart';

enum AuthStage { booting, loggedOut, mfa, context, ready }

/// Session lifecycle: login -> (MFA) -> pick showroom -> ready.
class AppState extends ChangeNotifier {
  AppState(this.api, this.prefs) {
    api.onUnauthorized = _expired;
  }

  final ApiClient api;
  final SharedPreferences prefs;

  AuthStage stage = AuthStage.booting;
  Map<String, dynamic> user = {};
  List<ShowroomOption> options = [];
  String sessionRaw = '';
  String tenantName = '';
  String branchName = '';
  String branchCode = '';

  String get userName => '${user['displayName'] ?? user['name'] ?? user['email'] ?? ''}';
  int get branchCount => options.length;

  void _expired() {
    if (stage == AuthStage.ready || stage == AuthStage.context) {
      stage = AuthStage.loggedOut;
      notifyListeners();
    }
  }

  void _captureToken(Map<String, dynamic> d) {
    final t = d['accessToken'] ?? d['token'] ?? d['sessionToken'];
    if (t is String && t.isNotEmpty) {
      api.bearer = t;
      prefs.setString('token', t);
    }
  }

  /// Why the first session check failed (shown on the sign-in screen).
  String? bootError;

  Future<void> bootstrap() async {
    api.bearer = prefs.getString('token');
    try {
      // Wait at most 2 s on the splash. If the server is slow or down we show
      // the sign-in screen right away; a late valid session still logs us in.
      await _loadSession().timeout(const Duration(seconds: 2));
    } on TimeoutException {
      if (stage == AuthStage.booting) {
        stage = AuthStage.loggedOut;
        notifyListeners();
      }
    } on ApiException catch (e) {
      if (e.status != 401) bootError = e.message;
      stage = AuthStage.loggedOut;
      notifyListeners();
    } catch (_) {
      stage = AuthStage.loggedOut;
      notifyListeners();
    }
  }

  Future<void> refreshSession() async {
    try {
      await _loadSession();
    } on ApiException {
      // keep what we have; the screen shows the raw response for debugging
    }
  }

  Future<void> _loadSession() async {
    final raw = await api.get('/session');
    sessionRaw = const JsonEncoder.withIndent('  ').convert(raw);
    final d = asMap(raw);
    if (d['user'] == null) throw ApiException('NO_SESSION', 'Signed out.');
    user = asMap(d['user']);
    options = parseShowrooms(d);
    final sel = d['selectedContext'];
    if (sel is Map) {
      _rememberLabels(Map<String, dynamic>.from(sel));
      stage = AuthStage.ready;
    } else {
      stage = AuthStage.context;
    }
    notifyListeners();
  }

  void _rememberLabels(Map<String, dynamic> sel) {
    final bid = '${sel['branchId'] ?? ''}';
    for (final o in options) {
      if (o.branchId == bid) {
        tenantName = o.tenantName;
        branchName = o.branchName;
        branchCode = o.branchCode;
        return;
      }
    }
    branchName = '${sel['branchName'] ?? ''}';
    tenantName = '${sel['tenantName'] ?? ''}';
  }

  Future<void> login(String email, String password) async {
    final d = asMap(await api.post('/auth/login', body: {'email': email.trim(), 'password': password}));
    if (d['mfaRequired'] == true) {
      stage = AuthStage.mfa;
      notifyListeners();
      return;
    }
    _captureToken(d);
    await _loadSession();
  }

  Future<void> submitMfa(String code) async {
    final d = asMap(await api.post('/auth/mfa/login', body: {'code': code.trim()}));
    _captureToken(d);
    await _loadSession();
  }

  void backToLogin() {
    stage = AuthStage.loggedOut;
    notifyListeners();
  }

  Future<void> selectContext(ShowroomOption o) async {
    await api.post('/session/context', body: {
      'tenantId': o.tenantId,
      'legalEntityId': o.entityId,
      'branchId': o.branchId,
    });
    tenantName = o.tenantName;
    branchName = o.branchName;
    branchCode = o.branchCode;
    stage = AuthStage.ready;
    notifyListeners();
  }

  void switchShowroom() {
    stage = AuthStage.context;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {}
    await api.clearSession();
    api.bearer = null;
    await prefs.remove('token');
    user = {};
    options = [];
    stage = AuthStage.loggedOut;
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    api.setBaseUrl(u);
    await prefs.setString('baseUrl_v2', u);
    notifyListeners();
  }
}
