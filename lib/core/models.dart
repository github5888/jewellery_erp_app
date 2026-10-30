import 'api.dart';

class MetalRate {
  MetalRate({
    required this.metal,
    required this.purity,
    required this.carat,
    required this.sell,
    required this.buy,
  });
  final String metal, purity, carat, sell, buy;

  factory MetalRate.fromJson(Map<String, dynamic> j) => MetalRate(
        metal: '${j['metal'] ?? ''}',
        purity: '${j['purity'] ?? ''}',
        carat: '${j['carat'] ?? ''}',
        sell: '${j['sellRatePerGram'] ?? '0.00'}',
        buy: '${j['buyRatePerGram'] ?? '0.00'}',
      );
}

class Article {
  Article(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['articleId'] ?? raw['id'] ?? ''}';
  String get barcode => '${raw['barcode'] ?? raw['tag'] ?? ''}';
  String get name => '${raw['name'] ?? raw['description'] ?? 'Unnamed piece'}';
  String get metal => '${raw['metal'] ?? ''}';
  String get purity => '${raw['purity'] ?? ''}';
  String get gross => '${raw['grossWeightGrams'] ?? '0'}';
  String get stone => '${raw['stoneWeightGrams'] ?? raw['componentWeightGrams'] ?? '0'}';
  String get net => '${raw['netMetalWeightGrams'] ?? '0'}';
  String get makingType => '${raw['makingChargesType'] ?? ''}';
  String get makingRate => '${raw['makingRate'] ?? '0'}';
  String get status => '${raw['status'] ?? raw['availability'] ?? raw['state'] ?? ''}';
  String get location => '${raw['vaultLocation'] ?? ''}';

  bool get sellable => status.isEmpty || const ['IN_VAULT', 'IN_STOCK', 'AVAILABLE', 'ACTIVE'].contains(status);
}

class Party {
  Party(this.raw);
  final Map<String, dynamic> raw;
  String get id => '${raw['id'] ?? raw['partyId'] ?? ''}';
  String get name =>
      '${raw['displayName'] ?? raw['name'] ?? raw['fullName'] ?? 'Customer'}';
  String get phone {
    final d = raw['phone'] ?? raw['mobile'] ?? raw['phoneNumber'];
    if (d != null) return '$d';
    final c = raw['contacts'];
    if (c is List) {
      for (final x in c) {
        if (x is Map && '${x['kind']}'.toUpperCase() == 'PHONE') return '${x['value'] ?? x['contact'] ?? ''}';
      }
    }
    return '';
  }
  String get pan => '${raw['pan'] ?? raw['panNumber'] ?? ''}';
  String get gstin => '${raw['gstin'] ?? raw['gstNumber'] ?? ''}';

  bool matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return name.toLowerCase().contains(s) || phone.contains(s);
  }

  static List<Party> listFrom(dynamic d) => asList(d).map(Party.new).toList();
}
