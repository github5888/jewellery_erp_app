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
import '../finance/accounting_finance_screens.dart';
import '../governance/tax_governance_screens.dart';
import '../more/old_gold_screen.dart';
import '../more/operations_screens.dart';
import '../more/reports_screen.dart';
import '../more/shift_screen.dart';
import '../supply/supply_production_screens.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onJump});
  final ValueChanged<int> onJump;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _stockGross = '—';
  String _stockFine = '—';
  String _stockValue = '—';
  int _articleCount = 0;
  int _invoiceCount = 0;
  int _partyCount = 0;
  String? _shiftNo;
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    final api = context.read<ApiClient>();
    final rates = context.read<RatesController>();
    rates.refresh();

    try {
      final results = await Future.wait<dynamic>([
        api.get('/reports/stock-valuation').catchError((_) => null),
        api.get('/inventory').catchError((_) => null),
        api.get('/pos-shifts').catchError((_) => null),
        api.get('/sales').catchError((_) => null),
        api.get('/parties').catchError((_) => null),
      ]);

      final val = results[0];
      if (val != null) {
        final m = asMap(val);
        final rows = asList(val, keys: const ['rows', 'items', 'lines', 'byMetal', 'summary']);
        _stockGross =
            '${m['totalGrossWeight'] ?? m['grossWeightGrams'] ?? m['grossWeight'] ?? _sumField(rows, 'grossWeightGrams', 'grossWeight')}';
        _stockFine =
            '${m['totalFineWeight'] ?? m['fineWeightGrams'] ?? m['fineWeight'] ?? _sumField(rows, 'fineWeightGrams', 'fineWeight')}';
        _stockValue =
            '${m['totalCarryingValue'] ?? m['totalValue'] ?? m['valuationAmount'] ?? _sumMoney(rows)}';
      }

      final inv = results[1];
      if (inv != null) {
        final arts = asList(inv, keys: const ['articles', 'items', 'taggedArticles']);
        _articleCount = arts.length;
        if (_stockGross == '—' || _stockGross.isEmpty || _stockGross == '0.000000') {
          var g = decOrZero('0');
          var f = decOrZero('0');
          var v = decOrZero('0');
          for (final raw in arts) {
            final a = Article.fromJson(raw);
            if (!a.isAvailable) continue;
            g += decOrZero(a.grossWeight);
            f += decOrZero(a.fineWeight);
            v += decOrZero(a.carryingCost);
          }
          if (arts.isNotEmpty) {
            _stockGross = g.toStringAsFixed(3);
            _stockFine = f.toStringAsFixed(3);
            if (v > decOrZero('0')) _stockValue = v.toStringAsFixed(2);
          }
        }
      }

      final sh = results[2];
      _shiftNo = null;
      if (sh != null) {
        final list = asList(sh, keys: const ['shifts', 'items']);
        final open = list
            .where((x) => '${x['status'] ?? x['state']}'.toUpperCase() == 'OPEN')
            .firstOrNull;
        final m = open ?? asMap(sh);
        if ('${m['status'] ?? m['state']}'.toUpperCase() == 'OPEN') {
          _shiftNo = '${m['shiftNumber'] ?? m['code'] ?? m['documentNumber'] ?? 'OPEN'}';
        }
      }

      final sales = results[3];
      if (sales != null) {
        final sm = asMap(sales);
        _invoiceCount = asList(sm['invoices'] ?? sales).length;
      }

      final parties = results[4];
      if (parties != null) {
        _partyCount = asList(parties, keys: const ['parties', 'items']).length;
      }
    } on ApiException catch (e) {
      _err = e.message;
    }

    if (mounted) setState(() => _loading = false);
  }

  String _sumField(List<Map<String, dynamic>> rows, String k1, String k2) {
    if (rows.isEmpty) return '—';
    var acc = decOrZero('0');
    for (final r in rows) {
      acc += decOrZero(r[k1] ?? r[k2]);
    }
    return acc.toStringAsFixed(3);
  }

  String _sumMoney(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '—';
    var acc = decOrZero('0');
    for (final r in rows) {
      acc += decOrZero(r['carryingValue'] ?? r['value'] ?? r['amount'] ?? r['carryingCost']);
    }
    return acc.toStringAsFixed(2);
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold24 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24');
    final gold22 = rates.find('GOLD', '916') ?? rates.find('GOLD', '22');
    final silver = rates.find('SILVER', '');
    final initial = (app.userName.isNotEmpty ? app.userName : app.tenantName).trim();
    final avatarChar = initial.isEmpty ? 'J' : initial[0].toUpperCase();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Pal.ink,
        body: Column(
          children: [
            // -----------------------------------------------------------------
            // 1. DARK ESPRESSO-BRONZE LUXURY HEADER WITH EXACT WEBSITE LOGO
            // -----------------------------------------------------------------
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF150F09), Color(0xFF281C0E), Color(0xFF3A2812)],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -40,
                    top: -20,
                    child: IgnorePointer(
                      child: Container(
                        width: 210,
                        height: 210,
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
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Top Bar: Exact `pos.hrpocket.in` Brand Lockup + Messaging + Avatar
                          Row(
                            children: [
                              Expanded(
                                child: WebsiteBrandLockup(
                                  badgeSize: 36,
                                  fontSize: 17.5,
                                  subtitle: app.tenantName.isEmpty
                                      ? 'Showroom Dashboard'
                                      : app.tenantName,
                                  darkSurface: true,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Customer Messaging',
                                onPressed: () => _open(const CustomerMessagingScreen()),
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
                                      colors: [Color(0xFFE7C664), Color(0xFFB8860B)],
                                    ),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text(
                                    avatarChar,
                                    style: T.body(14, color: Pal.ink, w: FontWeight.w800),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Showroom Context & Shift Status Pill
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 13.5,
                                color: Pal.goldSoft,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  [
                                    if (app.branchName.isNotEmpty) app.branchName,
                                    if (app.branchCode.isNotEmpty) '(${app.branchCode})',
                                    if (app.entityName.isNotEmpty) app.entityName,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.body(12, color: Colors.white70, w: FontWeight.w600),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                borderRadius: BorderRadius.circular(99),
                                onTap: () => _open(const ShiftScreen()),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 3.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (_shiftNo != null ? Pal.ok : Pal.warn)
                                        .withValues(alpha: 0.20),
                                    borderRadius: BorderRadius.circular(99),
                                    border: Border.all(
                                      color: (_shiftNo != null
                                              ? const Color(0xFF4ADE80)
                                              : Pal.goldSoft)
                                          .withValues(alpha: 0.55),
                                    ),
                                  ),
                                  child: Text(
                                    _shiftNo != null ? 'Shift $_shiftNo' : 'Shift Closed',
                                    style: T.body(
                                      10.8,
                                      color: Colors.white,
                                      w: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Live Bullion Strip (22K · 24K · Silver + Refresh)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.28),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Pal.goldBright.withValues(alpha: 0.32),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _RateMiniCol(
                                    label: 'GOLD 22K',
                                    value: gold22 != null
                                        ? '${inr(gold22.sell)}/g'
                                        : 'Unpublished',
                                  ),
                                ),
                                Container(width: 1, height: 26, color: Colors.white12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: _RateMiniCol(
                                      label: 'GOLD 24K',
                                      value: gold24 != null
                                          ? '${inr(gold24.sell)}/g'
                                          : 'Unpublished',
                                    ),
                                  ),
                                ),
                                Container(width: 1, height: 26, color: Colors.white12),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 10),
                                    child: _RateMiniCol(
                                      label: 'SILVER 999',
                                      value: silver != null
                                          ? '${inr(silver.sell)}/g'
                                          : 'Unpublished',
                                    ),
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: _load,
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.refresh_rounded,
                                      size: 18,
                                      color: Pal.goldSoft,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 4 Executive Metrics Row (Vault Stock · Fine 999 · Invoices · Parties)
                          Row(
                            children: [
                              Expanded(
                                child: _DarkHeroMetric(
                                  icon: Icons.diamond_outlined,
                                  title: 'Vault Stock',
                                  mainValue: _loading
                                      ? '…'
                                      : (_stockValue == '—'
                                          ? '$_articleCount tags'
                                          : inr(_stockValue)),
                                  subValue: _stockGross == '—'
                                      ? '$_articleCount ornaments'
                                      : '${grams(_stockGross)} gross',
                                  onTap: () => widget.onJump(1),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _DarkHeroMetric(
                                  icon: Icons.point_of_sale_rounded,
                                  title: 'Sales & Parties',
                                  mainValue: _loading ? '…' : '$_invoiceCount bills',
                                  subValue:
                                      '$_partyCount parties · ${_stockFine == '—' ? 'Fine 999' : '${grams(_stockFine)} fine'}',
                                  onTap: () => widget.onJump(2),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // -----------------------------------------------------------------
            // 2. CURVED WARM-CREAM SHEET — ONLY AUTHENTIC WEBSITE MODULES
            // -----------------------------------------------------------------
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFFAF6EE),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                clipBehavior: Clip.antiAlias,
                child: RefreshIndicator(
                  color: Pal.gold,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      if (_err != null) ...[
                        ErrorBlock(_err!, onRetry: _load),
                        const SizedBox(height: 12),
                      ],

                      // Quick Actions Gold Banner -> Opens `More` tab directly
                      InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => widget.onJump(4),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(18, 15, 16, 15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF3E2B14),
                                Color(0xFF8C6319),
                                Color(0xFFD7AF4B),
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Pal.gold.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Quick Actions',
                                      style: T.body(
                                        17,
                                        color: Colors.white,
                                        w: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Access all enterprise features in More  →',
                                      style: T.body(
                                        12.2,
                                        color: Colors.white.withValues(alpha: 0.90),
                                        w: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const GemMark(size: 40, darkSurface: true),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Website Group 1: Showroom & Retail (`pos.hrpocket.in`)
                      Text(
                        'SHOWROOM & RETAIL',
                        style: T.caps(10.8, color: Pal.goldDeep, letterSpacing: 0.9),
                      ),
                      const SizedBox(height: 8),
                      _LuxuryActionGrid(
                        items: [
                          _QuickItem(
                            Icons.diamond_outlined,
                            'Vault & Stock',
                            () => widget.onJump(1),
                          ),
                          _QuickItem(
                            Icons.point_of_sale_outlined,
                            'POS & Sales',
                            () => widget.onJump(2),
                          ),
                          _QuickItem(
                            Icons.lock_clock_rounded,
                            'POS Shifts',
                            () => _open(const ShiftScreen()),
                          ),
                          _QuickItem(
                            Icons.recycling_rounded,
                            'Old Metal',
                            () => _open(const OldGoldScreen()),
                          ),
                          _QuickItem(
                            Icons.auto_awesome_outlined,
                            'Custom Orders',
                            () => _open(const CustomOrdersScreen()),
                          ),
                          _QuickItem(
                            Icons.build_outlined,
                            'Repairs',
                            () => _open(const RepairsCustodyScreen()),
                          ),
                          _QuickItem(
                            Icons.groups_outlined,
                            'Parties',
                            () => widget.onJump(3),
                          ),
                          _QuickItem(
                            Icons.insights_rounded,
                            'Reports',
                            () => _open(const ReportsScreen()),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Website Group 2: Supply & Production (`pos.hrpocket.in`)
                      Text(
                        'SUPPLY & PRODUCTION',
                        style: T.caps(10.8, color: Pal.goldDeep, letterSpacing: 0.9),
                      ),
                      const SizedBox(height: 8),
                      _LuxuryActionGrid(
                        items: [
                          _QuickItem(
                            Icons.toll_rounded,
                            'Materials & Rates',
                            () => _open(const MaterialsRatesScreen()),
                          ),
                          _QuickItem(
                            Icons.shopping_cart_outlined,
                            'Procurement',
                            () => _open(const ProcurementScreen()),
                          ),
                          _QuickItem(
                            Icons.handyman_outlined,
                            'Karigar Job Work',
                            () => _open(const JobWorkScreen()),
                          ),
                          _QuickItem(
                            Icons.balance_rounded,
                            'Refining & Melt',
                            () => _open(const RefiningMeltingScreen()),
                          ),
                          _QuickItem(
                            Icons.swap_horiz_rounded,
                            'Branch Transfers',
                            () => _open(const InterBranchTransfersScreen()),
                          ),
                          _QuickItem(
                            Icons.handshake_outlined,
                            'Approval Memos',
                            () => _open(const ApprovalMemosScreen()),
                          ),
                          _QuickItem(
                            Icons.domain_rounded,
                            'Inter-Entity',
                            () => _open(const InterEntityTradingScreen()),
                          ),
                          _QuickItem(
                            Icons.trending_up_rounded,
                            'Rate Fixing',
                            () => _open(const RateFixingScreen()),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Website Group 3: Financials & GST (`pos.hrpocket.in`)
                      Text(
                        'FINANCIALS & GST',
                        style: T.caps(10.8, color: Pal.goldDeep, letterSpacing: 0.9),
                      ),
                      const SizedBox(height: 8),
                      _LuxuryActionGrid(
                        items: [
                          _QuickItem(
                            Icons.menu_book_rounded,
                            'Accounting',
                            () => _open(const DoubleEntryAccountingScreen()),
                          ),
                          _QuickItem(
                            Icons.account_balance_wallet_outlined,
                            'Settlements',
                            () => _open(const SettlementsCashupScreen()),
                          ),
                          _QuickItem(
                            Icons.account_balance_rounded,
                            'Banking',
                            () => _open(const BankingReconciliationScreen()),
                          ),
                          _QuickItem(
                            Icons.hub_outlined,
                            'Chain Analytics',
                            () => _open(const ConsolidatedAnalyticsScreen()),
                          ),
                          _QuickItem(
                            Icons.cloud_sync_outlined,
                            'Integrations',
                            () => _open(const ProviderIntegrationsScreen()),
                          ),
                          _QuickItem(
                            Icons.verified_user_outlined,
                            'GST & Transport',
                            () => _open(const GstRegistrationTransportScreen()),
                          ),
                          _QuickItem(
                            Icons.description_outlined,
                            'GST Returns',
                            () => _open(const GstReturnsItcScreen()),
                          ),
                          _QuickItem(
                            Icons.grid_view_rounded,
                            'More',
                            () => widget.onJump(4),
                          ),
                        ],
                      ),
                    ],
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

class _RateMiniCol extends StatelessWidget {
  const _RateMiniCol({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: T.caps(9.5, color: Pal.goldSoft, letterSpacing: 0.7)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: T.mono(12.2, color: Colors.white, w: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DarkHeroMetric extends StatelessWidget {
  const _DarkHeroMetric({
    required this.icon,
    required this.title,
    required this.mainValue,
    required this.subValue,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String mainValue;
  final String subValue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Pal.goldBright.withValues(alpha: 0.26)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: Pal.goldSoft),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.body(11.5, color: Colors.white70, w: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              mainValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.mono(15, color: Colors.white, w: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              subValue,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(11, color: Pal.goldSoft.withValues(alpha: 0.85)),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickItem {
  const _QuickItem(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _LuxuryActionGrid extends StatelessWidget {
  const _LuxuryActionGrid({required this.items});
  final List<_QuickItem> items;

  @override
  Widget build(BuildContext context) {
    final rows = <List<_QuickItem>>[];
    for (var i = 0; i < items.length; i += 4) {
      rows.add(items.sublist(i, (i + 4).clamp(0, items.length)));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7DFD0)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A1A140B), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < 4; c++)
                  Expanded(
                    child: c < rows[r].length
                        ? _QuickActionCell(item: rows[r][c])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActionCell extends StatelessWidget {
  const _QuickActionCell({required this.item});
  final _QuickItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFFFBF3DC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE5CC82)),
              ),
              child: Icon(item.icon, color: Pal.goldDeep, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.body(11.3, color: Pal.ink, w: FontWeight.w700, height: 1.18),
            ),
          ],
        ),
      ),
    );
  }
}
