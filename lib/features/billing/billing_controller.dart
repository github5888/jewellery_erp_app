import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';

class ExchangeCredit {
  ExchangeCredit({required this.voucherId, required this.label, required this.amount});
  final String voucherId;
  final String label;
  String amount; // decimal string, 2dp
}

class PaymentLine {
  PaymentLine({required this.mode, required this.amount, this.reference});
  final String mode; // CASH | UPI | CARD | BANK_TRANSFER | CHEQUE
  final String amount;
  final String? reference;
}

const paymentModes = {
  'CASH': 'Cash',
  'UPI': 'UPI',
  'CARD': 'Card',
  'BANK_TRANSFER': 'Bank transfer',
  'CHEQUE': 'Cheque',
};

/// Holds the open bill. All money maths happens on the server: this class
/// only collects pieces, credits and payments and sends them with an
/// Idempotency-Key so a retry after a dropped connection can't double-bill.
class BillingController extends ChangeNotifier {
  BillingController(this.api);
  final ApiClient api;

  Party? customer;
  final List<Article> lines = [];
  final List<ExchangeCredit> exchanges = [];
  final List<PaymentLine> payments = [];
  String remarks = '';

  bool busy = false;
  String? error;
  Map<String, dynamic>? receipt;

  String _key = const Uuid().v4();

  void _touch() {
    // Any change to the bill is a different checkout: new idempotency key.
    _key = const Uuid().v4();
    error = null;
    notifyListeners();
  }

  void setCustomer(Party? p) {
    customer = p;
    _touch();
  }

  /// Looks the piece up, locks it for this counter, then adds it.
  Future<Article> addByBarcode(String code) async {
    final c = code.trim();
    if (lines.any((a) => a.barcode == c)) {
      throw ApiException('DUPLICATE', 'This piece is already on the bill.');
    }
    final art = Article(asMap(await api.get('/inventory', query: {'barcode': c})));
    if (art.id.isEmpty) {
      throw ApiException('NOT_FOUND', 'No piece found for barcode $c.');
    }
    await addArticle(art);
    return art;
  }

  Future<void> addArticle(Article art) async {
    if (lines.any((a) => a.id == art.id)) {
      throw ApiException('DUPLICATE', 'This piece is already on the bill.');
    }
    // Pessimistic lock so another counter can't sell it meanwhile.
    await api.post('/inventory/articles/${art.id}/reserve');
    lines.add(art);
    _touch();
  }

  void removeLine(Article a) {
    lines.removeWhere((x) => x.id == a.id);
    _touch();
  }

  void addExchange(ExchangeCredit c) {
    exchanges.removeWhere((x) => x.voucherId == c.voucherId);
    exchanges.add(c);
    _touch();
  }

  void removeExchange(ExchangeCredit c) {
    exchanges.remove(c);
    _touch();
  }

  void addPayment(PaymentLine p) {
    payments.add(p);
    _touch();
  }

  void removePayment(PaymentLine p) {
    payments.remove(p);
    _touch();
  }

  void setRemarks(String v) => remarks = v;

  bool get canCheckout => lines.isNotEmpty && payments.isNotEmpty && !busy;

  Future<void> checkout() async {
    if (!canCheckout) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final body = {
        if (customer != null) 'customerId': customer!.id,
        'items': [
          for (final a in lines) {'articleId': a.id, 'quantity': 1, 'makingChargeOverride': null},
        ],
        'oldMetalExchanges': [
          for (final e in exchanges) {'voucherId': e.voucherId, 'appliedCredit': e.amount},
        ],
        'payments': [
          for (final p in payments)
            {
              'mode': p.mode,
              'amount': p.amount,
              if (p.reference != null && p.reference!.isNotEmpty) 'referenceNumber': p.reference,
            },
        ],
        if (remarks.trim().isNotEmpty) 'remarks': remarks.trim(),
      };
      final d = await api.post('/sales/pos/quick-bill', body: body, idempotencyKey: _key);
      receipt = asMap(d);
    } on ApiException catch (e) {
      error = e.message;
    }
    busy = false;
    notifyListeners();
  }

  /// Start a fresh bill (after a receipt, or when the showroom changes).
  void reset() {
    customer = null;
    lines.clear();
    exchanges.clear();
    payments.clear();
    remarks = '';
    receipt = null;
    error = null;
    busy = false;
    _key = const Uuid().v4();
    notifyListeners();
  }

  String get paymentsTotalLabel {
    // Display only: sum of typed payments using integer paise, no floats.
    var paise = 0;
    for (final p in payments) {
      final parts = p.amount.split('.');
      paise += int.parse(parts[0]) * 100 + int.parse(parts.length > 1 ? parts[1] : '0');
    }
    final s = '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
    return inr(s);
  }
}
