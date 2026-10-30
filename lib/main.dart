import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/app_state.dart';
import 'core/rates.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/auth/context_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/billing/billing_controller.dart';
import 'features/shell/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (details) => Material(
        color: Pal.pearl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('This screen hit an error', style: T.display(22)),
                const SizedBox(height: 8),
                Text('Copy this text and send it, so it can be fixed.', style: T.body(14, color: Pal.muted)),
                const SizedBox(height: 14),
                SelectableText(details.exceptionAsString(), style: T.body(12.5, color: Pal.danger)),
              ]),
            ),
          ),
        ),
      );
  final prefs = await SharedPreferences.getInstance();
  final api = await ApiClient.create(
    prefs.getString('baseUrl_v2') ?? ApiClient.defaultBaseUrl(),
  );
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider(create: (_) => AppState(api, prefs)..bootstrap()),
        ChangeNotifierProvider(create: (_) => RatesController(api)),
        ChangeNotifierProvider(create: (_) => BillingController(api)),
      ],
      child: const JewelleryApp(),
    ),
  );
}

class JewelleryApp extends StatelessWidget {
  const JewelleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jewellery ERP',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const _Gate(),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppState, AuthStage>((s) => s.stage);
    final Widget child;
    switch (stage) {
      case AuthStage.booting:
        child = const _Splash(key: ValueKey('boot'));
        break;
      case AuthStage.loggedOut:
      case AuthStage.mfa:
        child = const LoginScreen(key: ValueKey('login'));
        break;
      case AuthStage.context:
        child = const ContextScreen(key: ValueKey('context'));
        break;
      case AuthStage.ready:
        child = const Shell(key: ValueKey('shell'));
        break;
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      child: child,
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Pal.ink,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(width: 72, height: 72, child: GemMark()),
          const SizedBox(height: 22),
          Text('Connecting to server...', style: T.body(14, color: Colors.white.withValues(alpha: 0.7), w: FontWeight.w600)),
        ]),
      ),
    );
  }
}
