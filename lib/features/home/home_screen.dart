import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../billing/billing_controller.dart';
import '../inventory/scanner_page.dart';
import '../more/old_gold_screen.dart';
import '../more/operations_screens.dart';
import '../more/reports_screen.dart';
import '../more/shift_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onJump});
  final ValueChanged<int> onJump;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _perTenGram = false;
  Map<String, dynamic>? _stockSummary;
  int _invoiceCount = 0;
  Decimal _salesTotal = Decimal.zero;
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

      setState(() {
        _stockSummary = summary.isEmpty ? null : summary;
        _invoiceCount = invList.length;
        _salesTotal = rev;
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _MetalPriceCalculatorSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: Pal.gold,
          onRefresh: _refreshAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
            children: [
              // 1. Royal Espresso & 24K Gold Showroom Header
              LuxuryHeroCard(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 40,
                      height: 40,
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Pal.goldBright.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Pal.goldBright.withValues(alpha: 0.42)),
                      ),
                      child: const GemMark(darkSurface: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          (app.tenantName.isEmpty ? 'Jewellery ERP' : app.tenantName).toUpperCase(),
                          style: T.caps(10, color: Pal.goldSoft, letterSpacing: 1.15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          app.branchName.isEmpty ? 'Active Showroom' : app.branchName,
                          style: T.display(20, color: Colors.white),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ]),
                    ),
                    if (app.branchCount > 1)
                      IconButton(
                        tooltip: 'Switch Showroom',
                        visualDensity: VisualDensity.compact,
                        onPressed: app.switchShowroom,
                        icon: const Icon(Icons.swap_horiz_rounded, color: Pal.goldSoft, size: 20),
                      ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Quick Scan Tag',
                      visualDensity: VisualDensity.compact,
                      onPressed: _quickScanToBill,
                      style: IconButton.styleFrom(
                        backgroundColor: Pal.goldBright.withValues(alpha: 0.16),
                        side: BorderSide(color: Pal.goldBright.withValues(alpha: 0.35)),
                      ),
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: Pal.goldSoft, size: 19),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if (app.branchCode.isNotEmpty)
                      EnterpriseBadge(app.branchCode, icon: Icons.storefront_outlined),
                    EnterpriseBadge('${app.currency} · Fine 999 Ledger', icon: Icons.verified_outlined),
                  ]),
                ]),
              ),

              // 2. Live Bullion Spot Board (Overflow-Safe Header)
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  child: Text(
                    'LIVE BULLION BOARD',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.caps(10.8, color: Pal.goldDeep, letterSpacing: 0.9),
                  ),
                ),
                const SizedBox(width: 8),
                _UnitToggle(
                  perTenGram: _perTenGram,
                  onChanged: (v) => setState(() => _perTenGram = v),
                ),
                const SizedBox(width: 6),
                Material(
                  color: Pal.goldWash,
                  borderRadius: BorderRadius.circular(9),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: _openCalculator,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Pal.goldBorder),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.calculate_outlined, size: 14, color: Pal.goldDeep),
                        const SizedBox(width: 4),
                        Text('Quote', style: T.body(11.5, color: Pal.goldDeep, w: FontWeight.w700)),
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              _BullionBoard(rates: rates, perTenGram: _perTenGram),

              // 3. Live Showroom Custody & Revenue KPIs (Intrinsic Height, Never Overflows)
              const SectionLabel('Showroom Pulse'),
              if (_kpiLoading)
                const ResponsiveGrid2(
                  children: [
                    Panel(child: Skeleton(height: 68)),
                    Panel(child: Skeleton(height: 68)),
                  ],
                )
              else
                ResponsiveGrid2(
                  children: [
                    MetricTile(
                      label: 'Pure 999 Vault',
                      value: _stockSummary != null
                          ? fineGrams(_stockSummary!['grandPureFineGrams'] ?? '0')
                          : '0.000 g',
                      subtitle: '${_stockSummary?['totalTaggedPieces'] ?? 0} tagged pieces',
                      icon: Icons.diamond_outlined,
                      accent: Pal.goldDeep,
                      accentWash: Pal.goldWash,
                      onTap: () => widget.onJump(1),
                    ),
                    MetricTile(
                      label: 'Vault Valuation',
                      value: inrCompact(_stockSummary?['grandTotalInventoryCost'] ?? '0'),
                      subtitle: 'FIFO carrying cost',
                      icon: Icons.account_balance_outlined,
                      accent: Pal.goldDeep,
                      accentWash: Pal.goldWash,
                      onTap: () => _push(const ReportsScreen(initialTab: 'STOCK')),
                    ),
                    MetricTile(
                      label: 'Sales Register',
                      value: inrCompact(_salesTotal.toStringAsFixed(2)),
                      subtitle: '$_invoiceCount posted invoice(s)',
                      icon: Icons.receipt_long_outlined,
                      accent: Pal.ok,
                      accentWash: Pal.okWash,
                      onTap: () => widget.onJump(2),
                    ),
                    MetricTile(
                      label: 'Counter Drawer',
                      value: 'Shift Desk',
                      subtitle: 'Open / reconcile cash',
                      icon: Icons.point_of_sale_rounded,
                      accent: Pal.ruby,
                      accentWash: Pal.rubyWash,
                      onTap: () => _push(const ShiftScreen()),
                    ),
                  ],
                ),

              // 4. Counter & Vault Quick Actions Grid (Intrinsic Height, Never Overflows)
              const SectionLabel('Showroom Desk'),
              ResponsiveGrid2(
                children: [
                  _QuickCard(
                    icon: Icons.point_of_sale_rounded,
                    title: 'New POS Bill',
                    sub: 'GST invoice & split pay',
                    primary: true,
                    onTap: () => widget.onJump(2),
                  ),
                  _QuickCard(
                    icon: Icons.qr_code_scanner_rounded,
                    title: 'Scan Tag',
                    sub: 'Camera lookup & bill',
                    onTap: _quickScanToBill,
                  ),
                  _QuickCard(
                    icon: Icons.recycling_rounded,
                    title: 'Old Gold Assay',
                    sub: 'Melt loss & voucher',
                    onTap: () => _push(const OldGoldScreen()),
                  ),
                  _QuickCard(
                    icon: Icons.handshake_outlined,
                    title: 'Jangad Memo',
                    sub: 'VIP approval custody',
                    onTap: () => _push(const ApprovalMemosScreen()),
                  ),
                  _QuickCard(
                    icon: Icons.lock_clock_rounded,
                    title: 'Lock Gold Rate',
                    sub: 'Customer advance hedge',
                    onTap: () => _push(const RateFixingScreen()),
                  ),
                  _QuickCard(
                    icon: Icons.insights_rounded,
                    title: 'Ledger Reports',
                    sub: 'Margin, TB & AR ageing',
                    onTap: () => _push(const ReportsScreen()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact Royal Gold 1g / 10g pill switcher with zero wide Material segment padding.
class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.perTenGram, required this.onChanged});
  final bool perTenGram;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget item(String text, bool tenG) {
      final active = perTenGram == tenG;
      return GestureDetector(
        onTap: () => onChanged(tenG),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: active ? Pal.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            text,
            style: T.mono(
              11.5,
              w: FontWeight.w700,
              color: active ? Pal.goldSoft : Pal.textSoft,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Pal.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          item('1g', false),
          item('10g', true),
        ],
      ),
    );
  }
}

class _BullionBoard extends StatelessWidget {
  const _BullionBoard({required this.rates, required this.perTenGram});
  final RatesController rates;
  final bool perTenGram;

  @override
  Widget build(BuildContext context) {
    if (rates.loading && rates.rates.isEmpty) {
      return const Panel(
        child: Column(children: [
          Skeleton(height: 22),
          SizedBox(height: 12),
          Skeleton(height: 22),
          SizedBox(height: 12),
          Skeleton(height: 22),
        ]),
      );
    }
    if (rates.error != null && rates.rates.isEmpty) {
      return ErrorBlock(rates.error!, onRetry: rates.refresh);
    }
    if (rates.rates.isEmpty) {
      return const Panel(
        child: EmptyBlock(
          icon: Icons.currency_rupee_rounded,
          title: 'Showroom rate board awaiting publish',
          body: 'Publish today\'s bullion rate book on the web portal to activate live counter pricing.',
        ),
      );
    }

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < rates.rates.length; i++) ...[
          if (i > 0) const Divider(),
          _BullionRow(rateItem: rates.rates[i], perTenGram: perTenGram),
        ],
        if (rates.activeRateBookName != null || rates.updatedAt != null) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(color: Pal.ok, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  rates.activeRateBookName ?? 'Live Showroom Rate Book',
                  style: T.body(11.5, color: Pal.muted, w: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (rates.updatedAt != null)
                Text('Synced ${_ago(rates.updatedAt!)}', style: T.mono(11, color: Pal.muted)),
            ]),
          ),
        ],
      ]),
    );
  }

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return 'just now';
    if (s < 3600) return '${s ~/ 60}m ago';
    return '${s ~/ 3600}h ago';
  }
}

class _BullionRow extends StatelessWidget {
  const _BullionRow({required this.rateItem, required this.perTenGram});
  final MetalRate rateItem;
  final bool perTenGram;

  @override
  Widget build(BuildContext context) {
    final isGold = rateItem.metal.toUpperCase().contains('GOLD');
    final sellVal = perTenGram ? rateItem.sellPerTenGram : rateItem.sell;
    final buyVal = perTenGram ? rateItem.buyPerTenGram : rateItem.buy;
    final unitSuffix = perTenGram ? '/10g' : '/g';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isGold ? Pal.goldWash : Pal.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isGold ? Pal.goldBorder : Pal.line,
            ),
          ),
          child: Text(
            isGold ? rateItem.karatLabel.split(' ').first : 'Ag',
            style: T.mono(12, w: FontWeight.w700, color: isGold ? Pal.goldDeep : Pal.inkSoft),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${humanize(rateItem.metal)} · ${rateItem.karatLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(14, w: FontWeight.w800),
            ),
            if (decOrZero(buyVal) > Decimal.zero)
              Text(
                'Buyback ${inr(buyVal, paise: false)}$unitSuffix',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.mono(11.5, color: Pal.muted),
              ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(inr(sellVal, paise: false), style: T.display(18)),
          Text('Sell $unitSuffix', style: T.caps(9, color: Pal.goldDeep)),
        ]),
      ]),
    );
  }
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Panel(
      onTap: onTap,
      color: primary ? Pal.ink : Pal.card,
      borderColor: primary ? Pal.goldBright.withValues(alpha: 0.45) : Pal.line,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: primary ? Pal.goldBright.withValues(alpha: 0.16) : Pal.goldWash,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 17, color: primary ? Pal.goldSoft : Pal.goldDeep),
            ),
            const Spacer(),
            Icon(Icons.north_east_rounded, size: 15, color: primary ? Pal.goldSoft : Pal.muted),
          ]),
          const SizedBox(height: 12),
          Text(
            title,
            style: T.body(14, w: FontWeight.w800, color: primary ? Colors.white : Pal.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: T.body(11.5, color: primary ? Colors.white70 : Pal.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Interactive Counter Price Estimator calling `POST /pricing/calculate-metal` with exact `Decimal` fallback.
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

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 26 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Counter Jewellery Price Estimator', style: T.display(22)),
        const SizedBox(height: 4),
        Text('Live showroom bullion valuation with making charges and 3% GST.', style: T.body(12.5, color: Pal.muted)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
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
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Net Metal Wt (g)'),
              TextField(
                controller: _weight,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: T.mono(16, w: FontWeight.w700),
                decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
                onChanged: (_) => _recalc(),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FieldLabel('Making (${_makingPct.toStringAsFixed(0)}%)'),
              Slider(
                value: _makingPct,
                min: 0,
                max: 30,
                divisions: 30,
                activeColor: Pal.gold,
                onChanged: (v) => setState(() => _makingPct = v),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        LuxuryHeroCard(
          child: _busy
              ? const Center(child: Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(color: Pal.goldSoft)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  KeyValue('Applied Rate / g', rate(_quote?['ratePerGram'] ?? '0'), mono: true, valueColor: Colors.white),
                  KeyValue('Pure Fine 999 Wt', fineGrams(_quote?['fineWeightGrams'] ?? '0'), mono: true, valueColor: Colors.white),
                  KeyValue('Bullion Metal Value', inr(metalVal.toStringAsFixed(2)), mono: true, valueColor: Colors.white),
                  KeyValue('Making (${_makingPct.toStringAsFixed(0)}%)', inr(makingVal.toStringAsFixed(2)), mono: true, valueColor: Colors.white),
                  KeyValue('GST (3.00%)', inr(gst.toStringAsFixed(2)), mono: true, valueColor: Colors.white),
                  Divider(color: Colors.white.withValues(alpha: 0.16)),
                  Row(children: [
                    Expanded(child: Text('ESTIMATED QUOTE', style: T.caps(10, color: Colors.white70))),
                    Text(inr(grand.toStringAsFixed(2)), style: T.display(24, color: Pal.goldSoft)),
                  ]),
                ]),
        ),
      ]),
    );
  }
}
