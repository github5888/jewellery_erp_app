import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_erp/core/format.dart';
import 'package:jewellery_erp/core/models.dart';
import 'package:jewellery_erp/core/showrooms.dart';

void main() {
  test('inr groups lakhs and crores, keeps strings exact without float drift', () {
    expect(inr('237500.00'), '₹2,37,500.00');
    expect(inr('95602.92'), '₹95,602.92');
    expect(inr('12345678.50'), '₹1,23,45,678.50');
    expect(inr('0'), '₹0.00');
    expect(inrCompact('1450000.00'), '₹14.50 L');
  });

  test('grams and fineGrams format 6-dp metal weights cleanly', () {
    expect(grams('34.520000'), '34.520 g');
    expect(grams('14'), '14.000 g');
    expect(fineGrams('13.465200'), '13.4652 g');
    expect(normWeight6('14.25'), '14.250000');
    expect(isValidWeight('14.250000'), true);
    expect(isValidWeight('-1'), false);
  });

  test('rate hides empty paise and preserves non-zero paise', () {
    expect(rate('7850.00'), '₹7,850');
    expect(rate('94.50'), '₹94.50');
  });

  test('amount validation, normalisation and Decimal division', () {
    expect(isValidAmount('500'), true);
    expect(isValidAmount('500.5'), true);
    expect(isValidAmount('500.555'), false);
    expect(isValidAmount('-1'), false);
    expect(normAmount('500'), '500.00');
    expect(normAmount('500.5'), '500.50');

    final perGram = decDiv(Decimal.parse('78500.00'), Decimal.parse('10.000000000000'))
        .round(scale: 2);
    expect(perGram.toStringAsFixed(2), '7850.00');
  });

  test('parseShowrooms handles production scopes[] and nested legalEntities[] shapes', () {
    final prodSession = {
      'scopes': [
        {
          'tenantId': 't1',
          'tenantName': 'Kalyan Jewellers',
          'tenantSlug': 'kalyan-jewellers',
          'legalEntityId': 'le1',
          'legalEntityName': 'Kalyan Jewellers India Ltd',
          'currency': 'INR',
          'timezone': 'Asia/Kolkata',
          'branches': [
            {'id': 'b1', 'code': 'MUM-01', 'name': 'Mumbai Flagship'},
            {'id': 'b2', 'code': 'DEL-01', 'name': 'South Ex Showroom'},
          ],
        }
      ]
    };
    final options = parseShowrooms(prodSession);
    expect(options.length, 2);
    expect(options.first.tenantName, 'Kalyan Jewellers');
    expect(options.first.branchCode, 'MUM-01');
    expect(options.first.currency, 'INR');
  });

  test('Article.fromJson parses nested inventory workspace shape and stone weight', () {
    final art = Article.fromJson({
      'id': 'a-1',
      'tag': 'JWL-2026-B001',
      'description': '22K Temple Choker',
      'grossWeightGrams': '34.520000',
      'fineWeightGrams': '29.788320',
      'components': [
        {
          'metal': {'code': 'GOLD'},
          'purityGrade': {'code': '22K', 'fineness': '0.916000'},
          'componentWeightGrams': '32.520000',
        }
      ],
      'balance': {
        'availability': 'AVAILABLE',
        'version': 2,
        'location': {'id': 'loc-1', 'name': 'Main Vault'},
      },
      'valuationLayers': [
        {'remainingCost': '237500.00'}
      ],
    });
    expect(art.barcode, 'JWL-2026-B001');
    expect(art.effectiveNetWeight, '32.520000');
    expect(art.stoneWeight, '2.000000');
    expect(art.purity, '916');
    expect(art.balanceVersion, 2);
    expect(art.carryingCost, '237500.00');
  });

  test('Party.fromJson parses contacts, roles and GSTIN registrations', () {
    final p = Party.fromJson({
      'id': 'p-1',
      'code': 'CUST-0001',
      'displayName': 'Ananya Verma',
      'kind': 'INDIVIDUAL',
      'roles': [
        {'role': 'CUSTOMER'}
      ],
      'contacts': [
        {'kind': 'PHONE', 'value': '+919876543210', 'isPrimary': true}
      ],
      'taxRegistrations': [
        {'registrationType': 'GSTIN', 'registrationNumber': '27AAACB1234F1Z5'}
      ],
    });
    expect(p.name, 'Ananya Verma');
    expect(p.phone, '+919876543210');
    expect(p.gstin, '27AAACB1234F1Z5');
    expect(p.primaryRoleLabel, 'Customer');
  });
}
