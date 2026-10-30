import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

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
  final _search = TextEditingController();
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    return LuxuryModuleScaffold(
      title: 'Reports & Financial Ledgers',
      icon: Icons.insights_rounded,
      searchController: _search,
      searchHint: 'Search by Tag, Invoice, Account or Party...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
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
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
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
        for (final a in articles.where((a) {
          final q = _search.text.trim().toLowerCase();
          if (q.isEmpty) return true;
          return '${a['tagNumber'] ?? a['tag'] ?? ''} ${a['locationName'] ?? ''}'.toLowerCase().contains(q);
        }))
          LuxuryRecordCard(
            icon: Icons.diamond_outlined,
            code: '${a['tagNumber'] ?? a['tag'] ?? 'Article'}',
            status: 'CUSTODY',
            lines: [
              ('Location', '${a['locationName'] ?? '-'}'),
              ('Gross / Fine 999', '${grams(a['grossWeightGrams'] ?? '0')} · ${fineGrams(a['fineWeightGrams'] ?? '0')}'),
            ],
            amountLabel: 'FIFO Cost',
            amountValue: inr('${a['costAmount'] ?? '0.00'}'),
          ),
      ],
      if (lots.isNotEmpty) ...[
        SectionLabel('Fungible Bullion Lots (${lots.length})'),
        for (final l in lots.where((l) {
          final q = _search.text.trim().toLowerCase();
          if (q.isEmpty) return true;
          return '${l['lotCode'] ?? ''} ${l['metalCode'] ?? ''}'.toLowerCase().contains(q);
        }))
          LuxuryRecordCard(
            icon: Icons.layers_outlined,
            code: '${l['lotCode'] ?? 'Lot'}',
            status: '${l['metalCode'] ?? 'BULLION'}',
            lines: [
              ('Quantity / Fine', '${grams(l['quantityGrams'] ?? '0')} · ${fineGrams(l['fineWeightGrams'] ?? '0')}'),
            ],
            amountLabel: 'FIFO Cost',
            amountValue: inr('${l['costAmount'] ?? '0.00'}'),
          ),
      ],
      if (articles.isEmpty && lots.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: SaasEmptyBox(
            'Vault valuation is zero. Receive tagged pieces or bullion lots to view FIFO cost layers and Fine 999 totals.',
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
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EnterpriseBadge('MTD Profitability', icon: Icons.insights_rounded),
              ),
            ),
            const SizedBox(width: 8),
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
        const SaasEmptyBox(
          'No posted invoices this month. Issued and posted GST sales invoices appear here with FIFO COGS and margin.',
        )
      else
        for (final inv in invoices.where((inv) {
          final q = _search.text.trim().toLowerCase();
          if (q.isEmpty) return true;
          return '${inv['documentNumber'] ?? ''} ${inv['customerName'] ?? ''}'.toLowerCase().contains(q);
        }))
          LuxuryRecordCard(
            icon: Icons.receipt_long_outlined,
            code: '${inv['documentNumber'] ?? 'Invoice'}',
            status: '${pct(inv['grossMarginPct'] ?? '0')} GP',
            lines: [
              ('Customer', '${inv['customerName'] ?? 'Walk-in'}'),
              ('Invoice Date', formatDate(inv['invoiceDate'])),
              ('Invoice Total', inr('${inv['totalAmount'] ?? '0.00'}')),
            ],
            amountLabel: 'Gross Profit',
            amountValue: inr('${inv['grossProfit'] ?? '0.00'}'),
          ),
    ]);
  }

  Widget _buildTrialBalance() {
    final d = _trial ?? const {};
    final balanced = d['isBalanced'] != false;
    final accounts = asList(d, keys: const ['accounts']);
    final q = _search.text.trim().toLowerCase();
    final fAccounts = accounts.where((acc) {
      if (q.isEmpty) return true;
      return '${acc['code'] ?? ''} ${acc['name'] ?? ''} ${acc['group'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LuxuryHeroCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: EnterpriseBadge('Double-Entry Ledger', icon: Icons.balance_rounded),
              ),
            ),
            const SizedBox(width: 8),
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
      SectionLabel('Account Balances (${fAccounts.length})'),
      if (fAccounts.isEmpty)
        const SaasEmptyBox('No posted ledger entries match your filter.')
      else
        for (final acc in fAccounts)
          LuxuryRecordCard(
            icon: Icons.account_balance_outlined,
            code: '${acc['code'] ?? ''} · ${acc['name'] ?? ''}',
            status: '${acc['group'] ?? 'LEDGER'}',
            lines: [
              ('Account Group', '${acc['group'] ?? '-'}'),
            ],
            amountLabel: decOrZero(acc['closingDebit']) > decOrZero('0') ? 'Closing Dr' : 'Closing Cr',
            amountValue: decOrZero(acc['closingDebit']) > decOrZero('0')
                ? inr(acc['closingDebit'])
                : inr(acc['closingCredit'] ?? '0.00'),
          ),
    ]);
  }

  Widget _buildAgeing() {
    final d = _ageing ?? const {};
    final s = asMap(d['summary']);
    final parties = asList(d, keys: const ['parties']);
    final q = _search.text.trim().toLowerCase();
    final fParties = parties.where((p) {
      if (q.isEmpty) return true;
      return '${asMap(p['party'])['name'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LuxurySubChips<String>(
        value: _ageingKind,
        onChanged: (v) {
          setState(() => _ageingKind = v);
          _load();
        },
        items: const [
          ('RECEIVABLE', 'Customer Receivables (AR)'),
          ('PAYABLE', 'Supplier Payables (AP)'),
        ],
      ),
      const SizedBox(height: 14),
      ResponsiveGrid2(
        children: [
          MetricTile(label: 'Total Open', value: inr('${s['totalOpen'] ?? '0.00'}', paise: false), icon: Icons.account_balance_wallet_outlined),
          MetricTile(label: 'Current (0–30d)', value: inr('${s['current'] ?? '0.00'}', paise: false), icon: Icons.check_circle_outline_rounded, accent: Pal.ok, accentWash: Pal.okWash),
          MetricTile(label: '31–60 Days', value: inr('${s['days31To60'] ?? '0.00'}', paise: false), icon: Icons.timelapse_rounded, accent: Pal.warn, accentWash: Pal.warnWash),
          MetricTile(label: 'Over 60 Days', value: inr((decOrZero(s['days61To90']) + decOrZero(s['daysOver90'])).toStringAsFixed(2), paise: false), icon: Icons.warning_amber_rounded, accent: Pal.danger, accentWash: Pal.dangerWash),
        ],
      ),
      SectionLabel('Party Dues (${fParties.length})'),
      if (fParties.isEmpty)
        const SaasEmptyBox('Zero overdue balances in this ledger category.')
      else
        for (final p in fParties)
          LuxuryRecordCard(
            icon: Icons.person_outline_rounded,
            code: p['party'] is Map ? '${(p['party'] as Map)['name'] ?? 'Party'}' : 'Party',
            status: _ageingKind,
            lines: [
              ('Current (0–30d)', inr('${p['current'] ?? '0.00'}')),
              ('Overdue (31d+)', inr((decOrZero(p['days31To60']) + decOrZero(p['days61To90']) + decOrZero(p['daysOver90'])).toStringAsFixed(2))),
            ],
            amountLabel: 'Total Open',
            amountValue: inr('${p['totalOpen'] ?? '0.00'}'),
          ),
    ]);
  }

  Widget _buildPayments() {
    final d = _payments ?? const {};
    final openItems = asList(d, keys: const ['openItems']);
    final settlements = asList(d, keys: const ['settlements']);
    final q = _search.text.trim().toLowerCase();
    final fSettlements = settlements.where((s) {
      if (q.isEmpty) return true;
      return '${s['documentNumber'] ?? ''} ${asMap(s['party'])['displayName'] ?? ''} ${s['method'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

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
      SectionLabel('Recent Settlements (${fSettlements.length})'),
      if (fSettlements.isEmpty)
        const SaasEmptyBox('No settlement vouchers found.')
      else
        for (final s in fSettlements)
          LuxuryRecordCard(
            icon: Icons.payments_outlined,
            code: '${s['documentNumber'] ?? 'Settlement'}',
            status: '${s['state'] ?? 'POSTED'}',
            lines: [
              ('Party', s['party'] is Map ? '${(s['party'] as Map)['displayName'] ?? '-'}' : '-'),
              ('Method', '${s['method'] ?? '-'} · ${s['direction'] ?? ''}'),
              ('Date', formatDate(s['settlementDate'])),
            ],
            amountLabel: 'Amount',
            amountValue: inr('${s['amount'] ?? '0.00'}'),
          ),
    ]);
  }
}
