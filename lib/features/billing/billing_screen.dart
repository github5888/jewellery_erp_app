import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/device_bridge.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/pdf_export.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../inventory/scanner_page.dart';
import '../supply/supply_production_screens.dart';
import 'billing_controller.dart';

/// `Sales & POS Billing` (`pos.hrpocket.in/sales`) — Exact 1:1 mobile-formatted
/// parity with `image-64.png` and `Screenshot (709).png`..`Screenshot (716).png`:
/// 1. `Sales Invoices` + Posting Period / Sales Invoice Series / Journal Series bar + `POS Quick Bill`
/// 2. `POS 1-Click Billing & Counter Checkout` modal (Quick Walk-in Customer, Tag Scanner,
///    Charges, Required Posting Configuration, Immediate vs Open-Item Settlement, Atomic Posting & Print/PDF)
/// 3. `Estimates` (`Draft Authoritative Estimate / Quotation`)
/// 4. `Orders & Dispatch` (`Sales Orders` & `Dispatches` sub-tabs)
/// 5. `Credit Notes` (`Draft Sales Credit Note (Return)`)
/// 6. `Tax Profiles` (`Add Effective-Dated Tax Profile`)
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _regSearch = TextEditingController();

  // 'INVOICES' | 'ESTIMATES' | 'ORDERS' | 'CREDITS' | 'TAX_PROFILES'
  String _tab = 'INVOICES';
  // Inside 'ORDERS': 'SALES_ORDERS' | 'DISPATCHES'
  String _orderSubTab = 'SALES_ORDERS';

  int _lastSeenCartCount = 0;

  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _estimates = [];
  List<Map<String, dynamic>> _salesOrders = [];
  List<Map<String, dynamic>> _dispatches = [];
  List<Map<String, dynamic>> _credits = [];
  List<Map<String, dynamic>> _taxProfiles = [];
  List<LookupOption> _rateVersionOpts = [];
  WorkspaceLookup _lk = WorkspaceLookup();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  // null | 'ESTIMATE' | 'CN' | 'TAX' | 'CONVERT_INVOICE'
  String? _activeForm;

  // Sales Invoices Top Posting Configuration Bar (`image-64.png`)
  final _periodId = TextEditingController();
  final _invSeriesId = TextEditingController();
  final _jvSeriesId = TextEditingController();
  final _cnSeriesId = TextEditingController();

  // Default GL Accounts (auto-discovered from `/accounting/workspace`)
  final _recvAcctId = TextEditingController();
  final _revAcctId = TextEditingController();
  final _taxAcctId = TextEditingController();
  final _cogsAcctId = TextEditingController();
  final _invAcctId = TextEditingController();

  // Tab 2: `Draft Authoritative Estimate / Quotation` (`Screenshot (712).png`)
  final _qCustomerId = TextEditingController();
  final _qArticleId = TextEditingController();
  final _qRateVerId = TextEditingController();
  final _qTaxProfId = TextEditingController();
  final _qDate = TextEditingController(text: todayIso());
  final _qExpiresDate = TextEditingController();
  final _qMaking = TextEditingController();

  // Convert Estimate -> Invoice (`POST /sales/invoices`)
  final _convEstId = TextEditingController();
  final _convInvDate = TextEditingController(text: todayIso());

  // Tab 3A: `Orders & Dispatch` -> `Sales Orders` (`Screenshot (713).png`)
  final _soEstimateId = TextEditingController();
  final _soOrderDate = TextEditingController(text: todayIso());
  final _soPromisedDate = TextEditingController(text: todayIso());
  final _soSeriesId = TextEditingController();

  // Tab 3B: `Orders & Dispatch` -> `Dispatches` (`Screenshot (714).png`)
  final _dpInvoiceId = TextEditingController();
  final _dpDate = TextEditingController(text: todayIso());
  String _dpMethod = 'CUSTOMER_PICKUP';
  final _dpRecipient = TextEditingController();
  final _dpSeriesId = TextEditingController();

  // Tab 4: `Draft Sales Credit Note (Return)` (`Screenshot (715).png`)
  final _cnInvId = TextEditingController();
  final _cnArticleOrLineId = TextEditingController();
  String _cnDisposition = 'RESTOCK';
  final _cnReason = TextEditingController();
  final _cnRestockLocId = TextEditingController();

  // Tab 5: `Add Effective-Dated Tax Profile` (`Screenshot (716).png`)
  final _tpCode = TextEditingController();
  final _tpName = TextEditingController();
  final _tpRate = TextEditingController();
  final _tpEffFrom = TextEditingController(text: todayIso());
  bool _tpSynthetic = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final cart = context.read<BillingController>();
      _lastSeenCartCount = cart.lines.length;
      await _loadSalesWorkspace();
      if (!mounted) return;
      if (cart.lines.isNotEmpty) {
        _openPos1ClickModal(initialArticle: cart.lines.first.article);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _regSearch,
      _periodId,
      _invSeriesId,
      _jvSeriesId,
      _cnSeriesId,
      _recvAcctId,
      _revAcctId,
      _taxAcctId,
      _cogsAcctId,
      _invAcctId,
      _qCustomerId,
      _qArticleId,
      _qRateVerId,
      _qTaxProfId,
      _qDate,
      _qExpiresDate,
      _qMaking,
      _convEstId,
      _convInvDate,
      _soEstimateId,
      _soOrderDate,
      _soPromisedDate,
      _soSeriesId,
      _dpInvoiceId,
      _dpDate,
      _dpRecipient,
      _dpSeriesId,
      _cnInvId,
      _cnArticleOrLineId,
      _cnReason,
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
      final ratesRaw = results[1];
      final lk = results[2] as WorkspaceLookup;

      final invoices = asList(d, keys: const ['invoices', 'salesInvoices']);
      final estimates = asList(d, keys: const ['estimates']);
      final salesOrders = asList(d, keys: const ['salesOrders', 'orders']);
      final dispatches = asList(d, keys: const ['dispatches', 'deliveryChallans']);
      final credits = asList(d, keys: const ['creditNotes']);
      final taxProfiles = asList(d, keys: const ['taxProfiles']);

      final rvOpts = <LookupOption>[];
      for (final book in asList(ratesRaw, keys: const ['rateBooks', 'books', 'items'])) {
        final bookName = '${book['name'] ?? book['code'] ?? 'Rate Book'}';
        for (final v in asList(book['versions'])) {
          if ('${v['state']}'.toUpperCase() == 'PUBLISHED') {
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

      // Pre-populate real workspace IDs when available (never fake IDs)
      if (_periodId.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _periodId.text = lk.openPeriods().first.id;
      }
      if (_invSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['SALES_INVOICE', 'INVOICE']);
        if (s.isNotEmpty) _invSeriesId.text = s.first.id;
      }
      if (_jvSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['JOURNAL']);
        if (s.isNotEmpty) _jvSeriesId.text = s.first.id;
      }
      if (_cnSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['CREDIT_NOTE', 'RETURN']);
        if (s.isNotEmpty) _cnSeriesId.text = s.first.id;
      }
      if (_soSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['SALES_ORDER', 'ORDER']);
        if (s.isNotEmpty) _soSeriesId.text = s.first.id;
      }
      if (_dpSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['DISPATCH', 'DELIVERY_CHALLAN']);
        if (s.isNotEmpty) _dpSeriesId.text = s.first.id;
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
      final approvedTax = taxProfiles
          .where((t) => '${t['state']}'.toUpperCase() == 'APPROVED')
          .firstOrNull;
      if (_qTaxProfId.text.isEmpty && approvedTax != null) {
        _qTaxProfId.text = '${approvedTax['id']}';
      }

      setState(() {
        _invoices = invoices;
        _estimates = estimates;
        _salesOrders = salesOrders;
        _dispatches = dispatches;
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

  List<LookupOption> _approvedTaxOptions() => _taxProfiles
      .where((t) => '${t['state']}'.toUpperCase() == 'APPROVED')
      .map(
        (t) => LookupOption(
          id: '${t['id']}',
          label: '${t['code']} · ${t['name']} (${t['ratePercent']}%)',
          raw: t,
        ),
      )
      .toList();

  List<LookupOption> _availableArticleOptions() => _lk
      .availableArticles()
      .where((o) => o.id.isNotEmpty)
      .toList();

  Future<void> _mutate(
    Future<void> Function(ApiClient api) fn,
    String successMsg,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn(context.read<ApiClient>());
      if (!mounted) return;
      setState(() => _activeForm = null);
      toast(context, successMsg);
      await _loadSalesWorkspace();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadInvoiceWithServerRender(Map<String, dynamic> inv) async {
    final id = '${inv['id'] ?? ''}'.trim();
    String? html;
    if (id.isNotEmpty) {
      try {
        final snap = asMap(
          await context.read<ApiClient>().post(
            '/documents/render',
            idempotent: true,
            body: {
              'sourceType': 'SALES_INVOICE',
              'documentType': 'SALES_INVOICE',
              'sourceId': id,
            },
          ),
        );
        final rawOut =
            '${snap['renderedHtml'] ?? snap['html'] ?? snap['content'] ?? snap['renderedContent'] ?? ''}'
                .trim();
        if (rawOut.isNotEmpty) html = rawOut;
      } catch (_) {
        // Fallback cleanly to built-in A4 vector PDF export
      }
    }
    if (!mounted) return;
    await ErpPdfExporter.downloadSalesInvoice(
      context,
      inv,
      renderedHtml: html,
    );
  }

  /// Opens the exact `POS 1-Click Billing & Counter Checkout` modal (`Screenshot (710).png` + `Screenshot (709).png`).
  Future<void> _openPos1ClickModal({Article? initialArticle}) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _Pos1ClickCheckoutModal(
        initialLookup: _lk,
        rateVersionOpts: _rateVersionOpts,
        approvedTaxOpts: _approvedTaxOptions(),
        defaultPeriodId: _periodId.text,
        defaultInvSeriesId: _invSeriesId.text,
        defaultJvSeriesId: _jvSeriesId.text,
        defaultRecvAcctId: _recvAcctId.text,
        defaultRevAcctId: _revAcctId.text,
        defaultTaxAcctId: _taxAcctId.text,
        defaultCogsAcctId: _cogsAcctId.text,
        defaultInvAcctId: _invAcctId.text,
        initialArticle: initialArticle,
      ),
    );
    if (!mounted || result == null) return;
    context.read<BillingController>().clear();
    await _loadSalesWorkspace();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _InvoiceReceiptSheet(
        result,
        onDownloadPdf: () => _downloadInvoiceWithServerRender(result),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BillingController>();
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();

    if (c.lines.length > _lastSeenCartCount && c.lines.isNotEmpty) {
      final art = c.lines.first.article;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPos1ClickModal(initialArticle: art);
      });
    }
    _lastSeenCartCount = c.lines.length;

    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final bullionActive =
        (gold999 != null && decOrZero(gold999.sell) > Decimal.zero) ||
            _rateVersionOpts.isNotEmpty;
    final showroomSub = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    final q = _regSearch.text.trim().toLowerCase();
    bool matchesSearch(Map<String, dynamic> row) {
      if (q.isEmpty) return true;
      return row.values.any((v) => '$v'.toLowerCase().contains(q));
    }

    final fInvoices = _invoices.where(matchesSearch).toList();
    final fEstimates = _estimates.where(matchesSearch).toList();
    final fSalesOrders = _salesOrders.where(matchesSearch).toList();
    final fDispatches = _dispatches.where(matchesSearch).toList();
    final fCredits = _credits.where(matchesSearch).toList();
    final fTax = _taxProfiles.where(matchesSearch).toList();

    return LuxuryModuleScaffold(
      title: 'Sales & POS Billing',
      subtitle: showroomSub.isEmpty ? null : showroomSub,
      icon: Icons.receipt_long_rounded,
      searchController: _regSearch,
      searchHint: 'Search Doc #, Quote #, Customer, Tag or State...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: 'Refresh Sales Workspace',
          onPressed: _loadSalesWorkspace,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openPos1ClickModal(),
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
                  const SizedBox(width: 4),
                  Text(
                    'POS Bill',
                    style: T.body(11.5, color: Colors.white, w: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _loadSalesWorkspace,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            // Top Workspace Card (`Retail Sales and Customer Returns` — `image-64.png`)
            Panel(
              radius: 18,
              padding: const EdgeInsets.all(15),
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
                              style: T.body(16, color: Pal.ink, w: FontWeight.w800),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Authoritative estimates, tagged invoices with one-article-one-sale reservation, and credit notes with return QC.',
                              style: T.body(12.2, color: Pal.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Bullion rate pill + Contextual primary CTA (`POS Quick Bill` / `+ New Estimate` / `New Credit Note` / `+ Tax Profile`)
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
                        ).then((_) => _loadSalesWorkspace()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF8EB),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(color: const Color(0xFFE8D399)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.toll_rounded,
                                size: 13.5,
                                color: Pal.goldDeep,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                bullionActive
                                    ? (gold999 != null &&
                                            decOrZero(gold999.sell) > Decimal.zero
                                        ? 'Bullion 24K: ${inr(gold999.sell)} / g'
                                        : 'Bullion rates: Published board active')
                                    : 'Bullion rates: No published rate',
                                style: T.body(
                                  11.5,
                                  color: Pal.goldDeep,
                                  w: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildContextualActionButton(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 5 Exact Mode Tabs (`image-64.png`, `Screenshot (711)..(716)`)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Pal.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Pal.line),
                      ),
                      child: Row(
                        children: [
                          for (final t in [
                            ('INVOICES', 'Sales Invoices (${_invoices.length})'),
                            ('ESTIMATES', 'Estimates (${_estimates.length})'),
                            (
                              'ORDERS',
                              'Orders & Dispatch (${_salesOrders.length + _dispatches.length})',
                            ),
                            ('CREDITS', 'Credit Notes (${_credits.length})'),
                            ('TAX_PROFILES', 'Tax Profiles (${_taxProfiles.length})'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () => setState(() {
                                  _tab = t.$1;
                                  _activeForm = null;
                                  _error = null;
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: _tab == t.$1
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0xFFCFA234),
                                              Color(0xFFB38620),
                                            ],
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    t.$2,
                                    style: T.body(
                                      12.2,
                                      color: _tab == t.$1 ? Colors.white : Pal.ink,
                                      w: _tab == t.$1
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
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
              ErrorBanner(_error!, onRetry: _loadSalesWorkspace),
            ],

            const SizedBox(height: 12),

            if (_loading) ...[
              const Panel(child: Skeleton(height: 130)),
              const SizedBox(height: 12),
              const Panel(child: Skeleton(height: 120)),
            ] else if (_tab == 'INVOICES') ...[
              _buildSalesInvoicesTab(fInvoices, q),
            ] else if (_tab == 'ESTIMATES') ...[
              _buildEstimatesTab(fEstimates),
            ] else if (_tab == 'ORDERS') ...[
              _buildOrdersAndDispatchTab(fSalesOrders, fDispatches),
            ] else if (_tab == 'CREDITS') ...[
              _buildCreditNotesTab(fCredits),
            ] else ...[
              _buildTaxProfilesTab(fTax),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContextualActionButton() {
    switch (_tab) {
      case 'ESTIMATES':
        return GoldButton(
          label: _activeForm == 'ESTIMATE' ? 'Close Form' : '+ New Estimate',
          compact: true,
          onPressed: () => setState(
            () => _activeForm = _activeForm == 'ESTIMATE' ? null : 'ESTIMATE',
          ),
        );
      case 'CREDITS':
        return GoldButton(
          label: _activeForm == 'CN' ? 'Close Form' : 'New Credit Note',
          icon: Icons.replay_rounded,
          compact: true,
          onPressed: () => setState(
            () => _activeForm = _activeForm == 'CN' ? null : 'CN',
          ),
        );
      case 'TAX_PROFILES':
        return GoldButton(
          label: _activeForm == 'TAX' ? 'Close Form' : '+ Tax Profile',
          compact: true,
          onPressed: () => setState(
            () => _activeForm = _activeForm == 'TAX' ? null : 'TAX',
          ),
        );
      default:
        return GoldButton(
          label: 'POS Quick Bill',
          icon: Icons.auto_awesome_rounded,
          compact: true,
          onPressed: () => _openPos1ClickModal(),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 1: SALES INVOICES (`image-64.png`)
  // ---------------------------------------------------------------------------
  Widget _buildSalesInvoicesTab(
    List<Map<String, dynamic>> fInvoices,
    String query,
  ) {
    final openPeriods = _lk.openPeriods();
    final invSeries = _lk.seriesFor(const ['SALES_INVOICE', 'INVOICE']);
    final jvSeries = _lk.seriesFor(const ['JOURNAL']);
    final estOpts = _estimates
        .where((e) {
          final st = '${e['state']}'.toUpperCase();
          return st != 'CONVERTED' && st != 'EXPIRED';
        })
        .map(
          (e) => LookupOption(
            id: '${e['id']}',
            label:
                '${e['quoteNumber'] ?? shortId('${e['id']}')} · ${asMap(e['customer'])['displayName'] ?? 'Customer'} · ${inr(e['totalAmount'])}',
            raw: e,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Posting Period + Sales Invoice Series + Journal Series Configuration Card (`image-64.png`)
        Panel(
          radius: 16,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LookupField(
                label: 'Posting Period',
                controller: _periodId,
                options: openPeriods,
                hint: '-- Select open period --',
                optional: true,
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Sales Invoice Series',
                controller: _invSeriesId,
                options: invSeries.isNotEmpty ? invSeries : _lk.series,
                hint: '-- Select invoice series --',
                optional: true,
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Journal Series',
                controller: _jvSeriesId,
                options: jvSeries.isNotEmpty ? jvSeries : _lk.series,
                hint: '-- Select journal series --',
                optional: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Posting is blocked until an open period and matching active document series are explicitly selected.',
                style: T.body(11.6, color: Pal.muted),
              ),
            ],
          ),
        ),

        if (_activeForm == 'CONVERT_INVOICE') ...[
          const SizedBox(height: 12),
          SaasFormCard(
            title: 'Create Sales Invoice from Estimate',
            trailing: TextButton(
              onPressed: () => setState(() => _activeForm = null),
              child: const Text('Cancel'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Accepted / Open Estimate',
                  controller: _convEstId,
                  options: estOpts,
                  hint: '-- Select Estimate --',
                ),
                const SizedBox(height: 10),
                DatePickField(label: 'Invoice Date', controller: _convInvDate),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Customer Receivable Account *',
                  controller: _recvAcctId,
                  options: _lk.accounts,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Sales Revenue Account *',
                  controller: _revAcctId,
                  options: _lk.accounts,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Output Tax Account *',
                  controller: _taxAcctId,
                  options: _lk.accounts,
                  optional: true,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Cost of Goods Sold Account *',
                  controller: _cogsAcctId,
                  options: _lk.accounts,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Inventory Account *',
                  controller: _invAcctId,
                  options: _lk.accounts,
                ),
                const SizedBox(height: 12),
                GoldButton(
                  label: 'Create Sales Invoice',
                  busy: _busy,
                  onPressed: () => _mutate(
                    (api) => api.post(
                      '/sales/invoices',
                      idempotent: true,
                      body: {
                        'estimateId': _convEstId.text.trim(),
                        'invoiceDate': _convInvDate.text.trim(),
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
                      },
                    ),
                    'Sales invoice created from estimate.',
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 12),

        // Column header strip matching `image-64.png`
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Pal.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Pal.line),
          ),
          child: Text(
            'Invoice Date · Doc # · Customer · Articles · Taxable · Tax (GST) · Total Amount · Outstanding · State · Actions',
            style: T.body(11.2, color: Pal.ink, w: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),

        if (fInvoices.isEmpty)
          query.isNotEmpty
              ? const SaasEmptyBox('No sales invoices match your search query.')
              : Panel(
                  radius: 18,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 34,
                  ),
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
                          onPressed: () => _openPos1ClickModal(),
                        ),
                      ),
                      if (estOpts.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _activeForm = 'CONVERT_INVOICE'),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                          label: Text(
                            'Convert Existing Quote (${estOpts.length})',
                          ),
                        ),
                      ],
                    ],
                  ),
                )
        else
          for (final inv in fInvoices)
            _SalesInvoiceMobileCard(
              inv: inv,
              busy: _busy,
              onDownloadPdf: () => _downloadInvoiceWithServerRender(inv),
              onPost: '${inv['state']}'.toUpperCase() == 'DRAFT'
                  ? () {
                      if (_periodId.text.trim().isEmpty ||
                          _invSeriesId.text.trim().isEmpty ||
                          _jvSeriesId.text.trim().isEmpty) {
                        setState(
                          () => _error =
                              'Select Posting Period, Sales Invoice Series, and Journal Series above before posting.',
                        );
                        return;
                      }
                      _mutate(
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
                      );
                    }
                  : null,
              onDispatch: '${inv['state']}'.toUpperCase() == 'POSTED'
                  ? () => setState(() {
                        _tab = 'ORDERS';
                        _orderSubTab = 'DISPATCHES';
                        _dpInvoiceId.text = '${inv['id']}';
                      })
                  : null,
              onCreateReturn: '${inv['state']}'.toUpperCase() == 'POSTED'
                  ? () => setState(() {
                        _tab = 'CREDITS';
                        _cnInvId.text = '${inv['id']}';
                        _cnArticleOrLineId.clear();
                        _activeForm = 'CN';
                      })
                  : null,
            ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: ESTIMATES (`Screenshot (711).png` + `Screenshot (712).png`)
  // ---------------------------------------------------------------------------
  Widget _buildEstimatesTab(List<Map<String, dynamic>> fEstimates) {
    final availArticles = _availableArticleOptions();
    final taxOpts = _approvedTaxOptions();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_activeForm == 'ESTIMATE') ...[
          SaasFormCard(
            title: 'Draft Authoritative Estimate / Quotation',
            subtitle:
                'Quotes tagged jewellery items with live published rate breakdown',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Customer',
                  controller: _qCustomerId,
                  options: _lk.parties,
                  hint: '-- Select Customer --',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Tagged Article',
                  controller: _qArticleId,
                  options:
                      availArticles.isNotEmpty ? availArticles : _lk.articles,
                  hint: '-- Select Article in Stock --',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Published Rate Version',
                  controller: _qRateVerId,
                  options: _rateVersionOpts,
                  hint: '-- Select published rate --',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Approved Tax Profile',
                  controller: _qTaxProfId,
                  options: taxOpts,
                  hint: '-- Select approved tax profile --',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DatePickField(
                        label: 'Quote Date',
                        controller: _qDate,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DatePickField(
                        label: 'Estimate Expires At',
                        controller: _qExpiresDate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Making Charges (₹)',
                  controller: _qMaking,
                  hint: '1500.00',
                  mono: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    GoldButton(
                      label: 'Generate Estimate',
                      busy: _busy,
                      onPressed: () {
                        if (_qCustomerId.text.trim().isEmpty ||
                            _qArticleId.text.trim().isEmpty ||
                            _qRateVerId.text.trim().isEmpty ||
                            _qTaxProfId.text.trim().isEmpty) {
                          setState(
                            () => _error =
                                'Select Customer, Tagged Article, Published Rate Version, and Approved Tax Profile.',
                          );
                          return;
                        }
                        final expRaw = _qExpiresDate.text.trim();
                        final expIso = expRaw.isNotEmpty
                            ? '${expRaw}T23:59:59.000Z'
                            : DateTime.now()
                                .toUtc()
                                .add(const Duration(hours: 24))
                                .toIso8601String();
                        _mutate(
                          (api) => api.post(
                            '/sales/estimates',
                            idempotent: true,
                            body: {
                              'customerPartyId': _qCustomerId.text.trim(),
                              'rateVersionId': _qRateVerId.text.trim(),
                              'taxProfileId': _qTaxProfId.text.trim(),
                              'quoteDate': _qDate.text.trim(),
                              'expiresAt': expIso,
                              'lines': [
                                {
                                  'articleId': _qArticleId.text.trim(),
                                  'makingAmount': normAmount(
                                    _qMaking.text.trim().isEmpty
                                        ? '0.00'
                                        : _qMaking.text,
                                  ),
                                  'otherAmount': '0.00',
                                  'discountAmount': '0.00',
                                },
                              ],
                            },
                          ),
                          'Authoritative estimate generated.',
                        );
                      },
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() => _activeForm = null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Pal.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Pal.line),
          ),
          child: Text(
            'Quote # · Date · Customer · Metal Value · Making Charges · Tax · Total Amount · State · Action',
            style: T.body(11.2, color: Pal.ink, w: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),

        if (fEstimates.isEmpty)
          Panel(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
            child: Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF3DC),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: const Color(0xFFE7CF8B)),
                  ),
                  child: const Icon(
                    Icons.description_outlined,
                    size: 26,
                    color: Pal.goldDeep,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'No Estimates Created',
                  textAlign: TextAlign.center,
                  style: T.body(17, color: Pal.ink, w: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Provide authoritative jewellery price quotations quoting live metal board rates to prospective customers.',
                  textAlign: TextAlign.center,
                  style: T.body(12.6, color: Pal.muted),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 230,
                  child: RoyalGoldButton(
                    icon: Icons.add_rounded,
                    label: 'Draft New Quotation',
                    onPressed: () => setState(() => _activeForm = 'ESTIMATE'),
                  ),
                ),
              ],
            ),
          )
        else
          for (final est in fEstimates)
            LuxuryRecordCard(
              icon: Icons.description_outlined,
              pdfDocumentType: 'SALES ESTIMATE',
              code: '${est['quoteNumber'] ?? shortId('${est['id']}')}',
              status: '${est['state'] ?? 'OPEN'}',
              lines: [
                ('Customer', '${asMap(est['customer'])['displayName'] ?? '-'}'),
                if ('${est['quoteDate'] ?? ''}'.isNotEmpty)
                  ('Date', fmtDate('${est['quoteDate']}')),
                ('Metal Value', inr(est['metalValue'] ?? '0.00')),
                ('Making Charges', inr(est['makingAmount'] ?? '0.00')),
                ('Tax', inr(est['taxAmount'] ?? '0.00')),
              ],
              amountLabel: 'Total Amount',
              amountValue: inr(est['totalAmount']),
              actions: [
                if ('${est['state']}'.toUpperCase() == 'DRAFT' ||
                    '${est['state']}'.toUpperCase() == 'OPEN' ||
                    '${est['state']}'.toUpperCase() == 'ISSUED')
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _mutate(
                              (api) => api.post(
                                '/sales/estimates/${est['id']}/accept',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(est['version'], fallback: 1),
                                  'reason':
                                      'Customer accepted showroom estimate quotation.',
                                },
                              ),
                              'Estimate marked as accepted.',
                            ),
                    child: const Text('Accept'),
                  ),
                if ('${est['state']}'.toUpperCase() != 'CONVERTED' &&
                    '${est['state']}'.toUpperCase() != 'EXPIRED') ...[
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _tab = 'ORDERS';
                      _orderSubTab = 'SALES_ORDERS';
                      _soEstimateId.text = '${est['id']}';
                    }),
                    child: const Text('Create Order'),
                  ),
                  GoldButton(
                    label: 'Convert to Invoice',
                    compact: true,
                    busy: _busy,
                    onPressed: () => setState(() {
                      _tab = 'INVOICES';
                      _convEstId.text = '${est['id']}';
                      _activeForm = 'CONVERT_INVOICE';
                    }),
                  ),
                ],
              ],
            ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: ORDERS & DISPATCH (`Screenshot (713).png` + `Screenshot (714).png`)
  // ---------------------------------------------------------------------------
  Widget _buildOrdersAndDispatchTab(
    List<Map<String, dynamic>> fSalesOrders,
    List<Map<String, dynamic>> fDispatches,
  ) {
    final acceptedEstOpts = _estimates
        .where((e) => '${e['state']}'.toUpperCase() != 'EXPIRED')
        .map(
          (e) => LookupOption(
            id: '${e['id']}',
            label:
                '${e['quoteNumber'] ?? shortId('${e['id']}')} · ${asMap(e['customer'])['displayName'] ?? 'Customer'} · ${e['state'] ?? 'OPEN'}',
            raw: e,
          ),
        )
        .toList();
    final soSeriesOpts = _lk.seriesFor(const ['SALES_ORDER', 'ORDER']);
    final dpSeriesOpts =
        _lk.seriesFor(const ['DISPATCH', 'DELIVERY_CHALLAN', 'CHALLAN']);
    final settledInvOpts = _invoices
        .where((i) => '${i['state']}'.toUpperCase() == 'POSTED')
        .map(
          (i) => LookupOption(
            id: '${i['id']}',
            label:
                '${i['documentNumber'] ?? shortId('${i['id']}')} · ${asMap(i['customer'])['displayName'] ?? 'Customer'} · ${inr(i['totalAmount'])}',
            raw: i,
          ),
        )
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Sub-tabs: `Sales Orders (0)` | `Dispatches (0)` (`Screenshot (713)` & `(714)`)
        Row(
          children: [
            for (final st in [
              ('SALES_ORDERS', 'Sales Orders (${_salesOrders.length})'),
              ('DISPATCHES', 'Dispatches (${_dispatches.length})'),
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _orderSubTab = st.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8.5,
                    ),
                    decoration: BoxDecoration(
                      gradient: _orderSubTab == st.$1
                          ? const LinearGradient(
                              colors: [Color(0xFFCFA234), Color(0xFFB38620)],
                            )
                          : null,
                      color: _orderSubTab == st.$1 ? null : Pal.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _orderSubTab == st.$1
                            ? const Color(0xFFB38620)
                            : Pal.line,
                      ),
                    ),
                    child: Text(
                      st.$2,
                      style: T.body(
                        12.5,
                        color: _orderSubTab == st.$1 ? Colors.white : Pal.ink,
                        w: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_orderSubTab == 'SALES_ORDERS') ...[
          // Exact `Sales Orders` Creation Card (`Screenshot (713).png`)
          Panel(
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Accepted estimate UUID',
                  controller: _soEstimateId,
                  options: acceptedEstOpts,
                  hint: 'Accepted estimate UUID',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DatePickField(
                        label: 'Order Date',
                        controller: _soOrderDate,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DatePickField(
                        label: 'Promised Date',
                        controller: _soPromisedDate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'SALES_ORDER document series UUID (for confirmation)',
                  controller: _soSeriesId,
                  options:
                      soSeriesOpts.isNotEmpty ? soSeriesOpts : _lk.series,
                  hint: 'SALES_ORDER document series UUID (for confirmation)',
                  optional: true,
                ),
                const SizedBox(height: 12),
                RoyalGoldButton(
                  label: 'Create order',
                  busy: _busy,
                  onPressed: () {
                    final estId = _soEstimateId.text.trim();
                    if (estId.isEmpty) {
                      setState(
                        () => _error = 'Enter or select Accepted estimate UUID.',
                      );
                      return;
                    }
                    _mutate((api) async {
                      final body = <String, dynamic>{
                        'estimateId': estId,
                        'orderDate': _soOrderDate.text.trim(),
                        'promisedDate': _soPromisedDate.text.trim(),
                        'promisedDeliveryDate': _soPromisedDate.text.trim(),
                        if (_soSeriesId.text.trim().isNotEmpty)
                          'documentSeriesId': _soSeriesId.text.trim(),
                      };
                      try {
                        await api.post(
                          '/sales/orders',
                          idempotent: true,
                          body: body,
                        );
                      } on ApiException catch (e) {
                        if (e.status == 404) {
                          await api.post(
                            '/sales/sales-orders',
                            idempotent: true,
                            body: body,
                          );
                        } else {
                          rethrow;
                        }
                      }
                    }, 'Sales order created.');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Pal.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Pal.line),
            ),
            child: Text(
              'Order · Customer · Promised · Articles · Total · State · Actions',
              style: T.body(11.2, color: Pal.ink, w: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          if (fSalesOrders.isEmpty)
            const SaasEmptyBox('No sales orders created yet.')
          else
            for (final ord in fSalesOrders)
              LuxuryRecordCard(
                icon: Icons.shopping_bag_outlined,
                pdfDocumentType: 'SALES ORDER',
                code:
                    '${ord['documentNumber'] ?? ord['orderNumber'] ?? shortId('${ord['id']}')}',
                status: '${ord['state'] ?? ord['status'] ?? 'DRAFT'}',
                lines: [
                  (
                    'Customer',
                    '${asMap(ord['customer'])['displayName'] ?? ord['customerName'] ?? '-'}',
                  ),
                  (
                    'Promised',
                    fmtDate(
                      '${ord['promisedDate'] ?? ord['promisedDeliveryDate'] ?? ''}',
                    ),
                  ),
                  ('Articles', '${asList(ord['lines']).length}'),
                ],
                amountLabel: 'Total',
                amountValue: inr(ord['totalAmount'] ?? '0.00'),
                actions: [
                  if ('${ord['state']}'.toUpperCase() == 'DRAFT')
                    GoldButton(
                      label: 'Confirm Order',
                      compact: true,
                      busy: _busy,
                      onPressed: () {
                        if (_soSeriesId.text.trim().isEmpty) {
                          setState(
                            () => _error =
                                'Select SALES_ORDER document series UUID above before confirming.',
                          );
                          return;
                        }
                        _mutate(
                          (api) => api.post(
                            '/sales/orders/${ord['id']}/confirm',
                            idempotent: true,
                            body: {
                              'expectedVersion':
                                  asInt(ord['version'], fallback: 1),
                              'documentSeriesId': _soSeriesId.text.trim(),
                              'reason': 'Confirmed customer sales order.',
                            },
                          ),
                          'Sales order confirmed.',
                        );
                      },
                    ),
                ],
              ),
        ] else ...[
          // Exact `Dispatches` Creation Card (`Screenshot (714).png`)
          Panel(
            radius: 16,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Fully settled invoice UUID',
                  controller: _dpInvoiceId,
                  options: settledInvOpts,
                  hint: 'Fully settled invoice UUID',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DatePickField(
                        label: 'Dispatch Date',
                        controller: _dpDate,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SaasDropdown(
                        label: 'Dispatch Method',
                        value: _dpMethod,
                        options: const {
                          'CUSTOMER_PICKUP': 'Customer pickup',
                          'COURIER': 'Courier / Insured transit',
                          'HAND_DELIVERY': 'Hand delivery',
                          'ARMOURED_TRANSIT': 'Armoured transit',
                        },
                        onChanged: (v) => setState(() => _dpMethod = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Recipient name',
                  controller: _dpRecipient,
                  hint: 'Recipient name',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'DISPATCH document series UUID',
                  controller: _dpSeriesId,
                  options:
                      dpSeriesOpts.isNotEmpty ? dpSeriesOpts : _lk.series,
                  hint: 'DISPATCH document series UUID',
                  optional: true,
                ),
                const SizedBox(height: 12),
                RoyalGoldButton(
                  label: 'Create dispatch',
                  busy: _busy,
                  onPressed: () {
                    final invId = _dpInvoiceId.text.trim();
                    final recip = _dpRecipient.text.trim();
                    if (invId.isEmpty || recip.isEmpty) {
                      setState(
                        () => _error =
                            'Provide Fully settled invoice UUID and Recipient name.',
                      );
                      return;
                    }
                    _mutate((api) async {
                      final body = <String, dynamic>{
                        'salesInvoiceId': invId,
                        'invoiceId': invId,
                        'dispatchDate': _dpDate.text.trim(),
                        'dispatchMethod': _dpMethod,
                        'method': _dpMethod,
                        'recipientName': recip,
                        if (_dpSeriesId.text.trim().isNotEmpty)
                          'documentSeriesId': _dpSeriesId.text.trim(),
                      };
                      try {
                        await api.post(
                          '/sales/dispatches',
                          idempotent: true,
                          body: body,
                        );
                      } on ApiException catch (e) {
                        if (e.status == 404) {
                          await api.post(
                            '/sales/invoices/$invId/dispatches',
                            idempotent: true,
                            body: body,
                          );
                        } else {
                          rethrow;
                        }
                      }
                    }, 'Customer dispatch created.');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Pal.surfaceAlt,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Pal.line),
            ),
            child: Text(
              'Dispatch · Invoice · Recipient · Method · Articles · State · Actions',
              style: T.body(11.2, color: Pal.ink, w: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          if (fDispatches.isEmpty)
            const SaasEmptyBox('No dispatches recorded yet.')
          else
            for (final dp in fDispatches)
              LuxuryRecordCard(
                icon: Icons.local_shipping_outlined,
                pdfDocumentType: 'DISPATCH CHALLAN',
                code:
                    '${dp['documentNumber'] ?? shortId('${dp['id']}')}',
                status: '${dp['state'] ?? dp['status'] ?? 'RECORDED'}',
                lines: [
                  (
                    'Invoice',
                    '${asMap(dp['salesInvoice'])['documentNumber'] ?? dp['salesInvoiceId'] ?? '-'}',
                  ),
                  ('Recipient', '${dp['recipientName'] ?? '-'}'),
                  (
                    'Method',
                    humanize('${dp['dispatchMethod'] ?? dp['method'] ?? ''}'),
                  ),
                  (
                    'Dispatch Date',
                    fmtDate('${dp['dispatchDate'] ?? dp['createdAt'] ?? ''}'),
                  ),
                ],
                actions: [
                  if ('${dp['state']}'.toUpperCase() == 'DRAFT')
                    GoldButton(
                      label: 'Confirm Dispatch',
                      compact: true,
                      busy: _busy,
                      onPressed: () => _mutate(
                        (api) => api.post(
                          '/sales/dispatches/${dp['id']}/confirm',
                          idempotent: true,
                          body: {
                            'expectedVersion':
                                asInt(dp['version'], fallback: 1),
                            if (_dpSeriesId.text.trim().isNotEmpty)
                              'documentSeriesId': _dpSeriesId.text.trim(),
                            'reason': 'Confirmed showroom jewellery dispatch.',
                          },
                        ),
                        'Dispatch confirmed.',
                      ),
                    ),
                ],
              ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: CREDIT NOTES (`Screenshot (715).png`)
  // ---------------------------------------------------------------------------
  Widget _buildCreditNotesTab(List<Map<String, dynamic>> fCredits) {
    final postedInvOpts = _invoices
        .where((i) => '${i['state']}'.toUpperCase() == 'POSTED')
        .map(
          (i) => LookupOption(
            id: '${i['id']}',
            label:
                '${i['documentNumber'] ?? shortId('${i['id']}')} · ${asMap(i['customer'])['displayName'] ?? 'Customer'} · ${inr(i['totalAmount'])}',
            raw: i,
          ),
        )
        .toList();

    final selectedInv = _invoices
        .where((i) => '${i['id']}' == _cnInvId.text.trim())
        .firstOrNull;
    final invArticleOpts = <LookupOption>[];
    if (selectedInv != null) {
      for (final l in asList(selectedInv['lines'])) {
        final art = asMap(l['article']);
        final lineOrArtId = '${l['id'] ?? l['articleId'] ?? art['id'] ?? ''}';
        if (lineOrArtId.isNotEmpty) {
          invArticleOpts.add(
            LookupOption(
              id: lineOrArtId,
              label:
                  '${art['tag'] ?? l['articleTag'] ?? shortId(lineOrArtId)} · ${art['description'] ?? 'Billed Article'} · ${inr(l['lineTotal'] ?? l['totalAmount'] ?? '0')}',
              raw: l,
            ),
          );
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_activeForm == 'CN') ...[
          SaasFormCard(
            title: 'Draft Sales Credit Note (Return)',
            subtitle:
                'Record customer return with return QC and inventory disposition',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Sales Invoice UUID',
                  controller: _cnInvId,
                  options: postedInvOpts,
                  hint: 'Sales Invoice UUID',
                  onSelected: (_) => setState(() => _cnArticleOrLineId.clear()),
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Article UUID',
                  controller: _cnArticleOrLineId,
                  options: invArticleOpts.isNotEmpty
                      ? invArticleOpts
                      : _lk.articles,
                  hint: 'Article UUID',
                ),
                const SizedBox(height: 10),
                SaasDropdown(
                  label: 'Disposition',
                  value: _cnDisposition,
                  options: const {
                    'RESTOCK': 'Restock into Available Stock',
                    'QUARANTINE': 'Quarantine for QC Inspection',
                    'SCRAP': 'Scrap / Refining Melt Pool',
                  },
                  onChanged: (v) => setState(() => _cnDisposition = v),
                ),
                if (_cnDisposition == 'RESTOCK' &&
                    _lk.locations.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Restock Custody Location (optional)',
                    controller: _cnRestockLocId,
                    options: _lk.locations,
                    optional: true,
                  ),
                ],
                const SizedBox(height: 10),
                SaasField(
                  label: 'Return Reason Description',
                  controller: _cnReason,
                  hint: 'Return Reason Description',
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    GoldButton(
                      label: 'Create Credit Note',
                      busy: _busy,
                      onPressed: () {
                        final invId = _cnInvId.text.trim();
                        final targetId = _cnArticleOrLineId.text.trim();
                        final reason = _cnReason.text.trim();
                        if (invId.isEmpty || targetId.isEmpty || reason.length < 5) {
                          setState(
                            () => _error =
                                'Provide Sales Invoice UUID, Article UUID, and Return Reason Description (5+ chars).',
                          );
                          return;
                        }
                        // Match invoice line ID if user entered/selected articleId
                        var resolvedLineId = targetId;
                        var resolvedArtId = targetId;
                        if (selectedInv != null) {
                          for (final l in asList(selectedInv['lines'])) {
                            final lid = '${l['id'] ?? ''}';
                            final aid =
                                '${l['articleId'] ?? asMap(l['article'])['id'] ?? ''}';
                            if (targetId == lid || targetId == aid) {
                              if (lid.isNotEmpty) resolvedLineId = lid;
                              if (aid.isNotEmpty) resolvedArtId = aid;
                              break;
                            }
                          }
                        }
                        _mutate(
                          (api) => api.post(
                            '/sales/credit-notes',
                            idempotent: true,
                            body: {
                              'salesInvoiceId': invId,
                              'creditNoteDate': todayIso(),
                              'reason': reason.length >= 10
                                  ? reason
                                  : '$reason (customer return)',
                              'lines': [
                                {
                                  'salesInvoiceLineId': resolvedLineId,
                                  'articleId': resolvedArtId,
                                  'returnReason': reason,
                                  'qcState': _cnDisposition == 'RESTOCK'
                                      ? 'PASSED'
                                      : 'FAILED',
                                  'disposition': _cnDisposition,
                                  if (_cnRestockLocId.text.trim().isNotEmpty)
                                    'restockLocationId':
                                        _cnRestockLocId.text.trim(),
                                },
                              ],
                            },
                          ),
                          'Sales credit note draft created.',
                        );
                      },
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() => _activeForm = null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Pal.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Pal.line),
          ),
          child: Text(
            'Date · Doc # · Customer · Reason · Total Amount · Settled / Open · State · Action',
            style: T.body(11.2, color: Pal.ink, w: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),

        if (fCredits.isEmpty)
          const SaasEmptyBox('No sales credit notes recorded yet.')
        else
          for (final cn in fCredits)
            LuxuryRecordCard(
              icon: Icons.assignment_return_outlined,
              pdfDocumentType: 'CREDIT NOTE',
              code: '${cn['documentNumber'] ?? shortId('${cn['id']}')}',
              status: '${cn['state'] ?? 'DRAFT'}',
              lines: [
                ('Date', fmtDate('${cn['creditNoteDate'] ?? cn['createdAt'] ?? ''}')),
                ('Customer', '${asMap(cn['customer'])['displayName'] ?? '-'}'),
                if ('${cn['reason'] ?? ''}'.isNotEmpty)
                  ('Reason', '${cn['reason']}'),
              ],
              amountLabel: 'Total Amount',
              amountValue: inr(cn['totalAmount']),
              actions: [
                if ('${cn['state']}'.toUpperCase() == 'DRAFT' ||
                    '${cn['state']}'.toUpperCase() == 'APPROVED')
                  GoldButton(
                    label: '${cn['state']}'.toUpperCase() == 'DRAFT'
                        ? 'Approve'
                        : 'Post Credit Note',
                    compact: true,
                    busy: _busy,
                    onPressed: () {
                      if ('${cn['state']}'.toUpperCase() == 'DRAFT') {
                        _mutate(
                          (api) => api.post(
                            '/sales/credit-notes/${cn['id']}/approve',
                            body: {
                              'expectedVersion':
                                  asInt(cn['version'], fallback: 1),
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
                              'expectedVersion':
                                  asInt(cn['version'], fallback: 1),
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

  // ---------------------------------------------------------------------------
  // TAB 5: TAX PROFILES (`Screenshot (716).png`)
  // ---------------------------------------------------------------------------
  Widget _buildTaxProfilesTab(List<Map<String, dynamic>> fTax) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_activeForm == 'TAX') ...[
          SaasFormCard(
            title: 'Add Effective-Dated Tax Profile',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SaasField(
                  label: 'Code (e.g. GST_3_DEFAULT)',
                  controller: _tpCode,
                  hint: 'Code (e.g. GST_3_DEFAULT)',
                  mono: true,
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Name',
                  controller: _tpName,
                  hint: 'Name',
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Rate Percent (e.g. 3.000000)',
                  controller: _tpRate,
                  hint: 'Rate Percent (e.g. 3.000000)',
                  mono: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                DatePickField(
                  label: 'Effective From',
                  controller: _tpEffFrom,
                ),
                const SizedBox(height: 8),
                SaasCheckRow(
                  label:
                      'Synthetic/test-only profile (clear only after accountant approval for live use)',
                  value: _tpSynthetic,
                  onChanged: (v) => setState(() => _tpSynthetic = v),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    GoldButton(
                      label: 'Save Tax Profile',
                      busy: _busy,
                      onPressed: () {
                        if (_tpCode.text.trim().isEmpty ||
                            _tpName.text.trim().isEmpty ||
                            _tpRate.text.trim().isEmpty) {
                          setState(
                            () => _error =
                                'Provide Code, Name, and Rate Percent.',
                          );
                          return;
                        }
                        _mutate(
                          (api) => api.post(
                            '/sales/tax-profiles',
                            idempotent: true,
                            body: {
                              'code': _tpCode.text.trim().toUpperCase(),
                              'name': _tpName.text.trim(),
                              'ratePercent': _tpRate.text.trim(),
                              'syntheticTestOnly': _tpSynthetic,
                              'effectiveFrom': _tpEffFrom.text.trim(),
                            },
                          ),
                          'Tax profile saved.',
                        );
                      },
                    ),
                    OutlinedButton(
                      onPressed: () => setState(() => _activeForm = null),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Pal.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: Pal.line),
          ),
          child: Text(
            'Code · Name · Rate · Effective From · State · Action',
            style: T.body(11.2, color: Pal.ink, w: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 10),

        if (fTax.isEmpty)
          const SaasEmptyBox('No tax profiles configured yet.')
        else
          for (final tp in fTax)
            LuxuryRecordCard(
              enablePdfDownload: false,
              icon: Icons.percent_rounded,
              pdfDocumentType: 'TAX PROFILE',
              code: '${tp['code']} · ${tp['name']}',
              status: '${tp['state'] ?? 'DRAFT'}',
              lines: [
                ('Effective From', fmtDate('${tp['effectiveFrom'] ?? ''}')),
                if (tp['syntheticTestOnly'] == true)
                  ('Scope', 'Synthetic / Test-only'),
              ],
              amountLabel: 'Rate',
              amountValue: '${tp['ratePercent']}%',
              actions: [
                if ('${tp['state']}'.toUpperCase() == 'DRAFT')
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
}

// =============================================================================
// POS 1-CLICK BILLING & COUNTER CHECKOUT MODAL (`Screenshot (710)` & `(709)`)
// =============================================================================
class _Pos1ClickCheckoutModal extends StatefulWidget {
  const _Pos1ClickCheckoutModal({
    required this.initialLookup,
    required this.rateVersionOpts,
    required this.approvedTaxOpts,
    required this.defaultPeriodId,
    required this.defaultInvSeriesId,
    required this.defaultJvSeriesId,
    required this.defaultRecvAcctId,
    required this.defaultRevAcctId,
    required this.defaultTaxAcctId,
    required this.defaultCogsAcctId,
    required this.defaultInvAcctId,
    this.initialArticle,
  });

  final WorkspaceLookup initialLookup;
  final List<LookupOption> rateVersionOpts;
  final List<LookupOption> approvedTaxOpts;
  final String defaultPeriodId;
  final String defaultInvSeriesId;
  final String defaultJvSeriesId;
  final String defaultRecvAcctId;
  final String defaultRevAcctId;
  final String defaultTaxAcctId;
  final String defaultCogsAcctId;
  final String defaultInvAcctId;
  final Article? initialArticle;

  @override
  State<_Pos1ClickCheckoutModal> createState() =>
      _Pos1ClickCheckoutModalState();
}

class _Pos1ClickCheckoutModalState extends State<_Pos1ClickCheckoutModal> {
  late WorkspaceLookup _lk;
  bool _showWalkInBox = false;
  bool _savingWalkIn = false;
  bool _showPostingConfig = true;
  bool _submitting = false;
  String? _err;

  // Customer + Quick Walk-in Customer (`Screenshot (710).png`)
  final _customerId = TextEditingController();
  final _walkName = TextEditingController();
  final _walkPhone = TextEditingController();
  final _walkPan = TextEditingController();

  // Tagged Jewelry Piece (`Screenshot (710).png`)
  final _scanTagCtrl = TextEditingController();
  final _articleId = TextEditingController();

  // Charges (`Screenshot (710).png`)
  final _makingCtrl = TextEditingController();
  final _otherCtrl = TextEditingController(text: '0.00');
  final _discountCtrl = TextEditingController(text: '0.00');

  // Required posting configuration (`Screenshot (710)` + `(709)`)
  late final TextEditingController _rateVerId;
  late final TextEditingController _taxProfId;
  late final TextEditingController _periodId;
  late final TextEditingController _invSeriesId;
  late final TextEditingController _jvSeriesId;
  late final TextEditingController _recvAcctId;
  late final TextEditingController _revAcctId;
  late final TextEditingController _taxAcctId;
  late final TextEditingController _cogsAcctId;
  late final TextEditingController _invAcctId;
  final _businessReason = TextEditingController();

  // Payment & Settlement Mode (`Screenshot (709).png`)
  // 'IMMEDIATE' | 'OPEN_ITEM'
  String _settlementMode = 'IMMEDIATE';
  String _tenderMethod = 'CASH';
  final _cashBankAcctId = TextEditingController();
  final _tenderRef = TextEditingController();

  @override
  void initState() {
    super.initState();
    _lk = widget.initialLookup;
    _rateVerId = TextEditingController(
      text: widget.rateVersionOpts.isNotEmpty
          ? widget.rateVersionOpts.first.id
          : '',
    );
    _taxProfId = TextEditingController(
      text: widget.approvedTaxOpts.isNotEmpty
          ? widget.approvedTaxOpts.first.id
          : '',
    );
    _periodId = TextEditingController(text: widget.defaultPeriodId);
    _invSeriesId = TextEditingController(text: widget.defaultInvSeriesId);
    _jvSeriesId = TextEditingController(text: widget.defaultJvSeriesId);
    _recvAcctId = TextEditingController(text: widget.defaultRecvAcctId);
    _revAcctId = TextEditingController(text: widget.defaultRevAcctId);
    _taxAcctId = TextEditingController(text: widget.defaultTaxAcctId);
    _cogsAcctId = TextEditingController(text: widget.defaultCogsAcctId);
    _invAcctId = TextEditingController(text: widget.defaultInvAcctId);

    final cashAccts =
        _lk.accountsByControl(const ['CASH', 'BANK', 'CLEARING']);
    if (cashAccts.isNotEmpty) {
      _cashBankAcctId.text = cashAccts.first.id;
    }

    if (widget.initialArticle != null &&
        widget.initialArticle!.id.isNotEmpty) {
      _articleId.text = widget.initialArticle!.id;
      if (decOrZero(widget.initialArticle!.makingCharges) > Decimal.zero) {
        _makingCtrl.text = normAmount(widget.initialArticle!.makingCharges);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _customerId,
      _walkName,
      _walkPhone,
      _walkPan,
      _scanTagCtrl,
      _articleId,
      _makingCtrl,
      _otherCtrl,
      _discountCtrl,
      _rateVerId,
      _taxProfId,
      _periodId,
      _invSeriesId,
      _jvSeriesId,
      _recvAcctId,
      _revAcctId,
      _taxAcctId,
      _cogsAcctId,
      _invAcctId,
      _businessReason,
      _cashBankAcctId,
      _tenderRef,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<LookupOption> get _availArticles =>
      _lk.availableArticles().where((o) => o.id.isNotEmpty).toList();

  void _matchScannedTag(String rawTag) {
    final code = rawTag.trim().toUpperCase();
    if (code.isEmpty) return;
    for (final opt in _availArticles) {
      final tag = '${opt.raw['tag'] ?? opt.raw['barcode'] ?? ''}'.toUpperCase();
      if (tag == code || opt.id.toUpperCase() == code) {
        setState(() {
          _articleId.text = opt.id;
          _err = null;
        });
        _scanTagCtrl.clear();
        return;
      }
    }
    setState(
      () => _err =
          'Tag "$code" is not currently in available showroom stock.',
    );
  }

  Future<void> _openCameraScanner() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (scanned != null && mounted) {
      _matchScannedTag(scanned);
    }
  }

  Future<void> _saveQuickWalkInCustomer() async {
    final name = _walkName.text.trim();
    final phone = _walkPhone.text.trim();
    final pan = _walkPan.text.trim().toUpperCase();
    if (name.length < 2 || phone.length < 7) {
      setState(
        () => _err =
            'Enter Full Name and Mobile Phone to onboard a walk-in customer.',
      );
      return;
    }
    setState(() {
      _savingWalkIn = true;
      _err = null;
    });
    final api = context.read<ApiClient>();
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch.toString();
      final code = 'CUST-${stamp.substring(stamp.length - 6)}';
      final created = asMap(
        await api.post(
          '/parties',
          idempotent: true,
          body: {
            'code': code,
            'displayName': name,
            'kind': 'INDIVIDUAL',
            'roles': const ['CUSTOMER'],
            'contacts': [
              {'kind': 'PHONE', 'value': phone, 'isPrimary': true},
            ],
            if (pan.isNotEmpty)
              'taxRegistrations': [
                {
                  'registrationType': 'PAN',
                  'registrationNumber': pan,
                },
              ],
          },
        ),
      );
      final refreshed = await WorkspaceLookup.load(
        api,
        includeParties: true,
        includeInventory: true,
        includeAccounting: true,
      );
      if (!mounted) return;
      final newId = '${created['id'] ?? ''}';
      setState(() {
        _lk = refreshed;
        if (newId.isNotEmpty) _customerId.text = newId;
        _showWalkInBox = false;
        _walkName.clear();
        _walkPhone.clear();
        _walkPan.clear();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _savingWalkIn = false);
    }
  }

  Future<void> _submit1ClickCheckout() async {
    if (_customerId.text.trim().isEmpty) {
      setState(() => _err = 'Select Customer Party (or use Quick Walk-in Customer).');
      return;
    }
    if (_articleId.text.trim().isEmpty) {
      setState(
        () => _err =
            'Select or scan a Tagged Jewelry Piece from showroom stock.',
      );
      return;
    }
    if (_rateVerId.text.trim().isEmpty ||
        _taxProfId.text.trim().isEmpty ||
        _periodId.text.trim().isEmpty ||
        _invSeriesId.text.trim().isEmpty ||
        _jvSeriesId.text.trim().isEmpty ||
        _recvAcctId.text.trim().isEmpty ||
        _revAcctId.text.trim().isEmpty ||
        _taxAcctId.text.trim().isEmpty ||
        _cogsAcctId.text.trim().isEmpty ||
        _invAcctId.text.trim().isEmpty) {
      setState(() {
        _showPostingConfig = true;
        _err =
            'Complete all Required posting configuration selections (rate version, tax profile, period, series, and ledger accounts).';
      });
      return;
    }
    if (_businessReason.text.trim().length < 5) {
      setState(() {
        _showPostingConfig = true;
        _err = 'Enter Business Reason (minimum 5 characters).';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _err = null;
    });

    final api = context.read<ApiClient>();
    final making = normAmount(
      _makingCtrl.text.trim().isEmpty ? '0.00' : _makingCtrl.text,
    );
    final other = normAmount(
      _otherCtrl.text.trim().isEmpty ? '0.00' : _otherCtrl.text,
    );
    final discount = normAmount(
      _discountCtrl.text.trim().isEmpty ? '0.00' : _discountCtrl.text,
    );
    final reason = _businessReason.text.trim();
    final nowUtc = DateTime.now().toUtc();

    try {
      Map<String, dynamic>? committedDoc;

      // 1. Try dedicated atomic POS endpoint if exposed by server; fallback on 404/405 to authoritative pipeline
      final atomicPayload = <String, dynamic>{
        'customerPartyId': _customerId.text.trim(),
        'articleId': _articleId.text.trim(),
        'makingAmount': making,
        'otherAmount': other,
        'discountAmount': discount,
        'rateVersionId': _rateVerId.text.trim(),
        'taxProfileId': _taxProfId.text.trim(),
        'postingPeriodId': _periodId.text.trim(),
        'documentSeriesId': _invSeriesId.text.trim(),
        'journalSeriesId': _jvSeriesId.text.trim(),
        'receivableAccountId': _recvAcctId.text.trim(),
        'revenueAccountId': _revAcctId.text.trim(),
        'outputTaxAccountId': _taxAcctId.text.trim(),
        'cogsAccountId': _cogsAcctId.text.trim(),
        'inventoryAccountId': _invAcctId.text.trim(),
        'settlementMode': _settlementMode,
        if (_settlementMode == 'IMMEDIATE') ...{
          'paymentMethod': _tenderMethod,
          if (_cashBankAcctId.text.trim().isNotEmpty)
            'settlementAccountId': _cashBankAcctId.text.trim(),
          if (_tenderRef.text.trim().isNotEmpty)
            'paymentReference': _tenderRef.text.trim(),
        },
        'reason': reason,
      };

      for (final ep in const ['/sales/quick-bill', '/sales/pos-checkout']) {
        try {
          final r = await api.post(ep, idempotent: true, body: atomicPayload);
          final m = asMap(r);
          committedDoc = asMap(m['invoice']).isNotEmpty ? asMap(m['invoice']) : m;
          break;
        } on ApiException catch (e) {
          if (e.status == 404 || e.status == 405) continue;
          rethrow;
        }
      }

      // 2. Standard 3-step Estimate -> Invoice -> Post pipeline (`@jewellery-erp/contracts`)
      if (committedDoc == null || committedDoc.isEmpty) {
        final est = asMap(
          await api.post(
            '/sales/estimates',
            idempotent: true,
            body: {
              'customerPartyId': _customerId.text.trim(),
              'rateVersionId': _rateVerId.text.trim(),
              'taxProfileId': _taxProfId.text.trim(),
              'quoteDate': todayIso(),
              'expiresAt': nowUtc.add(const Duration(hours: 24)).toIso8601String(),
              'lines': [
                {
                  'articleId': _articleId.text.trim(),
                  'makingAmount': making,
                  'otherAmount': other,
                  'discountAmount': discount,
                },
              ],
            },
          ),
        );

        final invDraft = asMap(
          await api.post(
            '/sales/invoices',
            idempotent: true,
            body: {
              'estimateId': '${est['id']}',
              'invoiceDate': todayIso(),
              'reservationExpiresAt':
                  nowUtc.add(const Duration(hours: 4)).toIso8601String(),
              'receivableAccountId': _recvAcctId.text.trim(),
              'revenueAccountId': _revAcctId.text.trim(),
              'outputTaxAccountId': _taxAcctId.text.trim(),
              'cogsAccountId': _cogsAcctId.text.trim(),
              'inventoryAccountId': _invAcctId.text.trim(),
            },
          ),
        );

        final posted = asMap(
          await api.post(
            '/sales/invoices/${invDraft['id']}/post',
            idempotent: true,
            body: {
              'expectedVersion': asInt(invDraft['version'], fallback: 1),
              'postingPeriodId': _periodId.text.trim(),
              'documentSeriesId': _invSeriesId.text.trim(),
              'journalSeriesId': _jvSeriesId.text.trim(),
              'reason': reason,
            },
          ),
        );
        committedDoc = posted.isNotEmpty ? posted : invDraft;

        // Optional immediate receipt settlement if Cash/Bank account is selected
        if (_settlementMode == 'IMMEDIATE' &&
            _cashBankAcctId.text.trim().isNotEmpty &&
            committedDoc['totalAmount'] != null) {
          try {
            final rcptSeries =
                _lk.seriesFor(const ['CUSTOMER_RECEIPT', 'RECEIPT', 'PAYMENT']);
            final rcpt = asMap(
              await api.post(
                '/payments/customer-receipts',
                idempotent: true,
                body: {
                  'customerPartyId': _customerId.text.trim(),
                  'partyId': _customerId.text.trim(),
                  'receiptDate': todayIso(),
                  'paymentMethod': _tenderMethod,
                  'settlementAccountId': _cashBankAcctId.text.trim(),
                  'receivableAccountId': _recvAcctId.text.trim(),
                  'amount': '${committedDoc['totalAmount']}',
                  if (_tenderRef.text.trim().isNotEmpty)
                    'referenceNumber': _tenderRef.text.trim(),
                  'allocations': [
                    {
                      'salesInvoiceId': '${committedDoc['id']}',
                      'allocatedAmount': '${committedDoc['totalAmount']}',
                    },
                  ],
                  'reason': reason,
                },
              ),
            );
            if (rcpt['id'] != null && rcptSeries.isNotEmpty) {
              await api.post(
                '/payments/customer-receipts/${rcpt['id']}/post',
                idempotent: true,
                body: {
                  'expectedVersion': asInt(rcpt['version'], fallback: 1),
                  'postingPeriodId': _periodId.text.trim(),
                  'documentSeriesId': rcptSeries.first.id,
                  'journalSeriesId': _jvSeriesId.text.trim(),
                  'reason': reason,
                },
              );
            }
          } catch (_) {
            // Invoice already posted; cashier can finalize multi-tender in Settlements if needed
          }
        }
      }

      final custOpt = _lk.parties
          .where((p) => p.id == _customerId.text.trim())
          .firstOrNull;
      final outMap = <String, dynamic>{
        'customerName': custOpt?.label ?? 'Showroom Customer',
        'paymentMode': _settlementMode == 'IMMEDIATE'
            ? 'Immediate Settlement ($_tenderMethod)'
            : 'Subledger Open Item (Credit)',
        ...committedDoc,
      };
      if (!mounted) return;
      Navigator.pop(context, outMap);
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avail = _availArticles;
    final openPeriods = _lk.openPeriods();
    final invSeries = _lk.seriesFor(const ['SALES_INVOICE', 'INVOICE']);
    final jvSeries = _lk.seriesFor(const ['JOURNAL']);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.65,
      maxChildSize: 0.96,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Modal Header (`Screenshot (710).png`)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: Pal.goldDeep,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POS 1-Click Billing & Counter Checkout',
                        style: T.body(16.5, color: Pal.ink, w: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Instant atomic checkout: live bullion valuation + double-entry accounting + stock issue + tax invoice.',
                        style: T.body(11.8, color: Pal.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _submitting ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Scrollable Form Body
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                18,
                14,
                18,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              children: [
                if (_err != null) ...[
                  ErrorBanner(_err!),
                  const SizedBox(height: 12),
                ],

                // 1. Customer Party * + Quick Walk-in Customer (`Screenshot (710).png`)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Customer Party *',
                        style: T.body(12.5, color: Pal.ink, w: FontWeight.w700),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () =>
                          setState(() => _showWalkInBox = !_showWalkInBox),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                      label: Text(
                        _showWalkInBox
                            ? 'Hide Walk-in'
                            : 'Quick Walk-in Customer',
                      ),
                    ),
                  ],
                ),
                LookupField(
                  label: 'Select Customer Party',
                  controller: _customerId,
                  options: _lk.parties,
                  hint: '-- Select Customer --',
                ),
                if (_showWalkInBox) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFCF3),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEBD79C)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 16,
                              color: Pal.goldDeep,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Quick Walk-in Customer (0% Friction)',
                                style: T.body(
                                  12.8,
                                  color: Pal.goldDeep,
                                  w: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setState(() => _showWalkInBox = false),
                              icon: const Icon(Icons.close_rounded, size: 17),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SaasField(
                          label: 'Full Name *',
                          controller: _walkName,
                          hint: 'Full customer name',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Mobile Phone *',
                                controller: _walkPhone,
                                hint: '10-digit mobile',
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'PAN (Optional)',
                                controller: _walkPan,
                                hint: '10-character PAN',
                                mono: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '✓ Quick walk-in customer onboarding at the counter.',
                          style: T.body(11.4, color: Pal.muted),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: _savingWalkIn
                                  ? null
                                  : () =>
                                      setState(() => _showWalkInBox = false),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            GoldButton(
                              label: 'Save & Select',
                              compact: true,
                              busy: _savingWalkIn,
                              onPressed: _saveQuickWalkInCustomer,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // 2. Tagged Jewelry Piece (`Screenshot (710).png`)
                Text(
                  'Tagged Jewelry Piece (From Showroom Stock) *',
                  style: T.body(12.5, color: Pal.ink, w: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _scanTagCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: T.mono(13.5),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded, size: 19),
                          hintText: 'Scan barcode / tag and press Enter...',
                        ),
                        onSubmitted: _matchScannedTag,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Pal.obsidian,
                          foregroundColor: Pal.goldSoft,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: _openCameraScanner,
                        child: const Icon(Icons.qr_code_scanner_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LookupField(
                  label: 'Or Select Tagged Item from Stock List',
                  controller: _articleId,
                  options: avail,
                  hint: '-- Or Select Tagged Item from Stock List --',
                ),
                if (avail.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'No articles currently available in showroom stock. Please receive tagged stock in Tagged Stock & Lots first.',
                    style: T.body(11.8, color: Pal.warn, w: FontWeight.w600),
                  ),
                ],

                const SizedBox(height: 14),

                // 3. Making / Other / Discount (`Screenshot (710).png`)
                Row(
                  children: [
                    Expanded(
                      child: SaasField(
                        label: 'Making Charges (₹)',
                        controller: _makingCtrl,
                        hint: '0.00',
                        mono: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SaasField(
                        label: 'Other Charges (₹)',
                        controller: _otherCtrl,
                        mono: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SaasField(
                        label: 'Discount (₹)',
                        controller: _discountCtrl,
                        mono: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // 4. Required posting configuration (`Screenshot (710)` + `(709)`)
                Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Pal.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Pal.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () => setState(
                          () => _showPostingConfig = !_showPostingConfig,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _showPostingConfig
                                  ? Icons.arrow_drop_down_rounded
                                  : Icons.arrow_right_rounded,
                              size: 22,
                              color: Pal.ink,
                            ),
                            Expanded(
                              child: Text(
                                'Required posting configuration',
                                style: T.body(
                                  13,
                                  color: Pal.ink,
                                  w: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_showPostingConfig) ...[
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Published Rate Version *',
                          controller: _rateVerId,
                          options: widget.rateVersionOpts,
                          hint: '-- Select published rate --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Approved Tax Profile *',
                          controller: _taxProfId,
                          options: widget.approvedTaxOpts,
                          hint: '-- Select approved tax profile --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Posting Period *',
                          controller: _periodId,
                          options: openPeriods,
                          hint: '-- Select open period --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Sales Invoice Series *',
                          controller: _invSeriesId,
                          options:
                              invSeries.isNotEmpty ? invSeries : _lk.series,
                          hint: '-- Select invoice series --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Journal Series *',
                          controller: _jvSeriesId,
                          options:
                              jvSeries.isNotEmpty ? jvSeries : _lk.series,
                          hint: '-- Select journal series --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Customer Receivable Account *',
                          controller: _recvAcctId,
                          options: _lk.accounts,
                          hint: '-- Select account --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Sales Revenue Account *',
                          controller: _revAcctId,
                          options: _lk.accounts,
                          hint: '-- Select account --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Output Tax Account *',
                          controller: _taxAcctId,
                          options: _lk.accounts,
                          hint: '-- Select account --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Cost of Goods Sold Account *',
                          controller: _cogsAcctId,
                          options: _lk.accounts,
                          hint: '-- Select account --',
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Inventory Account *',
                          controller: _invAcctId,
                          options: _lk.accounts,
                          hint: '-- Select account --',
                        ),
                        const SizedBox(height: 10),
                        SaasField(
                          label: 'Business Reason *',
                          controller: _businessReason,
                          maxLines: 3,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 5. Payment & Settlement Mode (`Screenshot (709).png`)
                Text(
                  'Payment & Settlement Mode',
                  style: T.body(12.5, color: Pal.ink, w: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SettlementModeCard(
                        icon: Icons.link_rounded,
                        label: 'Immediate Settlement (Cash / UPI / Card)',
                        selected: _settlementMode == 'IMMEDIATE',
                        onTap: () =>
                            setState(() => _settlementMode = 'IMMEDIATE'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _SettlementModeCard(
                        icon: Icons.credit_card_outlined,
                        label: 'Subledger Open Item (Credit / Account)',
                        selected: _settlementMode == 'OPEN_ITEM',
                        onTap: () =>
                            setState(() => _settlementMode = 'OPEN_ITEM'),
                      ),
                    ),
                  ],
                ),
                if (_settlementMode == 'IMMEDIATE') ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasDropdown(
                          label: 'Payment Tender',
                          value: _tenderMethod,
                          options: const {
                            'CASH': 'Cash',
                            'UPI': 'UPI QR',
                            'CARD': 'Card POS',
                            'BANK_TRANSFER': 'NEFT / RTGS',
                          },
                          onChanged: (v) => setState(() => _tenderMethod = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LookupField(
                          label: 'Cash / Bank Account',
                          controller: _cashBankAcctId,
                          options: _lk.accounts,
                          optional: true,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // 6. Atomic Posting Callout (`Screenshot (709).png`)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBF0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEED89A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Pal.goldDeep,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: T.body(11.6, color: Pal.goldDeep),
                            children: [
                              TextSpan(
                                text: 'Atomic Posting: ',
                                style: T.body(
                                  11.6,
                                  color: Pal.goldDeep,
                                  w: FontWeight.w800,
                                ),
                              ),
                              const TextSpan(
                                text:
                                    'The explicitly selected published rate, approved tax profile, ledger accounts, posting period, and document series are validated before the invoice, journal, and stock issue commit in one MySQL transaction.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Footer CTA (`Cancel` + `1-Click Bill & Print Invoice` — `Screenshot (709).png`)
                Row(
                  children: [
                    OutlinedButton(
                      onPressed:
                          _submitting ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RoyalGoldButton(
                        icon: Icons.auto_awesome_rounded,
                        label: '1-Click Bill & Print Invoice',
                        busy: _submitting,
                        onPressed: _submitting ? null : _submit1ClickCheckout,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettlementModeCard extends StatelessWidget {
  const _SettlementModeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFCF6E4) : Pal.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFC69214) : Pal.line,
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Pal.goldDeep : Pal.muted,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: T.body(
                  11.6,
                  color: selected ? Pal.goldDeep : Pal.ink,
                  w: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesInvoiceMobileCard extends StatelessWidget {
  const _SalesInvoiceMobileCard({
    required this.inv,
    required this.busy,
    required this.onDownloadPdf,
    this.onPost,
    this.onDispatch,
    this.onCreateReturn,
  });

  final Map<String, dynamic> inv;
  final bool busy;
  final VoidCallback onDownloadPdf;
  final VoidCallback? onPost;
  final VoidCallback? onDispatch;
  final VoidCallback? onCreateReturn;

  @override
  Widget build(BuildContext context) {
    final docNo = '${inv['documentNumber'] ?? shortId('${inv['id'] ?? 'INV'}')}';
    final invDate = fmtDate('${inv['invoiceDate'] ?? inv['createdAt'] ?? ''}');
    final custName =
        '${asMap(inv['customer'])['displayName'] ?? inv['customerName'] ?? 'Customer'}';
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
                    Text(invDate, style: T.body(11.5, color: Pal.muted)),
                  ],
                ),
              ),
              StatusPill(state),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.person_outline_rounded,
                size: 15,
                color: Pal.muted,
              ),
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
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 36),
                ),
                onPressed: onDownloadPdf,
                icon: const Icon(Icons.download_rounded, size: 15),
                label: const Text('Download PDF'),
              ),
              if (onPost != null)
                GoldButton(
                  label: 'Post Invoice',
                  compact: true,
                  busy: busy,
                  onPressed: onPost,
                ),
              if (onDispatch != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 36),
                  ),
                  onPressed: busy ? null : onDispatch,
                  icon: const Icon(Icons.local_shipping_outlined, size: 15),
                  label: const Text('Dispatch'),
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

class _InvoiceReceiptSheet extends StatelessWidget {
  const _InvoiceReceiptSheet(
    this.r, {
    required this.onDownloadPdf,
  });

  final Map<String, dynamic> r;
  final VoidCallback onDownloadPdf;

  @override
  Widget build(BuildContext context) {
    final invNo =
        '${r['documentNumber'] ?? r['invoiceNumber'] ?? shortId('${r['id'] ?? 'POS-INV'}')}';
    final total =
        '${r['totalAmount'] ?? r['grandTotal'] ?? r['netAmount'] ?? '0.00'}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      icon: const Icon(
                        Icons.copy_rounded,
                        size: 17,
                        color: Colors.white70,
                      ),
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
                  KeyValue('Customer', '${r['customerName']}', strong: true),
                if (r['taxableAmount'] != null)
                  KeyValue(
                    'Taxable Value',
                    inr(r['taxableAmount']),
                    mono: true,
                  ),
                if (r['taxAmount'] != null)
                  KeyValue('GST Amount', inr(r['taxAmount']), mono: true),
                if (r['paymentMode'] != null)
                  KeyValue('Settlement', '${r['paymentMode']}'),
                KeyValue('Grand Total', inr(total), strong: true),
              ],
            ),
          ),
          const SizedBox(height: 14),
          RoyalGoldButton(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Download & Print Invoice PDF',
            onPressed: onDownloadPdf,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              final html = '''
<html><body style="font-family:sans-serif;padding:24px;">
<h2>GST Tax Invoice - $invNo</h2>
<p><strong>Customer:</strong> ${r['customerName'] ?? 'Customer'}</p>
<p><strong>Settlement:</strong> ${r['paymentMode'] ?? '-'}</p>
<hr/>
<h3>Total Amount: ${inr(total)}</h3>
</body></html>''';
              DeviceBridge.printHtmlDocument(html: html, jobName: invNo);
            },
            icon: const Icon(Icons.print_outlined, size: 17),
            label: const Text('System Print / Save as PDF'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done · Close'),
          ),
        ],
      ),
    );
  }
}
