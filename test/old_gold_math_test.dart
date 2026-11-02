import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_erp/core/format.dart';

// Mirrors the sample voucher in the API guide AND RateBook 10g->1g conversion:
// 15 g gross, 0.3 g loss, 916 purity, Rs 7100/g -> 13.465200 g pure, Rs 95,602.92
void main() {
  test('old-gold voucher maths matches the handoff sample to 6-dp weight & 2-dp INR', () {
    final g = Decimal.parse('15.000000');
    final w = Decimal.parse('0.300000');
    final fineness = Decimal.parse('916') * Decimal.parse('0.001');
    final netPure = ((g - w) * fineness).round(scale: 6);
    final total = (netPure * Decimal.parse('7100.00')).round(scale: 2);
    expect(netPure.toStringAsFixed(6), '13.465200');
    expect(total.toStringAsFixed(2), '95602.92');
  });

  test('24K 10g rate converts to 22K 916 1g rate matching packages/domain/src/decimal.ts', () {
    final ratePer10g = Decimal.parse('78500.00');
    final baseFactor = Decimal.parse('10.000000000000');
    final itemFineness = Decimal.parse('0.916000');
    final refFineness = Decimal.parse('0.999000');

    final perGram24k = decDiv(ratePer10g, baseFactor);
    final ratio = decDiv(itemFineness, refFineness);
    final perGram22k = (perGram24k * ratio).round(scale: 2);

    expect(perGram24k.round(scale: 2).toStringAsFixed(2), '7850.00');
    expect(perGram22k.toStringAsFixed(2), '7197.80');
  });
}
