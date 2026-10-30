import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:jewellery_erp/core/api.dart';
import 'package:jewellery_erp/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('JewelleryErpApp boots cleanly into enterprise sign-in screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final api = ApiClient.inMemory();

    await tester.pumpWidget(JewelleryErpApp(api: api, prefs: prefs));
    await tester.pumpAndSettle(const Duration(seconds: 4));

    expect(find.text('Sign in to workspace'), findsOneWidget);
    expect(find.text('Kalyan Store Fill'), findsOneWidget);
  });
}
