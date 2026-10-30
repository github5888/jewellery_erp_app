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

String _pickStr(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v is Map) {
      final inner = v['displayName'] ?? v['legalName'] ?? v['name'] ?? v['code'] ?? v['tagNumber'] ?? v['tag'];
      if (inner != null && '$inner'.isNotEmpty) return '$inner';
    } else if (v != null && '$v'.isNotEmpty && v is! List) {
      return '$v';
    }
  }
  return fallback;
}

// ============================================================================
// 1. CUSTOM ORDERS — GET /custom-orders, POST /custom-orders
// ============================================================================

class CustomOrdersScreen extends StatefulWidget {
  const CustomOrdersScreen({super.key});
  @override
  State<CustomOrdersScreen> createState() => _CustomOrdersScreenState();
}

class _CustomOrdersScreenState extends State<CustomOrdersScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;
  bool _showForm = false;
  bool _busy = false;
  String? _error;

  final _partyCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _metalCtrl = TextEditingController();
  final _purityCtrl = TextEditingController();
  final _orderDateCtrl = TextEditingController(text: todayIso());
  final _dueDateCtrl = TextEditingController(text: todayIso());
  final _targetWtCtrl = TextEditingController();
  final _estAmountCtrl = TextEditingController();
  final _specCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partyCtrl.dispose();
    _seriesCtrl.dispose();
    _metalCtrl.dispose();
    _purityCtrl.dispose();
    _orderDateCtrl.dispose();
    _dueDateCtrl.dispose();
    _targetWtCtrl.dispose();
    _estAmountCtrl.dispose();
    _specCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait<dynamic>([
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
        _orders = asList(results[0], keys: const ['orders', 'customOrders', 'items', 'rows']);
        _lookup = results[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createOrder() async {
    if (_partyCtrl.text.trim().isEmpty) {
      toast(context, 'Select the customer placing the custom order.', error: true);
      return;
    }
    if (_specCtrl.text.trim().isEmpty) {
      toast(context, 'Enter design specification or ornament details.', error: true);
      return;
    }
    if (_targetWtCtrl.text.trim().isNotEmpty && !isValidWeight(_targetWtCtrl.text)) {
      toast(context, 'Enter a valid target weight in grams.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/custom-orders',
        idempotencyKey: const Uuid().v4(),
        body: {
          'partyId': _partyCtrl.text.trim(),
          'customerId': _partyCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'seriesId': _seriesCtrl.text.trim(),
          if (_metalCtrl.text.trim().isNotEmpty) 'metalId': _metalCtrl.text.trim(),
          if (_purityCtrl.text.trim().isNotEmpty) 'purityGradeId': _purityCtrl.text.trim(),
          'orderDate': _orderDateCtrl.text.trim(),
          'promisedDate': _dueDateCtrl.text.trim(),
          if (_targetWtCtrl.text.trim().isNotEmpty)
            'targetWeightGrams': normWeight6(_targetWtCtrl.text),
          if (_estAmountCtrl.text.trim().isNotEmpty && isValidAmount(_estAmountCtrl.text))
            'estimatedAmount': normAmount(_estAmountCtrl.text),
          'currency': context.read<AppState>().currency,
          'description': _specCtrl.text.trim(),
          'specification': _specCtrl.text.trim(),
        },
      );
      _specCtrl.clear();
      _targetWtCtrl.clear();
      _estAmountCtrl.clear();
      setState(() => _showForm = false);
      await _load();
      if (mounted) toast(context, 'Custom order created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
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
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.auto_awesome_outlined,
              badge: 'Bespoke Patron Orders',
              title: 'Custom Jewellery Orders',
              subtitle:
                  'Capture bespoke patron specifications, target metal weights, promised dates, and artisan allocations.',
              trailing: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Pal.goldBright,
                  foregroundColor: Pal.ink,
                  minimumSize: const Size(110, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => setState(() => _showForm = !_showForm),
                icon: Icon(_showForm ? Icons.close_rounded : Icons.add_rounded, size: 17),
                label: Text(_showForm ? 'Close' : 'New Order', style: T.body(12.5, color: Pal.ink, w: FontWeight.w800)),
              ),
            ),
            if (_showForm) ...[
              const SizedBox(height: 14),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('New Custom Order', style: T.display(18)),
                  const SizedBox(height: 14),
                  LookupField(
                    label: 'Customer / Patron',
                    controller: _partyCtrl,
                    options: _lookup.partiesByRole('CUSTOMER'),
                    hint: 'Select customer',
                  ),
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Order Series',
                    controller: _seriesCtrl,
                    options: _lookup.seriesFor(const ['ORDER', 'CUSTOM', 'SALES']),
                    optional: true,
                    hint: 'Select document series',
                  ),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    LookupField(
                      label: 'Metal',
                      controller: _metalCtrl,
                      options: _lookup.metals,
                      optional: true,
                      hint: 'Metal',
                    ),
                    LookupField(
                      label: 'Purity Grade',
                      controller: _purityCtrl,
                      options: _lookup.purityGrades,
                      optional: true,
                      hint: 'Purity',
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    DatePickField(label: 'Order date', controller: _orderDateCtrl),
                    DatePickField(label: 'Promised date', controller: _dueDateCtrl),
                  ]),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Target weight (g)'),
                      TextField(
                        controller: _targetWtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: T.mono(13.5),
                        decoration: const InputDecoration(hintText: '0.000000'),
                      ),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Estimated value (INR)'),
                      TextField(
                        controller: _estAmountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: T.mono(13.5),
                        decoration: const InputDecoration(hintText: '0.00'),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  const FieldLabel('Design specification / instructions'),
                  TextField(
                    controller: _specCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Ornament style, size, hallmark & stone notes'),
                  ),
                  const SizedBox(height: 16),
                  RoyalGoldButton(
                    label: 'Create Custom Order',
                    icon: Icons.check_circle_outline_rounded,
                    busy: _busy,
                    onPressed: _createOrder,
                  ),
                ]),
              ),
            ],
            const SectionLabel('Order Register'),
            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 76)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_orders.isEmpty)
              Panel(
                child: EmptyBlock(
                  icon: Icons.auto_awesome_outlined,
                  title: 'No custom orders recorded yet',
                  body: 'Create a bespoke patron order to track design specifications, promised dates, and artisan progress.',
                  actionLabel: 'New Custom Order',
                  onAction: () => setState(() => _showForm = true),
                ),
              )
            else
              for (final o in _orders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _pickStr(o, ['documentNumber', 'orderNumber', 'code'], 'Custom Order'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_pickStr(o, ['state', 'status'], 'OPEN')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Patron', _pickStr(o, ['customer', 'party', 'customerName'], '-'), strong: true),
                      if (_pickStr(o, ['targetWeightGrams', 'estimatedWeightGrams']).isNotEmpty)
                        KeyValue('Target Weight', grams(_pickStr(o, ['targetWeightGrams', 'estimatedWeightGrams'])), mono: true),
                      if (_pickStr(o, ['estimatedAmount', 'totalAmount']).isNotEmpty)
                        KeyValue('Estimated Value', inr(_pickStr(o, ['estimatedAmount', 'totalAmount'])), mono: true),
                      if (_pickStr(o, ['promisedDate', 'dueDate']).isNotEmpty)
                        KeyValue('Promised Delivery', formatDate(_pickStr(o, ['promisedDate', 'dueDate']))),
                      if (_pickStr(o, ['description', 'specification']).isNotEmpty)
                        KeyValue('Specification', _pickStr(o, ['description', 'specification'])),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. REPAIRS & CUSTODY — GET /repairs, POST /repairs
// ============================================================================

class RepairsCustodyScreen extends StatefulWidget {
  const RepairsCustodyScreen({super.key});
  @override
  State<RepairsCustodyScreen> createState() => _RepairsCustodyScreenState();
}

class _RepairsCustodyScreenState extends State<RepairsCustodyScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _repairs = [];
  bool _loading = true;
  bool _showForm = false;
  bool _busy = false;
  String? _error;

  final _partyCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _intakeDateCtrl = TextEditingController(text: todayIso());
  final _promisedDateCtrl = TextEditingController(text: todayIso());
  final _wtCtrl = TextEditingController();
  final _chargeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partyCtrl.dispose();
    _locationCtrl.dispose();
    _seriesCtrl.dispose();
    _intakeDateCtrl.dispose();
    _promisedDateCtrl.dispose();
    _wtCtrl.dispose();
    _chargeCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait<dynamic>([
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
        _repairs = asList(results[0], keys: const ['repairs', 'repairOrders', 'items', 'rows']);
        _lookup = results[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createRepair() async {
    if (_partyCtrl.text.trim().isEmpty) {
      toast(context, 'Select the customer handing over the ornament.', error: true);
      return;
    }
    if (_wtCtrl.text.trim().isEmpty || !isValidWeight(_wtCtrl.text)) {
      toast(context, 'Enter valid received gross weight in grams.', error: true);
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      toast(context, 'Describe the ornament and repair work required.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/repairs',
        idempotencyKey: const Uuid().v4(),
        body: {
          'partyId': _partyCtrl.text.trim(),
          'customerId': _partyCtrl.text.trim(),
          if (_locationCtrl.text.trim().isNotEmpty) 'custodyLocationId': _locationCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'seriesId': _seriesCtrl.text.trim(),
          'businessDate': _intakeDateCtrl.text.trim(),
          'promisedDate': _promisedDateCtrl.text.trim(),
          'receivedWeightGrams': normWeight6(_wtCtrl.text),
          'grossWeightGrams': normWeight6(_wtCtrl.text),
          if (_chargeCtrl.text.trim().isNotEmpty && isValidAmount(_chargeCtrl.text))
            'estimatedCharge': normAmount(_chargeCtrl.text),
          'description': _descCtrl.text.trim(),
        },
      );
      _wtCtrl.clear();
      _chargeCtrl.clear();
      _descCtrl.clear();
      setState(() => _showForm = false);
      await _load();
      if (mounted) toast(context, 'Repair custody ticket created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
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
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.build_outlined,
              badge: 'Customer Custody',
              title: 'Repairs & Ornament Custody',
              subtitle:
                  'Issue customer ornament custody receipts with exact intake weight, vault location, and repair tracking.',
              trailing: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Pal.goldBright,
                  foregroundColor: Pal.ink,
                  minimumSize: const Size(110, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: () => setState(() => _showForm = !_showForm),
                icon: Icon(_showForm ? Icons.close_rounded : Icons.add_rounded, size: 17),
                label: Text(_showForm ? 'Close' : 'Intake', style: T.body(12.5, color: Pal.ink, w: FontWeight.w800)),
              ),
            ),
            if (_showForm) ...[
              const SizedBox(height: 14),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('New Repair Custody Intake', style: T.display(18)),
                  const SizedBox(height: 14),
                  LookupField(
                    label: 'Customer',
                    controller: _partyCtrl,
                    options: _lookup.partiesByRole('CUSTOMER'),
                    hint: 'Select customer',
                  ),
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Custody location',
                    controller: _locationCtrl,
                    options: _lookup.locations,
                    optional: true,
                    hint: 'Select showroom custody location',
                  ),
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Repair series',
                    controller: _seriesCtrl,
                    options: _lookup.seriesFor(const ['REPAIR', 'CUSTODY']),
                    optional: true,
                  ),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    DatePickField(label: 'Intake date', controller: _intakeDateCtrl),
                    DatePickField(label: 'Promised date', controller: _promisedDateCtrl),
                  ]),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Received gross weight (g)'),
                      TextField(
                        controller: _wtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: T.mono(13.5),
                        decoration: const InputDecoration(hintText: '0.000000'),
                      ),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Estimated charge (INR)'),
                      TextField(
                        controller: _chargeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: T.mono(13.5),
                        decoration: const InputDecoration(hintText: '0.00'),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  const FieldLabel('Ornament condition & repair instructions'),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Clasp soldering, ring resizing, stone tightening…'),
                  ),
                  const SizedBox(height: 16),
                  RoyalGoldButton(
                    label: 'Record Custody Intake',
                    icon: Icons.verified_user_outlined,
                    busy: _busy,
                    onPressed: _createRepair,
                  ),
                ]),
              ),
            ],
            const SectionLabel('Custody Register'),
            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 76)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_repairs.isEmpty)
              Panel(
                child: EmptyBlock(
                  icon: Icons.build_outlined,
                  title: 'No repair custody items yet',
                  body: 'Record customer ornaments accepted for polishing, soldering, resizing, or hallmark inspection.',
                  actionLabel: 'New Custody Intake',
                  onAction: () => setState(() => _showForm = true),
                ),
              )
            else
              for (final r in _repairs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _pickStr(r, ['documentNumber', 'ticketNumber', 'code'], 'Repair Ticket'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_pickStr(r, ['state', 'status'], 'IN_CUSTODY')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Customer', _pickStr(r, ['customer', 'party', 'customerName'], '-'), strong: true),
                      if (_pickStr(r, ['receivedWeightGrams', 'grossWeightGrams']).isNotEmpty)
                        KeyValue('Intake Weight', grams(_pickStr(r, ['receivedWeightGrams', 'grossWeightGrams'])), mono: true),
                      if (_pickStr(r, ['estimatedCharge', 'totalAmount']).isNotEmpty)
                        KeyValue('Est. Charge', inr(_pickStr(r, ['estimatedCharge', 'totalAmount'])), mono: true),
                      if (_pickStr(r, ['promisedDate', 'dueDate']).isNotEmpty)
                        KeyValue('Promised Date', formatDate(_pickStr(r, ['promisedDate', 'dueDate']))),
                      if (_pickStr(r, ['description']).isNotEmpty)
                        KeyValue('Work Notes', _pickStr(r, ['description'])),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 3. MATERIALS & BULLION RATES — /materials, /rates, /rate-books, /rate-versions/:id/publish
// ============================================================================

class MaterialsRatesScreen extends StatefulWidget {
  const MaterialsRatesScreen({super.key});
  @override
  State<MaterialsRatesScreen> createState() => _MaterialsRatesScreenState();
}

class _MaterialsRatesScreenState extends State<MaterialsRatesScreen> {
  String _tab = 'RATES';
  Map<String, dynamic> _materials = const {};
  Map<String, dynamic> _ratesWs = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/materials'),
        api.get('/rates'),
      ]);
      if (!mounted) return;
      setState(() {
        _materials = asMap(res[0]);
        _ratesWs = asMap(res[1]);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addMetalDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.card,
        title: Text('Register Precious Metal', style: T.display(19)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: codeCtrl,
            textCapitalization: TextCapitalization.characters,
            style: T.mono(14),
            labelText: 'Metal Code (e.g. GOLD, SILVER, PLATINUM)',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            labelText: 'Display Name',
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
            onPressed: () async {
              try {
                await context.read<ApiClient>().post('/materials/metals', body: {
                  'code': codeCtrl.text.trim().toUpperCase(),
                  'name': nameCtrl.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on ApiException catch (e) {
                if (ctx.mounted) toast(ctx, e.message, error: true);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _addPurityDialog(List<Map<String, dynamic>> metals) async {
    if (metals.isEmpty) {
      toast(context, 'Create a precious metal first before adding purity grades.', error: true);
      return;
    }
    var metalId = '${metals.first['id'] ?? ''}';
    final codeCtrl = TextEditingController();
    final karatCtrl = TextEditingController();
    final fineCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Pal.card,
          title: Text('Add Purity Grade', style: T.display(19)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GoldDropdown<String>(
                value: metalId,
                labelText: 'Precious Metal',
                items: [
                  for (final m in metals)
                    DropdownMenuItem(
                      value: '${m['id']}',
                      child: Text('${m['name']} (${m['code']})'),
                    ),
                ],
                onChanged: (v) => setLocal(() => metalId = v ?? metalId),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: T.mono(14),
                labelText: 'Purity Code (999, 916, 750)',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: karatCtrl,
                labelText: 'Display Karat (24K, 22K, 18K)',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fineCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: T.mono(14),
                labelText: 'Fineness per 1000 (e.g. 916.000)',
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () async {
                try {
                  await context.read<ApiClient>().post('/materials/purity-grades', body: {
                    'metalId': metalId,
                    'code': codeCtrl.text.trim().toUpperCase(),
                    if (karatCtrl.text.trim().isNotEmpty) 'displayKarat': karatCtrl.text.trim(),
                    'finenessPerThousand': fineCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
              child: const Text('Save Grade'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _createRateBookDialog() async {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.card,
        title: Text('Create Bullion Rate Book', style: T.display(19)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: codeCtrl,
            textCapitalization: TextCapitalization.characters,
            style: T.mono(14),
            labelText: 'Book Code (e.g. RETAIL-BOARD)',
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameCtrl,
            labelText: 'Rate Book Name',
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
            onPressed: () async {
              try {
                await context.read<ApiClient>().post('/rate-books', body: {
                  'code': codeCtrl.text.trim().toUpperCase(),
                  'name': nameCtrl.text.trim(),
                  'currency': context.read<AppState>().currency,
                });
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on ApiException catch (e) {
                if (ctx.mounted) toast(ctx, e.message, error: true);
              }
            },
            child: const Text('Create Book'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _publishVersion(String versionId) async {
    try {
      await context.read<ApiClient>().post(
        '/rate-versions/$versionId/publish',
        idempotencyKey: const Uuid().v4(),
        body: {'reason': 'Published showroom bullion board rate version.'},
      );
      await context.read<RatesController>().refresh();
      await _load();
      if (mounted) toast(context, 'Bullion rate version published live.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metals = asList(_materials['metals'] ?? _materials, keys: const ['metals']);
    final units = asList(_materials['units'] ?? const [], keys: const ['units']);
    final books = asList(_ratesWs['rateBooks'] ?? _ratesWs['books'] ?? _ratesWs, keys: const ['rateBooks', 'books']);
    final ratesCtrl = context.watch<RatesController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Materials & Bullion Rates'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.toll_rounded,
              badge: 'Fine 999 Bullion Governance',
              title: 'Materials & Bullion Board',
              subtitle:
                  'Configure precious metals, fineness-per-thousand grades, and versioned daily showroom rate books.',
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: const [
                ('RATES', 'Bullion Rate Books', Icons.trending_up_rounded),
                ('METALS', 'Metals & Purity Grades', Icons.diamond_outlined),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 110))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'RATES') ...[
              Row(children: [
                const Expanded(child: BullionHeaderBadge()),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(116, 40)),
                  onPressed: _createRateBookDialog,
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Rate Book'),
                ),
              ]),
              const SizedBox(height: 12),
              if (ratesCtrl.rates.isNotEmpty) ...[
                ResponsiveGrid2(children: [
                  for (final r in ratesCtrl.rates)
                    MetricTile(
                      label: '${r.metal} · ${r.karatLabel}',
                      value: '${rate(r.sell)}/g',
                      subtitle: 'Buy ${rate(r.buy)}/g',
                      icon: Icons.workspace_premium_outlined,
                    ),
                ]),
                const SizedBox(height: 12),
              ],
              if (books.isEmpty)
                Panel(
                  child: EmptyBlock(
                    icon: Icons.menu_book_outlined,
                    title: 'No rate books configured',
                    body: 'Create a showroom rate book to version and publish daily 24K/22K/18K & Silver spot rates.',
                    actionLabel: 'Create Rate Book',
                    onAction: _createRateBookDialog,
                  ),
                )
              else
                for (final b in books)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${b['name'] ?? b['code'] ?? 'Rate Book'}', style: T.display(17))),
                          MonoTag('${b['code'] ?? 'BOOK'}'),
                        ]),
                        const SizedBox(height: 8),
                        for (final v in asList(b['versions']))
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  'v${v['versionNumber'] ?? v['version'] ?? 1} · ${formatDateTime(v['effectiveFrom'] ?? v['createdAt'])}',
                                  style: T.body(12.5, color: Pal.muted),
                                ),
                              ),
                              StatusPill('${v['state'] ?? 'DRAFT'}'),
                              if ('${v['state']}'.toUpperCase() == 'DRAFT') ...[
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => _publishVersion('${v['id']}'),
                                  child: const Text('Publish'),
                                ),
                              ],
                            ]),
                          ),
                      ]),
                    ),
                  ),
            ] else ...[
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: _addMetalDialog,
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('+ Metal'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    onPressed: () => _addPurityDialog(metals),
                    icon: const Icon(Icons.grade_outlined, size: 17),
                    label: const Text('+ Purity Grade'),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              if (metals.isEmpty)
                const Panel(
                  child: EmptyBlock(
                    icon: Icons.diamond_outlined,
                    title: 'No metals defined yet',
                    body: 'Register GOLD, SILVER, or PLATINUM and their purity fineness grades.',
                  ),
                )
              else
                for (final m in metals)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${m['name'] ?? m['code']}', style: T.display(18))),
                          MonoTag('${m['code'] ?? ''}'),
                        ]),
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final pg in asList(m['purityGrades']))
                            Chip2(
                              '${pg['displayKarat'] ?? pg['code']} · ${pg['finenessPerThousand']}‰',
                              mono: true,
                            ),
                        ]),
                      ]),
                    ),
                  ),
              if (units.isNotEmpty) ...[
                const SectionLabel('Units of Measure'),
                Panel(
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final u in units)
                      Chip2('${u['name']} (${u['symbol'] ?? u['code']}) · ${u['dimension']}', gold: false),
                  ]),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 4. REFINING & MELTING — Screenshot 680 (`GET /refining`, `POST /refining`)
// ============================================================================

class RefiningMeltingScreen extends StatefulWidget {
  const RefiningMeltingScreen({super.key});
  @override
  State<RefiningMeltingScreen> createState() => _RefiningMeltingScreenState();
}

class _RefiningMeltingScreenState extends State<RefiningMeltingScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _batches = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _refinerCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _businessDateCtrl = TextEditingController(text: todayIso());
  final _descCtrl = TextEditingController();
  final _lossCtrl = TextEditingController(text: '0.000000');
  final _sourceBalanceCtrl = TextEditingController();
  final _balanceVerCtrl = TextEditingController(text: '1');
  final _inputQtyCtrl = TextEditingController();
  final _inputFineCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refinerCtrl.dispose();
    _seriesCtrl.dispose();
    _businessDateCtrl.dispose();
    _descCtrl.dispose();
    _lossCtrl.dispose();
    _sourceBalanceCtrl.dispose();
    _balanceVerCtrl.dispose();
    _inputQtyCtrl.dispose();
    _inputFineCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
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
        _batches = asList(res[0], keys: const ['batches', 'refiningBatches', 'meltBatches', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit() async {
    if (_seriesCtrl.text.trim().isEmpty) {
      toast(context, 'Select or enter the Melt series ID.', error: true);
      return;
    }
    if (_sourceBalanceCtrl.text.trim().isEmpty) {
      toast(context, 'Select or enter the Source balance ID.', error: true);
      return;
    }
    if (!isValidWeight(_inputQtyCtrl.text) || !isValidWeight(_inputFineCtrl.text)) {
      toast(context, 'Enter valid Input quantity (g) and Input fine (g).', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final ver = int.tryParse(_balanceVerCtrl.text.trim()) ?? 1;
      await context.read<ApiClient>().post(
        '/refining',
        idempotencyKey: const Uuid().v4(),
        body: {
          if (_refinerCtrl.text.trim().isNotEmpty) 'refinerPartyId': _refinerCtrl.text.trim(),
          'documentSeriesId': _seriesCtrl.text.trim(),
          'meltSeriesId': _seriesCtrl.text.trim(),
          'businessDate': _businessDateCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'allowedFineLossGrams': normWeight6(_lossCtrl.text),
          'inputs': [
            {
              'sourceBalanceId': _sourceBalanceCtrl.text.trim(),
              'expectedBalanceVersion': ver,
              'balanceVersion': ver,
              'quantityGrams': normWeight6(_inputQtyCtrl.text),
              'fineWeightGrams': normWeight6(_inputFineCtrl.text),
            },
          ],
        },
      );
      _descCtrl.clear();
      _inputQtyCtrl.clear();
      _inputFineCtrl.clear();
      await _load();
      if (mounted) toast(context, 'Controlled melt batch created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
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
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.balance_rounded,
              badge: 'Supply & Production',
              title: 'Refining & Melting',
              subtitle:
                  'Controlled batch genealogy, versioned assay approval, recoveries, process loss and FIFO cost allocation.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New melt batch', style: T.display(18)),
                const SizedBox(height: 14),
                LookupField(
                  label: 'Refiner party',
                  controller: _refinerCtrl,
                  options: _lookup.partiesByRole('REFINER'),
                  optional: true,
                  hint: 'Select refiner or leave blank for internal melt',
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Melt series',
                  controller: _seriesCtrl,
                  options: _lookup.seriesFor(const ['MELT', 'REFIN']),
                  hint: 'Select melt document series',
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  DatePickField(label: 'Business date', controller: _businessDateCtrl),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Allowed fine loss g'),
                    TextField(
                      controller: _lossCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                    ),
                  ]),
                ]),
                const SizedBox(height: 12),
                const FieldLabel('Batch description'),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(hintText: 'Old gold scrap crucible melt / refinery dispatch'),
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Source balance',
                  controller: _sourceBalanceCtrl,
                  options: _lookup.lotBalances,
                  hint: 'Select bullion lot balance or enter UUID',
                  onSelected: (opt) {
                    if (opt == null) return;
                    final v = opt.raw['version'];
                    if (v != null) _balanceVerCtrl.text = '$v';
                    final q = '${opt.raw['quantityGrams'] ?? ''}';
                    if (q.isNotEmpty) _inputQtyCtrl.text = q;
                    final f = '${opt.raw['fineWeightGrams'] ?? ''}';
                    if (f.isNotEmpty) _inputFineCtrl.text = f;
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Balance version'),
                    TextField(
                      controller: _balanceVerCtrl,
                      keyboardType: TextInputType.number,
                      style: T.mono(13.5),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Input quantity g'),
                    TextField(
                      controller: _inputQtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                      decoration: const InputDecoration(hintText: '0.000000'),
                    ),
                  ]),
                ]),
                const SizedBox(height: 12),
                const FieldLabel('Input fine g'),
                TextField(
                  controller: _inputFineCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: T.mono(13.5),
                  decoration: const InputDecoration(hintText: '0.000000'),
                ),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Create controlled batch',
                  icon: Icons.local_fire_department_outlined,
                  busy: _busy,
                  onPressed: _submit,
                ),
              ]),
            ),
            const SectionLabel('Refining Batches'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_batches.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.balance_rounded,
                  title: 'No refining batches yet',
                  body: 'Create a controlled melt batch above to track assay recoveries and Fine 999 process loss.',
                ),
              )
            else
              for (final b in _batches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _pickStr(b, ['documentNumber', 'batchNumber', 'code'], 'Melt Batch'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_pickStr(b, ['state', 'status'], 'OPEN')),
                      ]),
                      const SizedBox(height: 8),
                      if (_pickStr(b, ['refiner', 'refinerParty']).isNotEmpty)
                        KeyValue('Refiner', _pickStr(b, ['refiner', 'refinerParty'])),
                      KeyValue('Business Date', formatDate(_pickStr(b, ['businessDate', 'createdAt']))),
                      if (_pickStr(b, ['inputFineGrams', 'totalInputFineGrams']).isNotEmpty)
                        KeyValue('Input Fine 999', fineGrams(_pickStr(b, ['inputFineGrams', 'totalInputFineGrams'])), mono: true),
                      if (_pickStr(b, ['allowedFineLossGrams']).isNotEmpty)
                        KeyValue('Allowed Loss', fineGrams(_pickStr(b, ['allowedFineLossGrams'])), mono: true),
                      if (_pickStr(b, ['description']).isNotEmpty)
                        KeyValue('Description', _pickStr(b, ['description'])),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 5. INTER-BRANCH TRANSFERS — Screenshot 681 (`GET /stock-transfers`, `POST /stock-transfers`)
// ============================================================================

class InterBranchTransfersScreen extends StatefulWidget {
  const InterBranchTransfersScreen({super.key});
  @override
  State<InterBranchTransfersScreen> createState() => _InterBranchTransfersScreenState();
}

class _InterBranchTransfersScreenState extends State<InterBranchTransfersScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _transfers = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _destBranchCtrl = TextEditingController();
  final _transitLocCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _businessDateCtrl = TextEditingController(text: todayIso());
  final _expectedDateCtrl = TextEditingController(text: todayIso());
  final _descCtrl = TextEditingController();

  String _stockKind = 'TAGGED_ARTICLE';
  final _stockItemCtrl = TextEditingController();
  final _destCustodyCtrl = TextEditingController();
  final List<Map<String, dynamic>> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _destBranchCtrl.dispose();
    _transitLocCtrl.dispose();
    _seriesCtrl.dispose();
    _businessDateCtrl.dispose();
    _expectedDateCtrl.dispose();
    _descCtrl.dispose();
    _stockItemCtrl.dispose();
    _destCustodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/stock-transfers'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeOrganization: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _transfers = asList(res[0], keys: const ['transfers', 'stockTransfers', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _addLine() {
    final stockId = _stockItemCtrl.text.trim();
    if (stockId.isEmpty) {
      toast(context, 'Select an available tagged article or bullion lot.', error: true);
      return;
    }
    final opts = _stockKind == 'TAGGED_ARTICLE' ? _lookup.articles : _lookup.lotBalances;
    final label = opts.where((o) => o.id == stockId).firstOrNull?.label ?? stockId;
    setState(() {
      _lines.add({
        'stockKind': _stockKind,
        if (_stockKind == 'TAGGED_ARTICLE') 'articleId': stockId else 'sourceBalanceId': stockId,
        if (_destCustodyCtrl.text.trim().isNotEmpty) 'destinationLocationId': _destCustodyCtrl.text.trim(),
        '_label': label,
      });
      _stockItemCtrl.clear();
    });
  }

  Future<void> _createTransfer() async {
    if (_destBranchCtrl.text.trim().isEmpty || _transitLocCtrl.text.trim().isEmpty) {
      toast(context, 'Select Destination branch and Source transit custody.', error: true);
      return;
    }
    if (_lines.isEmpty) {
      toast(context, 'Add at least one transfer line before submitting.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/stock-transfers',
        idempotencyKey: const Uuid().v4(),
        body: {
          'destinationBranchId': _destBranchCtrl.text.trim(),
          'sourceTransitLocationId': _transitLocCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'businessDate': _businessDateCtrl.text.trim(),
          if (_expectedDateCtrl.text.trim().isNotEmpty) 'expectedReceiptDate': _expectedDateCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'lines': _lines
              .map((l) => Map<String, dynamic>.from(l)..remove('_label'))
              .toList(),
        },
      );
      setState(() {
        _lines.clear();
        _descCtrl.clear();
      });
      await _load();
      if (mounted) toast(context, 'Inter-branch transfer created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final stockOptions = _stockKind == 'TAGGED_ARTICLE' ? _lookup.articles : _lookup.lotBalances;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inter-Branch Transfers'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.swap_horiz_rounded,
              badge: 'Custody Transit',
              title: 'Inter-Branch Stock Transfers',
              subtitle:
                  'Same-entity branch movements with explicit transit custody, discrepancy quarantine, and zero revenue recognition.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New transfer request', style: T.display(18)),
                const SizedBox(height: 14),
                LookupField(
                  label: 'Destination branch',
                  controller: _destBranchCtrl,
                  options: _lookup.branches,
                  hint: 'Select destination showroom',
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Source transit custody',
                  controller: _transitLocCtrl,
                  options: _lookup.locations,
                  hint: 'Select transit vault custody',
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Transfer series',
                  controller: _seriesCtrl,
                  options: _lookup.seriesFor(const ['TRANSFER', 'STOCK']),
                  hint: 'Select transfer series',
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  DatePickField(label: 'Business date', controller: _businessDateCtrl),
                  DatePickField(label: 'Expected receipt', controller: _expectedDateCtrl, optional: true),
                ]),
                const SizedBox(height: 12),
                const FieldLabel('Description'),
                TextField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(hintText: 'Exhibition replenishment / vault rebalance'),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Pal.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Pal.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TRANSFER LINE BUILDER', style: T.caps(10, color: Pal.goldDeep)),
                    const SizedBox(height: 10),
                    const FieldLabel('Stock kind'),
                    GoldDropdown<String>(
                      value: _stockKind,
                      items: const [
                        DropdownMenuItem(value: 'TAGGED_ARTICLE', child: Text('Tagged article')),
                        DropdownMenuItem(value: 'MATERIAL_LOT', child: Text('Bullion material lot')),
                      ],
                      onChanged: (v) => setState(() {
                        _stockKind = v ?? 'TAGGED_ARTICLE';
                        _stockItemCtrl.clear();
                      }),
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Available stock',
                      controller: _stockItemCtrl,
                      options: stockOptions,
                      hint: 'Select available stock item',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Destination custody',
                      controller: _destCustodyCtrl,
                      options: _lookup.locations,
                      optional: true,
                      hint: 'Destination location UUID',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addLine,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Add transfer line'),
                    ),
                    if (_lines.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (var i = 0; i < _lines.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Panel(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  '${i + 1}. ${_lines[i]['_label']}',
                                  style: T.body(12.5, w: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded, size: 16, color: Pal.danger),
                                onPressed: () => setState(() => _lines.removeAt(i)),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Create transfer (${_lines.length} line${_lines.length == 1 ? '' : 's'})',
                  icon: Icons.local_shipping_outlined,
                  busy: _busy,
                  onPressed: _createTransfer,
                ),
              ]),
            ),
            const SectionLabel('Stock Transfers'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_transfers.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.swap_horiz_rounded,
                  title: 'No stock transfers yet',
                  body: 'Create a transfer request above to move tagged ornaments or bullion lots across branches.',
                ),
              )
            else
              for (final t in _transfers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _pickStr(t, ['documentNumber', 'transferNumber', 'code'], 'Stock Transfer'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_pickStr(t, ['state', 'status'], 'DRAFT')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Destination Branch', _pickStr(t, ['destinationBranch', 'toBranch'], '-'), strong: true),
                      KeyValue('Business Date', formatDate(_pickStr(t, ['businessDate', 'createdAt']))),
                      if (_pickStr(t, ['description']).isNotEmpty)
                        KeyValue('Notes', _pickStr(t, ['description'])),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 6. INTER-ENTITY TRADING — Screenshot 683 (`GET /inter-entity-trades`, `POST /inter-entity-trades`)
// ============================================================================

class InterEntityTradingScreen extends StatefulWidget {
  const InterEntityTradingScreen({super.key});
  @override
  State<InterEntityTradingScreen> createState() => _InterEntityTradingScreenState();
}

class _InterEntityTradingScreenState extends State<InterEntityTradingScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _trades = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _destEntityCtrl = TextEditingController();
  final _destBranchCtrl = TextEditingController();
  final _transitCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  String _taxTreatment = 'INTER_STATE_IGST';
  final _currencyCtrl = TextEditingController(text: 'INR');
  final _reqDateCtrl = TextEditingController(text: todayIso());
  final _expDateCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();

  final _sourceArticleCtrl = TextEditingController();
  final _destLocCtrl = TextEditingController();
  final _newTagCtrl = TextEditingController();
  final _taxableCtrl = TextEditingController();
  final _igstCtrl = TextEditingController(text: '0.00');
  final List<Map<String, dynamic>> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _destEntityCtrl.dispose();
    _destBranchCtrl.dispose();
    _transitCtrl.dispose();
    _seriesCtrl.dispose();
    _currencyCtrl.dispose();
    _reqDateCtrl.dispose();
    _expDateCtrl.dispose();
    _termsCtrl.dispose();
    _sourceArticleCtrl.dispose();
    _destLocCtrl.dispose();
    _newTagCtrl.dispose();
    _taxableCtrl.dispose();
    _igstCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/inter-entity-trades'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeOrganization: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _trades = asList(res[0], keys: const ['trades', 'interEntityTrades', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _addLine() {
    if (_sourceArticleCtrl.text.trim().isEmpty) {
      toast(context, 'Select a source tagged article.', error: true);
      return;
    }
    if (!isValidAmount(_taxableCtrl.text)) {
      toast(context, 'Enter a valid taxable value in INR.', error: true);
      return;
    }
    final label = _lookup.articles
            .where((a) => a.id == _sourceArticleCtrl.text.trim())
            .firstOrNull
            ?.label ??
        _sourceArticleCtrl.text.trim();
    setState(() {
      _lines.add({
        'sourceArticleId': _sourceArticleCtrl.text.trim(),
        if (_destLocCtrl.text.trim().isNotEmpty) 'destinationLocationId': _destLocCtrl.text.trim(),
        if (_newTagCtrl.text.trim().isNotEmpty) 'destinationTagNumber': _newTagCtrl.text.trim(),
        'taxableAmount': normAmount(_taxableCtrl.text),
        'taxAmount': isValidAmount(_igstCtrl.text) ? normAmount(_igstCtrl.text) : '0.00',
        '_label': label,
      });
      _sourceArticleCtrl.clear();
      _newTagCtrl.clear();
      _taxableCtrl.clear();
    });
  }

  Future<void> _createTrade() async {
    if (_destEntityCtrl.text.trim().isEmpty || _destBranchCtrl.text.trim().isEmpty) {
      toast(context, 'Select Destination entity and Destination branch.', error: true);
      return;
    }
    if (_lines.isEmpty) {
      toast(context, 'Add at least one trade line before creating the trade.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/inter-entity-trades',
        idempotencyKey: const Uuid().v4(),
        body: {
          'destinationLegalEntityId': _destEntityCtrl.text.trim(),
          'destinationBranchId': _destBranchCtrl.text.trim(),
          if (_transitCtrl.text.trim().isNotEmpty) 'sourceTransitLocationId': _transitCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'taxTreatment': _taxTreatment,
          'currency': _currencyCtrl.text.trim().toUpperCase(),
          'requestDate': _reqDateCtrl.text.trim(),
          if (_expDateCtrl.text.trim().isNotEmpty) 'expectedReceiptDate': _expDateCtrl.text.trim(),
          'terms': _termsCtrl.text.trim(),
          'lines': _lines
              .map((l) => Map<String, dynamic>.from(l)..remove('_label'))
              .toList(),
        },
      );
      setState(() {
        _lines.clear();
        _termsCtrl.clear();
      });
      await _load();
      if (mounted) toast(context, 'Related-entity trade created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final destBranches = _destEntityCtrl.text.trim().isEmpty
        ? _lookup.branches
        : _lookup.branches
            .where((b) => '${b.raw['legalEntityId']}' == _destEntityCtrl.text.trim())
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
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.domain_rounded,
              badge: 'Multi-Entity Commerce',
              title: 'Inter-Company Related-Entity Trading',
              subtitle:
                  'Arm\'s-length trades between separate legal entities in the same tenant, with dual journals, GST, AP/AR open items, and consolidation elimination schedules.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New related-entity trade', style: T.display(18)),
                const SizedBox(height: 14),
                LookupField(
                  label: 'Destination entity',
                  controller: _destEntityCtrl,
                  options: _lookup.legalEntities,
                  onSelected: (_) => setState(() => _destBranchCtrl.clear()),
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Destination branch',
                  controller: _destBranchCtrl,
                  options: destBranches,
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Source transit',
                  controller: _transitCtrl,
                  options: _lookup.locations,
                  hint: 'Select source transit custody',
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Trade series',
                  controller: _seriesCtrl,
                  options: _lookup.seriesFor(const ['TRADE', 'INTER', 'SALES']),
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Tax treatment'),
                    GoldDropdown<String>(
                      value: _taxTreatment,
                      items: const [
                        DropdownMenuItem(value: 'INTER_STATE_IGST', child: Text('Inter-state IGST')),
                        DropdownMenuItem(value: 'INTRA_STATE_CGST_SGST', child: Text('Intra-state CGST+SGST')),
                      ],
                      onChanged: (v) => setState(() => _taxTreatment = v ?? 'INTER_STATE_IGST'),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Currency'),
                    TextField(controller: _currencyCtrl, style: T.mono(13.5)),
                  ]),
                ]),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  DatePickField(label: 'Request date', controller: _reqDateCtrl),
                  DatePickField(label: 'Expected receipt', controller: _expDateCtrl, optional: true),
                ]),
                const SizedBox(height: 12),
                const FieldLabel('Terms'),
                TextField(
                  controller: _termsCtrl,
                  decoration: const InputDecoration(hintText: 'Arm\'s-length settlement & dispatch terms'),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Pal.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Pal.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('TRADE LINE BUILDER', style: T.caps(10, color: Pal.goldDeep)),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Source article',
                      controller: _sourceArticleCtrl,
                      options: _lookup.articles,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Destination location',
                      controller: _destLocCtrl,
                      options: _lookup.locations,
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('New destination tag'),
                    TextField(
                      controller: _newTagCtrl,
                      style: T.mono(13),
                      decoration: const InputDecoration(hintText: 'Destination barcode / tag number'),
                    ),
                    const SizedBox(height: 10),
                    ResponsiveGrid2(children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const FieldLabel('Taxable value'),
                        TextField(
                          controller: _taxableCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: T.mono(13.5),
                          decoration: const InputDecoration(hintText: '0.00'),
                        ),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const FieldLabel('IGST / Tax'),
                        TextField(
                          controller: _igstCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: T.mono(13.5),
                        ),
                      ]),
                    ]),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addLine,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Add line'),
                    ),
                    if (_lines.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (var i = 0; i < _lines.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Panel(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(children: [
                              Expanded(
                                child: Text(
                                  '${_lines[i]['_label']} · ${inr(_lines[i]['taxableAmount'])}',
                                  style: T.body(12.5, w: FontWeight.w700),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close_rounded, size: 16, color: Pal.danger),
                                onPressed: () => setState(() => _lines.removeAt(i)),
                              ),
                            ]),
                          ),
                        ),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Create trade',
                  icon: Icons.swap_calls_rounded,
                  busy: _busy,
                  onPressed: _createTrade,
                ),
              ]),
            ),
            const SectionLabel('Related-Entity Trades'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_trades.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.domain_rounded,
                  title: 'No related-entity trades yet',
                  body: 'Create an arm\'s-length trade between authorized legal entities above.',
                ),
              )
            else
              for (final t in _trades)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _pickStr(t, ['documentNumber', 'tradeNumber', 'code'], 'Inter-Entity Trade'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_pickStr(t, ['state', 'status'], 'DRAFT')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Destination Entity', _pickStr(t, ['destinationEntity', 'destinationLegalEntity'], '-'), strong: true),
                      if (_pickStr(t, ['totalAmount', 'taxableAmount']).isNotEmpty)
                        KeyValue('Total Value', inr(_pickStr(t, ['totalAmount', 'taxableAmount'])), mono: true),
                      KeyValue('Request Date', formatDate(_pickStr(t, ['requestDate', 'createdAt']))),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
