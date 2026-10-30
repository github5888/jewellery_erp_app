import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Enterprise Financial & Bullion Reports Suite matching `ReportsPanel.tsx` & `PaymentsPanel.tsx` on pos.hrpocket.in:
/// - Stock Valuation (`GET /reports/stock-valuation`)
/// - Gross Margin (`GET /reports/gross-margin`)
/// - Trial Balance (`GET /reports/trial-balance`)
/// - AR / AP Ageing (`GET /reports/ar-ap-ageing`)
/// - Settlements & Open Dues (`GET /payments`)
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initialTab = 'STOCK'});
  final String initialTab;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late String _tab = widget.initialTab;
  String _ageingKind = 'RECEIVABLE';
  Map<String, dynamic>? _stockVal;
  Map<String, dynamic>? _margin;
  Map<String, dynamic>? _trial;
  Map<String, dynamic>? _ageing;
  Map<String, dynamic>? _payments;
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
    final today = todayIso();
    final monthStart = monthStartIso();
    try {
      switch (_tab) {
        case 'STOCK':
          _stockVal = asMap(await api.get('/reports/stock-valuation'));
          break;
        case 'MARGIN':
          _margin = asMap(await api.get('/reports/gross-margin', query: {
            'startDate': monthStart,
            'endDate': today,
          }));
          break;
        case 'TRIAL':
          _trial = asMap(await api.get('/reports/trial-balance', query: {'asOfDate': today}));
          break;
        case 'AGEING':
          _ageing = asMap(await api.get('/reports/ar-ap-ageing', query: {
            'asOfDate': today,
            'kind': _ageingKind,
          }));
          break;
        case 'PAYMENTS':
          _payments = asMap(await api.get('/payments'));
          break;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _switchTab(String next) {
    setState(() => _tab = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Financial Ledgers'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.teal,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            PillTabs<String>(
              selected: _tab,
              onChanged: _switchTab,
              items: const [
                ('STOCK', 'Vault Valuation', Icons.diamond_outlined),
                ('MARGIN', 'Sales & Margin', Icons.trending_up_rounded),
                ('TRIAL', 'Trial Balance', Icons.balance_rounded),
                ('AGEING', 'AR / AP Ageing', Icons.schedule_rounded),
                ('PAYMENTS', 'Settlements', Icons.account_balance_wallet_outlined),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading) ...[
              const Panel(child: Skeleton(height: 110)),
              const SizedBox(height: 12),
              const Panel(child: Skeleton(height: 80)),
              const SizedBox(height: 12),
              const Panel(child: Skeleton(height: 80)),
            ] else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else ...[
              if (_tab == 'STOCK') _buildStockValuation(),
              if (_tab == 'MARGIN') _buildGrossMargin(),
              if (_tab == 'TRIAL') _buildTrialBalance(),
              if (_tab == 'AGEING') _buildAgeing(),
              if (_tab == 'PAYMENTS') _buildPayments(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStockValuation() {
    final d = _stockVal ?? const {};
    final s = asMap(d['summary']);
    final articles = asList(d, keys: const ['articles']);
    final lots = asList(d, keys: const ['materialLots']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LuxuryHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const EnterpriseBadge('Fine 999 Custody Valuation', icon: Icons.verified_rounded),
          const SizedBox(height: 12),
          Text(
            inr('${s['grandTotalInventoryCost'] ?? '0.00'}'),
            style: T.display(30, color: Pal.goldSoft),
          ),
          const SizedBox(height: 4),
          Text(
            'Total Pure 999 Fine Metal: ${fineGrams(s['grandPureFineGrams'] ?? '0')}',
            style: T.mono(13, color: Colors.white),
          ),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.14)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TAGGED ORNAMENTS', style: T.caps(9.5, color: Colors.white60)),
                const SizedBox(height: 3),
                Text('${s['totalTaggedPieces'] ?? articles.length} pcs · ${grams(s['totalTaggedGrossGrams'] ?? '0')}', style: T.body(12.5, color: Colors.white, w: FontWeight.w700)),
                Text(inr('${s['totalTaggedCost'] ?? '0.00'}'), style: T.mono(12, color: Pal.goldSoft)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('BULLION LOTS', style: T.caps(9.5, color: Colors.white60)),
                const SizedBox(height: 3),
                Text(grams(s['totalMaterialLotsGrossGrams'] ?? '0'), style: T.body(12.5, color: Colors.white, w: FontWeight.w700)),
                Text(inr('${s['totalMaterialLotsCost'] ?? '0.00'}'), style: T.mono(12, color: Pal.goldSoft)),
              ]),
            ),
          ]),
        ]),
      ),
      if (articles.isNotEmpty) ...[
        SectionLabel('Tagged Stock Valuation (${articles.length})'),
        for (final a in articles)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  MonoTag('${a['tagNumber'] ?? a['tag'] ?? ''}'),
                  const Spacer(),
                  Text(inr('${a['costAmount'] ?? '0.00'}'), style: T.display(17)),
                ]),
                const SizedBox(height: 8),
                KeyValue('Location', '${a['locationName'] ?? '-'}'),
                KeyValue('Gross / Fine 999', '${grams(a['grossWeightGrams'] ?? '0')} · ${fineGrams(a['fineWeightGrams'] ?? '0')}', mono: true),
              ]),
            ),
          ),
      ],
      if (lots.isNotEmpty) ...[
        SectionLabel('Fungible Bullion Lots (${lots.length})'),
        for (final l in lots)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  MonoTag('${l['lotCode'] ?? ''}'),
                  const SizedBox(width: 8),
                  Chip2('${l['metalCode'] ?? ''} ${pct(l['fineness'] ?? '') == '0%' ? '' : l['fineness'] ?? ''}'),
                  const Spacer(),
                  Text(inr('${l['costAmount'] ?? '0.00'}'), style: T.display(17)),
                ]),
                const SizedBox(height: 8),
                KeyValue('Quantity / Fine', '${grams(l['quantityGrams'] ?? '0')} · ${fineGrams(l['fineWeightGrams'] ?? '0')}', mono: true),
              ]),
            ),
          ),
      ],
      if (articles.isEmpty && lots.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Panel(
            child: EmptyBlock(
              icon: Icons.inventory_2_outlined,
              title: 'Vault valuation is zero',
              body: 'Receive tagged pieces or bullion lots to view FIFO cost layers and Fine 999 totals.',
            ),
          ),
        ),
    ]);
  }

  Widget _buildGrossMargin() {
    final d = _margin ?? const {};
    final s = asMap(d['summary']);
    final invoices = asList(d, keys: const ['invoices']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LuxuryHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const EnterpriseBadge('Month-to-Date Profitability', icon: Icons.insights_rounded),
            const Spacer(),
            StatusPill('${pct(s['overallGrossMarginPct'] ?? '0')} Margin', tone: Tone.gold),
          ]),
          const SizedBox(height: 12),
          Text(inr('${s['totalNetRevenue'] ?? '0.00'}'), style: T.display(30, color: Colors.white)),
          Text('Net Taxable Revenue (${formatDate(d['startDate'])} – ${formatDate(d['endDate'])})', style: T.body(12, color: Colors.white70)),
          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.14)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('HISTORICAL COGS', style: T.caps(9.5, color: Colors.white60)),
                const SizedBox(height: 3),
                Text(inr('${s['totalCogsCost'] ?? '0.00'}'), style: T.mono(13.5, color: Colors.white)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('GROSS PROFIT', style: T.caps(9.5, color: Colors.white60)),
                const SizedBox(height: 3),
                Text(inr('${s['totalGrossProfit'] ?? '0.00'}'), style: T.mono(13.5, color: Pal.goldSoft)),
              ]),
            ),
          ]),
        ]),
      ),
      SectionLabel('Posted Invoice Margins (${invoices.length})'),
      if (invoices.isEmpty)
        const Panel(
          child: EmptyBlock(
            icon: Icons.receipt_long_outlined,
            title: 'No posted invoices this month',
            body: 'Issued and posted GST sales invoices appear here with exact FIFO COGS and margin.',
          ),
        )
      else
        for (final inv in invoices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${inv['documentNumber'] ?? 'Invoice'}', style: T.display(17))),
                  StatusPill('${pct(inv['grossMarginPct'] ?? '0')} GP', tone: Tone.ok),
                ]),
                const SizedBox(height: 8),
                KeyValue('Customer', '${inv['customerName'] ?? 'Walk-in'}', strong: true),
                KeyValue('Invoice Date', formatDate(inv['invoiceDate'])),
                KeyValue('Total (incl. GST)', inr('${inv['totalAmount'] ?? '0.00'}'), mono: true),
                KeyValue('Gross Profit', inr('${inv['grossProfit'] ?? '0.00'}'), strong: true, valueColor: Pal.ok),
              ]),
            ),
          ),
    ]);
  }

  Widget _buildTrialBalance() {
    final d = _trial ?? const {};
    final balanced = d['isBalanced'] != false;
    final accounts = asList(d, keys: const ['accounts']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LuxuryHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const EnterpriseBadge('Double-Entry Ledger', icon: Icons.balance_rounded),
            const Spacer(),
            StatusPill(balanced ? 'BALANCED' : 'VARIANCE'),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('TOTAL DEBITS', style: T.caps(9.5, color: Colors.white60)),
                const SizedBox(height: 4),
                Text(inr('${d['totalDebit'] ?? '0.00'}'), style: T.display(20, color: Pal.goldSoft)),
              ]),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('TOTAL CREDITS', style: T.caps(9.5, color: Colors.white60)),
                const SizedBox(height: 4),
                Text(inr('${d['totalCredit'] ?? '0.00'}'), style: T.display(20, color: Colors.white)),
              ]),
            ),
          ]),
        ]),
      ),
      SectionLabel('Account Balances (${accounts.length})'),
      if (accounts.isEmpty)
        const Panel(
          child: EmptyBlock(
            icon: Icons.account_balance_outlined,
            title: 'No posted ledger entries',
            body: 'Double-entry account balances appear automatically once journals and invoices post.',
          ),
        )
      else
        Panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < accounts.length; i++) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                child: Row(children: [
                  MonoTag('${accounts[i]['code'] ?? ''}'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${accounts[i]['name'] ?? ''}', style: T.body(13.8, w: FontWeight.w700)),
                      Text('${accounts[i]['group'] ?? ''}', style: T.caps(9.5, color: Pal.muted)),
                    ]),
                  ),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (decOrZero(accounts[i]['closingDebit']) > decOrZero('0'))
                      Text('Dr ${inr(accounts[i]['closingDebit'])}', style: T.mono(12.5, color: Pal.text))
                    else if (decOrZero(accounts[i]['closingCredit']) > decOrZero('0'))
                      Text('Cr ${inr(accounts[i]['closingCredit'])}', style: T.mono(12.5, color: Pal.teal))
                    else
                      Text('₹0.00', style: T.mono(12.5, color: Pal.muted)),
                  ]),
                ]),
              ),
            ],
          ]),
        ),
    ]);
  }

  Widget _buildAgeing() {
    final d = _ageing ?? const {};
    final s = asMap(d['summary']);
    final parties = asList(d, keys: const ['parties']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'RECEIVABLE', label: Text('Customer Receivables (AR)')),
          ButtonSegment(value: 'PAYABLE', label: Text('Supplier Payables (AP)')),
        ],
        selected: {_ageingKind},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: Pal.ink,
          selectedForegroundColor: Colors.white,
          side: const BorderSide(color: Pal.line),
          textStyle: T.body(12.5, w: FontWeight.w700),
        ),
        onSelectionChanged: (sel) {
          setState(() => _ageingKind = sel.first);
          _load();
        },
      ),
      const SizedBox(height: 14),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.75,
        children: [
          MetricTile(label: 'Total Open', value: inr('${s['totalOpen'] ?? '0.00'}', paise: false), icon: Icons.account_balance_wallet_outlined),
          MetricTile(label: 'Current (0–30d)', value: inr('${s['current'] ?? '0.00'}', paise: false), icon: Icons.check_circle_outline_rounded, accent: Pal.ok, accentWash: Pal.okWash),
          MetricTile(label: '31–60 Days', value: inr('${s['days31To60'] ?? '0.00'}', paise: false), icon: Icons.timelapse_rounded, accent: Pal.warn, accentWash: Pal.warnWash),
          MetricTile(label: 'Over 60 Days', value: inr((decOrZero(s['days61To90']) + decOrZero(s['daysOver90'])).toStringAsFixed(2), paise: false), icon: Icons.warning_amber_rounded, accent: Pal.danger, accentWash: Pal.dangerWash),
        ],
      ),
      SectionLabel('Party Dues (${parties.length})'),
      if (parties.isEmpty)
        const Panel(
          child: EmptyBlock(
            icon: Icons.verified_outlined,
            title: 'Zero overdue balances',
            body: 'All open items in this ledger category are settled.',
          ),
        )
      else
        for (final p in parties)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      p['party'] is Map ? '${(p['party'] as Map)['name'] ?? ''}' : 'Party',
                      style: T.body(15, w: FontWeight.w800),
                    ),
                  ),
                  Text(inr('${p['totalOpen'] ?? '0.00'}'), style: T.display(17.5, color: Pal.danger)),
                ]),
                const SizedBox(height: 8),
                KeyValue('Current (0–30d)', inr('${p['current'] ?? '0.00'}'), mono: true),
                KeyValue('Overdue (31d+)', inr((decOrZero(p['days31To60']) + decOrZero(p['days61To90']) + decOrZero(p['daysOver90'])).toStringAsFixed(2)), mono: true),
              ]),
            ),
          ),
    ]);
  }

  Widget _buildPayments() {
    final d = _payments ?? const {};
    final openItems = asList(d, keys: const ['openItems']);
    final settlements = asList(d, keys: const ['settlements']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: MetricTile(
            label: 'Open Items',
            value: '${openItems.length}',
            subtitle: 'Unsettled AR / AP docs',
            icon: Icons.pending_actions_rounded,
            accent: Pal.warn,
            accentWash: Pal.warnWash,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricTile(
            label: 'Settlements',
            value: '${settlements.length}',
            subtitle: 'Receipts & payouts',
            icon: Icons.payments_outlined,
          ),
        ),
      ]),
      SectionLabel('Recent Settlements (${settlements.length})'),
      if (settlements.isEmpty)
        const Panel(
          child: EmptyBlock(
            icon: Icons.payments_outlined,
            title: 'No settlement vouchers yet',
            body: 'Customer receipts, UPI/Card clearings, and supplier disbursements appear here.',
          ),
        )
      else
        for (final s in settlements)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${s['documentNumber'] ?? 'Settlement'}', style: T.display(17))),
                  StatusPill('${s['state'] ?? 'POSTED'}'),
                ]),
                const SizedBox(height: 8),
                KeyValue(
                  'Party',
                  s['party'] is Map ? '${(s['party'] as Map)['displayName'] ?? ''}' : '-',
                  strong: true,
                ),
                KeyValue('Method', '${s['method'] ?? '-'} · ${s['direction'] ?? ''}'),
                KeyValue('Amount', inr('${s['amount'] ?? '0.00'}'), strong: true),
                KeyValue('Date', formatDate(s['settlementDate'])),
              ]),
            ),
          ),
    ]);
  }
}
