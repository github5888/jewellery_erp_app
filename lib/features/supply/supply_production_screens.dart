import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

const _supplyUuid = Uuid();

// ---------------------------------------------------------------------------
// 1. CUSTOM ORDERS (`/custom-orders` — `image-13.png`)
// ---------------------------------------------------------------------------

class CustomOrdersScreen extends StatefulWidget {
  const CustomOrdersScreen({super.key});
  @override
  State<CustomOrdersScreen> createState() => _CustomOrdersScreenState();
}

class _CustomOrdersScreenState extends State<CustomOrdersScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _showForm = true;
  bool _formInitialized = false;

  List<Map<String, dynamic>> _orders = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // All 21 exact fields of `New bespoke order and specification v1` (`image-13.png`)
  final _partyId = TextEditingController();
  final _orderDate = TextEditingController(text: todayIso());
  final _promisedDate = TextEditingController();
  final _designCode = TextEditingController();
  final _desc = TextEditingController();
  final _size = TextEditingController();
  final _metalId = TextEditingController();
  final _purityId = TextEditingController();
  final _grossWt = TextEditingController();
  final _metalWt = TextEditingController();
  final _fineWt = TextEditingController();
  final _toleranceWt = TextEditingController();
  final _metalValue = TextEditingController();
  final _making = TextEditingController();
  final _stone = TextEditingController();
  final _other = TextEditingController();
  final _discount = TextEditingController();
  final _taxable = TextEditingController();
  final _tax = TextEditingController();
  final _total = TextEditingController();
  final _requiredDeposit = TextEditingController();
  final _seriesId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _search,
      _partyId,
      _orderDate,
      _promisedDate,
      _designCode,
      _desc,
      _size,
      _metalId,
      _purityId,
      _grossWt,
      _metalWt,
      _fineWt,
      _toleranceWt,
      _metalValue,
      _making,
      _stone,
      _other,
      _discount,
      _taxable,
      _tax,
      _total,
      _requiredDeposit,
      _seriesId,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _pick(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty && '$v' != 'null') return '$v';
    }
    return fallback;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/custom-orders'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeMaterials: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final orders = asList(res[0], keys: const ['orders', 'customOrders', 'items']);
      final lk = res[1] as WorkspaceLookup;

      if (_metalId.text.isEmpty && lk.metals.isNotEmpty) {
        _metalId.text = lk.metals.first.id;
        final p = lk.puritiesForMetal(_metalId.text);
        if (p.isNotEmpty) _purityId.text = p.first.id;
      }
      if (_seriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['CUSTOM', 'ORDER']);
        if (s.isNotEmpty) _seriesId.text = s.first.id;
      }
      if (!_formInitialized) {
        _showForm = orders.isEmpty;
        _formInitialized = true;
      }

      setState(() {
        _orders = orders;
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Auto-computes `Fine 999 g` & live `Metal value` from `Metal weight g` + selected `Purity`,
  /// then updates `Taxable`, `Tax` (3% GST), and `Total`.
  void _recalcFromWeights() {
    final mw = tryDec(_metalWt.text.trim());
    if (mw != null && mw > Decimal.zero) {
      final purityOpt =
          _lk.purityGrades.where((p) => p.id == _purityId.text.trim()).firstOrNull;
      final fineness = tryDec(purityOpt?.raw['finenessPerThousand']) ?? Decimal.fromInt(916);
      final fine = (mw * fineness * Decimal.parse('0.001')).round(scale: 6);
      _fineWt.text = fine.toStringAsFixed(6);

      // Estimate live metal value from active bullion rate board if available
      final rates = context.read<RatesController>();
      final metalCode = '${purityOpt?.raw['metalCode'] ?? 'GOLD'}';
      final finCode = fineness.round().toString();
      final quote = rates.find(metalCode, finCode) ?? rates.find(metalCode, '999');
      if (quote != null && decOrZero(quote.sell) > Decimal.zero) {
        final mv = (mw * decOrZero(quote.sell)).round(scale: 2);
        _metalValue.text = mv.toStringAsFixed(2);
      }
    }
    _recalcTotals();
  }

  void _recalcTotals() {
    final mv = decOrZero(_metalValue.text);
    final mk = decOrZero(_making.text);
    final st = decOrZero(_stone.text);
    final ot = decOrZero(_other.text);
    final disc = decOrZero(_discount.text);
    final rawTaxable = mv + mk + st + ot - disc;
    final taxable = rawTaxable < Decimal.zero ? Decimal.zero : rawTaxable.round(scale: 2);
    if (taxable > Decimal.zero ||
        _metalValue.text.isNotEmpty ||
        _making.text.isNotEmpty ||
        _stone.text.isNotEmpty) {
      final tax = (taxable * Decimal.parse('0.03')).round(scale: 2);
      final total = (taxable + tax).round(scale: 2);
      _taxable.text = taxable.toStringAsFixed(2);
      _tax.text = tax.toStringAsFixed(2);
      _total.text = total.toStringAsFixed(2);
    }
    setState(() {});
  }

  Future<void> _createOrder() async {
    if (_partyId.text.trim().isEmpty) {
      setState(() => _error = 'Select a Customer before creating a custom order.');
      return;
    }
    if (_promisedDate.text.trim().isEmpty) {
      setState(() => _error = 'Select the Promised date for delivery.');
      return;
    }
    if (_desc.text.trim().length < 3) {
      setState(() => _error = 'Enter Description (min 3 characters).');
      return;
    }
    if (_metalId.text.trim().isEmpty || _purityId.text.trim().isEmpty) {
      setState(() => _error = 'Select both Metal and Purity.');
      return;
    }
    if (!isValidWeight(_grossWt.text) || !isValidWeight(_metalWt.text)) {
      setState(() => _error = 'Enter valid Gross weight g and Metal weight g.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final grossStr = normWeight6(_grossWt.text);
    final metalWtStr = normWeight6(_metalWt.text);
    final fineStr = normWeight6(_fineWt.text.trim().isEmpty ? _metalWt.text : _fineWt.text);
    final tolStr = normWeight6(_toleranceWt.text.trim().isEmpty ? '0' : _toleranceWt.text);
    final metalValStr = normAmount(_metalValue.text.trim().isEmpty ? '0' : _metalValue.text);
    final makingStr = normAmount(_making.text.trim().isEmpty ? '0' : _making.text);
    final stoneStr = normAmount(_stone.text.trim().isEmpty ? '0' : _stone.text);
    final otherStr = normAmount(_other.text.trim().isEmpty ? '0' : _other.text);
    final discountStr = normAmount(_discount.text.trim().isEmpty ? '0' : _discount.text);
    final taxableStr = normAmount(_taxable.text.trim().isEmpty ? '0' : _taxable.text);
    final taxStr = normAmount(_tax.text.trim().isEmpty ? '0' : _tax.text);
    final totalStr = normAmount(_total.text.trim().isEmpty ? '0' : _total.text);
    final depositStr = normAmount(
      _requiredDeposit.text.trim().isEmpty ? '0' : _requiredDeposit.text,
    );

    final specMap = <String, dynamic>{
      if (_designCode.text.trim().isNotEmpty) 'designCode': _designCode.text.trim(),
      'description': _desc.text.trim(),
      if (_size.text.trim().isNotEmpty) 'size': _size.text.trim(),
      'metalId': _metalId.text.trim(),
      'purityGradeId': _purityId.text.trim(),
      'grossWeightGrams': grossStr,
      'metalWeightGrams': metalWtStr,
      'fineWeightGrams': fineStr,
      'toleranceGrams': tolStr,
      'metalValue': metalValStr,
      'makingAmount': makingStr,
      'stoneAmount': stoneStr,
      'otherAmount': otherStr,
      'discountAmount': discountStr,
      'taxableAmount': taxableStr,
      'taxAmount': taxStr,
      'totalAmount': totalStr,
    };

    final api = context.read<ApiClient>();
    try {
      try {
        await api.post(
          '/custom-orders',
          idempotencyKey: _supplyUuid.v4(),
          body: {
            'customerPartyId': _partyId.text.trim(),
            if (_seriesId.text.trim().isNotEmpty) 'documentSeriesId': _seriesId.text.trim(),
            'orderDate': _orderDate.text.trim().isEmpty ? todayIso() : _orderDate.text.trim(),
            'promisedDate': _promisedDate.text.trim(),
            'requiredDepositAmount': depositStr,
            'advanceAmount': depositStr,
            'estimatedWeightGrams': grossStr,
            'quotedMakingAmount': makingStr,
            'currency': 'INR',
            ...specMap,
            'specification': specMap,
            'reason': 'Created bespoke customer order and specification v1.',
          },
        );
      } on ApiException catch (e) {
        if (e.status == 400) {
          // Strict schema fallback (nested specification v1 only)
          await api.post(
            '/custom-orders',
            idempotencyKey: _supplyUuid.v4(),
            body: {
              'customerPartyId': _partyId.text.trim(),
              'orderDate': _orderDate.text.trim().isEmpty ? todayIso() : _orderDate.text.trim(),
              'promisedDate': _promisedDate.text.trim(),
              'requiredDepositAmount': depositStr,
              'currency': 'INR',
              'specification': specMap,
            },
          );
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      for (final c in [
        _designCode,
        _desc,
        _size,
        _grossWt,
        _metalWt,
        _fineWt,
        _toleranceWt,
        _metalValue,
        _making,
        _stone,
        _other,
        _discount,
        _taxable,
        _tax,
        _total,
        _requiredDeposit,
      ]) {
        c.clear();
      }
      setState(() => _showForm = false);
      toast(context, 'Custom order & specification v1 created.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showOrderLifecycleSheet(Map<String, dynamic> order) async {
    final id = '${order['id'] ?? ''}';
    if (id.isEmpty) return;
    final curState = _pick(order, ['state', 'status'], 'DRAFT').toUpperCase();
    String stage = curState == 'DRAFT'
        ? 'APPROVE'
        : curState.contains('QC') || curState == 'BILLED'
            ? 'DELIVER'
            : 'QC';
    final reasonCtrl = TextEditingController();
    final ackCtrl = TextEditingController();
    final depAmtCtrl = TextEditingController(
      text: _pick(order, ['requiredDepositAmount', 'advanceAmount'], '0.00'),
    );
    bool sheetBusy = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Order Lifecycle · ${_pick(order, ['documentNumber', 'orderNumber'], shortId(id))}',
                style: T.display(20),
              ),
              const SizedBox(height: 4),
              Text(
                'Maker-checker approval, advance deposit, QC verification, and acknowledged delivery.',
                style: T.body(12.2, color: Pal.muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in const [
                    ('APPROVE', 'Approve Spec'),
                    ('ADVANCE', 'Record Deposit'),
                    ('QC', 'Pass Production QC'),
                    ('DELIVER', 'Acknowledge Delivery'),
                  ])
                    ChoiceChip(
                      label: Text(opt.$2),
                      selected: stage == opt.$1,
                      showCheckmark: false,
                      selectedColor: Pal.goldWash,
                      onSelected: (_) => setLocal(() => stage = opt.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (stage == 'ADVANCE') ...[
                SaasField(
                  label: 'Deposit Amount (INR)',
                  controller: depAmtCtrl,
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
              ],
              if (stage == 'DELIVER') ...[
                SaasField(
                  label: 'Customer Acknowledgement Ref',
                  controller: ackCtrl,
                  hint: 'Signed delivery challan / OTP ref',
                ),
                const SizedBox(height: 10),
              ],
              SaasField(
                label: 'Authorization Reason (min 5 chars)',
                controller: reasonCtrl,
                hint: 'Enter approval / QC / delivery note',
                maxLines: 2,
              ),
              if (sheetErr != null) ...[
                const SizedBox(height: 10),
                Text(sheetErr!, style: T.body(12.5, color: Pal.danger, w: FontWeight.w700)),
              ],
              const SizedBox(height: 14),
              RoyalGoldButton(
                busy: sheetBusy,
                label: stage == 'APPROVE'
                    ? 'Approve Specification'
                    : stage == 'ADVANCE'
                        ? 'Post Advance Deposit'
                        : stage == 'QC'
                            ? 'Confirm Production & QC'
                            : 'Confirm Acknowledged Delivery',
                onPressed: sheetBusy
                    ? null
                    : () async {
                        if (reasonCtrl.text.trim().length < 5) {
                          setLocal(() => sheetErr = 'Enter reason (min 5 chars).');
                          return;
                        }
                        setLocal(() {
                          sheetBusy = true;
                          sheetErr = null;
                        });
                        final api = context.read<ApiClient>();
                        final ver = asInt(order['version'], fallback: 1);
                        try {
                          final paths = switch (stage) {
                            'APPROVE' => ['/custom-orders/$id/approve'],
                            'ADVANCE' => [
                                '/custom-orders/$id/advances',
                                '/custom-orders/$id/deposits',
                              ],
                            'QC' => [
                                '/custom-orders/$id/qc',
                                '/custom-orders/$id/complete-qc',
                              ],
                            _ => [
                                '/custom-orders/$id/deliver',
                                '/custom-orders/$id/delivery',
                              ],
                          };
                          final payload = <String, dynamic>{
                            'expectedVersion': ver,
                            'reason': reasonCtrl.text.trim(),
                            if (stage == 'ADVANCE') 'amount': normAmount(depAmtCtrl.text),
                            if (stage == 'QC') 'qcState': 'PASSED',
                            if (stage == 'DELIVER') ...{
                              'deliveryDate': todayIso(),
                              if (ackCtrl.text.trim().isNotEmpty)
                                'customerAcknowledgementRef': ackCtrl.text.trim(),
                            },
                          };
                          for (var i = 0; i < paths.length; i++) {
                            try {
                              await api.post(
                                paths[i],
                                idempotencyKey: _supplyUuid.v4(),
                                body: payload,
                              );
                              break;
                            } on ApiException catch (e) {
                              if ((e.status != 404 && e.code != 'HTTP_ERROR') ||
                                  i == paths.length - 1) {
                                rethrow;
                              }
                            }
                          }
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          toast(context, 'Custom order updated.');
                          await _load();
                        } on ApiException catch (e) {
                          setLocal(() => sheetErr = e.message);
                        } finally {
                          if (ctx.mounted) setLocal(() => sheetBusy = false);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
    ackCtrl.dispose();
    depAmtCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999');
    final bullionActive = gold999 != null && decOrZero(gold999.sell) > Decimal.zero;
    final showroomContext = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    final q = _search.text.trim().toLowerCase();
    bool isDone(Map<String, dynamic> o) {
      final s = '${o['state'] ?? o['status'] ?? ''}'.toUpperCase();
      return s == 'DELIVERED' || s == 'COMPLETED' || s == 'CLOSED';
    }

    final openCnt = _orders.where((o) => !isDone(o)).length;
    final doneCnt = _orders.where(isDone).length;
    final filtered = _orders.where((o) {
      if (_filter == 'OPEN' && isDone(o)) return false;
      if (_filter == 'DELIVERED' && !isDone(o)) return false;
      if (q.isEmpty) return true;
      final spec = asMap(o['specification']);
      final hay =
          '${o['documentNumber'] ?? ''} ${o['orderNumber'] ?? ''} ${asMap(o['customer'])['displayName'] ?? ''} ${o['description'] ?? spec['description'] ?? ''} ${o['designCode'] ?? spec['designCode'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    final purities = _lk.puritiesForMetal(_metalId.text.trim());

    return LuxuryModuleScaffold(
      title: 'Custom Orders',
      icon: Icons.diamond_outlined,
      searchController: _search,
      searchHint: 'Search order #, design code, customer or state...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: 'Refresh custom orders',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${_orders.length})'),
          ('OPEN', 'In Progress ($openCnt)'),
          ('DELIVERED', 'Delivered ($doneCnt)'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'New bespoke order and specification v1',
        onPressed: () => setState(() => _showForm = !_showForm),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 88),
          children: [
            // Website Sub-Header (`Custom Orders` from `image-13.png`)
            Panel(
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBF3DC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE7CF8B)),
                        ),
                        child: const Icon(
                          Icons.diamond_outlined,
                          size: 19,
                          color: Pal.goldDeep,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Custom Orders',
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
                    'Versioned customer specifications, maker-checker approval, advance liability, production/QC, billing and acknowledged delivery.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const MaterialsRatesScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                                size: 13.5,
                                color: bullionActive ? Pal.goldDeep : Pal.warn,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                bullionActive
                                    ? 'Bullion 24K: Fine 999 Board Active'
                                    : 'Bullion 24K: Configure Rate Board',
                                style: T.body(
                                  11.2,
                                  color: bullionActive ? Pal.goldDeep : Pal.warn,
                                  w: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ActionChip(
                        avatar: Icon(
                          _showForm ? Icons.expand_less_rounded : Icons.add_rounded,
                          size: 16,
                          color: Pal.goldDeep,
                        ),
                        label: Text(
                          'New bespoke order v1',
                          style: T.body(11.8, color: Pal.goldDeep, w: FontWeight.w700),
                        ),
                        backgroundColor: _showForm ? Pal.goldWash : Pal.card,
                        side: BorderSide(color: Pal.gold.withValues(alpha: 0.45)),
                        onPressed: () => setState(() => _showForm = !_showForm),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!, onRetry: _load),
            ],

            // `New bespoke order and specification v1` (`image-13.png` — all 21 fields)
            if (_showForm) ...[
              const SizedBox(height: 12),
              SaasFormCard(
                title: 'New bespoke order and specification v1',
                trailing: _orders.isNotEmpty
                    ? TextButton(
                        onPressed: () => setState(() => _showForm = false),
                        child: const Text('Hide'),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Customer, Order date, Promised date, Design code
                    LookupField(
                      label: 'Customer',
                      controller: _partyId,
                      options: _lk.partiesByRole('CUSTOMER'),
                      hint: 'Select customer',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DatePickField(
                            label: 'Order date',
                            controller: _orderDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DatePickField(
                            label: 'Promised date',
                            controller: _promisedDate,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Design code',
                            controller: _designCode,
                            hint: 'Design code',
                            mono: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Size',
                            controller: _size,
                            hint: 'Size',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Description',
                      controller: _desc,
                      hint: 'Description',
                    ),
                    const SizedBox(height: 10),

                    // 2. Metal & Purity
                    Row(
                      children: [
                        Expanded(
                          child: LookupField(
                            label: 'Metal',
                            controller: _metalId,
                            options: _lk.metals,
                            hint: 'Select metal',
                            onSelected: (opt) {
                              setState(() {
                                _purityId.clear();
                                if (opt != null) {
                                  final p = _lk.puritiesForMetal(opt.id);
                                  if (p.isNotEmpty) _purityId.text = p.first.id;
                                }
                              });
                              _recalcFromWeights();
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: LookupField(
                            label: 'Purity',
                            controller: _purityId,
                            options: purities.isNotEmpty ? purities : _lk.purityGrades,
                            hint: 'Select purity',
                            onSelected: (_) => _recalcFromWeights(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 3. Gross weight g, Metal weight g, Fine 999 g, Tolerance g
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FieldLabel('Gross weight g'),
                              TextField(
                                controller: _grossWt,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                style: T.mono(13.5),
                                decoration: const InputDecoration(hintText: '0.000'),
                                onChanged: (v) {
                                  if (_metalWt.text.trim().isEmpty) {
                                    _metalWt.text = v;
                                    _recalcFromWeights();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const FieldLabel('Metal weight g'),
                              TextField(
                                controller: _metalWt,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                style: T.mono(13.5),
                                decoration: const InputDecoration(hintText: '0.000'),
                                onChanged: (_) => _recalcFromWeights(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Fine 999 g',
                            controller: _fineWt,
                            hint: '0.000000',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Tolerance g',
                            controller: _toleranceWt,
                            hint: '0.000',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 4. Metal value, Making, Stone, Other
                    Row(
                      children: [
                        Expanded(
                          child: _amountInputField('Metal value', _metalValue),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _amountInputField('Making', _making),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _amountInputField('Stone', _stone),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _amountInputField('Other', _other),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // 5. Discount, Taxable, Tax, Total, Required deposit
                    Row(
                      children: [
                        Expanded(
                          child: _amountInputField('Discount', _discount),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Taxable',
                            controller: _taxable,
                            hint: '0.00',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Tax',
                            controller: _tax,
                            hint: '0.00',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Total',
                            controller: _total,
                            hint: '0.00',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Required deposit',
                      controller: _requiredDeposit,
                      hint: '0.00',
                      mono: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 16),
                    RoyalGoldButton(
                      busy: _busy,
                      label: 'Create custom order',
                      onPressed: _busy ? null : _createOrder,
                    ),
                  ],
                ),
              ),
            ],

            const SectionLabel('Bespoke Orders Register'),
            if (_loading && _orders.isEmpty)
              const Panel(child: Skeleton(height: 110))
            else if (filtered.isEmpty)
              const SaasEmptyBox('No custom orders yet.')
            else
              for (final o in filtered)
                Builder(builder: (_) {
                  final spec = asMap(o['specification']);
                  final desc = _pick(o, ['description'], _pick(spec, ['description']));
                  final design = _pick(o, ['designCode'], _pick(spec, ['designCode']));
                  final gross = _pick(
                    o,
                    ['grossWeightGrams', 'estimatedWeightGrams'],
                    _pick(spec, ['grossWeightGrams'], '0'),
                  );
                  final total = _pick(
                    o,
                    ['totalAmount'],
                    _pick(spec, ['totalAmount'], _pick(o, ['requiredDepositAmount', 'advanceAmount'], '0.00')),
                  );
                  final deposit = _pick(
                    o,
                    ['requiredDepositAmount', 'advanceAmount'],
                    '0.00',
                  );
                  return LuxuryRecordCard(
                    icon: Icons.diamond_outlined,
                    code:
                        '${_pick(o, ['documentNumber', 'orderNumber'], shortId('${o['id']}'))}${design.isNotEmpty ? ' · $design' : ''}',
                    status: _pick(o, ['state', 'status'], 'DRAFT'),
                    lines: [
                      ('Customer', '${asMap(o['customer'])['displayName'] ?? '-'}'),
                      if (desc.isNotEmpty) ('Specification', desc),
                      (
                        'Promised Date',
                        fmtDate(_pick(o, ['promisedDate'])),
                      ),
                      ('Gross Weight', grams(gross)),
                      ('Required Deposit', inr(deposit)),
                    ],
                    amountLabel: 'Order Total',
                    amountValue: inr(total),
                    actions: [
                      GoldButton(
                        label: 'Manage Order',
                        compact: true,
                        onPressed: () => _showOrderLifecycleSheet(o),
                      ),
                    ],
                  );
                }),
          ],
        ),
      ),
    );
  }

  Widget _amountInputField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(label),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: T.mono(13.5),
          decoration: const InputDecoration(hintText: '0.00'),
          onChanged: (_) => _recalcTotals(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 2. REPAIRS & CUSTODY (`/repairs` — `image-14.png`)
// ---------------------------------------------------------------------------

class RepairsCustodyScreen extends StatefulWidget {
  const RepairsCustodyScreen({super.key});
  @override
  State<RepairsCustodyScreen> createState() => _RepairsCustodyScreenState();
}

class _RepairCustodyItemDraft {
  _RepairCustodyItemDraft({String defaultMetalId = '', String defaultPurityId = ''})
      : descCtrl = TextEditingController(),
        metalIdCtrl = TextEditingController(text: defaultMetalId),
        purityIdCtrl = TextEditingController(text: defaultPurityId),
        grossWtCtrl = TextEditingController(),
        metalWtCtrl = TextEditingController(),
        fineWtCtrl = TextEditingController(),
        stoneWtCtrl = TextEditingController(text: '0.000000'),
        marksCtrl = TextEditingController();

  final TextEditingController descCtrl;
  final TextEditingController metalIdCtrl;
  final TextEditingController purityIdCtrl;
  final TextEditingController grossWtCtrl;
  final TextEditingController metalWtCtrl;
  final TextEditingController fineWtCtrl;
  final TextEditingController stoneWtCtrl;
  final TextEditingController marksCtrl;

  void dispose() {
    descCtrl.dispose();
    metalIdCtrl.dispose();
    purityIdCtrl.dispose();
    grossWtCtrl.dispose();
    metalWtCtrl.dispose();
    fineWtCtrl.dispose();
    stoneWtCtrl.dispose();
    marksCtrl.dispose();
  }
}

class _RepairsCustodyScreenState extends State<RepairsCustodyScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _showForm = true;
  bool _formInitialized = false;

  List<Map<String, dynamic>> _repairs = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // All 11 header fields of `New repair intake` (`image-14.png`)
  final _partyId = TextEditingController();
  final _custodyLocId = TextEditingController();
  final _seriesId = TextEditingController();
  final _evidenceFileUuid = TextEditingController();
  final _intakeDate = TextEditingController(text: todayIso());
  final _promisedDate = TextEditingController();
  final _itemSummary = TextEditingController();
  final _complaint = TextEditingController();
  final _visibleCondition = TextEditingController();
  final _photoEvidenceRef = TextEditingController();
  final _customerAck = TextEditingController();

  // Dynamic `Custody item 1..N` (`+ Add custody item` in `image-14.png`)
  final List<_RepairCustodyItemDraft> _items = [_RepairCustodyItemDraft()];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final it in _items) {
      it.dispose();
    }
    for (final c in [
      _search,
      _partyId,
      _custodyLocId,
      _seriesId,
      _evidenceFileUuid,
      _intakeDate,
      _promisedDate,
      _itemSummary,
      _complaint,
      _visibleCondition,
      _photoEvidenceRef,
      _customerAck,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _pick(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty && '$v' != 'null') return '$v';
    }
    return fallback;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/repairs'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeMaterials: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final repairs = asList(res[0], keys: const ['repairs', 'repairOrders', 'jobs', 'items']);
      final lk = res[1] as WorkspaceLookup;

      final custodyLocs = lk.locationsByType(
        const ['CUSTOMER_CUSTODY', 'QUARANTINE', 'VAULT'],
      );
      if (_custodyLocId.text.isEmpty && custodyLocs.isNotEmpty) {
        _custodyLocId.text = custodyLocs.first.id;
      }
      final repSeries = lk.seriesFor(const ['REPAIR', 'CUSTODY']);
      if (_seriesId.text.isEmpty && repSeries.isNotEmpty) {
        _seriesId.text = repSeries.first.id;
      }
      for (final it in _items) {
        if (it.metalIdCtrl.text.isEmpty && lk.metals.isNotEmpty) {
          it.metalIdCtrl.text = lk.metals.first.id;
          final p = lk.puritiesForMetal(it.metalIdCtrl.text);
          if (p.isNotEmpty) it.purityIdCtrl.text = p.first.id;
        }
      }
      if (!_formInitialized) {
        _showForm = repairs.isEmpty;
        _formInitialized = true;
      }

      setState(() {
        _repairs = repairs;
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recalcItemFine(_RepairCustodyItemDraft item) {
    final mw = tryDec(item.metalWtCtrl.text.trim());
    if (mw != null && mw > Decimal.zero) {
      final pOpt = _lk.purityGrades
          .where((p) => p.id == item.purityIdCtrl.text.trim())
          .firstOrNull;
      final fineness = tryDec(pOpt?.raw['finenessPerThousand']) ?? Decimal.fromInt(916);
      final fine = (mw * fineness * Decimal.parse('0.001')).round(scale: 6);
      item.fineWtCtrl.text = fine.toStringAsFixed(6);
      setState(() {});
    }
  }

  Future<void> _recordIntake() async {
    if (_partyId.text.trim().isEmpty) {
      setState(() => _error = 'Select a Customer (Customer UUID).');
      return;
    }
    if (_custodyLocId.text.trim().isEmpty) {
      setState(() => _error = 'Select a Custody location (Custody location UUID).');
      return;
    }
    if (_promisedDate.text.trim().isEmpty) {
      setState(() => _error = 'Select the Promised date.');
      return;
    }
    if (_itemSummary.text.trim().length < 2 || _complaint.text.trim().length < 2) {
      setState(() => _error = 'Enter Item summary and Customer complaint.');
      return;
    }
    for (final it in _items) {
      if (it.descCtrl.text.trim().length < 2 ||
          it.metalIdCtrl.text.trim().isEmpty ||
          it.purityIdCtrl.text.trim().isEmpty ||
          !isValidWeight(it.grossWtCtrl.text) ||
          !isValidWeight(it.metalWtCtrl.text)) {
        setState(
          () => _error =
              'Complete Description, Metal UUID, Purity UUID, Gross weight g, and Metal weight g for every custody item.',
        );
        return;
      }
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    final builtItems = [
      for (final it in _items)
        {
          'description': it.descCtrl.text.trim(),
          'metalId': it.metalIdCtrl.text.trim(),
          'purityGradeId': it.purityIdCtrl.text.trim(),
          'grossWeightGrams': normWeight6(it.grossWtCtrl.text),
          'metalWeightGrams': normWeight6(it.metalWtCtrl.text),
          'fineWeightGrams': normWeight6(
            it.fineWtCtrl.text.trim().isEmpty ? it.metalWtCtrl.text : it.fineWtCtrl.text,
          ),
          'stoneWeightGrams': normWeight6(
            it.stoneWtCtrl.text.trim().isEmpty ? '0' : it.stoneWtCtrl.text,
          ),
          if (it.marksCtrl.text.trim().isNotEmpty)
            'distinguishingMarks': it.marksCtrl.text.trim(),
        },
    ];

    final totalGross = _items.fold<Decimal>(
      Decimal.zero,
      (s, it) => s + decOrZero(it.grossWtCtrl.text),
    );

    final body = <String, dynamic>{
      'customerPartyId': _partyId.text.trim(),
      'custodyLocationId': _custodyLocId.text.trim(),
      if (_seriesId.text.trim().isNotEmpty) 'intakeSeriesId': _seriesId.text.trim(),
      if (_seriesId.text.trim().isNotEmpty) 'documentSeriesId': _seriesId.text.trim(),
      if (_evidenceFileUuid.text.trim().isNotEmpty)
        'evidenceFileId': _evidenceFileUuid.text.trim(),
      'intakeDate': _intakeDate.text.trim().isEmpty ? todayIso() : _intakeDate.text.trim(),
      'promisedDate': _promisedDate.text.trim(),
      'itemSummary': _itemSummary.text.trim(),
      'articleDescription': _itemSummary.text.trim(),
      'customerComplaint': _complaint.text.trim(),
      if (_visibleCondition.text.trim().isNotEmpty)
        'visibleCondition': _visibleCondition.text.trim(),
      if (_visibleCondition.text.trim().isNotEmpty)
        'conditionNotes': _visibleCondition.text.trim(),
      if (_photoEvidenceRef.text.trim().isNotEmpty)
        'photoEvidenceRef': _photoEvidenceRef.text.trim(),
      if (_customerAck.text.trim().isNotEmpty)
        'customerAcknowledgementRef': _customerAck.text.trim(),
      'receivedGrossWeightGrams': totalGross.toStringAsFixed(6),
      'items': builtItems,
      'custodyItems': builtItems,
      'reason': 'Recorded customer repair custody intake with itemized weight verification.',
    };

    final api = context.read<ApiClient>();
    try {
      try {
        await api.post(
          '/repairs',
          idempotencyKey: _supplyUuid.v4(),
          body: body,
        );
      } on ApiException catch (e) {
        if (e.status == 404 || e.code == 'HTTP_ERROR') {
          await api.post(
            '/repairs/intakes',
            idempotencyKey: _supplyUuid.v4(),
            body: body,
          );
        } else if (e.status == 400) {
          // Strict-schema retry matching exact `image-14.png` field names
          await api.post(
            '/repairs',
            idempotencyKey: _supplyUuid.v4(),
            body: {
              'customerPartyId': _partyId.text.trim(),
              'custodyLocationId': _custodyLocId.text.trim(),
              if (_seriesId.text.trim().isNotEmpty) 'intakeSeriesId': _seriesId.text.trim(),
              if (_evidenceFileUuid.text.trim().isNotEmpty)
                'evidenceFileId': _evidenceFileUuid.text.trim(),
              'intakeDate':
                  _intakeDate.text.trim().isEmpty ? todayIso() : _intakeDate.text.trim(),
              'promisedDate': _promisedDate.text.trim(),
              'itemSummary': _itemSummary.text.trim(),
              'customerComplaint': _complaint.text.trim(),
              if (_visibleCondition.text.trim().isNotEmpty)
                'visibleCondition': _visibleCondition.text.trim(),
              if (_photoEvidenceRef.text.trim().isNotEmpty)
                'photoEvidenceRef': _photoEvidenceRef.text.trim(),
              if (_customerAck.text.trim().isNotEmpty)
                'customerAcknowledgement': _customerAck.text.trim(),
              'items': builtItems,
            },
          );
        } else {
          rethrow;
        }
      }

      if (!mounted) return;
      _itemSummary.clear();
      _complaint.clear();
      _visibleCondition.clear();
      _photoEvidenceRef.clear();
      _customerAck.clear();
      _evidenceFileUuid.clear();
      for (var i = _items.length - 1; i >= 1; i--) {
        _items[i].dispose();
        _items.removeAt(i);
      }
      _items.first.descCtrl.clear();
      _items.first.grossWtCtrl.clear();
      _items.first.metalWtCtrl.clear();
      _items.first.fineWtCtrl.clear();
      _items.first.stoneWtCtrl.text = '0.000000';
      _items.first.marksCtrl.clear();

      setState(() => _showForm = false);
      toast(context, 'Repair custody intake recorded.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showRepairLifecycleSheet(Map<String, dynamic> rep) async {
    final id = '${rep['id'] ?? ''}';
    if (id.isEmpty) return;
    String stage = 'COMPLETE';
    final chargeCtrl = TextEditingController(
      text: _pick(rep, ['estimatedChargeAmount', 'repairChargeAmount'], '0.00'),
    );
    final ackCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool sheetBusy = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Repair Custody · ${_pick(rep, ['documentNumber', 'jobNumber'], shortId(id))}',
                style: T.display(20),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final opt in const [
                    ('QUOTE', 'Approve Estimate'),
                    ('COMPLETE', 'Complete Repair QC'),
                    ('RETURN', 'Return Custody to Customer'),
                  ])
                    ChoiceChip(
                      label: Text(opt.$2),
                      selected: stage == opt.$1,
                      showCheckmark: false,
                      selectedColor: Pal.goldWash,
                      onSelected: (_) => setLocal(() => stage = opt.$1),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (stage == 'QUOTE') ...[
                SaasField(
                  label: 'Quoted Repair Charge (INR)',
                  controller: chargeCtrl,
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
              ],
              if (stage == 'RETURN') ...[
                SaasField(
                  label: 'Customer Return Acknowledgement Ref',
                  controller: ackCtrl,
                  hint: 'Signed return receipt / OTP ref',
                ),
                const SizedBox(height: 10),
              ],
              SaasField(
                label: 'Authorization / QC Notes (min 5 chars)',
                controller: reasonCtrl,
                hint: 'Verified repair weight & hallmark on return',
                maxLines: 2,
              ),
              if (sheetErr != null) ...[
                const SizedBox(height: 10),
                Text(sheetErr!, style: T.body(12.5, color: Pal.danger, w: FontWeight.w700)),
              ],
              const SizedBox(height: 14),
              RoyalGoldButton(
                busy: sheetBusy,
                label: stage == 'QUOTE'
                    ? 'Save Repair Estimate'
                    : stage == 'COMPLETE'
                        ? 'Mark Repair QC Passed'
                        : 'Confirm Custody Return',
                onPressed: sheetBusy
                    ? null
                    : () async {
                        if (reasonCtrl.text.trim().length < 5) {
                          setLocal(() => sheetErr = 'Enter notes (min 5 chars).');
                          return;
                        }
                        setLocal(() {
                          sheetBusy = true;
                          sheetErr = null;
                        });
                        final api = context.read<ApiClient>();
                        final ver = asInt(rep['version'], fallback: 1);
                        try {
                          final paths = switch (stage) {
                            'QUOTE' => ['/repairs/$id/quote', '/repairs/$id/approve'],
                            'COMPLETE' => ['/repairs/$id/complete', '/repairs/$id/qc'],
                            _ => ['/repairs/$id/deliver', '/repairs/$id/return'],
                          };
                          final payload = <String, dynamic>{
                            'expectedVersion': ver,
                            'reason': reasonCtrl.text.trim(),
                            if (stage == 'QUOTE')
                              'estimatedChargeAmount': normAmount(chargeCtrl.text),
                            if (stage == 'RETURN') ...{
                              'returnDate': todayIso(),
                              if (ackCtrl.text.trim().isNotEmpty)
                                'customerAcknowledgementRef': ackCtrl.text.trim(),
                            },
                          };
                          for (var i = 0; i < paths.length; i++) {
                            try {
                              await api.post(
                                paths[i],
                                idempotencyKey: _supplyUuid.v4(),
                                body: payload,
                              );
                              break;
                            } on ApiException catch (e) {
                              if ((e.status != 404 && e.code != 'HTTP_ERROR') ||
                                  i == paths.length - 1) {
                                rethrow;
                              }
                            }
                          }
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          toast(context, 'Repair job updated.');
                          await _load();
                        } on ApiException catch (e) {
                          setLocal(() => sheetErr = e.message);
                        } finally {
                          if (ctx.mounted) setLocal(() => sheetBusy = false);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
    chargeCtrl.dispose();
    ackCtrl.dispose();
    reasonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999');
    final bullionActive = gold999 != null && decOrZero(gold999.sell) > Decimal.zero;
    final showroomContext = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    final q = _search.text.trim().toLowerCase();
    bool isDone(Map<String, dynamic> r) {
      final s = '${r['state'] ?? r['status'] ?? ''}'.toUpperCase();
      return s == 'DELIVERED' || s == 'RETURNED' || s == 'COMPLETED' || s == 'CLOSED';
    }

    final activeCnt = _repairs.where((r) => !isDone(r)).length;
    final doneCnt = _repairs.where(isDone).length;
    final filtered = _repairs.where((r) {
      if (_filter == 'ACTIVE' && isDone(r)) return false;
      if (_filter == 'DONE' && !isDone(r)) return false;
      if (q.isEmpty) return true;
      final hay =
          '${r['documentNumber'] ?? ''} ${r['jobNumber'] ?? ''} ${asMap(r['customer'])['displayName'] ?? ''} ${r['itemSummary'] ?? r['articleDescription'] ?? ''} ${r['customerComplaint'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Repairs & Custody',
      icon: Icons.build_outlined,
      searchController: _search,
      searchHint: 'Search repair #, customer, item summary or complaint...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: 'Refresh repairs & custody',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${_repairs.length})'),
          ('ACTIVE', 'In Custody ($activeCnt)'),
          ('DONE', 'Returned ($doneCnt)'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'New repair intake',
        onPressed: () => setState(() => _showForm = !_showForm),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 88),
          children: [
            // Website Sub-Header (`Repairs & Custody` + `Bullion 24K`)
            Panel(
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBF3DC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE7CF8B)),
                        ),
                        child: const Icon(
                          Icons.build_outlined,
                          size: 18,
                          color: Pal.goldDeep,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Repairs & Custody',
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
                    'Customer ornament custody intake, itemized scale weights & distinguishing marks, workshop QC, and acknowledged return.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const MaterialsRatesScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
                                size: 13.5,
                                color: bullionActive ? Pal.goldDeep : Pal.warn,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                bullionActive
                                    ? 'Bullion 24K: Fine 999 Board Active'
                                    : 'Bullion 24K: Configure Rate Board',
                                style: T.body(
                                  11.2,
                                  color: bullionActive ? Pal.goldDeep : Pal.warn,
                                  w: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      ActionChip(
                        avatar: Icon(
                          _showForm ? Icons.expand_less_rounded : Icons.add_rounded,
                          size: 16,
                          color: Pal.goldDeep,
                        ),
                        label: Text(
                          'New repair intake',
                          style: T.body(11.8, color: Pal.goldDeep, w: FontWeight.w700),
                        ),
                        backgroundColor: _showForm ? Pal.goldWash : Pal.card,
                        side: BorderSide(color: Pal.gold.withValues(alpha: 0.45)),
                        onPressed: () => setState(() => _showForm = !_showForm),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!, onRetry: _load),
            ],

            // `New repair intake` (`image-14.png` — 11 intake fields + dynamic `Custody item 1..N`)
            if (_showForm) ...[
              const SizedBox(height: 12),
              SaasFormCard(
                title: 'New repair intake',
                trailing: _repairs.isNotEmpty
                    ? TextButton(
                        onPressed: () => setState(() => _showForm = false),
                        child: const Text('Hide'),
                      )
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Customer UUID',
                      controller: _partyId,
                      options: _lk.partiesByRole('CUSTOMER'),
                      hint: 'Select customer or enter UUID',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Custody location UUID',
                      controller: _custodyLocId,
                      options: _lk.locationsByType(
                        const ['CUSTOMER_CUSTODY', 'QUARANTINE', 'VAULT'],
                      ),
                      hint: 'Select custody location or enter UUID',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: LookupField(
                            label: 'Intake series UUID',
                            controller: _seriesId,
                            options: _lk.seriesFor(const ['REPAIR', 'CUSTODY']),
                            optional: true,
                            hint: 'Intake series',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Evidence file UUID',
                            controller: _evidenceFileUuid,
                            hint: 'Optional UUID',
                            mono: true,
                            trailing: IconButton(
                              tooltip: 'Generate Evidence UUID',
                              icon: const Icon(
                                Icons.auto_fix_high_rounded,
                                size: 17,
                                color: Pal.goldDeep,
                              ),
                              onPressed: () => setState(
                                () => _evidenceFileUuid.text = _supplyUuid.v4(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DatePickField(
                            label: 'Intake date',
                            controller: _intakeDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DatePickField(
                            label: 'Promised date',
                            controller: _promisedDate,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Item summary',
                      controller: _itemSummary,
                      hint: 'Item summary',
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Customer complaint',
                      controller: _complaint,
                      hint: 'Customer complaint',
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Visible condition',
                      controller: _visibleCondition,
                      hint: 'Visible condition',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Photo/evidence reference',
                            controller: _photoEvidenceRef,
                            hint: 'Photo/evidence ref',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Customer acknowledgement',
                            controller: _customerAck,
                            hint: 'Acknowledgement ref',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Dynamic `Custody item 1..N` (`image-14.png`)
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Builder(builder: (_) {
                        final it = _items[i];
                        final purities = _lk.puritiesForMetal(it.metalIdCtrl.text.trim());
                        return SaasSubBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Custody item ${i + 1}',
                                    style: T.body(13.2, color: Pal.ink, w: FontWeight.w800),
                                  ),
                                  const Spacer(),
                                  if (_items.length > 1)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        foregroundColor: Pal.danger,
                                      ),
                                      onPressed: () => setState(() {
                                        _items[i].dispose();
                                        _items.removeAt(i);
                                      }),
                                      child: const Text('Remove'),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              SaasField(
                                label: 'Description',
                                controller: it.descCtrl,
                                hint: 'Description',
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: LookupField(
                                      label: 'Metal UUID',
                                      controller: it.metalIdCtrl,
                                      options: _lk.metals,
                                      hint: 'Metal',
                                      onSelected: (opt) {
                                        setState(() {
                                          it.purityIdCtrl.clear();
                                          if (opt != null) {
                                            final p = _lk.puritiesForMetal(opt.id);
                                            if (p.isNotEmpty) {
                                              it.purityIdCtrl.text = p.first.id;
                                            }
                                          }
                                        });
                                        _recalcItemFine(it);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: LookupField(
                                      label: 'Purity UUID',
                                      controller: it.purityIdCtrl,
                                      options: purities.isNotEmpty
                                          ? purities
                                          : _lk.purityGrades,
                                      hint: 'Purity',
                                      onSelected: (_) => _recalcItemFine(it),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const FieldLabel('Gross weight g'),
                                        TextField(
                                          controller: it.grossWtCtrl,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                          style: T.mono(13.5),
                                          decoration: const InputDecoration(
                                            hintText: '0.000',
                                          ),
                                          onChanged: (v) {
                                            if (it.metalWtCtrl.text.trim().isEmpty) {
                                              it.metalWtCtrl.text = v;
                                              _recalcItemFine(it);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const FieldLabel('Metal weight g'),
                                        TextField(
                                          controller: it.metalWtCtrl,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                          style: T.mono(13.5),
                                          decoration: const InputDecoration(
                                            hintText: '0.000',
                                          ),
                                          onChanged: (_) => _recalcItemFine(it),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: SaasField(
                                      label: 'Fine 999 g',
                                      controller: it.fineWtCtrl,
                                      hint: '0.000000',
                                      mono: true,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SaasField(
                                      label: 'Stone weight g',
                                      controller: it.stoneWtCtrl,
                                      hint: '0.000000',
                                      mono: true,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SaasField(
                                label: 'Distinguishing marks',
                                controller: it.marksCtrl,
                                hint: 'Distinguishing marks',
                              ),
                            ],
                          ),
                        );
                      }),
                    ],

                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 38),
                        ),
                        onPressed: () {
                          final defMetal =
                              _lk.metals.isNotEmpty ? _lk.metals.first.id : '';
                          final defPur = defMetal.isNotEmpty &&
                                  _lk.puritiesForMetal(defMetal).isNotEmpty
                              ? _lk.puritiesForMetal(defMetal).first.id
                              : '';
                          setState(
                            () => _items.add(
                              _RepairCustodyItemDraft(
                                defaultMetalId: defMetal,
                                defaultPurityId: defPur,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Add custody item'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    RoyalGoldButton(
                      busy: _busy,
                      label: 'Record intake',
                      onPressed: _busy ? null : _recordIntake,
                    ),
                  ],
                ),
              ),
            ],

            const SectionLabel('Repair & Custody Orders'),
            if (_loading && _repairs.isEmpty)
              const Panel(child: Skeleton(height: 100))
            else if (filtered.isEmpty)
              const SaasEmptyBox('No repair orders yet.')
            else
              for (final r in filtered)
                LuxuryRecordCard(
                  icon: Icons.build_outlined,
                  code: _pick(
                    r,
                    ['documentNumber', 'jobNumber', 'intakeNumber'],
                    shortId('${r['id']}'),
                  ),
                  status: _pick(r, ['state', 'status'], 'RECEIVED'),
                  lines: [
                    ('Customer', '${asMap(r['customer'])['displayName'] ?? '-'}'),
                    if (_pick(r, ['itemSummary', 'articleDescription']).isNotEmpty)
                      ('Item Summary', _pick(r, ['itemSummary', 'articleDescription'])),
                    if (_pick(r, ['customerComplaint']).isNotEmpty)
                      ('Complaint', _pick(r, ['customerComplaint'])),
                    ('Promised Date', fmtDate(_pick(r, ['promisedDate']))),
                  ],
                  amountLabel: 'Gross Wt',
                  amountValue: grams(
                    _pick(r, ['receivedGrossWeightGrams', 'totalGrossWeightGrams'], '0'),
                  ),
                  actions: [
                    GoldButton(
                      label: 'Manage Repair',
                      compact: true,
                      onPressed: () => _showRepairLifecycleSheet(r),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. MATERIALS & BULLION RATES (`/materials` & `/rates`) — MaterialsRatesPanel.tsx
// ---------------------------------------------------------------------------

class MaterialsRatesScreen extends StatefulWidget {
  const MaterialsRatesScreen({super.key});
  @override
  State<MaterialsRatesScreen> createState() => _MaterialsRatesScreenState();
}

class _RateLineDraft {
  _RateLineDraft({
    this.metalId = '',
    this.side = 'SELL',
    this.ratePerUnit = '',
    this.referenceFineness = '999',
    this.unitId = '',
  });
  String metalId;
  String side;
  String ratePerUnit;
  String referenceFineness;
  String unitId;
}

class _MaterialsRatesScreenState extends State<MaterialsRatesScreen> {
  final _search = TextEditingController();
  Map<String, dynamic> _materials = const {};
  List<Map<String, dynamic>> _rateBooks = [];
  bool _loading = true;
  bool _calcBusy = false;
  String? _error;

  // Authoritative metal-price check (`POST /pricing/calculate-metal`)
  String? _calcRateVersionId;
  String? _calcMetalId;
  String? _calcPurityId;
  final _calcWeight = TextEditingController();
  String _calcSide = 'SELL';
  Map<String, dynamic>? _priceResult;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _calcWeight.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait([
        api.get('/materials'),
        api.get('/rates'),
      ]);
      if (!mounted) return;
      context.read<RatesStore>().refresh();
      final mats = asMap(res[0]);
      final books = asList(res[1], keys: const ['rateBooks', 'books', 'items']);
      setState(() {
        _materials = mats;
        _rateBooks = books;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LookupOption> get _metalOpts => asList(_materials['metals'])
      .map(
        (m) => LookupOption(
          id: '${m['id']}',
          label: '${m['name']} (${m['code']})',
          raw: m,
        ),
      )
      .where((o) => o.id.isNotEmpty)
      .toList();

  List<LookupOption> _purityOpts(String? metalId) {
    final out = <LookupOption>[];
    for (final m in asList(_materials['metals'])) {
      if (metalId != null && metalId.isNotEmpty && '${m['id']}' != metalId) {
        continue;
      }
      for (final pg in asList(m['purityGrades'])) {
        final karat = '${pg['displayKarat'] ?? pg['displayLabel'] ?? ''}'.trim();
        final fine = normWeight6('${pg['finenessPerThousand'] ?? ''}');
        final parts = <String>[
          '${pg['code'] ?? ''}'.trim(),
          if (karat.isNotEmpty) karat,
          fine,
        ].where((s) => s.isNotEmpty).toList();
        out.add(
          LookupOption(
            id: '${pg['id']}',
            label: metalId != null && metalId.isNotEmpty
                ? parts.join(' · ')
                : '${m['code']} · ${parts.join(' · ')}',
            raw: {...pg, '_metalId': '${m['id']}'},
          ),
        );
      }
    }
    return out;
  }

  List<LookupOption> get _massUnitOpts => asList(_materials['units'])
      .where((u) => '${u['dimension'] ?? 'MASS'}' == 'MASS')
      .map(
        (u) => LookupOption(
          id: '${u['id']}',
          label: '${u['code']} (${u['symbol'] ?? u['code']})',
          raw: u,
        ),
      )
      .where((o) => o.id.isNotEmpty)
      .toList();

  List<LookupOption> get _publishedVersionOpts {
    final out = <LookupOption>[];
    for (final b in _rateBooks) {
      for (final v in asList(b['versions'])) {
        if ('${v['state']}'.toUpperCase() == 'PUBLISHED') {
          out.add(
            LookupOption(
              id: '${v['id']}',
              label: '${b['name']} · v${v['sequenceNumber']}',
              raw: v,
            ),
          );
        }
      }
    }
    return out;
  }

  String _formatPurityBadge(Map<String, dynamic> g) {
    final code = '${g['code'] ?? ''}'.trim();
    final karat = '${g['displayKarat'] ?? g['displayLabel'] ?? ''}'.trim();
    final rawFine = '${g['finenessPerThousand'] ?? ''}'.trim();
    final fineDec = tryDec(rawFine);
    final fine = fineDec != null ? fineDec.toStringAsFixed(6) : rawFine;
    return [
      if (code.isNotEmpty) code,
      if (karat.isNotEmpty) karat,
      if (fine.isNotEmpty) fine,
    ].join(' · ');
  }

  String _formatUnitsLine(List<Map<String, dynamic>> units) {
    if (units.isEmpty) return '';
    final parts = <String>[];
    for (final u in units) {
      final code = '${u['code'] ?? ''}'.trim();
      if (code.isEmpty) continue;
      final rawFactor = '${u['baseFactor'] ?? u['toBaseFactor'] ?? '1.000000000000'}'.trim();
      final decFactor = tryDec(rawFactor);
      final factorStr = rawFactor.contains('.')
          ? rawFactor
          : (decFactor != null ? decFactor.toStringAsFixed(12) : rawFactor);
      parts.add('$code ($factorStr base)');
    }
    if (parts.isEmpty) return '';
    return 'Units: ${parts.join(' · ')}';
  }

  Future<void> _openAddMetalModal() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var saving = false;
    String? modalErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          backgroundColor: Pal.card,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add metal',
                        style: T.body(17, weight: FontWeight.w700, color: Pal.ink),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20, color: Pal.inkSoft),
                    ),
                  ],
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 12),
                SaasField(
                  label: 'Code',
                  controller: codeCtrl,
                  mono: true,
                ),
                const SizedBox(height: 12),
                SaasField(
                  label: 'Name',
                  controller: nameCtrl,
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: 'Create metal',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            final code = codeCtrl.text.trim().toUpperCase();
                            final name = nameCtrl.text.trim();
                            if (code.isEmpty || name.isEmpty) {
                              setModal(() => modalErr = 'Enter both metal code and name.');
                              return;
                            }
                            setModal(() {
                              saving = true;
                              modalErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/materials/metals',
                                idempotent: true,
                                body: {
                                  'code': code,
                                  'name': name,
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Metal master created.');
                              _load();
                            } on ApiException catch (e) {
                              setModal(() => modalErr = e.message);
                            } finally {
                              if (ctx.mounted) setModal(() => saving = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    codeCtrl.dispose();
    nameCtrl.dispose();
  }

  Future<void> _openAddPurityModal() async {
    String? selectedMetalId;
    final gradeCodeCtrl = TextEditingController();
    final karatCtrl = TextEditingController();
    final finenessCtrl = TextEditingController();
    var saving = false;
    String? modalErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          backgroundColor: Pal.card,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add purity grade',
                        style: T.body(17, weight: FontWeight.w700, color: Pal.ink),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20, color: Pal.inkSoft),
                    ),
                  ],
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 12),
                const FieldLabel('Metal'),
                GoldDropdown<String>(
                  value: selectedMetalId,
                  hint: 'Select metal',
                  items: _metalOpts
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m.id,
                          child: Text(
                            m.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setModal(() => selectedMetalId = v),
                ),
                const SizedBox(height: 12),
                SaasField(
                  label: 'Grade code',
                  controller: gradeCodeCtrl,
                  mono: true,
                ),
                const SizedBox(height: 12),
                SaasField(
                  label: 'Display label / karat',
                  controller: karatCtrl,
                ),
                const SizedBox(height: 12),
                SaasField(
                  label: 'Fineness per thousand',
                  controller: finenessCtrl,
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: 'Create purity grade',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            final metalId = (selectedMetalId ?? '').trim();
                            final code = gradeCodeCtrl.text.trim().toUpperCase();
                            final karat = karatCtrl.text.trim();
                            final fineness = finenessCtrl.text.trim();
                            if (metalId.isEmpty || code.isEmpty || fineness.isEmpty) {
                              setModal(
                                () => modalErr =
                                    'Select metal and enter grade code and fineness per thousand.',
                              );
                              return;
                            }
                            if (tryDec(fineness) == null) {
                              setModal(
                                () => modalErr = 'Fineness per thousand must be a valid decimal.',
                              );
                              return;
                            }
                            setModal(() {
                              saving = true;
                              modalErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/materials/purity-grades',
                                idempotent: true,
                                body: {
                                  'metalId': metalId,
                                  'code': code,
                                  if (karat.isNotEmpty) 'displayKarat': karat,
                                  'finenessPerThousand': fineness,
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Purity grade created.');
                              _load();
                            } on ApiException catch (e) {
                              setModal(() => modalErr = e.message);
                            } finally {
                              if (ctx.mounted) setModal(() => saving = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    gradeCodeCtrl.dispose();
    karatCtrl.dispose();
    finenessCtrl.dispose();
  }

  Future<void> _openNewRateBookModal() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final currencyCtrl = TextEditingController(text: 'INR');
    var saving = false;
    String? modalErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          backgroundColor: Pal.card,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'New rate book',
                        style: T.body(17, weight: FontWeight.w700, color: Pal.ink),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20, color: Pal.inkSoft),
                    ),
                  ],
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 12),
                SaasField(
                  label: 'Code',
                  controller: codeCtrl,
                  mono: true,
                ),
                const SizedBox(height: 12),
                SaasField(
                  label: 'Name',
                  controller: nameCtrl,
                ),
                const SizedBox(height: 12),
                SaasField(
                  label: 'Currency',
                  controller: currencyCtrl,
                  mono: true,
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: 'Create rate book',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            final code = codeCtrl.text.trim().toUpperCase();
                            final name = nameCtrl.text.trim();
                            final currency = currencyCtrl.text.trim().toUpperCase();
                            if (code.isEmpty || name.isEmpty || currency.isEmpty) {
                              setModal(
                                () => modalErr = 'Enter rate book code, name, and currency.',
                              );
                              return;
                            }
                            setModal(() {
                              saving = true;
                              modalErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/rate-books',
                                idempotent: true,
                                body: {
                                  'code': code,
                                  'name': name,
                                  'currency': currency,
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Rate book created.');
                              _load();
                            } on ApiException catch (e) {
                              setModal(() => modalErr = e.message);
                            } finally {
                              if (ctx.mounted) setModal(() => saving = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    codeCtrl.dispose();
    nameCtrl.dispose();
    currencyCtrl.dispose();
  }

  Future<void> _openCreateRateVersionSheet(Map<String, dynamic> book) async {
    final defaultMetalId = _metalOpts.isNotEmpty ? _metalOpts.first.id : '';
    final defaultUnitId = _massUnitOpts.isNotEmpty ? _massUnitOpts.first.id : '';
    final lines = <_RateLineDraft>[
      _RateLineDraft(metalId: defaultMetalId, unitId: defaultUnitId),
    ];
    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'New rate version · ${book['name'] ?? book['code']}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                Text(
                  'Immutable, effective-dated bullion board lines.',
                  style: T.body(12.2, color: Pal.muted),
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Line ${i + 1}',
                                style: T.body(12.5, weight: FontWeight.w700),
                              ),
                            ),
                            if (lines.length > 1)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Pal.err,
                                ),
                                onPressed: () => setSheet(() => lines.removeAt(i)),
                                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                                label: const Text('Remove'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: GoldDropdown<String>(
                                value: lines[i].metalId.isEmpty ? null : lines[i].metalId,
                                hint: 'Metal',
                                items: _metalOpts
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m.id,
                                        child: Text(
                                          m.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setSheet(() => lines[i].metalId = v ?? ''),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 104,
                              child: GoldDropdown<String>(
                                value: lines[i].side,
                                items: const [
                                  DropdownMenuItem(value: 'SELL', child: Text('SELL')),
                                  DropdownMenuItem(value: 'BUY', child: Text('BUY')),
                                ],
                                onChanged: (v) => setSheet(() => lines[i].side = v ?? 'SELL'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                decoration: const InputDecoration(hintText: 'Rate per unit'),
                                style: T.mono(13),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (v) => lines[i].ratePerUnit = v,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 92,
                              child: TextFormField(
                                initialValue: lines[i].referenceFineness,
                                decoration: const InputDecoration(hintText: '999'),
                                style: T.mono(13),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (v) => lines[i].referenceFineness = v,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GoldDropdown<String>(
                          value: lines[i].unitId.isEmpty ? null : lines[i].unitId,
                          hint: 'Mass unit',
                          items: _massUnitOpts
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u.id,
                                  child: Text(
                                    u.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setSheet(() => lines[i].unitId = v ?? ''),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => setSheet(
                      () => lines.add(
                        _RateLineDraft(metalId: defaultMetalId, unitId: defaultUnitId),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('Add rate line'),
                  ),
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  label: 'Create immutable draft',
                  busy: saving,
                  onPressed: saving
                      ? null
                      : () async {
                          final valid = lines
                              .where(
                                (l) =>
                                    l.metalId.isNotEmpty &&
                                    l.ratePerUnit.trim().isNotEmpty &&
                                    l.unitId.isNotEmpty,
                              )
                              .toList();
                          if (valid.isEmpty) {
                            setSheet(
                              () => sheetErr =
                                  'Add at least one complete rate line (metal, rate, fineness, unit).',
                            );
                            return;
                          }
                          setSheet(() {
                            saving = true;
                            sheetErr = null;
                          });
                          try {
                            await context.read<ApiClient>().post(
                              '/rate-books/${book['id']}/versions',
                              idempotent: true,
                              body: {
                                'expectedBookVersion': asInt(book['version'], fallback: 1),
                                'effectiveAt': DateTime.now().toUtc().toIso8601String(),
                                'lines': valid
                                    .map(
                                      (l) => {
                                        'metalId': l.metalId,
                                        'side': l.side,
                                        'ratePerUnit': l.ratePerUnit.trim(),
                                        'referenceFineness': l.referenceFineness.trim(),
                                        'unitId': l.unitId,
                                      },
                                    )
                                    .toList(),
                              },
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            toast(context, 'Immutable draft rate version created.');
                            _load();
                          } on ApiException catch (e) {
                            setSheet(() => sheetErr = e.message);
                          } finally {
                            if (ctx.mounted) setSheet(() => saving = false);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _publishVersion(Map<String, dynamic> v) async {
    final reasonCtrl = TextEditingController();
    var saving = false;
    String? modalErr;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Dialog(
          backgroundColor: Pal.card,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Publish version ${v['sequenceNumber']}',
                        style: T.body(16.5, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                Text(
                  'Publishing locks this complete rate proposal for historical use.',
                  style: T.body(12.5, color: Pal.muted),
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 12),
                SaasField(
                  label: 'Approval reason (min 10 chars)',
                  controller: reasonCtrl,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: 'Publish rate version',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            final reason = reasonCtrl.text.trim();
                            if (reason.length < 10) {
                              setModal(
                                () => modalErr =
                                    'Enter an approval reason of at least 10 characters.',
                              );
                              return;
                            }
                            setModal(() {
                              saving = true;
                              modalErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/rate-versions/${v['id']}/publish',
                                idempotent: true,
                                body: {
                                  'expectedVersion': asInt(v['version'], fallback: 1),
                                  'approvalReason': reason,
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Rate version published.');
                              _load();
                            } on ApiException catch (e) {
                              setModal(() => modalErr = e.message);
                            } finally {
                              if (ctx.mounted) setModal(() => saving = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  Future<void> _checkPrice() async {
    final rateVer = (_calcRateVersionId ?? '').trim();
    final metalId = (_calcMetalId ?? '').trim();
    final purityId = (_calcPurityId ?? '').trim();
    final wt = _calcWeight.text.trim();

    if (rateVer.isEmpty || metalId.isEmpty || purityId.isEmpty || wt.isEmpty) {
      setState(
        () => _error = 'Select published rate, metal, purity, and enter weight in grams.',
      );
      return;
    }
    if (!isValidWeight(wt)) {
      setState(() => _error = 'Weight g must be a positive decimal.');
      return;
    }

    setState(() {
      _calcBusy = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().post(
        '/pricing/calculate-metal',
        body: {
          'rateVersionId': rateVer,
          'components': [
            {
              'metalId': metalId,
              'purityGradeId': purityId,
              'weightGrams': normWeight6(wt),
              'side': _calcSide,
            },
          ],
        },
      );
      if (!mounted) return;
      setState(() => _priceResult = asMap(res));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _calcBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final metals = asList(_materials['metals']);
    final units = asList(_materials['units']);
    final unitsFooter = _formatUnitsLine(units);

    final q = _search.text.trim().toLowerCase();
    final fMetals = metals.where((m) {
      if (q.isEmpty) return true;
      final grades = asList(m['purityGrades'])
          .map((g) => '${g['code']} ${g['displayKarat'] ?? ''}')
          .join(' ');
      return '${m['name']} ${m['code']} $grades'.toLowerCase().contains(q);
    }).toList();
    final fBooks = _rateBooks.where((b) {
      if (q.isEmpty) return true;
      return '${b['name']} ${b['code']} ${b['currency']}'.toLowerCase().contains(q);
    }).toList();

    final purityItems = _purityOpts(_calcMetalId);

    return LuxuryModuleScaffold(
      title: 'Materials & Bullion Rates',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.toll_rounded,
      searchController: _search,
      searchHint: 'Search metals, purity grades or rate books...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Bullion 24K active board badge + Materials and rates header card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Pal.goldTint,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Pal.borderGold),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.toll_rounded, size: 13, color: Pal.goldDeep),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            gold999 != null
                                ? 'Bullion 24K: Fine 999 Board Active · ${inr(gold999.sell)}/g'
                                : 'Bullion 24K: Fine 999 Board Active',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body(11.5, weight: FontWeight.w700, color: Pal.goldDeep),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.diamond_outlined, size: 20, color: Pal.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Materials and rates',
                          style: T.body(16.5, weight: FontWeight.w700, color: Pal.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Exact purity masters and immutable, effective-dated metal rates.',
                    style: T.body(12.5, color: Pal.muted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        onPressed: _openAddMetalModal,
                        child: Text(
                          'Add metal',
                          style: T.body(12.5, weight: FontWeight.w600, color: Pal.ink),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(11),
                          ),
                        ),
                        onPressed: _openAddPurityModal,
                        child: Text(
                          'Add purity',
                          style: T.body(12.5, weight: FontWeight.w600, color: Pal.ink),
                        ),
                      ),
                      GoldButton(
                        label: 'New rate book',
                        compact: true,
                        onPressed: _openNewRateBookModal,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 1. Material masters card (exact image-17.png layout formatted for phone)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Material masters',
                    style: T.body(15.5, weight: FontWeight.w700, color: Pal.ink),
                  ),
                  const SizedBox(height: 14),
                  if (_loading && metals.isEmpty)
                    const Skeleton(height: 92)
                  else if (fMetals.isEmpty)
                    Text(
                      'No metals configured yet. Tap "Add metal" above to add a metal master.',
                      style: T.body(12.5, color: Pal.muted),
                    )
                  else ...[
                    for (var i = 0; i < fMetals.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Divider(height: 1, color: Pal.divider),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${fMetals[i]['name'] ?? ''}',
                              style: T.body(14.5, weight: FontWeight.w700, color: Pal.ink),
                            ),
                          ),
                          Text(
                            '${fMetals[i]['code'] ?? ''}'.toUpperCase(),
                            style: T.caps(10.8, color: Pal.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (asList(fMetals[i]['purityGrades']).isEmpty)
                        Text(
                          'No purity grades configured.',
                          style: T.body(12, color: Pal.muted),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final g in asList(fMetals[i]['purityGrades']))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Pal.goldTint,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Pal.borderGold.withValues(alpha: 0.55),
                                  ),
                                ),
                                child: Text(
                                  _formatPurityBadge(g),
                                  style: T.mono(
                                    11.8,
                                    weight: FontWeight.w600,
                                    color: Pal.goldDeep,
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ],
                  if (unitsFooter.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Pal.divider),
                    const SizedBox(height: 10),
                    Text(
                      unitsFooter,
                      style: T.body(11.5, color: Pal.muted),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 2. Rate books card (exact image-17.png layout formatted for phone)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.balance_rounded, size: 18, color: Pal.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Rate books',
                          style: T.body(15.5, weight: FontWeight.w700, color: Pal.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading && _rateBooks.isEmpty)
                    const Skeleton(height: 80)
                  else if (fBooks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'No rate books recorded yet. Tap "New rate book" above to create one.',
                        style: T.body(12.5, color: Pal.muted),
                      ),
                    )
                  else
                    for (var i = 0; i < fBooks.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      SaasSubBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${fBooks[i]['name'] ?? ''}',
                                        style: T.body(
                                          14,
                                          weight: FontWeight.w700,
                                          color: Pal.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${fBooks[i]['code'] ?? ''} · ${fBooks[i]['currency'] ?? 'INR'}',
                                        style: T.mono(11.5, color: Pal.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                StatusPill(
                                  asList(fBooks[i]['versions']).any(
                                    (v) => '${v['state']}'.toUpperCase() == 'PUBLISHED',
                                  )
                                      ? 'PUBLISHED'
                                      : 'DRAFT',
                                ),
                              ],
                            ),
                            if (asList(fBooks[i]['versions']).isNotEmpty) ...[
                              const SizedBox(height: 10),
                              for (final v in asList(fBooks[i]['versions']).take(4))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'v${v['sequenceNumber']} (${v['state']}) · ${asList(v['lines']).length} lines · ${fmtDateTime('${v['effectiveAt'] ?? ''}')}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: T.body(11.8, color: Pal.inkSoft),
                                        ),
                                      ),
                                      if ('${v['state']}'.toUpperCase() == 'DRAFT') ...[
                                        const SizedBox(width: 8),
                                        GoldButton(
                                          label: 'Publish v${v['sequenceNumber']}',
                                          compact: true,
                                          onPressed: () => _publishVersion(v),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: () => _openCreateRateVersionSheet(fBooks[i]),
                                icon: const Icon(Icons.add_rounded, size: 15),
                                label: const Text('New rate version'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // 3. Authoritative metal-price check card (exact image-17.png layout)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calculate_outlined, size: 18, color: Pal.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Authoritative metal-price check',
                          style: T.body(15.5, weight: FontWeight.w700, color: Pal.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  GoldDropdown<String>(
                    value: _calcRateVersionId,
                    hint: 'Published rate',
                    items: _publishedVersionOpts
                        .map(
                          (o) => DropdownMenuItem<String>(
                            value: o.id,
                            child: Text(
                              o.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _calcRateVersionId = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GoldDropdown<String>(
                          value: _calcMetalId,
                          hint: 'Metal',
                          items: _metalOpts
                              .map(
                                (m) => DropdownMenuItem<String>(
                                  value: m.id,
                                  child: Text(
                                    m.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setState(() {
                            _calcMetalId = v;
                            _calcPurityId = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GoldDropdown<String>(
                          value: _calcPurityId,
                          hint: 'Purity',
                          items: purityItems
                              .map(
                                (p) => DropdownMenuItem<String>(
                                  value: p.id,
                                  child: Text(
                                    p.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            final picked = purityItems.where((x) => x.id == v).firstOrNull;
                            final parentMetal = '${picked?.raw['_metalId'] ?? ''}'.trim();
                            setState(() {
                              _calcPurityId = v;
                              if ((_calcMetalId ?? '').isEmpty && parentMetal.isNotEmpty) {
                                _calcMetalId = parentMetal;
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _calcWeight,
                          style: T.mono(13.5),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            hintText: 'Weight g',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: GoldDropdown<String>(
                          value: _calcSide,
                          items: const [
                            DropdownMenuItem(value: 'SELL', child: Text('SELL')),
                            DropdownMenuItem(value: 'BUY', child: Text('BUY')),
                          ],
                          onChanged: (v) => setState(() => _calcSide = v ?? 'SELL'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RoyalGoldButton(
                    label: 'Calculate',
                    busy: _calcBusy,
                    onPressed: _calcBusy ? null : _checkPrice,
                  ),
                  if (_priceResult != null) ...[
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Column(
                        children: [
                          KVRow(
                            'Total Metal Value',
                            inr(_priceResult!['totalMetalValue']),
                            bold: true,
                          ),
                          for (final c in asList(_priceResult!['components']))
                            KVRow(
                              '${c['metalCode'] ?? ''} ${c['purityCode'] ?? ''} (${grams(c['fineWeightGrams'])} fine)',
                              inr(c['metalValue']),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. REFINING & MELTING (`/refining`) — `image-24.png`
// ---------------------------------------------------------------------------

class RefiningMeltingScreen extends StatefulWidget {
  const RefiningMeltingScreen({super.key});
  @override
  State<RefiningMeltingScreen> createState() => _RefiningMeltingScreenState();
}

class _RefiningInputDraft {
  _RefiningInputDraft()
      : balanceIdCtrl = TextEditingController(),
        versionCtrl = TextEditingController(text: '1'),
        qtyCtrl = TextEditingController(),
        fineCtrl = TextEditingController();

  final TextEditingController balanceIdCtrl;
  final TextEditingController versionCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController fineCtrl;

  void dispose() {
    balanceIdCtrl.dispose();
    versionCtrl.dispose();
    qtyCtrl.dispose();
    fineCtrl.dispose();
  }
}

class _RefiningMeltingScreenState extends State<RefiningMeltingScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _formExpanded = true;
  List<Map<String, dynamic>> _batches = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Exact header + input fields from `image-24.png` (`New melt batch`)
  final _refinerPartyId = TextEditingController();
  final _meltSeriesId = TextEditingController();
  final _businessDate = TextEditingController(text: todayIso());
  final _batchDesc = TextEditingController();
  final _allowedLoss = TextEditingController(text: '0.000000');
  final List<_RefiningInputDraft> _inputs = [_RefiningInputDraft()];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _search,
      _refinerPartyId,
      _meltSeriesId,
      _businessDate,
      _batchDesc,
      _allowedLoss,
    ]) {
      c.dispose();
    }
    for (final inp in _inputs) {
      inp.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait([
        api.get('/refining'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
          includeMaterials: true,
        ),
      ]);
      if (!mounted) return;
      final lk = res[1] as WorkspaceLookup;
      if (_meltSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['MELT', 'REFINING', 'BATCH']);
        if (s.isNotEmpty) _meltSeriesId.text = s.first.id;
      }
      setState(() {
        _batches = asList(
          res[0],
          keys: const ['batches', 'meltBatches', 'refiningBatches', 'items'],
        );
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createBatch() async {
    if (_meltSeriesId.text.trim().isEmpty ||
        _batchDesc.text.trim().length < 3) {
      setState(
        () => _error =
            'Select Melt series UUID and enter Batch description (3+ characters).',
      );
      return;
    }
    final lossText = _allowedLoss.text.trim().isEmpty
        ? '0.000000'
        : _allowedLoss.text.trim();
    if (tryDec(lossText) == null) {
      setState(() => _error = 'Allowed fine loss g must be a valid decimal.');
      return;
    }

    final inputPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < _inputs.length; i++) {
      final inp = _inputs[i];
      if (inp.balanceIdCtrl.text.trim().isEmpty ||
          !isValidWeight(inp.qtyCtrl.text) ||
          !isValidWeight(inp.fineCtrl.text)) {
        setState(
          () => _error =
              'Complete Source balance UUID, Input quantity g, and Input fine g for line ${i + 1}.',
        );
        return;
      }
      inputPayload.add({
        'balanceId': inp.balanceIdCtrl.text.trim(),
        'expectedBalanceVersion': int.tryParse(inp.versionCtrl.text.trim()) ?? 1,
        'quantityGrams': normWeight6(inp.qtyCtrl.text),
        'fineWeightGrams': normWeight6(inp.fineCtrl.text),
      });
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/refining/batches',
        idempotent: true,
        body: {
          if (_refinerPartyId.text.trim().isNotEmpty)
            'refinerPartyId': _refinerPartyId.text.trim(),
          'documentSeriesId': _meltSeriesId.text.trim(),
          'businessDate': _businessDate.text.trim(),
          'description': _batchDesc.text.trim(),
          'allowedFineLossGrams': normWeight6(lossText),
          'inputs': inputPayload,
        },
      );
      if (!mounted) return;
      _batchDesc.clear();
      for (final inp in _inputs) {
        inp.dispose();
      }
      setState(() {
        _inputs
          ..clear()
          ..add(_RefiningInputDraft());
      });
      toast(context, 'Controlled refining / melt batch created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openBatchLifecycleSheet(Map<String, dynamic> batch) async {
    var actionTab = 'ASSAY';

    final assayFinenessCtrl = TextEditingController();
    final assayFineWtCtrl = TextEditingController();
    final assayCertCtrl = TextEditingController();
    final assayNotesCtrl = TextEditingController();

    final apvReasonCtrl = TextEditingController();

    final outLocCtrl = TextEditingController(
      text: _lk.locations.isNotEmpty ? _lk.locations.first.id : '',
    );
    final outMetalCtrl = TextEditingController(
      text: _lk.metals.isNotEmpty ? _lk.metals.first.id : '',
    );
    final outPurityCtrl = TextEditingController();
    final outLotCodeCtrl = TextEditingController();
    final outQtyCtrl = TextEditingController();
    final outFineCtrl = TextEditingController();
    final outLossCtrl = TextEditingController(text: '0.000000');
    final chargeAmtCtrl = TextEditingController();
    final periodCtrl = TextEditingController(
      text: _lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : '',
    );
    final jrnSeriesCtrl = TextEditingController(
      text: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? _lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
    final settleReasonCtrl = TextEditingController();

    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Manage Batch · ${batch['documentNumber'] ?? batch['batchNumber'] ?? shortId('${batch['id']}')}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${batch['state'] ?? batch['status'] ?? 'OPEN'}'),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PillTabs<String>(
                  value: actionTab,
                  onChanged: (v) => setSheet(() {
                    actionTab = v;
                    sheetErr = null;
                  }),
                  tabs: const [
                    ('ASSAY', 'Submit Assay'),
                    ('APPROVE', 'Approve Assay'),
                    ('SETTLE', 'Recoveries & FIFO Settle'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (actionTab == 'ASSAY') ...[
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Assayed fineness ‰',
                          controller: assayFinenessCtrl,
                          hint: '999.000000',
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Assayed fine 999 g',
                          controller: assayFineWtCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Assay certificate / lab ref',
                    controller: assayCertCtrl,
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Assay notes (optional)',
                    controller: assayNotesCtrl,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Submit Versioned Assay',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (tryDec(assayFinenessCtrl.text) == null ||
                                !isValidWeight(assayFineWtCtrl.text)) {
                              setSheet(
                                () => sheetErr =
                                    'Enter valid assayed fineness per thousand and fine 999 weight.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/refining/batches/${batch['id']}/assays',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(batch['version'], fallback: 1),
                                  'assayedFinenessPerThousand':
                                      normWeight6(assayFinenessCtrl.text),
                                  'assayedFineWeightGrams':
                                      normWeight6(assayFineWtCtrl.text),
                                  if (assayCertCtrl.text.trim().isNotEmpty)
                                    'certificateReference':
                                        assayCertCtrl.text.trim(),
                                  if (assayNotesCtrl.text.trim().isNotEmpty)
                                    'notes': assayNotesCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Versioned assay recorded.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (actionTab == 'APPROVE') ...[
                  Text(
                    'Maker-checker approval locks the current assay version before recovery settlement.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Assay approval reason (minimum 10 characters)',
                    controller: apvReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Approve Assay Version',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (apvReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter an approval reason of at least 10 characters.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/refining/batches/${batch['id']}/approve-assay',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(batch['version'], fallback: 1),
                                  'reason': apvReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Assay version approved.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  LookupField(
                    label: 'Destination vault / location UUID',
                    controller: outLocCtrl,
                    options: _lk.locations,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Recovered metal',
                    controller: outMetalCtrl,
                    options: _lk.metals,
                    onSelected: (_) => setSheet(() => outPurityCtrl.clear()),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Recovered purity grade',
                    controller: outPurityCtrl,
                    options: _lk.puritiesForMetal(outMetalCtrl.text.trim()),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Output bullion lot code',
                    controller: outLotCodeCtrl,
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Recovered qty g',
                          controller: outQtyCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Recovered fine 999 g',
                          controller: outFineCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Process loss fine g',
                          controller: outLossCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Refining charge (INR)',
                          controller: chargeAmtCtrl,
                          hint: '0.00',
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Posting Period UUID',
                    controller: periodCtrl,
                    options: _lk.openPeriods(),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Journal Series UUID',
                    controller: jrnSeriesCtrl,
                    options: _lk.seriesFor(const ['JOURNAL']),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Settlement audit reason (min 10 chars)',
                    controller: settleReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Record Recovery & Settle FIFO Cost',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (outLocCtrl.text.trim().isEmpty ||
                                outMetalCtrl.text.trim().isEmpty ||
                                outPurityCtrl.text.trim().isEmpty ||
                                outLotCodeCtrl.text.trim().isEmpty ||
                                !isValidWeight(outQtyCtrl.text) ||
                                !isValidWeight(outFineCtrl.text) ||
                                settleReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Complete destination location, metal, purity, lot code, recovered weights, and 10+ char reason.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/refining/batches/${batch['id']}/settle',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(batch['version'], fallback: 1),
                                  'businessDate': todayIso(),
                                  if (periodCtrl.text.trim().isNotEmpty)
                                    'postingPeriodId': periodCtrl.text.trim(),
                                  if (jrnSeriesCtrl.text.trim().isNotEmpty)
                                    'journalSeriesId': jrnSeriesCtrl.text.trim(),
                                  'processLossFineGrams': normWeight6(
                                    outLossCtrl.text.trim().isEmpty
                                        ? '0'
                                        : outLossCtrl.text,
                                  ),
                                  if (chargeAmtCtrl.text.trim().isNotEmpty)
                                    'refiningChargeAmount':
                                        normAmount(chargeAmtCtrl.text),
                                  'recoveries': [
                                    {
                                      'locationId': outLocCtrl.text.trim(),
                                      'metalId': outMetalCtrl.text.trim(),
                                      'purityGradeId': outPurityCtrl.text.trim(),
                                      'lotCode': outLotCodeCtrl.text
                                          .trim()
                                          .toUpperCase(),
                                      'quantityGrams':
                                          normWeight6(outQtyCtrl.text),
                                      'fineWeightGrams':
                                          normWeight6(outFineCtrl.text),
                                    },
                                  ],
                                  'reason': settleReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(
                                context,
                                'Refining batch recovery & FIFO cost settled.',
                              );
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    for (final c in [
      assayFinenessCtrl,
      assayFineWtCtrl,
      assayCertCtrl,
      assayNotesCtrl,
      apvReasonCtrl,
      outLocCtrl,
      outMetalCtrl,
      outPurityCtrl,
      outLotCodeCtrl,
      outQtyCtrl,
      outFineCtrl,
      outLossCtrl,
      chargeAmtCtrl,
      periodCtrl,
      jrnSeriesCtrl,
      settleReasonCtrl,
    ]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final q = _search.text.trim().toLowerCase();
    bool isDone(Map<String, dynamic> b) {
      final s = '${b['state'] ?? b['status'] ?? ''}'.toUpperCase();
      return s == 'SETTLED' || s == 'COMPLETED' || s == 'POSTED';
    }

    final inProcCnt = _batches.where((b) => !isDone(b)).length;
    final doneCnt = _batches.where(isDone).length;
    final filtered = _batches.where((b) {
      if (_filter == 'IN_PROCESS' && isDone(b)) return false;
      if (_filter == 'COMPLETED' && !isDone(b)) return false;
      if (q.isEmpty) return true;
      final hay =
          '${b['documentNumber'] ?? ''} ${b['batchNumber'] ?? ''} ${b['description'] ?? ''} ${asMap(b['refiner'])['displayName'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Refining & Melting',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.factory_outlined,
      searchController: _search,
      searchHint: 'Search by Batch No. / Refiner...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${_batches.length})'),
          ('IN_PROCESS', 'In Process ($inProcCnt)'),
          ('COMPLETED', 'Completed ($doneCnt)'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Hero Header Card (`Refining & Melting` — image-24.png)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Pal.goldTint,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Pal.borderGold),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.toll_rounded,
                          size: 13,
                          color: Pal.goldDeep,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            gold999 != null
                                ? 'Bullion 24K: Fine 999 Board Active · ${inr(gold999.sell)}/g'
                                : 'Bullion 24K: Fine 999 Board Active',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body(
                              11.5,
                              weight: FontWeight.w700,
                              color: Pal.goldDeep,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.factory_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Refining & Melting',
                          style: T.body(
                            16,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Controlled batch genealogy, versioned assay approval, recoveries, process loss and FIFO cost allocation.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // `New melt batch` card (exact 9 fields from image-24.png)
            SaasFormCard(
              title: 'New melt batch',
              trailing: TextButton(
                onPressed: () => setState(() => _formExpanded = !_formExpanded),
                child: Text(_formExpanded ? 'Hide' : 'Show'),
              ),
              child: !_formExpanded
                  ? Text(
                      'Tap Show to create a controlled melt or refining batch.',
                      style: T.body(12.2, color: Pal.muted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LookupField(
                          label: 'Refiner party UUID (optional)',
                          controller: _refinerPartyId,
                          options: _lk.partiesByRole('REFINER'),
                          hint: 'Select refiner party (optional)',
                          optional: true,
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Melt series UUID',
                          controller: _meltSeriesId,
                          options: _lk.seriesFor(
                            const ['MELT', 'REFINING', 'BATCH'],
                          ),
                          hint: 'Select melt series',
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DatePickField(
                                label: 'Business date',
                                controller: _businessDate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'Allowed fine loss g',
                                controller: _allowedLoss,
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SaasField(
                          label: 'Batch description',
                          controller: _batchDesc,
                        ),
                        const SizedBox(height: 12),

                        for (var i = 0; i < _inputs.length; i++) ...[
                          if (i > 0) const SizedBox(height: 10),
                          SaasSubBox(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_inputs.length > 1)
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          'Source input ${i + 1}',
                                          style: T.body(
                                            12.2,
                                            weight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor: Pal.err,
                                        ),
                                        onPressed: () {
                                          final removed = _inputs.removeAt(i);
                                          removed.dispose();
                                          setState(() {});
                                        },
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 15,
                                        ),
                                        label: const Text('Remove'),
                                      ),
                                    ],
                                  ),
                                LookupField(
                                  label: 'Source balance UUID',
                                  controller: _inputs[i].balanceIdCtrl,
                                  options: _lk.lotBalances,
                                  hint: 'Select source lot balance',
                                  onSelected: (opt) {
                                    if (opt != null) {
                                      setState(() {
                                        _inputs[i].versionCtrl.text =
                                            '${opt.raw['balanceVersion'] ?? opt.raw['version'] ?? 1}';
                                        _inputs[i].qtyCtrl.text =
                                            '${opt.raw['quantityGrams'] ?? ''}';
                                        _inputs[i].fineCtrl.text =
                                            '${opt.raw['fineWeightGrams'] ?? ''}';
                                      });
                                    }
                                  },
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SaasField(
                                        label: 'Balance version',
                                        controller: _inputs[i].versionCtrl,
                                        mono: true,
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: SaasField(
                                        label: 'Input quantity g',
                                        controller: _inputs[i].qtyCtrl,
                                        mono: true,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SaasField(
                                  label: 'Input fine g',
                                  controller: _inputs[i].fineCtrl,
                                  mono: true,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () =>
                                setState(() => _inputs.add(_RefiningInputDraft())),
                            icon: const Icon(Icons.add_rounded, size: 16),
                            label: const Text('Add source balance'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        RoyalGoldButton(
                          label: 'Create controlled batch',
                          busy: _busy,
                          onPressed: _busy ? null : _createBatch,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Panel(child: Skeleton(height: 92))
            else if (filtered.isEmpty)
              const SaasEmptyBox('No refining batches yet.')
            else
              for (final b in filtered)
                LuxuryRecordCard(
                  icon: Icons.factory_outlined,
                  code:
                      '${b['documentNumber'] ?? b['batchNumber'] ?? shortId('${b['id']}')}',
                  status: '${b['state'] ?? b['status'] ?? 'OPEN'}',
                  lines: [
                    if ('${asMap(b['refiner'])['displayName'] ?? ''}'.isNotEmpty)
                      ('Refiner', '${asMap(b['refiner'])['displayName']}'),
                    if ('${b['description'] ?? ''}'.isNotEmpty)
                      ('Description', '${b['description']}'),
                    ('Business Date', fmtDate('${b['businessDate'] ?? ''}')),
                    (
                      'Allowed Loss',
                      grams(b['allowedFineLossGrams'] ?? '0'),
                    ),
                  ],
                  amountLabel: 'In / Out Fine',
                  amountValue:
                      '${grams(b['inputFineGrams'])} → ${grams(b['outputFineGrams'])}',
                  actions: [
                    GoldButton(
                      label: 'Manage Batch',
                      compact: true,
                      onPressed: () => _openBatchLifecycleSheet(b),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. INTER-BRANCH TRANSFERS (`/stock-transfers`) — Screenshot (681)
// ---------------------------------------------------------------------------

class InterBranchTransfersScreen extends StatefulWidget {
  const InterBranchTransfersScreen({super.key});
  @override
  State<InterBranchTransfersScreen> createState() => _InterBranchTransfersScreenState();
}

class _TransferDraftLine {
  const _TransferDraftLine({
    required this.stockKind,
    required this.stockId,
    required this.stockLabel,
    required this.destinationLocationId,
    required this.destinationLabel,
    this.quantityGrams = '',
  });
  final String stockKind; // TAGGED_ARTICLE | MATERIAL_LOT
  final String stockId;
  final String stockLabel;
  final String destinationLocationId;
  final String destinationLabel;
  final String quantityGrams;
}

class _InterBranchTransfersScreenState extends State<InterBranchTransfersScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _showForm = false;
  List<Map<String, dynamic>> _transfers = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _destBranchId = TextEditingController();
  final _sourceTransitId = TextEditingController();
  final _seriesId = TextEditingController();
  final _businessDate = TextEditingController(text: todayIso());
  final _expectedReceipt = TextEditingController(text: todayIso());
  final _description = TextEditingController();

  String _stockKind = 'TAGGED_ARTICLE';
  final _stockId = TextEditingController();
  final _destCustodyId = TextEditingController();
  final _qtyGrams = TextEditingController();
  final List<_TransferDraftLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _search, _destBranchId, _sourceTransitId, _seriesId, _businessDate,
      _expectedReceipt, _description, _stockId, _destCustodyId, _qtyGrams,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait([
        api.get('/stock-transfers'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeInventory: true,
          includeAccounting: true,
          includeOrganization: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _transfers = asList(res[0], keys: const ['transfers', 'stockTransfers', 'items']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addLine() {
    if (_stockId.text.trim().isEmpty || _destCustodyId.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select available stock and destination custody.')),
      );
      return;
    }
    final pool = _stockKind == 'TAGGED_ARTICLE' ? _lk.articles : _lk.lotBalances;
    final sLabel = pool.where((o) => o.id == _stockId.text.trim()).firstOrNull?.label ?? _stockId.text.trim();
    final dLabel = _lk.locations.where((o) => o.id == _destCustodyId.text.trim()).firstOrNull?.label ?? _destCustodyId.text.trim();
    setState(() {
      _lines.add(_TransferDraftLine(
        stockKind: _stockKind,
        stockId: _stockId.text.trim(),
        stockLabel: sLabel,
        destinationLocationId: _destCustodyId.text.trim(),
        destinationLabel: dLabel,
        quantityGrams: _qtyGrams.text.trim(),
      ));
      _stockId.clear();
      _qtyGrams.clear();
    });
  }

  Future<void> _createTransfer() async {
    if (_destBranchId.text.trim().isEmpty ||
        _sourceTransitId.text.trim().isEmpty ||
        _seriesId.text.trim().isEmpty) {
      setState(() => _error = 'Select Destination branch, Source transit custody, and Transfer series.');
      return;
    }
    if (_lines.isEmpty) {
      _addLine();
      if (_lines.isEmpty) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/stock-transfers',
        idempotent: true,
        body: {
          'destinationBranchId': _destBranchId.text.trim(),
          'sourceTransitLocationId': _sourceTransitId.text.trim(),
          'documentSeriesId': _seriesId.text.trim(),
          'businessDate': _businessDate.text.trim(),
          'expectedReceiptDate': _expectedReceipt.text.trim(),
          if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
          'lines': _lines
              .map((l) => l.stockKind == 'TAGGED_ARTICLE'
                  ? {
                      'stockKind': 'TAGGED_ARTICLE',
                      'articleId': l.stockId,
                      'destinationLocationId': l.destinationLocationId,
                    }
                  : {
                      'stockKind': 'MATERIAL_LOT',
                      'balanceId': l.stockId,
                      'destinationLocationId': l.destinationLocationId,
                      if (l.quantityGrams.isNotEmpty) 'quantityGrams': l.quantityGrams,
                    })
              .toList(),
        },
      );
      if (!mounted) return;
      setState(() {
        _lines.clear();
        _showForm = false;
      });
      _description.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inter-branch transfer created.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    bool isRecv(Map<String, dynamic> t) {
      final s = '${t['state'] ?? t['status'] ?? ''}'.toUpperCase();
      return s == 'RECEIVED' || s == 'COMPLETED' || s == 'CLOSED';
    }

    final transitCnt = _transfers.where((t) => !isRecv(t)).length;
    final recvCnt = _transfers.where(isRecv).length;
    final filtered = _transfers.where((t) {
      if (_filter == 'TRANSIT' && isRecv(t)) return false;
      if (_filter == 'RECEIVED' && !isRecv(t)) return false;
      if (q.isEmpty) return true;
      final hay = '${t['documentNumber'] ?? ''} ${t['transferNumber'] ?? ''} ${asMap(t['destinationBranch'])['name'] ?? ''} ${t['description'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Inter-Branch Transfers',
      icon: Icons.swap_horiz_rounded,
      searchController: _search,
      searchHint: 'Search by Transfer No. / Branch...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${_transfers.length})'),
          ('TRANSIT', 'In Transit ($transitCnt)'),
          ('RECEIVED', 'Received ($recvCnt)'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'New Transfer Request',
        onPressed: () => setState(() => _showForm = !_showForm),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            if (_showForm) ...[
              SaasFormCard(
                title: 'New transfer request',
                trailing: TextButton(
                  onPressed: () => setState(() => _showForm = false),
                  child: const Text('Close'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Destination branch',
                      controller: _destBranchId,
                      options: _lk.branches,
                      hint: 'Select',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Source transit custody',
                      controller: _sourceTransitId,
                      options: _lk.locationsByType(const ['TRANSIT', 'VAULT']),
                      hint: 'Select',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Transfer series',
                      controller: _seriesId,
                      options: _lk.seriesFor(const ['TRANSFER', 'STOCK_TRANSFER']),
                      hint: 'Select',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: DatePickField(label: 'Business date', controller: _businessDate)),
                        const SizedBox(width: 10),
                        Expanded(child: DatePickField(label: 'Expected receipt', controller: _expectedReceipt)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(label: 'Description', controller: _description),
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SaasDropdown(
                            label: 'Stock kind',
                            value: _stockKind,
                            options: const {
                              'TAGGED_ARTICLE': 'Tagged article',
                              'MATERIAL_LOT': 'Material lot',
                            },
                            onChanged: (v) => setState(() {
                              _stockKind = v;
                              _stockId.clear();
                            }),
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Available stock',
                            controller: _stockId,
                            options: _stockKind == 'TAGGED_ARTICLE' ? _lk.articles : _lk.lotBalances,
                            hint: 'Select',
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Destination custody',
                            controller: _destCustodyId,
                            options: _lk.locations,
                            hint: 'Select',
                          ),
                          if (_stockKind == 'MATERIAL_LOT') ...[
                            const SizedBox(height: 10),
                            SaasField(
                              label: 'Quantity grams',
                              controller: _qtyGrams,
                              mono: true,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: _addLine,
                              child: const Text('+ Add transfer line'),
                            ),
                          ),
                          for (var i = 0; i < _lines.length; i++) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_lines[i].stockLabel} → ${_lines[i].destinationLabel}',
                                    style: T.body(12.2, w: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close_rounded, size: 17, color: Pal.err),
                                  onPressed: () => setState(() => _lines.removeAt(i)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GoldButton(
                      label: _busy ? 'Saving…' : 'Create Transfer',
                      busy: _busy,
                      onPressed: _createTransfer,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const SaasEmptyBox('No inter-branch transfers found. Tap + to create a transfer.')
            else
              for (final t in filtered)
                LuxuryRecordCard(
                  icon: Icons.storefront_outlined,
                  code: '${t['documentNumber'] ?? t['transferNumber'] ?? shortId('${t['id']}')}',
                  status: '${t['state'] ?? t['status'] ?? 'DRAFT'}',
                  lines: [
                    if ('${asMap(t['sourceBranch'])['name'] ?? ''}'.isNotEmpty)
                      ('From', '${asMap(t['sourceBranch'])['name']}'),
                    ('To', '${asMap(t['destinationBranch'])['name'] ?? 'Destination Branch'}'),
                    ('Date', '${fmtDate('${t['businessDate'] ?? ''}')} → ${fmtDate('${t['expectedReceiptDate'] ?? ''}')}'),
                    if ('${t['description'] ?? ''}'.isNotEmpty) ('Notes', '${t['description']}'),
                  ],
                  amountLabel: 'Status',
                  amountValue: statusLabel('${t['state'] ?? t['status'] ?? 'DRAFT'}'),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. INTER-ENTITY TRADING (`/inter-entity-trades`) — Screenshot (684)
// ---------------------------------------------------------------------------

class InterEntityTradingScreen extends StatefulWidget {
  const InterEntityTradingScreen({super.key});
  @override
  State<InterEntityTradingScreen> createState() => _InterEntityTradingScreenState();
}

class _TradeDraftLine {
  const _TradeDraftLine({
    required this.sourceArticleId,
    required this.articleLabel,
    required this.destinationLocationId,
    required this.newDestinationTag,
    required this.taxableValue,
    required this.igstAmount,
  });
  final String sourceArticleId;
  final String articleLabel;
  final String destinationLocationId;
  final String newDestinationTag;
  final String taxableValue;
  final String igstAmount;
}

class _InterEntityTradingScreenState extends State<InterEntityTradingScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _showForm = false;
  List<Map<String, dynamic>> _trades = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _destEntityId = TextEditingController();
  final _destBranchId = TextEditingController();
  final _sourceTransitId = TextEditingController();
  final _seriesId = TextEditingController();
  String _taxTreatment = 'INTER_STATE_IGST';
  final _currency = TextEditingController(text: 'INR');
  final _requestDate = TextEditingController(text: todayIso());
  final _expectedReceipt = TextEditingController(text: todayIso());
  final _terms = TextEditingController();

  final _sourceArticleId = TextEditingController();
  final _destLocationId = TextEditingController();
  final _newDestTag = TextEditingController();
  final _taxableVal = TextEditingController();
  final _igstAmt = TextEditingController(text: '0.00');
  final List<_TradeDraftLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _search, _destEntityId, _destBranchId, _sourceTransitId, _seriesId,
      _currency, _requestDate, _expectedReceipt, _terms,
      _sourceArticleId, _destLocationId, _newDestTag, _taxableVal, _igstAmt,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait([
        api.get('/inter-entity-trades'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeInventory: true,
          includeAccounting: true,
          includeOrganization: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _trades = asList(res[0], keys: const ['trades', 'interEntityTrades', 'items']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addLine() {
    if (_sourceArticleId.text.trim().isEmpty ||
        _destLocationId.text.trim().isEmpty ||
        _newDestTag.text.trim().isEmpty ||
        _taxableVal.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Complete source article, destination location, new tag, and taxable value.')),
      );
      return;
    }
    final label = _lk.articles
            .where((a) => a.id == _sourceArticleId.text.trim())
            .firstOrNull
            ?.label ??
        _sourceArticleId.text.trim();
    setState(() {
      _lines.add(_TradeDraftLine(
        sourceArticleId: _sourceArticleId.text.trim(),
        articleLabel: label,
        destinationLocationId: _destLocationId.text.trim(),
        newDestinationTag: _newDestTag.text.trim().toUpperCase(),
        taxableValue: _taxableVal.text.trim(),
        igstAmount: _igstAmt.text.trim().isEmpty ? '0.00' : _igstAmt.text.trim(),
      ));
      _sourceArticleId.clear();
      _newDestTag.clear();
      _taxableVal.clear();
      _igstAmt.text = '0.00';
    });
  }

  Future<void> _createTrade() async {
    if (_destEntityId.text.trim().isEmpty ||
        _destBranchId.text.trim().isEmpty ||
        _sourceTransitId.text.trim().isEmpty ||
        _seriesId.text.trim().isEmpty) {
      setState(() => _error = 'Select Destination entity, Destination branch, Source transit, and Trade series.');
      return;
    }
    if (_lines.isEmpty) {
      _addLine();
      if (_lines.isEmpty) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/inter-entity-trades',
        idempotent: true,
        body: {
          'destinationLegalEntityId': _destEntityId.text.trim(),
          'destinationBranchId': _destBranchId.text.trim(),
          'sourceTransitLocationId': _sourceTransitId.text.trim(),
          'documentSeriesId': _seriesId.text.trim(),
          'taxTreatment': _taxTreatment,
          'currency': _currency.text.trim().toUpperCase(),
          'requestDate': _requestDate.text.trim(),
          'expectedReceiptDate': _expectedReceipt.text.trim(),
          if (_terms.text.trim().isNotEmpty) 'terms': _terms.text.trim(),
          'lines': _lines
              .map((l) => {
                    'sourceArticleId': l.sourceArticleId,
                    'destinationLocationId': l.destinationLocationId,
                    'newDestinationTag': l.newDestinationTag,
                    'taxableAmount': l.taxableValue,
                    'igstAmount': l.igstAmount,
                  })
              .toList(),
        },
      );
      if (!mounted) return;
      setState(() {
        _lines.clear();
        _showForm = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Related-entity jewellery trade created.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destBranches = _destEntityId.text.trim().isEmpty
        ? _lk.branches
        : _lk.branches
            .where((b) => '${b.raw['legalEntityId'] ?? ''}' == _destEntityId.text.trim())
            .toList();

    final q = _search.text.trim().toLowerCase();
    bool isDone(Map<String, dynamic> t) {
      final s = '${t['state'] ?? t['status'] ?? ''}'.toUpperCase();
      return s == 'SETTLED' || s == 'RECEIVED' || s == 'COMPLETED';
    }

    final pendCnt = _trades.where((t) => !isDone(t)).length;
    final doneCnt = _trades.where(isDone).length;
    final filtered = _trades.where((t) {
      if (_filter == 'PENDING' && isDone(t)) return false;
      if (_filter == 'COMPLETED' && !isDone(t)) return false;
      if (q.isEmpty) return true;
      final hay = '${t['documentNumber'] ?? ''} ${t['tradeNumber'] ?? ''} ${asMap(t['destinationLegalEntity'])['legalName'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Inter-Entity Trading',
      icon: Icons.domain_rounded,
      searchController: _search,
      searchHint: 'Search by Entity / Trade No...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${_trades.length})'),
          ('PENDING', 'Pending ($pendCnt)'),
          ('COMPLETED', 'Completed ($doneCnt)'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'New Inter-Entity Trade',
        onPressed: () => setState(() => _showForm = !_showForm),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            if (_showForm) ...[
              SaasFormCard(
                title: 'New related-entity trade',
                trailing: TextButton(
                  onPressed: () => setState(() => _showForm = false),
                  child: const Text('Close'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Destination entity',
                      controller: _destEntityId,
                      options: _lk.legalEntities,
                      hint: 'Select',
                      onSelected: (_) => setState(() => _destBranchId.clear()),
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Destination branch',
                      controller: _destBranchId,
                      options: destBranches.isNotEmpty ? destBranches : _lk.branches,
                      hint: 'Select',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Source transit',
                      controller: _sourceTransitId,
                      options: _lk.locationsByType(const ['TRANSIT', 'VAULT']),
                      hint: 'Select',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Trade series',
                      controller: _seriesId,
                      options: _lk.seriesFor(const ['TRADE', 'INTER_ENTITY']),
                      hint: 'Select',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SaasDropdown(
                            label: 'Tax treatment',
                            value: _taxTreatment,
                            options: const {
                              'INTER_STATE_IGST': 'Inter-state IGST',
                              'INTRA_STATE_CGST_SGST': 'Intra-state CGST+SGST',
                            },
                            onChanged: (v) => setState(() => _taxTreatment = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(label: 'Currency', controller: _currency, mono: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: DatePickField(label: 'Request date', controller: _requestDate)),
                        const SizedBox(width: 10),
                        Expanded(child: DatePickField(label: 'Expected receipt', controller: _expectedReceipt)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(label: 'Terms', controller: _terms),
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LookupField(
                            label: 'Source article',
                            controller: _sourceArticleId,
                            options: _lk.articles,
                            hint: 'Select',
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Destination location',
                            controller: _destLocationId,
                            options: _lk.locations,
                            hint: 'Select',
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label: 'New destination tag',
                            controller: _newDestTag,
                            mono: true,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Taxable value',
                                  controller: _taxableVal,
                                  mono: true,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasField(
                                  label: 'IGST',
                                  controller: _igstAmt,
                                  mono: true,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              onPressed: _addLine,
                              child: const Text('+ Add line'),
                            ),
                          ),
                          for (var i = 0; i < _lines.length; i++) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_lines[i].articleLabel} → ${_lines[i].newDestinationTag} · ₹${_lines[i].taxableValue}',
                                    style: T.body(12.2, w: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close_rounded, size: 17, color: Pal.err),
                                  onPressed: () => setState(() => _lines.removeAt(i)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    GoldButton(
                      label: _busy ? 'Saving…' : 'Create Trade',
                      busy: _busy,
                      onPressed: _createTrade,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const SaasEmptyBox('No related-entity jewellery trades found. Tap + to create a trade.')
            else
              for (final t in filtered)
                LuxuryRecordCard(
                  icon: Icons.domain_rounded,
                  code: '${asMap(t['destinationLegalEntity'])['legalName'] ?? t['documentNumber'] ?? shortId('${t['id']}')}',
                  status: '${t['state'] ?? t['status'] ?? 'DRAFT'}',
                  lines: [
                    ('Ref', '${t['documentNumber'] ?? t['tradeNumber'] ?? shortId('${t['id']}')}'),
                    ('Date', '${fmtDate('${t['requestDate'] ?? ''}')} → ${fmtDate('${t['expectedReceiptDate'] ?? ''}')}'),
                  ],
                  amountLabel: 'Amount',
                  amountValue: inr(t['totalAmount'] ?? t['taxableAmount']),
                ),
          ],
        ),
      ),
    );
  }
}
