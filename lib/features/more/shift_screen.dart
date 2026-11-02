import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../finance/accounting_finance_screens.dart';
import '../supply/supply_production_screens.dart';

/// POS Cash Shifts (`Counter POS Shifts`) — 1:1 mobile implementation of
/// `pos.hrpocket.in` (`image-5.png`) integrated with live `/pos-shifts` and
/// `/accounting/workspace` endpoints:
/// - Cashier drawer custody (`Business Date`, `Cash Drawer Account`, live `Opening Float (INR)`, `Evidence / Drawer Ref`)
/// - Exact 16-denomination Indian Currency Breakdown (`INR 2000` .. `INR 0.01`) formatted in a 2-column mobile grid
/// - Active shift system tender totals, closing denomination count, and manager-approved variance posting
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  static const _uuid = Uuid();

  /// Exact 16 Indian currency denominations from `pos.hrpocket.in` (`image-5.png`).
  static const List<({String key, String label, String valueStr})> _denominations = [
    (key: '2000', label: 'INR 2000', valueStr: '2000'),
    (key: '500', label: 'INR 500', valueStr: '500'),
    (key: '200', label: 'INR 200', valueStr: '200'),
    (key: '100', label: 'INR 100', valueStr: '100'),
    (key: '50', label: 'INR 50', valueStr: '50'),
    (key: '20', label: 'INR 20', valueStr: '20'),
    (key: '10', label: 'INR 10', valueStr: '10'),
    (key: '5', label: 'INR 5', valueStr: '5'),
    (key: '2', label: 'INR 2', valueStr: '2'),
    (key: '1', label: 'INR 1', valueStr: '1'),
    (key: '0.50', label: 'INR 0.50', valueStr: '0.50'),
    (key: '0.20', label: 'INR 0.20', valueStr: '0.20'),
    (key: '0.10', label: 'INR 0.10', valueStr: '0.10'),
    (key: '0.05', label: 'INR 0.05', valueStr: '0.05'),
    (key: '0.02', label: 'INR 0.02', valueStr: '0.02'),
    (key: '0.01', label: 'INR 0.01', valueStr: '0.01'),
  ];

  final _search = TextEditingController();
  String _tab = 'DRAWER';

  Map<String, dynamic>? _activeShift;
  List<Map<String, dynamic>> _history = [];
  List<LookupOption> _drawerAccounts = [];
  WorkspaceLookup _lk = WorkspaceLookup();

  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Open / Close Cashier Shift fields (`image-5.png`)
  final _businessDate = TextEditingController(text: todayIso());
  final _drawerAcctId = TextEditingController();
  final _evidenceRef = TextEditingController();
  final _varianceReason = TextEditingController();
  final _periodId = TextEditingController();
  final _journalSeriesId = TextEditingController();
  final _varianceAcctId = TextEditingController();

  late final Map<String, TextEditingController> _denomCtrls = {
    for (final d in _denominations) d.key: TextEditingController(text: '0'),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _businessDate.dispose();
    _drawerAcctId.dispose();
    _evidenceRef.dispose();
    _varianceReason.dispose();
    _periodId.dispose();
    _journalSeriesId.dispose();
    _varianceAcctId.dispose();
    for (final c in _denomCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isOpen => _activeShift != null && _activeShift!.isNotEmpty;

  bool get _needsVarianceApproval {
    if (!_isOpen) return false;
    final st = _pick(_activeShift!, ['state', 'status']).toUpperCase();
    return st.contains('VARIANCE') || st.contains('PENDING') || st == 'COUNTED';
  }

  int _countFor(String key) {
    final raw = _denomCtrls[key]?.text.trim() ?? '0';
    final n = int.tryParse(raw) ?? 0;
    return n < 0 ? 0 : n;
  }

  int get _totalNotesAndCoins {
    var sum = 0;
    for (final d in _denominations) {
      sum += _countFor(d.key);
    }
    return sum;
  }

  Decimal get _countedTotalDecimal {
    var total = Decimal.zero;
    for (final d in _denominations) {
      final qty = _countFor(d.key);
      if (qty > 0) {
        total += Decimal.parse(d.valueStr) * Decimal.fromInt(qty);
      }
    }
    return total.round(scale: 2);
  }

  void _stepDenom(String key, int delta) {
    final next = (_countFor(key) + delta).clamp(0, 999999);
    final ctrl = _denomCtrls[key];
    if (ctrl != null) {
      ctrl.text = '$next';
      setState(() {});
    }
  }

  void _resetDenominations() {
    for (final c in _denomCtrls.values) {
      c.text = '0';
    }
    setState(() {});
  }

  List<Map<String, dynamic>> _buildDenominationLines() {
    return [
      for (final d in _denominations)
        if (_countFor(d.key) > 0)
          {
            'denomination': d.valueStr,
            'count': _countFor(d.key),
            'quantity': _countFor(d.key),
            'amount': (Decimal.parse(d.valueStr) * Decimal.fromInt(_countFor(d.key)))
                .round(scale: 2)
                .toStringAsFixed(2),
          },
    ];
  }

  Map<String, int> _buildDenominationMap() {
    return {
      for (final d in _denominations)
        if (_countFor(d.key) > 0) d.valueStr: _countFor(d.key),
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait<dynamic>([
        api.get('/pos-shifts').catchError((Object e) {
          if (e is ApiException && (e.status == 404 || e.code == 'HTTP_ERROR')) {
            return <String, dynamic>{};
          }
          throw e;
        }),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final shiftRaw = results[0];
      final lk = results[1] as WorkspaceLookup;

      _parseWorkspace(shiftRaw, lk);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseWorkspace(dynamic d, WorkspaceLookup lk) {
    Map<String, dynamic>? current;
    var list = <Map<String, dynamic>>[];
    final explicitAccts = <LookupOption>[];

    if (d is Map) {
      for (final k in const ['current', 'currentShift', 'activeShift', 'openShift']) {
        if (d[k] is Map) {
          current = Map<String, dynamic>.from(d[k] as Map);
          break;
        }
      }
      if (d['shifts'] is List ||
          d['posShifts'] is List ||
          d['items'] is List ||
          d['history'] is List) {
        list = asList(d, keys: const ['shifts', 'posShifts', 'items', 'history']);
      } else if (current == null &&
          (d['id'] != null || d['state'] != null || d['status'] != null)) {
        list = [Map<String, dynamic>.from(d)];
      }

      for (final a in asList(
        d,
        keys: const ['cashDrawerAccounts', 'drawerAccounts', 'accounts'],
      )) {
        final id = '${a['id'] ?? ''}';
        if (id.isEmpty) continue;
        final code = '${a['code'] ?? ''}'.trim();
        final name = '${a['name'] ?? 'Cash Drawer'}'.trim();
        final ctrl = '${a['controlType'] ?? a['group'] ?? ''}'.trim();
        explicitAccts.add(
          LookupOption(
            id: id,
            label: [
              if (code.isNotEmpty) code,
              name,
              if (ctrl.isNotEmpty && ctrl != 'NONE') '($ctrl)',
            ].join(' · '),
            raw: a,
          ),
        );
      }
    } else if (d is List) {
      list = asList(d);
    }

    bool isActiveState(Map<String, dynamic> s) {
      final st = _pick(s, ['state', 'status']).toUpperCase();
      return st == 'OPEN' ||
          st == 'ACTIVE' ||
          st == 'COUNTED' ||
          st.contains('VARIANCE') ||
          st.contains('PENDING');
    }

    if (current == null) {
      for (final s in list) {
        if (isActiveState(s)) {
          current = s;
          break;
        }
      }
    } else if (!isActiveState(current)) {
      current = null;
    }

    // Merge cash drawer accounts from `/pos-shifts` + `/accounting/workspace`
    final seen = <String>{};
    final mergedAccounts = <LookupOption>[];
    for (final a in explicitAccts) {
      if (seen.add(a.id)) mergedAccounts.add(a);
    }
    bool looksLikeCashAccount(LookupOption o) {
      final ctrl = '${o.raw['controlType'] ?? ''}'.toUpperCase();
      final grp = '${o.raw['group'] ?? ''}'.toUpperCase();
      final hay = '${o.label} ${o.raw['name'] ?? ''} ${o.raw['code'] ?? ''}'.toLowerCase();
      return ctrl.contains('CASH') ||
          ctrl.contains('DRAWER') ||
          hay.contains('cash') ||
          hay.contains('drawer') ||
          hay.contains('counter') ||
          hay.contains('petty') ||
          grp == 'ASSET';
    }

    for (final a in lk.accounts.where(looksLikeCashAccount)) {
      if (seen.add(a.id)) mergedAccounts.add(a);
    }
    for (final a in lk.accounts) {
      if (seen.add(a.id)) mergedAccounts.add(a);
    }

    if (_drawerAcctId.text.trim().isEmpty && mergedAccounts.isNotEmpty) {
      _drawerAcctId.text = mergedAccounts.first.id;
    }
    if (_periodId.text.trim().isEmpty && lk.openPeriods().isNotEmpty) {
      _periodId.text = lk.openPeriods().first.id;
    }
    if (_journalSeriesId.text.trim().isEmpty) {
      final js = lk.seriesFor(const ['JOURNAL']);
      if (js.isNotEmpty) _journalSeriesId.text = js.first.id;
    }
    if (_varianceAcctId.text.trim().isEmpty) {
      final exp = lk.accountsByControl(const ['EXPENSE', 'INCOME']);
      if (exp.isNotEmpty) _varianceAcctId.text = exp.first.id;
    }

    setState(() {
      _activeShift = current;
      _history = list;
      _drawerAccounts = mergedAccounts;
      _lk = lk;
    });
  }

  String _pick(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty && '$v' != 'null') return '$v';
    }
    return fallback;
  }

  Decimal _expectedCashForActiveShift() {
    if (_activeShift == null) return Decimal.zero;
    final s = _activeShift!;
    final direct = _pick(s, [
      'expectedClosingCash',
      'expectedCash',
      'expectedCashAmount',
      'systemCashBalance',
      'expectedBalance',
    ]);
    if (direct.isNotEmpty) return decOrZero(direct);
    final opening = decOrZero(
      _pick(s, ['openingFloatAmount', 'openingCash', 'openingBalance', 'openingFloat'], '0.00'),
    );
    final cashIn = decOrZero(
      _pick(s, ['systemCashReceipts', 'cashSalesAmount', 'cashInAmount', 'cashTenderTotal'], '0.00'),
    );
    final cashOut = decOrZero(
      _pick(s, ['systemCashPayouts', 'cashRefundsAmount', 'cashOutAmount'], '0.00'),
    );
    return (opening + cashIn - cashOut).round(scale: 2);
  }

  Future<void> _openShift() async {
    if (_businessDate.text.trim().isEmpty) {
      setState(() => _error = 'Select the Business Date to open a counter shift.');
      return;
    }
    if (_drawerAccounts.isNotEmpty && _drawerAcctId.text.trim().isEmpty) {
      setState(() => _error = 'Select a Cash Drawer Account before opening the shift.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final floatStr = _countedTotalDecimal.toStringAsFixed(2);
    final refText = _evidenceRef.text.trim();
    final denomLines = _buildDenominationLines();
    final denomOnlyStrict = [
      for (final d in _denominations)
        if (_countFor(d.key) > 0)
          {
            'denomination': d.valueStr,
            'count': _countFor(d.key),
          },
    ];

    final api = context.read<ApiClient>();
    try {
      final primaryBody = <String, dynamic>{
        'businessDate': _businessDate.text.trim(),
        if (_drawerAcctId.text.trim().isNotEmpty)
          'cashDrawerAccountId': _drawerAcctId.text.trim(),
        'openingFloatAmount': floatStr,
        'openingCash': floatStr,
        if (refText.isNotEmpty) 'evidenceRef': refText,
        if (refText.isNotEmpty) 'remarks': refText,
        'denominations': denomOnlyStrict,
        if (denomLines.isNotEmpty) 'openingDenominations': _buildDenominationMap(),
      };

      try {
        await api.post(
          '/pos-shifts/open',
          idempotencyKey: _uuid.v4(),
          body: primaryBody,
        );
      } on ApiException catch (e) {
        if (e.status == 404 || e.code == 'HTTP_ERROR') {
          await api.post(
            '/pos-shifts',
            idempotencyKey: _uuid.v4(),
            body: {
              'businessDate': _businessDate.text.trim(),
              if (_drawerAcctId.text.trim().isNotEmpty)
                'cashDrawerAccountId': _drawerAcctId.text.trim(),
              'openingFloatAmount': floatStr,
              if (refText.isNotEmpty) 'evidenceRef': refText,
              'denominations': denomOnlyStrict,
            },
          );
        } else if (e.status == 400) {
          // Strict-schema retry with exact minimal web form keys (`image-5.png`)
          await api.post(
            '/pos-shifts/open',
            idempotencyKey: _uuid.v4(),
            body: {
              'businessDate': _businessDate.text.trim(),
              if (_drawerAcctId.text.trim().isNotEmpty)
                'cashDrawerAccountId': _drawerAcctId.text.trim(),
              'openingFloat': floatStr,
              if (refText.isNotEmpty) 'evidenceRef': refText,
              'denominations': denomOnlyStrict,
            },
          );
        } else {
          rethrow;
        }
      }

      _resetDenominations();
      _evidenceRef.clear();
      await _load();
      if (mounted) toast(context, 'Counter POS shift opened.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _closeShift() async {
    if (_activeShift == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final shiftId = '${_activeShift!['id'] ?? ''}';
    final expectedVersion = asInt(_activeShift!['version'], fallback: 1);
    final closingStr = _countedTotalDecimal.toStringAsFixed(2);
    final refText = _evidenceRef.text.trim();
    final reasonText = _varianceReason.text.trim();
    final denomOnlyStrict = [
      for (final d in _denominations)
        if (_countFor(d.key) > 0)
          {
            'denomination': d.valueStr,
            'count': _countFor(d.key),
          },
    ];

    final api = context.read<ApiClient>();
    try {
      final closeBody = <String, dynamic>{
        'expectedVersion': expectedVersion,
        'closingCash': closingStr,
        'closingFloatAmount': closingStr,
        if (refText.isNotEmpty) 'evidenceRef': refText,
        if (reasonText.isNotEmpty) 'reason': reasonText,
        if (reasonText.isNotEmpty) 'remarks': reasonText,
        'denominations': denomOnlyStrict,
        if (_periodId.text.trim().isNotEmpty) 'postingPeriodId': _periodId.text.trim(),
        if (_journalSeriesId.text.trim().isNotEmpty)
          'journalSeriesId': _journalSeriesId.text.trim(),
        if (_varianceAcctId.text.trim().isNotEmpty)
          'varianceAccountId': _varianceAcctId.text.trim(),
      };

      if (shiftId.isNotEmpty) {
        try {
          await api.post(
            '/pos-shifts/$shiftId/close',
            idempotencyKey: _uuid.v4(),
            body: closeBody,
          );
        } on ApiException catch (e) {
          if (e.status == 404 || e.code == 'HTTP_ERROR') {
            await api.post(
              '/pos-shifts/close',
              idempotencyKey: _uuid.v4(),
              body: {'shiftId': shiftId, ...closeBody},
            );
          } else {
            rethrow;
          }
        }
      } else {
        await api.post(
          '/pos-shifts/close',
          idempotencyKey: _uuid.v4(),
          body: closeBody,
        );
      }

      _resetDenominations();
      _evidenceRef.clear();
      _varianceReason.clear();
      await _load();
      if (mounted) toast(context, 'Counter shift counted & reconciled.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveVariance() async {
    if (_activeShift == null) return;
    final shiftId = '${_activeShift!['id'] ?? ''}';
    if (shiftId.isEmpty) return;
    if (_varianceReason.text.trim().length < 5) {
      setState(() => _error = 'Enter a manager approval reason (min 5 characters) to post shift variance.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final body = <String, dynamic>{
        'expectedVersion': asInt(_activeShift!['version'], fallback: 1),
        'reason': _varianceReason.text.trim(),
        if (_periodId.text.trim().isNotEmpty) 'postingPeriodId': _periodId.text.trim(),
        if (_journalSeriesId.text.trim().isNotEmpty)
          'journalSeriesId': _journalSeriesId.text.trim(),
        if (_varianceAcctId.text.trim().isNotEmpty)
          'varianceAccountId': _varianceAcctId.text.trim(),
      };
      try {
        await api.post(
          '/pos-shifts/$shiftId/approve-variance',
          idempotencyKey: _uuid.v4(),
          body: body,
        );
      } on ApiException catch (e) {
        if (e.status == 404 || e.code == 'HTTP_ERROR') {
          await api.post(
            '/pos-shifts/$shiftId/approve',
            idempotencyKey: _uuid.v4(),
            body: body,
          );
        } else {
          rethrow;
        }
      }
      _varianceReason.clear();
      await _load();
      if (mounted) toast(context, 'Manager variance approved & posted.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999');
    final bullionActive = gold999 != null && decOrZero(gold999.sell) > Decimal.zero;

    final q = _search.text.trim().toLowerCase();
    final fHistory = _history.where((s) {
      if (q.isEmpty) return true;
      final hay = [
        _pick(s, ['shiftNumber', 'documentNumber', 'code', 'counterName']),
        _pick(s, ['businessDate', 'openedAt']),
        _pick(s, ['evidenceRef', 'remarks']),
        _pick(s, ['state', 'status']),
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();

    final showroomContext = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    return LuxuryModuleScaffold(
      title: 'Counter POS Shifts',
      icon: Icons.payments_outlined,
      searchController: _tab == 'HISTORY' ? _search : null,
      searchHint: 'Search shift #, business date, ref or state...',
      onSearchChanged: _tab == 'HISTORY' ? (_) => setState(() {}) : null,
      actions: [
        IconButton(
          tooltip: 'Refresh shifts & drawer accounts',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: [
          ('DRAWER', _isOpen ? 'Active Shift (Open)' : 'POS Cash Shifts'),
          ('HISTORY', 'Shift Register (${_history.length})'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
          children: [
            // Website Module Sub-Header (`POS Cash Shifts` + Bullion 24K status badge from `image-5.png`)
            Panel(
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE7F7EF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFB7E4C7)),
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          size: 19,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'POS Cash Shifts',
                              style: T.body(16, color: Pal.ink, w: FontWeight.w800),
                            ),
                            if (showroomContext.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                showroomContext,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.body(11.8, color: Pal.muted, w: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Cashier drawer custody, denomination counts, system tender totals and manager-approved variance posting.',
                    style: T.body(12.4, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(builder: (_) => const MaterialsRatesScreen()),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                      decoration: BoxDecoration(
                        color: bullionActive ? const Color(0xFFFBF3DC) : Pal.warnWash,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: bullionActive
                              ? const Color(0xFFE5CC82)
                              : Pal.warn.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.toll_rounded,
                            size: 14,
                            color: bullionActive ? Pal.goldDeep : Pal.warn,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              bullionActive
                                  ? 'Bullion 24K: Fine 999 Board Active'
                                  : 'Bullion 24K: Configure Rate Board',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.body(
                                11.5,
                                color: bullionActive ? Pal.goldDeep : Pal.warn,
                                w: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!, onRetry: _load),
            ],

            const SizedBox(height: 12),

            if (_loading && _history.isEmpty && !_isOpen) ...[
              const Panel(child: Skeleton(height: 130)),
              const SizedBox(height: 12),
              const Panel(child: Skeleton(height: 220)),
            ] else if (_tab == 'HISTORY') ...[
              _buildShiftHistory(fHistory),
            ] else if (!_isOpen) ...[
              _buildOpenShiftCard(),
            ] else ...[
              _buildActiveShiftView(),
            ],
          ],
        ),
      ),
    );
  }

  /// Exact mobile layout for `Open Cashier Shift (Drawer Custody)` (`image-5.png`).
  Widget _buildOpenShiftCard() {
    final floatStr = _countedTotalDecimal.toStringAsFixed(2);
    final notesCount = _totalNotesAndCoins;

    return Panel(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Open Cashier Shift (Drawer Custody)',
            style: T.body(15.5, color: Pal.ink, w: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Select cash drawer account and count initial cash float denominations to open counter.',
            style: T.body(12.2, color: Pal.muted),
          ),
          const SizedBox(height: 14),

          // 1. Business Date
          DatePickField(
            label: 'Business Date',
            controller: _businessDate,
          ),
          const SizedBox(height: 12),

          // 2. Cash Drawer Account (`Loading accounts...` while fetching, live accounts once loaded)
          if (_loading && _drawerAccounts.isEmpty) ...[
            const FieldLabel('Cash Drawer Account'),
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: Pal.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Pal.line),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Pal.goldDeep),
                  ),
                  const SizedBox(width: 10),
                  Text('Loading accounts...', style: T.body(13.5, color: Pal.muted)),
                ],
              ),
            ),
          ] else ...[
            LookupField(
              label: 'Cash Drawer Account',
              controller: _drawerAcctId,
              options: _drawerAccounts,
              hint: _drawerAccounts.isEmpty
                  ? 'No cash drawer account found — tap Accounting'
                  : 'Select cash drawer account',
            ),
            if (_drawerAccounts.isEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const DoubleEntryAccountingScreen(),
                    ),
                  ).then((_) => _load()),
                  icon: const Icon(Icons.account_balance_outlined, size: 16),
                  label: const Text('Create Cash Drawer Account in Accounting →'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),

          // 3. Opening Float (INR) — emerald-highlighted auto-sum box matching `image-5.png`
          Row(
            children: [
              const Expanded(child: FieldLabel('Opening Float (INR)')),
              if (notesCount > 0)
                Text(
                  '$notesCount notes/coins counted',
                  style: T.body(11.2, color: const Color(0xFF0F766E), w: FontWeight.w700),
                ),
            ],
          ),
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3FBF8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981), width: 1.3),
            ),
            child: Row(
              children: [
                Text(
                  floatStr,
                  style: T.mono(
                    16.5,
                    color: const Color(0xFF047857),
                    w: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  inr(floatStr),
                  style: T.body(
                    12.5,
                    color: const Color(0xFF047857),
                    w: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4. Evidence / Drawer Ref
          SaasField(
            label: 'Evidence / Drawer Ref',
            controller: _evidenceRef,
            hint: 'DRAWER-01 Morning Float Count',
          ),
          const SizedBox(height: 16),

          // 5. Opening Currency Denomination Breakdown (All 16 denominations in a clean 2-col phone grid)
          _buildDenominationSection(
            title: 'Opening Currency Denomination Breakdown',
          ),
          const SizedBox(height: 18),

          RoyalGoldButton(
            busy: _busy,
            icon: Icons.lock_open_rounded,
            label: 'Open shift',
            onPressed: _busy ? null : _openShift,
          ),
        ],
      ),
    );
  }

  /// Active Shift Custody + System Tender Totals + Closing Denomination Count + Manager Variance Approval.
  Widget _buildActiveShiftView() {
    final s = _activeShift!;
    final shiftCode = _pick(
      s,
      ['shiftNumber', 'documentNumber', 'code', 'counterName'],
      shortId('${s['id'] ?? 'SHIFT'}'),
    );
    final status = _pick(s, ['state', 'status'], 'OPEN');
    final openingFloat = _pick(
      s,
      ['openingFloatAmount', 'openingCash', 'openingBalance', 'openingFloat'],
      '0.00',
    );
    final cashTenders = _pick(
      s,
      ['systemCashReceipts', 'cashSalesAmount', 'cashTenderTotal', 'cashInAmount'],
      '0.00',
    );
    final nonCashTenders = _pick(
      s,
      ['systemNonCashReceipts', 'nonCashTenderTotal', 'cardUpiBankTotal'],
      '0.00',
    );
    final expectedCash = _expectedCashForActiveShift();
    final countedClosing = _countedTotalDecimal;
    final variance = (countedClosing - expectedCash).round(scale: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxuryHeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: EnterpriseBadge(
                        'Active Drawer · $shiftCode',
                        icon: Icons.lock_open_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Cashier Drawer Custody Active',
                style: T.display(21, color: Colors.white),
              ),
              const SizedBox(height: 3),
              Text(
                [
                  if (_pick(s, ['businessDate']).isNotEmpty)
                    'Business Date: ${fmtDate(_pick(s, ['businessDate']))}',
                  if (_pick(s, ['evidenceRef', 'remarks']).isNotEmpty)
                    _pick(s, ['evidenceRef', 'remarks']),
                ].isEmpty
                    ? 'System tender totals update automatically from posted counter settlements.'
                    : [
                        if (_pick(s, ['businessDate']).isNotEmpty)
                          'Business Date: ${fmtDate(_pick(s, ['businessDate']))}',
                        if (_pick(s, ['evidenceRef', 'remarks']).isNotEmpty)
                          _pick(s, ['evidenceRef', 'remarks']),
                      ].join(' · '),
                style: T.body(12.2, color: Colors.white70),
              ),
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _heroMetric('OPENING FLOAT', inr(openingFloat)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _heroMetric('EXPECTED CASH', inr(expectedCash.toStringAsFixed(2))),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _heroMetric('SYSTEM CASH IN', inr(cashTenders)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _heroMetric('UPI / CARD / BANK', inr(nonCashTenders)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        Panel(
          radius: 18,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _needsVarianceApproval
                    ? 'Manager Variance Review & Posting'
                    : 'Close Cashier Shift (Closing Denomination Count)',
                style: T.body(15.5, color: Pal.ink, w: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Count physical drawer notes & coins to compute closing balance and cash variance.',
                style: T.body(12.2, color: Pal.muted),
              ),
              const SizedBox(height: 14),

              // Live Counted vs Expected vs Variance strip
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: variance == Decimal.zero
                      ? const Color(0xFFF3FBF8)
                      : Pal.warnWash,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: variance == Decimal.zero
                        ? const Color(0xFF10B981)
                        : Pal.warn.withValues(alpha: 0.45),
                  ),
                ),
                child: Column(
                  children: [
                    KVRow('Counted Closing Cash', inr(countedClosing.toStringAsFixed(2)), bold: true),
                    KVRow('System Expected Cash', inr(expectedCash.toStringAsFixed(2))),
                    KVRow(
                      'Drawer Variance',
                      variance == Decimal.zero
                          ? '₹0.00 (Balanced)'
                          : variance > Decimal.zero
                              ? '+${inr(variance.toStringAsFixed(2))} (Excess)'
                              : '−${inr((-variance).toStringAsFixed(2))} (Shortage)',
                      bold: true,
                      valueColor: variance == Decimal.zero ? Pal.ok : Pal.warn,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              if (!_needsVarianceApproval) ...[
                _buildDenominationSection(
                  title: 'Closing Currency Denomination Breakdown',
                ),
                const SizedBox(height: 14),
                SaasField(
                  label: 'Closing Evidence / Handover Ref',
                  controller: _evidenceRef,
                  hint: 'DRAWER-01 Evening Cashup Count',
                ),
                const SizedBox(height: 10),
              ],

              SaasField(
                label: variance != Decimal.zero || _needsVarianceApproval
                    ? 'Manager Variance / Handover Reason'
                    : 'Reconciliation Notes (Optional)',
                controller: _varianceReason,
                hint: 'Verified physical cash count against POS tender register',
              ),

              if (variance != Decimal.zero || _needsVarianceApproval) ...[
                const SizedBox(height: 12),
                LookupField(
                  label: 'Posting Period (for variance journal)',
                  controller: _periodId,
                  options: _lk.openPeriods(),
                  optional: true,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Journal Series',
                  controller: _journalSeriesId,
                  options: _lk.seriesFor(const ['JOURNAL']),
                  optional: true,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Cash Over / Short Variance Account',
                  controller: _varianceAcctId,
                  options: _lk.accounts,
                  optional: true,
                ),
              ],

              const SizedBox(height: 16),
              if (!_needsVarianceApproval)
                RoyalGoldButton(
                  busy: _busy,
                  icon: Icons.lock_outline_rounded,
                  label: 'Close & Reconcile Shift',
                  onPressed: _busy ? null : _closeShift,
                ),
              if (_needsVarianceApproval) ...[
                RoyalGoldButton(
                  busy: _busy,
                  icon: Icons.verified_user_outlined,
                  label: 'Approve Variance & Post Shift',
                  onPressed: _busy ? null : _approveVariance,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: T.caps(9.2, color: Colors.white60)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.mono(14, color: Pal.goldSoft, w: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// Renders all 16 denominations from `image-5.png` in a responsive 2-column mobile grid.
  Widget _buildDenominationSection({required String title}) {
    final anyNonZero = _totalNotesAndCoins > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: T.body(13, color: Pal.ink, w: FontWeight.w800),
              ),
            ),
            if (anyNonZero)
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                ),
                onPressed: _resetDenominations,
                icon: const Icon(Icons.restart_alt_rounded, size: 15, color: Pal.goldDeep),
                label: Text(
                  'Reset',
                  style: T.body(11.8, color: Pal.goldDeep, w: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final d in _denominations)
                  SizedBox(
                    width: cellWidth,
                    child: _DenominationCell(
                      label: d.label,
                      unitValueStr: d.valueStr,
                      controller: _denomCtrls[d.key]!,
                      onStep: (delta) => _stepDenom(d.key, delta),
                      onChanged: () => setState(() {}),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildShiftHistory(List<Map<String, dynamic>> shifts) {
    if (shifts.isEmpty) {
      return const SaasEmptyBox(
        'No counter POS shift records yet. Open a cashier shift from the POS Cash Shifts tab.',
      );
    }
    return Column(
      children: [
        for (final s in shifts)
          LuxuryRecordCard(
            icon: Icons.payments_outlined,
            code: _pick(
              s,
              ['shiftNumber', 'documentNumber', 'code', 'counterName'],
              shortId('${s['id'] ?? 'SHIFT'}'),
            ),
            status: _pick(s, ['state', 'status'], 'CLOSED'),
            lines: [
              if (_pick(s, ['businessDate', 'openedAt']).isNotEmpty)
                ('Business Date', fmtDate(_pick(s, ['businessDate', 'openedAt']))),
              if (_pick(s, ['evidenceRef', 'remarks']).isNotEmpty)
                ('Evidence / Ref', _pick(s, ['evidenceRef', 'remarks'])),
              (
                'Opening Float',
                inr(_pick(s, ['openingFloatAmount', 'openingCash', 'openingBalance'], '0.00')),
              ),
              if (_pick(s, ['closingCash', 'closingFloatAmount', 'closingBalance']).isNotEmpty)
                (
                  'Closing Counted',
                  inr(_pick(s, ['closingCash', 'closingFloatAmount', 'closingBalance'], '0.00')),
                ),
              if (_pick(s, ['varianceAmount', 'cashVariance']).isNotEmpty)
                ('Variance', inr(_pick(s, ['varianceAmount', 'cashVariance'], '0.00'))),
            ],
            amountLabel: _pick(s, ['closingCash', 'closingFloatAmount']).isNotEmpty
                ? 'Closing Cash'
                : 'Opening Float',
            amountValue: inr(
              _pick(
                s,
                [
                  'closingCash',
                  'closingFloatAmount',
                  'closingBalance',
                  'openingFloatAmount',
                  'openingCash',
                  'openingBalance',
                ],
                '0.00',
              ),
            ),
          ),
      ],
    );
  }
}

class _DenominationCell extends StatelessWidget {
  const _DenominationCell({
    required this.label,
    required this.unitValueStr,
    required this.controller,
    required this.onStep,
    required this.onChanged,
  });

  final String label;
  final String unitValueStr;
  final TextEditingController controller;
  final ValueChanged<int> onStep;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final qty = int.tryParse(controller.text.trim()) ?? 0;
    final active = qty > 0;
    final lineTotal = active
        ? (Decimal.parse(unitValueStr) * Decimal.fromInt(qty)).round(scale: 2)
        : Decimal.zero;

    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFFFFCF3) : Pal.card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: active ? Pal.gold.withValues(alpha: 0.65) : Pal.line,
          width: active ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(
                    11.5,
                    color: active ? Pal.goldDeep : Pal.muted,
                    w: FontWeight.w700,
                  ),
                ),
              ),
              if (active)
                Flexible(
                  child: Text(
                    inr(lineTotal.toStringAsFixed(2), paise: unitValueStr.contains('.')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.mono(10.5, color: Pal.goldDeep, w: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Pal.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Pal.line),
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                  onTap: qty > 0 ? () => onStep(-1) : null,
                  child: SizedBox(
                    width: 30,
                    height: 36,
                    child: Icon(
                      Icons.remove_rounded,
                      size: 15,
                      color: qty > 0 ? Pal.ink : Pal.muted.withValues(alpha: 0.4),
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    style: T.mono(
                      13.5,
                      color: active ? Pal.ink : Pal.muted,
                      w: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onTap: () {
                      if (controller.text == '0') {
                        controller.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: controller.text.length,
                        );
                      }
                    },
                    onChanged: (_) => onChanged(),
                  ),
                ),
                InkWell(
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                  onTap: () => onStep(1),
                  child: const SizedBox(
                    width: 30,
                    height: 36,
                    child: Icon(Icons.add_rounded, size: 15, color: Pal.goldDeep),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
