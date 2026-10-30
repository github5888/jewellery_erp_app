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
import '../../core/workspace_lookup.dart';
import '../billing/billing_controller.dart';
import '../debug/api_inspector.dart';
import '../finance/accounting_finance_screens.dart';
import '../governance/tax_governance_screens.dart';
import '../inventory/scanner_page.dart';
import '../more/old_gold_screen.dart';
import '../more/operations_screens.dart';
import '../more/reports_screen.dart';
import '../more/shift_screen.dart';
import '../supply/supply_production_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onJump, this.onOpenDrawer});
  final ValueChanged<int> onJump;
  final VoidCallback? onOpenDrawer;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _perTenGram = false;
  Map<String, dynamic>? _stockSummary;
  int _invoiceCount = 0;
  Decimal _salesTotal = Decimal.zero;
  int _pendingOrders = 0;
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
        api.get('/sales').catchError((_) => null),
        api.get('/procurement').catchError((_) => null),
        api.get('/custom-orders').catchError((_) => null),
        api.get('/job-work').catchError((_) => null),
        api.get('/refining').catchError((_) => null),
      ]);
      if (!mounted) return;

      final valMap = asMap(results[0]);
      final summary = asMap(valMap['summary']);

      final salesRaw = results[1];
      final invList = salesRaw is Map
          ? asList(salesRaw, keys: const ['invoices', 'salesInvoices'])
          : asList(salesRaw);
      var rev = Decimal.zero;
      for (final inv in invList) {
        if ('${inv['state'] ?? inv['status']}'.toUpperCase() != 'VOID') {
          rev += decOrZero(inv['totalAmount']);
        }
      }

      final procMap = asMap(results[2]);
      final pos = asList(procMap, keys: const ['purchaseOrders']);
      final openPos = pos.where((p) {
        final s = '${p['state'] ?? p['status']}'.toUpperCase();
        return s != 'CLOSED' && s != 'CANCELLED';
      }).length;

      final coList = asList(results[3], keys: const ['customOrders', 'orders', 'items']);
      final openCos = coList.where((o) {
        final s = '${o['state'] ?? o['status']}'.toUpperCase();
        return s != 'DELIVERED' && s != 'CANCELLED';
      }).length;

      final jwList = asList(results[4], keys: const ['workOrders', 'items']);
      final activeJw = jwList.where((w) {
        final s = '${w['state'] ?? w['status']}'.toUpperCase();
        return s != 'COMPLETED' && s != 'CLOSED' && s != 'CANCELLED';
      }).length;

      final refList = asList(results[5], keys: const ['batches', 'refiningBatches', 'items']);
      final activeRef = refList.where((b) {
        final s = '${b['state'] ?? b['status']}'.toUpperCase();
        return s != 'SETTLED' && s != 'POSTED' && s != 'CANCELLED';
      }).length;

      setState(() {
        _stockSummary = summary.isEmpty ? null : summary;
        _invoiceCount = invList.length;
        _salesTotal = rev;
        _pendingOrders = openPos + openCos;
        _activeBatches = activeJw + activeRef;
        _kpiLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _kpiLoading = false);
    }
  }

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => w));

  Future<void> _quickScanToBill() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (code == null || !mounted) return;
    final billing = context.read<BillingController>();
    await billing.scanAndAdd(code);
    if (!mounted) return;
    widget.onJump(2);
  }

  void _openCalculator() {
    showLuxuryFormSheet<void>(
      context: context,
      title: 'Counter Jewellery Estimator',
      subtitle: 'Live showroom bullion valuation with making & 3% GST',
      icon: Icons.calculate_outlined,
      builder: (_) => const _MetalPriceCalculatorSheet(),
    );
  }

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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();

    final storeBrand = app.tenantName.trim().isNotEmpty ? app.tenantName.trim() : 'Jewellery ERP';
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Pal.ink,
        body: Column(
          children: [
            // 1. Dark Espresso-Bronze & 24K Gold Executive Header (Screen 2 of image-1.png)
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
                          // Top Brand + Notifications/Diagnostics + Avatar Row
                          Row(
                            children: [
                              if (widget.onOpenDrawer != null) ...[
                                InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: widget.onOpenDrawer,
                                  child: const Padding(
                                    padding: EdgeInsets.only(right: 8, top: 4, bottom: 4),
                                    child: Icon(Icons.menu_rounded, color: Pal.goldSoft, size: 22),
                                  ),
                                ),
                              ],
                              const GemMark(size: 24, color: Pal.goldBright),
                              const SizedBox(width: 9),
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
                                onTap: app.branchCount > 1 ? app.switchShowroom : () => widget.onJump(4),
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
                          // Greeting
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
                                        branchLabel.isEmpty ? 'Active Showroom Context' : branchLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: T.body(13.5, color: Pal.ink, w: FontWeight.w700),
                                      ),
                                    ),
                                    if (app.branchCode.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Pal.goldWash,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: Pal.goldBorder),
                                        ),
                                        child: Text(
                                          app.branchCode,
                                          style: T.mono(10.5, color: Pal.goldDeep, w: FontWeight.w700),
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
                        // 2x2 Executive KPI Grid (matching Screen 2 of image-1.png)
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
                              onTap: widget.onOpenDrawer ?? () => widget.onJump(4),
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
                                            style: T.body(14.5, color: Colors.white, w: FontWeight.w800),
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
                        const SizedBox(height: 15),

                        // Exact 2x4 Module Icon Grid from Screen 2 of image-1.png
                        _FeatureIconGrid(
                          items: [
                            _GridAction(
                              icon: Icons.shopping_bag_outlined,
                              label: 'Purchase\nOrders',
                              onTap: () => _push(const ProcurementScreen(initialTab: 'PO')),
                            ),
                            _GridAction(
                              icon: Icons.inventory_outlined,
                              label: 'Goods\nReceipts',
                              onTap: () => _push(const ProcurementScreen(initialTab: 'GRN')),
                            ),
                            _GridAction(
                              icon: Icons.receipt_long_outlined,
                              label: 'Supplier\nBills',
                              onTap: () => _push(const ProcurementScreen(initialTab: 'BILLS')),
                            ),
                            _GridAction(
                              icon: Icons.assignment_return_outlined,
                              label: 'Returns /\nDebits',
                              onTap: () => _push(const ProcurementScreen(initialTab: 'RETURNS')),
                            ),
                            _GridAction(
                              icon: Icons.groups_outlined,
                              label: 'Parties &\nKarigars',
                              onTap: () => widget.onJump(3),
                            ),
                            _GridAction(
                              icon: Icons.handyman_outlined,
                              label: 'Karigar\nWork',
                              onTap: () => _push(const JobWorkScreen()),
                            ),
                            _GridAction(
                              icon: Icons.local_fire_department_outlined,
                              label: 'Refining &\nMelting',
                              onTap: () => _push(const RefiningMeltingScreen()),
                            ),
                            _GridAction(
                              icon: Icons.more_horiz_rounded,
                              label: 'More\nModules',
                              onTap: () => widget.onJump(4),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Enterprise Custody, Transfers, Finance & GST Strip
                        SectionLabel(
                          'Showroom, Custody & Finance',
                          trailing: GestureDetector(
                            onTap: _openCalculator,
                            child: Text(
                              'Price Estimator →',
                              style: T.body(11.8, color: Pal.goldDeep, w: FontWeight.w700),
                            ),
                          ),
                        ),
                        _FeatureIconGrid(
                          items: [
                            _GridAction(
                              icon: Icons.qr_code_scanner_rounded,
                              label: 'Scan &\nPOS Bill',
                              onTap: _quickScanToBill,
                            ),
                            _GridAction(
                              icon: Icons.swap_horiz_rounded,
                              label: 'Branch\nTransfers',
                              onTap: () => _push(const InterBranchTransfersScreen()),
                            ),
                            _GridAction(
                              icon: Icons.fact_check_outlined,
                              label: 'Approval &\nConsign.',
                              onTap: () => _push(const ApprovalConsignmentScreen()),
                            ),
                            _GridAction(
                              icon: Icons.domain_rounded,
                              label: 'Inter-Entity\nTrading',
                              onTap: () => _push(const InterEntityTradingScreen()),
                            ),
                            _GridAction(
                              icon: Icons.lock_clock_rounded,
                              label: 'Rate\nFixing',
                              onTap: () => _push(const WholesaleRateFixingScreen()),
                            ),
                            _GridAction(
                              icon: Icons.account_balance_outlined,
                              label: 'Double-Entry\nLedger',
                              onTap: () => _push(const DoubleEntryAccountingScreen()),
                            ),
                            _GridAction(
                              icon: Icons.account_balance_wallet_outlined,
                              label: 'Settlements\n& Cashup',
                              onTap: () => _push(const SettlementsCashupScreen()),
                            ),
                            _GridAction(
                              icon: Icons.verified_outlined,
                              label: 'GST, IRN &\n2B ITC',
                              onTap: () => _push(const GstRegistrationTransportScreen()),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Live Bullion Rate Board
                        SectionLabel(
                          'Live Bullion Board',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => _perTenGram = !_perTenGram),
                                child: Chip2(_perTenGram ? 'Per 10 g' : 'Per 1 g', mono: true),
                              ),
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _push(const MaterialsRatesScreen()),
                                child: const Chip2('Manage', gold: false),
                              ),
                            ],
                          ),
                        ),
                        if (rates.loading && rates.rates.isEmpty)
                          const Panel(child: Skeleton(height: 68))
                        else if (rates.rates.isEmpty)
                          Panel(
                            onTap: () => _push(const MaterialsRatesScreen()),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Pal.goldWash,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: const Icon(Icons.toll_rounded, color: Pal.goldDeep),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Publish Showroom Rate Version',
                                        style: T.body(13.8, w: FontWeight.w800),
                                      ),
                                      Text(
                                        'Tap to configure 24K / 22K / Silver live rates in Materials & Rates.',
                                        style: T.body(12, color: Pal.muted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, color: Pal.muted),
                              ],
                            ),
                          )
                        else
                          for (final r in rates.rates)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: _RateRowCard(rateItem: r, perTenGram: _perTenGram),
                            ),

                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _push(const OldGoldScreen()),
                                icon: const Icon(Icons.recycling_rounded, size: 17),
                                label: const Text('Old Gold Buyback'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _push(const ShiftScreen()),
                                icon: const Icon(Icons.point_of_sale_rounded, size: 17),
                                label: const Text('Cashier Shift'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _push(const ReportsScreen()),
                          icon: const Icon(Icons.bar_chart_rounded, size: 17),
                          label: const Text('Financial, Stock Valuation & Ageing Reports'),
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

class _GridAction {
  const _GridAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _FeatureIconGrid extends StatelessWidget {
  const _FeatureIconGrid({required this.items});
  final List<_GridAction> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 520 ? 4 : 4;
        final spacing = 9.0;
        final tileW = (c.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: tileW,
                child: Container(
                  decoration: BoxDecoration(
                    color: Pal.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Pal.line),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x081A140B),
                        blurRadius: 8,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: item.onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Pal.goldWash,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: Pal.goldBorder.withValues(alpha: 0.7),
                                ),
                              ),
                              child: Icon(item.icon, size: 19, color: Pal.goldDeep),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              item.label,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: T.body(11.0, color: Pal.textSoft, w: FontWeight.w700, height: 1.2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RateRowCard extends StatelessWidget {
  const _RateRowCard({required this.rateItem, required this.perTenGram});
  final MetalRate rateItem;
  final bool perTenGram;

  @override
  Widget build(BuildContext context) {
    final sellVal = perTenGram ? rateItem.sellPer10g : rateItem.sell;
    final buyVal = perTenGram ? rateItem.buyPer10g : rateItem.buy;
    final unitSuffix = perTenGram ? '/ 10g' : '/ g';

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Pal.goldWash,
              shape: BoxShape.circle,
              border: Border.all(color: Pal.goldBorder),
            ),
            child: Text(
              rateItem.carat,
              style: T.mono(11, color: Pal.goldDeep, w: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${rateItem.metalName} ${rateItem.karatLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(14, w: FontWeight.w800),
                ),
                if (decOrZero(buyVal) > Decimal.zero)
                  Text(
                    'Buyback ${inr(buyVal, paise: false)} $unitSuffix',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.mono(11.3, color: Pal.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(inr(sellVal, paise: false), style: T.mono(15.5, w: FontWeight.w800)),
              Text('SELL $unitSuffix', style: T.caps(9, color: Pal.goldDeep)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Interactive Counter Price Estimator calling `RatesController.calculateMetalValue`.
class _MetalPriceCalculatorSheet extends StatefulWidget {
  const _MetalPriceCalculatorSheet();
  @override
  State<_MetalPriceCalculatorSheet> createState() => _MetalPriceCalculatorSheetState();
}

class _MetalPriceCalculatorSheetState extends State<_MetalPriceCalculatorSheet> {
  String _metal = 'GOLD';
  String _purity = '916';
  final _weight = TextEditingController();
  double _makingPct = 12;
  Map<String, String>? _quote;
  bool _busy = false;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _recalc() async {
    if (!isValidWeight(_weight.text)) {
      setState(() => _quote = null);
      return;
    }
    setState(() => _busy = true);
    final q = await context.read<RatesController>().calculateMetalValue(
          metal: _metal,
          purity: _purity,
          netWeightGrams: _weight.text,
        );
    if (mounted) {
      setState(() {
        _quote = q;
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final metalVal = decOrZero(_quote?['metalValue']);
    final makingVal = (metalVal * Decimal.parse((_makingPct / 100).toStringAsFixed(4))).round(scale: 2);
    final taxable = metalVal + makingVal;
    final gst = (taxable * Decimal.parse('0.03')).round(scale: 2);
    final grand = taxable + gst;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final opt in const [
              ('GOLD', '999', 'Gold 24K'),
              ('GOLD', '916', 'Gold 22K'),
              ('GOLD', '750', 'Gold 18K'),
              ('SILVER', '999', 'Silver 999'),
            ])
              ChoiceChip(
                label: Text(opt.$3),
                selected: _metal == opt.$1 && _purity == opt.$2,
                showCheckmark: false,
                selectedColor: Pal.goldWash,
                onSelected: (_) {
                  setState(() {
                    _metal = opt.$1;
                    _purity = opt.$2;
                  });
                  _recalc();
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Net Metal Wt (g)'),
                  TextField(
                    controller: _weight,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: T.mono(16, w: FontWeight.w700),
                    decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
                    onChanged: (_) => _recalc(),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FieldLabel('Making (${_makingPct.toStringAsFixed(0)}%)'),
                  Slider(
                    value: _makingPct,
                    min: 0,
                    max: 30,
                    divisions: 30,
                    activeColor: Pal.gold,
                    onChanged: (v) => setState(() => _makingPct = v),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LuxuryHeroCard(
          child: _busy
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: CircularProgressIndicator(color: Pal.goldSoft),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyValue('Applied Rate / g', rate(_quote?['ratePerGram'] ?? '0'), mono: true, valueColor: Colors.white),
                    KeyValue('Pure Fine 999 Wt', fineGrams(_quote?['fineWeightGrams'] ?? '0'), mono: true, valueColor: Colors.white),
                    KeyValue('Bullion Metal Value', inr(metalVal.toStringAsFixed(2)), mono: true, valueColor: Colors.white),
                    KeyValue('Making (${_makingPct.toStringAsFixed(0)}%)', inr(makingVal.toStringAsFixed(2)), mono: true, valueColor: Colors.white),
                    KeyValue('GST (3.00%)', inr(gst.toStringAsFixed(2)), mono: true, valueColor: Colors.white),
                    Divider(color: Colors.white.withValues(alpha: 0.16)),
                    Row(
                      children: [
                        Expanded(child: Text('ESTIMATED QUOTE', style: T.caps(10, color: Colors.white70))),
                        Text(inr(grand.toStringAsFixed(2)), style: T.display(24, color: Pal.goldSoft)),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
