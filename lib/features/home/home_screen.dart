import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../more/old_gold_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _today;

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    try {
      final d = await context.read<ApiClient>().get('/reports/sales-daily');
      if (mounted) setState(() => _today = d is Map ? Map<String, dynamic>.from(d) : null);
    } on ApiException {
      // The Today strip is optional; stay quiet if the report isn't available for this role.
    }
  }

  Future<void> _refresh() async {
    await Future.wait([context.read<RatesController>().load(silent: true), _loadToday()]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: Pal.ink,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.branchName.isEmpty ? 'Showroom' : app.branchName, style: T.display(25)),
                    const SizedBox(height: 3),
                    Text(
                      [if (app.tenantName.isNotEmpty) app.tenantName, if (app.branchCode.isNotEmpty) app.branchCode].join('  |  '),
                      style: T.body(13, color: Pal.muted),
                    ),
                  ]),
                ),
                IconButton.outlined(
                  onPressed: app.branchCount > 1 ? app.switchShowroom : null,
                  tooltip: 'Switch showroom',
                  icon: const Icon(Icons.swap_horiz_rounded),
                  style: IconButton.styleFrom(side: const BorderSide(color: Pal.line)),
                ),
              ]),
              const SizedBox(height: 18),
              const RatePlate(),
              _todayStrip(),
              const SectionLabel('Start something'),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  _action(Icons.qr_code_scanner_rounded, 'Look up a piece', 'Scan a barcode for weights and status', () => widget.onNavigate(1)),
                  const Divider(indent: 66),
                  _action(Icons.receipt_long_rounded, 'New bill', 'Scan pieces, take payment, issue the invoice', () => widget.onNavigate(2)),
                  const Divider(indent: 66),
                  _action(Icons.recycling_rounded, 'Buy old gold', 'Value a customer\'s old metal for exchange', () {
                    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const OldGoldScreen()));
                  }),
                  const Divider(indent: 66),
                  _action(Icons.person_search_rounded, 'Find a customer', 'Search by name or phone', () => widget.onNavigate(3)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _action(IconData icon, String title, String sub, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: Pal.ink, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 20, color: Pal.goldSoft),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: T.body(15.5, w: FontWeight.w800)),
                Text(sub, style: T.body(13, color: Pal.muted)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Pal.muted),
          ]),
        ),
      );

  Widget _todayStrip() {
    final t = _today;
    if (t == null) return const SizedBox.shrink();
    String? pick(List<String> keys) {
      for (final k in keys) {
        if (t[k] != null && '${t[k]}'.isNotEmpty) return '${t[k]}';
      }
      return null;
    }

    final sales = pick(['grossAmount', 'totalAmount', 'totalSales', 'netAmount']);
    final count = pick(['invoiceCount', 'count', 'totalInvoices']);
    if (sales == null && count == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Panel(
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sales today', style: T.body(13, color: Pal.muted, w: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(sales == null ? '-' : inr(sales, paise: false), style: T.display(28)),
            ]),
          ),
          if (count != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Invoices', style: T.body(13, color: Pal.muted, w: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(count, style: T.display(28)),
            ]),
        ]),
      ),
    );
  }
}

/// The one memorable thing in the app: a vault-green plate with the day's
/// bullion rates set in large tabular numerals.
class RatePlate extends StatelessWidget {
  const RatePlate({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RatesController>();
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Pal.inkSoft, Pal.ink],
        ),
        boxShadow: [BoxShadow(color: Pal.ink.withValues(alpha: 0.28), blurRadius: 30, offset: const Offset(0, 14))],
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text("Today's rates", style: T.display(21, color: Colors.white)),
          const Spacer(),
          _Live(updated: r.updatedAt, failing: r.error != null && r.rates.isNotEmpty),
        ]),
        const SizedBox(height: 4),
        Text('Per gram', style: T.body(12.5, color: Colors.white.withValues(alpha: 0.55))),
        const SizedBox(height: 14),
        if (r.loading && r.rates.isEmpty)
          ...[
            for (var i = 0; i < 3; i++)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Opacity(opacity: 0.35, child: Skeleton(height: 28, radius: 8)),
              ),
          ]
        else if (r.rates.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(children: [
              Expanded(child: Text(r.error ?? 'No rates published for today yet.', style: T.body(14, color: Colors.white70))),
              TextButton(onPressed: r.load, child: Text('Retry', style: T.body(14, color: Pal.goldSoft, w: FontWeight.w800))),
            ]),
          )
        else ...[
          _headerRow(),
          for (var i = 0; i < r.rates.length; i++) ...[
            if (i > 0) Divider(color: Pal.inkLine.withValues(alpha: 0.7)),
            _row(r.rates[i]),
          ],
        ],
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _headerRow() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          const Expanded(flex: 4, child: SizedBox()),
          Expanded(flex: 5, child: Text('Sell', textAlign: TextAlign.right, style: T.body(12.5, color: Colors.white.withValues(alpha: 0.55), w: FontWeight.w700))),
          Expanded(flex: 4, child: Text('Buy', textAlign: TextAlign.right, style: T.body(12.5, color: Colors.white.withValues(alpha: 0.55), w: FontWeight.w700))),
        ]),
      );

  Widget _row(MetalRate m) {
    final silver = m.metal.toUpperCase() == 'SILVER';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          flex: 4,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.carat, style: T.body(16, color: Colors.white, w: FontWeight.w800)),
            Text(silver ? 'Silver ${m.purity}' : 'Gold ${m.purity}', style: T.body(12, color: Colors.white.withValues(alpha: 0.55))),
          ]),
        ),
        Expanded(
          flex: 5,
          child: Text(rate(m.sell), textAlign: TextAlign.right, style: T.display(27, color: Pal.goldSoft, w: FontWeight.w600)),
        ),
        Expanded(
          flex: 4,
          child: Text(rate(m.buy), textAlign: TextAlign.right, style: T.display(18, color: Colors.white.withValues(alpha: 0.78))),
        ),
      ]),
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.updated, required this.failing});
  final DateTime? updated;
  final bool failing;
  @override
  Widget build(BuildContext context) {
    final color = failing ? const Color(0xFFE9A24A) : const Color(0xFF6FD3A0);
    final label = updated == null ? 'Loading' : (failing ? 'Offline, ${clock(updated!)}' : 'Updated ${clock(updated!)}');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 7),
      Text(label, style: T.body(12.5, color: Colors.white.withValues(alpha: 0.75), w: FontWeight.w700)),
    ]);
  }
}
