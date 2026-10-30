import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/build.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../debug/api_inspector.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  bool _recoveryMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _error = context.read<AppState>().bootError;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() job) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await job();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _fillKalyanStore() {
    setState(() {
      _email.text = 'owner@kalyan.com';
      _password.text = 'Kalyan@2026Pass';
      _error = null;
    });
    context.read<AppState>().setServer(kProductionApiUrl);
  }

  void _login() {
    final mail = _email.text.trim();
    final pass = _password.text;
    if (mail.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Enter your work email address and password.');
      return;
    }
    _run(() => context.read<AppState>().login(mail, pass));
  }

  void _verify() {
    final raw = _code.text.trim().toUpperCase();
    final validTotp = RegExp(r'^\d{6}$').hasMatch(raw);
    final validRecovery = RegExp(r'^[A-HJ-NP-Z2-9]{4}(?:-[A-HJ-NP-Z2-9]{4}){2}$').hasMatch(raw);
    if (!validTotp && !validRecovery) {
      setState(() => _error = _recoveryMode
          ? 'Enter a valid recovery code (e.g. ABCD-EFGH-JKLM).'
          : 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    _run(() => context.read<AppState>().submitMfa(raw));
  }

  Future<void> _serverSheet() async {
    final app = context.read<AppState>();
    final c = TextEditingController(text: app.api.baseUrl);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('API Gateway Environment', style: T.display(22)),
                const SizedBox(height: 6),
                Text(
                  'Connect directly to the live production portal or switch to a local NestJS development server.',
                  style: T.body(13, color: Pal.muted),
                ),
                const SizedBox(height: 16),
                for (final preset in kServerPresets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      borderColor: c.text.trim() == preset.url ? Pal.teal : Pal.line,
                      color: c.text.trim() == preset.url ? Pal.tealWash.withValues(alpha: 0.35) : Colors.white,
                      onTap: () => setModal(() => c.text = preset.url),
                      child: Row(children: [
                        Icon(
                          preset.url.startsWith('https') ? Icons.cloud_done_outlined : Icons.developer_mode_rounded,
                          size: 20,
                          color: c.text.trim() == preset.url ? Pal.teal : Pal.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(preset.label, style: T.body(13.5, w: FontWeight.w700)),
                            Text(preset.subtitle, style: T.body(11.5, color: Pal.muted)),
                          ]),
                        ),
                        if (c.text.trim() == preset.url)
                          const Icon(Icons.check_circle_rounded, size: 18, color: Pal.teal),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
                const FieldLabel('Custom API Base URL'),
                TextField(
                  controller: c,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: T.mono(13),
                  decoration: const InputDecoration(hintText: 'https://pos.hrpocket.in/api/v1'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await app.setServer(c.text);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                  child: const Text('Apply Gateway Address'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mfa = context.select<AppState, bool>((s) => s.stage == AuthStage.mfa);
    final baseUrl = context.select<AppState, String>((s) => s.api.baseUrl);
    final hostLabel = Uri.tryParse(baseUrl)?.host ?? 'pos.hrpocket.in';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Pal.ink,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(children: [
            // Luxury Haute Joaillerie Hero matching https://pos.hrpocket.in/login
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF141E33), Pal.ink, Color(0xFF070B14)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 42,
                        height: 42,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Pal.goldBright.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Pal.goldBright.withValues(alpha: 0.35)),
                        ),
                        child: const GemMark(),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text('Jewellery ERP', style: T.display(20, color: Colors.white)),
                            const SizedBox(width: 8),
                            const EnterpriseBadge('Enterprise'),
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            'Haute Joaillerie & Precious Bullion',
                            style: T.body(12, color: Pal.goldSoft.withValues(alpha: 0.85), w: FontWeight.w600),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 22),
                    Text(
                      'Run your entire jewellery enterprise from one platform.',
                      style: T.display(25, color: Colors.white, w: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'From Fine 999 pure gold custody and Karigar vouchers to multi-counter POS billing and automated GST e-invoicing.',
                      style: T.body(13, color: Colors.white.withValues(alpha: 0.72)),
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _heroPill(Icons.scale_rounded, 'Fine 999 Metal Ledger'),
                      _heroPill(Icons.trending_up_rounded, 'Real-time Bullion Spot'),
                      _heroPill(Icons.verified_outlined, 'GST E-Invoicing Ready'),
                    ]),
                  ]),
                ),
              ),
            ),

            // Enterprise Workspace Sign-In Surface
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Pal.pearl,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(children: [
                Panel(
                  padding: const EdgeInsets.all(22),
                  radius: 20,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: mfa ? _mfaForm() : _loginForm(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _serverSheet,
                      icon: const Icon(Icons.dns_outlined, size: 16),
                      label: Text(hostLabel),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const ApiInspector()),
                      ),
                      icon: const Icon(Icons.monitor_heart_outlined, size: 16),
                      label: const Text('API Diagnostics'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.lock_outline_rounded, size: 13, color: Pal.muted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '256-Bit TLS · ISO/IEC 27001 RBAC Protected',
                      textAlign: TextAlign.center,
                      style: T.body(11.5, color: Pal.muted, w: FontWeight.w600),
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(
                  'Multi-Tenant Isolation · Double-Entry Integrity Locked · $kBuild',
                  textAlign: TextAlign.center,
                  style: T.body(11, color: Pal.muted),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _heroPill(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: Pal.goldSoft),
          const SizedBox(width: 6),
          Text(label, style: T.body(11.5, color: Colors.white.withValues(alpha: 0.9), w: FontWeight.w600)),
        ]),
      );

  Widget _loginForm() => Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const EnterpriseBadge('Enterprise Workspace', dark: false, icon: Icons.workspace_premium_rounded),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _fillKalyanStore,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bolt_rounded, size: 15, color: Pal.teal),
                  const SizedBox(width: 3),
                  Text('Kalyan Store Fill', style: T.body(12, color: Pal.teal, w: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Text('Sign in to workspace', style: T.display(25)),
          const SizedBox(height: 4),
          Text(
            'Enter your credentials to access your store & vault',
            style: T.body(13.5, color: Pal.muted),
          ),
          const SizedBox(height: 20),
          const FieldLabel('Work Email Address'),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'owner@kalyan.com',
              prefixIcon: Icon(Icons.mail_outline_rounded, size: 19, color: Pal.muted),
            ),
          ),
          const SizedBox(height: 16),
          FieldLabel(
            'Password',
            trailing: Text(
              'Contact admin for access',
              style: T.body(11.5, color: Pal.muted),
            ),
          ),
          TextField(
            controller: _password,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _login(),
            decoration: InputDecoration(
              hintText: '••••••••••••',
              prefixIcon: const Icon(Icons.key_rounded, size: 19, color: Pal.muted),
              suffixIcon: IconButton(
                icon: Icon(
                  _hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 19,
                  color: Pal.muted,
                ),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_error != null) _ErrorBanner(_error!),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _login,
            style: FilledButton.styleFrom(backgroundColor: Pal.teal),
            icon: _busy ? const SizedBox.shrink() : const Icon(Icons.lock_open_rounded, size: 18),
            label: _busy ? const _Spin() : const Text('Sign In to Workspace'),
          ),
        ],
      );

  Widget _mfaForm() => Column(
        key: const ValueKey('mfa'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EnterpriseBadge('2FA Security Check', dark: false, icon: Icons.shield_outlined),
          const SizedBox(height: 12),
          Text('Multi-factor verification', style: T.display(24)),
          const SizedBox(height: 6),
          Text(
            _recoveryMode
                ? 'Enter one of your 12-character emergency recovery codes.'
                : 'Open your authenticator app and enter the 6-digit TOTP code.',
            style: T.body(13.5, color: Pal.muted),
          ),
          const SizedBox(height: 20),
          if (!_recoveryMode)
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: T.mono(28, w: FontWeight.w700),
              onChanged: (v) {
                if (v.length == 6 && !_busy) _verify();
              },
              decoration: const InputDecoration(hintText: '000000'),
            )
          else
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: T.mono(18, w: FontWeight.w700),
              onSubmitted: (_) => _verify(),
              decoration: const InputDecoration(hintText: 'ABCD-EFGH-JKLM'),
            ),
          if (_error != null) _ErrorBanner(_error!),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _verify,
            style: FilledButton.styleFrom(backgroundColor: Pal.teal),
            child: _busy ? const _Spin() : const Text('Verify & Enter Workspace'),
          ),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _code.clear();
                      setState(() {
                        _recoveryMode = !_recoveryMode;
                        _error = null;
                      });
                    },
              child: Text(_recoveryMode ? 'Use 6-digit code' : 'Use recovery code'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _code.clear();
                      setState(() => _error = null);
                      context.read<AppState>().backToLogin();
                    },
              child: const Text('Switch account'),
            ),
          ]),
        ],
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Pal.dangerWash,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Pal.danger.withValues(alpha: 0.25)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, size: 17, color: Pal.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: T.body(13, color: Pal.danger, w: FontWeight.w600))),
        ]),
      );
}

class _Spin extends StatelessWidget {
  const _Spin();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2.3, color: Colors.white),
      );
}
