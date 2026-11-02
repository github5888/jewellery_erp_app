import 'package:decimal/decimal.dart';

import 'api.dart';
import 'format.dart';

class MetalRate {
  MetalRate({
    required this.metal,
    required this.metalName,
    required this.purity,
    required this.carat,
    required this.fineness,
    required this.sell,
    required this.buy,
    this.metalId,
    this.purityGradeId,
    this.rateVersionId,
  });

  final String metal;
  final String metalName;
  final String purity;
  final String carat;
  final String fineness;
  final String sell;
  final String buy;
  final String? metalId;
  final String? purityGradeId;
  final String? rateVersionId;

  String get karatLabel => carat.isEmpty ? purity : carat;

  String get sellPer10g {
    final d = tryDec(sell);
    if (d == null) return sell;
    return (d * Decimal.fromInt(10)).round(scale: 2).toStringAsFixed(2);
  }

  String get buyPer10g {
    final d = tryDec(buy);
    if (d == null) return buy;
    return (d * Decimal.fromInt(10)).round(scale: 2).toStringAsFixed(2);
  }

  String get sellPerTenGram => sellPer10g;
  String get buyPerTenGram => buyPer10g;

  factory MetalRate.fromJson(Map<String, dynamic> j) {
    final metalCode = '${j['metal'] ?? j['metalCode'] ?? 'GOLD'}'.toUpperCase();
    final pur = '${j['purity'] ?? j['purityCode'] ?? '999'}';
    final defaultCarat = metalCode == 'SILVER'
        ? (pur == '925' ? 'Sterling 925' : 'Fine Silver')
        : (pur == '999'
            ? '24K'
            : pur == '916'
                ? '22K'
                : pur == '750'
                    ? '18K'
                    : pur);
    return MetalRate(
      metal: metalCode,
      metalName: humanize(metalCode),
      purity: pur,
      carat: '${j['carat'] ?? j['displayKarat'] ?? defaultCarat}',
      fineness: '${j['finenessPerThousand'] ?? pur}',
      sell: '${j['sellRatePerGram'] ?? j['sell'] ?? '0.00'}',
      buy: '${j['buyRatePerGram'] ?? j['buy'] ?? '0.00'}',
      metalId: j['metalId']?.toString(),
      purityGradeId: j['purityGradeId']?.toString(),
      rateVersionId: j['rateVersionId']?.toString(),
    );
  }
}

class Article {
  Article(this.raw);
  factory Article.fromJson(Map<String, dynamic> j) => Article(j);

  final Map<String, dynamic> raw;

  Map<String, dynamic>? get _firstComp {
    final c = raw['components'];
    if (c is List && c.isNotEmpty && c.first is Map) {
      return Map<String, dynamic>.from(c.first as Map);
    }
    return null;
  }

  Map<String, dynamic>? get _balance =>
      raw['balance'] is Map ? Map<String, dynamic>.from(raw['balance'] as Map) : null;

  Map<String, dynamic>? get _location {
    final b = _balance;
    if (b != null && b['location'] is Map) {
      return Map<String, dynamic>.from(b['location'] as Map);
    }
    if (raw['location'] is Map) {
      return Map<String, dynamic>.from(raw['location'] as Map);
    }
    return null;
  }

  Map<String, dynamic>? get _firstValuation {
    final v = raw['valuationLayers'];
    if (v is List && v.isNotEmpty && v.first is Map) {
      return Map<String, dynamic>.from(v.first as Map);
    }
    return null;
  }

  String get id => '${raw['articleId'] ?? raw['id'] ?? ''}';
  String get barcode => '${raw['barcode'] ?? raw['tag'] ?? raw['tagNumber'] ?? ''}';
  String get name => '${raw['name'] ?? raw['description'] ?? 'Tagged Jewellery Piece'}';

  String get metal {
    final direct = '${raw['metal'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct.toUpperCase();
    final comp = _firstComp;
    if (comp != null && comp['metal'] is Map) {
      return '${(comp['metal'] as Map)['code'] ?? (comp['metal'] as Map)['name'] ?? 'GOLD'}'.toUpperCase();
    }
    return 'GOLD';
  }

  /// Canonical parts-per-thousand purity string (`"916"`, `"999"`, `"750"`, `"925"`).
  String get purity {
    final direct = '${raw['purity'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final comp = _firstComp;
    if (comp != null && comp['purityGrade'] is Map) {
      final pg = comp['purityGrade'] as Map;
      final fn = tryDec(pg['fineness'] ?? pg['finenessPerThousand']);
      if (fn != null && fn > Decimal.zero) {
        if (fn <= Decimal.one) {
          return (fn * Decimal.fromInt(1000)).round().toString();
        }
        return fn.round().toString();
      }
      final code = '${pg['code'] ?? ''}'.trim().toUpperCase();
      if (code == '24K') return '999';
      if (code == '22K') return '916';
      if (code == '18K') return '750';
      if (code == '14K') return '585';
      if (code.isNotEmpty) return code;
    }
    return '916';
  }

  String get karatLabel {
    final comp = _firstComp;
    if (comp != null && comp['purityGrade'] is Map) {
      final pg = comp['purityGrade'] as Map;
      final k = '${pg['displayKarat'] ?? pg['code'] ?? ''}'.trim();
      if (k.isNotEmpty) return k;
    }
    return switch (purity) {
      '999' => metal == 'SILVER' ? 'Fine 999' : '24K',
      '916' => '22K',
      '750' => '18K',
      '585' => '14K',
      '925' => 'Sterling 925',
      _ => purity,
    };
  }

  String get purityCode => purity;

  String get fineness {
    final comp = _firstComp;
    if (comp != null && comp['finenessPerThousand'] != null) {
      return '${comp['finenessPerThousand']}';
    }
    if (tryDec(purity) != null) return purity;
    return '916';
  }

  String get gross => '${raw['grossWeightGrams'] ?? '0.000000'}';
  String get grossWeight => gross;

  String get net {
    if (raw['netMetalWeightGrams'] != null) return '${raw['netMetalWeightGrams']}';
    if (raw['componentWeightGrams'] != null) return '${raw['componentWeightGrams']}';
    final comp = _firstComp;
    if (comp != null && comp['componentWeightGrams'] != null) {
      return '${comp['componentWeightGrams']}';
    }
    if (comp != null && comp['weightGrams'] != null) {
      return '${comp['weightGrams']}';
    }
    return gross;
  }

  String get effectiveNetWeight => net;

  String get stone {
    if (raw['stoneWeightGrams'] != null) return '${raw['stoneWeightGrams']}';
    final g = tryDec(gross);
    final n = tryDec(net);
    if (g != null && n != null && g >= n) {
      return (g - n).round(scale: 6).toStringAsFixed(6);
    }
    return '0.000000';
  }

  String get stoneWeight => stone;

  String get fine {
    if (raw['fineWeightGrams'] != null) return '${raw['fineWeightGrams']}';
    final n = tryDec(net);
    final f = tryDec(fineness);
    if (n != null && f != null) {
      return (n * f * Decimal.parse('0.001')).round(scale: 6).toStringAsFixed(6);
    }
    return '0.000000';
  }

  String get fineWeight => fine;

  String get makingType => '${raw['makingChargesType'] ?? 'PER_GRAM'}';
  String get makingRate => '${raw['makingCharges'] ?? raw['makingRate'] ?? '0.00'}';
  String get makingCharges => makingRate;

  String get carryingCost {
    if (raw['costAmount'] != null) return '${raw['costAmount']}';
    final v = _firstValuation;
    if (v != null) return '${v['remainingCost'] ?? v['acquiredCost'] ?? ''}';
    return '';
  }

  String get status {
    final b = _balance;
    if (b != null && b['availability'] != null) return '${b['availability']}';
    return '${raw['status'] ?? raw['availability'] ?? raw['state'] ?? 'AVAILABLE'}';
  }

  int get balanceVersion {
    final b = _balance;
    if (b != null && b['version'] is int) return b['version'] as int;
    return 1;
  }

  String get locationId => '${_location?['id'] ?? raw['locationId'] ?? ''}';

  String get location {
    final direct = '${raw['vaultLocation'] ?? raw['locationName'] ?? ''}'.trim();
    if (direct.isNotEmpty) return direct;
    final loc = _location;
    if (loc != null) {
      final code = '${loc['code'] ?? ''}'.trim();
      final nm = '${loc['name'] ?? ''}'.trim();
      if (code.isNotEmpty && nm.isNotEmpty) return '$code · $nm';
      return nm.isNotEmpty ? nm : code;
    }
    return '';
  }

  String get locationName => location;
  String get locationType => '${_location?['type'] ?? ''}';

  bool get sellable =>
      status.isEmpty ||
      const ['IN_VAULT', 'IN_STOCK', 'AVAILABLE', 'ACTIVE'].contains(status.toUpperCase());

  bool get isAvailable => sellable;

  bool matches(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return barcode.toLowerCase().contains(s) ||
        name.toLowerCase().contains(s) ||
        metal.toLowerCase().contains(s) ||
        purity.toLowerCase().contains(s) ||
        location.toLowerCase().contains(s);
  }
}

class MaterialLotItem {
  MaterialLotItem(this.raw);
  factory MaterialLotItem.fromJson(Map<String, dynamic> j) => MaterialLotItem(j);

  final Map<String, dynamic> raw;

  String get id => '${raw['id'] ?? ''}';
  String get lotCode => '${raw['lotCode'] ?? ''}';
  String get description => '${raw['description'] ?? ''}';
  String get metalCode =>
      raw['metal'] is Map ? '${(raw['metal'] as Map)['code'] ?? ''}' : '${raw['metalCode'] ?? 'GOLD'}';
  String get metalName =>
      raw['metal'] is Map ? '${(raw['metal'] as Map)['name'] ?? ''}' : humanize(metalCode);
  String get metal => metalName;
  String get purityCode =>
      raw['purityGrade'] is Map ? '${(raw['purityGrade'] as Map)['code'] ?? ''}' : '${raw['fineness'] ?? ''}';
  String get purityLabel => purityCode;
  String get form => '${raw['form'] ?? 'BULLION'}';
  String get fineness => '${raw['finenessPerThousand'] ?? raw['fineness'] ?? ''}';

  String get totalGrams {
    if (raw['quantityGrams'] != null) return '${raw['quantityGrams']}';
    final b = raw['balances'];
    if (b is List && b.isNotEmpty) {
      var sum = Decimal.zero;
      for (final x in b) {
        if (x is Map) sum += decOrZero(x['quantityGrams']);
      }
      return sum.toStringAsFixed(6);
    }
    return '${raw['acquiredWeightGrams'] ?? '0.000000'}';
  }

  String get quantityGrams => totalGrams;

  String get fineWeightGrams {
    if (raw['fineWeightGrams'] != null) return '${raw['fineWeightGrams']}';
    final b = raw['balances'];
    if (b is List && b.isNotEmpty) {
      var sum = Decimal.zero;
      for (final x in b) {
        if (x is Map) sum += decOrZero(x['fineWeightGrams']);
      }
      return sum.toStringAsFixed(6);
    }
    return '${raw['acquiredFineWeightGrams'] ?? '0.000000'}';
  }

  String get fineGrams => fineWeightGrams;

  String get locationLabel {
    final b = raw['balances'];
    if (b is List && b.isNotEmpty && b.first is Map) {
      final loc = (b.first as Map)['location'];
      if (loc is Map) return '${loc['name'] ?? loc['code'] ?? ''}';
    }
    return '';
  }

  String get locationName => locationLabel;

  String get remainingCost {
    if (raw['costAmount'] != null) return '${raw['costAmount']}';
    final v = raw['valuationLayers'];
    if (v is List && v.isNotEmpty && v.first is Map) {
      return '${(v.first as Map)['remainingCost'] ?? ''}';
    }
    return '';
  }
}

class StockLocationItem {
  StockLocationItem(this.raw);
  factory StockLocationItem.fromJson(Map<String, dynamic> j) => StockLocationItem(j);

  final Map<String, dynamic> raw;

  String get id => '${raw['id'] ?? ''}';
  String get code => '${raw['code'] ?? ''}';
  String get name => '${raw['name'] ?? ''}';
  String get type => '${raw['type'] ?? 'VAULT'}';
  String get state => '${raw['state'] ?? 'ACTIVE'}';
}

class ReservationItem {
  ReservationItem(this.raw);
  factory ReservationItem.fromJson(Map<String, dynamic> j) => ReservationItem(j);

  final Map<String, dynamic> raw;

  String get id => '${raw['id'] ?? ''}';
  String get articleId => '${raw['articleId'] ?? ''}';
  String get articleTag =>
      raw['article'] is Map ? '${(raw['article'] as Map)['tag'] ?? ''}' : '${raw['tag'] ?? ''}';
  String get state => '${raw['state'] ?? raw['status'] ?? 'ACTIVE'}';
  String get referenceType => '${raw['referenceType'] ?? 'HOLD'}';
  String get expiresAt => '${raw['expiresAt'] ?? ''}';
  int get version => raw['version'] is int ? raw['version'] as int : 1;
}

class Party {
  Party(this.raw);
  factory Party.fromJson(Map<String, dynamic> j) => Party(j);

  final Map<String, dynamic> raw;

  String get id => '${raw['id'] ?? raw['partyId'] ?? ''}';
  String get code => '${raw['code'] ?? ''}';
  String get kind => '${raw['kind'] ?? 'INDIVIDUAL'}';
  String get name =>
      '${raw['displayName'] ?? raw['name'] ?? raw['legalName'] ?? raw['fullName'] ?? 'Customer'}';
  String get legalName => '${raw['legalName'] ?? ''}';

  List<String> get roles {
    final r = raw['roles'];
    if (r is List) {
      return r
          .map((e) => e is Map ? '${e['role'] ?? ''}' : '$e')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const ['CUSTOMER'];
  }

  String get primaryRole => roles.isNotEmpty ? roles.first : 'CUSTOMER';
  String get primaryRoleLabel => humanize(primaryRole);

  String get phone {
    final d = raw['phone'] ?? raw['mobile'] ?? raw['phoneNumber'];
    if (d != null && '$d'.isNotEmpty) return '$d';
    final c = raw['contacts'];
    if (c is List) {
      for (final x in c) {
        if (x is Map) {
          final k = '${x['kind']}'.toUpperCase();
          if (k == 'PHONE' || k == 'WHATSAPP') {
            return '${x['value'] ?? x['contact'] ?? ''}';
          }
        }
      }
    }
    return '';
  }

  String get email {
    final d = raw['email'];
    if (d != null && '$d'.isNotEmpty) return '$d';
    final c = raw['contacts'];
    if (c is List) {
      for (final x in c) {
        if (x is Map && '${x['kind']}'.toUpperCase() == 'EMAIL') {
          return '${x['value'] ?? ''}';
        }
      }
    }
    return '';
  }

  String get pan => '${raw['pan'] ?? raw['panNumber'] ?? ''}';

  String get gstin {
    final d = raw['gstin'] ?? raw['gstNumber'];
    if (d != null && '$d'.isNotEmpty) return '$d';
    final t = raw['taxRegistrations'];
    if (t is List && t.isNotEmpty && t.first is Map) {
      return '${(t.first as Map)['registrationNumber'] ?? ''}';
    }
    return '';
  }

  String get city {
    final a = raw['addresses'];
    if (a is List && a.isNotEmpty && a.first is Map) {
      final addr = a.first as Map;
      return [addr['city'], addr['postalCode']]
          .where((x) => x != null && '$x'.isNotEmpty)
          .join(' - ');
    }
    return '';
  }

  String get creditLimit {
    final cp = raw['creditPolicies'];
    if (cp is List && cp.isNotEmpty && cp.first is Map) {
      return '${(cp.first as Map)['limitAmount'] ?? ''}';
    }
    return '';
  }

  bool matches(String q, {String? roleFilter}) {
    if (roleFilter != null && roleFilter.isNotEmpty && roleFilter != 'ALL') {
      if (!roles.any((r) => r.toUpperCase() == roleFilter.toUpperCase())) {
        return false;
      }
    }
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return true;
    return name.toLowerCase().contains(s) ||
        code.toLowerCase().contains(s) ||
        phone.toLowerCase().contains(s) ||
        gstin.toLowerCase().contains(s);
  }

  static List<Party> listFrom(dynamic d) =>
      asList(d, keys: const ['parties', 'items', 'rows']).map(Party.new).toList();
}
