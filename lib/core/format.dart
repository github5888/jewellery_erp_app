/// String-only formatting. Weights and money stay decimal STRINGS end to end
/// (API contract: never parse into double).

String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

bool looksNumeric(Object? v) =>
    v is String && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v);

/// "237500.00" -> "₹2,37,500.00"
String inr(Object? v, {bool paise = true}) {
  var s = (v ?? '0').toString();
  if (!looksNumeric(s)) return s.isEmpty ? '₹0.00' : s;
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final p = s.split('.');
  final frac = ('${p.length > 1 ? p[1] : ''}00').substring(0, 2);
  final whole = _groupIndian(p[0]);
  return '${neg ? '-' : ''}₹$whole${paise ? '.$frac' : ''}';
}

/// "34.520000" -> "34.520 g"
String grams(Object? v, {int dp = 3}) {
  final s = (v ?? '0').toString();
  if (!looksNumeric(s)) return s;
  final p = s.split('.');
  final frac = ('${p.length > 1 ? p[1] : ''}${'0' * dp}').substring(0, dp);
  return '${p[0]}.$frac g';
}

/// Rate display, no paise when whole: "7850.00" -> "₹7,850"
String rate(Object? v) {
  final s = (v ?? '0').toString();
  if (!looksNumeric(s)) return s;
  final p = s.split('.');
  final frac = p.length > 1 ? p[1].replaceAll(RegExp(r'0+$'), '') : '';
  return frac.isEmpty ? inr(s, paise: false) : inr(s);
}

final _amountRe = RegExp(r'^\d{1,12}(\.\d{1,2})?$');
bool isValidAmount(String s) => _amountRe.hasMatch(s.trim());

/// "500" -> "500.00"
String normAmount(String s) {
  final t = s.trim();
  final p = t.split('.');
  final frac = ('${p.length > 1 ? p[1] : ''}00').substring(0, 2);
  return '${p[0]}.$frac';
}

final _weightRe = RegExp(r'^\d{1,6}(\.\d{1,6})?$');
bool isValidWeight(String s) => _weightRe.hasMatch(s.trim());

String humanize(String key) {
  final spaced = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .trim()
      .toLowerCase();
  if (spaced.isEmpty) return key;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// IN_VAULT -> "In vault"
String statusLabel(String s) => humanize(s.toLowerCase());

String clock(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour >= 12 ? 'pm' : 'am'}';
}
