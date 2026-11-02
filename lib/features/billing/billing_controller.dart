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
      error = 'Select or register a customer before issuing an estimate or GST invoice.';
      notifyListeners();
      return null;
    }
    if (lines.isEmpty) {
      error = 'Scan or add at least one tagged ornament to bill.';
      notifyListeners();
      return null;
    }
    if (lines.any((l) => l.article.id.isEmpty)) {
      error = 'Every billed line must reference a vault tagged article UUID.';
      notifyListeners();
      return null;
    }
    busy = true;
    error = null;
    notifyListeners();
    try {
      // 1. Release temporary POS counter holds before estimate/invoice reservation
      for (final l in lines) {
        await _releaseIfHeld(l);
      }

      // 2. Discover published rateVersionId & approved taxProfileId from live workspace
      final ratesRes = await _api.get('/rates');
      String? rateVersionId;
      final now = DateTime.now().toUtc();
      for (final book in asList(ratesRes, keys: const ['rateBooks', 'books', 'items'])) {
        for (final v in asList(book['versions'])) {
          if ('${v['state']}' == 'PUBLISHED') {
            final eff = DateTime.tryParse('${v['effectiveAt'] ?? ''}');
            final exp = DateTime.tryParse('${v['expiresAt'] ?? ''}');
            if ((eff == null || !eff.isAfter(now)) && (exp == null || exp.isAfter(now))) {
              rateVersionId = '${v['id']}';
              break;
            }
            rateVersionId ??= '${v['id']}';
          }
        }
        if (rateVersionId != null && rateVersionId.isNotEmpty) break;
      }
      if (rateVersionId == null || rateVersionId.isEmpty) {
        throw ApiException(
          'RATE_VERSION_REQUIRED',
          'Publish a Rate Version in Materials & Bullion Rates before generating a sales estimate or invoice.',
        );
      }

      final salesWs = asMap(await _api.get('/sales'));
      String? taxProfileId;
      for (final tp in asList(salesWs['taxProfiles'])) {
        if ('${tp['state']}' == 'APPROVED') {
          taxProfileId = '${tp['id']}';
          break;
        }
      }
      if (taxProfileId == null || taxProfileId.isEmpty) {
        throw ApiException(
          'TAX_PROFILE_REQUIRED',
          'Create & approve a GST Tax Profile in Sales Lifecycle → Tax Profiles before billing.',
        );
      }

      // 3. Create authoritative Sales Estimate (`POST /sales/estimates`)
      final discountPerFirst = oldGoldCreditDecimal > Decimal.zero
          ? oldGoldCreditDecimal.toStringAsFixed(2)
          : '0.00';
      final estRaw = asMap(await _api.post(
        '/sales/estimates',
        idempotent: true,
        body: {
          'customerPartyId': customer!.id,
          'rateVersionId': rateVersionId,
          'taxProfileId': taxProfileId,
          'quoteDate': todayIso(),
          'expiresAt': now.add(const Duration(hours: 24)).toIso8601String(),
          'lines': [
            for (var i = 0; i < lines.length; i++)
              {
                'articleId': lines[i].article.id,
                'makingAmount': normAmount(lines[i].makingCharge),
                'otherAmount': '0.00',
                'discountAmount': i == 0 ? discountPerFirst : '0.00',
              },
          ],
        },
      ));
      final estId = '${estRaw['id'] ?? ''}';

      // 4. Attempt automatic conversion to Sales Invoice if GL accounts exist
      Map<String, dynamic> finalDoc = estRaw;
      try {
        final acctWs = asMap(await _api.get('/accounting/workspace'));
        final accts = asList(acctWs['accounts']);
        String? findAcct(List<String> keys) {
          for (final k in keys) {
            final hit = accts.where((a) =>
                '${a['controlType'] ?? ''}'.toUpperCase() == k ||
                '${a['group'] ?? ''}'.toUpperCase() == k).firstOrNull;
            if (hit != null) return '${hit['id']}';
          }
          return null;
        }

        final recvAcct = findAcct(const ['CUSTOMER_RECEIVABLE', 'ASSET']);
        final revAcct = findAcct(const ['INCOME']);
        final taxAcct = findAcct(const ['TAX_OUTPUT', 'LIABILITY']);
        final cogsAcct = findAcct(const ['EXPENSE']);
        final invAcct = findAcct(const ['INVENTORY', 'ASSET']);

        if (estId.isNotEmpty &&
            recvAcct != null &&
            revAcct != null &&
            cogsAcct != null &&
            invAcct != null) {
          final invDraft = asMap(await _api.post(
            '/sales/invoices',
            idempotent: true,
            body: {
              'estimateId': estId,
              'invoiceDate': todayIso(),
              'reservationExpiresAt': now.add(const Duration(hours: 4)).toIso8601String(),
              'receivableAccountId': recvAcct,
              'revenueAccountId': revAcct,
              if (taxAcct != null) 'outputTaxAccountId': taxAcct,
              'cogsAccountId': cogsAcct,
              'inventoryAccountId': invAcct,
            },
          ));
          finalDoc = invDraft;

          // Post invoice if open period & series exist
          final openPeriod = asList(acctWs['financialYears'])
              .expand((fy) => asList(fy['periods']))
              .where((p) => '${p['state']}' == 'OPEN')
              .firstOrNull;
          final allSeries = [
            ...asList(acctWs['series']),
            ...asList(acctWs['financialYears']).expand((fy) => asList(fy['series'])),
          ];
          final invSeries = allSeries
              .where((s) => '${s['documentType']}'.toUpperCase().contains('INVOICE'))
              .firstOrNull;
          final jvSeries = allSeries
              .where((s) => '${s['documentType']}'.toUpperCase() == 'JOURNAL')
              .firstOrNull;

          if (openPeriod != null && invSeries != null && jvSeries != null && invDraft['id'] != null) {
            final posted = asMap(await _api.post(
              '/sales/invoices/${invDraft['id']}/post',
              idempotent: true,
              body: {
                'expectedVersion': asInt(invDraft['version'], fallback: 1),
                'postingPeriodId': '${openPeriod['id']}',
                'documentSeriesId': '${invSeries['id']}',
                'journalSeriesId': '${jvSeries['id']}',
                'reason': 'Posted showroom sales invoice from mobile POS checkout.',
              },
            ));
            if (posted.isNotEmpty) finalDoc = posted;
          }
        }
      } catch (_) {
        // Estimate succeeded; keep estimate receipt if GL accounts/series are not yet set up
      }

      final normalized = <String, dynamic>{
        'invoiceNumber': finalDoc['documentNumber'] ??
            finalDoc['quoteNumber'] ??
            estRaw['quoteNumber'] ??
            shortId('${finalDoc['id'] ?? estId}'),
        'customerName': customer!.name,
        'metalSubtotal': estRaw['metalValue'] ?? metalSubtotal.toStringAsFixed(2),
        'makingSubtotal': estRaw['makingAmount'] ?? makingSubtotal.toStringAsFixed(2),
        'gstAmount': finalDoc['taxAmount'] ?? estRaw['taxAmount'] ?? gstSubtotal.toStringAsFixed(2),
        'oldGoldCredit': oldGold?.credit,
        'totalAmount': finalDoc['totalAmount'] ?? estRaw['totalAmount'] ?? grossInvoiceTotal.toStringAsFixed(2),
        'paidAmount': paidTotal,
        ...finalDoc,
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
