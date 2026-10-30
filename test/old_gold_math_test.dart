import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the sample voucher in the API guide:
// 15 g gross, 0.3 g loss, 916 purity, Rs 7100/g -> 13.4652 g pure, Rs 95,602.92
void main() {
  test('voucher maths matches the handoff sample exactly', () {
    final g = Decimal.parse('15.000000');
    final w = Decimal.parse('0.300000');
    final fineness = Decimal.parse('916') * Decimal.parse('0.001');
    final netPure = ((g - w) * fineness).round(scale: 6);
    final total = (netPure * Decimal.parse('7100.00')).round(scale: 2);
    expect(netPure.toStringAsFixed(6), '13.465200');
    expect(total.toStringAsFixed(2), '95602.92');
  });
}
