import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

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

  void _login() {
    final mail = _email.text.trim();
    final pass = _password.text;
    if (mail.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter your email ID and password.');
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
          ? 'Enter a valid recovery code.'
          : 'Enter the 6-digit authenticator code.');
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
                Row(children: [
                  Expanded(child: Text('Gateway Configuration', style: T.display(21))),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(builder: (_) => const ApiInspector()),
                      );
                    },
                    icon: const Icon(Icons.monitor_heart_outlined, size: 16),
                    label: const Text('Diagnostics'),
                  ),
                ]),
                const SizedBox(height: 12),
                for (final preset in kServerPresets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      borderColor: c.text.trim() == preset.url ? Pal.gold : Pal.line,
                      color: c.text.trim() == preset.url ? Pal.goldWash : Colors.white,
                      onTap: () => setModal(() => c.text = preset.url),
                      child: Row(children: [
                        Icon(
                          preset.url.startsWith('https') ? Icons.cloud_done_outlined : Icons.dns_outlined,
                          size: 20,
                          color: c.text.trim() == preset.url ? Pal.goldDeep : Pal.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(preset.label, style: T.body(13.5, w: FontWeight.w700)),
                            Text(preset.subtitle, style: T.body(11.5, color: Pal.muted)),
                          ]),
                        ),
                        if (c.text.trim() == preset.url)
                          const Icon(Icons.check_circle_rounded, size: 18, color: Pal.goldDeep),
                      ]),
                    ),
                  ),
                const SizedBox(height: 10),
                const FieldLabel('Server Endpoint'),
                TextField(
                  controller: c,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: T.mono(13),
                  decoration: const InputDecoration(hintText: 'https://pos.hrpocket.in/api/v1'),
                ),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Save Connection',
                  onPressed: () async {
                    await app.setServer(c.text);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _luxuryInput({
    required String hint,
    required IconData prefix,
    Widget? suffix,
  }) {
    OutlineInputBorder b(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xAA120D08),
      hintText: hint,
      hintStyle: T.body(13.8, color: Colors.white.withValues(alpha: 0.42)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      prefixIcon: Icon(prefix, size: 19, color: Pal.goldSoft.withValues(alpha: 0.85)),
      suffixIcon: suffix,
      border: b(Pal.goldBright.withValues(alpha: 0.28)),
      enabledBorder: b(Pal.goldBright.withValues(alpha: 0.28)),
      focusedBorder: b(Pal.goldBright, 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mfa = context.select<AppState, bool>((s) => s.stage == AuthStage.mfa);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0A06),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Subtle Royal 22K Gold Jewellery Watermark Background
            Positioned.fill(
              child: CustomPaint(
                painter: const _FiligreeWatermarkPainter(),
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: 0.34,
                child: Image.asset(
                  'assets/images/jewellery_watermark.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            // 2. Warm Espresso-Gold Luxury Vignette Overlay
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xFF0E0A06).withValues(alpha: 0.72),
                      const Color(0xFF150F09).withValues(alpha: 0.58),
                      const Color(0xFF0D0905).withValues(alpha: 0.86),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Discreet Top-Right Connection Settings Icon
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, right: 12),
                  child: IconButton(
                    tooltip: 'Server Settings',
                    onPressed: _serverSheet,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.28),
                      side: BorderSide(color: Pal.goldBright.withValues(alpha: 0.24)),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 18, color: Pal.goldSoft),
                  ),
                ),
              ),
            ),

            // 4. Centered Minimal Royal Gold Sign-In Card
            SafeArea(
              child: LayoutBuilder(
                builder: (ctx, constraints) => SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Exact `pos.hrpocket.in` Website Brand Logo
                            const GemMark(size: 56, darkSurface: true),
                            const SizedBox(height: 14),
                            Text(
                              'Jewellery ERP',
                              textAlign: TextAlign.center,
                              style: T.display(27, color: const Color(0xFFFDF8EE), w: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 26, height: 1, color: Pal.goldBright.withValues(alpha: 0.45)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 9),
                                  child: Text(
                                    'TRADITION  •  TRUST  •  GROWTH',
                                    style: T.caps(9.5, color: Pal.goldSoft, letterSpacing: 1.5),
                                  ),
                                ),
                                Container(width: 26, height: 1, color: Pal.goldBright.withValues(alpha: 0.45)),
                              ],
                            ),
                            const SizedBox(height: 26),

                            // Frosted Smoked-Velvet & Royal Gold Login Card
                            ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                                  decoration: BoxDecoration(
                                    color: const Color(0xBF1B140C),
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: Pal.goldBright.withValues(alpha: 0.38),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.45),
                                        blurRadius: 30,
                                        offset: const Offset(0, 14),
                                      ),
                                    ],
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    child: mfa ? _mfaForm() : _loginForm(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _darkFieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 7),
        child: Text(
          text,
          style: T.body(12.5, color: Pal.goldSoft.withValues(alpha: 0.92), w: FontWeight.w600),
        ),
      );

  Widget _loginForm() => Column(
        key: const ValueKey('login'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sign in to workspace',
            style: T.display(22, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Enter your authorised ID and password',
            style: T.body(12.8, color: Colors.white.withValues(alpha: 0.65)),
          ),
          const SizedBox(height: 20),
          _darkFieldLabel('User ID / Email'),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            textInputAction: TextInputAction.next,
            style: T.body(14.5, color: Colors.white, w: FontWeight.w600),
            cursorColor: Pal.goldSoft,
            decoration: _luxuryInput(
              hint: 'Enter your email address',
              prefix: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 15),
          _darkFieldLabel('Password'),
          TextField(
            controller: _password,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            style: T.body(14.5, color: Colors.white, w: FontWeight.w600),
            cursorColor: Pal.goldSoft,
            onSubmitted: (_) => _login(),
            decoration: _luxuryInput(
              hint: 'Enter your password',
              prefix: Icons.lock_outline_rounded,
              suffix: IconButton(
                icon: Icon(
                  _hide ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 19,
                  color: Pal.goldSoft.withValues(alpha: 0.75),
                ),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_error != null) _ErrorBanner(_error!),
          const SizedBox(height: 22),
          RoyalGoldButton(
            label: 'Sign In',
            icon: Icons.login_rounded,
            busy: _busy,
            onPressed: _login,
          ),
        ],
      );

  Widget _mfaForm() => Column(
        key: const ValueKey('mfa'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Two-Step Verification', style: T.display(22, color: Colors.white)),
          const SizedBox(height: 6),
          Text(
            _recoveryMode
                ? 'Enter your emergency recovery code.'
                : 'Enter the 6-digit code from your authenticator app.',
            style: T.body(12.8, color: Colors.white.withValues(alpha: 0.68)),
          ),
          const SizedBox(height: 18),
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
              style: T.mono(26, color: Pal.goldSoft, w: FontWeight.w700),
              cursorColor: Pal.goldSoft,
              onChanged: (v) {
                if (v.length == 6 && !_busy) _verify();
              },
              decoration: _luxuryInput(hint: '000000', prefix: Icons.shield_outlined),
            )
          else
            TextField(
              controller: _code,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: T.mono(17, color: Pal.goldSoft, w: FontWeight.w700),
              cursorColor: Pal.goldSoft,
              onSubmitted: (_) => _verify(),
              decoration: _luxuryInput(hint: 'XXXX-XXXX-XXXX', prefix: Icons.vpn_key_outlined),
            ),
          if (_error != null) _ErrorBanner(_error!),
          const SizedBox(height: 20),
          RoyalGoldButton(
            label: 'Verify & Continue',
            busy: _busy,
            onPressed: _verify,
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [
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
                child: Text(
                  _recoveryMode ? 'Use 6-digit code' : 'Use recovery code',
                  style: T.body(12.5, color: Pal.goldSoft, w: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        _code.clear();
                        setState(() => _error = null);
                        context.read<AppState>().backToLogin();
                      },
                child: Text(
                  'Back to sign in',
                  style: T.body(12.5, color: Colors.white70, w: FontWeight.w600),
                ),
              ),
            ],
          ),
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
          color: const Color(0x38DC2626),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x80F87171)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline_rounded, size: 17, color: Color(0xFFFCA5A5)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: T.body(12.5, color: const Color(0xFFFECACA), w: FontWeight.w600),
            ),
          ),
        ]),
      );
}

/// Delicate geometric Haute Joaillerie necklace & lotus filigree watermark fallback/underlay.
class _FiligreeWatermarkPainter extends CustomPainter {
  const _FiligreeWatermarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.5, size.height * 0.42);
    final maxR = math.min(size.width, size.height) * 0.62;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = Pal.goldBright.withValues(alpha: 0.08);

    for (final factor in const [0.32, 0.48, 0.66, 0.84, 1.0]) {
      canvas.drawCircle(center, maxR * factor, linePaint);
    }

    const petals = 16;
    for (var i = 0; i < petals; i++) {
      final a = (i * 2 * math.pi) / petals;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (maxR * 0.30);
      final p2 = center + Offset(math.cos(a), math.sin(a)) * maxR;
      canvas.drawLine(p1, p2, linePaint);

      final midA = a + (math.pi / petals);
      final ctrl = center + Offset(math.cos(midA), math.sin(midA)) * (maxR * 0.92);
      final nextP = center + Offset(math.cos(a + 2 * math.pi / petals), math.sin(a + 2 * math.pi / petals)) * (maxR * 0.66);
      final startP = center + Offset(math.cos(a), math.sin(a)) * (maxR * 0.66);
      final path = Path()
        ..moveTo(startP.dx, startP.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, nextP.dx, nextP.dy);
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
