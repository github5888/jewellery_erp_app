import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

// ---------------------------------------------------------------------------
// 1. PROCUREMENT & SUPPLIER LIFECYCLE (`/procurement`) — image-18..21.png
// ---------------------------------------------------------------------------

class ProcurementScreen extends StatefulWidget {
  const ProcurementScreen({super.key, this.initialTab = 'PO'});
  final String initialTab;
  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _PoDraftLine {
  _PoDraftLine({
    required this.itemKind,
    required this.description,
    required this.metalId,
    required this.purityGradeId,
    this.unitId = '',
    this.orderedQuantity = '',
    this.orderedPieces = 1,
    this.expectedGrossWeightGrams = '',
    required this.unitCost,
    required this.taxRate,
    this.overReceiptTolerancePct = '0',
    this.metalLabel = '',
  });

  final String itemKind; // MATERIAL | TAGGED_ARTICLE
  final String description;
  final String metalId;
  final String purityGradeId;
  final String unitId;
  final String orderedQuantity;
  final int orderedPieces;
  final String expectedGrossWeightGrams;
  final String unitCost;
  final String taxRate;
  final String overReceiptTolerancePct;
  final String metalLabel;

  Map<String, dynamic> toJson() {
    if (itemKind == 'TAGGED_ARTICLE') {
      return {
        'itemKind': 'TAGGED_ARTICLE',
        'description': description,
        'metalId': metalId,
        'purityGradeId': purityGradeId,
        'orderedPieces': orderedPieces,
        'expectedGrossWeightGrams': expectedGrossWeightGrams,
        'unitCost': unitCost,
        'taxRate': taxRate,
        'overReceiptTolerancePct': overReceiptTolerancePct,
      };
    }
    return {
      'itemKind': 'MATERIAL',
      'description': description,
      'metalId': metalId,
      'purityGradeId': purityGradeId,
      'unitId': unitId,
      'orderedQuantity': orderedQuantity,
      'unitCost': unitCost,
      'taxRate': taxRate,
      'overReceiptTolerancePct': overReceiptTolerancePct,
    };
  }
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  late String _tab = widget.initialTab == 'BILL'
      ? 'BILLS'
      : widget.initialTab == 'RETURN'
          ? 'RETURNS'
          : widget.initialTab;
  final _search = TextEditingController();
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  String? _error;
  bool _postingExpanded = true;
  String? _activeForm; // null | 'PO' | 'GRN' | 'BILL' | 'RETURN'
  bool _busy = false;

  // Controlled posting configuration (exact 6 UUIDs from image-18..21.png)
  final _periodId = TextEditingController();
  final _journalSeriesId = TextEditingController();
  final _poSeriesId = TextEditingController();
  final _grnSeriesId = TextEditingController();
  final _billSeriesId = TextEditingController();
  final _returnSeriesId = TextEditingController();

  // New PO form (`ProcurementPanel.tsx` + `createPurchaseOrderSchema`)
  final _poSupplierId = TextEditingController();
  final _poOrderDate = TextEditingController(text: todayIso());
  final _poDeliveryDate = TextEditingController();
  final _poCurrency = TextEditingController(text: 'INR');
  final _poTerms = TextEditingController();
  String _lineKind = 'MATERIAL';
  final _lineDesc = TextEditingController();
  final _lineMetalId = TextEditingController();
  final _linePurityId = TextEditingController();
  final _lineUnitId = TextEditingController();
  final _lineQty = TextEditingController();
  final _linePieces = TextEditingController(text: '1');
  final _lineGrossWt = TextEditingController();
  final _lineUnitCost = TextEditingController();
  final _lineTaxRate = TextEditingController(text: '3');
  final _lineTolerance = TextEditingController(text: '0');
  final List<_PoDraftLine> _poLines = [];

  // New GRN form (`createGoodsReceiptSchema`)
  final _grnPoId = TextEditingController();
  final _grnLocationId = TextEditingController();
  final _grnDate = TextEditingController(text: todayIso());
  final _grnDeliveryNote = TextEditingController();
  final _grnInvAcctId = TextEditingController();
  final _grnGrniAcctId = TextEditingController();
  final _grnLotOrTag = TextEditingController();
  final _grnAcceptedQty = TextEditingController();
  final _grnRejectedQty = TextEditingController(text: '0');
  final _grnQcNotes = TextEditingController();

  // New Supplier Bill form (`createSupplierBillSchema`)
  final _billPoId = TextEditingController();
  final _billGrnId = TextEditingController();
  final _billInvNo = TextEditingController();
  final _billInvDate = TextEditingController(text: todayIso());
  final _billPostDate = TextEditingController(text: todayIso());
  final _billDueDate = TextEditingController();
  final _billGrniAcctId = TextEditingController();
  final _billPayAcctId = TextEditingController();
  final _billTaxAcctId = TextEditingController();
  final _billVarAcctId = TextEditingController();
  final _billNetAmt = TextEditingController();
  final _billTaxAmt = TextEditingController(text: '0.00');

  // New Return / Debit Note form (`createPurchaseReturnSchema`)
  final _retSupplierId = TextEditingController();
  final _retDate = TextEditingController(text: todayIso());
  final _retPayAcctId = TextEditingController();
  final _retInvAcctId = TextEditingController();
  final _retReason = TextEditingController();
  String _retItemKind = 'MATERIAL';
  final _retLotId = TextEditingController();
  final _retArticleId = TextEditingController();
  final _retDesc = TextEditingController();
  final _retLineReason = TextEditingController();
  final _retQty = TextEditingController();
  final _retUnitCost = TextEditingController();
  final _retTaxRate = TextEditingController(text: '3');

  void _onPostingFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final c in [
      _periodId,
      _journalSeriesId,
      _poSeriesId,
      _grnSeriesId,
      _billSeriesId,
      _returnSeriesId,
    ]) {
      c.addListener(_onPostingFieldChanged);
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _periodId,
      _journalSeriesId,
      _poSeriesId,
      _grnSeriesId,
      _billSeriesId,
      _returnSeriesId,
    ]) {
      c.removeListener(_onPostingFieldChanged);
    }
    for (final c in [
      _search,
      _periodId,
      _journalSeriesId,
      _poSeriesId,
      _grnSeriesId,
      _billSeriesId,
      _returnSeriesId,
      _poSupplierId,
      _poOrderDate,
      _poDeliveryDate,
      _poCurrency,
      _poTerms,
      _lineDesc,
      _lineMetalId,
      _linePurityId,
      _lineUnitId,
      _lineQty,
      _linePieces,
      _lineGrossWt,
      _lineUnitCost,
      _lineTaxRate,
      _lineTolerance,
      _grnPoId,
      _grnLocationId,
      _grnDate,
      _grnDeliveryNote,
      _grnInvAcctId,
      _grnGrniAcctId,
      _grnLotOrTag,
      _grnAcceptedQty,
      _grnRejectedQty,
      _grnQcNotes,
      _billPoId,
      _billGrnId,
      _billInvNo,
      _billInvDate,
      _billPostDate,
      _billDueDate,
      _billGrniAcctId,
      _billPayAcctId,
      _billTaxAcctId,
      _billVarAcctId,
      _billNetAmt,
      _billTaxAmt,
      _retSupplierId,
      _retDate,
      _retPayAcctId,
      _retInvAcctId,
      _retReason,
      _retLotId,
      _retArticleId,
      _retDesc,
      _retLineReason,
      _retQty,
      _retUnitCost,
      _retTaxRate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canApprovePo => _poSeriesId.text.trim().isNotEmpty;

  bool get _canPostGrn =>
      _periodId.text.trim().isNotEmpty &&
      _journalSeriesId.text.trim().isNotEmpty &&
      _grnSeriesId.text.trim().isNotEmpty;

  bool get _canPostBill =>
      _periodId.text.trim().isNotEmpty &&
      _journalSeriesId.text.trim().isNotEmpty &&
      _billSeriesId.text.trim().isNotEmpty;

  bool get _canPostReturn =>
      _periodId.text.trim().isNotEmpty &&
      _journalSeriesId.text.trim().isNotEmpty &&
      _returnSeriesId.text.trim().isNotEmpty;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait([
        api.get('/procurement'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
          includeMaterials: true,
        ),
      ]);
      if (!mounted) return;
      final lk = results[1] as WorkspaceLookup;
      if (_periodId.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _periodId.text = lk.openPeriods().first.id;
      }
      if (_journalSeriesId.text.isEmpty) {
        final js = lk.seriesFor(const ['JOURNAL']);
        if (js.isNotEmpty) _journalSeriesId.text = js.first.id;
      }
      if (_poSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['PURCHASE_ORDER', 'PO']);
        if (s.isNotEmpty) _poSeriesId.text = s.first.id;
      }
      if (_grnSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['GOODS_RECEIPT', 'GRN']);
        if (s.isNotEmpty) _grnSeriesId.text = s.first.id;
      }
      if (_billSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['SUPPLIER_BILL', 'BILL']);
        if (s.isNotEmpty) _billSeriesId.text = s.first.id;
      }
      if (_returnSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['PURCHASE_RETURN', 'DEBIT']);
        if (s.isNotEmpty) _returnSeriesId.text = s.first.id;
      }
      setState(() {
        _ws = asMap(results[0]);
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _promptAuditReason({
    required String title,
    required String actionLabel,
  }) async {
    final ctrl = TextEditingController();
    String? modalErr;
    final res = await showDialog<String>(
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
                        title,
                        style: T.body(16.5, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 10),
                SaasField(
                  label: 'Audit reason (minimum 10 characters)',
                  controller: ctrl,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: actionLabel,
                    onPressed: () {
                      final r = ctrl.text.trim();
                      if (r.length < 10) {
                        setModal(
                          () => modalErr =
                              'Enter an audit reason of at least 10 characters.',
                        );
                        return;
                      }
                      Navigator.pop(ctx, r);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    return res;
  }

  void _addPoLine() {
    if (_lineDesc.text.trim().length < 3 ||
        _lineMetalId.text.trim().isEmpty ||
        _linePurityId.text.trim().isEmpty ||
        _lineUnitCost.text.trim().isEmpty) {
      toast(
        context,
        'Enter line description (3+ chars), metal, purity, and unit cost.',
        error: true,
      );
      return;
    }
    if (_lineKind == 'MATERIAL' &&
        (_lineUnitId.text.trim().isEmpty || _lineQty.text.trim().isEmpty)) {
      toast(
        context,
        'Select unit and ordered quantity for material line.',
        error: true,
      );
      return;
    }
    if (_lineKind == 'TAGGED_ARTICLE' && _lineGrossWt.text.trim().isEmpty) {
      toast(
        context,
        'Enter expected gross weight for tagged article line.',
        error: true,
      );
      return;
    }
    final mLabel = _lk.metals
            .where((m) => m.id == _lineMetalId.text.trim())
            .firstOrNull
            ?.label ??
        '';
    setState(() {
      _poLines.add(
        _PoDraftLine(
          itemKind: _lineKind,
          description: _lineDesc.text.trim(),
          metalId: _lineMetalId.text.trim(),
          purityGradeId: _linePurityId.text.trim(),
          unitId: _lineUnitId.text.trim(),
          orderedQuantity: _lineQty.text.trim(),
          orderedPieces: int.tryParse(_linePieces.text.trim()) ?? 1,
          expectedGrossWeightGrams: _lineGrossWt.text.trim(),
          unitCost: _lineUnitCost.text.trim(),
          taxRate: _lineTaxRate.text.trim().isEmpty ? '0' : _lineTaxRate.text.trim(),
          overReceiptTolerancePct:
              _lineTolerance.text.trim().isEmpty ? '0' : _lineTolerance.text.trim(),
          metalLabel: mLabel,
        ),
      );
      _lineDesc.clear();
      _lineQty.clear();
      _lineGrossWt.clear();
      _lineUnitCost.clear();
    });
  }

  Future<void> _submitPo() async {
    if (_poSupplierId.text.trim().isEmpty) {
      setState(() => _error = 'Select supplier party.');
      return;
    }
    if (_poLines.isEmpty) {
      _addPoLine();
      if (_poLines.isEmpty) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/procurement/purchase-orders',
        idempotent: true,
        body: {
          'supplierPartyId': _poSupplierId.text.trim(),
          'orderDate': _poOrderDate.text.trim(),
          if (_poDeliveryDate.text.trim().isNotEmpty)
            'expectedDeliveryDate': _poDeliveryDate.text.trim(),
          'currency': _poCurrency.text.trim().toUpperCase(),
          if (_poTerms.text.trim().length >= 3) 'terms': _poTerms.text.trim(),
          'lines': _poLines.map((l) => l.toJson()).toList(),
        },
      );
      if (!mounted) return;
      setState(() {
        _poLines.clear();
        _activeForm = null;
      });
      toast(context, 'Purchase Order created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approvePo(Map<String, dynamic> po) async {
    if (!_canApprovePo) {
      setState(
        () => _error =
            'Set Purchase Order Series UUID in Controlled posting configuration.',
      );
      return;
    }
    final reason = await _promptAuditReason(
      title: 'Approve Purchase Order',
      actionLabel: 'Approve PO',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/procurement/purchase-orders/${po['id']}/approve',
        idempotent: true,
        body: {
          'expectedVersion': asInt(po['version'], fallback: 1),
          'documentSeriesId': _poSeriesId.text.trim(),
          'reason': reason,
        },
      );
      if (!mounted) return;
      toast(context, 'Purchase Order approved.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitGrn() async {
    final pos = asList(_ws['purchaseOrders']);
    final po = pos.where((p) => '${p['id']}' == _grnPoId.text.trim()).firstOrNull;
    final poLines = asList(po?['lines']);
    if (po == null ||
        poLines.isEmpty ||
        _grnLocationId.text.trim().isEmpty ||
        _grnInvAcctId.text.trim().isEmpty ||
        _grnGrniAcctId.text.trim().isEmpty ||
        _grnLotOrTag.text.trim().isEmpty ||
        _grnAcceptedQty.text.trim().isEmpty) {
      setState(
        () => _error =
            'Select PO, location, Inventory/GRNI accounts, lot/tag code, and accepted quantity.',
      );
      return;
    }
    final firstLine = poLines.first;
    final kind = '${firstLine['itemKind'] ?? 'MATERIAL'}';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/procurement/goods-receipts',
        idempotent: true,
        body: {
          'purchaseOrderId': _grnPoId.text.trim(),
          'locationId': _grnLocationId.text.trim(),
          'receiptDate': _grnDate.text.trim(),
          if (_grnDeliveryNote.text.trim().isNotEmpty)
            'supplierDeliveryNote': _grnDeliveryNote.text.trim(),
          'inventoryAccountId': _grnInvAcctId.text.trim(),
          'grniAccountId': _grnGrniAcctId.text.trim(),
          'lines': [
            if (kind == 'TAGGED_ARTICLE')
              {
                'itemKind': 'TAGGED_ARTICLE',
                'purchaseOrderLineId': '${firstLine['id']}',
                'acceptedPieces': 1,
                'rejectedPieces': 0,
                'articleTag': _grnLotOrTag.text.trim().toUpperCase(),
                'grossWeightGrams': _grnAcceptedQty.text.trim(),
                if (_grnQcNotes.text.trim().length >= 3)
                  'qcNotes': _grnQcNotes.text.trim(),
              }
            else
              {
                'itemKind': 'MATERIAL',
                'purchaseOrderLineId': '${firstLine['id']}',
                'acceptedQuantity': _grnAcceptedQty.text.trim(),
                'rejectedQuantity': _grnRejectedQty.text.trim().isEmpty
                    ? '0'
                    : _grnRejectedQty.text.trim(),
                'lotCode': _grnLotOrTag.text.trim().toUpperCase(),
                if (_grnQcNotes.text.trim().length >= 3)
                  'qcNotes': _grnQcNotes.text.trim(),
              },
          ],
        },
      );
      if (!mounted) return;
      setState(() => _activeForm = null);
      toast(context, 'Goods Receipt created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _postGrn(Map<String, dynamic> grn) async {
    if (!_canPostGrn) {
      setState(
        () => _error =
            'Set Posting Period, Journal Series, and Goods Receipt Series UUIDs in Controlled posting configuration.',
      );
      return;
    }
    final reason = await _promptAuditReason(
      title: 'Post Goods Receipt',
      actionLabel: 'Post GRN',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/procurement/goods-receipts/${grn['id']}/post',
        idempotent: true,
        body: {
          'expectedVersion': asInt(grn['version'], fallback: 1),
          'documentSeriesId': _grnSeriesId.text.trim(),
          'postingPeriodId': _periodId.text.trim(),
          'journalSeriesId': _journalSeriesId.text.trim(),
          'reason': reason,
        },
      );
      if (!mounted) return;
      toast(context, 'Goods Receipt posted to inventory & ledger.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitSupplierBill() async {
    final pos = asList(_ws['purchaseOrders']);
    final grns = asList(_ws['goodsReceipts']);
    final po = pos.where((p) => '${p['id']}' == _billPoId.text.trim()).firstOrNull;
    final grn = grns.where((g) => '${g['id']}' == _billGrnId.text.trim()).firstOrNull;
    final poLines = asList(po?['lines']);
    final grnLines = asList(grn?['lines']);
    if (po == null ||
        poLines.isEmpty ||
        grn == null ||
        grnLines.isEmpty ||
        _billInvNo.text.trim().isEmpty ||
        _billGrniAcctId.text.trim().isEmpty ||
        _billPayAcctId.text.trim().isEmpty ||
        _billVarAcctId.text.trim().isEmpty ||
        _billNetAmt.text.trim().isEmpty) {
      setState(
        () => _error =
            'Select PO, posted GRN, invoice #, GRNI/Payable/Variance accounts, and net amount.',
      );
      return;
    }
    final poLine = poLines.first;
    final grnLine = grnLines.first;
    final isArt = '${poLine['itemKind']}' == 'TAGGED_ARTICLE';
    final qty = '${grnLine['acceptedQuantity'] ?? poLine['orderedQuantity'] ?? '1'}';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/procurement/supplier-bills',
        idempotent: true,
        body: {
          'purchaseOrderId': _billPoId.text.trim(),
          'supplierInvoiceNumber': _billInvNo.text.trim(),
          'supplierInvoiceDate': _billInvDate.text.trim(),
          'postingDate': _billPostDate.text.trim(),
          if (_billDueDate.text.trim().isNotEmpty)
            'dueDate': _billDueDate.text.trim(),
          'grniAccountId': _billGrniAcctId.text.trim(),
          'payableAccountId': _billPayAcctId.text.trim(),
          if (_billTaxAcctId.text.trim().isNotEmpty)
            'inputTaxAccountId': _billTaxAcctId.text.trim(),
          'varianceAccountId': _billVarAcctId.text.trim(),
          'lines': [
            {
              'purchaseOrderLineId': '${poLine['id']}',
              'description': '${poLine['description'] ?? 'Matched supplier bill line'}',
              if (isArt) 'billedPieces': 1 else 'billedQuantity': qty,
              'netAmount': _billNetAmt.text.trim(),
              'taxAmount':
                  _billTaxAmt.text.trim().isEmpty ? '0.00' : _billTaxAmt.text.trim(),
              'allocations': [
                {
                  'goodsReceiptLineId': '${grnLine['id']}',
                  if (isArt) 'allocatedPieces': 1 else 'allocatedQuantity': qty,
                },
              ],
            },
          ],
        },
      );
      if (!mounted) return;
      setState(() => _activeForm = null);
      toast(context, 'Supplier Bill created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _postBill(Map<String, dynamic> bill) async {
    if (!_canPostBill) {
      setState(
        () => _error =
            'Set Posting Period, Journal Series, and Supplier Bill Series UUIDs in Controlled posting configuration.',
      );
      return;
    }
    final reason = await _promptAuditReason(
      title: 'Post Supplier Bill',
      actionLabel: 'Post Bill',
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/procurement/supplier-bills/${bill['id']}/post',
        idempotent: true,
        body: {
          'expectedVersion': asInt(bill['version'], fallback: 1),
          'documentSeriesId': _billSeriesId.text.trim(),
          'postingPeriodId': _periodId.text.trim(),
          'journalSeriesId': _journalSeriesId.text.trim(),
          'reason': reason,
        },
      );
      if (!mounted) return;
      toast(context, 'Supplier Bill posted.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitPurchaseReturn() async {
    if (_retSupplierId.text.trim().isEmpty ||
        _retPayAcctId.text.trim().isEmpty ||
        _retInvAcctId.text.trim().isEmpty ||
        _retReason.text.trim().length < 10 ||
        _retDesc.text.trim().length < 3 ||
        _retLineReason.text.trim().length < 5 ||
        _retUnitCost.text.trim().isEmpty) {
      setState(
        () => _error =
            'Complete supplier, accounts, overall reason (10+ chars), line description, return reason, and unit cost.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/procurement/returns',
        idempotent: true,
        body: {
          'supplierPartyId': _retSupplierId.text.trim(),
          'returnDate': _retDate.text.trim(),
          'currency': 'INR',
          'reason': _retReason.text.trim(),
          'payableAccountId': _retPayAcctId.text.trim(),
          'inventoryAccountId': _retInvAcctId.text.trim(),
          'lines': [
            if (_retItemKind == 'TAGGED_ARTICLE')
              {
                'itemKind': 'TAGGED_ARTICLE',
                'articleId': _retArticleId.text.trim(),
                'description': _retDesc.text.trim(),
                'returnReason': _retLineReason.text.trim(),
                'qcState': 'PASSED',
                'returnPieces': 1,
                if (_retQty.text.trim().isNotEmpty)
                  'grossWeightGrams': _retQty.text.trim(),
                'unitCost': _retUnitCost.text.trim(),
                'taxRate':
                    _retTaxRate.text.trim().isEmpty ? '0' : _retTaxRate.text.trim(),
              }
            else
              {
                'itemKind': 'MATERIAL',
                'materialLotId': _retLotId.text.trim(),
                'description': _retDesc.text.trim(),
                'returnReason': _retLineReason.text.trim(),
                'qcState': 'PASSED',
                'returnQuantity': _retQty.text.trim(),
                'unitCost': _retUnitCost.text.trim(),
                'taxRate':
                    _retTaxRate.text.trim().isEmpty ? '0' : _retTaxRate.text.trim(),
              },
          ],
        },
      );
      if (!mounted) return;
      setState(() => _activeForm = null);
      toast(context, 'Purchase return draft created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _returnAction(Map<String, dynamic> ret, String action) async {
    if (action == 'post' && !_canPostReturn) {
      setState(
        () => _error =
            'Set Posting Period, Journal Series, and Debit Note Series UUIDs in Controlled posting configuration.',
      );
      return;
    }
    final reason = await _promptAuditReason(
      title: action == 'approve'
          ? 'Approve Purchase Return'
          : 'Post Purchase Return / Debit Note',
      actionLabel: action == 'approve' ? 'Approve' : 'Post Return',
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    try {
      if (action == 'approve') {
        await context.read<ApiClient>().post(
          '/procurement/returns/${ret['id']}/approve',
          idempotent: true,
          body: {
            'expectedVersion': asInt(ret['version'], fallback: 1),
            'reason': reason,
          },
        );
      } else {
        await context.read<ApiClient>().post(
          '/procurement/returns/${ret['id']}/post',
          idempotent: true,
          body: {
            'expectedVersion': asInt(ret['version'], fallback: 1),
            'documentSeriesId': _returnSeriesId.text.trim(),
            'postingPeriodId': _periodId.text.trim(),
            'journalSeriesId': _journalSeriesId.text.trim(),
            'reason': reason,
          },
        );
      }
      if (!mounted) return;
      toast(
        context,
        action == 'approve'
            ? 'Purchase return approved.'
            : 'Purchase return posted.',
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildEmptyTableCard({
    required List<String> columns,
    required String emptyMessage,
  }) {
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Pal.bgTint,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < columns.length; i++) ...[
                    if (i > 0) const SizedBox(width: 18),
                    Text(
                      columns[i],
                      style: T.body(11.5, weight: FontWeight.w700, color: Pal.inkSoft),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, color: Pal.divider),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 28),
            child: Center(
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: T.body(13, color: Pal.muted),
              ),
            ),
          ),
        ],
      ),
    );
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

    final pos = asList(_ws['purchaseOrders']);
    final grns = asList(_ws['goodsReceipts']);
    final bills = asList(_ws['supplierBills']);
    final rets = asList(_ws['purchaseReturns']);

    final poOptions = pos
        .map(
          (p) => LookupOption(
            id: '${p['id'] ?? ''}',
            label:
                '${asMap(p['supplier'])['displayName'] ?? 'PO'} · ${fmtDate('${p['orderDate']}')} · ${inr(p['totalAmount'])} (${p['state']})',
            raw: p,
          ),
        )
        .where((o) => o.id.isNotEmpty)
        .toList();
    final grnOptions = grns
        .map(
          (g) => LookupOption(
            id: '${g['id'] ?? ''}',
            label:
                '${asMap(g['supplier'])['displayName'] ?? 'GRN'} · ${fmtDate('${g['receiptDate']}')} · ${inr(g['acceptedNetAmount'])} (${g['state']})',
            raw: g,
          ),
        )
        .where((o) => o.id.isNotEmpty)
        .toList();

    final q = _search.text.trim().toLowerCase();
    bool matches(Map<String, dynamic> m, List<String> fields) {
      if (q.isEmpty) return true;
      final sup =
          '${asMap(m['supplier'])['displayName'] ?? asMap(m['supplier'])['code'] ?? ''}'
              .toLowerCase();
      if (sup.contains(q)) return true;
      return fields.any((f) => '${m[f] ?? ''}'.toLowerCase().contains(q));
    }

    final fPos = pos
        .where(
          (m) => matches(
            m,
            const ['documentNumber', 'orderNumber', 'id', 'state'],
          ),
        )
        .toList();
    final fGrns = grns
        .where(
          (m) => matches(
            m,
            const ['documentNumber', 'supplierDeliveryNote', 'id', 'state'],
          ),
        )
        .toList();
    final fBills = bills
        .where(
          (m) => matches(
            m,
            const ['supplierInvoiceNumber', 'documentNumber', 'id', 'state'],
          ),
        )
        .toList();
    final fRets = rets
        .where(
          (m) => matches(
            m,
            const ['documentNumber', 'reason', 'id', 'state'],
          ),
        )
        .toList();

    return LuxuryModuleScaffold(
      title: 'Procurement & Intake',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.shopping_cart_outlined,
      searchController: _search,
      searchHint: 'Search supplier, PO, GRN, invoice or return...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _activeForm = null;
        }),
        tabs: [
          ('PO', 'Purchase Orders (${pos.length})'),
          ('GRN', 'Goods Receipts (${grns.length})'),
          ('BILLS', 'Supplier Bills (${bills.length})'),
          ('RETURNS', 'Returns / Debits (${rets.length})'),
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

            // Hero Header Card (`Procurement and Supplier Lifecycle` — image-18..21.png)
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
                        Icons.shopping_cart_outlined,
                        size: 20,
                        color: Pal.ok,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Procurement and Supplier Lifecycle',
                          style: T.body(16, weight: FontWeight.w700, color: Pal.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Purchase orders, goods receipt with QC, supplier bill matching, and purchase returns / debit notes.',
                    style: T.body(12.3, color: Pal.muted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_tab == 'PO')
                        GoldButton(
                          label: _activeForm == 'PO' ? 'Close PO' : '+ New PO',
                          compact: true,
                          onPressed: () => setState(
                            () => _activeForm = _activeForm == 'PO' ? null : 'PO',
                          ),
                        )
                      else if (_tab == 'GRN')
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                          ),
                          onPressed: () => setState(
                            () => _activeForm = _activeForm == 'GRN' ? null : 'GRN',
                          ),
                          icon: Icon(
                            _activeForm == 'GRN'
                                ? Icons.close_rounded
                                : Icons.add_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _activeForm == 'GRN' ? 'Close GRN' : 'Record GRN',
                          ),
                        )
                      else if (_tab == 'BILLS')
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 13,
                              vertical: 9,
                            ),
                          ),
                          onPressed: () => setState(
                            () => _activeForm = _activeForm == 'BILL' ? null : 'BILL',
                          ),
                          icon: Icon(
                            _activeForm == 'BILL'
                                ? Icons.close_rounded
                                : Icons.add_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _activeForm == 'BILL'
                                ? 'Close Bill'
                                : 'Match Supplier Bill',
                          ),
                        )
                      else if (_tab == 'RETURNS')
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFB45309),
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(11),
                            ),
                          ),
                          onPressed: () => setState(
                            () => _activeForm =
                                _activeForm == 'RETURN' ? null : 'RETURN',
                          ),
                          icon: Icon(
                            _activeForm == 'RETURN'
                                ? Icons.close_rounded
                                : Icons.inventory_2_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _activeForm == 'RETURN' ? 'Close Return' : 'New Return',
                            style: T.body(
                              12.5,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Controlled posting configuration card (visible on all 4 tabs — image-18..21.png)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () =>
                        setState(() => _postingExpanded = !_postingExpanded),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Controlled posting configuration',
                                style: T.body(
                                  14,
                                  weight: FontWeight.w700,
                                  color: Pal.ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Required series and period IDs are validated by the API; blank values keep posting actions disabled.',
                                style: T.body(11.8, color: Pal.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          _postingExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: Pal.muted,
                        ),
                      ],
                    ),
                  ),
                  if (_postingExpanded) ...[
                    const SizedBox(height: 12),
                    LookupField(
                      label: 'Posting Period UUID',
                      controller: _periodId,
                      options: _lk.openPeriods(),
                      hint: 'Posting Period UUID',
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Journal Series UUID',
                      controller: _journalSeriesId,
                      options: _lk.seriesFor(const ['JOURNAL']),
                      hint: 'Journal Series UUID',
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Purchase Order Series UUID',
                      controller: _poSeriesId,
                      options: _lk.seriesFor(const ['PURCHASE_ORDER', 'PO']),
                      hint: 'Purchase Order Series UUID',
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Goods Receipt Series UUID',
                      controller: _grnSeriesId,
                      options: _lk.seriesFor(const ['GOODS_RECEIPT', 'GRN']),
                      hint: 'Goods Receipt Series UUID',
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Supplier Bill Series UUID',
                      controller: _billSeriesId,
                      options: _lk.seriesFor(const ['SUPPLIER_BILL', 'BILL']),
                      hint: 'Supplier Bill Series UUID',
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Debit Note Series UUID',
                      controller: _returnSeriesId,
                      options: _lk.seriesFor(const ['PURCHASE_RETURN', 'DEBIT']),
                      hint: 'Debit Note Series UUID',
                      optional: true,
                    ),
                  ],
                ],
              ),
            ),

            if (_activeForm == 'PO') ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'New Purchase Order',
                subtitle:
                    'Supplier commitment for bullion material lots or tagged jewellery articles.',
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _activeForm = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Supplier',
                      controller: _poSupplierId,
                      options: _lk.partiesByRole('SUPPLIER'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DatePickField(
                            label: 'Order date',
                            controller: _poOrderDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DatePickField(
                            label: 'Expected delivery',
                            controller: _poDeliveryDate,
                            optional: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Currency',
                            controller: _poCurrency,
                            mono: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Terms (optional)',
                            controller: _poTerms,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SaasDropdown(
                            label: 'Item kind',
                            value: _lineKind,
                            options: const {
                              'MATERIAL': 'Fungible bullion / material',
                              'TAGGED_ARTICLE': 'Tagged jewellery article',
                            },
                            onChanged: (v) => setState(() => _lineKind = v),
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label: 'Line description',
                            controller: _lineDesc,
                            hint: 'Line description',
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Metal',
                            controller: _lineMetalId,
                            options: _lk.metals,
                            onSelected: (_) =>
                                setState(() => _linePurityId.clear()),
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Purity grade',
                            controller: _linePurityId,
                            options: _lk.puritiesForMetal(_lineMetalId.text.trim()),
                          ),
                          const SizedBox(height: 10),
                          if (_lineKind == 'MATERIAL')
                            Row(
                              children: [
                                Expanded(
                                  child: LookupField(
                                    label: 'Unit',
                                    controller: _lineUnitId,
                                    options: _lk.units,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SaasField(
                                    label: 'Ordered quantity',
                                    controller: _lineQty,
                                    mono: true,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: SaasField(
                                    label: 'Ordered pieces',
                                    controller: _linePieces,
                                    mono: true,
                                    keyboardType: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SaasField(
                                    label: 'Expected gross g',
                                    controller: _lineGrossWt,
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
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Unit cost (INR)',
                                  controller: _lineUnitCost,
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
                                  label: 'Tax rate (%)',
                                  controller: _lineTaxRate,
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
                          OutlinedButton.icon(
                            onPressed: _addPoLine,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('Add PO line'),
                          ),
                          for (var i = 0; i < _poLines.length; i++) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${i + 1}. ${_poLines[i].description} · ${_poLines[i].itemKind == 'MATERIAL' ? '${_poLines[i].orderedQuantity} qty' : '${_poLines[i].orderedPieces} pcs'} @ ₹${_poLines[i].unitCost}',
                                    style: T.body(12.2, w: FontWeight.w600),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 17,
                                    color: Pal.err,
                                  ),
                                  onPressed: () =>
                                      setState(() => _poLines.removeAt(i)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Create Purchase Order',
                      busy: _busy,
                      onPressed: _busy ? null : _submitPo,
                    ),
                  ],
                ),
              ),
            ],

            if (_activeForm == 'GRN') ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'New Goods Receipt (GRN)',
                subtitle:
                    'Receive against an approved Purchase Order with QC & vault location.',
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _activeForm = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Purchase Order',
                      controller: _grnPoId,
                      options: poOptions,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Vault / Stock Location',
                      controller: _grnLocationId,
                      options: _lk.locations,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DatePickField(
                            label: 'Receipt date',
                            controller: _grnDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Supplier delivery note',
                            controller: _grnDeliveryNote,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Inventory Account',
                      controller: _grnInvAcctId,
                      options: _lk.accountsByControl(
                        const ['INVENTORY', 'ASSET'],
                      ),
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'GRNI Clearing Account',
                      controller: _grnGrniAcctId,
                      options: _lk.accountsByControl(
                        const ['LIABILITY', 'SUPPLIER_PAYABLE'],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Lot code / Article tag',
                            controller: _grnLotOrTag,
                            mono: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Accepted wt / qty (g)',
                            controller: _grnAcceptedQty,
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
                      label: 'QC notes (optional)',
                      controller: _grnQcNotes,
                    ),
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Create Goods Receipt',
                      busy: _busy,
                      onPressed: _busy ? null : _submitGrn,
                    ),
                  ],
                ),
              ),
            ],

            if (_activeForm == 'BILL') ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'New Supplier Bill (3-Way Match)',
                subtitle:
                    'Match supplier invoice against PO and posted GRN lines.',
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _activeForm = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Purchase Order',
                      controller: _billPoId,
                      options: poOptions,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Matched Goods Receipt',
                      controller: _billGrnId,
                      options: grnOptions,
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Supplier invoice number',
                      controller: _billInvNo,
                      mono: true,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DatePickField(
                            label: 'Invoice date',
                            controller: _billInvDate,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DatePickField(
                            label: 'Posting date',
                            controller: _billPostDate,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DatePickField(
                      label: 'Due date',
                      controller: _billDueDate,
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'GRNI Account',
                      controller: _billGrniAcctId,
                      options: _lk.accountsByControl(const ['LIABILITY']),
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Supplier Payable Account',
                      controller: _billPayAcctId,
                      options: _lk.accountsByControl(
                        const ['SUPPLIER_PAYABLE', 'LIABILITY'],
                      ),
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Input Tax Account',
                      controller: _billTaxAcctId,
                      options:
                          _lk.accountsByControl(const ['TAX_INPUT', 'ASSET']),
                      optional: true,
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Price Variance Account',
                      controller: _billVarAcctId,
                      options: _lk.accountsByControl(const ['EXPENSE']),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Net amount (INR)',
                            controller: _billNetAmt,
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
                            label: 'Tax amount (INR)',
                            controller: _billTaxAmt,
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Create Supplier Bill',
                      busy: _busy,
                      onPressed: _busy ? null : _submitSupplierBill,
                    ),
                  ],
                ),
              ),
            ],

            if (_activeForm == 'RETURN') ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'New Purchase Return / Debit Note',
                subtitle:
                    'Return defective or excess supplier stock with subledger debit.',
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _activeForm = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Supplier',
                      controller: _retSupplierId,
                      options: _lk.partiesByRole('SUPPLIER'),
                    ),
                    const SizedBox(height: 10),
                    DatePickField(label: 'Return date', controller: _retDate),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Supplier Payable Account',
                      controller: _retPayAcctId,
                      options: _lk.accountsByControl(
                        const ['SUPPLIER_PAYABLE', 'LIABILITY'],
                      ),
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Inventory Account',
                      controller: _retInvAcctId,
                      options:
                          _lk.accountsByControl(const ['INVENTORY', 'ASSET']),
                    ),
                    const SizedBox(height: 10),
                    SaasDropdown(
                      label: 'Item kind',
                      value: _retItemKind,
                      options: const {
                        'MATERIAL': 'Material lot',
                        'TAGGED_ARTICLE': 'Tagged article',
                      },
                      onChanged: (v) => setState(() => _retItemKind = v),
                    ),
                    const SizedBox(height: 10),
                    if (_retItemKind == 'MATERIAL')
                      LookupField(
                        label: 'Material lot',
                        controller: _retLotId,
                        options: _lk.materialLots,
                      )
                    else
                      LookupField(
                        label: 'Tagged article',
                        controller: _retArticleId,
                        options: _lk.articles,
                      ),
                    const SizedBox(height: 10),
                    SaasField(label: 'Line description', controller: _retDesc),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Line return reason',
                      controller: _retLineReason,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Return qty / gross g',
                            controller: _retQty,
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
                            label: 'Unit cost (INR)',
                            controller: _retUnitCost,
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
                      label: 'Audit reason (minimum 10 characters)',
                      controller: _retReason,
                    ),
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Create Return Draft',
                      busy: _busy,
                      onPressed: _busy ? null : _submitPurchaseReturn,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 100))
            else if (_tab == 'PO')
              fPos.isEmpty
                  ? _buildEmptyTableCard(
                      columns: const [
                        'Order Date',
                        'Supplier',
                        'Lines',
                        'Subtotal',
                        'Tax',
                        'Total Amount',
                        'State',
                        'Action',
                      ],
                      emptyMessage: 'No purchase orders recorded yet.',
                    )
                  : Column(
                      children: [
                        for (final po in fPos)
                          LuxuryRecordCard(
                            icon: Icons.shopping_bag_outlined,
                            code:
                                '${po['documentNumber'] ?? po['orderNumber'] ?? shortId('${po['id']}')}',
                            status: '${po['state'] ?? 'DRAFT'}',
                            lines: [
                              ('Order Date', fmtDate('${po['orderDate'] ?? ''}')),
                              (
                                'Supplier',
                                '${asMap(po['supplier'])['displayName'] ?? asMap(po['supplier'])['code'] ?? '-'}',
                              ),
                              ('Lines', '${asList(po['lines']).length}'),
                              ('Subtotal', inr(po['subtotalAmount'])),
                              ('Tax', inr(po['taxAmount'])),
                            ],
                            amountLabel: 'Total Amount',
                            amountValue: inr(po['totalAmount']),
                            actions: [
                              if ('${po['state']}'.toUpperCase() == 'DRAFT')
                                GoldButton(
                                  label: 'Approve PO',
                                  compact: true,
                                  busy: _busy,
                                  onPressed:
                                      _canApprovePo && !_busy ? () => _approvePo(po) : null,
                                ),
                              if ('${po['state']}'.toUpperCase() == 'APPROVED')
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => setState(() {
                                    _grnPoId.text = '${po['id']}';
                                    _tab = 'GRN';
                                    _activeForm = 'GRN';
                                  }),
                                  icon: const Icon(Icons.inventory_2_outlined, size: 15),
                                  label: const Text('Receive GRN'),
                                ),
                            ],
                          ),
                      ],
                    )
            else if (_tab == 'GRN')
              fGrns.isEmpty
                  ? _buildEmptyTableCard(
                      columns: const [
                        'Receipt Date',
                        'Supplier',
                        'Delivery Note',
                        'Lines & QC',
                        'Accepted Net Amount',
                        'State',
                        'Action',
                      ],
                      emptyMessage: 'No goods receipts recorded yet.',
                    )
                  : Column(
                      children: [
                        for (final grn in fGrns)
                          LuxuryRecordCard(
                            icon: Icons.inventory_outlined,
                            code:
                                '${grn['documentNumber'] ?? shortId('${grn['id']}')}',
                            status: '${grn['state'] ?? 'DRAFT'}',
                            lines: [
                              (
                                'Receipt Date',
                                fmtDate('${grn['receiptDate'] ?? ''}'),
                              ),
                              (
                                'Supplier',
                                '${asMap(grn['supplier'])['displayName'] ?? '-'}',
                              ),
                              (
                                'Delivery Note',
                                '${grn['supplierDeliveryNote'] ?? '—'}',
                              ),
                              ('Lines & QC', '${asList(grn['lines']).length} line(s)'),
                            ],
                            amountLabel: 'Accepted Net Amount',
                            amountValue: inr(grn['acceptedNetAmount']),
                            actions: [
                              if ('${grn['state']}'.toUpperCase() == 'DRAFT')
                                GoldButton(
                                  label: 'Post GRN',
                                  compact: true,
                                  busy: _busy,
                                  onPressed:
                                      _canPostGrn && !_busy ? () => _postGrn(grn) : null,
                                ),
                              if ('${grn['state']}'.toUpperCase() == 'POSTED')
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => setState(() {
                                    if ('${grn['purchaseOrderId'] ?? ''}'.isNotEmpty) {
                                      _billPoId.text = '${grn['purchaseOrderId']}';
                                    }
                                    _billGrnId.text = '${grn['id']}';
                                    _tab = 'BILLS';
                                    _activeForm = 'BILL';
                                  }),
                                  icon: const Icon(Icons.receipt_long_outlined, size: 15),
                                  label: const Text('Match Bill'),
                                ),
                            ],
                          ),
                      ],
                    )
            else if (_tab == 'BILLS')
              fBills.isEmpty
                  ? _buildEmptyTableCard(
                      columns: const [
                        'Posting Date',
                        'Invoice #',
                        'Supplier',
                        'Total Amount',
                        'Matched GRN Net',
                        'Variance',
                        'State',
                        'Action',
                      ],
                      emptyMessage: 'No supplier bills recorded yet.',
                    )
                  : Column(
                      children: [
                        for (final bill in fBills)
                          LuxuryRecordCard(
                            icon: Icons.receipt_long_outlined,
                            code:
                                '${bill['supplierInvoiceNumber'] ?? bill['documentNumber'] ?? shortId('${bill['id']}')}',
                            status: '${bill['state'] ?? 'DRAFT'}',
                            lines: [
                              (
                                'Posting Date',
                                fmtDate('${bill['postingDate'] ?? ''}'),
                              ),
                              (
                                'Invoice #',
                                '${bill['supplierInvoiceNumber'] ?? '-'}',
                              ),
                              (
                                'Supplier',
                                '${asMap(bill['supplier'])['displayName'] ?? '-'}',
                              ),
                              (
                                'Matched GRN Net',
                                inr(bill['matchedReceiptNetAmount']),
                              ),
                              ('Variance', inr(bill['varianceAmount'])),
                            ],
                            amountLabel: 'Total Amount',
                            amountValue: inr(bill['totalAmount']),
                            actions: [
                              if ('${bill['state']}'.toUpperCase() == 'DRAFT')
                                GoldButton(
                                  label: 'Post Bill',
                                  compact: true,
                                  busy: _busy,
                                  onPressed:
                                      _canPostBill && !_busy ? () => _postBill(bill) : null,
                                ),
                            ],
                          ),
                      ],
                    )
            else
              fRets.isEmpty
                  ? _buildEmptyTableCard(
                      columns: const [
                        'Date',
                        'Doc #',
                        'Supplier',
                        'Total Amount',
                        'Settled / Open',
                        'State',
                        'Action',
                      ],
                      emptyMessage: 'No purchase returns recorded yet.',
                    )
                  : Column(
                      children: [
                        for (final ret in fRets)
                          LuxuryRecordCard(
                            icon: Icons.assignment_return_outlined,
                            code:
                                '${ret['documentNumber'] ?? shortId('${ret['id']}')}',
                            status: '${ret['state'] ?? 'DRAFT'}',
                            lines: [
                              ('Date', fmtDate('${ret['returnDate'] ?? ''}')),
                              (
                                'Doc #',
                                '${ret['documentNumber'] ?? shortId('${ret['id']}')}',
                              ),
                              (
                                'Supplier',
                                '${asMap(ret['supplier'])['displayName'] ?? '-'}',
                              ),
                              (
                                'Settled / Open',
                                '${inr(ret['settledAmount'] ?? '0')} / ${inr(ret['outstandingAmount'] ?? ret['totalAmount'])}',
                              ),
                            ],
                            amountLabel: 'Total Amount',
                            amountValue: inr(ret['totalAmount']),
                            actions: [
                              if ('${ret['state']}'.toUpperCase() == 'DRAFT')
                                GoldButton(
                                  label: 'Approve',
                                  compact: true,
                                  busy: _busy,
                                  onPressed: _busy
                                      ? null
                                      : () => _returnAction(ret, 'approve'),
                                ),
                              if ('${ret['state']}'.toUpperCase() == 'APPROVED')
                                GoldButton(
                                  label: 'Post Return',
                                  compact: true,
                                  busy: _busy,
                                  onPressed: _canPostReturn && !_busy
                                      ? () => _returnAction(ret, 'post')
                                      : null,
                                ),
                            ],
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
// 2. KARIGAR & INTERNAL JOB WORK (`/job-work`) — `image-23.png`
// ---------------------------------------------------------------------------

class JobWorkScreen extends StatefulWidget {
  const JobWorkScreen({super.key});
  @override
  State<JobWorkScreen> createState() => _JobWorkScreenState();
}

class _JobWorkScreenState extends State<JobWorkScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _formExpanded = true;
  List<Map<String, dynamic>> _orders = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Exact 9 fields from `image-23.png` (`New work order`)
  String _execution = 'KARIGAR';
  final _karigarPartyId = TextEditingController();
  final _custodyLocationId = TextEditingController();
  final _jobSeriesId = TextEditingController();
  final _businessDate = TextEditingController(text: todayIso());
  final _promisedDate = TextEditingController(text: todayIso());
  String _settlement = 'MIXED';
  final _allowedLoss = TextEditingController(text: '0.000000');
  final _spec = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _search,
      _karigarPartyId,
      _custodyLocationId,
      _jobSeriesId,
      _businessDate,
      _promisedDate,
      _allowedLoss,
      _spec,
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
        api.get('/job-work'),
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
      if (_jobSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['JOB', 'WORK_ORDER']);
        if (s.isNotEmpty) _jobSeriesId.text = s.first.id;
      }
      if (_custodyLocationId.text.isEmpty) {
        final locs = lk.locationsByType(const ['EXTERNAL_CUSTODY', 'VAULT']);
        if (locs.isNotEmpty) _custodyLocationId.text = locs.first.id;
      }
      setState(() {
        _orders = asList(
          res[0],
          keys: const ['workOrders', 'orders', 'jobOrders', 'items'],
        );
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createJob() async {
    if (_execution == 'KARIGAR' && _karigarPartyId.text.trim().isEmpty) {
      setState(() => _error = 'Select Karigar party UUID.');
      return;
    }
    if (_custodyLocationId.text.trim().isEmpty ||
        _jobSeriesId.text.trim().isEmpty ||
        _spec.text.trim().length < 3) {
      setState(
        () => _error =
            'Select External custody location UUID, Job series UUID, and Specification / work description (3+ chars).',
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

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/job-work/work-orders',
        idempotent: true,
        body: {
          'executionMode': _execution,
          if (_karigarPartyId.text.trim().isNotEmpty)
            'karigarPartyId': _karigarPartyId.text.trim(),
          'externalCustodyLocationId': _custodyLocationId.text.trim(),
          'documentSeriesId': _jobSeriesId.text.trim(),
          'businessDate': _businessDate.text.trim(),
          'promisedDate': _promisedDate.text.trim(),
          'settlementMode': _settlement,
          'allowedFineLossGrams': normWeight6(lossText),
          'description': _spec.text.trim(),
        },
      );
      if (!mounted) return;
      _spec.clear();
      toast(context, 'Controlled work order created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openJobLifecycleSheet(Map<String, dynamic> job) async {
    var actionTab = 'ISSUE';
    final balanceCtrl = TextEditingController();
    final balVerCtrl = TextEditingController(text: '1');
    final issueQtyCtrl = TextEditingController();
    final issueFineCtrl = TextEditingController();
    final issueNoteCtrl = TextEditingController();

    final recvLocCtrl = TextEditingController(
      text: _lk.locations.isNotEmpty ? _lk.locations.first.id : '',
    );
    final recvMetalCtrl = TextEditingController(
      text: _lk.metals.isNotEmpty ? _lk.metals.first.id : '',
    );
    final recvPurityCtrl = TextEditingController();
    final recvGrossCtrl = TextEditingController();
    final recvNetCtrl = TextEditingController();
    final recvFineCtrl = TextEditingController();
    final recvLossCtrl = TextEditingController(text: '0.000000');
    final assayRefCtrl = TextEditingController();

    final apvLossCtrl = TextEditingController(
      text: '${job['allowedFineLossGrams'] ?? '0.000000'}',
    );
    final apvReasonCtrl = TextEditingController();

    final labourAmtCtrl = TextEditingController();
    final periodCtrl = TextEditingController(
      text: _lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : '',
    );
    final jrnSeriesCtrl = TextEditingController(
      text: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? _lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
    final expAcctCtrl = TextEditingController();
    final payAcctCtrl = TextEditingController();
    final recReasonCtrl = TextEditingController();

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
                        'Manage Job · ${job['documentNumber'] ?? job['jobNumber'] ?? shortId('${job['id']}')}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${job['state'] ?? job['status'] ?? 'OPEN'}'),
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
                    ('ISSUE', 'Issue Metal'),
                    ('RECEIPT', 'Assay Receipt'),
                    ('LOSS', 'Approve Loss'),
                    ('RECONCILE', 'Labour & Reconcile'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (actionTab == 'ISSUE') ...[
                  LookupField(
                    label: 'Source lot balance UUID',
                    controller: balanceCtrl,
                    options: _lk.lotBalances,
                    onSelected: (opt) {
                      if (opt != null) {
                        setSheet(() {
                          balVerCtrl.text =
                              '${opt.raw['balanceVersion'] ?? opt.raw['version'] ?? 1}';
                          issueQtyCtrl.text = '${opt.raw['quantityGrams'] ?? ''}';
                          issueFineCtrl.text =
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
                          controller: balVerCtrl,
                          mono: true,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Issue quantity g',
                          controller: issueQtyCtrl,
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
                    label: 'Issue fine 999 g',
                    controller: issueFineCtrl,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Custody notes (optional)',
                    controller: issueNoteCtrl,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Issue Controlled Metal',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (balanceCtrl.text.trim().isEmpty ||
                                !isValidWeight(issueQtyCtrl.text) ||
                                !isValidWeight(issueFineCtrl.text)) {
                              setSheet(
                                () => sheetErr =
                                    'Select source balance and enter valid issue quantity & fine weight.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/job-work/work-orders/${job['id']}/issues',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(job['version'], fallback: 1),
                                  'businessDate': todayIso(),
                                  'lines': [
                                    {
                                      'balanceId': balanceCtrl.text.trim(),
                                      'expectedBalanceVersion':
                                          int.tryParse(balVerCtrl.text.trim()) ??
                                              1,
                                      'quantityGrams':
                                          normWeight6(issueQtyCtrl.text),
                                      'fineWeightGrams':
                                          normWeight6(issueFineCtrl.text),
                                    },
                                  ],
                                  if (issueNoteCtrl.text.trim().isNotEmpty)
                                    'notes': issueNoteCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Metal issued to external custody.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (actionTab == 'RECEIPT') ...[
                  LookupField(
                    label: 'Destination vault / location UUID',
                    controller: recvLocCtrl,
                    options: _lk.locations,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Metal',
                    controller: recvMetalCtrl,
                    options: _lk.metals,
                    onSelected: (_) => setSheet(() => recvPurityCtrl.clear()),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Purity grade',
                    controller: recvPurityCtrl,
                    options: _lk.puritiesForMetal(recvMetalCtrl.text.trim()),
                    onSelected: (opt) {
                      final fineRatio = tryDec(
                            opt?.raw['finenessPerThousand'] ?? '916',
                          ) ??
                          Decimal.fromInt(916);
                      final net = tryDec(recvNetCtrl.text);
                      if (net != null) {
                        recvFineCtrl.text =
                            ((net * fineRatio) / Decimal.fromInt(1000))
                                .toDecimal(scaleOnInfinitePrecision: 6)
                                .toStringAsFixed(6);
                      }
                      setSheet(() {});
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Gross weight g',
                          controller: recvGrossCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Net metal weight g',
                          controller: recvNetCtrl,
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
                          label: 'Fine 999 g',
                          controller: recvFineCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Process loss fine g',
                          controller: recvLossCtrl,
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
                    label: 'Assay certificate / reference',
                    controller: assayRefCtrl,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Record Assay Receipt',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (recvLocCtrl.text.trim().isEmpty ||
                                recvMetalCtrl.text.trim().isEmpty ||
                                recvPurityCtrl.text.trim().isEmpty ||
                                !isValidWeight(recvGrossCtrl.text) ||
                                !isValidWeight(recvFineCtrl.text)) {
                              setSheet(
                                () => sheetErr =
                                    'Complete destination location, metal, purity, gross weight, and fine weight.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/job-work/work-orders/${job['id']}/receipts',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(job['version'], fallback: 1),
                                  'businessDate': todayIso(),
                                  'locationId': recvLocCtrl.text.trim(),
                                  'metalId': recvMetalCtrl.text.trim(),
                                  'purityGradeId': recvPurityCtrl.text.trim(),
                                  'grossWeightGrams':
                                      normWeight6(recvGrossCtrl.text),
                                  'netMetalWeightGrams': normWeight6(
                                    recvNetCtrl.text.trim().isEmpty
                                        ? recvGrossCtrl.text
                                        : recvNetCtrl.text,
                                  ),
                                  'fineWeightGrams':
                                      normWeight6(recvFineCtrl.text),
                                  'processLossFineGrams': normWeight6(
                                    recvLossCtrl.text.trim().isEmpty
                                        ? '0'
                                        : recvLossCtrl.text,
                                  ),
                                  if (assayRefCtrl.text.trim().isNotEmpty)
                                    'assayReference': assayRefCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Assay receipt recorded.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (actionTab == 'LOSS') ...[
                  SaasField(
                    label: 'Approved fine loss g',
                    controller: apvLossCtrl,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Approval reason (minimum 10 characters)',
                    controller: apvReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Approve Process Loss',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (tryDec(apvLossCtrl.text) == null ||
                                apvReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter valid approved fine loss and a reason of 10+ characters.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/job-work/work-orders/${job['id']}/approve-loss',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(job['version'], fallback: 1),
                                  'approvedFineLossGrams':
                                      normWeight6(apvLossCtrl.text),
                                  'reason': apvReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Process loss approved.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  SaasField(
                    label: 'Labour payable amount (INR)',
                    controller: labourAmtCtrl,
                    hint: '0.00',
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                  LookupField(
                    label: 'Labour Expense Account',
                    controller: expAcctCtrl,
                    options: _lk.accountsByControl(const ['EXPENSE']),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Karigar Payable Account',
                    controller: payAcctCtrl,
                    options: _lk.accountsByControl(
                      const ['SUPPLIER_PAYABLE', 'LIABILITY'],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Reconciliation audit reason (min 10 chars)',
                    controller: recReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Post Labour & Reconcile Job',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (periodCtrl.text.trim().isEmpty ||
                                jrnSeriesCtrl.text.trim().isEmpty ||
                                recReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select posting period, journal series, and enter a 10+ char reason.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/job-work/work-orders/${job['id']}/reconcile',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(job['version'], fallback: 1),
                                  if (labourAmtCtrl.text.trim().isNotEmpty)
                                    'labourAmount':
                                        normAmount(labourAmtCtrl.text),
                                  'postingPeriodId': periodCtrl.text.trim(),
                                  'journalSeriesId': jrnSeriesCtrl.text.trim(),
                                  if (expAcctCtrl.text.trim().isNotEmpty)
                                    'labourExpenseAccountId':
                                        expAcctCtrl.text.trim(),
                                  if (payAcctCtrl.text.trim().isNotEmpty)
                                    'payableAccountId': payAcctCtrl.text.trim(),
                                  'reason': recReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Work order reconciled.');
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
      balanceCtrl,
      balVerCtrl,
      issueQtyCtrl,
      issueFineCtrl,
      issueNoteCtrl,
      recvLocCtrl,
      recvMetalCtrl,
      recvPurityCtrl,
      recvGrossCtrl,
      recvNetCtrl,
      recvFineCtrl,
      recvLossCtrl,
      assayRefCtrl,
      apvLossCtrl,
      apvReasonCtrl,
      labourAmtCtrl,
      periodCtrl,
      jrnSeriesCtrl,
      expAcctCtrl,
      payAcctCtrl,
      recReasonCtrl,
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
    bool isDone(Map<String, dynamic> w) {
      final s = '${w['state'] ?? w['status'] ?? ''}'.toUpperCase();
      return s == 'COMPLETED' || s == 'CLOSED' || s == 'RECONCILED';
    }

    final inProcCount = _orders.where((w) => !isDone(w)).length;
    final doneCount = _orders.where(isDone).length;

    final filtered = _orders.where((w) {
      if (_filter == 'IN_PROCESS' && isDone(w)) return false;
      if (_filter == 'COMPLETED' && !isDone(w)) return false;
      if (q.isEmpty) return true;
      final hay =
          '${w['documentNumber'] ?? ''} ${w['jobNumber'] ?? ''} ${asMap(w['karigar'])['displayName'] ?? ''} ${w['description'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Karigar Job Work',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.handyman_outlined,
      searchController: _search,
      searchHint: 'Search by Karigar / Job No...',
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
          ('ALL', 'All (${_orders.length})'),
          ('IN_PROCESS', 'In Process ($inProcCount)'),
          ('COMPLETED', 'Completed ($doneCount)'),
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

            // Hero Header Card (`Karigar & Internal Job Work` — image-23.png)
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
                        Icons.handyman_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Karigar & Internal Job Work',
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
                    'Fine-metal controlled issue, external custody, assay receipt, approved process loss, labour payable and exact reconciliation.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // `New work order` card (exact 9 fields from image-23.png)
            SaasFormCard(
              title: 'New work order',
              trailing: TextButton(
                onPressed: () => setState(() => _formExpanded = !_formExpanded),
                child: Text(_formExpanded ? 'Hide' : 'Show'),
              ),
              child: !_formExpanded
                  ? Text(
                      'Tap Show to create a controlled Karigar or internal work order.',
                      style: T.body(12.2, color: Pal.muted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SaasDropdown(
                          label: 'Execution',
                          value: _execution,
                          options: const {
                            'KARIGAR': 'KARIGAR',
                            'INTERNAL': 'INTERNAL',
                          },
                          onChanged: (v) => setState(() => _execution = v),
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Karigar party UUID',
                          controller: _karigarPartyId,
                          options: _lk.partiesByRole('KARIGAR'),
                          hint: 'Select Karigar party',
                          optional: _execution == 'INTERNAL',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'External custody location UUID',
                          controller: _custodyLocationId,
                          options: _lk.locationsByType(
                            const ['EXTERNAL_CUSTODY', 'VAULT'],
                          ),
                          hint: 'Select external custody location',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Job series UUID',
                          controller: _jobSeriesId,
                          options: _lk.seriesFor(const ['JOB', 'WORK_ORDER']),
                          hint: 'Select job series',
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
                              child: SaasDropdown(
                                label: 'Settlement',
                                value: _settlement,
                                options: const {
                                  'MIXED': 'MIXED',
                                  'CASH': 'CASH',
                                  'FINE_METAL': 'FINE_METAL',
                                },
                                onChanged: (v) =>
                                    setState(() => _settlement = v),
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
                          label: 'Specification / work description',
                          controller: _spec,
                        ),
                        const SizedBox(height: 14),
                        RoyalGoldButton(
                          label: 'Create controlled job',
                          busy: _busy,
                          onPressed: _busy ? null : _createJob,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Panel(child: Skeleton(height: 92))
            else if (filtered.isEmpty)
              const SaasEmptyBox('No work orders yet.')
            else
              for (final w in filtered)
                LuxuryRecordCard(
                  icon: Icons.handyman_outlined,
                  code:
                      '${w['documentNumber'] ?? w['jobNumber'] ?? shortId('${w['id']}')}',
                  status: '${w['state'] ?? w['status'] ?? 'OPEN'}',
                  lines: [
                    (
                      'Karigar / Execution',
                      '${asMap(w['karigar'])['displayName'] ?? w['executionMode'] ?? 'KARIGAR'}',
                    ),
                    (
                      'Business → Promised',
                      '${fmtDate('${w['businessDate'] ?? ''}')} → ${fmtDate('${w['promisedDate'] ?? ''}')}',
                    ),
                    if ('${w['description'] ?? ''}'.isNotEmpty)
                      ('Specification', '${w['description']}'),
                    (
                      'Settlement / Loss',
                      '${w['settlementMode'] ?? 'MIXED'} · Allowed ${grams(w['allowedFineLossGrams'])}',
                    ),
                  ],
                  amountLabel: 'Issued / Recv Fine',
                  amountValue:
                      '${grams(w['issuedFineGrams'])} / ${grams(w['receivedFineGrams'])}',
                  actions: [
                    GoldButton(
                      label: 'Manage Job',
                      compact: true,
                      onPressed: () => _openJobLifecycleSheet(w),
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
// 3. APPROVAL & CONSIGNMENT (`/approval-memos`) — `image-26.png`
// ---------------------------------------------------------------------------

class ApprovalConsignmentScreen extends StatefulWidget {
  const ApprovalConsignmentScreen({super.key});
  @override
  State<ApprovalConsignmentScreen> createState() =>
      _ApprovalConsignmentScreenState();
}

class _MemoDraftLine {
  const _MemoDraftLine({
    required this.articleId,
    required this.articleLabel,
    required this.taxableAmount,
    required this.taxAmount,
  });
  final String articleId;
  final String articleLabel;
  final String taxableAmount;
  final String taxAmount;
}

class _ApprovalConsignmentScreenState extends State<ApprovalConsignmentScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _formExpanded = true;
  List<Map<String, dynamic>> _memos = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Exact fields from `image-26.png` (`New approval memo`)
  String _direction = 'CUSTOMER_OUTBOUND';
  final _partyId = TextEditingController();
  final _custodyLocationId = TextEditingController();
  final _seriesId = TextEditingController();
  final _memoDate = TextEditingController(text: todayIso());
  final _dueDate = TextEditingController(text: todayIso());
  final _currency = TextEditingController(text: 'INR');
  final _terms = TextEditingController();

  final _articleId = TextEditingController();
  final _taxableAmt = TextEditingController();
  final _taxAmt = TextEditingController(text: '0.00');
  final List<_MemoDraftLine> _lines = [];

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
      _custodyLocationId,
      _seriesId,
      _memoDate,
      _dueDate,
      _currency,
      _terms,
      _articleId,
      _taxableAmt,
      _taxAmt,
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
        api.get('/approval-memos'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final lk = res[1] as WorkspaceLookup;
      if (_seriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['APPROVAL', 'MEMO', 'CONSIGNMENT']);
        if (s.isNotEmpty) _seriesId.text = s.first.id;
      }
      setState(() {
        _memos = asList(
          res[0],
          keys: const ['memos', 'approvalMemos', 'items'],
        );
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addLine() {
    if (_articleId.text.trim().isEmpty || !isValidAmount(_taxableAmt.text)) {
      toast(
        context,
        'Select eligible article and enter taxable amount.',
        error: true,
      );
      return;
    }
    final label = _lk.articles
            .where((a) => a.id == _articleId.text.trim())
            .firstOrNull
            ?.label ??
        _articleId.text.trim();
    setState(() {
      _lines.add(
        _MemoDraftLine(
          articleId: _articleId.text.trim(),
          articleLabel: label,
          taxableAmount: normAmount(_taxableAmt.text),
          taxAmount: _taxAmt.text.trim().isEmpty
              ? '0.00'
              : normAmount(_taxAmt.text),
        ),
      );
      _articleId.clear();
      _taxableAmt.clear();
      _taxAmt.text = '0.00';
    });
  }

  Future<void> _createMemo() async {
    if (_partyId.text.trim().isEmpty ||
        _custodyLocationId.text.trim().isEmpty ||
        _seriesId.text.trim().isEmpty) {
      setState(
        () => _error = 'Select Party, Custody location, and Memo series.',
      );
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
        '/approval-memos',
        idempotent: true,
        body: {
          'direction': _direction,
          'partyId': _partyId.text.trim(),
          'custodyLocationId': _custodyLocationId.text.trim(),
          'documentSeriesId': _seriesId.text.trim(),
          'memoDate': _memoDate.text.trim(),
          'dueDate': _dueDate.text.trim(),
          'currency': _currency.text.trim().toUpperCase(),
          if (_terms.text.trim().isNotEmpty) 'terms': _terms.text.trim(),
          'lines': _lines
              .map(
                (l) => {
                  'articleId': l.articleId,
                  'taxableAmount': l.taxableAmount,
                  'taxAmount': l.taxAmount,
                },
              )
              .toList(),
        },
      );
      if (!mounted) return;
      setState(() => _lines.clear());
      _terms.clear();
      toast(context, 'Approval / consignment memo created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMemoLifecycleSheet(Map<String, dynamic> memo) async {
    var actionTab = 'ISSUE';
    final issueReasonCtrl = TextEditingController();

    final convDateCtrl = TextEditingController(text: todayIso());
    final invSeriesCtrl = TextEditingController(
      text: _lk.seriesFor(const ['INVOICE', 'SALE', 'BILL']).isNotEmpty
          ? _lk.seriesFor(const ['INVOICE', 'SALE', 'BILL']).first.id
          : '',
    );
    final convPeriodCtrl = TextEditingController(
      text: _lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : '',
    );
    final convJrnCtrl = TextEditingController(
      text: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? _lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
    final convArticleCtrl = TextEditingController();
    final convReasonCtrl = TextEditingController();

    final retDateCtrl = TextEditingController(text: todayIso());
    final retLocCtrl = TextEditingController(
      text: _lk.locations.isNotEmpty ? _lk.locations.first.id : '',
    );
    final retArticleCtrl = TextEditingController();
    final retReasonCtrl = TextEditingController();

    final memoLines = asList(memo['lines']);
    final memoArticleOptions = [
      for (final l in memoLines)
        if ('${l['articleId'] ?? asMap(l['article'])['id'] ?? ''}'.isNotEmpty)
          LookupOption(
            id: '${l['articleId'] ?? asMap(l['article'])['id']}',
            label:
                '${asMap(l['article'])['tagNumber'] ?? asMap(l['article'])['description'] ?? shortId('${l['articleId'] ?? asMap(l['article'])['id']}')} · ${inr(l['taxableAmount'])}',
            raw: l,
          ),
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
                        'Manage Memo · ${memo['documentNumber'] ?? memo['memoNumber'] ?? shortId('${memo['id']}')}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${memo['state'] ?? memo['status'] ?? 'OPEN'}'),
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
                    ('ISSUE', 'Issue Memo'),
                    ('CONVERT', 'Partial Convert'),
                    ('RETURN', 'Return Custody'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (actionTab == 'ISSUE') ...[
                  SaasField(
                    label: 'Custody handover / approval note',
                    controller: issueReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Issue Ownership-Safe Approval Memo',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/approval-memos/${memo['id']}/issue',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(memo['version'], fallback: 1),
                                  if (issueReasonCtrl.text.trim().isNotEmpty)
                                    'notes': issueReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Approval memo issued.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (actionTab == 'CONVERT') ...[
                  DatePickField(
                    label: 'Conversion date',
                    controller: convDateCtrl,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Article to convert (blank = all open lines)',
                    controller: convArticleCtrl,
                    options: memoArticleOptions.isNotEmpty
                        ? memoArticleOptions
                        : _lk.articles,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Invoice / Purchase Series UUID',
                    controller: invSeriesCtrl,
                    options: _lk.seriesFor(
                      const ['INVOICE', 'SALE', 'BILL', 'PURCHASE'],
                    ),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Posting Period UUID',
                    controller: convPeriodCtrl,
                    options: _lk.openPeriods(),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Journal Series UUID',
                    controller: convJrnCtrl,
                    options: _lk.seriesFor(const ['JOURNAL']),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Conversion audit reason (min 10 chars)',
                    controller: convReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Convert Approved Item(s)',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (convReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter a conversion reason of at least 10 characters.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/approval-memos/${memo['id']}/convert',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(memo['version'], fallback: 1),
                                  'conversionDate': convDateCtrl.text.trim(),
                                  if (convArticleCtrl.text.trim().isNotEmpty)
                                    'articleIds': [convArticleCtrl.text.trim()],
                                  if (invSeriesCtrl.text.trim().isNotEmpty)
                                    'documentSeriesId':
                                        invSeriesCtrl.text.trim(),
                                  if (convPeriodCtrl.text.trim().isNotEmpty)
                                    'postingPeriodId':
                                        convPeriodCtrl.text.trim(),
                                  if (convJrnCtrl.text.trim().isNotEmpty)
                                    'journalSeriesId': convJrnCtrl.text.trim(),
                                  'reason': convReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Memo conversion recorded.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  DatePickField(
                    label: 'Return date',
                    controller: retDateCtrl,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Return vault / showroom location',
                    controller: retLocCtrl,
                    options: _lk.locations,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Returned article (blank = all remaining)',
                    controller: retArticleCtrl,
                    options: memoArticleOptions.isNotEmpty
                        ? memoArticleOptions
                        : _lk.articles,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Return inspection / audit reason (min 10 chars)',
                    controller: retReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Record Custody Return',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (retLocCtrl.text.trim().isEmpty ||
                                retReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select return location and enter a reason of at least 10 characters.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/approval-memos/${memo['id']}/return',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(memo['version'], fallback: 1),
                                  'returnDate': retDateCtrl.text.trim(),
                                  'returnLocationId': retLocCtrl.text.trim(),
                                  if (retArticleCtrl.text.trim().isNotEmpty)
                                    'articleIds': [retArticleCtrl.text.trim()],
                                  'reason': retReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Custody return recorded.');
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
      issueReasonCtrl,
      convDateCtrl,
      invSeriesCtrl,
      convPeriodCtrl,
      convJrnCtrl,
      convArticleCtrl,
      convReasonCtrl,
      retDateCtrl,
      retLocCtrl,
      retArticleCtrl,
      retReasonCtrl,
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
    bool isClosed(Map<String, dynamic> m) {
      final s = '${m['state'] ?? m['status'] ?? ''}'.toUpperCase();
      return s == 'CLOSED' || s == 'CONVERTED' || s == 'RETURNED';
    }

    bool isOverdue(Map<String, dynamic> m) {
      if (isClosed(m)) return false;
      final due = '${m['dueDate'] ?? ''}';
      if (due.isEmpty) return false;
      final dt = DateTime.tryParse(due);
      return dt != null && dt.isBefore(DateTime.now());
    }

    final openCnt = _memos.where((m) => !isClosed(m)).length;
    final overCnt = _memos.where(isOverdue).length;
    final closedCnt = _memos.where(isClosed).length;

    final filtered = _memos.where((m) {
      if (_filter == 'OPEN' && isClosed(m)) return false;
      if (_filter == 'OVERDUE' && !isOverdue(m)) return false;
      if (_filter == 'CLOSED' && !isClosed(m)) return false;
      if (q.isEmpty) return true;
      final hay =
          '${m['documentNumber'] ?? ''} ${m['memoNumber'] ?? ''} ${asMap(m['party'])['displayName'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    final roleFilter = _direction == 'CUSTOMER_OUTBOUND'
        ? const ['CUSTOMER', 'WHOLESALE']
        : const ['SUPPLIER', 'VENDOR', 'CONSIGNOR'];

    return LuxuryModuleScaffold(
      title: 'Approval & Consignment',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.verified_user_outlined,
      searchController: _search,
      searchHint: 'Search by Party / Memo No...',
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
          ('ALL', 'All (${_memos.length})'),
          ('OPEN', 'Open ($openCnt)'),
          ('OVERDUE', 'Overdue ($overCnt)'),
          ('CLOSED', 'Closed ($closedCnt)'),
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

            // Hero Header Card (`Approval & Consignment Memos` — image-26.png)
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
                        Icons.verified_user_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Approval & Consignment Memos',
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
                    'Ownership-safe customer approvals, supplier consignments, partial conversion, returns and overdue exposure.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // `New approval memo` card (exact fields from image-26.png)
            SaasFormCard(
              title: 'New approval memo',
              trailing: TextButton(
                onPressed: () => setState(() => _formExpanded = !_formExpanded),
                child: Text(_formExpanded ? 'Hide' : 'Show'),
              ),
              child: !_formExpanded
                  ? Text(
                      'Tap Show to create a customer approval or supplier consignment memo.',
                      style: T.body(12.2, color: Pal.muted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SaasDropdown(
                          label: 'Direction',
                          value: _direction,
                          options: const {
                            'CUSTOMER_OUTBOUND': 'Customer outbound approval',
                            'SUPPLIER_INBOUND':
                                'Supplier inbound consignment',
                          },
                          onChanged: (v) => setState(() {
                            _direction = v;
                            _partyId.clear();
                          }),
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Party',
                          controller: _partyId,
                          options: _lk.partiesByRole(roleFilter),
                          hint: 'Select...',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Custody location',
                          controller: _custodyLocationId,
                          options: _lk.locationsByType(
                            const [
                              'CUSTOMER_CUSTODY',
                              'EXTERNAL_CUSTODY',
                              'VAULT',
                            ],
                          ),
                          hint: 'Select...',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Memo series',
                          controller: _seriesId,
                          options: _lk.seriesFor(
                            const ['APPROVAL', 'MEMO', 'CONSIGNMENT'],
                          ),
                          hint: 'Select...',
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DatePickField(
                                label: 'Memo date',
                                controller: _memoDate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DatePickField(
                                label: 'Due date',
                                controller: _dueDate,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Currency',
                                controller: _currency,
                                mono: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: SaasField(
                                label: 'Terms',
                                controller: _terms,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SaasSubBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              LookupField(
                                label: 'Eligible article',
                                controller: _articleId,
                                options: _lk.articles,
                                hint: 'Select...',
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const FieldLabel('Taxable amount'),
                                        TextField(
                                          controller: _taxableAmt,
                                          style: T.mono(13.5),
                                          keyboardType: const TextInputType
                                              .numberWithOptions(decimal: true),
                                          onChanged: (v) {
                                            final t = tryDec(v);
                                            if (t != null) {
                                              _taxAmt.text = (t *
                                                      Decimal.parse('0.03'))
                                                  .toStringAsFixed(2);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: SaasField(
                                      label: 'Tax amount',
                                      controller: _taxAmt,
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
                                        '${_lines[i].articleLabel} · ₹${_lines[i].taxableAmount}',
                                        style: T.body(12.2, w: FontWeight.w600),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 17,
                                        color: Pal.err,
                                      ),
                                      onPressed: () =>
                                          setState(() => _lines.removeAt(i)),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        RoyalGoldButton(
                          label: 'Create memo',
                          busy: _busy,
                          onPressed: _busy ? null : _createMemo,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Panel(child: Skeleton(height: 92))
            else if (filtered.isEmpty)
              const SaasEmptyBox('No approval or consignment memos yet.')
            else
              for (final m in filtered)
                LuxuryRecordCard(
                  icon: Icons.verified_user_outlined,
                  code:
                      '${asMap(m['party'])['displayName'] ?? m['documentNumber'] ?? shortId('${m['id']}')}',
                  status: isOverdue(m)
                      ? 'OVERDUE'
                      : '${m['state'] ?? m['status'] ?? 'OPEN'}',
                  lines: [
                    (
                      'Memo No.',
                      '${m['documentNumber'] ?? m['memoNumber'] ?? shortId('${m['id']}')}',
                    ),
                    ('Direction', '${m['direction'] ?? 'CUSTOMER_OUTBOUND'}'),
                    (
                      'Date → Due',
                      '${fmtDate('${m['memoDate'] ?? ''}')} → ${fmtDate('${m['dueDate'] ?? ''}')}',
                    ),
                  ],
                  amountLabel: 'Value',
                  amountValue: inr(m['totalAmount'] ?? m['taxableAmount']),
                  actions: [
                    GoldButton(
                      label: 'Manage Memo',
                      compact: true,
                      onPressed: () => _openMemoLifecycleSheet(m),
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
// 4. WHOLESALE RATE FIXING (`/rate-fixing`) — `image-28.png`
// ---------------------------------------------------------------------------

class WholesaleRateFixingScreen extends StatefulWidget {
  const WholesaleRateFixingScreen({super.key});
  @override
  State<WholesaleRateFixingScreen> createState() =>
      _WholesaleRateFixingScreenState();
}

class _WholesaleRateFixingScreenState extends State<WholesaleRateFixingScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _formExpanded = true;
  List<Map<String, dynamic>> _contracts = [];
  Map<String, dynamic> _summary = {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Exact 15 fields from `image-28.png` (`New metal-denominated contract`)
  String _direction = 'CUSTOMER_SALE';
  final _partyId = TextEditingController();
  final _metalId = TextEditingController();
  final _purityId = TextEditingController();
  final _unitId = TextEditingController();
  final _seriesId = TextEditingController();
  final _contractDate = TextEditingController(text: todayIso());
  final _fixingDeadline = TextEditingController(text: todayIso());
  final _deliveryDeadline = TextEditingController(text: todayIso());
  final _contractQty = TextEditingController();
  final _exactFineGrams = TextEditingController();
  final _fineTolerance = TextEditingController(text: '0');
  final _settlementDueDays = TextEditingController(text: '7');
  final _currency = TextEditingController(text: 'INR');
  final _terms = TextEditingController();

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
      _metalId,
      _purityId,
      _unitId,
      _seriesId,
      _contractDate,
      _fixingDeadline,
      _deliveryDeadline,
      _contractQty,
      _exactFineGrams,
      _fineTolerance,
      _settlementDueDays,
      _currency,
      _terms,
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
        api.get('/rate-fixing'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
          includeMaterials: true,
        ),
      ]);
      if (!mounted) return;
      final m = asMap(res[0]);
      final lk = res[1] as WorkspaceLookup;
      if (_seriesId.text.isEmpty) {
        final s = lk.seriesFor(
          const ['RATE_FIXING', 'CONTRACT', 'WHOLESALE'],
        );
        if (s.isNotEmpty) _seriesId.text = s.first.id;
      }
      setState(() {
        _summary = asMap(m['summary']).isNotEmpty ? asMap(m['summary']) : m;
        _contracts = asList(
          res[0],
          keys: const ['contracts', 'rateFixingContracts', 'items'],
        );
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _recalcFine() {
    final qty = dParse(_contractQty.text);
    final purity =
        _lk.purities.where((p) => p.id == _purityId.text.trim()).firstOrNull;
    if (qty > Decimal.zero && purity != null) {
      final ppt = dParse(purity.raw['finenessPpt'] ?? purity.raw['fineness']);
      if (ppt > Decimal.zero) {
        final fine = (qty * ppt / Decimal.fromInt(1000)).toDecimal(
          scaleOnInfinitePrecision: 6,
        );
        _exactFineGrams.text = dStr6(fine);
      }
    }
  }

  Future<void> _createContract() async {
    if (_partyId.text.trim().isEmpty ||
        _metalId.text.trim().isEmpty ||
        _purityId.text.trim().isEmpty ||
        _unitId.text.trim().isEmpty ||
        _seriesId.text.trim().isEmpty ||
        _contractQty.text.trim().isEmpty ||
        _exactFineGrams.text.trim().isEmpty) {
      setState(
        () => _error =
            'Select Party, Metal, Purity, Contract unit, Document series, and enter Contract quantity & Exact fine grams.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/rate-fixing/contracts',
        idempotent: true,
        body: {
          'direction': _direction,
          'partyId': _partyId.text.trim(),
          'metalId': _metalId.text.trim(),
          'purityGradeId': _purityId.text.trim(),
          'unitId': _unitId.text.trim(),
          'documentSeriesId': _seriesId.text.trim(),
          'contractDate': _contractDate.text.trim(),
          'fixingDeadline': _fixingDeadline.text.trim(),
          'deliveryDeadline': _deliveryDeadline.text.trim(),
          'contractQuantity': normWeight6(_contractQty.text),
          'exactFineWeightGrams': normWeight6(_exactFineGrams.text),
          'fineToleranceGrams': normWeight6(
            _fineTolerance.text.trim().isEmpty ? '0' : _fineTolerance.text,
          ),
          'settlementDueDays':
              int.tryParse(_settlementDueDays.text.trim()) ?? 7,
          'currency': _currency.text.trim().toUpperCase(),
          if (_terms.text.trim().isNotEmpty)
            'commercialTerms': _terms.text.trim(),
        },
      );
      if (!mounted) return;
      _contractQty.clear();
      _exactFineGrams.clear();
      _terms.clear();
      toast(context, 'Draft metal-denominated contract created.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openContractLifecycleSheet(Map<String, dynamic> c) async {
    final rates = context.read<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');

    var actionTab = 'APPROVE';
    final approveReasonCtrl = TextEditingController();

    final fixDateCtrl = TextEditingController(text: todayIso());
    final fixFineCtrl = TextEditingController(
      text: '${c['unfixedFineWeightGrams'] ?? c['exactFineWeightGrams'] ?? ''}',
    );
    final fixRateCtrl = TextEditingController(
      text: gold999 != null ? gold999.sell.toStringAsFixed(2) : '',
    );
    final fixRefCtrl = TextEditingController();
    final fixNotesCtrl = TextEditingController();

    final delDateCtrl = TextEditingController(text: todayIso());
    final delLocCtrl = TextEditingController(
      text: _lk.locations.isNotEmpty ? _lk.locations.first.id : '',
    );
    final delBalCtrl = TextEditingController();
    final delQtyCtrl = TextEditingController(
      text: '${c['contractQuantity'] ?? ''}',
    );
    final delFineCtrl = TextEditingController(
      text:
          '${c['undeliveredFineWeightGrams'] ?? c['exactFineWeightGrams'] ?? ''}',
    );
    final delEvidenceCtrl = TextEditingController();

    final setDateCtrl = TextEditingController(text: todayIso());
    final setAmtCtrl = TextEditingController(
      text: '${c['unsettledMatchedValue'] ?? c['matchedValue'] ?? ''}',
    );
    final setPeriodCtrl = TextEditingController(
      text: _lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : '',
    );
    final setJrnCtrl = TextEditingController(
      text: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? _lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
    final setPartyAcctCtrl = TextEditingController();
    final setOffsetAcctCtrl = TextEditingController();
    final setReasonCtrl = TextEditingController();

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
                        'Manage Contract · ${c['documentNumber'] ?? c['contractNumber'] ?? shortId('${c['id']}')}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${c['state'] ?? c['status'] ?? 'DRAFT'}'),
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
                    ('APPROVE', 'Approve'),
                    ('FIX', 'Fix Rate'),
                    ('DELIVER', 'Physical Delivery'),
                    ('SETTLE', 'GL Settlement'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (actionTab == 'APPROVE') ...[
                  SaasField(
                    label: 'Contract approval note / commercial sign-off',
                    controller: approveReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Approve & Activate Contract',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/rate-fixing/contracts/${c['id']}/approve',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(c['version'], fallback: 1),
                                  if (approveReasonCtrl.text.trim().isNotEmpty)
                                    'reason': approveReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Metal contract approved.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (actionTab == 'FIX') ...[
                  DatePickField(
                    label: 'Fixing date',
                    controller: fixDateCtrl,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Fixed fine wt g',
                          controller: fixFineCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Rate / fine gram (INR)',
                          controller: fixRateCtrl,
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
                    label: 'Board / counterparty deal ref',
                    controller: fixRefCtrl,
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Fixing notes (optional)',
                    controller: fixNotesCtrl,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Record Rate Fixing Tranche',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (!isValidWeight(fixFineCtrl.text) ||
                                !isValidAmount(fixRateCtrl.text)) {
                              setSheet(
                                () => sheetErr =
                                    'Enter valid fixed fine grams and rate per fine gram.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/rate-fixing/contracts/${c['id']}/fixings',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(c['version'], fallback: 1),
                                  'fixingDate': fixDateCtrl.text.trim(),
                                  'fixedFineWeightGrams':
                                      normWeight6(fixFineCtrl.text),
                                  'agreedRatePerFineGram':
                                      normAmount(fixRateCtrl.text),
                                  if (fixRefCtrl.text.trim().isNotEmpty)
                                    'rateReference': fixRefCtrl.text.trim(),
                                  if (fixNotesCtrl.text.trim().isNotEmpty)
                                    'notes': fixNotesCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Rate fixing tranche recorded.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (actionTab == 'DELIVER') ...[
                  DatePickField(
                    label: 'Physical delivery date',
                    controller: delDateCtrl,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Vault / custody location',
                    controller: delLocCtrl,
                    options: _lk.locations,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Lot balance UUID (optional)',
                    controller: delBalCtrl,
                    options: _lk.lotBalances,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Delivered quantity',
                          controller: delQtyCtrl,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Delivered fine wt g',
                          controller: delFineCtrl,
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
                    label: 'Delivery challan / assay evidence ref',
                    controller: delEvidenceCtrl,
                    mono: true,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Record Evidenced Physical Delivery',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (delLocCtrl.text.trim().isEmpty ||
                                !isValidWeight(delFineCtrl.text)) {
                              setSheet(
                                () => sheetErr =
                                    'Select custody location and enter delivered fine grams.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/rate-fixing/contracts/${c['id']}/deliveries',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(c['version'], fallback: 1),
                                  'deliveryDate': delDateCtrl.text.trim(),
                                  'locationId': delLocCtrl.text.trim(),
                                  if (delBalCtrl.text.trim().isNotEmpty)
                                    'balanceId': delBalCtrl.text.trim(),
                                  if (delQtyCtrl.text.trim().isNotEmpty)
                                    'deliveredQuantity':
                                        normWeight6(delQtyCtrl.text),
                                  'deliveredFineWeightGrams':
                                      normWeight6(delFineCtrl.text),
                                  if (delEvidenceCtrl.text.trim().isNotEmpty)
                                    'evidenceReference':
                                        delEvidenceCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(
                                context,
                                'Evidenced physical delivery recorded.',
                              );
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  DatePickField(
                    label: 'Settlement date',
                    controller: setDateCtrl,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Matched settlement amount (INR)',
                    controller: setAmtCtrl,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Posting Period UUID',
                    controller: setPeriodCtrl,
                    options: _lk.openPeriods(),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Journal Series UUID',
                    controller: setJrnCtrl,
                    options: _lk.seriesFor(const ['JOURNAL']),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'AR / AP Control Account UUID (optional)',
                    controller: setPartyAcctCtrl,
                    options: _lk.accountsByType(const ['ASSET', 'LIABILITY']),
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Revenue / Bullion Inventory Account (optional)',
                    controller: setOffsetAcctCtrl,
                    options: _lk.accounts,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Settlement audit reason (min 10 chars)',
                    controller: setReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Post GL-Backed Settlement Reconciliation',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (setPeriodCtrl.text.trim().isEmpty ||
                                setJrnCtrl.text.trim().isEmpty ||
                                setReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select Posting Period & Journal Series and enter a reason of at least 10 characters.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/rate-fixing/contracts/${c['id']}/settle',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(c['version'], fallback: 1),
                                  'settlementDate': setDateCtrl.text.trim(),
                                  if (setAmtCtrl.text.trim().isNotEmpty)
                                    'settledAmount':
                                        normAmount(setAmtCtrl.text),
                                  'postingPeriodId': setPeriodCtrl.text.trim(),
                                  'journalSeriesId': setJrnCtrl.text.trim(),
                                  if (setPartyAcctCtrl.text.trim().isNotEmpty)
                                    'partyControlAccountId':
                                        setPartyAcctCtrl.text.trim(),
                                  if (setOffsetAcctCtrl.text.trim().isNotEmpty)
                                    'offsetAccountId':
                                        setOffsetAcctCtrl.text.trim(),
                                  'reason': setReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(
                                context,
                                'Contract GL settlement reconciled.',
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

    for (final ctrl in [
      approveReasonCtrl,
      fixDateCtrl,
      fixFineCtrl,
      fixRateCtrl,
      fixRefCtrl,
      fixNotesCtrl,
      delDateCtrl,
      delLocCtrl,
      delBalCtrl,
      delQtyCtrl,
      delFineCtrl,
      delEvidenceCtrl,
      setDateCtrl,
      setAmtCtrl,
      setPeriodCtrl,
      setJrnCtrl,
      setPartyAcctCtrl,
      setOffsetAcctCtrl,
      setReasonCtrl,
    ]) {
      ctrl.dispose();
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
    bool isSettled(Map<String, dynamic> c) {
      final s = '${c['state'] ?? c['status'] ?? ''}'.toUpperCase();
      return s == 'SETTLED' || s == 'CLOSED' || s == 'COMPLETED';
    }

    final activeCnt = _contracts.where((c) => !isSettled(c)).length;
    final settledCnt = _contracts.where(isSettled).length;
    final filtered = _contracts.where((c) {
      if (_filter == 'ACTIVE' && isSettled(c)) return false;
      if (_filter == 'SETTLED' && !isSettled(c)) return false;
      if (q.isEmpty) return true;
      final hay =
          '${c['documentNumber'] ?? ''} ${c['contractNumber'] ?? ''} ${asMap(c['party'])['displayName'] ?? ''}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    final unfixedFine = dParse(
      _summary['unfixedFineExposureGrams'] ??
          _summary['unfixedFineGrams'] ??
          '0',
    );
    final undeliveredFine = dParse(
      _summary['undeliveredFineGrams'] ?? '0',
    );
    final unsettledVal =
        _summary['unsettledMatchedValue'] ?? _summary['unsettledAmount'] ?? 0;

    final roleFilter = _direction == 'CUSTOMER_SALE'
        ? const ['CUSTOMER', 'WHOLESALE']
        : const ['SUPPLIER', 'VENDOR', 'BULLION_DEALER'];

    return LuxuryModuleScaffold(
      title: 'Wholesale Rate Fixing',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.monetization_on_outlined,
      searchController: _search,
      searchHint: 'Search by Party / Contract No...',
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
          ('ALL', 'All (${_contracts.length})'),
          ('ACTIVE', 'Active ($activeCnt)'),
          ('SETTLED', 'Settled ($settledCnt)'),
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

            // Hero Header Card (`Wholesale Rate Fixing` — image-28.png)
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
                        Icons.monetization_on_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Wholesale Rate Fixing',
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
                    'Metal-denominated sale and purchase contracts with partial fixing, independently evidenced physical delivery and GL-backed settlement reconciliation.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Exact 4 KPI Cards from `image-28.png`
            SaasKpiGrid(
              items: [
                (
                  'ACTIVE CONTRACTS',
                  '${_summary['activeContracts'] ?? activeCnt}',
                ),
                ('UNFIXED FINE EXPOSURE', '${dStr6(unfixedFine)} g'),
                ('UNDELIVERED FINE', '${dStr6(undeliveredFine)} g'),
                ('UNSETTLED MATCHED VALUE', inr(unsettledVal)),
              ],
            ),

            const SizedBox(height: 12),

            // `New metal-denominated contract` card (exact 15 fields from image-28.png)
            SaasFormCard(
              title: 'New metal-denominated contract',
              trailing: TextButton(
                onPressed: () => setState(() => _formExpanded = !_formExpanded),
                child: Text(_formExpanded ? 'Hide' : 'Show'),
              ),
              child: !_formExpanded
                  ? Text(
                      'Tap Show to create a draft metal-denominated contract.',
                      style: T.body(12.2, color: Pal.muted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SaasDropdown(
                          label: 'Direction',
                          value: _direction,
                          options: const {
                            'CUSTOMER_SALE': 'Wholesale customer sale',
                            'SUPPLIER_PURCHASE': 'Bullion supplier purchase',
                          },
                          onChanged: (v) => setState(() {
                            _direction = v;
                            _partyId.clear();
                          }),
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Party',
                          controller: _partyId,
                          options: _lk.partiesByRole(roleFilter),
                          hint: 'Select...',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Metal',
                          controller: _metalId,
                          options: _lk.metals,
                          hint: 'Select...',
                          onSelected: (_) =>
                              setState(() => _purityId.clear()),
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Purity / agreed fineness',
                          controller: _purityId,
                          options: _lk.puritiesForMetal(
                            _metalId.text.trim().isEmpty
                                ? null
                                : _metalId.text.trim(),
                          ),
                          hint: 'Select...',
                          onSelected: (_) => setState(_recalcFine),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: LookupField(
                                label: 'Contract unit',
                                controller: _unitId,
                                options: _lk.units,
                                hint: 'Select...',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LookupField(
                                label: 'Document series',
                                controller: _seriesId,
                                options: _lk.seriesFor(
                                  const [
                                    'RATE_FIXING',
                                    'CONTRACT',
                                    'WHOLESALE',
                                  ],
                                ),
                                hint: 'Select...',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DatePickField(
                          label: 'Contract date',
                          controller: _contractDate,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DatePickField(
                                label: 'Fixing deadline',
                                controller: _fixingDeadline,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DatePickField(
                                label: 'Delivery deadline',
                                controller: _deliveryDeadline,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const FieldLabel('Contract quantity'),
                                  TextField(
                                    controller: _contractQty,
                                    style: T.mono(13.5),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    onChanged: (_) => setState(_recalcFine),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'Exact fine grams',
                                controller: _exactFineGrams,
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
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Fine tolerance grams',
                                controller: _fineTolerance,
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
                                label: 'Settlement due days',
                                controller: _settlementDueDays,
                                mono: true,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'Currency',
                                controller: _currency,
                                mono: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SaasField(
                          label: 'Commercial terms',
                          controller: _terms,
                        ),
                        const SizedBox(height: 14),
                        RoyalGoldButton(
                          label: 'Create draft contract',
                          busy: _busy,
                          onPressed: _busy ? null : _createContract,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Panel(child: Skeleton(height: 92))
            else if (filtered.isEmpty)
              const SaasEmptyBox('No wholesale metal contracts yet.')
            else
              for (final c in filtered)
                LuxuryRecordCard(
                  icon: Icons.monetization_on_outlined,
                  code:
                      '${asMap(c['party'])['displayName'] ?? c['documentNumber'] ?? shortId('${c['id']}')}',
                  status: '${c['state'] ?? c['status'] ?? 'DRAFT'}',
                  lines: [
                    (
                      'Contract No.',
                      '${c['documentNumber'] ?? c['contractNumber'] ?? shortId('${c['id']}')}',
                    ),
                    ('Direction', '${c['direction'] ?? 'CUSTOMER_SALE'}'),
                    (
                      'Exact Fine Wt',
                      '${grams(c['exactFineWeightGrams'] ?? c['fineWeightGrams'])} g',
                    ),
                    (
                      'Fixing / Delivery',
                      '${fmtDate('${c['fixingDeadline'] ?? ''}')} / ${fmtDate('${c['deliveryDeadline'] ?? ''}')}',
                    ),
                  ],
                  amountLabel: 'Matched Value',
                  amountValue: inr(c['matchedValue'] ?? c['totalAmount']),
                  actions: [
                    GoldButton(
                      label: 'Manage Contract',
                      compact: true,
                      onPressed: () => _openContractLifecycleSheet(c),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

typedef ApprovalMemosScreen = ApprovalConsignmentScreen;
typedef RateFixingScreen = WholesaleRateFixingScreen;
