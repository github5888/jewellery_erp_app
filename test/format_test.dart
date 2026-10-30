import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_erp/core/format.dart';

void main() {
  test('inr groups lakhs and crores, keeps strings exact', () {
    expect(inr('237500.00'), '₹2,37,500.00');
    expect(inr('95602.92'), '₹95,602.92');
    expect(inr('12345678.50'), '₹1,23,45,678.50');
    expect(inr('0'), '₹0.00');
  });

  test('grams trims to 3 dp for display without rounding through double', () {
    expect(grams('34.520000'), '34.520 g');
    expect(grams('14'), '14.000 g');
  });

  test('rate hides empty paise', () {
    expect(rate('7850.00'), '₹7,850');
    expect(rate('94.50'), '₹94.50');
  });

  test('amount validation and normalisation', () {
    expect(isValidAmount('500'), true);
    expect(isValidAmount('500.5'), true);
    expect(isValidAmount('500.555'), false);
    expect(isValidAmount('-1'), false);
    expect(normAmount('500'), '500.00');
    expect(normAmount('500.5'), '500.50');
  });
}
