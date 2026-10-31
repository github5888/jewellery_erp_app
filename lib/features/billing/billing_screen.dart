import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../customers/customers_screen.dart';
import '../inventory/scanner_page.dart';
import '../more/old_gold_screen.dart';
import '../more/shift_screen.dart';
import '../supply/supply_production_screens.dart';
import 'billing_controller.dart';

/// Sales & POS Billing (`pos.hrpocket.in/sales` — `image-4.png`) formatted
/// cleanly for mobile phones and wired to live `/sales`, `/custom-orders`,
/// `/rates`, `/inventory`, and `/accounting/workspace` endpoints.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _barcode = TextEditingController();
  final _regSearch = TextEditingController();

  // 'INVOICES' | 'ESTIMATES' | 'ORDERS' | 'CREDITS' | 'TAX_PROFILES' | 'POS'
  String _tab = 'INVOICES';
  int _lastSeenCartCount = 0;

  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _estimates = [];
  List<Map<String, dynamic>> _ordersAndDispatch = [];
  List<Map<String, dynamic>> _credits = [];
  List<Map<String, dynamic>> _taxProfiles = [];
  List<LookupOption> _rateVersionOpts = [];
  WorkspaceLookup _lk = WorkspaceLookup();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _activeForm; // null | 'INVOICE' | 'ESTIMATE' | 'CN' | 'TAX'

  // Controlled Sales Posting Config (auto-discovered from `/accounting/workspace`)
  final _periodId = TextEditingController();
  final _invSeriesId = TextEditingController();
  final _cnSeriesId = TextEditingController();
  final _jvSeriesId = TextEditingController();
  final _recvAcctId = TextEditingController();
  final _revAcctId = TextEditingController();
  final _taxAcctId = TextEditingController();
  final _cogsAcctId = TextEditingController();
  final _invAcctId = TextEditingController();

  // Create Standalone Estimate (`POST /sales/estimates`)
  final _qCustomerId = TextEditingController();
  final _qRateVerId = TextEditingController();
  final _qTaxProfId = TextEditingController();
  final _qDate = TextEditingController(text: todayIso());
  final _qArticleId = TextEditingController();
  final _qMaking = TextEditingController(text: '0.00');
  final _qDiscount = TextEditingController(text: '0.00');

  // Convert Estimate -> Sales Invoice (`POST /sales/invoices`)
  final _estId = TextEditingController();
  final _invDate = TextEditingController(text: todayIso());

  // Create Credit Note / Return QC (`POST /sales/credit-notes`)
  final _cnInvId = TextEditingController();
  final _cnLineId = TextEditingController();
  final _cnDate = TextEditingController(text: todayIso());
  final _cnReason = TextEditingController();
  final _cnLineReason = TextEditingController();
  String _cnQcState = 'PASSED';
  String _cnDisposition = 'RESTOCK';
  final _cnRestockLocId = TextEditingController();

  // Create GST Tax Profile (`POST /sales/tax-profiles`)
  final _tpCode = TextEditingController();
  final _tpName = TextEditingController();
  final _tpRate = TextEditingController(text: '3');
  final _tpEffFrom = TextEditingController(text: todayIso());
  bool _tpSynthetic = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cartLen = context.read<BillingController>().lines.length;
      _lastSeenCartCount = cartLen;
      if (cartLen > 0) {
        setState(() => _tab = 'POS');
      }
      _loadSalesWorkspace();
    });
  }

  @override
  void dispose() {
    for (final c in [
      _barcode,
      _regSearch,
      _periodId,
      _invSeriesId,
      _cnSeriesId,
      _jvSeriesId,
      _recvAcctId,
      _revAcctId,
      _taxAcctId,
      _cogsAcctId,
      _invAcctId,
      _qCustomerId,
      _qRateVerId,
      _qTaxProfId,
      _qDate,
      _qArticleId,
      _qMaking,
      _qDiscount,
      _estId,
      _invDate,
      _cnInvId,
      _cnLineId,
      _cnDate,
      _cnReason,
      _cnLineReason,
      _cnRestockLocId,
      _tpCode,
      _tpName,
      _tpRate,
      _tpEffFrom,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSalesWorkspace() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait<dynamic>([
        api.get('/sales'),
        api.get('/custom-orders').catchError((_) => <String, dynamic>{}),
        api.get('/rates').catchError((_) => <String, dynamic>{}),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;

      final d = asMap(results[0]);
      final coRaw = results[1];
      final ratesRaw = results[2];
      final lk = results[3] as WorkspaceLookup;

      final invoices = asList(d, keys: const ['invoices', 'salesInvoices']);
      final estimates = asList(d, keys: const ['estimates']);
      final credits = asList(d, keys: const ['creditNotes']);
      final taxProfiles = asList(d, keys: const ['taxProfiles']);

      // Merge Orders & Dispatch from `/sales` + `/custom-orders`
      final salesOrders = asList(
        d,
        keys: const ['orders', 'salesOrders', 'dispatches', 'deliveryChallans'],
      );
      final customOrders = asList(
        coRaw,
        keys: const ['orders', 'customOrders', 'items'],
      );
      final seenOrders = <String>{};
      final mergedOrders = <Map<String, dynamic>>[];
      for (final o in [...salesOrders, ...customOrders]) {
        final id = '${o['id'] ?? o['documentNumber'] ?? o['orderNumber'] ?? mergedOrders.length}';
        if (seenOrders.add(id)) mergedOrders.add(o);
      }

      // Published Rate Versions for standalone Estimate builder
      final rvOpts = <LookupOption>[];
      for (final book in asList(ratesRaw, keys: const ['rateBooks', 'books', 'items'])) {
        final bookName = '${book['name'] ?? book['code'] ?? 'Rate Book'}';
        for (final v in asList(book['versions'])) {
          if ('${v['state']}' == 'PUBLISHED') {
            final vid = '${v['id'] ?? ''}';
            if (vid.isNotEmpty) {
              rvOpts.add(
                LookupOption(
                  id: vid,
                  label: '$bookName · v${v['versionNumber'] ?? 1} (PUBLISHED)',
                  raw: v,
                ),
              );
            }
          }
        }
      }

      // Auto-populate controlled GL posting & series defaults
      if (_periodId.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _periodId.text = lk.openPeriods().first.id;
      }
      if (_jvSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['JOURNAL']);
        if (s.isNotEmpty) _jvSeriesId.text = s.first.id;
      }
      if (_invSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['SALES_INVOICE', 'INVOICE']);
        if (s.isNotEmpty) _invSeriesId.text = s.first.id;
      }
      if (_cnSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['CREDIT_NOTE', 'RETURN']);
        if (s.isNotEmpty) _cnSeriesId.text = s.first.id;
      }
      if (_recvAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['CUSTOMER_RECEIVABLE']);
        if (a.isNotEmpty) _recvAcctId.text = a.first.id;
      }
      if (_revAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['INCOME']);
        if (a.isNotEmpty) _revAcctId.text = a.first.id;
      }
      if (_taxAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['TAX_OUTPUT']);
        if (a.isNotEmpty) _taxAcctId.text = a.first.id;
      }
      if (_cogsAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['EXPENSE']);
        if (a.isNotEmpty) _cogsAcctId.text = a.first.id;
      }
      if (_invAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['INVENTORY']);
        if (a.isNotEmpty) _invAcctId.text = a.first.id;
      }
      if (_qRateVerId.text.isEmpty && rvOpts.isNotEmpty) {
        _qRateVerId.text = rvOpts.first.id;
      }
      final approvedTax = taxProfiles.where((t) => '${t['state']}' == 'APPROVED').firstOrNull;
      if (_qTaxProfId.text.isEmpty && approvedTax != null) {
        _qTaxProfId.text = '${approvedTax['id']}';
      }

      setState(() {
        _invoices = invoices;
        _estimates = estimates;
        _ordersAndDispatch = mergedOrders;
        _credits = credits;
        _taxProfiles = taxProfiles;
        _rateVersionOpts = rvOpts;
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mutate(Future<void> Function(ApiClient api) fn, String msg) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn(context.read<ApiClient>());
      if (!mounted) return;
      setState(() => _activeForm = null);
      toast(context, msg);
      await _loadSalesWorkspace();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPosQuickBill() {
    setState(() {
      _activeForm = null;
      _tab = 'POS';
    });
  }

  Future<void> _scan(BillingController c) async {
    final v = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (v != null) c.scanAndAdd(v);
  }

  Future<void> _editMaking(BillingController c, int index) async {
    final line = c.lines[index];
    final ctrl = TextEditingController(text: line.makingCharge);
    final updated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Making Charges · ${line.article.barcode}', style: T.display(20)),
            const SizedBox(height: 6),
            Text(
              'Metal value: ${inr(line.metalValue.toStringAsFixed(2))} (${grams(line.article.effectiveNetWeight)} @ ${rate(line.ratePerGram)})',
              style: T.body(12.5, color: Pal.muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final pctVal in const [8, 12, 16, 20])
                  ActionChip(
                    label: Text('$pctVal%'),
                    backgroundColor: Pal.goldWash,
                    onPressed: () {
                      final mc = (line.metalValue *
                              Decimal.fromInt(pctVal) /
                              Decimal.fromInt(100))
                          .toDecimal(scaleOnInfinitePrecision: 6)
                          .round(scale: 2);
                      ctrl.text = mc.toStringAsFixed(2);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const FieldLabel('Making Charge (INR)'),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(16, w: FontWeight.w700),
              decoration: const InputDecoration(prefixText: '₹ '),
            ),
            const SizedBox(height: 16),
            RoyalGoldButton(
              label: 'Update Line Making Charge',
              onPressed: () => Navigator.pop(ctx, ctrl.text),
            ),
          ],
        ),
      ),
    );
    if (updated != null &&
        (isValidAmount(updated) || updated == '0' || updated == '0.00')) {
      c.updateMakingCharge(index, updated);
    }
  }

  Future<void> _addPayment(BillingController c) async {
    String mode = 'UPI';
    final rem = c.remainingBalanceDecimal;
    final amt = TextEditingController(
      text: rem > Decimal.zero ? rem.toStringAsFixed(2) : '',
    );
    final ref = TextEditingController();
    final res = await showModalBottomSheet<PayEntry>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Record Payment Tender', style: T.display(22)),
              const SizedBox(height: 14),
              const FieldLabel('Payment Mode'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in const [
                    ('UPI', 'UPI QR'),
                    ('CARD', 'Card POS'),
                    ('CASH', 'Cash'),
                    ('BANK_TRANSFER', 'RTGS / NEFT'),
                  ])
                    ChoiceChip(
                      label: Text(m.$2),
                      selected: mode == m.$1,
                      showCheckmark: false,
                      selectedColor: Pal.goldWash,
                      onSelected: (_) => setLocal(() => mode = m.$1),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const FieldLabel('Tender Amount (INR)'),
              TextField(
                controller: amt,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: T.mono(18, w: FontWeight.w700),
                decoration: const InputDecoration(prefixText: '₹ ', hintText: '0.00'),
              ),
              if (mode != 'CASH') ...[
                const SizedBox(height: 12),
                const FieldLabel('UTR / RRN / Auth Reference (Optional)'),
                TextField(
                  controller: ref,
                  style: T.mono(14),
                  decoration: const InputDecoration(hintText: 'Transaction / UTR reference'),
                ),
              ],
              const SizedBox(height: 18),
              RoyalGoldButton(
                label: 'Add Payment Split',
                onPressed: () {
                  if (!isValidAmount(amt.text)) return;
                  Navigator.pop(
                    ctx,
                    PayEntry(mode, normAmount(amt.text), reference: ref.text.trim()),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (res != null) c.addPayment(res.mode, res.amount, reference: res.reference);
  }

  Future<void> _checkout(BillingController c) async {
    final receipt = await c.checkout();
    if (receipt == null || !mounted) return;
    await _loadSalesWorkspace();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InvoiceReceiptSheet(receipt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BillingController>();
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();

    // Automatically jump to POS Quick Bill when an item is added from Vault
    if (c.lines.length > _lastSeenCartCount && _tab != 'POS') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _tab = 'POS');
      });
    }
    _lastSeenCartCount = c.lines.length;

    final isPosTab = _tab == 'POS';
    final gold999 = rates.find('GOLD', '999');
    final bullionActive = gold999 != null && decOrZero(gold999.sell) > Decimal.zero;
    final showroomContext = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    return LuxuryModuleScaffold(
      title: 'Sales & POS Billing',
      icon: Icons.receipt_long_rounded,
      searchController: isPosTab ? null : _regSearch,
      searchHint: 'Search Doc #, Quote #, Customer or State...',
      onSearchChanged: isPosTab ? null : (_) => setState(() {}),
      actions: [
        if (!isPosTab) ...[
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openPosQuickBill,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFDAB046), Color(0xFFB38620)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'POS Quick Bill',
                      style: T.body(11.8, color: Colors.white, w: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Refresh sales register',
            onPressed: _loadSalesWorkspace,
            icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
          ),
        ] else ...[
          IconButton(
            tooltip: 'Counter POS Shifts',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ShiftScreen()),
            ),
            icon: const Icon(Icons.payments_outlined, color: Pal.goldSoft),
          ),
          if (c.lines.isNotEmpty ||
              c.customer != null ||
              c.payments.isNotEmpty ||
              c.oldGold != null)
            TextButton.icon(
              onPressed: c.busy ? null : c.clear,
              icon: const Icon(Icons.restart_alt_rounded, size: 17, color: Pal.goldSoft),
              label: Text(
                'Reset',
                style: T.body(12.2, color: Pal.goldSoft, w: FontWeight.w700),
              ),
            ),
        ],
      ],
      topFilterBar: PillTabs<String>(
        selected: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _activeForm = null;
        }),
        items: [
          (
            'INVOICES',
            'Sales Invoices (${_invoices.length})',
            Icons.receipt_long_outlined,
          ),
          (
            'ESTIMATES',
            'Estimates (${_estimates.length})',
            Icons.request_quote_outlined,
          ),
          (
            'ORDERS',
            'Orders & Dispatch (${_ordersAndDispatch.length})',
            Icons.local_shipping_outlined,
          ),
          (
            'CREDITS',
            'Credit Notes (${_credits.length})',
            Icons.assignment_return_outlined,
          ),
          (
            'TAX_PROFILES',
            'Tax Profiles (${_taxProfiles.length})',
            Icons.percent_rounded,
          ),
          (
            'POS',
            c.lines.isEmpty ? 'POS Quick Bill' : 'POS Quick Bill (${c.lines.length})',
            Icons.auto_awesome_rounded,
          ),
        ],
      ),
      body: isPosTab
          ? _buildPosQuickBill(c, bullionActive)
          : _buildRegisterBody(bullionActive, showroomContext),
    );
  }

  /// Register Workspace matching `image-4.png` (`Retail Sales and Customer Returns`).
  Widget _buildRegisterBody(bool bullionActive, String showroomContext) {
    final q = _regSearch.text.trim().toLowerCase();

    final fInvoices = _invoices.where((inv) {
      if (q.isEmpty) return true;
      return '${inv['documentNumber'] ?? ''} ${asMap(inv['customer'])['displayName'] ?? ''} ${inv['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fEstimates = _estimates.where((est) {
      if (q.isEmpty) return true;
      return '${est['quoteNumber'] ?? ''} ${asMap(est['customer'])['displayName'] ?? ''} ${est['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fOrders = _ordersAndDispatch.where((ord) {
      if (q.isEmpty) return true;
      return '${ord['documentNumber'] ?? ord['orderNumber'] ?? ''} ${asMap(ord['customer'])['displayName'] ?? ''} ${ord['description'] ?? ''} ${ord['state'] ?? ord['status'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fCredits = _credits.where((cn) {
      if (q.isEmpty) return true;
      return '${cn['documentNumber'] ?? ''} ${asMap(cn['customer'])['displayName'] ?? ''} ${cn['reason'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fTax = _taxProfiles.where((tp) {
      if (q.isEmpty) return true;
      return '${tp['code'] ?? ''} ${tp['name'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    final estOpts = _estimates
        .map(
          (e) => LookupOption(
            id: '${e['id']}',
            label:
                '${e['quoteNumber'] ?? shortId('${e['id']}')} · ${asMap(e['customer'])['displayName'] ?? 'Customer'} · ${inr(e['totalAmount'])}',
            raw: e,
          ),
        )
        .toList();

    final invOpts = _invoices
        .map(
          (inv) => LookupOption(
            id: '${inv['id']}',
            label:
                '${inv['documentNumber'] ?? shortId('${inv['id']}')} · ${asMap(inv['customer'])['displayName'] ?? 'Customer'} · ${inr(inv['totalAmount'])}',
            raw: inv,
          ),
        )
        .toList();

    final taxOpts = _taxProfiles
        .where((tp) => '${tp['state']}' == 'APPROVED')
        .map(
          (tp) => LookupOption(
            id: '${tp['id']}',
            label: '${tp['code']} · ${tp['name']} (${tp['ratePercent']}%)',
            raw: tp,
          ),
        )
        .toList();

    final availArticles = _lk.articles
        .where((a) {
          final av = '${asMap(a.raw['balance'])['availability'] ?? a.raw['status'] ?? 'AVAILABLE'}'
              .toUpperCase();
          return av == 'AVAILABLE' || av == 'IN_STOCK' || av.isEmpty;
        })
        .toList();

    final selectedCnInvoice =
        _invoices.where((i) => '${i['id']}' == _cnInvId.text.trim()).firstOrNull;
    final cnLineOpts = asList(selectedCnInvoice?['lines']).map((ln) {
      final lid = '${ln['id'] ?? ''}';
      final art = asMap(ln['article']);
      final tag = '${art['tag'] ?? art['barcode'] ?? shortId(lid)}';
      return LookupOption(
        id: lid,
        label: '$tag · ${art['description'] ?? 'Line'} · ${inr(ln['lineTotal'] ?? ln['taxableAmount'] ?? '0.00')}',
        raw: ln,
      );
    }).where((o) => o.id.isNotEmpty).toList();

    return Stack(
      children: [
        RefreshIndicator(
          color: Pal.gold,
          onRefresh: _loadSalesWorkspace,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 92),
            children: [
              // Website Sub-Header (`Retail Sales and Customer Returns` + `Bullion 24K: Fine 999 Board Active` from `image-4.png`)
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
                            color: const Color(0xFFFBF3DC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE7CF8B)),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
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
                                'Retail Sales and Customer Returns',
                                style: T.body(15.8, color: Pal.ink, w: FontWeight.w800),
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
                      'Authoritative estimates, tagged invoices with one-article-one-sale reservation, and credit notes with return QC.',
                      style: T.body(12.2, color: Pal.muted),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5.5,
                            ),
                            decoration: BoxDecoration(
                              color: bullionActive
                                  ? const Color(0xFFFBF3DC)
                                  : Pal.warnWash,
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
                        InkWell(
                          borderRadius: BorderRadius.circular(99),
                          onTap: _openPosQuickBill,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5.5,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFDAB046), Color(0xFFB38620)],
                              ),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 13.5,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'POS Quick Bill',
                                  style: T.body(
                                    11.5,
                                    color: Colors.white,
                                    w: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                ErrorBanner(_error!, onRetry: _loadSalesWorkspace),
              ],

              // Inline Action Forms
              if (_activeForm == 'INVOICE') ...[
                const SizedBox(height: 12),
                SaasFormCard(
                  title: 'Create Sales Invoice from Estimate',
                  trailing: TextButton(
                    onPressed: () => setState(() => _activeForm = null),
                    child: const Text('Close'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LookupField(
                        label: 'Approved / Open Estimate',
                        controller: _estId,
                        options: estOpts,
                      ),
                      const SizedBox(height: 10),
                      DatePickField(label: 'Invoice Date', controller: _invDate),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Customer Receivable Account',
                        controller: _recvAcctId,
                        options: _lk.accounts,
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Sales Revenue Account',
                        controller: _revAcctId,
                        options: _lk.accounts,
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Output GST Account (optional)',
                        controller: _taxAcctId,
                        options: _lk.accounts,
                        optional: true,
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'COGS Account',
                        controller: _cogsAcctId,
                        options: _lk.accounts,
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Inventory Asset Account',
                        controller: _invAcctId,
                        options: _lk.accounts,
                      ),
                      const SizedBox(height: 12),
                      GoldButton(
                        label: 'Create Sales Invoice',
                        busy: _busy,
                        onPressed: () => _mutate(
                          (api) => api.post('/sales/invoices', idempotent: true, body: {
                            'estimateId': _estId.text.trim(),
                            'invoiceDate': _invDate.text.trim(),
                            'reservationExpiresAt': DateTime.now()
                                .toUtc()
                                .add(const Duration(hours: 4))
                                .toIso8601String(),
                            'receivableAccountId': _recvAcctId.text.trim(),
                            'revenueAccountId': _revAcctId.text.trim(),
                            if (_taxAcctId.text.trim().isNotEmpty)
                              'outputTaxAccountId': _taxAcctId.text.trim(),
                            'cogsAccountId': _cogsAcctId.text.trim(),
                            'inventoryAccountId': _invAcctId.text.trim(),
                          }),
                          'Draft sales invoice created.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_activeForm == 'ESTIMATE') ...[
                const SizedBox(height: 12),
                SaasFormCard(
                  title: 'New Showroom Sales Estimate',
                  trailing: TextButton(
                    onPressed: () => setState(() => _activeForm = null),
                    child: const Text('Close'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LookupField(
                        label: 'Customer',
                        controller: _qCustomerId,
                        options: _lk.parties,
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Published Bullion Rate Version',
                        controller: _qRateVerId,
                        options: _rateVersionOpts,
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Approved GST Tax Profile',
                        controller: _qTaxProfId,
                        options: taxOpts,
                      ),
                      const SizedBox(height: 10),
                      DatePickField(label: 'Quote Date', controller: _qDate),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Tagged Article',
                        controller: _qArticleId,
                        options: availArticles.isNotEmpty ? availArticles : _lk.articles,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SaasField(
                              label: 'Making (INR)',
                              controller: _qMaking,
                              mono: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SaasField(
                              label: 'Discount (INR)',
                              controller: _qDiscount,
                              mono: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GoldButton(
                        label: 'Generate Authoritative Estimate',
                        busy: _busy,
                        onPressed: () => _mutate(
                          (api) => api.post('/sales/estimates', idempotent: true, body: {
                            'customerPartyId': _qCustomerId.text.trim(),
                            'rateVersionId': _qRateVerId.text.trim(),
                            'taxProfileId': _qTaxProfId.text.trim(),
                            'quoteDate': _qDate.text.trim(),
                            'expiresAt': DateTime.now()
                                .toUtc()
                                .add(const Duration(hours: 24))
                                .toIso8601String(),
                            'lines': [
                              {
                                'articleId': _qArticleId.text.trim(),
                                'makingAmount': normAmount(
                                  _qMaking.text.trim().isEmpty ? '0.00' : _qMaking.text,
                                ),
                                'otherAmount': '0.00',
                                'discountAmount': normAmount(
                                  _qDiscount.text.trim().isEmpty ? '0.00' : _qDiscount.text,
                                ),
                              },
                            ],
                          }),
                          'Sales estimate generated.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_activeForm == 'CN') ...[
                const SizedBox(height: 12),
                SaasFormCard(
                  title: 'New Sales Credit Note (Return QC)',
                  trailing: TextButton(
                    onPressed: () => setState(() => _activeForm = null),
                    child: const Text('Close'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LookupField(
                        label: 'Posted Sales Invoice',
                        controller: _cnInvId,
                        options: invOpts,
                        onSelected: (_) {
                          _cnLineId.clear();
                          setState(() {});
                        },
                      ),
                      if (cnLineOpts.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Returned Invoice Line',
                          controller: _cnLineId,
                          options: cnLineOpts,
                        ),
                      ],
                      const SizedBox(height: 10),
                      DatePickField(label: 'Credit Note Date', controller: _cnDate),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SaasDropdown(
                              label: 'Return QC State',
                              value: _cnQcState,
                              options: const {
                                'PASSED': 'PASSED',
                                'FAILED': 'FAILED',
                              },
                              onChanged: (v) => setState(() => _cnQcState = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SaasDropdown(
                              label: 'Disposition',
                              value: _cnDisposition,
                              options: const {
                                'RESTOCK': 'RESTOCK',
                                'QUARANTINE': 'QUARANTINE',
                                'SCRAP': 'SCRAP',
                              },
                              onChanged: (v) => setState(() => _cnDisposition = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Restock Custody Location (optional)',
                        controller: _cnRestockLocId,
                        options: _lk.locations,
                        optional: true,
                      ),
                      const SizedBox(height: 10),
                      SaasField(
                        label: 'Line return reason (min 5 chars)',
                        controller: _cnLineReason,
                      ),
                      const SizedBox(height: 10),
                      SaasField(
                        label: 'Credit note reason (min 10 chars)',
                        controller: _cnReason,
                      ),
                      const SizedBox(height: 12),
                      GoldButton(
                        label: 'Create Credit Note',
                        busy: _busy,
                        onPressed: () {
                          final invLines = asList(selectedCnInvoice?['lines']);
                          final chosenLineId = _cnLineId.text.trim().isNotEmpty
                              ? _cnLineId.text.trim()
                              : (invLines.isNotEmpty ? '${invLines.first['id']}' : '');
                          if (chosenLineId.isEmpty) {
                            setState(
                              () => _error =
                                  'Select a sales invoice that contains at least one billed article line.',
                            );
                            return;
                          }
                          _mutate(
                            (api) => api.post('/sales/credit-notes', idempotent: true, body: {
                              'salesInvoiceId': _cnInvId.text.trim(),
                              'creditNoteDate': _cnDate.text.trim(),
                              'reason': _cnReason.text.trim(),
                              'lines': [
                                {
                                  'salesInvoiceLineId': chosenLineId,
                                  'returnReason': _cnLineReason.text.trim(),
                                  'qcState': _cnQcState,
                                  'disposition': _cnDisposition,
                                  if (_cnRestockLocId.text.trim().isNotEmpty)
                                    'restockLocationId': _cnRestockLocId.text.trim(),
                                },
                              ],
                            }),
                            'Sales credit note draft created.',
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],

              if (_activeForm == 'TAX') ...[
                const SizedBox(height: 12),
                SaasFormCard(
                  title: 'New GST Tax Profile',
                  trailing: TextButton(
                    onPressed: () => setState(() => _activeForm = null),
                    child: const Text('Close'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SaasField(
                              label: 'Code (e.g. GST_3)',
                              controller: _tpCode,
                              mono: true,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SaasField(
                              label: 'Rate (%)',
                              controller: _tpRate,
                              mono: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SaasField(label: 'Tax Profile Name', controller: _tpName),
                      const SizedBox(height: 10),
                      DatePickField(label: 'Effective From', controller: _tpEffFrom),
                      const SizedBox(height: 8),
                      SaasCheckRow(
                        label: 'Synthetic test profile only',
                        value: _tpSynthetic,
                        onChanged: (v) => setState(() => _tpSynthetic = v),
                      ),
                      const SizedBox(height: 10),
                      GoldButton(
                        label: 'Create Tax Profile',
                        busy: _busy,
                        onPressed: () => _mutate(
                          (api) => api.post('/sales/tax-profiles', body: {
                            'code': _tpCode.text.trim().toUpperCase(),
                            'name': _tpName.text.trim(),
                            'ratePercent': _tpRate.text.trim(),
                            'syntheticTestOnly': _tpSynthetic,
                            'effectiveFrom': _tpEffFrom.text.trim(),
                          }),
                          'Tax profile created.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),

              if (_loading) ...[
                const Panel(child: Skeleton(height: 130)),
                const SizedBox(height: 12),
                const Panel(child: Skeleton(height: 110)),
              ] else if (_tab == 'INVOICES') ...[
                _buildSalesInvoicesTab(fInvoices, q),
              ] else if (_tab == 'ESTIMATES') ...[
                _buildEstimatesTab(fEstimates),
              ] else if (_tab == 'ORDERS') ...[
                _buildOrdersDispatchTab(fOrders),
              ] else if (_tab == 'CREDITS') ...[
                _buildCreditNotesTab(fCredits),
              ] else ...[
                _buildTaxProfilesTab(fTax),
              ],
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: GoldAddFab(
            icon: _activeForm != null ? Icons.close_rounded : Icons.add_rounded,
            tooltip: _tab == 'ESTIMATES'
                ? 'New Estimate'
                : _tab == 'ORDERS'
                    ? 'Book Custom Order'
                    : _tab == 'CREDITS'
                        ? 'New Credit Note'
                        : _tab == 'TAX_PROFILES'
                            ? 'New Tax Profile'
                            : 'Convert Estimate to Invoice',
            onPressed: () {
              if (_tab == 'ORDERS') {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const CustomOrdersScreen()),
                ).then((_) => _loadSalesWorkspace());
                return;
              }
              setState(() {
                if (_activeForm != null) {
                  _activeForm = null;
                } else {
                  _activeForm = _tab == 'ESTIMATES'
                      ? 'ESTIMATE'
                      : _tab == 'CREDITS'
                          ? 'CN'
                          : _tab == 'TAX_PROFILES'
                              ? 'TAX'
                              : 'INVOICE';
                }
              });
            },
          ),
        ),
      ],
    );
  }

  /// Exact `Sales Invoices` view from `image-4.png`:
  /// - Luxury `No Sales Invoices Yet` + `Start POS Billing Now` empty state when 0 invoices
  /// - Rich mobile cards showing all 9 columns (`Invoice Date`, `Doc #`, `Customer`, `Articles`, `Taxable`, `Tax (GST)`, `Total Amount`, `Outstanding`, `State`, `Actions`)
  Widget _buildSalesInvoicesTab(List<Map<String, dynamic>> fInvoices, String query) {
    if (fInvoices.isEmpty) {
      if (query.isNotEmpty) {
        return const SaasEmptyBox('No sales invoices match your search query.');
      }
      return Panel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFBF3DC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE7CF8B)),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 28,
                color: Pal.goldDeep,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Sales Invoices Yet',
              textAlign: TextAlign.center,
              style: T.body(17.5, color: Pal.ink, w: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Ready to bill showroom customers? Start a quick POS bill with live gold valuation or convert an existing quote.',
              textAlign: TextAlign.center,
              style: T.body(12.8, color: Pal.muted),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 240,
              child: RoyalGoldButton(
                icon: Icons.auto_awesome_rounded,
                label: 'Start POS Billing Now',
                onPressed: _openPosQuickBill,
              ),
            ),
            if (_estimates.isNotEmpty) ...[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => setState(() => _activeForm = 'INVOICE'),
                icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                label: Text('Convert Existing Quote (${_estimates.length})'),
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final inv in fInvoices)
          _SalesInvoiceMobileCard(
            inv: inv,
            busy: _busy,
            onPost: '${inv['state']}' == 'DRAFT'
                ? () => _mutate(
                      (api) => api.post(
                        '/sales/invoices/${inv['id']}/post',
                        idempotent: true,
                        body: {
                          'expectedVersion': asInt(inv['version'], fallback: 1),
                          'postingPeriodId': _periodId.text.trim(),
                          'documentSeriesId': _invSeriesId.text.trim(),
                          'journalSeriesId': _jvSeriesId.text.trim(),
                          'reason':
                              'Posted showroom sales invoice to AR & inventory ledger.',
                        },
                      ),
                      'Sales invoice posted.',
                    )
                : null,
            onCreateReturn: '${inv['state']}' == 'POSTED'
                ? () => setState(() {
                      _tab = 'CREDITS';
                      _cnInvId.text = '${inv['id']}';
                      _cnLineId.clear();
                      _activeForm = 'CN';
                    })
                : null,
          ),
      ],
    );
  }

  Widget _buildEstimatesTab(List<Map<String, dynamic>> fEstimates) {
    if (fEstimates.isEmpty) {
      return Panel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          children: [
            const Icon(Icons.request_quote_outlined, size: 34, color: Pal.goldDeep),
            const SizedBox(height: 10),
            Text('No Estimates Generated Yet', style: T.body(16, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Tap + to draft an authoritative showroom quote or use POS Quick Bill.',
              textAlign: TextAlign.center,
              style: T.body(12.5, color: Pal.muted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => setState(() => _activeForm = 'ESTIMATE'),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Estimate'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final est in fEstimates)
          LuxuryRecordCard(
            icon: Icons.request_quote_outlined,
            code: '${est['quoteNumber'] ?? shortId('${est['id']}')}',
            status: '${est['state'] ?? 'OPEN'}',
            lines: [
              ('Customer', '${asMap(est['customer'])['displayName'] ?? '-'}'),
              if ('${est['quoteDate'] ?? ''}'.isNotEmpty)
                ('Quote Date', fmtDate('${est['quoteDate']}')),
              ('Articles', '${asList(est['lines']).length} tagged piece(s)'),
              (
                'Metal / Making',
                '${inr(est['metalValue'] ?? '0')} · ${inr(est['makingAmount'] ?? '0')}',
              ),
              ('GST', inr(est['taxAmount'] ?? '0')),
            ],
            amountLabel: 'Total Estimate',
            amountValue: inr(est['totalAmount']),
            actions: [
              if ('${est['state'] ?? 'OPEN'}' != 'CONVERTED' &&
                  '${est['state'] ?? 'OPEN'}' != 'EXPIRED')
                GoldButton(
                  label: 'Convert to Invoice',
                  compact: true,
                  busy: _busy,
                  onPressed: () => setState(() {
                    _tab = 'INVOICES';
                    _estId.text = '${est['id']}';
                    _activeForm = 'INVOICE';
                  }),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildOrdersDispatchTab(List<Map<String, dynamic>> fOrders) {
    if (fOrders.isEmpty) {
      return Panel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Column(
          children: [
            const Icon(Icons.local_shipping_outlined, size: 34, color: Pal.goldDeep),
            const SizedBox(height: 10),
            Text('No Pending Orders or Dispatches', style: T.body(16, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Custom showroom bookings, scheduled deliveries, and dispatch challans appear here.',
              textAlign: TextAlign.center,
              style: T.body(12.5, color: Pal.muted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const CustomOrdersScreen()),
              ).then((_) => _loadSalesWorkspace()),
              icon: const Icon(Icons.diamond_outlined, size: 17),
              label: const Text('Open Custom Orders'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (final ord in fOrders)
          LuxuryRecordCard(
            icon: Icons.local_shipping_outlined,
            code:
                '${ord['documentNumber'] ?? ord['orderNumber'] ?? shortId('${ord['id'] ?? 'ORD'}')}',
            status: '${ord['state'] ?? ord['status'] ?? 'OPEN'}',
            lines: [
              (
                'Customer',
                '${asMap(ord['customer'])['displayName'] ?? ord['customerName'] ?? '-'}',
              ),
              if ('${ord['promisedDate'] ?? ord['deliveryDate'] ?? ''}'.isNotEmpty)
                (
                  'Promised Delivery',
                  fmtDate('${ord['promisedDate'] ?? ord['deliveryDate']}'),
                ),
              if ('${ord['estimatedWeightGrams'] ?? ''}'.isNotEmpty)
                ('Est. Weight', grams('${ord['estimatedWeightGrams']}')),
              if ('${ord['description'] ?? ''}'.isNotEmpty)
                ('Specification', '${ord['description']}'),
            ],
            amountLabel: '${ord['advanceAmount'] ?? ''}'.isNotEmpty
                ? 'Advance / Value'
                : 'Order Value',
            amountValue: inr(
              ord['totalAmount'] ??
                  ord['quotedMakingAmount'] ??
                  ord['advanceAmount'] ??
                  '0.00',
            ),
            actions: [
              GoldButton(
                label: 'Manage Order',
                compact: true,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const CustomOrdersScreen()),
                ).then((_) => _loadSalesWorkspace()),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildCreditNotesTab(List<Map<String, dynamic>> fCredits) {
    if (fCredits.isEmpty) {
      return const SaasEmptyBox(
        'No sales credit notes recorded yet. Tap + to create a return credit note with QC.',
      );
    }

    return Column(
      children: [
        for (final cn in fCredits)
          LuxuryRecordCard(
            icon: Icons.assignment_return_outlined,
            code: '${cn['documentNumber'] ?? shortId('${cn['id']}')}',
            status: '${cn['state'] ?? 'DRAFT'}',
            lines: [
              ('Customer', '${asMap(cn['customer'])['displayName'] ?? '-'}'),
              if ('${cn['creditNoteDate'] ?? ''}'.isNotEmpty)
                ('Credit Note Date', fmtDate('${cn['creditNoteDate']}')),
              if ('${cn['reason'] ?? ''}'.isNotEmpty) ('Reason', '${cn['reason']}'),
            ],
            amountLabel: 'Credit Value',
            amountValue: inr(cn['totalAmount']),
            actions: [
              if ('${cn['state']}' == 'DRAFT' || '${cn['state']}' == 'APPROVED')
                GoldButton(
                  label: '${cn['state']}' == 'DRAFT' ? 'Approve' : 'Post Return',
                  compact: true,
                  busy: _busy,
                  onPressed: () {
                    if ('${cn['state']}' == 'DRAFT') {
                      _mutate(
                        (api) => api.post(
                          '/sales/credit-notes/${cn['id']}/approve',
                          body: {
                            'expectedVersion': asInt(cn['version'], fallback: 1),
                            'reason':
                                'Approved sales return credit note after QC verification.',
                          },
                        ),
                        'Credit note approved.',
                      );
                    } else {
                      _mutate(
                        (api) => api.post(
                          '/sales/credit-notes/${cn['id']}/post',
                          idempotent: true,
                          body: {
                            'expectedVersion': asInt(cn['version'], fallback: 1),
                            'postingPeriodId': _periodId.text.trim(),
                            'documentSeriesId': _cnSeriesId.text.trim(),
                            'journalSeriesId': _jvSeriesId.text.trim(),
                            'reason':
                                'Posted approved sales credit note to inventory & AR.',
                          },
                        ),
                        'Credit note posted.',
                      );
                    }
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildTaxProfilesTab(List<Map<String, dynamic>> fTax) {
    if (fTax.isEmpty) {
      return const SaasEmptyBox(
        'No GST tax profiles found. Tap + to create & approve a 3% GST jewellery profile.',
      );
    }

    return Column(
      children: [
        for (final tp in fTax)
          LuxuryRecordCard(
            icon: Icons.percent_rounded,
            code: '${tp['code']} · ${tp['name']}',
            status: '${tp['state'] ?? 'DRAFT'}',
            lines: [
              ('Effective From', fmtDate('${tp['effectiveFrom'] ?? ''}')),
            ],
            amountLabel: 'GST Rate',
            amountValue: '${tp['ratePercent']}%',
            actions: [
              if ('${tp['state']}' == 'DRAFT')
                GoldButton(
                  label: 'Approve',
                  compact: true,
                  busy: _busy,
                  onPressed: () => _mutate(
                    (api) => api.post(
                      '/sales/tax-profiles/${tp['id']}/approve',
                      body: {
                        'expectedVersion': asInt(tp['version'], fallback: 1),
                        'reason':
                            'Approved GST tax profile after statutory rate verification.',
                      },
                    ),
                    'Tax profile approved.',
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Interactive Showroom Counter POS Quick Bill (`POS Quick Bill` button in `image-4.png`).
  Widget _buildPosQuickBill(BillingController c, bool bullionActive) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        // Top strip: Return to Sales Invoices + Live Rate / Counter Shift link
        Row(
          children: [
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: () => setState(() => _tab = 'INVOICES'),
              icon: const Icon(Icons.arrow_back_rounded, size: 17),
              label: const Text('Sales Invoices'),
            ),
            const Spacer(),
            InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const ShiftScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Pal.goldWash,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: Pal.goldBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.payments_outlined, size: 14, color: Pal.goldDeep),
                    const SizedBox(width: 5),
                    Text(
                      bullionActive ? 'Drawer Shift · 24K Live' : 'Counter POS Shifts',
                      style: T.body(11.2, color: Pal.goldDeep, w: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        // 1. Customer Card
        const SectionLabel('1 · Patron / Customer'),
        Panel(
          onTap: () async {
            final p = await showCustomerPicker(context);
            if (p != null) c.setCustomer(p);
          },
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.customer == null ? Pal.surfaceAlt : Pal.goldWash,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.customer == null
                        ? Pal.line
                        : Pal.gold.withValues(alpha: 0.45),
                  ),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 20,
                  color: c.customer == null ? Pal.muted : Pal.goldDeep,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: c.customer == null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select or Register Customer',
                            style: T.body(14.5, w: FontWeight.w700),
                          ),
                          Text(
                            'Tap to search mobile, name, GSTIN or PAN',
                            style: T.body(12, color: Pal.muted),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.customer!.name, style: T.body(15, w: FontWeight.w800)),
                          Text(
                            [
                              if (c.customer!.phone.isNotEmpty) c.customer!.phone,
                              if (c.customer!.gstin.isNotEmpty)
                                'GSTIN: ${c.customer!.gstin}',
                            ].isEmpty
                                ? c.customer!.code
                                : [
                                    if (c.customer!.phone.isNotEmpty) c.customer!.phone,
                                    if (c.customer!.gstin.isNotEmpty)
                                      'GSTIN: ${c.customer!.gstin}',
                                  ].join(' · '),
                            style: T.body(12, color: Pal.muted),
                          ),
                        ],
                      ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Pal.muted),
            ],
          ),
        ),

        // 2. Ornament Cart
        SectionLabel('2 · Tagged Ornaments (${c.lines.length})'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _barcode,
                textCapitalization: TextCapitalization.characters,
                style: T.mono(14),
                decoration: const InputDecoration(
                  hintText: 'Scan or enter ornament tag',
                  prefixIcon: Icon(Icons.sell_outlined, size: 19),
                ),
                onSubmitted: (s) {
                  c.scanAndAdd(s);
                  _barcode.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 50,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Pal.obsidian,
                  foregroundColor: Pal.goldSoft,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 50),
                ),
                onPressed: c.busy ? null : () => _scan(c),
                child: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (c.lines.isEmpty)
          Panel(
            color: Pal.surfaceAlt,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: Pal.muted, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Scan ornament string tags with the camera or add pieces directly from the Vault tab.',
                      style: T.body(12.8, color: Pal.muted),
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          for (var i = 0; i < c.lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CartLineCard(
                line: c.lines[i],
                onEditMaking: () => _editMaking(c, i),
                onRemove: () => c.removeAt(i),
              ),
            ),

        // 3. Old Gold Exchange Credit
        const SectionLabel('3 · Old Gold Trade-In (Optional)'),
        if (c.oldGold == null)
          OutlinedButton.icon(
            onPressed: () async {
              final v = await Navigator.push<ExchangeCredit>(
                context,
                MaterialPageRoute(builder: (_) => const OldGoldScreen(pickMode: true)),
              );
              if (v != null) c.setOldGold(v);
            },
            icon: const Icon(Icons.recycling_rounded, size: 18),
            label: const Text('Appraise & Attach Old Gold Credit'),
          )
        else
          Panel(
            color: Pal.goldWash,
            borderColor: Pal.gold.withValues(alpha: 0.55),
            child: Row(
              children: [
                const Icon(Icons.recycling_rounded, color: Pal.goldDeep, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.oldGold!.label.isEmpty
                            ? 'Old Gold Voucher Credit'
                            : c.oldGold!.label,
                        style: T.body(13.5, w: FontWeight.w800),
                      ),
                      if (c.oldGold!.fineWeight.isNotEmpty)
                        Text(
                          'Fine 999: ${fineGrams(c.oldGold!.fineWeight)}',
                          style: T.mono(11.5, color: Pal.goldDeep),
                        ),
                    ],
                  ),
                ),
                Text(
                  '− ${inr(c.oldGold!.credit)}',
                  style: T.display(18, color: Pal.goldDeep),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () => c.setOldGold(null),
                ),
              ],
            ),
          ),

        // 4. Multi-Tender Payments
        SectionLabel('4 · Payment Split (${inr(c.paidTotal)})'),
        if (c.lines.isNotEmpty && c.remainingBalanceDecimal > Decimal.zero) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final quick in const [
                ('UPI', '1-Tap Full UPI', Icons.qr_code_rounded),
                ('CARD', 'Full Card', Icons.credit_card_rounded),
                ('CASH', 'Full Cash', Icons.payments_outlined),
              ])
                ActionChip(
                  avatar: Icon(quick.$3, size: 15, color: Pal.goldDeep),
                  label: Text(
                    quick.$2,
                    style: T.body(12, color: Pal.goldDeep, w: FontWeight.w700),
                  ),
                  backgroundColor: Pal.goldWash,
                  side: BorderSide(color: Pal.gold.withValues(alpha: 0.45)),
                  onPressed: () => c.fillRemainingBalance(quick.$1),
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < c.payments.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Chip2(humanize(c.payments[i].mode)),
                  if (c.payments[i].reference.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    MonoTag(c.payments[i].reference),
                  ],
                  const Spacer(),
                  Text(
                    inr(c.payments[i].amount),
                    style: T.mono(14.5, w: FontWeight.w700),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18, color: Pal.muted),
                    onPressed: () => c.removePayment(i),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _addPayment(c),
          icon: const Icon(Icons.add_card_rounded, size: 18),
          label: const Text('Add Custom Payment Split'),
        ),

        // 5. Live GST Tax Invoice Summary Card
        if (c.lines.isNotEmpty) ...[
          const SizedBox(height: 18),
          LuxuryHeroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const EnterpriseBadge(
                  'GST Tax Invoice Preview',
                  icon: Icons.verified_outlined,
                ),
                const SizedBox(height: 12),
                _darkRow(
                  'Bullion Metal Value',
                  inr(c.metalSubtotal.toStringAsFixed(2)),
                ),
                _darkRow(
                  'Artisan Making Charges',
                  inr(c.makingSubtotal.toStringAsFixed(2)),
                ),
                _darkRow(
                  'GST (3.00% Jewellery)',
                  inr(c.gstSubtotal.toStringAsFixed(2)),
                ),
                if (c.oldGold != null)
                  _darkRow(
                    'Less: Old Gold Exchange',
                    '− ${inr(c.oldGold!.credit)}',
                    accent: Pal.goldSoft,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(color: Colors.white.withValues(alpha: 0.16)),
                ),
                Row(
                  children: [
                    Text('NET PAYABLE', style: T.caps(10.5, color: Colors.white70)),
                    const Spacer(),
                    Text(
                      inr(c.netPayableDecimal.toStringAsFixed(2)),
                      style: T.display(26, color: Pal.goldSoft),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      c.remainingBalanceDecimal == Decimal.zero
                          ? 'Tender Balanced'
                          : 'Balance Due: ${inr(c.remainingBalanceDecimal.toStringAsFixed(2))}',
                      style: T.mono(
                        12,
                        color: c.remainingBalanceDecimal == Decimal.zero
                            ? const Color(0xFF6EE7B7)
                            : Colors.white70,
                      ),
                    ),
                    const Spacer(),
                    Text('Paid: ${inr(c.paidTotal)}', style: T.mono(12, color: Colors.white)),
                  ],
                ),
              ],
            ),
          ),
        ],

        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Panel(
              color: Pal.dangerWash,
              borderColor: Pal.danger.withValues(alpha: 0.35),
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 18, color: Pal.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.error!,
                      style: T.body(12.8, color: Pal.danger, w: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),

        const SizedBox(height: 18),
        RoyalGoldButton(
          busy: c.busy,
          icon: Icons.receipt_long_rounded,
          onPressed: c.busy ? null : () => _checkout(c),
          label: c.lines.isEmpty
              ? 'Issue GST Tax Invoice'
              : 'Issue GST Invoice · ${inr(c.netPayableDecimal.toStringAsFixed(2))}',
        ),
      ],
    );
  }

  Widget _darkRow(String k, String v, {Color? accent}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          children: [
            Expanded(child: Text(k, style: T.body(12.8, color: Colors.white70))),
            Text(
              v,
              style: T.mono(13, color: accent ?? Colors.white, w: FontWeight.w600),
            ),
          ],
        ),
      );
}

/// Mobile-formatted Sales Invoice card displaying all 9 columns from `image-4.png`
/// (`Invoice Date`, `Doc #`, `Customer`, `Articles`, `Taxable`, `Tax (GST)`,
/// `Total Amount`, `Outstanding`, `State`, `Actions`).
class _SalesInvoiceMobileCard extends StatelessWidget {
  const _SalesInvoiceMobileCard({
    required this.inv,
    required this.busy,
    this.onPost,
    this.onCreateReturn,
  });

  final Map<String, dynamic> inv;
  final bool busy;
  final VoidCallback? onPost;
  final VoidCallback? onCreateReturn;

  @override
  Widget build(BuildContext context) {
    final docNo = '${inv['documentNumber'] ?? shortId('${inv['id'] ?? 'INV'}')}';
    final invDate = fmtDate('${inv['invoiceDate'] ?? inv['createdAt'] ?? ''}');
    final custName = '${asMap(inv['customer'])['displayName'] ?? inv['customerName'] ?? 'Walk-in Customer'}';
    final articlesCnt = asList(inv['lines']).length;
    final state = '${inv['state'] ?? inv['status'] ?? 'DRAFT'}';

    final taxable = '${inv['taxableAmount'] ?? inv['subtotalAmount'] ?? '0.00'}';
    final taxAmt = '${inv['taxAmount'] ?? inv['gstAmount'] ?? '0.00'}';
    final totalAmt = '${inv['totalAmount'] ?? '0.00'}';
    final outstandingRaw =
        inv['outstandingAmount'] ?? inv['openAmount'] ?? inv['balanceAmount'] ?? totalAmt;
    final outstandingDec = decOrZero(outstandingRaw);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pal.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1A140E),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Pal.goldWash,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Pal.goldBorder),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 17,
                  color: Pal.goldDeep,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      docNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.mono(13.5, color: Pal.ink, w: FontWeight.w800),
                    ),
                    Text(
                      invDate,
                      style: T.body(11.5, color: Pal.muted),
                    ),
                  ],
                ),
              ),
              StatusPill(state),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 15, color: Pal.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  custName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(13.5, color: Pal.ink, w: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Chip2(
                articlesCnt == 1 ? '1 Article' : '$articlesCnt Articles',
                gold: true,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Pal.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Pal.line),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _cell('TAXABLE', inr(taxable))),
                    const SizedBox(width: 8),
                    Expanded(child: _cell('TAX (GST)', inr(taxAmt))),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _cell('TOTAL AMOUNT', inr(totalAmt), bold: true),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _cell(
                        'OUTSTANDING',
                        inr(outstandingRaw),
                        bold: true,
                        color: outstandingDec > Decimal.zero ? Pal.warn : Pal.ok,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onPost != null || onCreateReturn != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onPost != null)
                  GoldButton(
                    label: 'Post Invoice',
                    compact: true,
                    busy: busy,
                    onPressed: onPost,
                  ),
                if (onCreateReturn != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: busy ? null : onCreateReturn,
                    icon: const Icon(Icons.assignment_return_outlined, size: 15),
                    label: const Text('Return / Credit Note'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(String label, String val, {bool bold = false, Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.caps(9, color: Pal.muted)),
        const SizedBox(height: 2),
        Text(
          val,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.mono(
            12.5,
            color: color ?? Pal.ink,
            w: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    required this.line,
    required this.onEditMaking,
    required this.onRemove,
  });

  final CartLine line;
  final VoidCallback onEditMaking;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final a = line.article;
    return Panel(
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
                      a.name.isEmpty ? a.barcode : a.name,
                      style: T.body(15, w: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        MonoTag(a.barcode),
                        Chip2('${a.metal} ${a.karatLabel}', gold: true),
                        StatusPill(line.reservationId != null ? 'HELD 15M' : 'IN CART'),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Pal.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Pal.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                KeyValue(
                  'Net Wt × Rate',
                  '${grams(a.effectiveNetWeight)} × ${rate(line.ratePerGram)}',
                  mono: true,
                ),
                KeyValue(
                  'Metal Value',
                  inr(line.metalValue.toStringAsFixed(2)),
                  mono: true,
                ),
                InkWell(
                  onTap: onEditMaking,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          'Making Charges',
                          style: T.body(12.8, color: Pal.goldDeep, w: FontWeight.w700),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_outlined, size: 13, color: Pal.goldDeep),
                        const Spacer(),
                        Text(
                          inr(line.makingCharge),
                          style: T.mono(13, color: Pal.goldDeep, w: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                KeyValue('GST (3%)', inr(line.gstAmount.toStringAsFixed(2)), mono: true),
                const Divider(),
                KeyValue(
                  'Line Total',
                  inr(line.lineTotal.toStringAsFixed(2)),
                  strong: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceReceiptSheet extends StatelessWidget {
  const _InvoiceReceiptSheet(this.r);
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final invNo = '${r['invoiceNumber'] ?? r['documentNumber'] ?? r['id'] ?? 'POS-INV'}';
    final total = '${r['totalAmount'] ?? r['grandTotal'] ?? r['netAmount'] ?? '0.00'}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LuxuryHeroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const EnterpriseBadge(
                      'GST Tax Invoice Issued',
                      icon: Icons.verified_rounded,
                    ),
                    const Spacer(),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy_rounded, size: 17, color: Colors.white70),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: invNo));
                        toast(context, 'Invoice number copied.');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(invNo, style: T.display(22, color: Colors.white)),
                const SizedBox(height: 6),
                Text(inr(total), style: T.display(30, color: Pal.goldSoft)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Panel(
            child: Column(
              children: [
                if (r['customerName'] != null)
                  KeyValue('Patron', '${r['customerName']}', strong: true),
                if (r['metalSubtotal'] != null)
                  KeyValue('Metal Value', inr(r['metalSubtotal']), mono: true),
                if (r['makingSubtotal'] != null)
                  KeyValue('Making Charges', inr(r['makingSubtotal']), mono: true),
                if (r['gstAmount'] != null)
                  KeyValue('GST (3%)', inr(r['gstAmount']), mono: true),
                if (r['oldGoldCredit'] != null)
                  KeyValue(
                    'Old Gold Credit',
                    '− ${inr(r['oldGoldCredit'])}',
                    mono: true,
                  ),
                if (r['paidAmount'] != null)
                  KeyValue(
                    'Tender Collected',
                    inr(r['paidAmount']),
                    strong: true,
                    valueColor: Pal.ok,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done · Start Next Bill'),
          ),
        ],
      ),
    );
  }
}
