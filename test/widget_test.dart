import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jewellery_erp/core/api.dart';
import 'package:jewellery_erp/core/app_state.dart';
import 'package:jewellery_erp/core/format.dart';
import 'package:jewellery_erp/features/more/more_screen.dart';
import 'package:jewellery_erp/main.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('Decimal string formatting preserves 6dp weights and 2dp Indian INR', () {
    expect(normWeight6('12.5'), '12.500000');
    expect(normAmount('237500'), '237500.00');
    expect(inr('237500.00'), '₹2,37,500.00');
    expect(fineGrams('29.696720', fullPrecision: true), '29.696720 g');
  });

  testWidgets('JewelleryErpApp boots cleanly into Royal Gold sign-in screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = ApiClient.inMemory();

    await tester.pumpWidget(JewelleryErpApp(api: api, prefs: prefs));
    await tester.pumpAndSettle(const Duration(seconds: 4));

    expect(find.text('Sign in to workspace'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Enterprise SaaS Suite renders all pos.hrpocket.in module groups cleanly', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = ApiClient.inMemory();
    final appState = AppState(api, prefs);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ApiClient>.value(value: api),
          ChangeNotifierProvider<AppState>.value(value: appState),
        ],
        child: const MaterialApp(home: MoreScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('More · All Modules'), findsOneWidget);
    expect(find.text('Jewellery ERP'), findsOneWidget);
    expect(find.text('SAAS'), findsOneWidget);
  });
}
