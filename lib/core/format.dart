import 'package:decimal/decimal.dart';

/// High-precision string-first formatting for Indian Jewellery ERP.
/// Metal weights (6dp) and INR amounts (2dp) never pass through IEEE-754 double.

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
    v is String && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v.trim());

Decimal? tryDec(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return Decimal.tryParse(s);
}

Decimal decOrZero(Object? v) => tryDec(v) ?? Decimal.zero;

Decimal decDiv(Decimal numerator, Decimal denominator, {int scale = 12}) {
  if (denominator == Decimal.zero) return Decimal.zero;
  return (numerator / denominator).toDecimal(scaleOnInfinitePrecision: scale);
}

/// "237500.00" -> "₹2,37,500.00"
String inr(Object? v, {bool paise = true}) {
  var s = (v ?? '0').toString().trim();
  if (!looksNumeric(s)) return s.isEmpty ? (paise ? '₹0.00' : '₹0') : s;
  final d = Decimal.tryParse(s);
  if (d != null) {
    s = d.round(scale: 2).toStringAsFixed(2);
  }
  final neg = s.startsWith('-');
  if (neg) s = s.substring(1);
  final p = s.split('.');
  final frac = ('${p.length > 1 ? p[1] : ''}00').substring(0, 2);
  final whole = _groupIndian(p[0]);
  return '${neg ? '-' : ''}₹$whole${paise ? '.$frac' : ''}';
}

/// Compact Indian notation for executive KPI subtitles: "₹12.45 L", "₹1.20 Cr"
String inrCompact(Object? v) {
  final d = tryDec(v);
  if (d == null) return inr(v, paise: false);
  final abs = d.abs();
  final sign = d < Decimal.zero ? '-' : '';
  final crore = Decimal.fromInt(10000000);
  final lakh = Decimal.fromInt(100000);
  if (abs >= crore) {
    final cr = decDiv(abs, crore, scale: 4).round(scale: 2).toStringAsFixed(2);
    return '$sign₹$cr Cr';
  }
  if (abs >= lakh) {
    final lk = decDiv(abs, lakh, scale: 4).round(scale: 2).toStringAsFixed(2);
    return '$sign₹$lk L';
  }
  return inr(v, paise: false);
}

/// "34.520000" -> "34.520 g"
String grams(Object? v, {int dp = 3}) {
  final s = (v ?? '0').toString().trim();
  if (!looksNumeric(s)) return s.isEmpty ? '0.${'0' * dp} g' : s;
  final neg = s.startsWith('-');
  final clean = neg ? s.substring(1) : s;
  final p = clean.split('.');
  final frac = ('${p.length > 1 ? p[1] : ''}${'0' * dp}').substring(0, dp);
  return '${neg ? '-' : ''}${_groupIndian(p[0])}.$frac g';
}

/// Exact 6-decimal Fine 999 ledger weight: "29.696720" -> "29.696720 g" (or trims trailing zeros down to 3dp).
String fineGrams(Object? v, {bool fullPrecision = false}) {
  final s = (v ?? '0').toString().trim();
  if (!looksNumeric(s)) return s.isEmpty ? '0.000 g' : s;
  final d = Decimal.tryParse(s);
  if (d == null) return grams(s);
  final six = d.round(scale: 6).toStringAsFixed(6);
  if (fullPrecision) return '$six g';
  final parts = six.split('.');
  var frac = parts[1].replaceAll(RegExp(r'0+$'), '');
  if (frac.length < 3) frac = frac.padRight(3, '0');
  return '${_groupIndian(parts[0])}.$frac g';
}

/// Rate display, no paise when whole: "7850.00" -> "₹7,850"
String rate(Object? v) {
  final s = (v ?? '0').toString().trim();
  if (!looksNumeric(s)) return s;
  final d = Decimal.tryParse(s);
  final normalized = d != null ? d.round(scale: 2).toStringAsFixed(2) : s;
  final p = normalized.split('.');
  final frac = p.length > 1 ? p[1].replaceAll(RegExp(r'0+$'), '') : '';
  return frac.isEmpty ? inr(normalized, paise: false) : inr(normalized);
}

/// "3.000000" -> "3%" or "3.25%"
String pct(Object? v) {
  final s = (v ?? '0').toString().trim();
  if (!looksNumeric(s)) return s;
  final d = Decimal.tryParse(s);
  final fixed = d != null ? d.round(scale: 2).toStringAsFixed(2) : s;
  final parts = fixed.split('.');
  final frac = parts.length > 1 ? parts[1].replaceAll(RegExp(r'0+$'), '') : '';
  return frac.isEmpty ? '${parts[0]}%' : '${parts[0]}.$frac%';
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

/// Normalizes weight to 6 decimal places as required by API contracts.
String normWeight6(String s) {
  final d = Decimal.tryParse(s.trim());
  if (d == null) return '0.000000';
  return d.round(scale: 6).toStringAsFixed(6);
}

String humanize(String key) {
  final spaced = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAll('_', ' ')
      .replaceAll('-', ' ')
      .trim()
      .toLowerCase();
  if (spaced.isEmpty) return key;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// IN_VAULT -> "In vault"
String statusLabel(String s) => humanize(s.toLowerCase());

String clock(DateTime d) {
  final local = d.toLocal();
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final m = local.minute.toString().padLeft(2, '0');
  return '$h:$m ${local.hour >= 12 ? 'pm' : 'am'}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2026-10-30T08:15:00.000Z" or "2026-10-30" -> "30 Oct 2026"
String formatDate(Object? v) {
  if (v == null) return '-';
  final s = v.toString().trim();
  if (s.isEmpty) return '-';
  final parsed = DateTime.tryParse(s);
  if (parsed != null) {
    final d = s.contains('T') ? parsed.toLocal() : parsed;
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';
  }
  return s;
}

/// "2026-10-30T08:15:00.000Z" -> "30 Oct 2026 · 1:45 pm"
String formatDateTime(Object? v) {
  if (v == null) return '-';
  final s = v.toString().trim();
  if (s.isEmpty) return '-';
  final parsed = DateTime.tryParse(s);
  if (parsed != null) {
    final d = parsed.toLocal();
    return '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year} · ${clock(d)}';
  }
  return s;
}

/// Today's ISO calendar date YYYY-MM-DD in local time.
String todayIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

/// Start of current month YYYY-MM-01 in local time.
String monthStartIso() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-01';
}

Decimal dParse(Object? v) => decOrZero(v);

String dStr2(Decimal d) => d.round(scale: 2).toStringAsFixed(2);

String dStr6(Decimal d) => d.round(scale: 6).toStringAsFixed(6);

String fmtDate(Object? v) => formatDate(v);

String fmtDateTime(Object? v) => formatDateTime(v);

String shortId(Object? v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return '-';
  return s.length > 8 ? s.substring(0, 8) : s;
}
