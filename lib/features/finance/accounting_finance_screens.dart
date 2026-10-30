import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

String _fStr(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v is Map) {
      final inner = v['displayName'] ?? v['legalName'] ?? v['name'] ?? v['code'];
      if (inner != null && '$inner'.isNotEmpty) return '$inner';
    } else if (v != null && '$v'.isNotEmpty && v is! List) {
      return '$v';
    }
  }
  return fallback;
}

// ============================================================================
// 1. DOUBLE-ENTRY ACCOUNTING — Screenshots 685–688 (`/accounting/workspace`)
// ============================================================================

class _JournalDraftLine {
  _JournalDraftLine()
      : accountCtrl = TextEditingController(),
        descCtrl = TextEditingController(),
        debitCtrl = TextEditingController(text: '0.00'),
        creditCtrl = TextEditingController(text: '0.00');
  final TextEditingController accountCtrl;
  final TextEditingController descCtrl;
  final TextEditingController debitCtrl;
  final TextEditingController creditCtrl;

  void dispose() {
    accountCtrl.dispose();
    descCtrl.dispose();
    debitCtrl.dispose();
    creditCtrl.dispose();
  }
}

class DoubleEntryAccountingScreen extends StatefulWidget {
  const DoubleEntryAccountingScreen({super.key});
  @override
  State<DoubleEntryAccountingScreen> createState() => _DoubleEntryAccountingScreenState();
}

class _DoubleEntryAccountingScreenState extends State<DoubleEntryAccountingScreen> {
  String _tab = 'JOURNAL';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _fys = [];
  List<Map<String, dynamic>> _accounts = [];
  List<Map<String, dynamic>> _journals = [];
  List<Map<String, dynamic>> _workflows = [];

  // Manual Adjustment Draft (Screenshot 685)
  final _periodCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(text: todayIso());
  final _adjDescCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  late final List<_JournalDraftLine> _lines = [_JournalDraftLine(), _JournalDraftLine()];

  // Period Control Note (Screenshot 685)
  final _periodNoteCtrl = TextEditingController();

  // Profit & Loss / Balance Sheet (Screenshot 686)
  String _statementKind = 'PROFIT_AND_LOSS';
  final _stmtStartCtrl = TextEditingController(text: monthStartIso());
  final _stmtEndCtrl = TextEditingController(text: todayIso());
  final _stmtCurrencyCtrl = TextEditingController(text: 'INR');
  Map<String, dynamic>? _statementResult;

  // Stage Opening Data & Annual Close (Screenshots 687–688)
  final _closeReasonCtrl = TextEditingController();
  final _evidenceCtrl = TextEditingController();
  final _openingJsonCtrl = TextEditingController();
  final _completedFyCtrl = TextEditingController();
  final _nextFyCtrl = TextEditingController();
  final _closingSeriesCtrl = TextEditingController();
  final _retainedAcctCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _periodCtrl.dispose();
    _seriesCtrl.dispose();
    _dateCtrl.dispose();
    _adjDescCtrl.dispose();
    _reasonCtrl.dispose();
    _periodNoteCtrl.dispose();
    _stmtStartCtrl.dispose();
    _stmtEndCtrl.dispose();
    _stmtCurrencyCtrl.dispose();
    _closeReasonCtrl.dispose();
    _evidenceCtrl.dispose();
    _openingJsonCtrl.dispose();
    _completedFyCtrl.dispose();
    _nextFyCtrl.dispose();
    _closingSeriesCtrl.dispose();
    _retainedAcctCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/accounting/workspace'),
        WorkspaceLookup.load(api, includeParties: false, includeAccounting: true),
      ]);
      if (!mounted) return;
      final ws = asMap(res[0]);
      final lk = res[1] as WorkspaceLookup;
      setState(() {
        _fys = asList(ws['financialYears'] ?? const []);
        _accounts = asList(ws['accounts'] ?? const []);
        _journals = asList(ws['journals'] ?? const []);
        _workflows = asList(ws['workflows'] ?? ws['openingCloseWorkflows'] ?? const []);
        _lookup = lk;
        if (_periodCtrl.text.isEmpty && lk.openPeriods().isNotEmpty) {
          _periodCtrl.text = lk.openPeriods().first.id;
        }
        final jSeries = lk.seriesFor(const ['JOURNAL']);
        if (_seriesCtrl.text.isEmpty && jSeries.isNotEmpty) {
          _seriesCtrl.text = jSeries.first.id;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Decimal get _totalDebit =>
      _lines.fold<Decimal>(Decimal.zero, (s, l) => s + decOrZero(l.debitCtrl.text));

  Decimal get _totalCredit =>
      _lines.fold<Decimal>(Decimal.zero, (s, l) => s + decOrZero(l.creditCtrl.text));

  bool get _isBalanced => _totalDebit > Decimal.zero && _totalDebit == _totalCredit;

  Future<void> _saveBalancedDraft() async {
    if (_periodCtrl.text.trim().isEmpty || _seriesCtrl.text.trim().isEmpty) {
      toast(context, 'Select an Open period and Journal series.', error: true);
      return;
    }
    if (_reasonCtrl.text.trim().length < 10) {
      toast(context, 'Business reason must be at least 10 characters.', error: true);
      return;
    }
    if (!_isBalanced) {
      toast(context, 'Journal lines must be positive and strictly balanced (Debit = Credit).', error: true);
      return;
    }
    for (final l in _lines) {
      if (l.accountCtrl.text.trim().isEmpty) {
        toast(context, 'Select an Account on every journal line.', error: true);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/accounting/journals',
        idempotencyKey: const Uuid().v4(),
        body: {
          'postingPeriodId': _periodCtrl.text.trim(),
          'documentSeriesId': _seriesCtrl.text.trim(),
          'businessDate': _dateCtrl.text.trim(),
          'sourceType': 'MANUAL_ADJUSTMENT',
          'sourceId': const Uuid().v4(),
          'sourceAction': 'ADJUSTMENT',
          'description': _adjDescCtrl.text.trim().isEmpty ? 'Manual Ledger Adjustment' : _adjDescCtrl.text.trim(),
          'reason': _reasonCtrl.text.trim(),
          'currency': 'INR',
          'lines': [
            for (final l in _lines)
              {
                'accountId': l.accountCtrl.text.trim(),
                'description': l.descCtrl.text.trim().isEmpty ? 'Adjustment line' : l.descCtrl.text.trim(),
                'debit': normAmount(l.debitCtrl.text),
                'credit': normAmount(l.creditCtrl.text),
              },
          ],
        },
      );
      _adjDescCtrl.clear();
      _reasonCtrl.clear();
      await _load();
      if (mounted) toast(context, 'Balanced manual journal draft saved.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _postJournal(Map<String, dynamic> j) async {
    final id = _fStr(j, ['id']);
    if (id.isEmpty) return;
    try {
      await context.read<ApiClient>().post(
        '/accounting/journals/$id/post',
        idempotencyKey: const Uuid().v4(),
        body: {
          'expectedVersion': (j['version'] as num?)?.toInt() ?? 1,
          'reason': 'Posted balanced journal to immutable ledger.',
        },
      );
      await _load();
      if (mounted) toast(context, 'Journal posted to general ledger.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _togglePeriod(Map<String, dynamic> p, bool close) async {
    final id = _fStr(p, ['id']);
    final note = _periodNoteCtrl.text.trim();
    if (note.length < 10) {
      toast(context, 'Enter a Period control note (min 10 chars) before changing period state.', error: true);
      return;
    }
    try {
      await context.read<ApiClient>().post(
        '/accounting/posting-periods/$id/${close ? 'close' : 'reopen'}',
        idempotencyKey: const Uuid().v4(),
        body: {
          'expectedVersion': (p['version'] as num?)?.toInt() ?? 1,
          'reason': note,
        },
      );
      await _load();
      if (mounted) toast(context, close ? 'Posting period closed.' : 'Posting period reopened.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _generateStatement() async {
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      Map<String, dynamic> data;
      try {
        data = asMap(await api.get('/accounting/statements', query: {
          'kind': _statementKind,
          'startDate': _stmtStartCtrl.text.trim(),
          'endDate': _stmtEndCtrl.text.trim(),
          'currency': _stmtCurrencyCtrl.text.trim(),
        }));
      } on ApiException {
        data = asMap(await api.get('/reports/trial-balance', query: {
          'asOfDate': _stmtEndCtrl.text.trim(),
        }));
      }
      if (mounted) setState(() => _statementResult = data);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _populateOpeningTemplate() {
    final template = {
      'currency': 'INR',
      'asOfDate': todayIso(),
      'balances': [
        for (final a in _accounts.take(4))
          {
            'accountId': a['id'],
            'accountCode': a['code'],
            'debit': '0.00',
            'credit': '0.00',
          },
      ],
    };
    setState(() {
      _openingJsonCtrl.text = const JsonEncoder.withIndent('  ').convert(template);
    });
  }

  Future<void> _stageOpeningData() async {
    if (_closeReasonCtrl.text.trim().length < 10) {
      toast(context, 'Enter Business reason (min 10 chars).', error: true);
      return;
    }
    if (_openingJsonCtrl.text.trim().isEmpty) {
      toast(context, 'Generate or paste Opening JSON payload first.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final parsed = jsonDecode(_openingJsonCtrl.text.trim());
      await context.read<ApiClient>().post(
        '/accounting/opening-balances',
        idempotencyKey: const Uuid().v4(),
        body: {
          'reason': _closeReasonCtrl.text.trim(),
          'evidence': _evidenceCtrl.text.trim(),
          'payload': parsed,
        },
      );
      await _load();
      if (mounted) toast(context, 'Opening data staged for review.');
    } on FormatException {
      if (mounted) toast(context, 'Invalid JSON syntax in opening payload.', error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _prepareAnnualClose() async {
    if (_completedFyCtrl.text.trim().isEmpty || _nextFyCtrl.text.trim().isEmpty) {
      toast(context, 'Select Completed financial year and Contiguous next financial year.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/accounting/annual-close',
        idempotencyKey: const Uuid().v4(),
        body: {
          'completedFinancialYearId': _completedFyCtrl.text.trim(),
          'nextFinancialYearId': _nextFyCtrl.text.trim(),
          if (_closingSeriesCtrl.text.trim().isNotEmpty) 'closingSeriesId': _closingSeriesCtrl.text.trim(),
          if (_retainedAcctCtrl.text.trim().isNotEmpty) 'retainedEarningsAccountId': _retainedAcctCtrl.text.trim(),
          'reason': _closeReasonCtrl.text.trim(),
          'evidence': _evidenceCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) toast(context, 'Annual close workflow prepared.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _quickSetupDialog(String kind) async {
    final c1 = TextEditingController();
    final c2 = TextEditingController();
    final c3 = TextEditingController();
    String group = 'ASSET';
    String docType = 'JOURNAL';
    String fyId = _fys.isNotEmpty ? '${_fys.first['id']}' : '';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Pal.card,
          title: Text(
            kind == 'FY'
                ? 'New Financial Year'
                : kind == 'SERIES'
                    ? 'New Document Series'
                    : 'New Ledger Account',
            style: T.display(19),
          ),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (kind == 'FY') ...[
                TextField(controller: c1, decoration: const InputDecoration(labelText: 'Label (e.g. FY 2026-27)')),
                const SizedBox(height: 10),
                TextField(controller: c2, style: T.mono(13.5), decoration: const InputDecoration(labelText: 'Start Date (YYYY-MM-DD)', hintText: '2026-04-01')),
                const SizedBox(height: 10),
                TextField(controller: c3, style: T.mono(13.5), decoration: const InputDecoration(labelText: 'End Date (YYYY-MM-DD)', hintText: '2027-03-31')),
              ] else if (kind == 'SERIES') ...[
                if (_fys.isNotEmpty)
                  GoldDropdown<String>(
                    value: fyId,
                    labelText: 'Financial Year',
                    items: [
                      for (final fy in _fys)
                        DropdownMenuItem(value: '${fy['id']}', child: Text('${fy['label']}')),
                    ],
                    onChanged: (v) => setLocal(() => fyId = v ?? fyId),
                  ),
                const SizedBox(height: 10),
                GoldDropdown<String>(
                  value: docType,
                  labelText: 'Document Type',
                  items: const [
                    DropdownMenuItem(value: 'JOURNAL', child: Text('JOURNAL')),
                    DropdownMenuItem(value: 'SALES_INVOICE', child: Text('SALES_INVOICE')),
                    DropdownMenuItem(value: 'PURCHASE_ORDER', child: Text('PURCHASE_ORDER')),
                    DropdownMenuItem(value: 'GOODS_RECEIPT', child: Text('GOODS_RECEIPT')),
                    DropdownMenuItem(value: 'SUPPLIER_BILL', child: Text('SUPPLIER_BILL')),
                    DropdownMenuItem(value: 'JOB_WORK', child: Text('JOB_WORK')),
                    DropdownMenuItem(value: 'APPROVAL_MEMO', child: Text('APPROVAL_MEMO')),
                  ],
                  onChanged: (v) => setLocal(() => docType = v ?? 'JOURNAL'),
                ),
                const SizedBox(height: 10),
                TextField(controller: c1, style: T.mono(13.5), decoration: const InputDecoration(labelText: 'Series Key (e.g. JRN-HQ)')),
                const SizedBox(height: 10),
                TextField(controller: c2, style: T.mono(13.5), decoration: const InputDecoration(labelText: 'Prefix (e.g. JRN/26-27/)')),
              ] else ...[
                TextField(controller: c1, style: T.mono(13.5), decoration: const InputDecoration(labelText: 'Account Code (e.g. 1010)')),
                const SizedBox(height: 10),
                TextField(controller: c2, decoration: const InputDecoration(labelText: 'Account Name')),
                const SizedBox(height: 10),
                GoldDropdown<String>(
                  value: group,
                  labelText: 'Account Group',
                  items: const [
                    DropdownMenuItem(value: 'ASSET', child: Text('ASSET')),
                    DropdownMenuItem(value: 'LIABILITY', child: Text('LIABILITY')),
                    DropdownMenuItem(value: 'EQUITY', child: Text('EQUITY')),
                    DropdownMenuItem(value: 'INCOME', child: Text('INCOME')),
                    DropdownMenuItem(value: 'EXPENSE', child: Text('EXPENSE')),
                  ],
                  onChanged: (v) => setLocal(() => group = v ?? 'ASSET'),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () async {
                final api = context.read<ApiClient>();
                try {
                  if (kind == 'FY') {
                    await api.post('/accounting/financial-years', body: {
                      'label': c1.text.trim(),
                      'startDate': c2.text.trim(),
                      'endDate': c3.text.trim(),
                    });
                  } else if (kind == 'SERIES') {
                    await api.post('/accounting/document-series', body: {
                      'financialYearId': fyId,
                      'documentType': docType,
                      'seriesKey': c1.text.trim().toUpperCase(),
                      'prefix': c2.text.trim().toUpperCase(),
                      'padding': 5,
                    });
                  } else {
                    await api.post('/accounting/accounts', body: {
                      'code': c1.text.trim(),
                      'name': c2.text.trim(),
                      'group': group,
                      'controlType': 'NONE',
                      'currency': 'INR',
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Double-Entry Accounting'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.account_balance_outlined,
              badge: 'Financials & GST',
              title: 'Accounting & Ledger Control',
              subtitle:
                  'Balanced double-entry adjustments, period controls, P&L / Balance Sheet statements, opening balances, and annual close.',
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: const [
                ('JOURNAL', 'Manual Journal', Icons.edit_note_rounded),
                ('STMTS', 'P&L / Balance Sheet', Icons.analytics_outlined),
                ('PERIODS', 'Periods & COA', Icons.calendar_month_outlined),
                ('CLOSE', 'Opening & Annual Close', Icons.lock_outline_rounded),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 110))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'JOURNAL')
              _buildManualJournalTab()
            else if (_tab == 'STMTS')
              _buildStatementsTab()
            else if (_tab == 'PERIODS')
              _buildPeriodsCoaTab()
            else
              _buildOpeningCloseTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildManualJournalTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Manual adjustment draft', style: T.display(18))),
            StatusPill(_isBalanced ? 'BALANCED' : 'UNBALANCED'),
          ]),
          const SizedBox(height: 14),
          LookupField(
            label: 'Open period',
            controller: _periodCtrl,
            options: _lookup.openPeriods(),
          ),
          const SizedBox(height: 12),
          LookupField(
            label: 'Journal series',
            controller: _seriesCtrl,
            options: _lookup.seriesFor(const ['JOURNAL']),
          ),
          const SizedBox(height: 12),
          DatePickField(label: 'Date', controller: _dateCtrl),
          const SizedBox(height: 12),
          const FieldLabel('Adjustment description'),
          TextField(
            controller: _adjDescCtrl,
            decoration: const InputDecoration(hintText: 'Accrual, depreciation, or ledger reclassification'),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _lines.length; i++) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Pal.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Pal.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('LINE ${i + 1}', style: T.caps(10, color: Pal.goldDeep)),
                  const Spacer(),
                  if (_lines.length > 2)
                    InkWell(
                      onTap: () => setState(() {
                        final removed = _lines.removeAt(i);
                        removed.dispose();
                      }),
                      child: const Icon(Icons.close_rounded, size: 17, color: Pal.danger),
                    ),
                ]),
                const SizedBox(height: 8),
                LookupField(
                  label: 'Account',
                  controller: _lines[i].accountCtrl,
                  options: _lookup.accounts,
                ),
                const SizedBox(height: 8),
                const FieldLabel('Line description'),
                TextField(controller: _lines[i].descCtrl),
                const SizedBox(height: 8),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Debit'),
                    TextField(
                      controller: _lines[i].debitCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                      onChanged: (_) => setState(() {}),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Credit'),
                    TextField(
                      controller: _lines[i].creditCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                      onChanged: (_) => setState(() {}),
                    ),
                  ]),
                ]),
              ]),
            ),
          ],
          Row(children: [
            TextButton.icon(
              onPressed: () => setState(() => _lines.add(_JournalDraftLine())),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('+ Add line'),
            ),
            const Spacer(),
            Text(
              'Dr ${inr(_totalDebit.toStringAsFixed(2))} · Cr ${inr(_totalCredit.toStringAsFixed(2))}',
              style: T.mono(11.5, color: _isBalanced ? Pal.ok : Pal.warn),
            ),
          ]),
          const SizedBox(height: 8),
          const FieldLabel('Business reason (min 10 chars)'),
          TextField(
            controller: _reasonCtrl,
            decoration: const InputDecoration(hintText: 'Documented audit justification for manual entry'),
          ),
          const SizedBox(height: 16),
          RoyalGoldButton(
            label: 'Save balanced draft',
            icon: Icons.check_circle_outline_rounded,
            busy: _busy,
            onPressed: _saveBalancedDraft,
          ),
        ]),
      ),
      const SectionLabel('Ledger Journals'),
      if (_journals.isEmpty)
        const Panel(
          child: EmptyBlock(
            icon: Icons.menu_book_outlined,
            title: 'No journals recorded yet',
            body: 'Draft or posted double-entry journals for this legal entity appear here.',
          ),
        )
      else
        for (final j in _journals)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      _fStr(j, ['documentNumber'], 'Draft Journal · ${formatDate(j['businessDate'])}'),
                      style: T.display(17),
                    ),
                  ),
                  StatusPill(_fStr(j, ['state'], 'DRAFT')),
                ]),
                const SizedBox(height: 8),
                KeyValue('Description', _fStr(j, ['description'], '-'), strong: true),
                KeyValue('Debit / Credit', '${inr(j['debitTotal'])} / ${inr(j['creditTotal'])}', mono: true),
                if ('${j['state']}'.toUpperCase() == 'DRAFT') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
                    onPressed: () => _postJournal(j),
                    icon: const Icon(Icons.publish_rounded, size: 17),
                    label: const Text('Post Journal to Ledger'),
                  ),
                ],
              ]),
            ),
          ),
    ]);
  }

  Widget _buildStatementsTab() {
    final rows = _statementResult == null
        ? const <Map<String, dynamic>>[]
        : asList(_statementResult, keys: const ['lines', 'accounts', 'rows', 'sections']);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Profit & Loss / Balance Sheet', style: T.display(18)),
          const SizedBox(height: 4),
          Text(
            'Generated directly from posted journals in the authorized legal entity.',
            style: T.body(12.2, color: Pal.muted),
          ),
          const SizedBox(height: 14),
          ResponsiveGrid2(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Statement'),
              GoldDropdown<String>(
                value: _statementKind,
                items: const [
                  DropdownMenuItem(value: 'PROFIT_AND_LOSS', child: Text('Profit & Loss')),
                  DropdownMenuItem(value: 'BALANCE_SHEET', child: Text('Balance Sheet')),
                ],
                onChanged: (v) => setState(() => _statementKind = v ?? 'PROFIT_AND_LOSS'),
              ),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Currency'),
              TextField(controller: _stmtCurrencyCtrl, style: T.mono(13.5)),
            ]),
          ]),
          const SizedBox(height: 12),
          ResponsiveGrid2(children: [
            DatePickField(label: 'Period start', controller: _stmtStartCtrl),
            DatePickField(label: 'Period end / BS date', controller: _stmtEndCtrl),
          ]),
          const SizedBox(height: 16),
          RoyalGoldButton(
            label: 'Generate statement',
            icon: Icons.analytics_outlined,
            busy: _busy,
            onPressed: _generateStatement,
          ),
        ]),
      ),
      if (_statementResult != null) ...[
        const SectionLabel('Statement Output'),
        if (rows.isEmpty)
          const Panel(
            child: EmptyBlock(
              icon: Icons.balance_rounded,
              title: 'Zero posted movement in selected period',
              body: 'Post sales, procurement, or manual journals to populate financial statement lines.',
            ),
          )
        else
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_fStr(r, ['accountName', 'name', 'label'], 'Account'), style: T.body(14, w: FontWeight.w700)),
                      Text(_fStr(r, ['accountCode', 'code', 'group'], ''), style: T.mono(11.5, color: Pal.muted)),
                    ]),
                  ),
                  Text(
                    inr(r['balance'] ?? r['netAmount'] ?? r['debit'] ?? '0.00'),
                    style: T.mono(13.5, w: FontWeight.w800),
                  ),
                ]),
              ),
            ),
      ],
    ]);
  }

  Widget _buildPeriodsCoaTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 42)),
          onPressed: () => _quickSetupDialog('FY'),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('+ Financial Year'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 42)),
          onPressed: () => _quickSetupDialog('SERIES'),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('+ Series'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(120, 42)),
          onPressed: () => _quickSetupDialog('ACCOUNT'),
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('+ Account'),
        ),
      ]),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('Period control note (min 10 chars)'),
          TextField(
            controller: _periodNoteCtrl,
            decoration: const InputDecoration(hintText: 'Month-end close / audit reopen reason'),
          ),
        ]),
      ),
      const SectionLabel('Financial Years & Posting Periods'),
      if (_fys.isEmpty)
        const Panel(
          child: EmptyBlock(
            icon: Icons.calendar_month_outlined,
            title: 'No financial years configured',
            body: 'Create an open financial year and document series to enable ledger posting.',
          ),
        )
      else
        for (final fy in _fys)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${fy['label'] ?? 'Financial Year'}', style: T.display(17.5))),
                  StatusPill('${fy['state'] ?? 'OPEN'}'),
                ]),
                const SizedBox(height: 6),
                Text('${formatDate(fy['startDate'])} – ${formatDate(fy['endDate'])}', style: T.body(12, color: Pal.muted)),
                for (final p in asList(fy['periods']))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(child: Text('${p['name'] ?? p['code']}', style: T.body(13, w: FontWeight.w700))),
                      StatusPill('${p['state'] ?? 'OPEN'}'),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => _togglePeriod(p, '${p['state']}'.toUpperCase() == 'OPEN'),
                        child: Text('${p['state']}'.toUpperCase() == 'OPEN' ? 'Close' : 'Reopen'),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
      SectionLabel('Chart of Accounts (${_accounts.length})'),
      for (final a in _accounts)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              MonoTag('${a['code'] ?? ''}'),
              const SizedBox(width: 10),
              Expanded(child: Text('${a['name'] ?? ''}', style: T.body(13.5, w: FontWeight.w700))),
              Chip2('${a['group'] ?? ''}', gold: false),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildOpeningCloseTab() {
    final equityAccounts = _lookup.accounts
        .where((a) => '${a.raw['group']}'.toUpperCase() == 'EQUITY')
        .toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Opening Balances, Legacy Cutover & Annual Close', style: T.display(18)),
          const SizedBox(height: 12),
          const FieldLabel('Business reason (min 10 chars)'),
          TextField(controller: _closeReasonCtrl),
          const SizedBox(height: 10),
          const FieldLabel('Accountant / source-control evidence'),
          TextField(controller: _evidenceCtrl),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('Stage opening data', style: T.display(16.5))),
            TextButton(
              onPressed: _populateOpeningTemplate,
              child: const Text('Template from COA'),
            ),
          ]),
          TextField(
            controller: _openingJsonCtrl,
            maxLines: 5,
            style: T.mono(12),
            decoration: const InputDecoration(hintText: 'Normalized opening data JSON'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _stageOpeningData,
            icon: const Icon(Icons.upload_file_outlined, size: 17),
            label: const Text('Stage opening data'),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Prepare annual close', style: T.display(18)),
          const SizedBox(height: 12),
          LookupField(
            label: 'Completed financial year',
            controller: _completedFyCtrl,
            options: _lookup.financialYears,
          ),
          const SizedBox(height: 10),
          LookupField(
            label: 'Contiguous next financial year',
            controller: _nextFyCtrl,
            options: _lookup.financialYears,
          ),
          const SizedBox(height: 10),
          LookupField(
            label: 'Closing JOURNAL series',
            controller: _closingSeriesCtrl,
            options: _lookup.seriesFor(const ['JOURNAL']),
          ),
          const SizedBox(height: 10),
          LookupField(
            label: 'Retained earnings equity account',
            controller: _retainedAcctCtrl,
            options: equityAccounts.isNotEmpty ? equityAccounts : _lookup.accounts,
          ),
          const SizedBox(height: 14),
          RoyalGoldButton(
            label: 'Prepare annual close',
            icon: Icons.verified_outlined,
            busy: _busy,
            onPressed: _prepareAnnualClose,
          ),
        ]),
      ),
      const SectionLabel('Workflow History'),
      if (_workflows.isEmpty)
        const Panel(
          child: EmptyBlock(
            icon: Icons.history_rounded,
            title: 'No opening or annual-close workflows created',
            body: 'Staged cutover snapshots and year-end close runs are logged here.',
          ),
        )
      else
        for (final w in _workflows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              child: Row(children: [
                Expanded(child: Text(_fStr(w, ['kind', 'type', 'id'], 'Workflow'), style: T.body(13.5, w: FontWeight.w700))),
                StatusPill(_fStr(w, ['state', 'status'], 'STAGED')),
              ]),
            ),
          ),
    ]);
  }
}

// ============================================================================
// 2. SETTLEMENTS & CASHUP — Screenshot 689 (`/payments`)
// ============================================================================

class SettlementsCashupScreen extends StatefulWidget {
  const SettlementsCashupScreen({super.key});
  @override
  State<SettlementsCashupScreen> createState() => _SettlementsCashupScreenState();
}

class _SettlementsCashupScreenState extends State<SettlementsCashupScreen> {
  String _tab = 'OPEN';
  bool _loading = true;
  String? _error;

  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _openItems = [];
  List<Map<String, dynamic>> _settlements = [];
  List<Map<String, dynamic>> _clearings = [];

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
    try {
      final res = await Future.wait<dynamic>([
        api.get('/payments'),
        WorkspaceLookup.load(api, includeParties: true, includeAccounting: true),
      ]);
      if (!mounted) return;
      final ws = asMap(res[0]);
      setState(() {
        _openItems = asList(ws['openItems'] ?? const []);
        _settlements = asList(ws['settlements'] ?? const []);
        _clearings = asList(ws['providerClearings'] ?? const []);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openSettlementSheet(String kind) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NewSettlementSheet(
        kind: kind,
        lookup: _lookup,
        openItems: _openItems,
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final receipts = _settlements
        .where((s) => '${s['direction']}'.toUpperCase().contains('IN') || '${s['direction']}'.toUpperCase() == 'RECEIPT')
        .toList();
    final disbursements = _settlements
        .where((s) => '${s['direction']}'.toUpperCase().contains('OUT') || '${s['direction']}'.toUpperCase() == 'DISBURSEMENT')
        .toList();
    final refunds = _settlements
        .where((s) => '${s['direction']}'.toUpperCase().contains('REFUND'))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settlements & Cashup'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.account_balance_wallet_outlined,
              badge: 'Financials & GST',
              title: 'Payments, Settlements & Cashup',
              subtitle:
                  'AR receipts, AP disbursements, customer/supplier refunds, open-item allocations, and payment provider clearings.',
              trailing: _tab == 'OPEN'
                  ? null
                  : FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Pal.goldBright,
                        foregroundColor: Pal.ink,
                        minimumSize: const Size(106, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: () => _openSettlementSheet(_tab),
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: Text('Record', style: T.body(12.5, color: Pal.ink, w: FontWeight.w800)),
                    ),
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: [
                ('OPEN', 'Open Items (${_openItems.length})', Icons.pending_actions_rounded),
                ('RECEIPT', 'Receipts (${receipts.length})', Icons.call_received_rounded),
                ('DISB', 'Disbursements (${disbursements.length})', Icons.call_made_rounded),
                ('REFUND', 'Refunds (${refunds.length})', Icons.replay_rounded),
                ('CLEARING', 'Provider Clearings (${_clearings.length})', Icons.verified_outlined),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 100))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'OPEN')
              _buildOpenItems()
            else if (_tab == 'RECEIPT')
              _buildSettlementList(receipts, 'RECEIPT', 'No customer receipts recorded yet')
            else if (_tab == 'DISB')
              _buildSettlementList(disbursements, 'DISB', 'No supplier disbursements recorded yet')
            else if (_tab == 'REFUND')
              _buildSettlementList(refunds, 'REFUND', 'No refunds recorded yet')
            else
              _buildClearings(),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenItems() {
    if (_openItems.isEmpty) {
      return const Panel(
        child: EmptyBlock(
          icon: Icons.check_circle_outline_rounded,
          title: 'No open receivable or payable items',
          body: 'Posted sales invoices and supplier bills with unsettled balances appear here.',
        ),
      );
    }
    return Column(children: [
      for (final item in _openItems)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_fStr(item, ['documentNumber'], 'Open Item'), style: T.display(17))),
                StatusPill(_fStr(item, ['kind', 'state'], 'OPEN')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Party', _fStr(item, ['party'], '-'), strong: true),
              KeyValue('Original / Settled', '${inr(item['originalAmount'])} / ${inr(item['settledAmount'])}', mono: true),
              KeyValue('Open Balance', inr(item['openAmount']), strong: true, mono: true),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildSettlementList(List<Map<String, dynamic>> list, String kind, String emptyTitle) {
    if (list.isEmpty) {
      return Panel(
        child: EmptyBlock(
          icon: Icons.account_balance_wallet_outlined,
          title: emptyTitle,
          body: 'Post cash, UPI, card, or RTGS settlements with ledger allocation.',
          actionLabel: 'Record Settlement',
          onAction: () => _openSettlementSheet(kind),
        ),
      );
    }
    return Column(children: [
      for (final s in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_fStr(s, ['documentNumber'], 'Settlement'), style: T.display(17))),
                StatusPill(_fStr(s, ['state'], 'POSTED')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Party', _fStr(s, ['party'], '-'), strong: true),
              KeyValue('Method & Date', '${_fStr(s, ['method'], 'CASH')} · ${formatDate(s['settlementDate'])}'),
              KeyValue('Amount', inr(s['amount']), strong: true, mono: true),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildClearings() {
    if (_clearings.isEmpty) {
      return Panel(
        child: EmptyBlock(
          icon: Icons.verified_outlined,
          title: 'No provider clearing batches yet',
          body: 'Reconcile card/UPI gateway settlement batches net of MDR fees.',
          actionLabel: 'Record Clearing Batch',
          onAction: () => _openSettlementSheet('CLEARING'),
        ),
      );
    }
    return Column(children: [
      for (final c in _clearings)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_fStr(c, ['clearingBatchReference'], 'Clearing Batch'), style: T.display(17))),
                StatusPill(_fStr(c, ['state'], 'POSTED')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Gross / Fee', '${inr(c['grossAmount'])} / ${inr(c['feeAmount'])}', mono: true),
              KeyValue('Net Settled', inr(c['netAmount']), strong: true, mono: true),
            ]),
          ),
        ),
    ]);
  }
}

class _NewSettlementSheet extends StatefulWidget {
  const _NewSettlementSheet({
    required this.kind,
    required this.lookup,
    required this.openItems,
  });
  final String kind;
  final WorkspaceLookup lookup;
  final List<Map<String, dynamic>> openItems;
  @override
  State<_NewSettlementSheet> createState() => _NewSettlementSheetState();
}

class _NewSettlementSheetState extends State<_NewSettlementSheet> {
  final _partyCtrl = TextEditingController();
  final _periodCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _bankAcctCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(text: todayIso());
  final _amtCtrl = TextEditingController();
  final _refCtrl = TextEditingController();
  String _method = 'UPI';
  bool _busy = false;

  @override
  void dispose() {
    _partyCtrl.dispose();
    _periodCtrl.dispose();
    _seriesCtrl.dispose();
    _bankAcctCtrl.dispose();
    _dateCtrl.dispose();
    _amtCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!isValidAmount(_amtCtrl.text)) {
      toast(context, 'Enter valid INR amount.', error: true);
      return;
    }
    setState(() => _busy = true);
    final api = context.read<ApiClient>();
    try {
      final path = switch (widget.kind) {
        'DISB' => '/payments/disbursements',
        'REFUND' => '/payments/refunds',
        'CLEARING' => '/payments/provider-clearings',
        _ => '/payments/receipts',
      };
      await api.post(
        path,
        idempotencyKey: const Uuid().v4(),
        body: widget.kind == 'CLEARING'
            ? {
                'clearingBatchReference': _refCtrl.text.trim().isEmpty ? 'BATCH-${DateTime.now().millisecondsSinceEpoch}' : _refCtrl.text.trim(),
                'settlementDate': _dateCtrl.text.trim(),
                'currency': 'INR',
                'grossAmount': normAmount(_amtCtrl.text),
                'feeAmount': '0.00',
                if (_bankAcctCtrl.text.trim().isNotEmpty) 'bankAccountId': _bankAcctCtrl.text.trim(),
                if (_periodCtrl.text.trim().isNotEmpty) 'postingPeriodId': _periodCtrl.text.trim(),
                if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
              }
            : {
                'partyId': _partyCtrl.text.trim(),
                'settlementDate': _dateCtrl.text.trim(),
                'method': _method,
                'currency': 'INR',
                'amount': normAmount(_amtCtrl.text),
                if (_refCtrl.text.trim().isNotEmpty) 'paymentReference': _refCtrl.text.trim(),
                if (_bankAcctCtrl.text.trim().isNotEmpty) 'cashOrBankAccountId': _bankAcctCtrl.text.trim(),
                if (_periodCtrl.text.trim().isNotEmpty) 'postingPeriodId': _periodCtrl.text.trim(),
                if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
                'allocations': const <Map<String, dynamic>>[],
              },
      );
      if (mounted) {
        toast(context, 'Settlement posted.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.kind) {
      'DISB' => 'Supplier Disbursement',
      'REFUND' => 'Customer Refund',
      'CLEARING' => 'Provider Clearing Batch',
      _ => 'Customer Receipt',
    };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(title, style: T.display(21)),
        const SizedBox(height: 14),
        if (widget.kind != 'CLEARING') ...[
          LookupField(label: 'Party', controller: _partyCtrl, options: widget.lookup.parties),
          const SizedBox(height: 10),
          const FieldLabel('Payment Method'),
          GoldDropdown<String>(
            value: _method,
            items: const [
              DropdownMenuItem(value: 'CASH', child: Text('CASH')),
              DropdownMenuItem(value: 'UPI', child: Text('UPI')),
              DropdownMenuItem(value: 'CARD', child: Text('CARD')),
              DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('BANK_TRANSFER / RTGS')),
            ],
            onChanged: (v) => setState(() => _method = v ?? 'UPI'),
          ),
          const SizedBox(height: 10),
        ],
        ResponsiveGrid2(children: [
          DatePickField(label: 'Settlement date', controller: _dateCtrl),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const FieldLabel('Amount (INR)'),
            TextField(
              controller: _amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(13.5),
              decoration: const InputDecoration(hintText: '0.00'),
            ),
          ]),
        ]),
        const SizedBox(height: 10),
        LookupField(
          label: 'Cash / Bank Ledger Account',
          controller: _bankAcctCtrl,
          options: widget.lookup.accounts,
          optional: true,
        ),
        const SizedBox(height: 10),
        ResponsiveGrid2(children: [
          LookupField(label: 'Open Period', controller: _periodCtrl, options: widget.lookup.openPeriods(), optional: true),
          LookupField(label: 'Series', controller: _seriesCtrl, options: widget.lookup.series, optional: true),
        ]),
        const SizedBox(height: 10),
        const FieldLabel('UTR / Batch Reference'),
        TextField(controller: _refCtrl, style: T.mono(13)),
        const SizedBox(height: 16),
        RoyalGoldButton(label: 'Post $title', busy: _busy, onPressed: _submit),
      ]),
    );
  }
}

// ============================================================================
// 3. BANKING & RECONCILIATION — Screenshot 690 (`/banking`)
// ============================================================================

class BankingReconciliationScreen extends StatefulWidget {
  const BankingReconciliationScreen({super.key});
  @override
  State<BankingReconciliationScreen> createState() => _BankingReconciliationScreenState();
}

class _BankingReconciliationScreenState extends State<BankingReconciliationScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _statements = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _bankAcctCtrl = TextEditingController();
  final _stmtIdCtrl = TextEditingController();
  final _startDateCtrl = TextEditingController(text: monthStartIso());
  final _endDateCtrl = TextEditingController(text: todayIso());
  final _openBalCtrl = TextEditingController(text: '0.00');
  final _closeBalCtrl = TextEditingController(text: '0.00');
  final _currencyCtrl = TextEditingController(text: 'INR');
  final _csvCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _bankAcctCtrl.dispose();
    _stmtIdCtrl.dispose();
    _startDateCtrl.dispose();
    _endDateCtrl.dispose();
    _openBalCtrl.dispose();
    _closeBalCtrl.dispose();
    _currencyCtrl.dispose();
    _csvCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/banking'),
        WorkspaceLookup.load(api, includeParties: false, includeAccounting: true),
      ]);
      if (!mounted) return;
      setState(() {
        _statements = asList(res[0], keys: const ['statements', 'bankStatements', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _importCsv() async {
    if (_bankAcctCtrl.text.trim().isEmpty || _stmtIdCtrl.text.trim().isEmpty) {
      toast(context, 'Select Bank account UUID and enter Statement ID.', error: true);
      return;
    }
    if (_csvCtrl.text.trim().isEmpty) {
      toast(context, 'Paste normalized CSV statement lines.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/banking',
        idempotencyKey: const Uuid().v4(),
        body: {
          'bankAccountId': _bankAcctCtrl.text.trim(),
          'statementId': _stmtIdCtrl.text.trim(),
          'externalStatementId': _stmtIdCtrl.text.trim(),
          'startDate': _startDateCtrl.text.trim(),
          'endDate': _endDateCtrl.text.trim(),
          'openingBalance': normAmount(_openBalCtrl.text),
          'closingBalance': normAmount(_closeBalCtrl.text),
          'currency': _currencyCtrl.text.trim().toUpperCase(),
          'csvContent': _csvCtrl.text.trim(),
          'csv': _csvCtrl.text.trim(),
        },
      );
      _stmtIdCtrl.clear();
      _csvCtrl.clear();
      await _load();
      if (mounted) toast(context, 'Bank statement imported.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final assetAccts = _lookup.accounts
        .where((a) => '${a.raw['group']}'.toUpperCase() == 'ASSET')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banking & Reconciliation'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.account_balance_rounded,
              badge: 'Financials & GST',
              title: 'Bank Statement Import & Reconciliation',
              subtitle:
                  'Duplicate-safe CSV import, settlement/clearing matching, adjustment journals, and immutable reconciliation sign-off.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Import normalized bank CSV', style: T.display(18)),
                const SizedBox(height: 14),
                LookupField(
                  label: 'Bank account UUID',
                  controller: _bankAcctCtrl,
                  options: assetAccts.isNotEmpty ? assetAccts : _lookup.accounts,
                ),
                const SizedBox(height: 12),
                const FieldLabel('Statement ID'),
                TextField(
                  controller: _stmtIdCtrl,
                  style: T.mono(13.5),
                  decoration: const InputDecoration(hintText: 'Bank statement reference ID'),
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  DatePickField(label: 'Start date', controller: _startDateCtrl),
                  DatePickField(label: 'End date', controller: _endDateCtrl),
                ]),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Opening balance'),
                    TextField(
                      controller: _openBalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Closing balance'),
                    TextField(
                      controller: _closeBalCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: T.mono(13.5),
                    ),
                  ]),
                ]),
                const SizedBox(height: 12),
                const FieldLabel('Currency'),
                TextField(controller: _currencyCtrl, style: T.mono(13.5)),
                const SizedBox(height: 12),
                const FieldLabel('Normalized CSV rows (date,reference,description,debit,credit)'),
                TextField(
                  controller: _csvCtrl,
                  maxLines: 4,
                  style: T.mono(12),
                  decoration: const InputDecoration(
                    hintText: 'date,reference,description,debit,credit',
                  ),
                ),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Import statement',
                  icon: Icons.upload_file_outlined,
                  busy: _busy,
                  onPressed: _importCsv,
                ),
              ]),
            ),
            const SectionLabel('Imported Statements'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_statements.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.account_balance_rounded,
                  title: 'No bank statements imported yet',
                  body: 'Import a normalized bank CSV statement above to begin matching settlements.',
                ),
              )
            else
              for (final s in _statements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _fStr(s, ['statementId', 'externalStatementId', 'id'], 'Statement'),
                            style: T.display(17),
                          ),
                        ),
                        StatusPill(_fStr(s, ['state', 'status'], 'IMPORTED')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Period', '${formatDate(s['startDate'])} – ${formatDate(s['endDate'])}'),
                      KeyValue('Opening / Closing', '${inr(s['openingBalance'])} → ${inr(s['closingBalance'])}', mono: true),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 4. CONSOLIDATED CHAIN ANALYTICS — Screenshot 691 (`GET /chain-analytics`)
// ============================================================================

class ConsolidatedAnalyticsScreen extends StatefulWidget {
  const ConsolidatedAnalyticsScreen({super.key});
  @override
  State<ConsolidatedAnalyticsScreen> createState() => _ConsolidatedAnalyticsScreenState();
}

class _ConsolidatedAnalyticsScreenState extends State<ConsolidatedAnalyticsScreen> {
  final _fromCtrl = TextEditingController(text: '${DateTime.now().year}-01-01');
  final _toCtrl = TextEditingController(text: todayIso());
  Map<String, dynamic> _data = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/chain-analytics', query: {
        'startDate': _fromCtrl.text.trim(),
        'endDate': _toCtrl.text.trim(),
        'from': _fromCtrl.text.trim(),
        'to': _toCtrl.text.trim(),
      });
      if (mounted) setState(() => _data = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final reported = asMap(_data['reportedTotals'] ?? _data['reportedLedgerTotals']);
    final consolidated = asMap(_data['consolidatedTotals'] ?? _data['afterEliminations']);
    final recon = asMap(_data['intercompanyReconciliation']);
    final eliminations = asList(_data['eliminationSchedule'] ?? const []);
    final entities = asList(_data['entityComparison'] ?? _data['legalEntities'] ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consolidated Chain Analytics'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.hub_outlined,
              badge: 'Multi-Entity Rollup',
              title: 'Consolidated Multi-Entity & Chain Analytics',
              subtitle:
                  'Read-only rollup across authorized legal entities and branches, with separate intercompany elimination schedules.',
            ),
            const SizedBox(height: 14),
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                ResponsiveGrid2(children: [
                  DatePickField(
                    label: 'From',
                    controller: _fromCtrl,
                    onChanged: (_) => _load(),
                  ),
                  DatePickField(
                    label: 'To',
                    controller: _toCtrl,
                    onChanged: (_) => _load(),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 120))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else ...[
              ResponsiveGrid2(children: [
                MetricTile(
                  label: 'Authorized Entities',
                  value: '${_data['authorizedEntitiesCount'] ?? _data['authorizedEntities'] ?? entities.length}',
                  icon: Icons.domain_rounded,
                ),
                MetricTile(
                  label: 'Authorized Branches',
                  value: '${_data['authorizedBranchesCount'] ?? _data['authorizedBranches'] ?? 0}',
                  icon: Icons.storefront_outlined,
                ),
                MetricTile(
                  label: 'Reported Profit · INR',
                  value: inr(reported['netProfit'] ?? _data['reportedProfit'] ?? '0.00'),
                  icon: Icons.trending_up_rounded,
                ),
                MetricTile(
                  label: 'Consolidated Profit',
                  value: inr(consolidated['netProfit'] ?? _data['consolidatedProfit'] ?? '0.00'),
                  icon: Icons.workspace_premium_outlined,
                ),
              ]),
              const SectionLabel('Reported Ledger Totals'),
              Panel(
                child: Column(children: [
                  KeyValue('Revenue', inr(reported['revenue'] ?? '0.00'), mono: true),
                  KeyValue('Expenses', inr(reported['expenses'] ?? '0.00'), mono: true),
                  KeyValue('Net Profit', inr(reported['netProfit'] ?? '0.00'), strong: true, mono: true),
                  KeyValue('Assets', inr(reported['assets'] ?? '0.00'), mono: true),
                  KeyValue('Liabilities', inr(reported['liabilities'] ?? '0.00'), mono: true),
                  KeyValue('Inventory Cost', inr(reported['inventoryCost'] ?? '0.00'), mono: true),
                  KeyValue('Pure Fine Gold/Metal', fineGrams(reported['pureFineGrams'] ?? '0.000000'), mono: true),
                ]),
              ),
              const SectionLabel('After Consolidation Eliminations'),
              Panel(
                child: Column(children: [
                  KeyValue('Revenue', inr(consolidated['revenue'] ?? '0.00'), mono: true),
                  KeyValue('Expenses', inr(consolidated['expenses'] ?? '0.00'), mono: true),
                  KeyValue('Net Profit', inr(consolidated['netProfit'] ?? '0.00'), strong: true, mono: true),
                  KeyValue('Assets', inr(consolidated['assets'] ?? '0.00'), mono: true),
                  KeyValue('Liabilities', inr(consolidated['liabilities'] ?? '0.00'), mono: true),
                  KeyValue('Inventory Cost', inr(consolidated['inventoryCost'] ?? '0.00'), mono: true),
                ]),
              ),
              const SectionLabel('Intercompany Reconciliation'),
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Elimination Match Status', style: T.body(14, w: FontWeight.w700))),
                    StatusPill('${recon['state'] ?? recon['status'] ?? 'RECONCILED'}'),
                  ]),
                  const SizedBox(height: 8),
                  KeyValue('Intercompany AR', inr(recon['receivables'] ?? '0.00'), mono: true),
                  KeyValue('Intercompany AP', inr(recon['payables'] ?? '0.00'), mono: true),
                  KeyValue('Unrealized Stock Profit', inr(recon['unrealizedInventoryProfit'] ?? '0.00'), mono: true),
                ]),
              ),
              if (eliminations.isNotEmpty) ...[
                const SectionLabel('Elimination Schedule'),
                for (final el in eliminations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Row(children: [
                        Expanded(child: Text(_fStr(el, ['description', 'kind'], 'Elimination'), style: T.body(13.5, w: FontWeight.w700))),
                        Text(inr(el['amount'] ?? '0.00'), style: T.mono(13, w: FontWeight.w700)),
                      ]),
                    ),
                  ),
              ],
              const SectionLabel('Legal-Entity Comparison'),
              if (entities.isEmpty)
                const Panel(
                  child: EmptyBlock(
                    icon: Icons.domain_rounded,
                    title: 'Single or unposted entity scope',
                    body: 'Per-entity revenue, profit, and vault custody comparisons appear here.',
                  ),
                )
              else
                for (final ent in entities)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_fStr(ent, ['legalName', 'name'], 'Legal Entity'), style: T.display(17)),
                        const SizedBox(height: 8),
                        KeyValue('Revenue', inr(ent['revenue'] ?? '0.00'), mono: true),
                        KeyValue('Net Profit', inr(ent['netProfit'] ?? '0.00'), strong: true, mono: true),
                        KeyValue('Inventory Cost', inr(ent['inventoryCost'] ?? '0.00'), mono: true),
                      ]),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}
