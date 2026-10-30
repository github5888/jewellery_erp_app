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

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// 1. DOUBLE-ENTRY ACCOUNTING (`/accounting/workspace`) — Screenshots 683,686-688
// ---------------------------------------------------------------------------

class DoubleEntryAccountingScreen extends StatefulWidget {
  const DoubleEntryAccountingScreen({super.key});
  @override
  State<DoubleEntryAccountingScreen> createState() => _DoubleEntryAccountingScreenState();
}

class _JournalDraftLine {
  _JournalDraftLine()
      : desc = TextEditingController(),
        debit = TextEditingController(text: '0'),
        credit = TextEditingController(text: '0');
  String accountId = '';
  final TextEditingController desc;
  final TextEditingController debit;
  final TextEditingController credit;

  void dispose() {
    desc.dispose();
    debit.dispose();
    credit.dispose();
  }
}

class _DoubleEntryAccountingScreenState extends State<DoubleEntryAccountingScreen> {
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _showSetup = false;
  bool _showMappingRefs = false;

  // Setup forms (`AccountingPanel.tsx`)
  final _fyLabel = TextEditingController();
  final _fyStart = TextEditingController(text: '${DateTime.now().year}-04-01');
  final _fyEnd = TextEditingController(text: '${DateTime.now().year + 1}-03-31');

  final _perFyId = TextEditingController();
  final _perCode = TextEditingController();
  final _perName = TextEditingController();
  final _perStart = TextEditingController(text: monthStartIso());
  final _perEnd = TextEditingController(text: todayIso());

  final _serFyId = TextEditingController();
  final _serDocType = TextEditingController(text: 'JOURNAL');
  final _serKey = TextEditingController(text: 'MANUAL');
  final _serPrefix = TextEditingController(text: 'JV/');

  final _acctCode = TextEditingController();
  final _acctName = TextEditingController();
  String _acctGroup = 'ASSET';
  String _acctControl = 'NONE';

  // Manual adjustment draft (Screenshot 683/685)
  final _jPeriodId = TextEditingController();
  final _jSeriesId = TextEditingController();
  final _jDate = TextEditingController(text: todayIso());
  final _jDesc = TextEditingController();
  final _jReason = TextEditingController();
  final List<_JournalDraftLine> _jLines = [_JournalDraftLine(), _JournalDraftLine()];

  // Period control reason (Screenshot 685)
  final _periodActionReason = TextEditingController(
    text: 'Approved after reviewing the accounting source and supporting evidence.',
  );

  // Profit & Loss / Balance Sheet (Screenshot 686)
  String _stmtKind = 'PROFIT_AND_LOSS';
  final _stmtStart = TextEditingController(text: monthStartIso());
  final _stmtEnd = TextEditingController(text: todayIso());
  final _stmtCurrency = TextEditingController(text: 'INR');
  Map<String, dynamic>? _stmtData;

  // Opening data and annual close (Screenshots 687 & 688)
  final _closeReason = TextEditingController();
  final _closeEvidence = TextEditingController();
  final _openingJson = TextEditingController();
  final _completedFyId = TextEditingController();
  final _nextFyId = TextEditingController();
  final _closingSeriesId = TextEditingController();
  final _retainedEquityAcctId = TextEditingController();
  String _workflowRecordId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final l in _jLines) {
      l.dispose();
    }
    for (final c in [
      _fyLabel, _fyStart, _fyEnd, _perFyId, _perCode, _perName, _perStart, _perEnd,
      _serFyId, _serDocType, _serKey, _serPrefix, _acctCode, _acctName,
      _jPeriodId, _jSeriesId, _jDate, _jDesc, _jReason, _periodActionReason,
      _stmtStart, _stmtEnd, _stmtCurrency, _closeReason, _closeEvidence, _openingJson,
      _completedFyId, _nextFyId, _closingSeriesId, _retainedEquityAcctId,
    ]) {
      c.dispose();
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
      final res = await Future.wait([
        api.get('/accounting/workspace'),
        WorkspaceLookup.load(api, includeParties: false, includeAccounting: true),
      ]);
      if (!mounted) return;
      final lk = res[1] as WorkspaceLookup;
      if (_jPeriodId.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _jPeriodId.text = lk.openPeriods().first.id;
      }
      if (_jSeriesId.text.isEmpty) {
        final js = lk.seriesFor(const ['JOURNAL']);
        if (js.isNotEmpty) _jSeriesId.text = js.first.id;
      }
      setState(() {
        _ws = asMap(res[0]);
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runMutation(Future<void> Function(ApiClient api) fn, String okMsg) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn(context.read<ApiClient>());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(okMsg)));
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveBalancedDraft() async {
    if (_jPeriodId.text.trim().isEmpty ||
        _jSeriesId.text.trim().isEmpty ||
        _jDesc.text.trim().length < 5 ||
        _jReason.text.trim().length < 10) {
      setState(() => _error = 'Select Open period, Journal series, Adjustment description (5+ chars), and Business reason (10+ chars).');
      return;
    }
    final valid = _jLines.where((l) => l.accountId.isNotEmpty && l.desc.text.trim().isNotEmpty).toList();
    if (valid.length < 2) {
      setState(() => _error = 'Provide at least 2 balanced journal lines with account and line description.');
      return;
    }
    var dr = Decimal.zero;
    var cr = Decimal.zero;
    for (final l in valid) {
      dr += dParse(l.debit.text.trim());
      cr += dParse(l.credit.text.trim());
    }
    if (dr <= Decimal.zero || dr != cr) {
      setState(() => _error = 'Debits (${dStr2(dr)}) must equal Credits (${dStr2(cr)}) and be > 0.');
      return;
    }
    await _runMutation(
      (api) async {
        await api.post('/accounting/journals', idempotent: true, body: {
          'postingPeriodId': _jPeriodId.text.trim(),
          'documentSeriesId': _jSeriesId.text.trim(),
          'businessDate': _jDate.text.trim(),
          'sourceType': 'MANUAL_ADJUSTMENT',
          'sourceId': _uuid.v4(),
          'sourceAction': 'CREATE',
          'description': _jDesc.text.trim(),
          'reason': _jReason.text.trim(),
          'currency': 'INR',
          'lines': valid
              .map((l) => {
                    'accountId': l.accountId,
                    'description': l.desc.text.trim(),
                    'debit': dStr2(dParse(l.debit.text.trim())),
                    'credit': dStr2(dParse(l.credit.text.trim())),
                  })
              .toList(),
        });
        _jDesc.clear();
        _jReason.clear();
      },
      'Balanced manual adjustment draft saved.',
    );
  }

  Future<void> _generateStatement() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      dynamic res;
      try {
        res = await api.get('/accounting/statements', query: {
          'statement': _stmtKind,
          'startDate': _stmtStart.text.trim(),
          'endDate': _stmtEnd.text.trim(),
          'currency': _stmtCurrency.text.trim().toUpperCase(),
        });
      } on ApiException {
        res = await api.get('/reports/trial-balance', query: {
          'asOfDate': _stmtEnd.text.trim(),
        });
      }
      if (!mounted) return;
      setState(() => _stmtData = asMap(res));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _populateOpeningTemplate() {
    final sample = {
      'cutoverDate': todayIso(),
      'currency': 'INR',
      'balances': [
        for (final a in _lk.accounts.take(2))
          {
            'accountId': a.id,
            'debit': '0.00',
            'credit': '0.00',
          },
      ],
    };
    setState(() {
      _openingJson.text = const JsonEncoder.withIndent('  ').convert(sample);
    });
  }

  Future<void> _stageOpeningSnapshot() async {
    if (_closeReason.text.trim().length < 10 || _openingJson.text.trim().isEmpty) {
      setState(() => _error = 'Enter Business reason (10+ chars) and Opening JSON payload.');
      return;
    }
    dynamic parsed;
    try {
      parsed = jsonDecode(_openingJson.text.trim());
    } catch (_) {
      setState(() => _error = 'Opening data must be valid JSON.');
      return;
    }
    await _runMutation(
      (api) async {
        await api.post('/accounting/opening-snapshots', idempotent: true, body: {
          'reason': _closeReason.text.trim(),
          if (_closeEvidence.text.trim().isNotEmpty) 'evidence': _closeEvidence.text.trim(),
          'payload': parsed,
        });
      },
      'Opening snapshot validated & staged.',
    );
  }

  Future<void> _prepareAnnualClose() async {
    if (_completedFyId.text.trim().isEmpty ||
        _nextFyId.text.trim().isEmpty ||
        _closingSeriesId.text.trim().isEmpty ||
        _retainedEquityAcctId.text.trim().isEmpty ||
        _closeReason.text.trim().length < 10) {
      setState(() => _error = 'Select Completed FY, Next FY, Closing JOURNAL series, Retained earnings equity account, and Business reason.');
      return;
    }
    await _runMutation(
      (api) async {
        await api.post('/accounting/annual-close', idempotent: true, body: {
          'completedFinancialYearId': _completedFyId.text.trim(),
          'nextFinancialYearId': _nextFyId.text.trim(),
          'closingDocumentSeriesId': _closingSeriesId.text.trim(),
          'retainedEarningsAccountId': _retainedEquityAcctId.text.trim(),
          'reason': _closeReason.text.trim(),
          if (_closeEvidence.text.trim().isNotEmpty) 'evidence': _closeEvidence.text.trim(),
        });
      },
      'Annual close & control snapshot prepared.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final journals = asList(_ws['journals']);
    final allPeriods = asList(_ws['financialYears'])
        .expand((fy) => asList(fy['periods']))
        .toList();

    return LuxuryModuleScaffold(
      title: 'Double-Entry Accounting',
      icon: Icons.menu_book_rounded,
      actions: [
        IconButton(
          tooltip: 'Accounting Setup',
          onPressed: () => setState(() => _showSetup = !_showSetup),
          icon: Icon(
            _showSetup ? Icons.close_rounded : Icons.settings_outlined,
            color: Pal.goldSoft,
          ),
        ),
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],

            // Expandable Accounting Setup (`AccountingPanel.tsx`)
            if (_showSetup) ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'Accounting setup',
                subtitle: 'Financial years, posting periods, document series, and GL chart of accounts.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('1. Financial year', style: T.body(13, w: FontWeight.w700)),
                    const SizedBox(height: 6),
                    SaasField(label: 'Label (e.g. FY 2026-27)', controller: _fyLabel),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: DatePickField(label: 'Start date', controller: _fyStart)),
                        const SizedBox(width: 10),
                        Expanded(child: DatePickField(label: 'End date', controller: _fyEnd)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton(
                        onPressed: _busy
                            ? null
                            : () => _runMutation(
                                  (api) => api.post('/accounting/financial-years', body: {
                                    'label': _fyLabel.text.trim(),
                                    'startDate': _fyStart.text.trim(),
                                    'endDate': _fyEnd.text.trim(),
                                  }),
                                  'Financial year created.',
                                ),
                        child: const Text('Create year'),
                      ),
                    ),
                    const Divider(height: 24),
                    Text('2. Posting period', style: T.body(13, w: FontWeight.w700)),
                    const SizedBox(height: 6),
                    LookupField(label: 'Financial year', controller: _perFyId, options: _lk.financialYears),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: SaasField(label: 'Code (2026-10)', controller: _perCode, mono: true)),
                        const SizedBox(width: 10),
                        Expanded(child: SaasField(label: 'Name (October 2026)', controller: _perName)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: DatePickField(label: 'Start date', controller: _perStart)),
                        const SizedBox(width: 10),
                        Expanded(child: DatePickField(label: 'End date', controller: _perEnd)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton(
                        onPressed: _busy
                            ? null
                            : () => _runMutation(
                                  (api) => api.post('/accounting/posting-periods', body: {
                                    'financialYearId': _perFyId.text.trim(),
                                    'code': _perCode.text.trim().toUpperCase(),
                                    'name': _perName.text.trim(),
                                    'startDate': _perStart.text.trim(),
                                    'endDate': _perEnd.text.trim(),
                                  }),
                                  'Posting period created.',
                                ),
                        child: const Text('Create period'),
                      ),
                    ),
                    const Divider(height: 24),
                    Text('3. Document series', style: T.body(13, w: FontWeight.w700)),
                    const SizedBox(height: 6),
                    LookupField(label: 'Financial year', controller: _serFyId, options: _lk.financialYears),
                    const SizedBox(height: 8),
                    SaasField(
                      label: 'Document type (JOURNAL, SALES_INVOICE, PURCHASE_ORDER, JOB, MELT, TRANSFER, MEMO, TRADE, RATE_FIXING)',
                      controller: _serDocType,
                      mono: true,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: SaasField(label: 'Series key', controller: _serKey, mono: true)),
                        const SizedBox(width: 10),
                        Expanded(child: SaasField(label: 'Prefix', controller: _serPrefix, mono: true)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton(
                        onPressed: _busy
                            ? null
                            : () => _runMutation(
                                  (api) => api.post('/accounting/document-series', body: {
                                    'financialYearId': _serFyId.text.trim(),
                                    'documentType': _serDocType.text.trim().toUpperCase(),
                                    'seriesKey': _serKey.text.trim().toUpperCase(),
                                    'prefix': _serPrefix.text.trim(),
                                    'padding': 6,
                                  }),
                                  'Document series created.',
                                ),
                        child: const Text('Create series'),
                      ),
                    ),
                    const Divider(height: 24),
                    Text('4. Ledger account', style: T.body(13, w: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: SaasField(label: 'Code (1000)', controller: _acctCode, mono: true)),
                        const SizedBox(width: 10),
                        Expanded(child: SaasField(label: 'Account name', controller: _acctName)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SaasDropdown(
                            label: 'Group',
                            value: _acctGroup,
                            options: const {
                              'ASSET': 'ASSET',
                              'LIABILITY': 'LIABILITY',
                              'EQUITY': 'EQUITY',
                              'INCOME': 'INCOME',
                              'EXPENSE': 'EXPENSE',
                            },
                            onChanged: (v) => setState(() => _acctGroup = v),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasDropdown(
                            label: 'Control type',
                            value: _acctControl,
                            options: const {
                              'NONE': 'NONE',
                              'CUSTOMER_RECEIVABLE': 'CUSTOMER_RECEIVABLE',
                              'SUPPLIER_PAYABLE': 'SUPPLIER_PAYABLE',
                              'INVENTORY': 'INVENTORY',
                              'CASH': 'CASH',
                              'BANK': 'BANK',
                              'PAYMENT_CLEARING': 'PAYMENT_CLEARING',
                              'TAX_INPUT': 'TAX_INPUT',
                              'TAX_OUTPUT': 'TAX_OUTPUT',
                            },
                            onChanged: (v) => setState(() => _acctControl = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton(
                        onPressed: _busy
                            ? null
                            : () => _runMutation(
                                  (api) => api.post('/accounting/accounts', body: {
                                    'code': _acctCode.text.trim().toUpperCase(),
                                    'name': _acctName.text.trim(),
                                    'group': _acctGroup,
                                    'controlType': _acctControl,
                                    'currency': 'INR',
                                  }),
                                  'Ledger account created.',
                                ),
                        child: const Text('Create account'),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Manual adjustment draft (Screenshot 683/685)
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Manual adjustment draft',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Open period',
                    controller: _jPeriodId,
                    options: _lk.openPeriods(),
                    hint: 'Open period',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Journal series',
                    controller: _jSeriesId,
                    options: _lk.seriesFor(const ['JOURNAL']),
                    hint: 'Journal series',
                  ),
                  const SizedBox(height: 10),
                  DatePickField(label: 'Business date', controller: _jDate),
                  const SizedBox(height: 10),
                  SaasField(label: 'Adjustment description', controller: _jDesc),
                  const SizedBox(height: 12),
                  for (var i = 0; i < _jLines.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    SaasSubBox(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: GoldDropdown<String>(
                                  value: _jLines[i].accountId.isEmpty ? null : _jLines[i].accountId,
                                  hint: 'Account',
                                  items: _lk.accounts
                                      .map((a) => DropdownMenuItem(
                                            value: a.id,
                                            child: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ))
                                      .toList(),
                                  onChanged: (v) => setState(() => _jLines[i].accountId = v ?? ''),
                                ),
                              ),
                              if (_jLines.length > 2)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.close_rounded, size: 17, color: Pal.err),
                                  onPressed: () => setState(() {
                                    final rem = _jLines.removeAt(i);
                                    rem.dispose();
                                  }),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _jLines[i].desc,
                            decoration: const InputDecoration(hintText: 'Line description'),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Debit',
                                  controller: _jLines[i].debit,
                                  mono: true,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasField(
                                  label: 'Credit',
                                  controller: _jLines[i].credit,
                                  mono: true,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _jLines.add(_JournalDraftLine())),
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('Add line'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SaasField(
                    label: 'Business reason (minimum 10 characters)',
                    controller: _jReason,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _saveBalancedDraft,
                      child: Text(_busy ? 'Saving…' : 'Save balanced draft'),
                    ),
                  ),
                ],
              ),
            ),

            // Period control (Screenshot 685)
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Period control',
              icon: Icons.lock_outline_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasField(
                    label: 'Period control & posting reason',
                    controller: _periodActionReason,
                    maxLines: 2,
                  ),
                  if (allPeriods.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final p in allPeriods)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${p['code']} · ${p['name']} (${p['state']})',
                                style: T.body(12.8, w: FontWeight.w600),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () {
                                      final open = '${p['state']}' == 'OPEN';
                                      _runMutation(
                                        (api) => api.post(
                                          '/accounting/posting-periods/${p['id']}/${open ? 'close' : 'reopen'}',
                                          body: {
                                            'expectedVersion': asInt(p['version'], fallback: 1),
                                            'reason': _periodActionReason.text.trim(),
                                          },
                                        ),
                                        open ? 'Period closed.' : 'Period reopened.',
                                      );
                                    },
                              child: Text('${p['state']}' == 'OPEN' ? 'Close' : 'Reopen'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Journals list (Screenshot 685)
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Journals',
              subtitle: 'Date / document · Description · Status · Total · Action',
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : journals.isEmpty
                      ? const SaasEmptyBox('No journals recorded yet.')
                      : Column(
                          children: [
                            for (final j in journals)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SaasSubBox(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${fmtDate('${j['businessDate'] ?? ''}')} · ${j['documentNumber'] ?? 'DRAFT'}',
                                              style: T.mono(12.5, w: FontWeight.w700),
                                            ),
                                          ),
                                          StatusChip('${j['state'] ?? 'DRAFT'}'),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${j['description'] ?? ''}', style: T.body(13, w: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      KVRow('Total', inr(j['debitTotal']), bold: true),
                                      if ('${j['state']}' == 'DRAFT' || '${j['state']}' == 'POSTED') ...[
                                        const SizedBox(height: 6),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: ElevatedButton(
                                            onPressed: _busy
                                                ? null
                                                : () {
                                                    if ('${j['state']}' == 'DRAFT') {
                                                      _runMutation(
                                                        (api) => api.post(
                                                          '/accounting/journals/${j['id']}/post',
                                                          idempotent: true,
                                                          body: {
                                                            'expectedVersion': asInt(j['version'], fallback: 1),
                                                            'reason': _periodActionReason.text.trim(),
                                                          },
                                                        ),
                                                        'Journal posted.',
                                                      );
                                                    } else {
                                                      _runMutation(
                                                        (api) => api.post(
                                                          '/accounting/journals/${j['id']}/reverse',
                                                          idempotent: true,
                                                          body: {
                                                            'expectedVersion': asInt(j['version'], fallback: 1),
                                                            'postingPeriodId': _jPeriodId.text.trim(),
                                                            'documentSeriesId': _jSeriesId.text.trim(),
                                                            'businessDate': _jDate.text.trim(),
                                                            'reason': _periodActionReason.text.trim(),
                                                          },
                                                        ),
                                                        'Reversal journal posted.',
                                                      );
                                                    }
                                                  },
                                            child: Text('${j['state']}' == 'DRAFT' ? 'Post' : 'Reverse'),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),

            // Profit & Loss / Balance Sheet (Screenshot 686)
            const SizedBox(height: 16),
            SaasFormCard(
              title: 'Profit & Loss / Balance Sheet',
              subtitle:
                  'Real-time financial statements derived directly from posted general ledger journal entries.',
              icon: Icons.bar_chart_rounded,
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
                      Expanded(child: DatePickField(label: 'Period start (P&L)', controller: _stmtStart)),
                      const SizedBox(width: 10),
                      Expanded(child: DatePickField(label: 'Period end / BS date', controller: _stmtEnd)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(label: 'Currency', controller: _stmtCurrency, mono: true),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _generateStatement,
                      child: const Text('Generate statement'),
                    ),
                  ),
                  if (_stmtData != null) ...[
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Column(
                        children: [
                          if (_stmtData!.containsKey('totalDebit'))
                            KVRow('Total Debit / Credit', '${inr(_stmtData!['totalDebit'])} / ${inr(_stmtData!['totalCredit'])}', bold: true),
                          for (final a in asList(_stmtData!['accounts'] ?? _stmtData!['lines']))
                            KVRow(
                              '${a['code'] ?? ''} ${a['name'] ?? ''}',
                              inr(a['closingDebit'] ?? a['balance'] ?? a['amount'] ?? '0.00'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Opening data and annual close (Screenshots 687 & 688)
            const SizedBox(height: 16),
            SaasFormCard(
              title: 'Opening data and annual close',
              subtitle:
                  'Stage opening balances, dry-run posting validation, post cutover snapshots, and close completed financial years.',
              icon: Icons.upload_file_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasField(label: 'Business reason', controller: _closeReason),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Accountant/source-control evidence',
                    controller: _closeEvidence,
                  ),
                  const SizedBox(height: 14),
                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Stage opening data', style: T.body(14, w: FontWeight.w700)),
                            OutlinedButton(
                              onPressed: _populateOpeningTemplate,
                              child: const Text('Create import template'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SaasField(
                          label: 'Opening cutover JSON',
                          controller: _openingJson,
                          mono: true,
                          maxLines: 5,
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _stageOpeningSnapshot,
                            child: const Text('Validate & stage opening snapshot'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => setState(() => _showMappingRefs = !_showMappingRefs),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _showMappingRefs
                                      ? Icons.expand_less_rounded
                                      : Icons.chevron_right_rounded,
                                  size: 18,
                                  color: Pal.goldDeep,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Account and master mapping references',
                                  style: T.body(12.2, color: Pal.ink, w: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showMappingRefs)
                          for (final a in _lk.accounts)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('${a.label} → ${a.id}', style: T.mono(11, color: Pal.muted)),
                            ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Prepare annual close', style: T.body(14, w: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'All periods in the completed year must be closed before preparing retained-earnings carry-forward.',
                          style: T.body(11.8, color: Pal.muted),
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Completed financial year',
                          controller: _completedFyId,
                          options: _lk.financialYears,
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Contiguous next financial year',
                          controller: _nextFyId,
                          options: _lk.financialYears,
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Closing JOURNAL series',
                          controller: _closingSeriesId,
                          options: _lk.seriesFor(const ['JOURNAL']),
                        ),
                        const SizedBox(height: 10),
                        LookupField(
                          label: 'Retained earnings equity account',
                          controller: _retainedEquityAcctId,
                          options: _lk.accountsByControl(const ['EQUITY']),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _prepareAnnualClose,
                            child: const Text('Prepare close and control snapshot'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SaasDropdown(
                    label: 'Workflow history · latest 200',
                    value: _workflowRecordId,
                    options: const {'': 'Select...'},
                    onChanged: (v) => setState(() => _workflowRecordId = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. SETTLEMENTS & CASHUP (`/payments`) — Screenshot (689)
// ---------------------------------------------------------------------------

class SettlementsCashupScreen extends StatefulWidget {
  const SettlementsCashupScreen({super.key});
  @override
  State<SettlementsCashupScreen> createState() => _SettlementsCashupScreenState();
}

class _SettlementsCashupScreenState extends State<SettlementsCashupScreen> {
  String _tab = 'OPEN_ITEMS';
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _showForm = false;

  // Shared posting configuration
  final _periodId = TextEditingController();
  final _docSeriesId = TextEditingController();
  final _journalSeriesId = TextEditingController();

  // Settlement fields (`settlementCommandBaseSchema`)
  final _partyId = TextEditingController();
  final _instrumentAcctId = TextEditingController();
  String _method = 'BANK_TRANSFER';
  final _settlementDate = TextEditingController(text: todayIso());
  final _amount = TextEditingController();
  final _paymentRef = TextEditingController();
  final _providerRef = TextEditingController();
  final _openItemId = TextEditingController();
  final _reason = TextEditingController(
    text: 'Authorized counterparty settlement verified against bank / cash register.',
  );

  // Provider clearing fields (`postProviderClearingSchema`)
  final _providerName = TextEditingController(text: 'RAZORPAY');
  final _providerBatchRef = TextEditingController();
  final _feeAmt = TextEditingController(text: '0.00');
  final _sourceClearAcctId = TextEditingController();
  final _bankAcctId = TextEditingController();
  final _feeAcctId = TextEditingController();
  final _settlementDocId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _periodId, _docSeriesId, _journalSeriesId, _partyId, _instrumentAcctId,
      _settlementDate, _amount, _paymentRef, _providerRef, _openItemId, _reason,
      _providerName, _providerBatchRef, _feeAmt, _sourceClearAcctId,
      _bankAcctId, _feeAcctId, _settlementDocId,
    ]) {
      c.dispose();
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
      final res = await Future.wait([
        api.get('/payments'),
        WorkspaceLookup.load(api, includeParties: true, includeAccounting: true),
      ]);
      if (!mounted) return;
      final lk = res[1] as WorkspaceLookup;
      if (_periodId.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _periodId.text = lk.openPeriods().first.id;
      }
      if (_journalSeriesId.text.isEmpty) {
        final js = lk.seriesFor(const ['JOURNAL']);
        if (js.isNotEmpty) _journalSeriesId.text = js.first.id;
      }
      if (_docSeriesId.text.isEmpty && lk.series.isNotEmpty) {
        _docSeriesId.text = lk.series.first.id;
      }
      setState(() {
        _ws = asMap(res[0]);
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitSettlement() async {
    if (_periodId.text.trim().isEmpty ||
        _docSeriesId.text.trim().isEmpty ||
        _journalSeriesId.text.trim().isEmpty ||
        _reason.text.trim().length < 10) {
      setState(() => _error = 'Select Posting period, Document series, Journal series, and Reason (10+ chars).');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      if (_tab == 'CLEARINGS') {
        await api.post('/payments/provider-clearings', idempotent: true, body: {
          'provider': _providerName.text.trim().toUpperCase(),
          'providerBatchRef': _providerBatchRef.text.trim(),
          'settlementDate': _settlementDate.text.trim(),
          'feeAmount': _feeAmt.text.trim().isEmpty ? '0.00' : _feeAmt.text.trim(),
          'sourceAccountId': _sourceClearAcctId.text.trim(),
          'bankAccountId': _bankAcctId.text.trim(),
          'feeAccountId': _feeAcctId.text.trim(),
          'postingPeriodId': _periodId.text.trim(),
          'documentSeriesId': _docSeriesId.text.trim(),
          'journalSeriesId': _journalSeriesId.text.trim(),
          'lines': [
            {
              'settlementDocumentId': _settlementDocId.text.trim(),
              'grossAmount': _amount.text.trim(),
            },
          ],
          'reason': _reason.text.trim(),
        });
      } else {
        final isCardOrUpi = _method == 'CARD' || _method == 'UPI';
        final path = _tab == 'DISBURSEMENTS'
            ? '/payments/supplier-disbursements'
            : _tab == 'REFUNDS'
                ? '/payments/customer-refunds'
                : '/payments/customer-receipts';
        await api.post(path, idempotent: true, body: {
          'partyId': _partyId.text.trim(),
          'method': _method,
          'settlementDate': _settlementDate.text.trim(),
          'currency': 'INR',
          'amount': _amount.text.trim(),
          'instrumentAccountId': _instrumentAcctId.text.trim(),
          if (isCardOrUpi)
            'providerReference': _providerRef.text.trim()
          else if (_paymentRef.text.trim().length >= 2)
            'paymentReference': _paymentRef.text.trim(),
          'postingPeriodId': _periodId.text.trim(),
          'documentSeriesId': _docSeriesId.text.trim(),
          'journalSeriesId': _journalSeriesId.text.trim(),
          'allocations': _openItemId.text.trim().isNotEmpty
              ? [
                  {
                    'openItemId': _openItemId.text.trim(),
                    'amount': _amount.text.trim(),
                  },
                ]
              : [],
          'reason': _reason.text.trim(),
        });
      }
      if (!mounted) return;
      _amount.clear();
      setState(() => _showForm = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settlement posted to subledger & GL.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final openItems = asList(_ws['openItems']);
    final settlements = asList(_ws['settlements']);
    final clearings = asList(_ws['providerClearings'] ?? _ws['clearings']);

    final openOpts = openItems
        .map((o) => LookupOption(
              id: '${o['id']}',
              label: '${o['documentNumber']} · ${asMap(o['party'])['displayName'] ?? ''} · Open ${inr(o['openAmount'])}',
              raw: o,
            ))
        .toList();
    final settlementOpts = settlements
        .map((s) => LookupOption(
              id: '${s['id']}',
              label: '${s['documentNumber'] ?? shortId('${s['id']}')} · ${inr(s['amount'])} (${s['method'] ?? ''})',
              raw: s,
            ))
        .toList();

    final methodOptions = (_tab == 'DISBURSEMENTS' || _tab == 'REFUNDS')
        ? const {
            'BANK_TRANSFER': 'BANK_TRANSFER',
            'CASH': 'CASH',
            'CHEQUE': 'CHEQUE',
          }
        : const {
            'UPI': 'UPI',
            'CARD': 'CARD',
            'BANK_TRANSFER': 'BANK_TRANSFER',
            'CASH': 'CASH',
            'CHEQUE': 'CHEQUE',
          };
    if (!methodOptions.containsKey(_method)) {
      _method = methodOptions.keys.first;
    }

    return LuxuryModuleScaffold(
      title: 'Settlements & Cashup',
      icon: Icons.account_balance_wallet_outlined,
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _showForm = v != 'OPEN_ITEMS';
        }),
        tabs: [
          ('OPEN_ITEMS', 'Open Items (${openItems.length})'),
          ('RECEIPTS', 'Receipts'),
          ('DISBURSEMENTS', 'Disbursements'),
          ('REFUNDS', 'Refunds'),
          ('CLEARINGS', 'Provider Clearings (${clearings.length})'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],

            if (_tab != 'OPEN_ITEMS') ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _showForm = !_showForm),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: Text(
                    _tab == 'RECEIPTS'
                        ? 'Post Customer Receipt'
                        : _tab == 'DISBURSEMENTS'
                            ? 'Post Supplier Disbursement'
                            : _tab == 'REFUNDS'
                                ? 'Post Customer Refund'
                                : 'Post Provider Clearing',
                  ),
                ),
              ),
            ],

            if (_showForm && _tab != 'OPEN_ITEMS') ...[
              const SizedBox(height: 12),
              SaasFormCard(
                title: _tab == 'CLEARINGS'
                    ? 'Post Provider Clearing Batch'
                    : 'Post ${_tab.substring(0, _tab.length - 1)}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(label: 'Posting period', controller: _periodId, options: _lk.openPeriods()),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: LookupField(
                            label: 'Document series',
                            controller: _docSeriesId,
                            options: _lk.series,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: LookupField(
                            label: 'Journal series',
                            controller: _journalSeriesId,
                            options: _lk.seriesFor(const ['JOURNAL']),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DatePickField(label: 'Settlement date', controller: _settlementDate),
                    const SizedBox(height: 10),
                    if (_tab == 'CLEARINGS') ...[
                      Row(
                        children: [
                          Expanded(child: SaasField(label: 'Provider (RAZORPAY)', controller: _providerName, mono: true)),
                          const SizedBox(width: 10),
                          Expanded(child: SaasField(label: 'Provider batch ref', controller: _providerBatchRef, mono: true)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Source clearing account',
                        controller: _sourceClearAcctId,
                        options: _lk.accountsByControl(const ['PAYMENT_CLEARING', 'ASSET']),
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Bank account',
                        controller: _bankAcctId,
                        options: _lk.accountsByControl(const ['BANK', 'ASSET']),
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Gateway fee expense account',
                        controller: _feeAcctId,
                        options: _lk.accountsByControl(const ['EXPENSE']),
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Card/UPI settlement document',
                        controller: _settlementDocId,
                        options: settlementOpts,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SaasField(
                              label: 'Gross amount (INR)',
                              controller: _amount,
                              mono: true,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SaasField(
                              label: 'Fee amount (INR)',
                              controller: _feeAmt,
                              mono: true,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      LookupField(
                        label: _tab == 'DISBURSEMENTS' ? 'Supplier' : 'Customer',
                        controller: _partyId,
                        options: _lk.partiesByRole(_tab == 'DISBURSEMENTS' ? 'SUPPLIER' : 'CUSTOMER'),
                      ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Instrument account (Cash / Bank / Clearing)',
                        controller: _instrumentAcctId,
                        options: _lk.accountsByControl(const ['CASH', 'BANK', 'PAYMENT_CLEARING']),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: SaasDropdown(
                              label: 'Method',
                              value: _method,
                              options: methodOptions,
                              onChanged: (v) => setState(() => _method = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SaasField(
                              label: 'Amount (INR)',
                              controller: _amount,
                              mono: true,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_method == 'CARD' || _method == 'UPI')
                        SaasField(
                          label: 'Provider reference (required for Card/UPI)',
                          controller: _providerRef,
                          mono: true,
                        )
                      else
                        SaasField(
                          label: 'Payment reference (optional)',
                          controller: _paymentRef,
                          mono: true,
                        ),
                      const SizedBox(height: 10),
                      LookupField(
                        label: _tab == 'REFUNDS'
                            ? 'Credit open item (required)'
                            : 'Allocate open item (optional)',
                        controller: _openItemId,
                        options: openOpts,
                        optional: _tab != 'REFUNDS',
                      ),
                    ],
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Reason (minimum 10 characters)',
                      controller: _reason,
                    ),
                    const SizedBox(height: 14),
                    GoldButton(
                      label: 'Post Settlement',
                      icon: Icons.check_rounded,
                      busy: _busy,
                      onPressed: _submitSettlement,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tab == 'OPEN_ITEMS')
              openItems.isEmpty
                  ? const SaasEmptyBox('No open receivable or payable items.')
                  : Column(
                      children: [
                        for (final o in openItems)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${o['documentNumber']} · ${asMap(o['party'])['displayName'] ?? ''}',
                                          style: T.body(14, w: FontWeight.w700),
                                        ),
                                      ),
                                      StatusChip('${o['state'] ?? 'OPEN'}'),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  KVRow('Date / Kind', '${fmtDate('${o['documentDate'] ?? ''}')} · ${o['kind'] ?? ''}'),
                                  KVRow('GL Account', '${asMap(o['account'])['code'] ?? ''} · ${asMap(o['account'])['name'] ?? ''}'),
                                  KVRow('Original / Settled', '${inr(o['originalAmount'])} / ${inr(o['settledAmount'])}'),
                                  KVRow('Open Amount', inr(o['openAmount']), bold: true),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
            else if (_tab == 'CLEARINGS')
              clearings.isEmpty
                  ? const SaasEmptyBox('No provider clearings recorded yet.')
                  : Column(
                      children: [
                        for (final c in clearings)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${c['provider'] ?? ''} · ${c['providerBatchRef'] ?? ''}', style: T.body(14, w: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  KVRow('Settlement Date', fmtDate('${c['settlementDate'] ?? ''}')),
                                  KVRow('Fee', inr(c['feeAmount'])),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
            else
              settlements.isEmpty
                  ? const SaasEmptyBox('No settlement documents recorded yet.')
                  : Column(
                      children: [
                        for (final s in settlements)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SectionCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${s['documentNumber'] ?? shortId('${s['id']}')} · ${asMap(s['party'])['displayName'] ?? ''}',
                                          style: T.body(14, w: FontWeight.w700),
                                        ),
                                      ),
                                      StatusChip('${s['method'] ?? s['state'] ?? 'POSTED'}'),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  KVRow('Date', fmtDate('${s['settlementDate'] ?? ''}')),
                                  KVRow('Amount', inr(s['amount']), bold: true),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. BANKING & RECONCILIATION (`/banking`) — Screenshot (690)
// ---------------------------------------------------------------------------

class BankingReconciliationScreen extends StatefulWidget {
  const BankingReconciliationScreen({super.key});
  @override
  State<BankingReconciliationScreen> createState() => _BankingReconciliationScreenState();
}

class _BankingReconciliationScreenState extends State<BankingReconciliationScreen> {
  List<Map<String, dynamic>> _statements = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _bankAcctId = TextEditingController();
  final _statementId = TextEditingController();
  final _startDate = TextEditingController(text: todayIso());
  final _endDate = TextEditingController(text: todayIso());
  final _openingBal = TextEditingController();
  final _closingBal = TextEditingController();
  final _currency = TextEditingController(text: 'INR');
  final _csvText = TextEditingController(
    text: 'transaction_date,direction,amount,description',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _bankAcctId, _statementId, _startDate, _endDate,
      _openingBal, _closingBal, _currency, _csvText,
    ]) {
      c.dispose();
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
      final res = await Future.wait([
        api.get('/banking'),
        WorkspaceLookup.load(api, includeParties: false, includeAccounting: true),
      ]);
      if (!mounted) return;
      setState(() {
        _statements = asList(res[0], keys: const ['statements', 'bankStatements', 'items']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _importStatement() async {
    if (_bankAcctId.text.trim().isEmpty ||
        _statementId.text.trim().isEmpty ||
        _openingBal.text.trim().isEmpty ||
        _closingBal.text.trim().isEmpty ||
        _csvText.text.trim().isEmpty) {
      setState(() => _error = 'Complete Bank account UUID, Statement ID, Opening/Closing balances, and CSV rows.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/banking/statements',
        idempotent: true,
        body: {
          'bankAccountId': _bankAcctId.text.trim(),
          'externalStatementId': _statementId.text.trim(),
          'startDate': _startDate.text.trim(),
          'endDate': _endDate.text.trim(),
          'openingBalance': _openingBal.text.trim(),
          'closingBalance': _closingBal.text.trim(),
          'currency': _currency.text.trim().toUpperCase(),
          'csvContent': _csvText.text.trim(),
        },
      );
      if (!mounted) return;
      _statementId.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bank statement imported.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LuxuryModuleScaffold(
      title: 'Banking & Reconciliation',
      icon: Icons.account_balance_rounded,
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            SaasFormCard(
              title: 'Import normalized bank CSV',
              subtitle:
                  'Required columns: transaction_date, direction, amount, description. Optional: value_date, reference, bank_transaction_id.',
              icon: Icons.upload_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Bank account UUID',
                    controller: _bankAcctId,
                    options: _lk.accountsByControl(const ['BANK', 'ASSET']),
                    hint: 'Bank account UUID',
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Statement ID',
                    controller: _statementId,
                    hint: 'Statement ID',
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: DatePickField(label: 'Start date', controller: _startDate)),
                      const SizedBox(width: 10),
                      Expanded(child: DatePickField(label: 'End date', controller: _endDate)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Opening balance',
                          controller: _openingBal,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Closing balance',
                          controller: _closingBal,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(label: 'Currency', controller: _currency, mono: true),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Normalized CSV content',
                    controller: _csvText,
                    mono: true,
                    maxLines: 5,
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _importStatement,
                      child: Text(_busy ? 'Importing…' : 'Import statement'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_statements.isEmpty)
              const SaasEmptyBox('No bank statements imported yet.')
            else
              for (final s in _statements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${s['externalStatementId'] ?? shortId('${s['id']}')}',
                                style: T.mono(13.5, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${s['state'] ?? s['status'] ?? 'IMPORTED'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Period', '${fmtDate('${s['startDate'] ?? ''}')} → ${fmtDate('${s['endDate'] ?? ''}')}'),
                        KVRow('Opening / Closing', '${inr(s['openingBalance'])} → ${inr(s['closingBalance'])}', bold: true),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. CONSOLIDATED CHAIN ANALYTICS (`/chain-analytics`) — Screenshot (691)
// ---------------------------------------------------------------------------

class ConsolidatedChainAnalyticsScreen extends StatefulWidget {
  const ConsolidatedChainAnalyticsScreen({super.key});
  @override
  State<ConsolidatedChainAnalyticsScreen> createState() =>
      _ConsolidatedChainAnalyticsScreenState();
}

class _ConsolidatedChainAnalyticsScreenState
    extends State<ConsolidatedChainAnalyticsScreen> {
  final _fromDate = TextEditingController(text: monthStartIso());
  final _toDate = TextEditingController(text: todayIso());
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
    _fromDate.dispose();
    _toDate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/chain-analytics', query: {
        'from': _fromDate.text.trim(),
        'to': _toDate.text.trim(),
        'startDate': _fromDate.text.trim(),
        'endDate': _toDate.text.trim(),
      });
      if (!mounted) return;
      setState(() => _data = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reported = asMap(_data['reportedTotals'] ?? _data['reportedLedgerTotals']);
    final consolidated = asMap(_data['consolidatedTotals'] ?? _data['afterEliminations']);
    final icPairs = asList(_data['intercompanyReconciliation'] ?? _data['entityPairs']);
    final eliminations = asList(_data['eliminationSchedule'] ?? _data['eliminations']);
    final entities = asList(_data['legalEntities'] ?? _data['legalEntityComparison']);
    final balanced = _data['intercompanyBalanced'] != false;

    return LuxuryModuleScaffold(
      title: 'Consolidated Chain Analytics',
      icon: Icons.hub_outlined,
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            Row(
              children: [
                Expanded(
                  child: DatePickField(
                    label: 'From',
                    controller: _fromDate,
                    onChanged: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DatePickField(
                    label: 'To',
                    controller: _toDate,
                    onChanged: (_) => _load(),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasKpiGrid(
              items: [
                (
                  label: 'AUTHORIZED ENTITIES',
                  value: '${_data['authorizedEntities'] ?? entities.length}',
                ),
                (
                  label: 'AUTHORIZED BRANCHES',
                  value: '${_data['authorizedBranches'] ?? 0}',
                ),
                (
                  label: 'REPORTED PROFIT · INR',
                  value: '${reported['profit'] ?? _data['reportedProfit'] ?? '0.00'}',
                ),
                (
                  label: 'CONSOLIDATED PROFIT · INR',
                  value: '${consolidated['profit'] ?? _data['consolidatedProfit'] ?? '0.00'}',
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              SaasFormCard(
                title: 'Reported ledger totals',
                child: Column(
                  children: [
                    KVRow('Revenue', inr(reported['revenue'] ?? '0.00')),
                    KVRow('Expense', inr(reported['expense'] ?? '0.00')),
                    KVRow('Net Profit', inr(reported['profit'] ?? _data['reportedProfit'] ?? '0.00'), bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SaasFormCard(
                title: 'After consolidation eliminations',
                child: Column(
                  children: [
                    KVRow('Consolidated Revenue', inr(consolidated['revenue'] ?? '0.00')),
                    KVRow('Consolidated Expense', inr(consolidated['expense'] ?? '0.00')),
                    KVRow('Consolidated Profit', inr(consolidated['profit'] ?? _data['consolidatedProfit'] ?? '0.00'), bold: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SaasFormCard(
                title: 'Intercompany reconciliation',
                trailing: StatusChip(balanced ? 'BALANCED' : 'VARIANCE'),
                child: icPairs.isEmpty
                    ? Text('No intercompany receivable or payable balances.', style: T.body(12.5, color: Pal.muted))
                    : Column(
                        children: [
                          for (final p in icPairs)
                            KVRow(
                              '${p['entityPair'] ?? ''}',
                              'AR ${inr(p['receivable'])} / AP ${inr(p['payable'])} (Diff ${inr(p['difference'])})',
                            ),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              SaasFormCard(
                title: 'Elimination schedule',
                child: eliminations.isEmpty
                    ? Text('No posted inter-entity elimination entries in the selected range.', style: T.body(12.5, color: Pal.muted))
                    : Column(
                        children: [
                          for (final el in eliminations)
                            KVRow('${el['description'] ?? el['reference'] ?? ''}', inr(el['amount'])),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              SaasFormCard(
                title: 'Legal-entity comparison',
                child: entities.isEmpty
                    ? Text('No legal-entity comparison rows returned.', style: T.body(12.5, color: Pal.muted))
                    : Column(
                        children: [
                          for (final e in entities)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: SaasSubBox(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${e['legalName'] ?? e['name'] ?? 'Entity'}', style: T.body(13.8, w: FontWeight.w700)),
                                    Text(
                                      '${e['authorizedBranchCount'] ?? asList(e['branches']).length} authorized branch(es) · ${e['currency'] ?? 'INR'}',
                                      style: T.body(11.8, color: Pal.muted),
                                    ),
                                    if (e['profit'] != null) ...[
                                      const SizedBox(height: 4),
                                      KVRow('Profit', inr(e['profit']), bold: true),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef ConsolidatedAnalyticsScreen = ConsolidatedChainAnalyticsScreen;
