import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

String _firstStr(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v is Map) {
      final inner = v['displayName'] ?? v['legalName'] ?? v['name'] ?? v['code'] ?? v['tag'];
      if (inner != null && '$inner'.isNotEmpty) return '$inner';
    } else if (v != null && '$v'.isNotEmpty && v is! List) {
      return '$v';
    }
  }
  return fallback;
}

// ============================================================================
// 1. PROCUREMENT & INTAKE — Screenshot 677 (`/procurement`)
// ============================================================================

class ProcurementScreen extends StatefulWidget {
  const ProcurementScreen({super.key});
  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  String _tab = 'PO';
  bool _showPostingConfig = false;
  bool _loading = true;
  String? _error;

  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _pos = [];
  List<Map<String, dynamic>> _grns = [];
  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _returns = [];

  // Controlled posting configuration (Screenshot 677)
  final _postingPeriodCtrl = TextEditingController();
  final _journalSeriesCtrl = TextEditingController();
  final _poSeriesCtrl = TextEditingController();
  final _grnSeriesCtrl = TextEditingController();
  final _billSeriesCtrl = TextEditingController();
  final _debitSeriesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _postingPeriodCtrl.dispose();
    _journalSeriesCtrl.dispose();
    _poSeriesCtrl.dispose();
    _grnSeriesCtrl.dispose();
    _billSeriesCtrl.dispose();
    _debitSeriesCtrl.dispose();
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
        api.get('/procurement'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeMaterials: true,
          includeAccounting: true,
          includeInventory: true,
        ),
      ]);
      if (!mounted) return;
      final ws = asMap(res[0]);
      final lk = res[1] as WorkspaceLookup;
      setState(() {
        _pos = asList(ws['purchaseOrders'] ?? const []);
        _grns = asList(ws['goodsReceipts'] ?? const []);
        _bills = asList(ws['supplierBills'] ?? const []);
        _returns = asList(ws['purchaseReturns'] ?? const []);
        _lookup = lk;
        if (_postingPeriodCtrl.text.isEmpty && lk.openPeriods().isNotEmpty) {
          _postingPeriodCtrl.text = lk.openPeriods().first.id;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _approvePo(Map<String, dynamic> po) async {
    final id = _firstStr(po, ['id']);
    if (id.isEmpty) return;
    try {
      await context.read<ApiClient>().post(
        '/procurement/purchase-orders/$id/approve',
        idempotencyKey: const Uuid().v4(),
        body: {
          'expectedVersion': (po['version'] as num?)?.toInt() ?? 1,
          'reason': 'Approved for showroom bullion procurement.',
        },
      );
      await _load();
      if (mounted) toast(context, 'Purchase order approved.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _openCreatePoSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreatePoSheet(
        lookup: _lookup,
        defaultSeriesId: _poSeriesCtrl.text.trim(),
      ),
    );
    if (created == true) _load();
  }

  Future<void> _openCreateGrnSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateGrnSheet(
        lookup: _lookup,
        purchaseOrders: _pos,
        defaultSeriesId: _grnSeriesCtrl.text.trim(),
      ),
    );
    if (created == true) _load();
  }

  Future<void> _openCreateBillSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateBillSheet(
        lookup: _lookup,
        defaultSeriesId: _billSeriesCtrl.text.trim(),
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Procurement & Intake'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.shopping_cart_outlined,
              badge: 'Supply & Production',
              title: 'Procurement & Supplier Lifecycle',
              subtitle:
                  'Purchase orders, goods receipt with QC, supplier bill matching, and purchase returns / debit notes.',
              trailing: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Pal.goldBright,
                  foregroundColor: Pal.ink,
                  minimumSize: const Size(108, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: _tab == 'GRN'
                    ? _openCreateGrnSheet
                    : _tab == 'BILL'
                        ? _openCreateBillSheet
                        : _openCreatePoSheet,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text(
                  _tab == 'GRN'
                      ? 'New GRN'
                      : _tab == 'BILL'
                          ? 'New Bill'
                          : 'New PO',
                  style: T.body(12.5, color: Pal.ink, w: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: [
                ('PO', 'Purchase Orders (${_pos.length})', Icons.receipt_long_outlined),
                ('GRN', 'Goods Receipts (${_grns.length})', Icons.inventory_outlined),
                ('BILL', 'Supplier Bills (${_bills.length})', Icons.request_quote_outlined),
                ('RET', 'Returns / Debits (${_returns.length})', Icons.assignment_return_outlined),
              ],
            ),
            const SizedBox(height: 12),

            // Controlled posting configuration card (Screenshot 677)
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                InkWell(
                  onTap: () => setState(() => _showPostingConfig = !_showPostingConfig),
                  child: Row(children: [
                    const Icon(Icons.tune_rounded, size: 18, color: Pal.goldDeep),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Controlled posting configuration', style: T.body(14, w: FontWeight.w800)),
                        Text(
                          'Required series and period IDs validated by the API.',
                          style: T.body(11.8, color: Pal.muted),
                        ),
                      ]),
                    ),
                    Icon(
                      _showPostingConfig ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      color: Pal.goldDeep,
                    ),
                  ]),
                ),
                if (_showPostingConfig) ...[
                  const SizedBox(height: 14),
                  LookupField(
                    label: 'Posting Period UUID',
                    controller: _postingPeriodCtrl,
                    options: _lookup.openPeriods(),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Journal Series UUID',
                    controller: _journalSeriesCtrl,
                    options: _lookup.seriesFor(const ['JOURNAL']),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Purchase Order Series UUID',
                    controller: _poSeriesCtrl,
                    options: _lookup.seriesFor(const ['PO', 'PURCHASE']),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Goods Receipt Series UUID',
                    controller: _grnSeriesCtrl,
                    options: _lookup.seriesFor(const ['GRN', 'RECEIPT']),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Supplier Bill Series UUID',
                    controller: _billSeriesCtrl,
                    options: _lookup.seriesFor(const ['BILL', 'AP']),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Debit Note Series UUID',
                    controller: _debitSeriesCtrl,
                    options: _lookup.seriesFor(const ['DEBIT', 'RETURN']),
                    optional: true,
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 14),

            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 76)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'PO')
              _buildPoList()
            else if (_tab == 'GRN')
              _buildGrnList()
            else if (_tab == 'BILL')
              _buildBillList()
            else
              _buildReturnsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPoList() {
    if (_pos.isEmpty) {
      return Panel(
        child: EmptyBlock(
          icon: Icons.shopping_cart_outlined,
          title: 'No purchase orders recorded yet',
          body: 'Create a purchase order to procure gold bullion, diamonds, or artisan stock.',
          actionLabel: '+ New PO',
          onAction: _openCreatePoSheet,
        ),
      );
    }
    return Column(children: [
      for (final po in _pos)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    _firstStr(po, ['documentNumber', 'poNumber'], 'PO · ${formatDate(po['orderDate'])}'),
                    style: T.display(17),
                  ),
                ),
                StatusPill(_firstStr(po, ['state', 'status'], 'DRAFT')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Supplier', _firstStr(po, ['supplier'], '-'), strong: true),
              KeyValue('Order Date', formatDate(po['orderDate'])),
              KeyValue('Subtotal / Tax', '${inr(po['subtotal'])} + ${inr(po['taxAmount'])}', mono: true),
              KeyValue('Total Amount', inr(po['totalAmount']), strong: true, mono: true),
              if ('${po['state']}'.toUpperCase() == 'DRAFT') ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                  onPressed: () => _approvePo(po),
                  icon: const Icon(Icons.verified_outlined, size: 17),
                  label: const Text('Approve Purchase Order'),
                ),
              ],
            ]),
          ),
        ),
    ]);
  }

  Widget _buildGrnList() {
    if (_grns.isEmpty) {
      return Panel(
        child: EmptyBlock(
          icon: Icons.inventory_outlined,
          title: 'No goods receipts recorded yet',
          body: 'Record inward bullion & jewellery receipts with QC inspection.',
          actionLabel: '+ New GRN',
          onAction: _openCreateGrnSheet,
        ),
      );
    }
    return Column(children: [
      for (final g in _grns)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    _firstStr(g, ['documentNumber', 'supplierDeliveryNote'], 'GRN · ${formatDate(g['receiptDate'])}'),
                    style: T.display(17),
                  ),
                ),
                StatusPill(_firstStr(g, ['state', 'status'], 'DRAFT')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Supplier', _firstStr(g, ['supplier'], '-'), strong: true),
              KeyValue('Receipt Date', formatDate(g['receiptDate'])),
              KeyValue('Accepted Net', inr(g['acceptedNetAmount']), strong: true, mono: true),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildBillList() {
    if (_bills.isEmpty) {
      return Panel(
        child: EmptyBlock(
          icon: Icons.request_quote_outlined,
          title: 'No supplier bills recorded yet',
          body: 'Match supplier tax invoices against accepted GRN receipts.',
          actionLabel: '+ New Supplier Bill',
          onAction: _openCreateBillSheet,
        ),
      );
    }
    return Column(children: [
      for (final b in _bills)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    _firstStr(b, ['supplierInvoiceNumber', 'documentNumber'], 'Supplier Bill'),
                    style: T.display(17),
                  ),
                ),
                StatusPill(_firstStr(b, ['state', 'matchState'], 'DRAFT')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Supplier', _firstStr(b, ['supplier'], '-'), strong: true),
              KeyValue('Posting Date', formatDate(b['postingDate'])),
              KeyValue('Total Amount', inr(b['totalAmount']), strong: true, mono: true),
              if (_firstStr(b, ['varianceAmount']).isNotEmpty)
                KeyValue('3-Way Variance', inr(b['varianceAmount']), mono: true),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildReturnsList() {
    if (_returns.isEmpty) {
      return const Panel(
        child: EmptyBlock(
          icon: Icons.assignment_return_outlined,
          title: 'No purchase returns / debit notes yet',
          body: 'Quarantined or rejected inward items returned to suppliers appear here.',
        ),
      );
    }
    return Column(children: [
      for (final r in _returns)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_firstStr(r, ['documentNumber'], 'Debit Note'), style: T.display(17))),
                StatusPill(_firstStr(r, ['state'], 'DRAFT')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Supplier', _firstStr(r, ['supplier'], '-'), strong: true),
              KeyValue('Return Date', formatDate(r['returnDate'])),
              KeyValue('Total Amount', inr(r['totalAmount']), strong: true, mono: true),
            ]),
          ),
        ),
    ]);
  }
}

class _CreatePoSheet extends StatefulWidget {
  const _CreatePoSheet({required this.lookup, required this.defaultSeriesId});
  final WorkspaceLookup lookup;
  final String defaultSeriesId;
  @override
  State<_CreatePoSheet> createState() => _CreatePoSheetState();
}

class _CreatePoSheetState extends State<_CreatePoSheet> {
  final _supplierCtrl = TextEditingController();
  late final _seriesCtrl = TextEditingController(text: widget.defaultSeriesId);
  final _dateCtrl = TextEditingController(text: todayIso());
  final _metalCtrl = TextEditingController();
  final _purityCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _unitCostCtrl = TextEditingController();
  final _taxPctCtrl = TextEditingController(text: '3');
  bool _busy = false;

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _seriesCtrl.dispose();
    _dateCtrl.dispose();
    _metalCtrl.dispose();
    _purityCtrl.dispose();
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _unitCostCtrl.dispose();
    _taxPctCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_supplierCtrl.text.trim().isEmpty) {
      toast(context, 'Select supplier.', error: true);
      return;
    }
    if (!isValidWeight(_qtyCtrl.text) || !isValidAmount(_unitCostCtrl.text)) {
      toast(context, 'Enter valid quantity (g) and unit cost (INR/g).', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/procurement/purchase-orders',
        idempotencyKey: const Uuid().v4(),
        body: {
          'supplierId': _supplierCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'orderDate': _dateCtrl.text.trim(),
          'currency': 'INR',
          'lines': [
            {
              'itemKind': 'MATERIAL_LOT',
              'description': _descCtrl.text.trim().isEmpty ? 'Bullion Purchase' : _descCtrl.text.trim(),
              if (_metalCtrl.text.trim().isNotEmpty) 'metalId': _metalCtrl.text.trim(),
              if (_purityCtrl.text.trim().isNotEmpty) 'purityGradeId': _purityCtrl.text.trim(),
              'orderedQuantity': normWeight6(_qtyCtrl.text),
              'unitCost': normAmount(_unitCostCtrl.text),
              'taxRate': _taxPctCtrl.text.trim(),
            },
          ],
        },
      );
      if (mounted) {
        toast(context, 'Purchase order created.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('New Purchase Order', style: T.display(21)),
        const SizedBox(height: 14),
        LookupField(
          label: 'Supplier',
          controller: _supplierCtrl,
          options: widget.lookup.partiesByRole('SUPPLIER'),
        ),
        const SizedBox(height: 10),
        LookupField(
          label: 'PO Series',
          controller: _seriesCtrl,
          options: widget.lookup.seriesFor(const ['PO', 'PURCHASE']),
          optional: true,
        ),
        const SizedBox(height: 10),
        DatePickField(label: 'Order date', controller: _dateCtrl),
        const SizedBox(height: 10),
        ResponsiveGrid2(children: [
          LookupField(label: 'Metal', controller: _metalCtrl, options: widget.lookup.metals),
          LookupField(label: 'Purity Grade', controller: _purityCtrl, options: widget.lookup.purityGrades),
        ]),
        const SizedBox(height: 10),
        const FieldLabel('Line Description'),
        TextField(controller: _descCtrl, decoration: const InputDecoration(hintText: 'Fine 999 Bullion Bar / Ornaments')),
        const SizedBox(height: 10),
        ResponsiveGrid2(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('Quantity (g)'),
            TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(13.5),
              decoration: const InputDecoration(hintText: '0.000000'),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('Unit Cost (INR/g)'),
            TextField(
              controller: _unitCostCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(13.5),
              decoration: const InputDecoration(hintText: '0.00'),
            ),
          ]),
        ]),
        const SizedBox(height: 16),
        RoyalGoldButton(label: 'Create Purchase Order', busy: _busy, onPressed: _submit),
      ]),
    );
  }
}

class _CreateGrnSheet extends StatefulWidget {
  const _CreateGrnSheet({
    required this.lookup,
    required this.purchaseOrders,
    required this.defaultSeriesId,
  });
  final WorkspaceLookup lookup;
  final List<Map<String, dynamic>> purchaseOrders;
  final String defaultSeriesId;
  @override
  State<_CreateGrnSheet> createState() => _CreateGrnSheetState();
}

class _CreateGrnSheetState extends State<_CreateGrnSheet> {
  final _supplierCtrl = TextEditingController();
  late final _seriesCtrl = TextEditingController(text: widget.defaultSeriesId);
  final _dateCtrl = TextEditingController(text: todayIso());
  final _challanCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _seriesCtrl.dispose();
    _dateCtrl.dispose();
    _challanCtrl.dispose();
    _descCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_supplierCtrl.text.trim().isEmpty || !isValidWeight(_qtyCtrl.text) || !isValidAmount(_costCtrl.text)) {
      toast(context, 'Select supplier and enter valid received quantity & unit cost.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/procurement/goods-receipts',
        idempotencyKey: const Uuid().v4(),
        body: {
          'supplierId': _supplierCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'receiptDate': _dateCtrl.text.trim(),
          'currency': 'INR',
          if (_challanCtrl.text.trim().isNotEmpty) 'supplierDeliveryNote': _challanCtrl.text.trim(),
          'lines': [
            {
              'itemKind': 'MATERIAL_LOT',
              'description': _descCtrl.text.trim().isEmpty ? 'Goods Receipt' : _descCtrl.text.trim(),
              'receivedQuantity': normWeight6(_qtyCtrl.text),
              'acceptedQuantity': normWeight6(_qtyCtrl.text),
              'qcState': 'PASSED',
              'unitCost': normAmount(_costCtrl.text),
            },
          ],
        },
      );
      if (mounted) {
        toast(context, 'Goods receipt recorded.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('New Goods Receipt (GRN)', style: T.display(21)),
        const SizedBox(height: 14),
        LookupField(
          label: 'Supplier',
          controller: _supplierCtrl,
          options: widget.lookup.partiesByRole('SUPPLIER'),
        ),
        const SizedBox(height: 10),
        DatePickField(label: 'Receipt date', controller: _dateCtrl),
        const SizedBox(height: 10),
        const FieldLabel('Supplier Delivery Challan #'),
        TextField(controller: _challanCtrl, style: T.mono(13.5)),
        const SizedBox(height: 10),
        const FieldLabel('Description'),
        TextField(controller: _descCtrl, decoration: const InputDecoration(hintText: 'QC passed bullion / ornaments')),
        const SizedBox(height: 10),
        ResponsiveGrid2(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('Accepted Weight (g)'),
            TextField(
              controller: _qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(13.5),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('Unit Cost (INR/g)'),
            TextField(
              controller: _costCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(13.5),
            ),
          ]),
        ]),
        const SizedBox(height: 16),
        RoyalGoldButton(label: 'Save Goods Receipt', busy: _busy, onPressed: _submit),
      ]),
    );
  }
}

class _CreateBillSheet extends StatefulWidget {
  const _CreateBillSheet({required this.lookup, required this.defaultSeriesId});
  final WorkspaceLookup lookup;
  final String defaultSeriesId;
  @override
  State<_CreateBillSheet> createState() => _CreateBillSheetState();
}

class _CreateBillSheetState extends State<_CreateBillSheet> {
  final _supplierCtrl = TextEditingController();
  late final _seriesCtrl = TextEditingController(text: widget.defaultSeriesId);
  final _dateCtrl = TextEditingController(text: todayIso());
  final _invNoCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _netCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0.00');
  bool _busy = false;

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _seriesCtrl.dispose();
    _dateCtrl.dispose();
    _invNoCtrl.dispose();
    _descCtrl.dispose();
    _netCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_supplierCtrl.text.trim().isEmpty || _invNoCtrl.text.trim().isEmpty || !isValidAmount(_netCtrl.text)) {
      toast(context, 'Select supplier, enter invoice #, and net amount.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/procurement/supplier-bills',
        idempotencyKey: const Uuid().v4(),
        body: {
          'supplierId': _supplierCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'postingDate': _dateCtrl.text.trim(),
          'supplierInvoiceNumber': _invNoCtrl.text.trim(),
          'currency': 'INR',
          'lines': [
            {
              'description': _descCtrl.text.trim().isEmpty ? 'Supplier Bullion Invoice' : _descCtrl.text.trim(),
              'netAmount': normAmount(_netCtrl.text),
              'taxAmount': isValidAmount(_taxCtrl.text) ? normAmount(_taxCtrl.text) : '0.00',
            },
          ],
        },
      );
      if (mounted) {
        toast(context, 'Supplier bill recorded.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('New Supplier Bill', style: T.display(21)),
        const SizedBox(height: 14),
        LookupField(
          label: 'Supplier',
          controller: _supplierCtrl,
          options: widget.lookup.partiesByRole('SUPPLIER'),
        ),
        const SizedBox(height: 10),
        DatePickField(label: 'Posting date', controller: _dateCtrl),
        const SizedBox(height: 10),
        const FieldLabel('Supplier Tax Invoice Number'),
        TextField(controller: _invNoCtrl, style: T.mono(13.5)),
        const SizedBox(height: 10),
        const FieldLabel('Line Description'),
        TextField(controller: _descCtrl),
        const SizedBox(height: 10),
        ResponsiveGrid2(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('Net Amount (INR)'),
            TextField(
              controller: _netCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(13.5),
            ),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('GST Amount (INR)'),
            TextField(
              controller: _taxCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(13.5),
            ),
          ]),
        ]),
        const SizedBox(height: 16),
        RoyalGoldButton(label: 'Record Supplier Bill', busy: _busy, onPressed: _submit),
      ]),
    );
  }
}

// ============================================================================
// 2. KARIGAR & INTERNAL JOB WORK — Screenshot 679 (`/job-work`)
// ============================================================================

class JobWorkScreen extends StatefulWidget {
  const JobWorkScreen({super.key});
  @override
  State<JobWorkScreen> createState() => _JobWorkScreenState();
}

class _JobWorkScreenState extends State<JobWorkScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String _execution = 'KARIGAR';
  final _karigarCtrl = TextEditingController();
  final _custodyCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _businessDateCtrl = TextEditingController(text: todayIso());
  final _promisedDateCtrl = TextEditingController(text: todayIso());
  String _settlement = 'MIXED';
  final _lossCtrl = TextEditingController(text: '0.000000');
  final _specCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _karigarCtrl.dispose();
    _custodyCtrl.dispose();
    _seriesCtrl.dispose();
    _businessDateCtrl.dispose();
    _promisedDateCtrl.dispose();
    _lossCtrl.dispose();
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
      final res = await Future.wait<dynamic>([
        api.get('/job-work'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _jobs = asList(res[0], keys: const ['jobs', 'workOrders', 'jobOrders', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createJob() async {
    if (_execution == 'KARIGAR' && _karigarCtrl.text.trim().isEmpty) {
      toast(context, 'Select Karigar party or switch execution to INTERNAL.', error: true);
      return;
    }
    if (_seriesCtrl.text.trim().isEmpty) {
      toast(context, 'Select or enter Job series UUID.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/job-work',
        idempotencyKey: const Uuid().v4(),
        body: {
          'executionMode': _execution,
          'execution': _execution,
          if (_karigarCtrl.text.trim().isNotEmpty) 'karigarPartyId': _karigarCtrl.text.trim(),
          if (_custodyCtrl.text.trim().isNotEmpty) 'externalCustodyLocationId': _custodyCtrl.text.trim(),
          'documentSeriesId': _seriesCtrl.text.trim(),
          'jobSeriesId': _seriesCtrl.text.trim(),
          'businessDate': _businessDateCtrl.text.trim(),
          'promisedDate': _promisedDateCtrl.text.trim(),
          'settlementMode': _settlement,
          'settlement': _settlement,
          'allowedFineLossGrams': normWeight6(_lossCtrl.text),
          'description': _specCtrl.text.trim(),
          'specification': _specCtrl.text.trim(),
        },
      );
      _specCtrl.clear();
      await _load();
      if (mounted) toast(context, 'Controlled job work order created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Karigar Job Work'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.handyman_outlined,
              badge: 'Supply & Production',
              title: 'Karigar & Internal Job Work',
              subtitle:
                  'Fine-metal controlled issue, external custody, assay receipt, approved process loss, labour payable and exact reconciliation.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New work order', style: T.display(18)),
                const SizedBox(height: 14),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Execution'),
                    GoldDropdown<String>(
                      value: _execution,
                      items: const [
                        DropdownMenuItem(value: 'KARIGAR', child: Text('KARIGAR')),
                        DropdownMenuItem(value: 'INTERNAL', child: Text('INTERNAL')),
                      ],
                      onChanged: (v) => setState(() => _execution = v ?? 'KARIGAR'),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Settlement'),
                    GoldDropdown<String>(
                      value: _settlement,
                      items: const [
                        DropdownMenuItem(value: 'MIXED', child: Text('MIXED')),
                        DropdownMenuItem(value: 'METAL', child: Text('METAL')),
                        DropdownMenuItem(value: 'CASH', child: Text('CASH')),
                      ],
                      onChanged: (v) => setState(() => _settlement = v ?? 'MIXED'),
                    ),
                  ]),
                ]),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Karigar party UUID',
                  controller: _karigarCtrl,
                  options: _lookup.partiesByRole('KARIGAR'),
                  optional: _execution == 'INTERNAL',
                  hint: 'Select Karigar artisan',
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'External custody location UUID',
                  controller: _custodyCtrl,
                  options: _lookup.locations,
                  optional: true,
                  hint: 'Select external custody location',
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Job series UUID',
                  controller: _seriesCtrl,
                  options: _lookup.seriesFor(const ['JOB', 'WORK', 'KARIGAR']),
                  hint: 'Select job document series',
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  DatePickField(label: 'Business date', controller: _businessDateCtrl),
                  DatePickField(label: 'Promised date', controller: _promisedDateCtrl),
                ]),
                const SizedBox(height: 12),
                const FieldLabel('Allowed fine loss g'),
                TextField(
                  controller: _lossCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: T.mono(13.5),
                ),
                const SizedBox(height: 12),
                const FieldLabel('Specification / work description'),
                TextField(
                  controller: _specCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(hintText: 'Ornament specification, purity & craftsmanship instructions'),
                ),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Create controlled job',
                  icon: Icons.gavel_rounded,
                  busy: _busy,
                  onPressed: _createJob,
                ),
              ]),
            ),
            const SectionLabel('Work Orders'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_jobs.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.handyman_outlined,
                  title: 'No work orders yet',
                  body: 'Create a controlled Karigar or internal job order above.',
                ),
              )
            else
              for (final j in _jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _firstStr(j, ['documentNumber', 'jobNumber', 'code'], 'Work Order'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_firstStr(j, ['state', 'status'], 'OPEN')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Karigar / Mode', _firstStr(j, ['karigar', 'karigarParty', 'executionMode'], _execution), strong: true),
                      KeyValue('Promised Date', formatDate(_firstStr(j, ['promisedDate', 'dueDate']))),
                      if (_firstStr(j, ['allowedFineLossGrams']).isNotEmpty)
                        KeyValue('Allowed Fine Loss', fineGrams(_firstStr(j, ['allowedFineLossGrams'])), mono: true),
                      if (_firstStr(j, ['description', 'specification']).isNotEmpty)
                        KeyValue('Specification', _firstStr(j, ['description', 'specification'])),
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
// 3. APPROVAL & CONSIGNMENT — Screenshot 682 (`/approval-memos`)
// ============================================================================

class ApprovalMemosScreen extends StatefulWidget {
  const ApprovalMemosScreen({super.key});
  @override
  State<ApprovalMemosScreen> createState() => _ApprovalMemosScreenState();
}

class _ApprovalMemosScreenState extends State<ApprovalMemosScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _memos = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _returningId;

  String _direction = 'CUSTOMER_OUTBOUND';
  final _partyCtrl = TextEditingController();
  final _custodyCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _memoDateCtrl = TextEditingController(text: todayIso());
  final _dueDateCtrl = TextEditingController(text: todayIso());
  final _currencyCtrl = TextEditingController(text: 'INR');
  final _termsCtrl = TextEditingController();

  final _articleCtrl = TextEditingController();
  final _taxableCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0.00');
  final List<Map<String, dynamic>> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partyCtrl.dispose();
    _custodyCtrl.dispose();
    _seriesCtrl.dispose();
    _memoDateCtrl.dispose();
    _dueDateCtrl.dispose();
    _currencyCtrl.dispose();
    _termsCtrl.dispose();
    _articleCtrl.dispose();
    _taxableCtrl.dispose();
    _taxCtrl.dispose();
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
        api.get('/approval-memos'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _memos = asList(res[0], keys: const ['memos', 'approvalMemos', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _addLine() {
    if (_articleCtrl.text.trim().isEmpty) {
      toast(context, 'Select an eligible tagged article.', error: true);
      return;
    }
    if (!isValidAmount(_taxableCtrl.text)) {
      toast(context, 'Enter valid taxable amount in INR.', error: true);
      return;
    }
    final label = _lookup.articles
            .where((a) => a.id == _articleCtrl.text.trim())
            .firstOrNull
            ?.label ??
        _articleCtrl.text.trim();
    setState(() {
      _lines.add({
        'articleId': _articleCtrl.text.trim(),
        'taxableAmount': normAmount(_taxableCtrl.text),
        'taxAmount': isValidAmount(_taxCtrl.text) ? normAmount(_taxCtrl.text) : '0.00',
        '_label': label,
      });
      _articleCtrl.clear();
      _taxableCtrl.clear();
    });
  }

  Future<void> _createMemo() async {
    if (_partyCtrl.text.trim().isEmpty || _custodyCtrl.text.trim().isEmpty) {
      toast(context, 'Select Party and Custody location.', error: true);
      return;
    }
    if (_lines.isEmpty) {
      toast(context, 'Add at least one memo article line.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/approval-memos',
        idempotencyKey: const Uuid().v4(),
        body: {
          'direction': _direction,
          'partyId': _partyCtrl.text.trim(),
          'custodyLocationId': _custodyCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'memoDate': _memoDateCtrl.text.trim(),
          'dueDate': _dueDateCtrl.text.trim(),
          'currency': _currencyCtrl.text.trim().toUpperCase(),
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
      if (mounted) toast(context, 'Approval / consignment memo created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _returnMemo(Map<String, dynamic> memo) async {
    final id = _firstStr(memo, ['id', 'memoId']);
    if (id.isEmpty) return;
    setState(() => _returningId = id);
    try {
      await context.read<ApiClient>().post(
        '/approval-memos/$id/return',
        idempotencyKey: const Uuid().v4(),
        body: {'reason': 'Returned to showroom custody and verified.'},
      );
      await _load();
      if (mounted) toast(context, 'Memo returned to vault custody.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _returningId = null);
  }

  @override
  Widget build(BuildContext context) {
    final partyOptions = _direction == 'SUPPLIER_INBOUND'
        ? _lookup.partiesByRole('SUPPLIER')
        : _lookup.partiesByRole('CUSTOMER');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Approval & Consignment'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.handshake_outlined,
              badge: 'Custody & Ownership',
              title: 'Approval & Consignment',
              subtitle:
                  'Outbound approval memos and inbound supplier consignment with separate custody vs ownership, return, and conversion to posted sales or purchases.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New approval memo', style: T.display(18)),
                const SizedBox(height: 14),
                const FieldLabel('Direction'),
                GoldDropdown<String>(
                  value: _direction,
                  items: const [
                    DropdownMenuItem(value: 'CUSTOMER_OUTBOUND', child: Text('Customer outbound approval')),
                    DropdownMenuItem(value: 'SUPPLIER_INBOUND', child: Text('Supplier inbound consignment')),
                  ],
                  onChanged: (v) => setState(() {
                    _direction = v ?? 'CUSTOMER_OUTBOUND';
                    _partyCtrl.clear();
                  }),
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Party',
                  controller: _partyCtrl,
                  options: partyOptions,
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Custody location',
                  controller: _custodyCtrl,
                  options: _lookup.locations,
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Memo series',
                  controller: _seriesCtrl,
                  options: _lookup.seriesFor(const ['MEMO', 'APPROVAL', 'JANGAD']),
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  DatePickField(label: 'Memo date', controller: _memoDateCtrl),
                  DatePickField(label: 'Due date', controller: _dueDateCtrl),
                ]),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Currency'),
                    TextField(controller: _currencyCtrl, style: T.mono(13.5)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Terms'),
                    TextField(controller: _termsCtrl, decoration: const InputDecoration(hintText: 'Custody terms')),
                  ]),
                ]),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Pal.surfaceAlt,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Pal.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('MEMO ARTICLE LINES', style: T.caps(10, color: Pal.goldDeep)),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Eligible article',
                      controller: _articleCtrl,
                      options: _lookup.articles,
                    ),
                    const SizedBox(height: 10),
                    ResponsiveGrid2(children: [
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const FieldLabel('Taxable amount'),
                        TextField(
                          controller: _taxableCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: T.mono(13.5),
                          decoration: const InputDecoration(hintText: '0.00'),
                        ),
                      ]),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const FieldLabel('Tax amount'),
                        TextField(
                          controller: _taxCtrl,
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
                  label: 'Create memo',
                  icon: Icons.handshake_outlined,
                  busy: _busy,
                  onPressed: _createMemo,
                ),
              ]),
            ),
            const SectionLabel('Approval Memos'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_memos.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.handshake_outlined,
                  title: 'No approval memos yet',
                  body: 'Create an outbound patron approval or inbound supplier consignment memo above.',
                ),
              )
            else
              for (final m in _memos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _buildMemoCard(m),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoCard(Map<String, dynamic> m) {
    final id = _firstStr(m, ['id', 'memoId']);
    final status = _firstStr(m, ['state', 'status'], 'OPEN');
    final canReturn = ['OPEN', 'ISSUED', 'ON_APPROVAL', 'ACTIVE'].contains(status.toUpperCase());
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              _firstStr(m, ['documentNumber', 'memoNumber', 'code'], 'Approval Memo'),
              style: T.display(17),
            ),
          ),
          StatusPill(status),
        ]),
        const SizedBox(height: 8),
        KeyValue('Party', _firstStr(m, ['party', 'customer'], '-'), strong: true),
        if (_firstStr(m, ['totalAmount', 'estimatedValue']).isNotEmpty)
          KeyValue('Declared Value', inr(_firstStr(m, ['totalAmount', 'estimatedValue'])), mono: true),
        if (_firstStr(m, ['dueDate']).isNotEmpty)
          KeyValue('Due Date', formatDate(_firstStr(m, ['dueDate']))),
        if (canReturn && id.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _returningId == id ? null : () => _returnMemo(m),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
            icon: _returningId == id
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.assignment_return_outlined, size: 17),
            label: const Text('Mark Returned to Vault'),
          ),
        ],
      ]),
    );
  }
}

// ============================================================================
// 4. WHOLESALE RATE FIXING — Screenshot 684 (`/rate-fixing`)
// ============================================================================

class RateFixingScreen extends StatefulWidget {
  const RateFixingScreen({super.key});
  @override
  State<RateFixingScreen> createState() => _RateFixingScreenState();
}

class _RateFixingScreenState extends State<RateFixingScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _contracts = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  String _direction = 'WHOLESALE_CUSTOMER_SALE';
  final _partyCtrl = TextEditingController();
  final _metalCtrl = TextEditingController();
  final _purityCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _contractDateCtrl = TextEditingController(text: todayIso());
  final _fixingDeadlineCtrl = TextEditingController();
  final _deliveryDeadlineCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _fineGramsCtrl = TextEditingController();
  final _toleranceCtrl = TextEditingController(text: '0.000000');
  final _dueDaysCtrl = TextEditingController(text: '7');
  final _currencyCtrl = TextEditingController(text: 'INR');
  final _termsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partyCtrl.dispose();
    _metalCtrl.dispose();
    _purityCtrl.dispose();
    _unitCtrl.dispose();
    _seriesCtrl.dispose();
    _contractDateCtrl.dispose();
    _fixingDeadlineCtrl.dispose();
    _deliveryDeadlineCtrl.dispose();
    _qtyCtrl.dispose();
    _fineGramsCtrl.dispose();
    _toleranceCtrl.dispose();
    _dueDaysCtrl.dispose();
    _currencyCtrl.dispose();
    _termsCtrl.dispose();
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
        api.get('/rate-fixing'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeMaterials: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final raw = res[0];
      setState(() {
        _summary = raw is Map ? asMap(raw['summary'] ?? raw) : const {};
        _contracts = asList(raw, keys: const ['contracts', 'rateFixings', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createContract() async {
    if (_partyCtrl.text.trim().isEmpty || _metalCtrl.text.trim().isEmpty) {
      toast(context, 'Select Party and Metal.', error: true);
      return;
    }
    if (!isValidWeight(_qtyCtrl.text) || !isValidWeight(_fineGramsCtrl.text)) {
      toast(context, 'Enter valid Contract quantity and Exact fine grams.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/rate-fixing',
        idempotencyKey: const Uuid().v4(),
        body: {
          'direction': _direction,
          'partyId': _partyCtrl.text.trim(),
          'metalId': _metalCtrl.text.trim(),
          if (_purityCtrl.text.trim().isNotEmpty) 'purityGradeId': _purityCtrl.text.trim(),
          if (_unitCtrl.text.trim().isNotEmpty) 'unitId': _unitCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'contractDate': _contractDateCtrl.text.trim(),
          if (_fixingDeadlineCtrl.text.trim().isNotEmpty) 'fixingDeadline': _fixingDeadlineCtrl.text.trim(),
          if (_deliveryDeadlineCtrl.text.trim().isNotEmpty) 'deliveryDeadline': _deliveryDeadlineCtrl.text.trim(),
          'contractQuantity': normWeight6(_qtyCtrl.text),
          'exactFineGrams': normWeight6(_fineGramsCtrl.text),
          'fineToleranceGrams': normWeight6(_toleranceCtrl.text),
          'settlementDueDays': int.tryParse(_dueDaysCtrl.text.trim()) ?? 7,
          'currency': _currencyCtrl.text.trim().toUpperCase(),
          'terms': _termsCtrl.text.trim(),
        },
      );
      _qtyCtrl.clear();
      _fineGramsCtrl.clear();
      _termsCtrl.clear();
      await _load();
      if (mounted) toast(context, 'Draft metal-denominated contract created.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _summary['activeContracts'] ?? _contracts.length;
    final unfixedFine = '${_summary['unfixedFineExposureGrams'] ?? _summary['unfixedFineGrams'] ?? '0.000000'}';
    final undeliveredFine = '${_summary['undeliveredFineGrams'] ?? '0.000000'}';
    final unsettledVal = '${_summary['unsettledMatchedValue'] ?? '0.00'}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Wholesale Rate Fixing'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.trending_up_rounded,
              badge: 'Bullion Exposure Control',
              title: 'Wholesale & Unfixed Rate-Fixing Contracts',
              subtitle:
                  'Track physical delivery separately from rate fixing, match partial fixings and deliveries by exact fine weight, and post balanced payable or receivable obligations.',
            ),
            const SizedBox(height: 14),
            ResponsiveGrid2(children: [
              MetricTile(
                label: 'Active Contracts',
                value: '$activeCount',
                icon: Icons.description_outlined,
              ),
              MetricTile(
                label: 'Unfixed Fine Exposure',
                value: fineGrams(unfixedFine),
                icon: Icons.scale_outlined,
              ),
              MetricTile(
                label: 'Undelivered Fine',
                value: fineGrams(undeliveredFine),
                icon: Icons.local_shipping_outlined,
              ),
              MetricTile(
                label: 'Unsettled Matched Value',
                value: inr(unsettledVal),
                icon: Icons.account_balance_wallet_outlined,
              ),
            ]),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('New metal-denominated contract', style: T.display(18)),
                const SizedBox(height: 14),
                const FieldLabel('Direction'),
                GoldDropdown<String>(
                  value: _direction,
                  items: const [
                    DropdownMenuItem(value: 'WHOLESALE_CUSTOMER_SALE', child: Text('Wholesale customer sale')),
                    DropdownMenuItem(value: 'SUPPLIER_BULLION_PURCHASE', child: Text('Supplier bullion purchase')),
                  ],
                  onChanged: (v) => setState(() => _direction = v ?? 'WHOLESALE_CUSTOMER_SALE'),
                ),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Party',
                  controller: _partyCtrl,
                  options: _direction == 'SUPPLIER_BULLION_PURCHASE'
                      ? _lookup.partiesByRole('SUPPLIER')
                      : _lookup.parties,
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  LookupField(label: 'Metal', controller: _metalCtrl, options: _lookup.metals),
                  LookupField(
                    label: 'Purity / agreed fineness',
                    controller: _purityCtrl,
                    options: _lookup.purityGrades,
                    onSelected: (pg) {
                      if (pg == null) return;
                      final qty = tryDec(_qtyCtrl.text);
                      final finePer1000 = tryDec(pg.raw['finenessPerThousand']);
                      if (qty != null && finePer1000 != null) {
                        final fine = decDiv(qty * finePer1000, Decimal.fromInt(1000), scale: 6);
                        _fineGramsCtrl.text = fine.round(scale: 6).toStringAsFixed(6);
                      }
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  LookupField(label: 'Contract unit', controller: _unitCtrl, options: _lookup.units, optional: true),
                  LookupField(
                    label: 'Document series',
                    controller: _seriesCtrl,
                    options: _lookup.seriesFor(const ['RATE', 'CONTRACT', 'WHOLESALE']),
                  ),
                ]),
                const SizedBox(height: 12),
                DatePickField(label: 'Contract date', controller: _contractDateCtrl),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  DatePickField(label: 'Fixing deadline', controller: _fixingDeadlineCtrl, optional: true),
                  DatePickField(label: 'Delivery deadline', controller: _deliveryDeadlineCtrl, optional: true),
                ]),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Contract quantity'),
                    TextField(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                      decoration: const InputDecoration(hintText: '0.000000'),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Exact fine grams'),
                    TextField(
                      controller: _fineGramsCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                      decoration: const InputDecoration(hintText: '0.000000'),
                    ),
                  ]),
                ]),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Fine tolerance grams'),
                    TextField(
                      controller: _toleranceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Settlement due days'),
                    TextField(
                      controller: _dueDaysCtrl,
                      keyboardType: TextInputType.number,
                      style: T.mono(13.5),
                    ),
                  ]),
                ]),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Currency'),
                    TextField(controller: _currencyCtrl, style: T.mono(13.5)),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Commercial terms'),
                    TextField(controller: _termsCtrl, decoration: const InputDecoration(hintText: 'Margin & fixing call terms')),
                  ]),
                ]),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Create draft contract',
                  icon: Icons.lock_clock_rounded,
                  busy: _busy,
                  onPressed: _createContract,
                ),
              ]),
            ),
            const SectionLabel('Rate-Fixing Contracts'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_contracts.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.lock_clock_rounded,
                  title: 'No wholesale rate-fixing contracts yet',
                  body: 'Create a metal-denominated contract above to manage unfixed bullion exposure.',
                ),
              )
            else
              for (final c in _contracts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _firstStr(c, ['documentNumber', 'contractNumber', 'code'], 'Rate Contract'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_firstStr(c, ['state', 'status'], 'DRAFT')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Party', _firstStr(c, ['party', 'customer', 'supplier'], '-'), strong: true),
                      if (_firstStr(c, ['exactFineGrams', 'fineWeightGrams']).isNotEmpty)
                        KeyValue('Exact Fine 999', fineGrams(_firstStr(c, ['exactFineGrams', 'fineWeightGrams'])), mono: true),
                      KeyValue('Contract Date', formatDate(_firstStr(c, ['contractDate', 'createdAt']))),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
