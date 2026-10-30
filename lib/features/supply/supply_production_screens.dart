import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

// ---------------------------------------------------------------------------
// 1. CUSTOM ORDERS (`/custom-orders`)
// ---------------------------------------------------------------------------

class CustomOrdersScreen extends StatefulWidget {
  const CustomOrdersScreen({super.key});
  @override
  State<CustomOrdersScreen> createState() => _CustomOrdersScreenState();
}

class _CustomOrdersScreenState extends State<CustomOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _partyId = TextEditingController();
  final _seriesId = TextEditingController();
  final _orderDate = TextEditingController(text: todayIso());
  final _promisedDate = TextEditingController(text: todayIso());
  final _metalId = TextEditingController();
  final _purityId = TextEditingController();
  final _estGrams = TextEditingController();
  final _quotedMaking = TextEditingController(text: '0.00');
  final _advanceAmt = TextEditingController(text: '0.00');
  final _spec = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _partyId, _seriesId, _orderDate, _promisedDate,
      _metalId, _purityId, _estGrams, _quotedMaking, _advanceAmt, _spec,
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
        api.get('/custom-orders'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeMaterials: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = asList(res[0], keys: const ['orders', 'customOrders', 'items']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createOrder() async {
    if (_partyId.text.trim().isEmpty ||
        _metalId.text.trim().isEmpty ||
        _purityId.text.trim().isEmpty ||
        _estGrams.text.trim().isEmpty ||
        _spec.text.trim().length < 3) {
      setState(() => _error = 'Select customer, metal, purity, estimated weight, and design specification.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/custom-orders',
        idempotent: true,
        body: {
          'customerPartyId': _partyId.text.trim(),
          if (_seriesId.text.trim().isNotEmpty) 'documentSeriesId': _seriesId.text.trim(),
          'orderDate': _orderDate.text.trim(),
          'promisedDate': _promisedDate.text.trim(),
          'metalId': _metalId.text.trim(),
          'purityGradeId': _purityId.text.trim(),
          'estimatedWeightGrams': _estGrams.text.trim(),
          'quotedMakingAmount': _quotedMaking.text.trim().isEmpty ? '0.00' : _quotedMaking.text.trim(),
          'advanceAmount': _advanceAmt.text.trim().isEmpty ? '0.00' : _advanceAmt.text.trim(),
          'currency': 'INR',
          'description': _spec.text.trim(),
        },
      );
      if (!mounted) return;
      _estGrams.clear();
      _spec.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom order created.')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Orders'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.auto_awesome_outlined,
              title: 'Custom Orders & Made-to-Order',
              subtitle:
                  'Bespoke customer design specifications, metal/purity targets, advance booking, and Karigar linkage.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'New custom order',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Customer',
                    controller: _partyId,
                    options: _lk.partiesByRole('CUSTOMER'),
                    hint: 'Select',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Order series',
                    controller: _seriesId,
                    options: _lk.seriesFor(const ['CUSTOM', 'ORDER']),
                    optional: true,
                    hint: 'Select',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: DatePickField(label: 'Order date', controller: _orderDate)),
                      const SizedBox(width: 10),
                      Expanded(child: DatePickField(label: 'Promised delivery', controller: _promisedDate)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Metal',
                    controller: _metalId,
                    options: _lk.metals,
                    hint: 'Select',
                    onSelected: (_) => setState(() => _purityId.clear()),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Purity grade',
                    controller: _purityId,
                    options: _lk.puritiesForMetal(_metalId.text.trim()),
                    hint: 'Select',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Estimated weight g',
                          controller: _estGrams,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Quoted making (INR)',
                          controller: _quotedMaking,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Advance receipt (INR)',
                    controller: _advanceAmt,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Design & size specification',
                    controller: _spec,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _createOrder,
                      child: Text(_busy ? 'Saving…' : 'Create custom order'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_orders.isEmpty)
              const SaasEmptyBox('No custom orders yet.')
            else
              for (final o in _orders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${o['documentNumber'] ?? o['orderNumber'] ?? shortId('${o['id']}')} · ${asMap(o['customer'])['displayName'] ?? 'Customer'}',
                                style: T.body(14, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${o['state'] ?? o['status'] ?? 'OPEN'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Promised Delivery', fmtDate('${o['promisedDate'] ?? ''}')),
                        KVRow('Est. Weight / Advance', '${grams(o['estimatedWeightGrams'])} · ${inr(o['advanceAmount'])}', bold: true),
                        if ('${o['description'] ?? ''}'.isNotEmpty)
                          KVRow('Design', '${o['description']}'),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. REPAIRS & CUSTOMER CUSTODY (`/repairs`)
// ---------------------------------------------------------------------------

class RepairsCustodyScreen extends StatefulWidget {
  const RepairsCustodyScreen({super.key});
  @override
  State<RepairsCustodyScreen> createState() => _RepairsCustodyScreenState();
}

class _RepairsCustodyScreenState extends State<RepairsCustodyScreen> {
  List<Map<String, dynamic>> _repairs = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _partyId = TextEditingController();
  final _custodyLocId = TextEditingController();
  final _seriesId = TextEditingController();
  final _intakeDate = TextEditingController(text: todayIso());
  final _promisedDate = TextEditingController(text: todayIso());
  final _articleDesc = TextEditingController();
  final _grossGrams = TextEditingController();
  final _estCharge = TextEditingController(text: '0.00');
  final _conditionNotes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _partyId, _custodyLocId, _seriesId, _intakeDate, _promisedDate,
      _articleDesc, _grossGrams, _estCharge, _conditionNotes,
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
        api.get('/repairs'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _repairs = asList(res[0], keys: const ['repairs', 'jobs', 'items']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createRepair() async {
    if (_partyId.text.trim().isEmpty ||
        _custodyLocId.text.trim().isEmpty ||
        _articleDesc.text.trim().length < 3 ||
        _grossGrams.text.trim().isEmpty) {
      setState(() => _error = 'Select customer, custody location, article description, and gross weight.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/repairs',
        idempotent: true,
        body: {
          'customerPartyId': _partyId.text.trim(),
          'custodyLocationId': _custodyLocId.text.trim(),
          if (_seriesId.text.trim().isNotEmpty) 'documentSeriesId': _seriesId.text.trim(),
          'intakeDate': _intakeDate.text.trim(),
          'promisedDate': _promisedDate.text.trim(),
          'articleDescription': _articleDesc.text.trim(),
          'receivedGrossWeightGrams': _grossGrams.text.trim(),
          'estimatedChargeAmount': _estCharge.text.trim().isEmpty ? '0.00' : _estCharge.text.trim(),
          'currency': 'INR',
          if (_conditionNotes.text.trim().isNotEmpty) 'conditionNotes': _conditionNotes.text.trim(),
        },
      );
      if (!mounted) return;
      _articleDesc.clear();
      _grossGrams.clear();
      _conditionNotes.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Repair custody receipt recorded.')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repairs & Custody'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.build_outlined,
              title: 'Repairs & Customer Custody',
              subtitle:
                  'Segregated customer-owned jewellery intake, stone/condition notes, workshop custody, and delivery sign-off.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'New customer repair intake',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Customer',
                    controller: _partyId,
                    options: _lk.partiesByRole('CUSTOMER'),
                    hint: 'Select',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Customer custody location',
                    controller: _custodyLocId,
                    options: _lk.locationsByType(const ['CUSTOMER_CUSTODY', 'QUARANTINE', 'VAULT']),
                    hint: 'Select',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Repair series',
                    controller: _seriesId,
                    options: _lk.seriesFor(const ['REPAIR', 'CUSTODY']),
                    optional: true,
                    hint: 'Select',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: DatePickField(label: 'Intake date', controller: _intakeDate)),
                      const SizedBox(width: 10),
                      Expanded(child: DatePickField(label: 'Promised date', controller: _promisedDate)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(label: 'Article description', controller: _articleDesc),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Received gross weight g',
                          controller: _grossGrams,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Estimated charge (INR)',
                          controller: _estCharge,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Condition & stone remarks',
                    controller: _conditionNotes,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _createRepair,
                      child: Text(_busy ? 'Saving…' : 'Receive customer article'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_repairs.isEmpty)
              const SaasEmptyBox('No repair or customer custody jobs yet.')
            else
              for (final r in _repairs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${r['documentNumber'] ?? r['jobNumber'] ?? shortId('${r['id']}')} · ${asMap(r['customer'])['displayName'] ?? r['articleDescription'] ?? ''}',
                                style: T.body(14, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${r['state'] ?? r['status'] ?? 'RECEIVED'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Received Gross Wt', grams(r['receivedGrossWeightGrams']), bold: true),
                        KVRow('Promised Date', fmtDate('${r['promisedDate'] ?? ''}')),
                      ],
                    ),
                  ),
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
  Map<String, dynamic> _materials = const {};
  List<Map<String, dynamic>> _rateBooks = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _openPanel; // null | 'METAL' | 'PURITY' | 'BOOK'

  // Add metal / purity / rate book
  final _metalCode = TextEditingController();
  final _metalName = TextEditingController();
  final _gradeMetalId = TextEditingController();
  final _gradeCode = TextEditingController();
  final _gradeKarat = TextEditingController();
  final _gradeFineness = TextEditingController();
  final _bookCode = TextEditingController();
  final _bookName = TextEditingController();
  final _bookCurrency = TextEditingController(text: 'INR');

  // Create complete rate version (`POST /rate-books/:id/versions`)
  Map<String, dynamic>? _versionTargetBook;
  final List<_RateLineDraft> _versionLines = [_RateLineDraft()];

  // Authoritative metal-price check (`POST /pricing/calculate-metal`)
  final _calcRateVersionId = TextEditingController();
  final _calcMetalId = TextEditingController();
  final _calcPurityId = TextEditingController();
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
    for (final c in [
      _metalCode, _metalName, _gradeMetalId, _gradeCode, _gradeKarat,
      _gradeFineness, _bookCode, _bookName, _bookCurrency,
      _calcRateVersionId, _calcMetalId, _calcPurityId, _calcWeight,
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
        api.get('/materials'),
        api.get('/rates'),
      ]);
      if (!mounted) return;
      context.read<RatesStore>().refresh();
      setState(() {
        _materials = asMap(res[0]);
        _rateBooks = asList(res[1], keys: const ['rateBooks', 'books', 'items']);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LookupOption> get _metalOpts => asList(_materials['metals'])
      .map((m) => LookupOption(id: '${m['id']}', label: '${m['name']} (${m['code']})', raw: m))
      .where((o) => o.id.isNotEmpty)
      .toList();

  List<LookupOption> _purityOpts(String? metalId) {
    final out = <LookupOption>[];
    for (final m in asList(_materials['metals'])) {
      if (metalId != null && metalId.isNotEmpty && '${m['id']}' != metalId) continue;
      for (final pg in asList(m['purityGrades'])) {
        out.add(LookupOption(
          id: '${pg['id']}',
          label: '${m['code']} · ${pg['code']}${pg['displayKarat'] != null ? ' (${pg['displayKarat']})' : ''} · ${pg['finenessPerThousand']}‰',
          raw: pg,
        ));
      }
    }
    return out;
  }

  List<LookupOption> get _massUnitOpts => asList(_materials['units'])
      .where((u) => '${u['dimension'] ?? 'MASS'}' == 'MASS')
      .map((u) => LookupOption(id: '${u['id']}', label: '${u['code']} (${u['symbol'] ?? u['code']})', raw: u))
      .where((o) => o.id.isNotEmpty)
      .toList();

  List<LookupOption> get _publishedVersionOpts {
    final out = <LookupOption>[];
    for (final b in _rateBooks) {
      for (final v in asList(b['versions'])) {
        if ('${v['state']}' == 'PUBLISHED') {
          out.add(LookupOption(
            id: '${v['id']}',
            label: '${b['name']} · v${v['sequenceNumber']}',
            raw: v,
          ));
        }
      }
    }
    return out;
  }

  Future<void> _submitQuickMaster() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      if (_openPanel == 'METAL') {
        await api.post('/materials/metals', idempotent: true, body: {
          'code': _metalCode.text.trim().toUpperCase(),
          'name': _metalName.text.trim(),
        });
        _metalCode.clear();
        _metalName.clear();
      } else if (_openPanel == 'PURITY') {
        await api.post('/materials/purity-grades', idempotent: true, body: {
          'metalId': _gradeMetalId.text.trim(),
          'code': _gradeCode.text.trim().toUpperCase(),
          if (_gradeKarat.text.trim().isNotEmpty) 'displayKarat': _gradeKarat.text.trim(),
          'finenessPerThousand': _gradeFineness.text.trim(),
        });
        _gradeCode.clear();
        _gradeKarat.clear();
        _gradeFineness.clear();
      } else if (_openPanel == 'BOOK') {
        await api.post('/rate-books', idempotent: true, body: {
          'code': _bookCode.text.trim().toUpperCase(),
          'name': _bookName.text.trim(),
          'currency': _bookCurrency.text.trim().toUpperCase(),
        });
        _bookCode.clear();
        _bookName.clear();
      }
      if (!mounted) return;
      setState(() => _openPanel = null);
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createRateVersion() async {
    final book = _versionTargetBook;
    if (book == null) return;
    final validLines = _versionLines
        .where((l) => l.metalId.isNotEmpty && l.ratePerUnit.trim().isNotEmpty && l.unitId.isNotEmpty)
        .toList();
    if (validLines.isEmpty) {
      setState(() => _error = 'Add at least one complete rate line (metal, rate, reference fineness, unit).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = DateTime.now().toUtc();
      await context.read<ApiClient>().post(
        '/rate-books/${book['id']}/versions',
        idempotent: true,
        body: {
          'expectedBookVersion': asInt(book['version'], fallback: 1),
          'effectiveAt': now.toIso8601String(),
          'lines': validLines
              .map((l) => {
                    'metalId': l.metalId,
                    'side': l.side,
                    'ratePerUnit': l.ratePerUnit.trim(),
                    'referenceFineness': l.referenceFineness.trim(),
                    'unitId': l.unitId,
                  })
              .toList(),
        },
      );
      if (!mounted) return;
      setState(() {
        _versionTargetBook = null;
        _versionLines
          ..clear()
          ..add(_RateLineDraft());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Immutable draft rate version created.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publishVersion(Map<String, dynamic> v) async {
    final reasonCtrl = TextEditingController(
      text: 'Approved showroom bullion board rate after treasury verification.',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Publish version ${v['sequenceNumber']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Publishing locks this complete rate proposal for historical use.',
              style: T.body(12.5, color: Pal.muted),
            ),
            const SizedBox(height: 12),
            SaasField(
              label: 'Approval reason (min 10 chars)',
              controller: reasonCtrl,
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish rate version')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/rate-versions/${v['id']}/publish',
        idempotent: true,
        body: {
          'expectedVersion': asInt(v['version'], fallback: 1),
          'approvalReason': reasonCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rate version published!')));
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPrice() async {
    if (_calcRateVersionId.text.trim().isEmpty ||
        _calcMetalId.text.trim().isEmpty ||
        _calcPurityId.text.trim().isEmpty ||
        _calcWeight.text.trim().isEmpty) {
      setState(() => _error = 'Select published rate, metal, purity, and weight in grams.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().post(
        '/pricing/calculate-metal',
        body: {
          'rateVersionId': _calcRateVersionId.text.trim(),
          'components': [
            {
              'metalId': _calcMetalId.text.trim(),
              'purityGradeId': _calcPurityId.text.trim(),
              'weightGrams': _calcWeight.text.trim(),
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
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metals = asList(_materials['metals']);
    final units = asList(_materials['units']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Materials & Bullion Rates'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.diamond_outlined,
              title: 'Materials and rates',
              subtitle: 'Exact purity masters and immutable, effective-dated metal rates.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => setState(() => _openPanel = _openPanel == 'METAL' ? null : 'METAL'),
                  child: const Text('Add metal'),
                ),
                OutlinedButton(
                  onPressed: () => setState(() => _openPanel = _openPanel == 'PURITY' ? null : 'PURITY'),
                  child: const Text('Add purity'),
                ),
                ElevatedButton(
                  onPressed: () => setState(() => _openPanel = _openPanel == 'BOOK' ? null : 'BOOK'),
                  child: const Text('New rate book'),
                ),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],

            if (_openPanel != null) ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: _openPanel == 'METAL'
                    ? 'Add metal master'
                    : _openPanel == 'PURITY'
                        ? 'Add purity grade'
                        : 'New rate book',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_openPanel == 'METAL') ...[
                      SaasField(label: 'Metal code (e.g. GOLD)', controller: _metalCode, mono: true),
                      const SizedBox(height: 10),
                      SaasField(label: 'Metal name', controller: _metalName),
                    ] else if (_openPanel == 'PURITY') ...[
                      LookupField(label: 'Metal', controller: _gradeMetalId, options: _metalOpts),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: SaasField(label: 'Grade code (22K916)', controller: _gradeCode, mono: true)),
                          const SizedBox(width: 10),
                          Expanded(child: SaasField(label: 'Display karat (22K)', controller: _gradeKarat)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SaasField(
                        label: 'Fineness per thousand (e.g. 916.000000)',
                        controller: _gradeFineness,
                        mono: true,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ] else ...[
                      SaasField(label: 'Rate book code', controller: _bookCode, mono: true),
                      const SizedBox(height: 10),
                      SaasField(label: 'Rate book name', controller: _bookName),
                      const SizedBox(height: 10),
                      SaasField(label: 'Currency', controller: _bookCurrency, mono: true),
                    ],
                    const SizedBox(height: 12),
                    GoldButton(
                      label: 'Save',
                      busy: _busy,
                      onPressed: _submitQuickMaster,
                    ),
                  ],
                ),
              ),
            ],

            if (_versionTargetBook != null) ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'Create complete version · ${_versionTargetBook!['name']}',
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => setState(() => _versionTargetBook = null),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _versionLines.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      SaasSubBox(
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: GoldDropdown<String>(
                                    value: _versionLines[i].metalId.isEmpty ? null : _versionLines[i].metalId,
                                    hint: 'Metal',
                                    items: _metalOpts
                                        .map((m) => DropdownMenuItem(value: m.id, child: Text(m.label)))
                                        .toList(),
                                    onChanged: (v) => setState(() => _versionLines[i].metalId = v ?? ''),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 100,
                                  child: GoldDropdown<String>(
                                    value: _versionLines[i].side,
                                    items: const [
                                      DropdownMenuItem(value: 'SELL', child: Text('SELL')),
                                      DropdownMenuItem(value: 'BUY', child: Text('BUY')),
                                    ],
                                    onChanged: (v) => setState(() => _versionLines[i].side = v ?? 'SELL'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    decoration: const InputDecoration(hintText: 'Rate'),
                                    style: T.mono(13),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    onChanged: (v) => _versionLines[i].ratePerUnit = v,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 90,
                                  child: TextFormField(
                                    initialValue: _versionLines[i].referenceFineness,
                                    decoration: const InputDecoration(hintText: '999'),
                                    style: T.mono(13),
                                    onChanged: (v) => _versionLines[i].referenceFineness = v,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: GoldDropdown<String>(
                                    value: _versionLines[i].unitId.isEmpty ? null : _versionLines[i].unitId,
                                    hint: 'Unit',
                                    items: _massUnitOpts
                                        .map((u) => DropdownMenuItem(value: u.id, child: Text(u.label)))
                                        .toList(),
                                    onChanged: (v) => setState(() => _versionLines[i].unitId = v ?? ''),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _versionLines.add(_RateLineDraft())),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add rate line'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GoldButton(
                      label: 'Create immutable draft',
                      busy: _busy,
                      onPressed: _createRateVersion,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Material masters',
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : metals.isEmpty
                      ? const SaasEmptyBox('No metals configured yet.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final m in metals) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${m['name']}', style: T.body(14, w: FontWeight.w700)),
                                  Text('${m['code']}', style: T.mono(12, color: Pal.muted)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final g in asList(m['purityGrades']))
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Pal.goldWash,
                                        borderRadius: BorderRadius.circular(99),
                                        border: Border.all(color: Pal.goldBorder),
                                      ),
                                      child: Text(
                                        '${g['code']}${g['displayKarat'] != null ? ' · ${g['displayKarat']}' : ''} · ${g['finenessPerThousand']}',
                                        style: T.body(11.5, color: Pal.goldDeep, w: FontWeight.w600),
                                      ),
                                    ),
                                ],
                              ),
                              const Divider(height: 20),
                            ],
                            if (units.isNotEmpty)
                              Text(
                                'Units: ${units.map((u) => '${u['code']} (${u['baseFactor']} base)').join(' · ')}',
                                style: T.body(11.8, color: Pal.muted),
                              ),
                          ],
                        ),
            ),

            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Rate books',
              icon: Icons.scale_outlined,
              child: _rateBooks.isEmpty
                  ? const SaasEmptyBox('No rate books created yet.')
                  : Column(
                      children: [
                        for (final book in _rateBooks) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Pal.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${book['name']}', style: T.body(14, w: FontWeight.w700)),
                                          Text(
                                            '${book['code']} · ${book['currency']} · version ${book['version']}',
                                            style: T.body(11.8, color: Pal.muted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => setState(() => _versionTargetBook = book),
                                      icon: const Icon(Icons.add_rounded, size: 15),
                                      label: const Text('Create version'),
                                    ),
                                  ],
                                ),
                                for (final v in asList(book['versions'])) ...[
                                  const Divider(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Version ${v['sequenceNumber']} · ${v['state']}',
                                              style: T.body(13, w: FontWeight.w600),
                                            ),
                                            Text(
                                              'Effective ${fmtDateTime('${v['effectiveAt'] ?? ''}')} · ${asList(v['lines']).length} lines',
                                              style: T.body(11.5, color: Pal.muted),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if ('${v['state']}' == 'DRAFT')
                                        ElevatedButton.icon(
                                          onPressed: _busy ? null : () => _publishVersion(v),
                                          icon: const Icon(Icons.send_rounded, size: 13),
                                          label: const Text('Publish'),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
            ),

            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Authoritative metal-price check',
              icon: Icons.calculate_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Published rate',
                    controller: _calcRateVersionId,
                    options: _publishedVersionOpts,
                    hint: 'Published rate',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Metal',
                    controller: _calcMetalId,
                    options: _metalOpts,
                    hint: 'Metal',
                    onSelected: (_) => setState(() => _calcPurityId.clear()),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Purity grade',
                    controller: _calcPurityId,
                    options: _purityOpts(_calcMetalId.text.trim()),
                    hint: 'Purity',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Weight grams',
                          controller: _calcWeight,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasDropdown(
                          label: 'Side',
                          value: _calcSide,
                          options: const {'SELL': 'SELL', 'BUY': 'BUY'},
                          onChanged: (v) => setState(() => _calcSide = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _checkPrice,
                      child: const Text('Calculate metal value'),
                    ),
                  ),
                  if (_priceResult != null) ...[
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Column(
                        children: [
                          KVRow('Total Metal Value', inr(_priceResult!['totalMetalValue']), bold: true),
                          for (final c in asList(_priceResult!['components']))
                            KVRow(
                              '${c['metalCode']} ${c['purityCode']} (${grams(c['fineWeightGrams'])} fine)',
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
// 4. REFINING & MELTING (`/refining`) — Screenshot (680)
// ---------------------------------------------------------------------------

class RefiningMeltingScreen extends StatefulWidget {
  const RefiningMeltingScreen({super.key});
  @override
  State<RefiningMeltingScreen> createState() => _RefiningMeltingScreenState();
}

class _RefiningMeltingScreenState extends State<RefiningMeltingScreen> {
  List<Map<String, dynamic>> _batches = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _refinerPartyId = TextEditingController();
  final _meltSeriesId = TextEditingController();
  final _businessDate = TextEditingController(text: todayIso());
  final _batchDesc = TextEditingController();
  final _allowedLoss = TextEditingController(text: '0.000000');
  final _sourceBalanceId = TextEditingController();
  final _balanceVersion = TextEditingController(text: '1');
  final _inputQty = TextEditingController();
  final _inputFine = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _refinerPartyId, _meltSeriesId, _businessDate, _batchDesc,
      _allowedLoss, _sourceBalanceId, _balanceVersion, _inputQty, _inputFine,
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
        api.get('/refining'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _batches = asList(res[0], keys: const ['batches', 'meltBatches', 'refiningBatches', 'items']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createBatch() async {
    if (_meltSeriesId.text.trim().isEmpty ||
        _batchDesc.text.trim().length < 3 ||
        _sourceBalanceId.text.trim().isEmpty ||
        _inputQty.text.trim().isEmpty ||
        _inputFine.text.trim().isEmpty) {
      setState(() => _error = 'Complete Melt series, Batch description, Source balance, Input quantity g, and Input fine g.');
      return;
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
          'allowedFineLossGrams': _allowedLoss.text.trim().isEmpty
              ? '0.000000'
              : _allowedLoss.text.trim(),
          'inputs': [
            {
              'balanceId': _sourceBalanceId.text.trim(),
              'expectedBalanceVersion': int.tryParse(_balanceVersion.text.trim()) ?? 1,
              'quantityGrams': _inputQty.text.trim(),
              'fineWeightGrams': _inputFine.text.trim(),
            },
          ],
        },
      );
      if (!mounted) return;
      _batchDesc.clear();
      _inputQty.clear();
      _inputFine.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Controlled refining / melt batch created.')),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Refining & Melting'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.precision_manufacturing_outlined,
              title: 'Refining & Melting',
              subtitle:
                  'Controlled batch genealogy, versioned assay approval, recoveries, process loss and FIFO cost allocation.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'New melt batch',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Refiner party UUID (optional)',
                    controller: _refinerPartyId,
                    options: _lk.partiesByRole('REFINER'),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Melt series UUID',
                    controller: _meltSeriesId,
                    options: _lk.seriesFor(const ['MELT', 'REFINING', 'BATCH']),
                  ),
                  const SizedBox(height: 10),
                  DatePickField(label: 'Business date', controller: _businessDate),
                  const SizedBox(height: 10),
                  SaasField(label: 'Batch description', controller: _batchDesc),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Allowed fine loss g',
                    controller: _allowedLoss,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Source balance UUID',
                    controller: _sourceBalanceId,
                    options: _lk.lotBalances,
                    onSelected: (opt) {
                      if (opt != null) {
                        setState(() {
                          _balanceVersion.text = '${opt.raw['balanceVersion'] ?? opt.raw['version'] ?? 1}';
                          _inputQty.text = '${opt.raw['quantityGrams'] ?? ''}';
                          _inputFine.text = '${opt.raw['fineWeightGrams'] ?? ''}';
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
                          controller: _balanceVersion,
                          mono: true,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Input quantity g',
                          controller: _inputQty,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Input fine g',
                    controller: _inputFine,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _createBatch,
                      child: Text(_busy ? 'Saving…' : 'Create controlled batch'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_batches.isEmpty)
              const SaasEmptyBox('No refining batches yet.')
            else
              for (final b in _batches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${b['documentNumber'] ?? b['batchNumber'] ?? shortId('${b['id']}')} · ${b['description'] ?? 'Melt batch'}',
                                style: T.body(14, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${b['state'] ?? b['status'] ?? 'OPEN'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Business Date', fmtDate('${b['businessDate'] ?? ''}')),
                        KVRow('Input / Output Fine', '${grams(b['inputFineGrams'])} → ${grams(b['outputFineGrams'])}', bold: true),
                      ],
                    ),
                  ),
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
      _destBranchId, _sourceTransitId, _seriesId, _businessDate,
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
      setState(() => _lines.clear());
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inter-Branch Transfers'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.swap_horiz_rounded,
              title: 'Inter-Branch Stock Transfers',
              subtitle:
                  'Dispatch through transit custody, receive without partial silent drops, and record discrepancy claims explicitly.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'New transfer request',
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
                            child: const Text('Add transfer line'),
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _createTransfer,
                      child: Text(_busy ? 'Saving…' : 'Create transfer'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_transfers.isEmpty)
              const SaasEmptyBox('No inter-branch transfers yet.')
            else
              for (final t in _transfers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t['documentNumber'] ?? t['transferNumber'] ?? shortId('${t['id']}')} · ${asMap(t['destinationBranch'])['name'] ?? 'Branch Transfer'}',
                                style: T.body(14, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${t['state'] ?? t['status'] ?? 'DRAFT'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Business / Expected', '${fmtDate('${t['businessDate'] ?? ''}')} → ${fmtDate('${t['expectedReceiptDate'] ?? ''}')}'),
                        if ('${t['description'] ?? ''}'.isNotEmpty)
                          KVRow('Description', '${t['description']}'),
                      ],
                    ),
                  ),
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
      _destEntityId, _destBranchId, _sourceTransitId, _seriesId,
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
      setState(() => _lines.clear());
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inter-Entity Trading'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.domain_add_rounded,
              title: 'Related-Entity Jewellery Trading',
              subtitle:
                  'Symmetric sale and purchase arms, GST-ready line economics, transit custody, and elimination-ready references.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'New related-entity trade',
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
                            child: const Text('Add line'),
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _createTrade,
                      child: Text(_busy ? 'Saving…' : 'Create trade'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_trades.isEmpty)
              const SaasEmptyBox('No related-entity jewellery trades yet.')
            else
              for (final t in _trades)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t['documentNumber'] ?? t['tradeNumber'] ?? shortId('${t['id']}')} · ${asMap(t['destinationLegalEntity'])['legalName'] ?? 'Inter-Entity Trade'}',
                                style: T.body(14, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${t['state'] ?? t['status'] ?? 'DRAFT'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Request / Expected', '${fmtDate('${t['requestDate'] ?? ''}')} → ${fmtDate('${t['expectedReceiptDate'] ?? ''}')}'),
                        KVRow('Total Amount', inr(t['totalAmount'] ?? t['taxableAmount']), bold: true),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
