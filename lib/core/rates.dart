import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'format.dart';
import 'models.dart';

/// Live Bullion Spot & Showroom Rate Board controller.
/// Supports both:
/// 1) Enterprise RateBook + Materials masters (`GET /rates` -> RateBook[], `GET /materials`)
/// 2) Flat mobile rate list (`GET /rates` -> `{ metals: [...] }`)
class RatesController extends ChangeNotifier {
  RatesController(this.api);
  final ApiClient api;

  List<MetalRate> rates = [];
  List<Map<String, dynamic>> rawBooks = [];
  List<Map<String, dynamic>> rawMetals = [];
  String? activeBookName;
  String? get activeRateBookName => activeBookName;
  String? activeBookCode;
  String? activeRateVersionId;
  int? activeSequence;
  String? effectiveAtIso;

  bool loading = false;
  String? error;
  DateTime? updatedAt;
  Timer? _timer;

  void start() {
    load();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => load(silent: true));
  }

  void stop() => _timer?.cancel();

  Future<void> refresh() => load();

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final results = await Future.wait<dynamic>([
        api.get('/rates'),
        api.get('/materials').catchError((_) => null),
      ]);
      final d = results[0];
      final mat = results[1];
      if (mat is Map && mat['metals'] is List) {
        rawMetals = asList(mat, keys: const ['metals']);
      }

      if (d is Map && d['metals'] is List) {
        // Direct handoff payload: { metals: [{ metal, purity, carat, sellRatePerGram, buyRatePerGram }] }
        rates = asList(d, keys: const ['metals']).map(MetalRate.fromJson).toList();
        activeBookName = d['bookName']?.toString() ?? 'Live Bullion Board';
      } else {
        // RateBook[] payload from @jewellery-erp/contracts
        final books = asList(d);
        rawBooks = books;
        rates = _deriveRatesFromBooks(books, rawMetals);
      }
      updatedAt = DateTime.now();
      error = null;
    } on ApiException catch (e) {
      if (!silent || rates.isEmpty) error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  List<MetalRate> _deriveRatesFromBooks(
    List<Map<String, dynamic>> books,
    List<Map<String, dynamic>> metalsMaster,
  ) {
    Map<String, dynamic>? chosenBook;
    Map<String, dynamic>? chosenVersion;

    // Prefer an active PUBLISHED version whose effective window is current.
    final now = DateTime.now();
    for (final book in books) {
      final versions = asList(book, keys: const ['versions']);
      for (final v in versions) {
        if ('${v['state']}'.toUpperCase() == 'PUBLISHED') {
          final eff = DateTime.tryParse('${v['effectiveAt'] ?? ''}');
          final exp = DateTime.tryParse('${v['expiresAt'] ?? ''}');
          final activeNow = (eff == null || !eff.isAfter(now)) && (exp == null || exp.isAfter(now));
          if (activeNow) {
            chosenBook = book;
            chosenVersion = v;
            break;
          }
          chosenBook ??= book;
          chosenVersion ??= v;
        }
      }
      if (chosenVersion != null) break;
    }

    // Fallback to latest version if none published yet so draft setups still preview cleanly.
    if (chosenVersion == null) {
      for (final book in books) {
        final versions = asList(book, keys: const ['versions']);
        if (versions.isNotEmpty) {
          chosenBook = book;
          chosenVersion = versions.first;
          break;
        }
      }
    }

    if (chosenBook == null || chosenVersion == null) {
      activeBookName = null;
      activeBookCode = null;
      activeRateVersionId = null;
      activeSequence = null;
      effectiveAtIso = null;
      return const [];
    }

    activeBookName = '${chosenBook['name'] ?? 'Showroom Rate Book'}';
    activeBookCode = '${chosenBook['code'] ?? ''}';
    activeRateVersionId = '${chosenVersion['id'] ?? ''}';
    activeSequence = chosenVersion['sequenceNumber'] is int ? chosenVersion['sequenceNumber'] as int : null;
    effectiveAtIso = '${chosenVersion['effectiveAt'] ?? chosenVersion['publishedAt'] ?? ''}';

    final lines = asList(chosenVersion, keys: const ['lines']);
    if (lines.isEmpty) return const [];

    // Group BUY and SELL per-gram base rates by metal code.
    final byMetal = <String, _BaseMetalQuote>{};
    for (final line in lines) {
      final metalObj = line['metal'] is Map ? Map<String, dynamic>.from(line['metal'] as Map) : <String, dynamic>{};
      final unitObj = line['unit'] is Map ? Map<String, dynamic>.from(line['unit'] as Map) : <String, dynamic>{};
      final code = '${metalObj['code'] ?? line['metalCode'] ?? ''}'.toUpperCase();
      if (code.isEmpty) continue;
      final ratePerUnit = decOrZero(line['ratePerUnit']);
      final baseFactor = tryDec(unitObj['baseFactor']) ?? Decimal.one;
      final refFineness = tryDec(line['referenceFineness']) ?? Decimal.fromInt(999);
      final perGramAtRef = baseFactor > Decimal.zero ? decDiv(ratePerUnit, baseFactor, scale: 12) : ratePerUnit;

      final quote = byMetal.putIfAbsent(
        code,
        () => _BaseMetalQuote(
          metalId: '${metalObj['id'] ?? ''}',
          code: code,
          name: '${metalObj['name'] ?? humanize(code)}',
        ),
      );
      final side = '${line['side'] ?? 'SELL'}'.toUpperCase();
      if (side == 'SELL') {
        quote.sellPerGramRef = perGramAtRef;
        quote.sellRefFineness = refFineness;
      } else if (side == 'BUY') {
        quote.buyPerGramRef = perGramAtRef;
        quote.buyRefFineness = refFineness;
      }
    }

    final out = <MetalRate>[];
    for (final q in byMetal.values) {
      // Match purity grades from /materials for this metal, or standard showroom purities.
      Map<String, dynamic>? metalMaster;
      for (final m in metalsMaster) {
        if ('${m['code']}'.toUpperCase() == q.code || '${m['id']}' == q.metalId) {
          metalMaster = m;
          break;
        }
      }
      var grades = metalMaster != null ? asList(metalMaster, keys: const ['purityGrades']) : <Map<String, dynamic>>[];
      if (grades.isEmpty) {
        grades = q.code == 'SILVER'
            ? [
                {'code': '999', 'displayKarat': 'Fine Silver', 'finenessPerThousand': '999.000000'},
                {'code': '925', 'displayKarat': 'Sterling 925', 'finenessPerThousand': '925.000000'},
              ]
            : [
                {'code': '999', 'displayKarat': '24K', 'finenessPerThousand': '999.000000'},
                {'code': '916', 'displayKarat': '22K', 'finenessPerThousand': '916.000000'},
                {'code': '750', 'displayKarat': '18K', 'finenessPerThousand': '750.000000'},
              ];
      } else {
        // Sort highest fineness first (e.g. 24K -> 22K -> 18K).
        grades.sort((a, b) => decOrZero(b['finenessPerThousand']).compareTo(decOrZero(a['finenessPerThousand'])));
      }

      for (final g in grades) {
        final code = '${g['code'] ?? ''}';
        final fineness = tryDec(g['finenessPerThousand']) ?? tryDec(code) ?? Decimal.fromInt(999);
        final sellGram = q.sellPerGramRef != null && q.sellRefFineness != null && q.sellRefFineness! > Decimal.zero
            ? decDiv(q.sellPerGramRef! * fineness, q.sellRefFineness!, scale: 10).round(scale: 2).toStringAsFixed(2)
            : '0.00';
        final buyGram = q.buyPerGramRef != null && q.buyRefFineness != null && q.buyRefFineness! > Decimal.zero
            ? decDiv(q.buyPerGramRef! * fineness, q.buyRefFineness!, scale: 10).round(scale: 2).toStringAsFixed(2)
            : sellGram;
        final karat = '${g['displayKarat'] ?? ''}'.trim();
        out.add(MetalRate(
          metal: q.code,
          metalName: q.name,
          purity: code,
          carat: karat.isNotEmpty ? karat : code,
          fineness: fineness.toStringAsFixed(6),
          sell: sellGram,
          buy: buyGram,
          metalId: q.metalId.isEmpty ? null : q.metalId,
          purityGradeId: g['id']?.toString(),
          rateVersionId: activeRateVersionId,
        ));
      }
    }
    return out;
  }

  MetalRate? find(String metal, String purity) {
    final m = metal.toUpperCase();
    final p = purity.toUpperCase();
    for (final r in rates) {
      if (r.metal.toUpperCase() == m &&
          (r.purity.toUpperCase() == p || r.carat.toUpperCase() == p || p.contains(r.purity.toUpperCase()))) {
        return r;
      }
    }
    for (final r in rates) {
      if (r.metal.toUpperCase() == m) return r;
    }
    return null;
  }

  /// Calls `POST /pricing/calculate-metal` on the server if IDs are available,
  /// otherwise computes exact Decimal metal value & Fine 999 weight from the active rate board.
  Future<Map<String, String>> calculateMetalValue({
    required String metal,
    required String purity,
    required String netWeightGrams,
    String side = 'SELL',
  }) async {
    final metalRate = find(metal, purity);
    final w = decOrZero(netWeightGrams);
    final purNum = tryDec(purity) ?? Decimal.fromInt(916);
    final fineRatio = purNum <= Decimal.one ? purNum : purNum * Decimal.parse('0.001');
    final fineWt = (w * fineRatio).round(scale: 6).toStringAsFixed(6);

    if (metalRate == null) {
      return {
        'ratePerGram': '0.00',
        'fineWeightGrams': fineWt,
        'metalValue': '0.00',
      };
    }

    final appliedRate = side == 'BUY' ? metalRate.buy : metalRate.sell;
    if (metalRate.rateVersionId != null &&
        metalRate.rateVersionId!.isNotEmpty &&
        metalRate.metalId != null &&
        metalRate.metalId!.isNotEmpty &&
        metalRate.purityGradeId != null &&
        metalRate.purityGradeId!.isNotEmpty) {
      try {
        final res = asMap(await api.post('/pricing/calculate-metal', body: {
          'rateVersionId': metalRate.rateVersionId,
          'components': [
            {
              'metalId': metalRate.metalId,
              'purityGradeId': metalRate.purityGradeId,
              'weightGrams': normWeight6(netWeightGrams),
              'side': side,
            },
          ],
        }));
        final v = res['totalMetalValue'];
        if (v != null && '$v'.isNotEmpty) {
          return {
            'ratePerGram': appliedRate,
            'fineWeightGrams': '${res['totalFineWeightGrams'] ?? fineWt}',
            'metalValue': normAmount('$v'),
          };
        }
      } catch (_) {
        // Fall through to local Decimal calculation using active rate board.
      }
    }
    final r = decOrZero(appliedRate);
    final val = (w * r).round(scale: 2).toStringAsFixed(2);
    return {
      'ratePerGram': appliedRate,
      'fineWeightGrams': fineWt,
      'metalValue': val,
    };
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _BaseMetalQuote {
  _BaseMetalQuote({required this.metalId, required this.code, required this.name});
  final String metalId;
  final String code;
  final String name;
  Decimal? sellPerGramRef;
  Decimal? sellRefFineness;
  Decimal? buyPerGramRef;
  Decimal? buyRefFineness;
}
