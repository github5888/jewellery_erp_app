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

/// `Audit & Compliance Reports` (`Financial & Commercial Intelligence Reports`)
/// — Exact 1:1 mobile parity with `pos.hrpocket.in` (`image-49.png`..`image-54.png`):
/// 1. Trial Balance (`GET /reports/trial-balance`)
/// 2. General Ledger (`GET /reports/general-ledger`)
/// 3. Party Statement (`GET /reports/party-statement`)
/// 4. AR / AP Ageing (`GET /reports/ar-ap-ageing`)
/// 5. Stock Valuation (`GET /reports/stock-valuation`)
/// 6. Gross Margin (`GET /reports/gross-margin`)
/// + Persistent `Profit & Loss / Balance Sheet` statement generator card.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.initialTab = 'TRIAL'});
  final String initialTab;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

typedef AuditComplianceReportsScreen = ReportsScreen;

class _ReportsScreenState extends State<ReportsScreen> {
  static String _indianFyStartIso() {
    final now = todayIso();
    final y = int.tryParse(now.substring(0, 4)) ?? 2026;
    final m = int.tryParse(now.substring(5, 7)) ?? 10;
    final fyYear = m >= 4 ? y : y - 1;
    return '$fyYear-04-01';
  }

  final _search = TextEditingController();
  late String _tab;
  WorkspaceLookup _lk = WorkspaceLookup();

  bool _loading = true;
  bool _stmtBusy = false;
  String? _error;

  // 1. Trial Balance (`image-49.png`)
  final _tbAsOf = TextEditingController(text: todayIso());
  Map<String, dynamic>? _trial;

  // 2. General Ledger (`image-50.png`)
  final _glFrom = TextEditingController(text: monthStartIso());
  final _glTo = TextEditingController(text: todayIso());
  final _glAccountId = TextEditingController();
  Map<String, dynamic>? _ledger;

  // 3. Party Statement (`image-51.png`)
  final _psFrom = TextEditingController(text: monthStartIso());
  final _psTo = TextEditingController(text: todayIso());
  final _psPartyId = TextEditingController();
  Map<String, dynamic>? _partyStmt;

  // 4. AR / AP Ageing (`image-52.png`)
  final _ageingAsOf = TextEditingController(text: todayIso());
  String _ageingKind = 'RECEIVABLE';
  Map<String, dynamic>? _ageing;

  // 5. Stock Valuation (`image-53.png`)
  Map<String, dynamic>? _stockVal;

  // 6. Gross Margin (`image-54.png`)
  final _gmFrom = TextEditingController(text: monthStartIso());
  final _gmTo = TextEditingController(text: todayIso());
  Map<String, dynamic>? _margin;

  // Bottom `Profit & Loss / Balance Sheet` card (`image-49..54.png`)
  String _stmtKind = 'PROFIT_AND_LOSS';
  final _stmtStart = TextEditingController(text: _indianFyStartIso());
  final _stmtEnd = TextEditingController(text: todayIso());
  final _stmtCurrency = TextEditingController(text: 'INR');
  Map<String, dynamic>? _stmtResult;

  @override
  void initState() {
    super.initState();
    const validTabs = {'TRIAL', 'LEDGER', 'PARTY', 'AGEING', 'STOCK', 'MARGIN'};
    _tab = validTabs.contains(widget.initialTab) ? widget.initialTab : 'TRIAL';
    _initLookupsAndLoad();
  }

  @override
  void dispose() {
    for (final c in [
      _search,
      _tbAsOf,
      _glFrom,
      _glTo,
      _glAccountId,
      _psFrom,
      _psTo,
      _psPartyId,
      _ageingAsOf,
      _gmFrom,
      _gmTo,
      _stmtStart,
      _stmtEnd,
      _stmtCurrency,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _initLookupsAndLoad() async {
    final api = context.read<ApiClient>();
    try {
      final lk = await WorkspaceLookup.load(
        api,
        includeParties: true,
        includeAccounting: true,
      );
      if (mounted) {
        setState(() => _lk = lk);
      }
    } catch (_) {}
    await _loadActiveTab();
  }

  Future<void> _loadActiveTab() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      switch (_tab) {
        case 'TRIAL':
          final asOf = _tbAsOf.text.trim().isEmpty
              ? todayIso()
              : _tbAsOf.text.trim();
          final d = await api.get(
            '/reports/trial-balance',
            query: {'asOfDate': asOf},
          );
          if (mounted) setState(() => _trial = asMap(d));
          break;

        case 'LEDGER':
          final acctId = _glAccountId.text.trim();
          if (acctId.isEmpty) {
            if (mounted) setState(() => _ledger = null);
          } else {
            final from = _glFrom.text.trim();
            final to = _glTo.text.trim();
            final d = await api.get(
              '/reports/general-ledger',
              query: {
                'accountId': acctId,
                if (from.isNotEmpty) 'startDate': from,
                if (from.isNotEmpty) 'from': from,
                if (to.isNotEmpty) 'endDate': to,
                if (to.isNotEmpty) 'to': to,
              },
            );
            if (mounted) setState(() => _ledger = asMap(d));
          }
          break;

        case 'PARTY':
          final partyId = _psPartyId.text.trim();
          if (partyId.isEmpty) {
            if (mounted) setState(() => _partyStmt = null);
          } else {
            final from = _psFrom.text.trim();
            final to = _psTo.text.trim();
            final d = await api.get(
              '/reports/party-statement',
              query: {
                'partyId': partyId,
                if (from.isNotEmpty) 'startDate': from,
                if (from.isNotEmpty) 'from': from,
                if (to.isNotEmpty) 'endDate': to,
                if (to.isNotEmpty) 'to': to,
              },
            );
            if (mounted) setState(() => _partyStmt = asMap(d));
          }
          break;

        case 'AGEING':
          final asOf = _ageingAsOf.text.trim().isEmpty
              ? todayIso()
              : _ageingAsOf.text.trim();
          final d = await api.get(
            '/reports/ar-ap-ageing',
            query: {
              'asOfDate': asOf,
              'kind': _ageingKind,
            },
          );
          if (mounted) setState(() => _ageing = asMap(d));
          break;

        case 'STOCK':
          final d = await api.get('/reports/stock-valuation');
          if (mounted) setState(() => _stockVal = asMap(d));
          break;

        case 'MARGIN':
          final from = _gmFrom.text.trim();
          final to = _gmTo.text.trim();
          final d = await api.get(
            '/reports/gross-margin',
            query: {
              if (from.isNotEmpty) 'startDate': from,
              if (from.isNotEmpty) 'from': from,
              if (to.isNotEmpty) 'endDate': to,
              if (to.isNotEmpty) 'to': to,
            },
          );
          if (mounted) setState(() => _margin = asMap(d));
          break;
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _switchTab(String next) {
    if (next == _tab) return;
    setState(() => _tab = next);
    _loadActiveTab();
  }

  String _inrCode(Object? v) {
    final d = decOrZero(v).round(scale: 2);
    final neg = d < Decimal.zero;
    final absStr = d.abs().toStringAsFixed(2);
    final formatted = inr(absStr);
    final clean = formatted.startsWith('₹')
        ? formatted.substring(1)
        : formatted;
    return '${neg ? '-' : ''}INR $clean';
  }

  String _grams6(Object? v) {
    final d = decOrZero(v).round(scale: 6);
    return '${d.toStringAsFixed(6)}g';
  }

  Future<void> _generateStatement() async {
    setState(() {
      _stmtBusy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final start = _stmtStart.text.trim();
      final end = _stmtEnd.text.trim().isEmpty
          ? todayIso()
          : _stmtEnd.text.trim();
      final ccy = _stmtCurrency.text.trim().isEmpty
          ? 'INR'
          : _stmtCurrency.text.trim().toUpperCase();

      final tb = asMap(
        await api.get(
          '/reports/trial-balance',
          query: {
            if (start.isNotEmpty) 'startDate': start,
            'asOfDate': end,
          },
        ),
      );
      if (!mounted) return;

      final acctGroupById = <String, String>{
        for (final a in _lk.accounts)
          a.id: '${a.raw['group'] ?? ''}'.toUpperCase(),
      };
      final acctGroupByCode = <String, String>{
        for (final a in _lk.accounts)
          '${a.raw['code'] ?? ''}'.toUpperCase():
              '${a.raw['group'] ?? ''}'.toUpperCase(),
      };

      final tbRows = asList(
        tb['accounts'] ?? tb['rows'] ?? tb['lines'] ?? tb,
      );

      final incomeRows = <Map<String, dynamic>>[];
      final expenseRows = <Map<String, dynamic>>[];
      final assetRows = <Map<String, dynamic>>[];
      final liabilityRows = <Map<String, dynamic>>[];
      final equityRows = <Map<String, dynamic>>[];

      var totalIncome = Decimal.zero;
      var totalExpense = Decimal.zero;
      var totalAssets = Decimal.zero;
      var totalLiabilities = Decimal.zero;
      var totalEquity = Decimal.zero;

      for (final row in tbRows) {
        final id = '${row['accountId'] ?? row['id'] ?? ''}';
        final code = '${row['code'] ?? row['accountCode'] ?? ''}'.toUpperCase();
        final name = '${row['name'] ?? row['accountName'] ?? code}';
        final grp = ('${row['group'] ?? row['accountGroup'] ?? ''}'
                    .toUpperCase()
                    .isNotEmpty
                ? '${row['group'] ?? row['accountGroup']}'.toUpperCase()
                : (acctGroupById[id] ?? acctGroupByCode[code] ?? ''))
            .trim();

        final dr = decOrZero(
          row['closingDebit'] ?? row['debit'] ?? row['debitBalance'],
        );
        final cr = decOrZero(
          row['closingCredit'] ?? row['credit'] ?? row['creditBalance'],
        );

        if (grp == 'INCOME' || grp == 'REVENUE') {
          final net = cr - dr;
          totalIncome += net;
          incomeRows.add({
            'code': code,
            'name': name,
            'amount': net.toStringAsFixed(2),
          });
        } else if (grp == 'EXPENSE' || grp == 'EXPENSES') {
          final net = dr - cr;
          totalExpense += net;
          expenseRows.add({
            'code': code,
            'name': name,
            'amount': net.toStringAsFixed(2),
          });
        } else if (grp == 'ASSET' || grp == 'ASSETS') {
          final net = dr - cr;
          totalAssets += net;
          assetRows.add({
            'code': code,
            'name': name,
            'amount': net.toStringAsFixed(2),
          });
        } else if (grp == 'LIABILITY' || grp == 'LIABILITIES') {
          final net = cr - dr;
          totalLiabilities += net;
          liabilityRows.add({
            'code': code,
            'name': name,
            'amount': net.toStringAsFixed(2),
          });
        } else if (grp == 'EQUITY' || grp == 'CAPITAL') {
          final net = cr - dr;
          totalEquity += net;
          equityRows.add({
            'code': code,
            'name': name,
            'amount': net.toStringAsFixed(2),
          });
        }
      }

      final netProfit = totalIncome - totalExpense;
      setState(() {
        _stmtResult = {
          'kind': _stmtKind,
          'startDate': start,
          'endDate': end,
          'currency': ccy,
          'incomeRows': incomeRows,
          'expenseRows': expenseRows,
          'assetRows': assetRows,
          'liabilityRows': liabilityRows,
          'equityRows': equityRows,
          'totalIncome': totalIncome.toStringAsFixed(2),
          'totalExpense': totalExpense.toStringAsFixed(2),
          'netProfit': netProfit.toStringAsFixed(2),
          'totalAssets': totalAssets.toStringAsFixed(2),
          'totalLiabilities': totalLiabilities.toStringAsFixed(2),
          'totalEquity': totalEquity.toStringAsFixed(2),
        };
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _stmtBusy = false);
    }
  }

  Widget _buildSummaryBox({
    required String label,
    required String value,
    String? subline,
    String? footerLabel,
    String? footerValue,
    Color valueColor = Pal.ink,
    bool mintTint = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: mintTint ? const Color(0xFFF0FDF8) : Pal.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: mintTint ? const Color(0xFFB7EBDD) : Pal.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: T.body(
              11.5,
              weight: FontWeight.w600,
              color: mintTint ? const Color(0xFF0F766E) : Pal.muted,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.mono(17, weight: FontWeight.w800, color: valueColor),
          ),
          if (subline != null && subline.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subline,
              style: T.body(11.3, color: Pal.muted),
            ),
          ],
          if (footerLabel != null && footerLabel.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              footerLabel,
              style: T.body(
                11,
                weight: FontWeight.w600,
                color: mintTint ? const Color(0xFF0F766E) : Pal.muted,
              ),
            ),
          ],
          if (footerValue != null && footerValue.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              footerValue,
              style: T.mono(
                13.2,
                weight: FontWeight.w700,
                color: const Color(0xFF0F766E),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // TAB 1: TRIAL BALANCE (`image-49.png`)
  // -------------------------------------------------------------------------
  Widget _buildTrialBalanceTab(String q) {
    final d = _trial ?? const {};
    final balanced = d['isBalanced'] != false;
    final totalDebit =
        d['totalDebit'] ?? d['debitTotal'] ?? asMap(d['summary'])['totalDebit'] ?? '0.00';
    final totalCredit =
        d['totalCredit'] ?? d['creditTotal'] ?? asMap(d['summary'])['totalCredit'] ?? '0.00';
    final asOf =
        '${d['asOfDate'] ?? (_tbAsOf.text.trim().isEmpty ? todayIso() : _tbAsOf.text.trim())}';
    final accounts = asList(
      d['accounts'] ?? d['rows'] ?? d['lines'],
    ).where((acc) {
      if (q.isEmpty) return true;
      return '${acc['code'] ?? ''} ${acc['name'] ?? ''} ${acc['group'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Pal.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Pal.border),
          ),
          child: DatePickField(
            label: 'As of date',
            controller: _tbAsOf,
            onChanged: (_) => _loadActiveTab(),
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Panel(child: Skeleton(height: 96))
        else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Pal.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: balanced ? const Color(0xFFB7EBDD) : Pal.danger,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      balanced
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      color: balanced ? Pal.ok : Pal.danger,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            balanced
                                ? 'Trial Balance is in Exact Balance'
                                : 'Trial Balance Variance Detected',
                            style: T.body(
                              14.2,
                              weight: FontWeight.w700,
                              color: Pal.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            balanced
                                ? 'As of $asOf · Sum of Debits equals Sum of Credits'
                                : 'As of $asOf · Review unposted or out-of-balance entries',
                            style: T.body(11.8, color: Pal.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1, color: Pal.divider),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Debits',
                            style: T.body(11.3, color: Pal.muted),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _inrCode(totalDebit),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.mono(
                              14.5,
                              weight: FontWeight.w800,
                              color: Pal.ink,
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
                            'Total Credits',
                            style: T.body(11.3, color: Pal.muted),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _inrCode(totalCredit),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.mono(
                              14.5,
                              weight: FontWeight.w800,
                              color: Pal.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Pal.bgTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Pal.border),
            ),
            child: Text(
              'Account Code · Account Name · Group · Debit Balance · Credit Balance',
              style: T.body(11.4, weight: FontWeight.w700, color: Pal.muted),
            ),
          ),
          const SizedBox(height: 8),
          if (accounts.isEmpty)
            const SaasEmptyBox('No posted ledger account balances as of this date.')
          else
            for (final acc in accounts)
              LuxuryRecordCard(
                icon: Icons.account_balance_outlined,
                code:
                    '${acc['code'] ?? acc['accountCode'] ?? ''} · ${acc['name'] ?? acc['accountName'] ?? 'Ledger'}',
                status: '${acc['group'] ?? acc['accountGroup'] ?? 'LEDGER'}',
                onTap: () {
                  final id = '${acc['accountId'] ?? acc['id'] ?? ''}'.trim();
                  if (id.isNotEmpty) {
                    setState(() {
                      _glAccountId.text = id;
                      _tab = 'LEDGER';
                    });
                    _loadActiveTab();
                  }
                },
                lines: [
                  (
                    'Debit Balance',
                    _inrCode(acc['closingDebit'] ?? acc['debitBalance'] ?? '0'),
                  ),
                  (
                    'Credit Balance',
                    _inrCode(
                      acc['closingCredit'] ?? acc['creditBalance'] ?? '0',
                    ),
                  ),
                ],
                amountLabel: decOrZero(
                          acc['closingDebit'] ?? acc['debitBalance'],
                        ) >=
                        decOrZero(acc['closingCredit'] ?? acc['creditBalance'])
                    ? 'Net Dr'
                    : 'Net Cr',
                amountValue: decOrZero(
                          acc['closingDebit'] ?? acc['debitBalance'],
                        ) >=
                        decOrZero(acc['closingCredit'] ?? acc['creditBalance'])
                    ? _inrCode(
                        acc['closingDebit'] ?? acc['debitBalance'] ?? '0',
                      )
                    : _inrCode(
                        acc['closingCredit'] ?? acc['creditBalance'] ?? '0',
                      ),
              ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // TAB 2: GENERAL LEDGER (`image-50.png`)
  // -------------------------------------------------------------------------
  Widget _buildGeneralLedgerTab(String q) {
    final hasAcct = _glAccountId.text.trim().isNotEmpty;
    final d = _ledger ?? const {};
    final entries = asList(
      d['entries'] ?? d['lines'] ?? d['transactions'] ?? d['rows'],
    ).where((e) {
      if (q.isEmpty) return true;
      return '${e['documentNumber'] ?? e['journalNumber'] ?? ''} ${e['description'] ?? e['narration'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Pal.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Pal.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DatePickField(
                      label: 'From',
                      controller: _glFrom,
                      onChanged: (_) {
                        if (_glAccountId.text.trim().isNotEmpty) {
                          _loadActiveTab();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DatePickField(
                      label: 'To',
                      controller: _glTo,
                      onChanged: (_) {
                        if (_glAccountId.text.trim().isNotEmpty) {
                          _loadActiveTab();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Account UUID',
                controller: _glAccountId,
                options: _lk.accounts,
                hint: 'Account UUID',
                onSelected: (_) => _loadActiveTab(),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: GoldButton(
                  label: 'Load General Ledger',
                  compact: true,
                  icon: Icons.manage_search_rounded,
                  onPressed: _loading ? null : _loadActiveTab,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!hasAcct)
          const SaasEmptyBox(
            'Enter an Account UUID above to view the general ledger statement and chronological entries.',
          )
        else if (_loading)
          const Panel(child: Skeleton(height: 96))
        else ...[
          SaasKpiGrid(
            items: [
              (
                label: 'OPENING BALANCE',
                value: _inrCode(
                  d['openingBalance'] ?? asMap(d['summary'])['openingBalance'],
                ),
              ),
              (
                label: 'TOTAL DEBITS',
                value: _inrCode(
                  d['totalDebit'] ?? asMap(d['summary'])['totalDebit'],
                ),
              ),
              (
                label: 'TOTAL CREDITS',
                value: _inrCode(
                  d['totalCredit'] ?? asMap(d['summary'])['totalCredit'],
                ),
              ),
              (
                label: 'CLOSING BALANCE',
                value: _inrCode(
                  d['closingBalance'] ?? asMap(d['summary'])['closingBalance'],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const SaasEmptyBox(
              'No chronological ledger entries posted for this account in the selected period.',
            )
          else
            for (final e in entries)
              LuxuryRecordCard(
                icon: Icons.menu_book_outlined,
                code:
                    '${e['documentNumber'] ?? e['journalNumber'] ?? shortId('${e['id'] ?? ''}')}',
                status: '${e['sourceType'] ?? 'POSTED'}',
                lines: [
                  (
                    'Posting Date',
                    fmtDate('${e['postingDate'] ?? e['entryDate'] ?? e['date'] ?? ''}'),
                  ),
                  if ('${e['description'] ?? e['narration'] ?? ''}'.isNotEmpty)
                    ('Narration', '${e['description'] ?? e['narration']}'),
                  ('Debit / Credit', '${_inrCode(e['debit'])} / ${_inrCode(e['credit'])}'),
                ],
                amountLabel: 'Running Bal',
                amountValue: _inrCode(e['runningBalance'] ?? e['balance']),
              ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // TAB 3: PARTY STATEMENT (`image-51.png`)
  // -------------------------------------------------------------------------
  Widget _buildPartyStatementTab(String q) {
    final hasParty = _psPartyId.text.trim().isNotEmpty;
    final d = _partyStmt ?? const {};
    final entries = asList(
      d['entries'] ?? d['transactions'] ?? d['lines'] ?? d['rows'],
    ).where((e) {
      if (q.isEmpty) return true;
      return '${e['documentNumber'] ?? ''} ${e['description'] ?? e['type'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Pal.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Pal.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DatePickField(
                      label: 'From',
                      controller: _psFrom,
                      onChanged: (_) {
                        if (_psPartyId.text.trim().isNotEmpty) {
                          _loadActiveTab();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DatePickField(
                      label: 'To',
                      controller: _psTo,
                      onChanged: (_) {
                        if (_psPartyId.text.trim().isNotEmpty) {
                          _loadActiveTab();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Select Customer / Counterparty (or enter Party UUID)',
                controller: _psPartyId,
                options: _lk.parties,
                hint: '-- Select Customer / Counterparty --',
                onSelected: (_) => _loadActiveTab(),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: GoldButton(
                  label: 'Load Party Statement',
                  compact: true,
                  icon: Icons.person_search_outlined,
                  onPressed: _loading ? null : _loadActiveTab,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (!hasParty)
          const SaasEmptyBox(
            'Enter a Party UUID above to view their statement of account with transaction timeline.',
          )
        else if (_loading)
          const Panel(child: Skeleton(height: 96))
        else ...[
          SaasKpiGrid(
            items: [
              (
                label: 'OPENING BALANCE',
                value: _inrCode(
                  d['openingBalance'] ?? asMap(d['summary'])['openingBalance'],
                ),
              ),
              (
                label: 'TOTAL DEBITS',
                value: _inrCode(
                  d['totalDebit'] ?? asMap(d['summary'])['totalDebit'],
                ),
              ),
              (
                label: 'TOTAL CREDITS',
                value: _inrCode(
                  d['totalCredit'] ?? asMap(d['summary'])['totalCredit'],
                ),
              ),
              (
                label: 'CLOSING BALANCE',
                value: _inrCode(
                  d['closingBalance'] ?? asMap(d['summary'])['closingBalance'],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            const SaasEmptyBox(
              'No counterparty ledger transactions posted in this period.',
            )
          else
            for (final e in entries)
              LuxuryRecordCard(
                icon: Icons.receipt_long_outlined,
                code:
                    '${e['documentNumber'] ?? e['reference'] ?? shortId('${e['id'] ?? ''}')}',
                status: '${e['documentType'] ?? e['type'] ?? 'ENTRY'}',
                lines: [
                  ('Date', fmtDate('${e['date'] ?? e['postingDate'] ?? ''}')),
                  if ('${e['description'] ?? ''}'.isNotEmpty)
                    ('Particulars', '${e['description']}'),
                  ('Dr / Cr', '${_inrCode(e['debit'])} / ${_inrCode(e['credit'])}'),
                ],
                amountLabel: 'Balance',
                amountValue: _inrCode(e['runningBalance'] ?? e['balance']),
              ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // TAB 4: AR / AP AGEING (`image-52.png`)
  // -------------------------------------------------------------------------
  Widget _buildAgeingTab(String q) {
    final d = _ageing ?? const {};
    final s = asMap(d['summary']);
    final parties = asList(
      d['parties'] ?? d['counterparties'] ?? d['rows'] ?? d['items'],
    ).where((p) {
      if (q.isEmpty) return true;
      final pName =
          '${asMap(p['party'])['displayName'] ?? asMap(p['party'])['name'] ?? p['partyName'] ?? ''}';
      return pName.toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Pal.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Pal.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: DatePickField(
                  label: 'As of date',
                  controller: _ageingAsOf,
                  onChanged: (_) => _loadActiveTab(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SaasDropdown(
                  label: 'Subledger',
                  value: _ageingKind,
                  options: const {
                    'RECEIVABLE': 'Customer Receivables',
                    'PAYABLE': 'Supplier Payables',
                  },
                  onChanged: (v) {
                    setState(() => _ageingKind = v);
                    _loadActiveTab();
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Panel(child: Skeleton(height: 120))
        else ...[
          _buildSummaryBox(
            label: 'Total Outstanding',
            value: _inrCode(s['totalOpen'] ?? s['totalOutstanding'] ?? '0'),
            valueColor: Pal.ink,
          ),
          const SizedBox(height: 10),
          ResponsiveGrid2(
            children: [
              _buildSummaryBox(
                label: 'Current (0–30 Days)',
                value: _inrCode(s['current'] ?? s['days0To30'] ?? '0'),
                valueColor: Pal.ok,
              ),
              _buildSummaryBox(
                label: '31–60 Days',
                value: _inrCode(s['days31To60'] ?? '0'),
                valueColor: const Color(0xFF1D4ED8),
              ),
              _buildSummaryBox(
                label: '61–90 Days',
                value: _inrCode(s['days61To90'] ?? '0'),
                valueColor: Pal.warn,
              ),
              _buildSummaryBox(
                label: 'Over 90 Days',
                value: _inrCode(s['daysOver90'] ?? s['over90Days'] ?? '0'),
                valueColor: Pal.danger,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Pal.bgTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Pal.border),
            ),
            child: Text(
              'Counterparty · Total Open · Current · 31–60 Days · 61–90 Days · Over 90 Days',
              style: T.body(11.4, weight: FontWeight.w700, color: Pal.muted),
            ),
          ),
          const SizedBox(height: 8),
          if (parties.isEmpty)
            const SaasEmptyBox('No overdue or open balances found.')
          else
            for (final p in parties)
              LuxuryRecordCard(
                icon: Icons.person_outline_rounded,
                code:
                    '${asMap(p['party'])['displayName'] ?? asMap(p['party'])['name'] ?? p['partyName'] ?? 'Counterparty'}',
                status: _ageingKind,
                onTap: () {
                  final pid =
                      '${asMap(p['party'])['id'] ?? p['partyId'] ?? ''}'.trim();
                  if (pid.isNotEmpty) {
                    setState(() {
                      _psPartyId.text = pid;
                      _tab = 'PARTY';
                    });
                    _loadActiveTab();
                  }
                },
                lines: [
                  ('Current (0–30d)', _inrCode(p['current'])),
                  ('31–60 / 61–90 Days', '${_inrCode(p['days31To60'])} / ${_inrCode(p['days61To90'])}'),
                  ('Over 90 Days', _inrCode(p['daysOver90'])),
                ],
                amountLabel: 'Total Open',
                amountValue: _inrCode(p['totalOpen']),
              ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // TAB 5: STOCK VALUATION (`image-53.png`)
  // -------------------------------------------------------------------------
  Widget _buildStockValuationTab(String q) {
    final d = _stockVal ?? const {};
    final s = asMap(d['summary']);
    final articles = asList(d['articles']);
    final lots = asList(d['materialLots']);

    final taggedPcs =
        '${s['totalTaggedPieces'] ?? articles.length} pcs';
    final taggedGross = _grams6(s['totalTaggedGrossGrams']);
    final taggedFine = _grams6(s['totalTaggedFineGrams']);
    final taggedCost = _inrCode(s['totalTaggedCost']);

    final lotsGross = _grams6(s['totalMaterialLotsGrossGrams']);
    final lotsFine = _grams6(s['totalMaterialLotsFineGrams']);
    final lotsCost = _inrCode(s['totalMaterialLotsCost']);

    final grandFine = _grams6(s['grandPureFineGrams']);
    final grandCost = _inrCode(s['grandTotalInventoryCost']);

    final combinedRows = <Map<String, dynamic>>[
      for (final a in articles)
        {
          '_kind': 'TAGGED',
          'code': '${a['tagNumber'] ?? a['tag'] ?? 'Article'}',
          'locOrMetal':
              '${a['locationName'] ?? a['metalCode'] ?? 'Showroom Custody'}',
          'gross': a['grossWeightGrams'],
          'fine': a['fineWeightGrams'],
          'cost': a['costAmount'] ?? a['valuationCost'],
        },
      for (final l in lots)
        {
          '_kind': 'LOT',
          'code': '${l['lotCode'] ?? l['code'] ?? 'Lot'}',
          'locOrMetal':
              '${l['locationName'] ?? ''}${l['metalCode'] != null ? ' · ${l['metalCode']}' : ''}'
                  .trim(),
          'gross': l['quantityGrams'] ?? l['grossWeightGrams'],
          'fine': l['fineWeightGrams'],
          'cost': l['costAmount'] ?? l['valuationCost'],
        },
    ].where((r) {
      if (q.isEmpty) return true;
      return '${r['_kind']} ${r['code']} ${r['locOrMetal']}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const Panel(child: Skeleton(height: 120))
        else ...[
          ResponsiveGrid2(
            children: [
              _buildSummaryBox(
                label: 'Tagged Pieces in Stock',
                value: taggedPcs,
                subline: 'Gross: $taggedGross · Fine: $taggedFine',
                footerValue: taggedCost,
              ),
              _buildSummaryBox(
                label: 'Material Lots Balance',
                value: lotsGross,
                subline: 'Pure Fine 999: $lotsFine',
                footerValue: lotsCost,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSummaryBox(
            label: 'Grand Pure Fine Grams (999 eq)',
            value: grandFine,
            footerLabel: 'Total Inventory Cost',
            footerValue: grandCost,
            mintTint: true,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Pal.bgTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Pal.border),
            ),
            child: Text(
              'Type · Tag / Lot Code · Location / Metal · Gross Weight · Fine Weight · Valuation Cost',
              style: T.body(11.4, weight: FontWeight.w700, color: Pal.muted),
            ),
          ),
          const SizedBox(height: 8),
          if (combinedRows.isEmpty)
            const SaasEmptyBox('No stock currently available in inventory.')
          else
            for (final r in combinedRows)
              LuxuryRecordCard(
                icon: r['_kind'] == 'TAGGED'
                    ? Icons.diamond_outlined
                    : Icons.layers_outlined,
                code: '${r['code']}',
                status: '${r['_kind']}',
                lines: [
                  ('Location / Metal', '${r['locOrMetal']}'),
                  (
                    'Gross / Fine 999',
                    '${_grams6(r['gross'])} · ${_grams6(r['fine'])}',
                  ),
                ],
                amountLabel: 'Valuation Cost',
                amountValue: _inrCode(r['cost']),
              ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // TAB 6: GROSS MARGIN (`image-54.png`)
  // -------------------------------------------------------------------------
  Widget _buildGrossMarginTab(String q) {
    final d = _margin ?? const {};
    final s = asMap(d['summary']);
    final invoices = asList(d['invoices'] ?? d['rows'] ?? d['items']).where((inv) {
      if (q.isEmpty) return true;
      return '${inv['documentNumber'] ?? inv['invoiceNumber'] ?? ''} ${inv['customerName'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final marginPctVal =
        decOrZero(s['overallGrossMarginPct']).round(scale: 2).toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Pal.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Pal.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: DatePickField(
                  label: 'From',
                  controller: _gmFrom,
                  onChanged: (_) => _loadActiveTab(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DatePickField(
                  label: 'To',
                  controller: _gmTo,
                  onChanged: (_) => _loadActiveTab(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Panel(child: Skeleton(height: 120))
        else ...[
          ResponsiveGrid2(
            children: [
              _buildSummaryBox(
                label: 'Net Sales Revenue',
                value: _inrCode(s['totalNetRevenue'] ?? '0'),
                valueColor: Pal.ink,
              ),
              _buildSummaryBox(
                label: 'COGS Inventory Cost',
                value: _inrCode(s['totalCogsCost'] ?? '0'),
                valueColor: Pal.danger,
              ),
              _buildSummaryBox(
                label: 'Gross Profit',
                value: _inrCode(s['totalGrossProfit'] ?? '0'),
                valueColor: Pal.ok,
              ),
              _buildSummaryBox(
                label: 'Overall Gross Margin',
                value: '$marginPctVal%',
                mintTint: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Pal.bgTint,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Pal.border),
            ),
            child: Text(
              'Invoice Date · Invoice # · Customer · Net Revenue · COGS Cost · Gross Profit · Margin %',
              style: T.body(11.4, weight: FontWeight.w700, color: Pal.muted),
            ),
          ),
          const SizedBox(height: 8),
          if (invoices.isEmpty)
            const SaasEmptyBox('No invoices found in this period.')
          else
            for (final inv in invoices)
              LuxuryRecordCard(
                icon: Icons.receipt_long_outlined,
                code:
                    '${inv['documentNumber'] ?? inv['invoiceNumber'] ?? 'Invoice'}',
                status: '${pct(inv['grossMarginPct'] ?? '0')} Margin',
                lines: [
                  (
                    'Invoice Date / Customer',
                    '${fmtDate('${inv['invoiceDate'] ?? ''}')} · ${inv['customerName'] ?? 'Walk-in'}',
                  ),
                  (
                    'Net Revenue / COGS',
                    '${_inrCode(inv['netRevenue'] ?? inv['totalAmount'])} / ${_inrCode(inv['cogsCost'])}',
                  ),
                ],
                amountLabel: 'Gross Profit',
                amountValue: _inrCode(inv['grossProfit']),
              ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // PERSISTENT BOTTOM CARD: `Profit & Loss / Balance Sheet` (`image-49..54.png`)
  // -------------------------------------------------------------------------
  Widget _buildStatementCard() {
    final res = _stmtResult;
    return SaasFormCard(
      title: 'Profit & Loss / Balance Sheet',
      icon: Icons.account_balance_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SaasDropdown(
            label: 'Statement',
            value: _stmtKind,
            options: const {
              'PROFIT_AND_LOSS': 'Profit & Loss',
              'BALANCE_SHEET': 'Balance Sheet',
            },
            onChanged: (v) => setState(() => _stmtKind = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DatePickField(
                  label: 'Period start (P&L)',
                  controller: _stmtStart,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DatePickField(
                  label: 'Period end / balance sheet date',
                  controller: _stmtEnd,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SaasField(
            label: 'Currency',
            controller: _stmtCurrency,
            mono: true,
          ),
          const SizedBox(height: 14),
          RoyalGoldButton(
            label: 'Generate statement',
            busy: _stmtBusy,
            onPressed: _stmtBusy ? null : _generateStatement,
          ),
          if (res != null) ...[
            const SizedBox(height: 14),
            SaasSubBox(
              child: res['kind'] == 'PROFIT_AND_LOSS'
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Profit & Loss (${res['startDate']} → ${res['endDate']}) · ${res['currency']}',
                          style: T.body(13.5, weight: FontWeight.w700),
                        ),
                        const Divider(height: 18),
                        Text('INCOME', style: T.caps(10.5, color: Pal.muted)),
                        const SizedBox(height: 4),
                        if (asList(res['incomeRows']).isEmpty)
                          Text(
                            'No posted income entries in period.',
                            style: T.body(12, color: Pal.muted),
                          )
                        else
                          for (final r in asList(res['incomeRows']))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r['code']} · ${r['name']}',
                                      style: T.body(12.2),
                                    ),
                                  ),
                                  Text(
                                    _inrCode(r['amount']),
                                    style: T.mono(12.2),
                                  ),
                                ],
                              ),
                            ),
                        const SizedBox(height: 8),
                        Text('EXPENSES', style: T.caps(10.5, color: Pal.muted)),
                        const SizedBox(height: 4),
                        if (asList(res['expenseRows']).isEmpty)
                          Text(
                            'No posted expense entries in period.',
                            style: T.body(12, color: Pal.muted),
                          )
                        else
                          for (final r in asList(res['expenseRows']))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${r['code']} · ${r['name']}',
                                      style: T.body(12.2),
                                    ),
                                  ),
                                  Text(
                                    _inrCode(r['amount']),
                                    style: T.mono(12.2),
                                  ),
                                ],
                              ),
                            ),
                        const Divider(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'NET PROFIT / (LOSS)',
                              style: T.body(12.8, weight: FontWeight.w800),
                            ),
                            Text(
                              _inrCode(res['netProfit']),
                              style: T.mono(
                                13.5,
                                weight: FontWeight.w800,
                                color: decOrZero(res['netProfit']) >=
                                        Decimal.zero
                                    ? Pal.ok
                                    : Pal.danger,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Balance Sheet (As of ${res['endDate']}) · ${res['currency']}',
                          style: T.body(13.5, weight: FontWeight.w700),
                        ),
                        const Divider(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Assets', style: T.body(12.5)),
                            Text(
                              _inrCode(res['totalAssets']),
                              style: T.mono(12.8, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Liabilities', style: T.body(12.5)),
                            Text(
                              _inrCode(res['totalLiabilities']),
                              style: T.mono(12.8, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Equity', style: T.body(12.5)),
                            Text(
                              _inrCode(res['totalEquity']),
                              style: T.mono(12.8, weight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = auth.tenantName.trim();
    final branchName = auth.branchName.trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final q = _search.text.trim().toLowerCase();

    return LuxuryModuleScaffold(
      title: 'Audit & Compliance Reports',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.bar_chart_rounded,
      searchController: _search,
      searchHint: 'Search accounts, counterparties, tags or invoices...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _loadActiveTab,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: _switchTab,
        tabs: const [
          ('TRIAL', 'Trial Balance'),
          ('LEDGER', 'General Ledger'),
          ('PARTY', 'Party Statement'),
          ('AGEING', 'AR / AP Ageing'),
          ('STOCK', 'Stock Valuation'),
          ('MARGIN', 'Gross Margin'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _loadActiveTab,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _loadActiveTab),
              const SizedBox(height: 12),
            ],

            // Hero Header Card (`Financial & Commercial Intelligence Reports` — image-49..54.png)
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
                        Icons.bar_chart_rounded,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Financial & Commercial Intelligence Reports',
                          style: T.body(
                            15.8,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Authoritative double-entry trial balance, subledger ageing, inventory valuation, and gross margin analytics.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (_tab == 'TRIAL')
              _buildTrialBalanceTab(q)
            else if (_tab == 'LEDGER')
              _buildGeneralLedgerTab(q)
            else if (_tab == 'PARTY')
              _buildPartyStatementTab(q)
            else if (_tab == 'AGEING')
              _buildAgeingTab(q)
            else if (_tab == 'STOCK')
              _buildStockValuationTab(q)
            else
              _buildGrossMarginTab(q),

            const SizedBox(height: 16),

            // Persistent `Profit & Loss / Balance Sheet` Generator Card (`image-49..54.png`)
            _buildStatementCard(),
          ],
        ),
      ),
    );
  }
}
