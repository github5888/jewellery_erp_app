import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../debug/api_inspector.dart';
import '../governance/tax_governance_screens.dart';
import '../more/operations_screens.dart';
import '../supply/supply_production_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onJump});
  final ValueChanged<int> onJump;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _stockSummary;
  int _availableTaggedCount = 0;
  Decimal _grossStockGrams = Decimal.zero;
  int _invoiceCount = 0;
  Decimal _salesTotal = Decimal.zero;
  List<Map<String, dynamic>> _recentInvoices = const [];
  int _pendingOrders = 0;
  Decimal _orderPipelineValue = Decimal.zero;
  List<Map<String, dynamic>> _openOrderPreview = const [];
  int _activeBatches = 0;
  bool _kpiLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAll());
  }

  Future<void> _refreshAll() async {
    final rates = context.read<RatesController>();
    final api = context.read<ApiClient>();
    await Future.wait([
      rates.refresh(),
      _loadKpis(api),
    ]);
  }

  Future<void> _loadKpis(ApiClient api) async {
    if (mounted) setState(() => _kpiLoading = true);
    try {
      final results = await Future.wait<dynamic>([
        api.get('/reports/stock-valuation').catchError((_) => null),
        api.get('/inventory').catchError((_) => null),
        api.get('/sales').catchError((_) => null),
        api.get('/procurement').catchError((_) => null),
        api.get('/custom-orders').catchError((_) => null),
        api.get('/job-work').catchError((_) => null),
        api.get('/refining').catchError((_) => null),
      ]);
      if (!mounted) return;

      final valMap = asMap(results[0]);
      final summary = asMap(valMap['summary']);

      final invRaw = results[1];
      final articlesRaw = asList(invRaw, keys: const ['articles', 'taggedArticles', 'items']);
      var availCount = 0;
      var grossSum = Decimal.zero;
      for (final raw in articlesRaw) {
        final a = Article.fromJson(raw);
        if (a.isAvailable) {
          availCount++;
          grossSum += decOrZero(a.grossWeight);
        }
      }
      if (grossSum == Decimal.zero && summary['totalGrossWeightGrams'] != null) {
        grossSum = decOrZero(summary['totalGrossWeightGrams']);
      }

      final salesRaw = results[2];
      final invList = salesRaw is Map
          ? asList(salesRaw, keys: const ['invoices', 'salesInvoices'])
          : asList(salesRaw);
      var rev = Decimal.zero;
      for (final inv in invList) {
        if ('${inv['state'] ?? inv['status']}'.toUpperCase() != 'VOID') {
          rev += decOrZero(inv['totalAmount']);
        }
      }

      final procMap = asMap(results[3]);
      final pos = asList(procMap, keys: const ['purchaseOrders']);
      final openPos = pos.where((p) {
        final s = '${p['state'] ?? p['status']}'.toUpperCase();
        return s != 'CLOSED' && s != 'CANCELLED';
      }).toList();

      final coList = asList(results[4], keys: const ['customOrders', 'orders', 'items']);
      final openCos = coList.where((o) {
        final s = '${o['state'] ?? o['status']}'.toUpperCase();
        return s != 'DELIVERED' && s != 'CANCELLED';
      }).toList();

      final jwList = asList(results[5], keys: const ['workOrders', 'items']);
      final activeJw = jwList.where((w) {
        final s = '${w['state'] ?? w['status']}'.toUpperCase();
        return s != 'COMPLETED' && s != 'CLOSED' && s != 'CANCELLED';
      }).toList();

      final refList = asList(results[6], keys: const ['batches', 'refiningBatches', 'items']);
      final activeRef = refList.where((b) {
        final s = '${b['state'] ?? b['status']}'.toUpperCase();
        return s != 'SETTLED' && s != 'POSTED' && s != 'CANCELLED';
      }).length;

      var pipeline = Decimal.zero;
      for (final o in openCos) {
        pipeline += decOrZero(
          o['estimatedAmount'] ?? o['quotedMakingAmount'] ?? o['advanceAmount'],
        );
      }
      for (final p in openPos) {
        pipeline += decOrZero(p['totalAmount'] ?? p['subtotalAmount']);
      }

      final orderPreview = <Map<String, dynamic>>[
        ...openCos.take(2),
        ...activeJw.take(2),
      ].take(3).toList();

      setState(() {
        _stockSummary = summary.isEmpty ? null : summary;
        _availableTaggedCount = availCount;
        _grossStockGrams = grossSum;
        _invoiceCount = invList.length;
        _salesTotal = rev;
        _recentInvoices = invList.take(3).toList();
        _pendingOrders = openCos.length + openPos.length;
        _orderPipelineValue = pipeline;
        _openOrderPreview = orderPreview;
        _activeBatches = activeJw.length + activeRef;
        _kpiLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _kpiLoading = false);
    }
  }

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => w));

  String _greetingText() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _firstName(AppState app) {
    final raw = app.userName.trim();
    if (raw.isEmpty) return 'Partner';
    final clean = raw.contains('@') ? raw.split('@').first : raw;
    final first = clean.split(RegExp(r'[\s._-]+')).first;
    if (first.isEmpty) return 'Partner';
    return first[0].toUpperCase() + first.substring(1);
  }

  MetalRate? _exactRate(RatesController rates, String metal, List<String> purityTokens) {
    final m = metal.toUpperCase();
    for (final r in rates.rates) {
      if (r.metal.toUpperCase() != m) continue;
      final p = r.purity.toUpperCase();
      final c = r.carat.toUpperCase();
      for (final tok in purityTokens) {
        final t = tok.toUpperCase();
        if (p == t || c == t || c.contains(t)) return r;
      }
    }
    return null;
  }

  String _spreadGoldQuote(Decimal base999, int targetFineness) {
    if (base999 <= Decimal.zero) return '—';
    final spread = decDiv(
      base999 * Decimal.fromInt(targetFineness),
      Decimal.fromInt(999),
      scale: 6,
    ).round(scale: 2);
    return '${inr(spread.toStringAsFixed(2))} / g';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();

    final storeBrand =
        app.tenantName.trim().isNotEmpty ? app.tenantName.trim() : 'Jewellery ERP';
    final branchCode = app.branchCode.trim().isNotEmpty ? app.branchCode.trim() : 'MAIN';
    final branchLabel = [
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
      if (app.entityName.trim().isNotEmpty) app.entityName.trim(),
    ].join(' — ');
    final stockValue = _stockSummary != null
        ? inr(_stockSummary!['totalCarryingCost'] ?? '0', paise: false)
        : '₹0';
    final fineStockGrams = _stockSummary != null
        ? fineGrams(_stockSummary!['totalFineWeightGrams'] ?? '0')
        : '0.000 g';
    final avatarChar = _firstName(app)[0].toUpperCase();

    // Live Bullion Rate Board quotes (`image-2.png` exact 4 rows + Purity auto-spread)
    final gold24Obj =
        _exactRate(rates, 'GOLD', const ['999', '24K', '24']) ?? rates.find('GOLD', '999');
    final gold22Obj = _exactRate(rates, 'GOLD', const ['916', '22K', '22']);
    final gold18Obj = _exactRate(rates, 'GOLD', const ['750', '18K', '18']);
    final silverObj =
        _exactRate(rates, 'SILVER', const ['999', 'FINE']) ?? rates.find('SILVER', '999');

    final gold24Dec = decOrZero(gold24Obj?.sell);
    final hasLiveRates = rates.rates.isNotEmpty &&
        (gold24Dec > Decimal.zero || decOrZero(silverObj?.sell) > Decimal.zero);

    final gold24Quote = gold24Dec > Decimal.zero
        ? '${inr(gold24Obj!.sell)} / g'
        : '—';
    final gold22Quote = (gold22Obj != null && decOrZero(gold22Obj.sell) > Decimal.zero)
        ? '${inr(gold22Obj.sell)} / g'
        : _spreadGoldQuote(gold24Dec, 916);
    final gold18Quote = (gold18Obj != null && decOrZero(gold18Obj.sell) > Decimal.zero)
        ? '${inr(gold18Obj.sell)} / g'
        : _spreadGoldQuote(gold24Dec, 750);
    final silverQuote = (silverObj != null && decOrZero(silverObj.sell) > Decimal.zero)
        ? '${inr(silverObj.sell)} / g'
        : '—';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Pal.ink,
        body: Column(
          children: [
            // 1. Dark Espresso-Bronze & 24K Gold Executive Header
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF140E08), Color(0xFF271B0D), Color(0xFF3A2812)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -40,
                    top: -20,
                    child: IgnorePointer(
                      child: Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Pal.goldBright.withValues(alpha: 0.28),
                              Pal.goldBright.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Brand + Notifications + Avatar Row
                          Row(
                            children: [
                              const GemMark(size: 32, darkSurface: true),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  storeBrand,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.display(19, color: Pal.goldSoft, w: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'API & Live Rate Diagnostics',
                                onPressed: () => _push(const ApiInspector()),
                                icon: const Icon(
                                  Icons.notifications_none_rounded,
                                  color: Pal.goldSoft,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                borderRadius: BorderRadius.circular(99),
                                onTap: app.branchCount > 1
                                    ? app.switchShowroom
                                    : () => widget.onJump(4),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFFE5C463), Color(0xFFA87718)],
                                    ),
                                    border: Border.all(color: Colors.white30, width: 1.2),
                                  ),
                                  child: Text(
                                    avatarChar,
                                    style: T.body(14, color: Pal.ink, w: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '${_greetingText()}, ${_firstName(app)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body(21, color: Colors.white, w: FontWeight.w800),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            "Here's your business overview",
                            style: T.body(12.8, color: Pal.goldSoft.withValues(alpha: 0.78)),
                          ),
                          const SizedBox(height: 14),
                          // Showroom / Branch Selector Pill inside Header
                          Material(
                            color: const Color(0xFFFAF6EE),
                            borderRadius: BorderRadius.circular(13),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(13),
                              onTap: app.branchCount > 1
                                  ? app.switchShowroom
                                  : () => _push(const ShowroomHierarchyScreen()),
                              child: Container(
                                height: 44,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(color: Pal.goldBright.withValues(alpha: 0.45)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.storefront_outlined,
                                      size: 18,
                                      color: Pal.goldDeep,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        branchLabel.isEmpty
                                            ? 'Active Showroom Context'
                                            : branchLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: T.body(13.5, color: Pal.ink, w: FontWeight.w700),
                                      ),
                                    ),
                                    if (app.branchCode.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Pal.goldWash,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Pal.goldBorder),
                                        ),
                                        child: Text(
                                          app.branchCode,
                                          style: T.mono(
                                            10.5,
                                            color: Pal.goldDeep,
                                            w: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: Pal.goldDeep,
                                      size: 21,
                                    ),
                                  ],
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

            // 2. Curved Warm Cream-Ivory Dashboard Body
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Pal.pearl,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  child: RefreshIndicator(
                    color: Pal.gold,
                    onRefresh: _refreshAll,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                      children: [
                        // 2x2 Executive KPI Grid
                        ResponsiveGrid2(
                          spacing: 11,
                          children: [
                            _OverviewKpiCard(
                              icon: Icons.inventory_2_outlined,
                              iconBg: const Color(0xFFFBF2DC),
                              iconColor: Pal.goldDeep,
                              label: 'Total Stock Value',
                              value: _kpiLoading ? '...' : stockValue,
                              badgeText: fineStockGrams,
                              badgeColor: Pal.ok,
                              badgeBg: Pal.okWash,
                              onTap: () => widget.onJump(1),
                            ),
                            _OverviewKpiCard(
                              icon: Icons.payments_outlined,
                              iconBg: const Color(0xFFEAF7F0),
                              iconColor: Pal.ok,
                              label: 'Total Sales',
                              value: _kpiLoading
                                  ? '...'
                                  : inr(_salesTotal.toStringAsFixed(2), paise: false),
                              badgeText: '$_invoiceCount bills',
                              badgeColor: Pal.ok,
                              badgeBg: Pal.okWash,
                              onTap: () => widget.onJump(2),
                            ),
                            _OverviewKpiCard(
                              icon: Icons.pending_actions_rounded,
                              iconBg: const Color(0xFFFEF4E2),
                              iconColor: Pal.warn,
                              label: 'Pending Orders',
                              value: _kpiLoading ? '...' : '$_pendingOrders',
                              badgeText: 'PO & Custom',
                              badgeColor: Pal.warn,
                              badgeBg: Pal.warnWash,
                              onTap: () => _push(const ProcurementScreen(initialTab: 'PO')),
                            ),
                            _OverviewKpiCard(
                              icon: Icons.precision_manufacturing_outlined,
                              iconBg: const Color(0xFFEEF3FC),
                              iconColor: const Color(0xFF28559A),
                              label: 'Active Batches',
                              value: _kpiLoading ? '...' : '$_activeBatches',
                              badgeText: 'Karigar & Melt',
                              badgeColor: const Color(0xFF28559A),
                              badgeBg: const Color(0xFFEEF3FC),
                              onTap: () => _push(const JobWorkScreen()),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),

                        // Dark Espresso-Gold "Quick Actions — Access all features in one place →" Banner
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [Color(0xFF1A120A), Color(0xFF3B2912), Color(0xFF6B4B1B)],
                            ),
                            border: Border.all(color: Pal.goldBright.withValues(alpha: 0.42)),
                            boxShadow: [
                              BoxShadow(
                                color: Pal.ink.withValues(alpha: 0.16),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => widget.onJump(4),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: Pal.goldBright.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(11),
                                        border: Border.all(
                                          color: Pal.goldBright.withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.hub_outlined,
                                        color: Pal.goldSoft,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Quick Actions',
                                            style: T.body(
                                              14.5,
                                              color: Colors.white,
                                              w: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Access all features in one place',
                                            style: T.body(
                                              12,
                                              color: Pal.goldSoft.withValues(alpha: 0.85),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Pal.goldSoft,
                                      size: 21,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ===============================================================
                        // BELOW QUICK ACTIONS: EXACT WEBSITE DASHBOARD CARDS (image-2.png)
                        // ===============================================================

                        // CARD 1: Live Bullion Rate Board (`image-2.png` left card)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFEFA),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE9DBB4), width: 1.2),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x0A1A140E),
                                blurRadius: 12,
                                offset: Offset(0, 4),
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
                                      color: const Color(0xFFFBF3DC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE7CF8B)),
                                    ),
                                    child: const Icon(
                                      Icons.toll_rounded,
                                      size: 18,
                                      color: Pal.goldDeep,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Live Bullion Rate Board',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: T.body(15, color: Pal.ink, w: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: hasLiveRates
                                          ? const Color(0xFFE6F6EC)
                                          : const Color(0xFFFEF4E2),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(
                                        color: hasLiveRates
                                            ? const Color(0xFFB7E4C7)
                                            : const Color(0xFFF4D59A),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6.5,
                                          height: 6.5,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: hasLiveRates
                                                ? const Color(0xFF15803D)
                                                : Pal.warn,
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          hasLiveRates ? 'Active' : 'Unpublished',
                                          style: T.body(
                                            11.2,
                                            w: FontWeight.w700,
                                            color: hasLiveRates
                                                ? const Color(0xFF15803D)
                                                : Pal.warn,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Daily showroom pricing basis for $branchCode.',
                                style: T.body(12.2, color: Pal.muted),
                              ),
                              const SizedBox(height: 12),
                              _BullionQuoteTile(
                                title: 'Gold 24K (Fine 999)',
                                subtitle: 'Pure Bullion Basis',
                                quote: gold24Quote,
                                highlighted: true,
                              ),
                              const SizedBox(height: 8),
                              _BullionQuoteTile(
                                title: 'Gold 22K (916 Hallmark)',
                                subtitle: 'Standard Jewellery',
                                quote: gold22Quote,
                              ),
                              const SizedBox(height: 8),
                              _BullionQuoteTile(
                                title: 'Gold 18K (750 Purity)',
                                subtitle: 'Diamond Jewellery',
                                quote: gold18Quote,
                              ),
                              const SizedBox(height: 8),
                              _BullionQuoteTile(
                                title: 'Silver (Fine 999)',
                                subtitle: 'Pure Silver Spot',
                                quote: silverQuote,
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Purity auto-spread enabled',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: T.body(11.5, color: Pal.muted),
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(8),
                                    onTap: () => _push(const MaterialsRatesScreen()),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        'Configure Rates →',
                                        style: T.body(
                                          12.8,
                                          color: Pal.goldDeep,
                                          w: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // CARD 2: Pending Orders (`image-2.png` middle card)
                        Panel(
                          radius: 18,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFBF3DC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE7CF8B)),
                                    ),
                                    child: const Icon(
                                      Icons.access_time_rounded,
                                      size: 18,
                                      color: Pal.goldDeep,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Pending Orders',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: T.body(15, color: Pal.ink, w: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDF5E3),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(color: const Color(0xFFEBD49E)),
                                    ),
                                    child: Text(
                                      '$_pendingOrders Active',
                                      style: T.mono(
                                        11.2,
                                        w: FontWeight.w800,
                                        color: Pal.goldDeep,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Custom bookings, Karigar jobwork, and unfulfilled showroom orders.',
                                style: T.body(12.2, color: Pal.muted),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F8FA),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFECEAE4)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ORDER PIPELINE VALUE',
                                      style: T.caps(
                                        10,
                                        color: Pal.muted,
                                        letterSpacing: 0.7,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      inr(
                                        _orderPipelineValue.toStringAsFixed(2),
                                        paise: false,
                                      ),
                                      style: T.mono(19, color: Pal.ink, w: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '$_pendingOrders orders scheduled for delivery in this branch.',
                                      style: T.body(11.8, color: Pal.muted),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              if (_openOrderPreview.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: Text(
                                      'No pending orders in this showroom.',
                                      textAlign: TextAlign.center,
                                      style: T.body(12.2, color: Pal.muted),
                                    ),
                                  ),
                                )
                              else
                                for (final o in _openOrderPreview)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.circle,
                                          size: 6,
                                          color: Pal.goldDeep,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${o['documentNumber'] ?? o['orderNumber'] ?? o['jobNumber'] ?? 'ORDER'} · ${asMap(o['customer'])['displayName'] ?? asMap(o['karigar'])['displayName'] ?? o['description'] ?? ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: T.body(12.2, w: FontWeight.w600),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        StatusPill('${o['state'] ?? o['status'] ?? 'OPEN'}'),
                                      ],
                                    ),
                                  ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => _push(const CustomOrdersScreen()),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'View All Orders →',
                                      style: T.body(
                                        12.8,
                                        color: Pal.goldDeep,
                                        w: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // CARD 3: Low Stock Alert (`image-2.png` right card)
                        Panel(
                          radius: 18,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: _availableTaggedCount < 5
                                          ? const Color(0xFFFDECEC)
                                          : const Color(0xFFEAF7F0),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: _availableTaggedCount < 5
                                            ? const Color(0xFFF7C6C9)
                                            : const Color(0xFFB7E4C7),
                                      ),
                                    ),
                                    child: Icon(
                                      _availableTaggedCount < 5
                                          ? Icons.warning_amber_rounded
                                          : Icons.verified_outlined,
                                      size: 18,
                                      color: _availableTaggedCount < 5
                                          ? const Color(0xFFC83E4D)
                                          : Pal.ok,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Low Stock Alert',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: T.body(15, color: Pal.ink, w: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _availableTaggedCount < 5
                                          ? const Color(0xFFFDECEC)
                                          : const Color(0xFFEAF7F0),
                                      borderRadius: BorderRadius.circular(99),
                                      border: Border.all(
                                        color: _availableTaggedCount < 5
                                            ? const Color(0xFFF7C6C9)
                                            : const Color(0xFFB7E4C7),
                                      ),
                                    ),
                                    child: Text(
                                      _availableTaggedCount < 5
                                          ? 'Restock Warning'
                                          : 'Stock Healthy',
                                      style: T.body(
                                        11.2,
                                        w: FontWeight.w700,
                                        color: _availableTaggedCount < 5
                                            ? const Color(0xFFB42334)
                                            : Pal.ok,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Showcase inventory levels & physical metal balances in $branchCode.',
                                style: T.body(12.2, color: Pal.muted),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(13),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F8FA),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFECEAE4)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'AVAILABLE PIECES',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: T.caps(
                                              10,
                                              color: Pal.muted,
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '$_availableTaggedCount Tagged',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: T.mono(
                                              16.5,
                                              color: Pal.ink,
                                              w: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            'GROSS WEIGHT',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: T.caps(
                                              10,
                                              color: Pal.muted,
                                              letterSpacing: 0.7,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${_grossStockGrams.toStringAsFixed(2)} g',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: T.mono(
                                              16.5,
                                              color: Pal.goldDeep,
                                              w: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Center(
                                  child: Text(
                                    _availableTaggedCount == 0
                                        ? 'No tagged inventory in this showroom location.'
                                        : 'Active Fine 999 metal balance: $fineStockGrams',
                                    textAlign: TextAlign.center,
                                    style: T.body(12.2, color: Pal.muted),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => widget.onJump(1),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'Manage Inventory & Tags →',
                                      style: T.body(
                                        12.8,
                                        color: Pal.goldDeep,
                                        w: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // CARD 4: Recent Showroom Billing & Invoices (`image-2.png` bottom row)
                        Panel(
                          radius: 18,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFBF3DC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE7CF8B)),
                                    ),
                                    child: const Icon(
                                      Icons.receipt_long_outlined,
                                      size: 18,
                                      color: Pal.goldDeep,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Recent Showroom Billing & Invoices',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: T.body(15, color: Pal.ink, w: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Chip2('$_invoiceCount Bills', mono: true),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (_recentInvoices.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: Center(
                                    child: Text(
                                      'No sales invoices posted in this showroom yet.',
                                      textAlign: TextAlign.center,
                                      style: T.body(12.2, color: Pal.muted),
                                    ),
                                  ),
                                )
                              else
                                for (final inv in _recentInvoices)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${inv['documentNumber'] ?? inv['invoiceNumber'] ?? shortId('${inv['id']}')}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: T.mono(12.5, w: FontWeight.w700),
                                              ),
                                              Text(
                                                '${asMap(inv['customer'])['displayName'] ?? 'Showroom Customer'} · ${fmtDate('${inv['invoiceDate'] ?? inv['createdAt'] ?? ''}')}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: T.body(11.5, color: Pal.muted),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          inr(inv['totalAmount']),
                                          style: T.mono(
                                            13,
                                            color: Pal.goldDeep,
                                            w: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => widget.onJump(2),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'Open Sales & POS Billing →',
                                      style: T.body(
                                        12.8,
                                        color: Pal.goldDeep,
                                        w: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BullionQuoteTile extends StatelessWidget {
  const _BullionQuoteTile({
    required this.title,
    required this.subtitle,
    required this.quote,
    this.highlighted = false,
  });

  final String title;
  final String subtitle;
  final String quote;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFFFDF5) : const Color(0xFFFAF9F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? const Color(0xFFE7CE85) : const Color(0xFFEDEBE5),
          width: highlighted ? 1.2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(13.2, color: Pal.ink, w: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(11.3, color: Pal.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            quote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.mono(
              14,
              color: highlighted ? Pal.goldDeep : Pal.ink,
              w: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewKpiCard extends StatelessWidget {
  const _OverviewKpiCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeBg,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;
  final String badgeText;
  final Color badgeColor;
  final Color badgeBg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      radius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(11.8, color: Pal.muted, w: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.body(19.5, color: Pal.ink, w: FontWeight.w800),
          ),
          const SizedBox(height: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              badgeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(10.8, color: badgeColor, w: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
