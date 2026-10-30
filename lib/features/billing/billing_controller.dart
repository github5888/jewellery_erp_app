import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';

class ExchangeCredit {
  const ExchangeCredit({
    required this.voucherId,
    required this.label,
    required this.amount,
    this.fineWeight = '',
  });

  final String voucherId;
  final String label;
  final String amount;
  final String fineWeight;

  String get id => voucherId;
  String get credit => amount;
}

class CartLine {
  CartLine({
    required this.article,
    required this.ratePerGram,
    required this.makingCharge,
    this.reservationId,
    this.reservationVersion,
  });

  final Article article;
  final String ratePerGram;
  String makingCharge;
  final String? reservationId;
  final int? reservationVersion;

  Decimal get metalValue {
    final wt = decOrZero(article.effectiveNetWeight);
    final r = decOrZero(ratePerGram);
    if (r > Decimal.zero && wt > Decimal.zero) {
      return (wt * r).round(scale: 2);
    }
    if (decOrZero(article.carryingCost) > Decimal.zero) {
      return decOrZero(article.carryingCost).round(scale: 2);
    }
    return Decimal.zero;
  }

  Decimal get makingValue => decOrZero(makingCharge).round(scale: 2);

  Decimal get taxableAmount => (metalValue + makingValue).round(scale: 2);

  /// Standard 3% Indian GST on gold/silver jewellery (1.5% CGST + 1.5% SGST).
  Decimal get gstAmount => (taxableAmount * Decimal.parse('0.03')).round(scale: 2);

  Decimal get lineTotal => (taxableAmount + gstAmount).round(scale: 2);
}

class PayEntry {
  const PayEntry(this.mode, this.amount, {this.reference = ''});
  final String mode;
  final String amount;
  final String reference;
}

class BillingController extends ChangeNotifier {
  BillingController(this._api, this._rates);
  final ApiClient _api;
  final RatesController _rates;
  static const _uuid = Uuid();

  Party? customer;
  final List<CartLine> lines = [];
  final List<PayEntry> payments = [];
  ExchangeCredit? oldGold;
  bool busy = false;
  String? error;

  void setCustomer(Party? p) {
    customer = p;
    notifyListeners();
  }

  void setOldGold(ExchangeCredit? v) {
    oldGold = v;
    notifyListeners();
  }

  void addExchange(ExchangeCredit v) => setOldGold(v);

  String _resolveRateForArticle(Article art) {
    final m = _rates.find(art.metal, art.purity.isEmpty ? '916' : art.purity) ??
        _rates.find(art.metal, '999');
    if (m != null && decOrZero(m.sell) > Decimal.zero) {
      return m.sell;
    }
    return '0.00';
  }

  String _defaultMakingForArticle(Article art, String ratePerGram) {
    if (decOrZero(art.makingCharges) > Decimal.zero) {
      return normAmount(art.makingCharges);
    }
    final wt = decOrZero(art.effectiveNetWeight);
    final r = decOrZero(ratePerGram);
    if (wt > Decimal.zero && r > Decimal.zero) {
      return (wt * r * Decimal.parse('0.12')).round(scale: 2).toStringAsFixed(2);
    }
    return '0.00';
  }

  /// Adds an [Article] to the POS cart, attempting a 15-minute counter reservation when supported.
  Future<bool> addArticle(Article art) async {
    final code = art.barcode.trim().toUpperCase();
    if (lines.any((l) =>
        l.article.barcode.toUpperCase() == code ||
        (art.id.isNotEmpty && l.article.id == art.id))) {
      error = '${art.barcode} is already in the current bill.';
      notifyListeners();
      return false;
    }
    if (art.status.toUpperCase() == 'SOLD' || art.status.toUpperCase() == 'DISPATCHED') {
      error = '${art.barcode} has already been sold.';
      notifyListeners();
      return false;
    }

    busy = true;
    error = null;
    notifyListeners();

    String? reservationId;
    int? reservationVersion;
    if (art.id.isNotEmpty && art.isAvailable) {
      try {
        final exp = DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String();
        final r = asMap(await _api.post(
          '/inventory/articles/${art.id}/reserve',
          idempotencyKey: _uuid.v4(),
          body: {
            'expectedBalanceVersion': art.balanceVersion,
            'referenceType': 'POS_BILL',
            'referenceId': _uuid.v4(),
            'expiresAt': exp,
            'reason': 'POS counter checkout hold for ${art.barcode}',
          },
        ));
        reservationId = (r['reservationId'] ?? r['id'])?.toString();
        reservationVersion = int.tryParse('${r['version'] ?? 1}') ?? 1;
      } catch (_) {
        // Non-blocking fallback when cashier session does not hold MFA reserve permission
      }
    }

    final ratePg = _resolveRateForArticle(art);
    final making = _defaultMakingForArticle(art, ratePg);
    lines.add(CartLine(
      article: art,
      ratePerGram: ratePg,
      makingCharge: making,
      reservationId: reservationId,
      reservationVersion: reservationVersion,
    ));
    busy = false;
    notifyListeners();
    return true;
  }

  Future<void> scanAndAdd(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) return;
    if (lines.any((l) => l.article.barcode.toUpperCase() == code)) {
      error = '$code is already in the current bill.';
      notifyListeners();
      return;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final d = await _api.get('/inventory', query: {'barcode': code});
      Article? found;
      if (d is Map && d['articles'] is List) {
        final all = asList(d, keys: const ['articles']).map(Article.fromJson).toList();
        for (final a in all) {
          if (a.barcode.toUpperCase() == code) {
            found = a;
            break;
          }
        }
      } else {
        final m = asMap(d);
        if (m.isNotEmpty && (m['barcode'] != null || m['tag'] != null || m['articleId'] != null)) {
          found = Article.fromJson(m);
        } else {
          final list = asList(d).map(Article.fromJson).toList();
          for (final a in list) {
            if (a.barcode.toUpperCase() == code) {
              found = a;
              break;
            }
          }
        }
      }

      if (found == null || found.barcode.isEmpty) {
        error = 'Tag "$code" was not found in active showroom stock.';
        busy = false;
        notifyListeners();
        return;
      }
      busy = false;
      await addArticle(found);
    } on ApiException catch (e) {
      error = e.message;
      busy = false;
      notifyListeners();
    }
  }

  void updateMakingCharge(int index, String amount) {
    if (index < 0 || index >= lines.length) return;
    lines[index].makingCharge = normAmount(amount);
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    final line = lines.removeAt(index);
    notifyListeners();
    await _releaseIfHeld(line);
  }

  Future<void> _releaseIfHeld(CartLine line) async {
    final resId = line.reservationId;
    if (resId == null || resId.isEmpty) return;
    try {
      await _api.post(
        '/inventory/reservations/$resId/release',
        idempotencyKey: _uuid.v4(),
        body: {
          'expectedReservationVersion': line.reservationVersion ?? 1,
          'expectedBalanceVersion': line.article.balanceVersion + 1,
          'reason': 'Removed from mobile POS cart before billing',
        },
      );
    } catch (_) {}
  }

  void addPayment(String mode, String rawAmount, {String reference = ''}) {
    if (!isValidAmount(rawAmount)) {
      error = 'Enter a valid positive INR tender amount.';
      notifyListeners();
      return;
    }
    error = null;
    payments.add(PayEntry(mode, normAmount(rawAmount), reference: reference.trim()));
    notifyListeners();
  }

  void fillRemainingBalance(String mode, {String reference = ''}) {
    final rem = remainingBalanceDecimal;
    if (rem <= Decimal.zero) return;
    payments.add(PayEntry(mode, rem.toStringAsFixed(2), reference: reference.trim()));
    error = null;
    notifyListeners();
  }

  void removePayment(int i) {
    payments.removeAt(i);
    notifyListeners();
  }

  Decimal get metalSubtotal =>
      lines.fold(Decimal.zero, (acc, l) => acc + l.metalValue);

  Decimal get makingSubtotal =>
      lines.fold(Decimal.zero, (acc, l) => acc + l.makingValue);

  Decimal get taxableSubtotal =>
      lines.fold(Decimal.zero, (acc, l) => acc + l.taxableAmount);

  Decimal get gstSubtotal =>
      lines.fold(Decimal.zero, (acc, l) => acc + l.gstAmount);

  Decimal get grossInvoiceTotal =>
      lines.fold(Decimal.zero, (acc, l) => acc + l.lineTotal);

  Decimal get oldGoldCreditDecimal => decOrZero(oldGold?.credit);

  Decimal get netPayableDecimal {
    final net = grossInvoiceTotal - oldGoldCreditDecimal;
    return net < Decimal.zero ? Decimal.zero : net;
  }

  Decimal get paidTotalDecimal =>
      payments.fold(Decimal.zero, (acc, p) => acc + decOrZero(p.amount));

  Decimal get remainingBalanceDecimal {
    final rem = netPayableDecimal - paidTotalDecimal;
    return rem < Decimal.zero ? Decimal.zero : rem;
  }

  String get paidTotal => paidTotalDecimal.toStringAsFixed(2);

  Future<Map<String, dynamic>?> checkout() async {
    if (customer == null) {
      error = 'Select or register a customer before issuing a GST invoice.';
      notifyListeners();
      return null;
    }
    if (lines.isEmpty) {
      error = 'Scan or add at least one ornament tag to bill.';
      notifyListeners();
      return null;
    }
    if (payments.isEmpty && netPayableDecimal > Decimal.zero) {
      error = 'Record at least one payment tender (Cash, UPI, Card, or Bank).';
      notifyListeners();
      return null;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      final d = await _api.post(
        '/sales/pos/quick-bill',
        idempotencyKey: _uuid.v4(),
        body: {
          'customerId': customer!.id,
          'barcodes': [for (final l in lines) l.article.barcode],
          'items': [
            for (final l in lines)
              {
                if (l.article.id.isNotEmpty) 'articleId': l.article.id,
                'barcode': l.article.barcode,
                'ratePerGram': l.ratePerGram,
                'makingCharges': l.makingCharge,
              },
          ],
          'payments': [
            for (final p in payments)
              {
                'mode': p.mode,
                'amount': p.amount,
                if (p.reference.isNotEmpty) 'reference': p.reference,
              },
          ],
          if (oldGold != null && oldGold!.id.isNotEmpty) 'oldGoldVoucherId': oldGold!.id,
          if (oldGold != null) 'oldGoldCreditAmount': normAmount(oldGold!.credit),
        },
      );
      final receipt = asMap(d);
      final normalized = <String, dynamic>{
        'invoiceNumber': receipt['invoiceNumber'] ??
            receipt['documentNumber'] ??
            'POS-${DateTime.now().millisecondsSinceEpoch % 100000}',
        'customerName': customer!.name,
        'metalSubtotal': metalSubtotal.toStringAsFixed(2),
        'makingSubtotal': makingSubtotal.toStringAsFixed(2),
        'gstAmount': receipt['taxAmount'] ?? receipt['gstAmount'] ?? gstSubtotal.toStringAsFixed(2),
        'oldGoldCredit': oldGold?.credit,
        'totalAmount': receipt['totalAmount'] ?? grossInvoiceTotal.toStringAsFixed(2),
        'paidAmount': paidTotal,
        ...receipt,
      };
      customer = null;
      lines.clear();
      payments.clear();
      oldGold = null;
      busy = false;
      notifyListeners();
      return normalized;
    } on ApiException catch (e) {
      error = e.message;
      busy = false;
      notifyListeners();
      return null;
    }
  }

  void reset() {
    clear();
  }

  Future<void> clear() async {
    final prev = List<CartLine>.from(lines);
    customer = null;
    lines.clear();
    payments.clear();
    oldGold = null;
    error = null;
    notifyListeners();
    for (final l in prev) {
      await _releaseIfHeld(l);
    }
  }
}
