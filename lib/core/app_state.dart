import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'showrooms.dart';

enum AuthStage { booting, loggedOut, mfa, context, ready }

/// Session lifecycle matching https://pos.hrpocket.in:
/// Login -> (2FA TOTP / Recovery Code) -> Select Store/Branch Context -> Ready.
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

  String selectedTenantId = '';
  String selectedEntityId = '';
  String selectedBranchId = '';
  String tenantName = '';
  String entityName = '';
  String branchName = '';
  String branchCode = '';
  String currency = 'INR';
  String timezone = 'Asia/Kolkata';

  bool mfaEnrolled = false;
  int mfaLevel = 0;
  String actorKind = 'TENANT_MEMBER';

  /// Active showroom / company logo (`PNG`, `JPEG`, or `WebP` bytes) scoped to
  /// the selected branch (`GET /organization/invoice-profile/logo`).
  /// Shown in the top-right header badge on `HomeScreen` when uploaded.
  Uint8List? showroomLogoBytes;
  String _logoBranchKey = '';

  String get userName => '${user['displayName'] ?? user['name'] ?? user['email'] ?? ''}';
  String get userEmail => '${user['email'] ?? ''}';
  int get branchCount => options.length;

  /// Why the initial session check failed (only set on non-401 network errors).
  String? bootError;

  void _expired() {
    if (stage == AuthStage.ready || stage == AuthStage.context) {
      showroomLogoBytes = null;
      _logoBranchKey = '';
      stage = AuthStage.loggedOut;
      notifyListeners();
    }
  }

  /// Updates the active showroom logo in memory and notifies `HomeScreen` / `MoreScreen` immediately.
  void setShowroomLogo(Uint8List? bytes, {String? branchId}) {
    _logoBranchKey = branchId ?? selectedBranchId;
    showroomLogoBytes = (bytes != null && bytes.isNotEmpty) ? bytes : null;
    notifyListeners();
  }

  /// Fetches the private branch-scoped showroom logo from
  /// `GET /organization/invoice-profile/logo` (with inline base64 fallback from
  /// `GET /organization/invoice-profile`).
  Future<void> loadShowroomLogo({bool force = false}) async {
    if (stage != AuthStage.ready) return;
    final targetBranch = selectedBranchId;
    final targetEntity = selectedEntityId;
    if (!force && _logoBranchKey == targetBranch && showroomLogoBytes != null) {
      return;
    }

    final query = <String, dynamic>{
      if (targetBranch.isNotEmpty) 'branchId': targetBranch,
      if (targetEntity.isNotEmpty) 'legalEntityId': targetEntity,
    };

    Uint8List? bytes;
    try {
      bytes = await api.getBytes('/organization/invoice-profile/logo', query: query);
      if (bytes == null || bytes.isEmpty) {
        final env = asMap(
          await api.get('/organization/invoice-profile', query: query),
        );
        final nested = asMap(
          env['profile'] ?? env['invoiceProfile'] ?? env['branchProfile'],
        );
        final showroom = asMap(env['showroomIdentity'] ?? env['showroom']);
        final merged = <String, dynamic>{...env, ...nested, ...showroom};
        final inlineB64 = '${merged['logoDataUrl'] ?? merged['logoBase64'] ?? merged['logoContentBase64'] ?? ''}'.trim();
        if (inlineB64.isNotEmpty) {
          final comma = inlineB64.indexOf(',');
          bytes = base64Decode(
            comma >= 0 ? inlineB64.substring(comma + 1) : inlineB64,
          );
        }
      }
    } catch (_) {
      // Silently ignore when a user role lacks invoice-profile read access or offline.
      return;
    }

    if (stage != AuthStage.ready || selectedBranchId != targetBranch) return;
    _logoBranchKey = targetBranch;
    final nextLogo = (bytes != null && bytes.isNotEmpty) ? bytes : null;
    if (showroomLogoBytes != nextLogo) {
      showroomLogoBytes = nextLogo;
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

  Future<void> bootstrap() async {
    api.bearer = prefs.getString('token');
    try {
      await _loadSession().timeout(const Duration(seconds: 3));
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
      // Preserve current state; diagnostics view retains raw log.
    }
  }

  Future<void> _loadSession() async {
    final raw = await api.get('/session');
    sessionRaw = const JsonEncoder.withIndent('  ').convert(raw);
    final d = asMap(raw);
    if (d['user'] == null) throw ApiException('NO_SESSION', 'Signed out.');
    user = asMap(d['user']);
    final mfaMap = asMap(d['mfa']);
    mfaEnrolled = mfaMap['enrolled'] == true;
    mfaLevel = mfaMap['level'] is int ? mfaMap['level'] as int : 0;
    options = parseShowrooms(d);

    final sel = d['selectedContext'];
    if (sel is Map) {
      final selMap = Map<String, dynamic>.from(sel);
      actorKind = '${selMap['actorKind'] ?? 'TENANT_MEMBER'}';
      _rememberLabels(selMap);
      if (_logoBranchKey != selectedBranchId) {
        showroomLogoBytes = null;
      }
      stage = AuthStage.ready;
      notifyListeners();
      unawaited(loadShowroomLogo(force: true));
    } else {
      showroomLogoBytes = null;
      _logoBranchKey = '';
      stage = AuthStage.context;
      notifyListeners();
    }
  }

  void _rememberLabels(Map<String, dynamic> sel) {
    selectedTenantId = '${sel['tenantId'] ?? ''}';
    selectedEntityId = '${sel['legalEntityId'] ?? ''}';
    selectedBranchId = '${sel['branchId'] ?? ''}';
    for (final o in options) {
      if (o.branchId == selectedBranchId) {
        tenantName = o.tenantName;
        entityName = o.entityName;
        branchName = o.branchName;
        branchCode = o.branchCode;
        currency = o.currency;
        timezone = o.timezone;
        return;
      }
    }
    final sup = sel['support'];
    if (sup is Map) {
      final t = sup['tenant'];
      final e = sup['legalEntity'];
      final b = sup['branch'];
      if (t is Map) tenantName = '${t['name'] ?? ''}';
      if (e is Map) entityName = '${e['legalName'] ?? e['name'] ?? ''}';
      if (b is Map) {
        branchName = '${b['name'] ?? ''}';
        branchCode = '${b['code'] ?? ''}';
      }
      return;
    }
    branchName = '${sel['branchName'] ?? ''}';
    tenantName = '${sel['tenantName'] ?? ''}';
  }

  Future<void> login(String email, String password) async {
    bootError = null;
    final d = asMap(await api.post(
      '/auth/login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
    ));
    if (d['mfaRequired'] == true) {
      stage = AuthStage.mfa;
      notifyListeners();
      return;
    }
    _captureToken(d);
    await _loadSession();
  }

  Future<void> submitMfa(String code) async {
    final d = asMap(await api.post(
      '/auth/mfa/login',
      body: {'code': code.trim().toUpperCase()},
    ));
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
    if (_logoBranchKey != o.branchId) {
      showroomLogoBytes = null;
      _logoBranchKey = '';
    }
    selectedTenantId = o.tenantId;
    selectedEntityId = o.entityId;
    selectedBranchId = o.branchId;
    tenantName = o.tenantName;
    entityName = o.entityName;
    branchName = o.branchName;
    branchCode = o.branchCode;
    currency = o.currency;
    timezone = o.timezone;
    stage = AuthStage.ready;
    notifyListeners();
    unawaited(loadShowroomLogo(force: true));
  }

  Future<void> selectContextByIds({
    required String tenantId,
    required String legalEntityId,
    required String branchId,
    String? legalEntityName,
    String? branchDisplayName,
    String? branchDisplayCode,
  }) async {
    await api.post('/session/context', body: {
      'tenantId': tenantId,
      'legalEntityId': legalEntityId,
      'branchId': branchId,
    });
    if (_logoBranchKey != branchId) {
      showroomLogoBytes = null;
      _logoBranchKey = '';
    }
    selectedTenantId = tenantId;
    selectedEntityId = legalEntityId;
    selectedBranchId = branchId;
    if (legalEntityName != null && legalEntityName.isNotEmpty) {
      entityName = legalEntityName;
    }
    if (branchDisplayName != null && branchDisplayName.isNotEmpty) {
      branchName = branchDisplayName;
    }
    if (branchDisplayCode != null && branchDisplayCode.isNotEmpty) {
      branchCode = branchDisplayCode;
    }
    stage = AuthStage.ready;
    notifyListeners();
    await refreshSession();
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
    selectedTenantId = '';
    selectedEntityId = '';
    selectedBranchId = '';
    tenantName = '';
    entityName = '';
    branchName = '';
    branchCode = '';
    showroomLogoBytes = null;
    _logoBranchKey = '';
    stage = AuthStage.loggedOut;
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (u.isEmpty) u = ApiClient.defaultBaseUrl();
    api.setBaseUrl(u);
    await prefs.setString('baseUrl_v3', u);
    bootError = null;
    notifyListeners();
  }
}

/// Alias kept for modules referencing auth/session context controller.
typedef AuthController = AppState;
