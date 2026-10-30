import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/app_state.dart';
import 'core/build.dart';
import 'core/rates.dart';
import 'core/theme.dart';
import 'core/widgets.dart';
import 'features/auth/context_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/billing/billing_controller.dart';
import 'features/shell/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  final prefs = await SharedPreferences.getInstance();
  // Uses `baseUrl_v3` so legacy broken `localhost:3000` preferences automatically
  // upgrade to the live production gateway `https://pos.hrpocket.in/api/v1`.
  final savedUrl = prefs.getString('baseUrl_v3');
  final api = await ApiClient.create(
    (savedUrl == null || savedUrl.trim().isEmpty) ? kProductionApiUrl : savedUrl,
  );
  runApp(JewelleryErpApp(api: api, prefs: prefs));
}

class JewelleryErpApp extends StatelessWidget {
  const JewelleryErpApp({super.key, required this.api, required this.prefs});
  final ApiClient api;
  final SharedPreferences prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: api),
        ChangeNotifierProvider(create: (_) => AppState(api, prefs)..bootstrap()),
        ChangeNotifierProvider(create: (_) => RatesController(api)),
        ChangeNotifierProxyProvider<RatesController, BillingController>(
          create: (ctx) => BillingController(api, ctx.read<RatesController>()),
          update: (_, rates, prev) => prev ?? BillingController(api, rates),
        ),
      ],
      child: MaterialApp(
        title: 'Jewellery ERP',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final stage = context.select<AppState, AuthStage>((s) => s.stage);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: switch (stage) {
        AuthStage.booting => const Scaffold(
            key: ValueKey('boot'),
            backgroundColor: Pal.obsidian,
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                GemMark(size: 54, darkSurface: true),
                SizedBox(height: 18),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Pal.goldSoft),
                ),
              ]),
            ),
          ),
        AuthStage.loggedOut || AuthStage.mfa => const LoginScreen(key: ValueKey('login')),
        AuthStage.context => const ContextScreen(key: ValueKey('ctx')),
        AuthStage.ready => const Shell(key: ValueKey('shell')),
      },
    );
  }
}
