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

  void _login() {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    _run(() => context.read<AppState>().login(_email.text, _password.text));
  }

  void _verify() {
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    _run(() => context.read<AppState>().submitMfa(_code.text));
  }

  Future<void> _server() async {
    final app = context.read<AppState>();
    final c = TextEditingController(text: app.api.baseUrl);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Server address', style: T.display(22)),
          const SizedBox(height: 6),
          Text('Use your laptop\'s Wi-Fi IP on a real phone, 10.0.2.2 on the Android emulator.',
              style: T.body(13.5, color: Pal.muted)),
          const SizedBox(height: 16),
          TextField(controller: c, keyboardType: TextInputType.url, autocorrect: false),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await app.setServer(c.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('Save address'),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mfa = context.select<AppState, bool>((s) => s.stage == AuthStage.mfa);
    final h = MediaQuery.of(context).size.height;
    return Scaffold(
      backgroundColor: Pal.ink,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: h),
          child: Column(children: [
            SafeArea(
              bottom: false,
              child: SizedBox(
                height: h * 0.36,
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox(width: 78, height: 78, child: GemMark()),
                    const SizedBox(height: 18),
                    Text('Jewellery ERP', style: T.display(30, color: Colors.white)),
                    const SizedBox(height: 6),
                    Text('Rates, stock and billing for your showroom',
                        style: T.body(14, color: Pal.goldSoft.withValues(alpha: 0.85))),
                  ]),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              constraints: BoxConstraints(minHeight: h * 0.64),
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
              decoration: const BoxDecoration(
                color: Pal.pearl,
                borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: mfa ? _mfaForm() : _loginForm(),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _loginForm() => Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sign in', style: T.display(28)),
          const SizedBox(height: 22),
          const FieldLabel('Email'),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(hintText: 'you@yourshowroom.com'),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Password'),
          TextField(
            controller: _password,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _login(),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Pal.muted),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_error != null) _ErrorLine(_error!),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy ? const _Spin() : const Text('Sign in'),
          ),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.center, children: [
            TextButton.icon(
              onPressed: _server,
              icon: const Icon(Icons.dns_outlined, size: 18),
              label: Text(Uri.tryParse(context.read<AppState>().api.baseUrl)?.authority ?? 'Server'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApiInspector())),
              icon: const Icon(Icons.monitor_heart_outlined, size: 18),
              label: const Text('API check'),
            ),
          ]),
          Center(child: Text(kBuild, style: T.body(11.5, color: Pal.muted))),
        ],
      );

  Widget _mfaForm() => Column(
        key: const ValueKey('mfa'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Two-step check', style: T.display(28)),
          const SizedBox(height: 8),
          Text('Open your authenticator app and enter the 6-digit code for this account.',
              style: T.body(14.5, color: Pal.muted)),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: T.display(34, w: FontWeight.w600).copyWith(letterSpacing: 10),
            onChanged: (v) {
              if (v.length == 6 && !_busy) _verify();
            },
            decoration: const InputDecoration(hintText: '······'),
          ),
          if (_error != null) _ErrorLine(_error!),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _verify,
            child: _busy ? const _Spin() : const Text('Verify and continue'),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () {
                      _code.clear();
                      setState(() => _error = null);
                      context.read<AppState>().backToLogin();
                    },
              child: const Text('Use a different account'),
            ),
          ),
        ],
      );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Pal.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: T.body(13.5, color: Pal.danger, w: FontWeight.w600))),
        ]),
      );
}

class _Spin extends StatelessWidget {
  const _Spin();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      );
}
