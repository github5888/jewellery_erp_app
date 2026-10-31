import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

const _uuid = Uuid();

String _fyStartIso() {
  final now = DateTime.now();
  final fyYear = now.month >= 4 ? now.year : now.year - 1;
  return '$fyYear-04-01';
}

String _fyEndIso() {
  final now = DateTime.now();
  final fyEndYear = now.month >= 4 ? now.year + 1 : now.year;
  return '$fyEndYear-03-31';
}

// ---------------------------------------------------------------------------
// 1. DOUBLE-ENTRY ACCOUNTING (`/accounting/workspace`) — `image-29..31.png`
// ---------------------------------------------------------------------------

class DoubleEntryAccountingScreen extends StatefulWidget {
  const DoubleEntryAccountingScreen({super.key});
  @override
  State<DoubleEntryAccountingScreen> createState() =>
      _DoubleEntryAccountingScreenState();
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

class _DoubleEntryAccountingScreenState
    extends State<DoubleEntryAccountingScreen> {
  final _search = TextEditingController();
  String _tab = 'LEDGER';
  bool _draftExpanded = true;
  bool _periodsExpanded = true;
  bool _showMappingRefs = false;
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Manual adjustment draft (`image-29.png`)
  final _jPeriodId = TextEditingController();
  final _jSeriesId = TextEditingController();
  final _jDate = TextEditingController(text: todayIso());
  final _jDesc = TextEditingController();
  final _jReason = TextEditingController();
  final List<_JournalDraftLine> _jLines = [
    _JournalDraftLine(),
    _JournalDraftLine(),
  ];

  // Period control (`image-29.png`)
  final _periodActionReason = TextEditingController(
    text:
        'Approved after reviewing the accounting source and supporting evidence.',
  );

  // Profit & Loss / Balance Sheet (`image-30.png`)
  String _stmtKind = 'PROFIT_AND_LOSS';
  final _stmtStart = TextEditingController(text: _fyStartIso());
  final _stmtEnd = TextEditingController(text: todayIso());
  final _stmtCurrency = TextEditingController(text: 'INR');
  Map<String, dynamic>? _stmtResult;

  // Opening data and annual close (`image-30.png` & `image-31.png`)
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
      _search,
      _jPeriodId,
      _jSeriesId,
      _jDate,
      _jDesc,
      _jReason,
      _periodActionReason,
      _stmtStart,
      _stmtEnd,
      _stmtCurrency,
      _closeReason,
      _closeEvidence,
      _openingJson,
      _completedFyId,
      _nextFyId,
      _closingSeriesId,
      _retainedEquityAcctId,
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
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeAccounting: true,
          includeOrganization: true,
        ),
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

  Future<void> _runMutation(
    Future<void> Function(ApiClient api) fn,
    String okMsg,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn(context.read<ApiClient>());
      if (!mounted) return;
      toast(context, okMsg);
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------------------
  // `+ Accounting setup` modal sheet (`image-29.png` top-right button)
  // -------------------------------------------------------------------------
  Future<void> _openAccountingSetupSheet() async {
    var setupTab = 'YEAR';
    final fyLabelCtrl = TextEditingController();
    final fyStartCtrl = TextEditingController(text: _fyStartIso());
    final fyEndCtrl = TextEditingController(text: _fyEndIso());

    final perFyCtrl = TextEditingController(
      text: _lk.financialYears.isNotEmpty ? _lk.financialYears.first.id : '',
    );
    final perCodeCtrl = TextEditingController();
    final perNameCtrl = TextEditingController();
    final perStartCtrl = TextEditingController(text: monthStartIso());
    final perEndCtrl = TextEditingController(text: todayIso());

    final serFyCtrl = TextEditingController(
      text: _lk.financialYears.isNotEmpty ? _lk.financialYears.first.id : '',
    );
    var serDocType = 'JOURNAL';
    final serKeyCtrl = TextEditingController(text: 'MANUAL');
    final serPrefixCtrl = TextEditingController(text: 'JV/');
    final serPadCtrl = TextEditingController(text: '6');

    final acctCodeCtrl = TextEditingController();
    final acctNameCtrl = TextEditingController();
    var acctGroup = 'ASSET';
    var acctControl = 'NONE';
    final acctCurrCtrl = TextEditingController(text: 'INR');

    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.menu_book_rounded, color: Pal.gold, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Accounting setup',
                        style: T.body(17, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                Text(
                  'Entity-scoped financial years, posting periods, document series, and GL chart of accounts.',
                  style: T.body(12, color: Pal.muted),
                ),
                const SizedBox(height: 12),
                PillTabs<String>(
                  value: setupTab,
                  onChanged: (v) => setSheet(() {
                    setupTab = v;
                    sheetErr = null;
                  }),
                  tabs: const [
                    ('YEAR', 'Financial Year'),
                    ('PERIOD', 'Posting Period'),
                    ('SERIES', 'Doc Series'),
                    ('ACCOUNT', 'GL Account'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (setupTab == 'YEAR') ...[
                  SaasField(
                    label: 'Financial year label',
                    controller: fyLabelCtrl,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DatePickField(
                          label: 'Start date',
                          controller: fyStartCtrl,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DatePickField(
                          label: 'End date',
                          controller: fyEndCtrl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Create financial year',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (fyLabelCtrl.text.trim().isEmpty) {
                              setSheet(
                                () => sheetErr = 'Enter financial year label.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/accounting/financial-years',
                                idempotent: true,
                                body: {
                                  'label': fyLabelCtrl.text.trim(),
                                  'startDate': fyStartCtrl.text.trim(),
                                  'endDate': fyEndCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Financial year created.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (setupTab == 'PERIOD') ...[
                  LookupField(
                    label: 'Financial year',
                    controller: perFyCtrl,
                    options: _lk.financialYears,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Period code',
                          controller: perCodeCtrl,
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Period name',
                          controller: perNameCtrl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DatePickField(
                          label: 'Start date',
                          controller: perStartCtrl,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DatePickField(
                          label: 'End date',
                          controller: perEndCtrl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Create posting period',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (perFyCtrl.text.trim().isEmpty ||
                                perCodeCtrl.text.trim().isEmpty ||
                                perNameCtrl.text.trim().isEmpty) {
                              setSheet(
                                () => sheetErr =
                                    'Select financial year and enter period code & name.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/accounting/posting-periods',
                                idempotent: true,
                                body: {
                                  'financialYearId': perFyCtrl.text.trim(),
                                  'code':
                                      perCodeCtrl.text.trim().toUpperCase(),
                                  'name': perNameCtrl.text.trim(),
                                  'startDate': perStartCtrl.text.trim(),
                                  'endDate': perEndCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Posting period created.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (setupTab == 'SERIES') ...[
                  LookupField(
                    label: 'Financial year',
                    controller: serFyCtrl,
                    options: _lk.financialYears,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  SaasDropdown(
                    label: 'Document type',
                    value: serDocType,
                    options: const {
                      'JOURNAL': 'JOURNAL',
                      'SALES_INVOICE': 'SALES_INVOICE',
                      'PURCHASE_ORDER': 'PURCHASE_ORDER',
                      'GOODS_RECEIPT': 'GOODS_RECEIPT',
                      'SUPPLIER_BILL': 'SUPPLIER_BILL',
                      'JOB_WORK': 'JOB_WORK',
                      'REFINING_BATCH': 'REFINING_BATCH',
                      'STOCK_TRANSFER': 'STOCK_TRANSFER',
                      'APPROVAL_MEMO': 'APPROVAL_MEMO',
                      'INTER_ENTITY_TRADE': 'INTER_ENTITY_TRADE',
                      'RATE_FIXING_CONTRACT': 'RATE_FIXING_CONTRACT',
                      'SETTLEMENT': 'SETTLEMENT',
                    },
                    onChanged: (v) => setSheet(() => serDocType = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Series key',
                          controller: serKeyCtrl,
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Prefix',
                          controller: serPrefixCtrl,
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Padding',
                          controller: serPadCtrl,
                          mono: true,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Create document series',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (serFyCtrl.text.trim().isEmpty ||
                                serKeyCtrl.text.trim().isEmpty ||
                                serPrefixCtrl.text.trim().isEmpty) {
                              setSheet(
                                () => sheetErr =
                                    'Select financial year and enter series key & prefix.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/accounting/document-series',
                                idempotent: true,
                                body: {
                                  'financialYearId': serFyCtrl.text.trim(),
                                  'documentType': serDocType,
                                  'seriesKey':
                                      serKeyCtrl.text.trim().toUpperCase(),
                                  'prefix': serPrefixCtrl.text.trim(),
                                  'padding':
                                      int.tryParse(serPadCtrl.text.trim()) ?? 6,
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Document series created.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Account code',
                          controller: acctCodeCtrl,
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: SaasField(
                          label: 'Account name',
                          controller: acctNameCtrl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasDropdown(
                          label: 'Group',
                          value: acctGroup,
                          options: const {
                            'ASSET': 'ASSET',
                            'LIABILITY': 'LIABILITY',
                            'EQUITY': 'EQUITY',
                            'INCOME': 'INCOME',
                            'EXPENSE': 'EXPENSE',
                          },
                          onChanged: (v) => setSheet(() => acctGroup = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasDropdown(
                          label: 'Control type',
                          value: acctControl,
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
                          onChanged: (v) => setSheet(() => acctControl = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Currency',
                    controller: acctCurrCtrl,
                    mono: true,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Create GL account',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (acctCodeCtrl.text.trim().isEmpty ||
                                acctNameCtrl.text.trim().isEmpty) {
                              setSheet(
                                () => sheetErr =
                                    'Enter account code and account name.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/accounting/accounts',
                                idempotent: true,
                                body: {
                                  'code':
                                      acctCodeCtrl.text.trim().toUpperCase(),
                                  'name': acctNameCtrl.text.trim(),
                                  'group': acctGroup,
                                  'controlType': acctControl,
                                  'currency':
                                      acctCurrCtrl.text.trim().toUpperCase(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'GL account created.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    for (final c in [
      fyLabelCtrl,
      fyStartCtrl,
      fyEndCtrl,
      perFyCtrl,
      perCodeCtrl,
      perNameCtrl,
      perStartCtrl,
      perEndCtrl,
      serFyCtrl,
      serKeyCtrl,
      serPrefixCtrl,
      serPadCtrl,
      acctCodeCtrl,
      acctNameCtrl,
      acctCurrCtrl,
    ]) {
      c.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // Journal Inspector, Post & Linked Reversal Sheet
  // -------------------------------------------------------------------------
  Future<void> _openJournalActionSheet(Map<String, dynamic> j) async {
    final state = '${j['state'] ?? 'DRAFT'}'.toUpperCase();
    final lines = asList(j['lines']);
    final revPeriodCtrl = TextEditingController(
      text: _jPeriodId.text.trim().isNotEmpty
          ? _jPeriodId.text.trim()
          : (_lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : ''),
    );
    final revSeriesCtrl = TextEditingController(
      text: _jSeriesId.text.trim().isNotEmpty
          ? _jSeriesId.text.trim()
          : (_lk.seriesFor(const ['JOURNAL']).isNotEmpty
              ? _lk.seriesFor(const ['JOURNAL']).first.id
              : ''),
    );
    final revDateCtrl = TextEditingController(text: todayIso());
    final revReasonCtrl = TextEditingController(
      text: _periodActionReason.text.trim(),
    );
    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${j['documentNumber'] ?? 'DRAFT JOURNAL'}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill(state),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                Text(
                  '${fmtDate('${j['businessDate'] ?? ''}')} · ${j['sourceType'] ?? 'JOURNAL'}',
                  style: T.body(12, color: Pal.muted),
                ),
                if ('${j['description'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('${j['description']}', style: T.body(13)),
                ],
                if (lines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Balanced Journal Lines',
                          style: T.body(12.2, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        for (final l in lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${asMap(l['account'])['code'] ?? ''} ${asMap(l['account'])['name'] ?? l['description'] ?? ''}'
                                        .trim(),
                                    style: T.body(12),
                                  ),
                                ),
                                Text(
                                  dParse(l['debit']) > Decimal.zero
                                      ? 'Dr ${inr(l['debit'])}'
                                      : 'Cr ${inr(l['credit'])}',
                                  style: T.mono(12),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                if (state == 'DRAFT') ...[
                  const SizedBox(height: 12),
                  SaasField(
                    label: 'Posting audit reason (min 10 chars)',
                    controller: revReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Post Balanced Journal',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (revReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter a posting reason of at least 10 characters.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/accounting/journals/${j['id']}/post',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(j['version'], fallback: 1),
                                  'reason': revReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Journal posted to general ledger.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (state == 'POSTED') ...[
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Reversal open period',
                    controller: revPeriodCtrl,
                    options: _lk.openPeriods(),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Reversal journal series',
                    controller: revSeriesCtrl,
                    options: _lk.seriesFor(const ['JOURNAL']),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  DatePickField(
                    label: 'Reversal date',
                    controller: revDateCtrl,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Reversal business reason (min 10 chars)',
                    controller: revReasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Post Linked Reversal Journal',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (revPeriodCtrl.text.trim().isEmpty ||
                                revSeriesCtrl.text.trim().isEmpty ||
                                revReasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select open period, journal series, and enter reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/accounting/journals/${j['id']}/reverse',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(j['version'], fallback: 1),
                                  'postingPeriodId': revPeriodCtrl.text.trim(),
                                  'documentSeriesId': revSeriesCtrl.text.trim(),
                                  'businessDate': revDateCtrl.text.trim(),
                                  'reason': revReasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Linked reversal journal posted.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    for (final c in [revPeriodCtrl, revSeriesCtrl, revDateCtrl, revReasonCtrl]) {
      c.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // Save Balanced Manual Adjustment Draft (`image-29.png`)
  // -------------------------------------------------------------------------
  Future<void> _saveBalancedDraft() async {
    if (_jPeriodId.text.trim().isEmpty ||
        _jSeriesId.text.trim().isEmpty ||
        _jDesc.text.trim().length < 5 ||
        _jReason.text.trim().length < 10) {
      setState(
        () => _error =
            'Select Open period, Journal series, Adjustment description (5+ chars), and Business reason (minimum 10 characters).',
      );
      return;
    }
    final valid = _jLines
        .where((l) => l.accountId.isNotEmpty && l.desc.text.trim().isNotEmpty)
        .toList();
    if (valid.length < 2) {
      setState(
        () => _error =
            'Provide at least 2 balanced journal lines with account and line description.',
      );
      return;
    }
    var dr = Decimal.zero;
    var cr = Decimal.zero;
    for (final l in valid) {
      dr += dParse(l.debit.text.trim());
      cr += dParse(l.credit.text.trim());
    }
    if (dr <= Decimal.zero || dr != cr) {
      setState(
        () => _error =
            'Debits (${dStr2(dr)}) must equal Credits (${dStr2(cr)}) and be greater than 0.',
      );
      return;
    }
    await _runMutation(
      (api) async {
        await api.post(
          '/accounting/journals',
          idempotent: true,
          body: {
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
                .map(
                  (l) => {
                    'accountId': l.accountId,
                    'description': l.desc.text.trim(),
                    'debit': dStr2(dParse(l.debit.text.trim())),
                    'credit': dStr2(dParse(l.credit.text.trim())),
                  },
                )
                .toList(),
          },
        );
        _jDesc.clear();
        _jReason.clear();
        for (final l in _jLines) {
          l.desc.clear();
          l.debit.text = '0';
          l.credit.text = '0';
        }
      },
      'Balanced manual adjustment draft saved.',
    );
  }

  // -------------------------------------------------------------------------
  // Profit & Loss / Balance Sheet Generator (`image-30.png`)
  // -------------------------------------------------------------------------
  Future<void> _generateStatement() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      Map<String, dynamic> rawStmt = {};
      var fromTrialBalance = false;
      try {
        final r = await api.get(
          '/accounting/statements',
          query: {
            'statement': _stmtKind,
            'startDate': _stmtStart.text.trim(),
            'endDate': _stmtEnd.text.trim(),
            'currency': _stmtCurrency.text.trim().toUpperCase(),
          },
        );
        rawStmt = asMap(r);
      } on ApiException {
        fromTrialBalance = true;
        final tb = await api.get(
          '/reports/trial-balance',
          query: {
            'startDate': _stmtStart.text.trim(),
            'asOfDate': _stmtEnd.text.trim(),
          },
        );
        rawStmt = asMap(tb);
      }
      if (!mounted) return;

      if (!fromTrialBalance && rawStmt.isNotEmpty) {
        setState(() => _stmtResult = rawStmt);
        return;
      }

      // Derive structured P&L or Balance Sheet directly from live GL Trial Balance + COA groups
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
        rawStmt['accounts'] ?? rawStmt['rows'] ?? rawStmt['lines'] ?? rawStmt,
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

        final dr = dParse(
          row['closingDebit'] ?? row['debit'] ?? row['totalDebit'],
        );
        final cr = dParse(
          row['closingCredit'] ?? row['credit'] ?? row['totalCredit'],
        );

        if (grp == 'INCOME' || grp == 'REVENUE') {
          final net = cr - dr;
          totalIncome += net;
          incomeRows.add({'label': '$code · $name', 'amount': dStr2(net)});
        } else if (grp == 'EXPENSE') {
          final net = dr - cr;
          totalExpense += net;
          expenseRows.add({'label': '$code · $name', 'amount': dStr2(net)});
        } else if (grp == 'ASSET') {
          final net = dr - cr;
          totalAssets += net;
          assetRows.add({'label': '$code · $name', 'amount': dStr2(net)});
        } else if (grp == 'LIABILITY') {
          final net = cr - dr;
          totalLiabilities += net;
          liabilityRows.add({'label': '$code · $name', 'amount': dStr2(net)});
        } else if (grp == 'EQUITY') {
          final net = cr - dr;
          totalEquity += net;
          equityRows.add({'label': '$code · $name', 'amount': dStr2(net)});
        }
      }

      final netProfit = totalIncome - totalExpense;
      setState(() {
        _stmtResult = {
          'derivedFromGl': true,
          'kind': _stmtKind,
          'currency': _stmtCurrency.text.trim().toUpperCase(),
          'startDate': _stmtStart.text.trim(),
          'endDate': _stmtEnd.text.trim(),
          'incomeRows': incomeRows,
          'expenseRows': expenseRows,
          'assetRows': assetRows,
          'liabilityRows': liabilityRows,
          'equityRows': equityRows,
          'totalIncome': dStr2(totalIncome),
          'totalExpense': dStr2(totalExpense),
          'netProfit': dStr2(netProfit),
          'totalAssets': dStr2(totalAssets),
          'totalLiabilities': dStr2(totalLiabilities),
          'totalEquity': dStr2(totalEquity + netProfit),
        };
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------------------
  // Opening Data Template & Annual Close (`image-30.png` & `image-31.png`)
  // -------------------------------------------------------------------------
  void _populateOpeningTemplate() {
    final template = {
      'cutoverDate': todayIso(),
      'currency': 'INR',
      'ledgerBalances': [
        for (final a in _lk.accounts.take(2))
          {
            'accountId': a.id,
            'debit': '0.00',
            'credit': '0.00',
          },
      ],
      'openPartyItems': <Map<String, dynamic>>[],
      'openingStock': <Map<String, dynamic>>[],
    };
    setState(() {
      _openingJson.text = const JsonEncoder.withIndent('  ').convert(template);
    });
    toast(context, 'Opening import JSON template generated.');
  }

  Future<void> _pasteOpeningClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = (data?.text ?? '').trim();
    if (txt.isEmpty) {
      if (mounted) toast(context, 'Clipboard is empty.', error: true);
      return;
    }
    setState(() => _openingJson.text = txt);
    if (mounted) toast(context, 'JSON pasted from clipboard.');
  }

  Future<void> _stageOpeningSnapshot() async {
    if (_closeReason.text.trim().length < 10 ||
        _openingJson.text.trim().isEmpty) {
      setState(
        () => _error =
            'Enter Business reason (10+ chars) and reviewed opening-data JSON.',
      );
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
        await api.post(
          '/accounting/opening-snapshots',
          idempotent: true,
          body: {
            'reason': _closeReason.text.trim(),
            if (_closeEvidence.text.trim().isNotEmpty)
              'evidence': _closeEvidence.text.trim(),
            'payload': parsed,
          },
        );
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
      setState(
        () => _error =
            'Select Completed financial year, Contiguous next financial year, Closing JOURNAL series, Retained earnings equity account, and Business reason (10+ chars).',
      );
      return;
    }
    await _runMutation(
      (api) async {
        await api.post(
          '/accounting/annual-close',
          idempotent: true,
          body: {
            'completedFinancialYearId': _completedFyId.text.trim(),
            'nextFinancialYearId': _nextFyId.text.trim(),
            'closingDocumentSeriesId': _closingSeriesId.text.trim(),
            'retainedEarningsAccountId': _retainedEquityAcctId.text.trim(),
            'reason': _closeReason.text.trim(),
            if (_closeEvidence.text.trim().isNotEmpty)
              'evidence': _closeEvidence.text.trim(),
          },
        );
      },
      'Annual close & control snapshot prepared.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final journals = asList(_ws['journals']);
    final allPeriods = asList(_ws['financialYears'])
        .expand((fy) => asList(fy['periods']))
        .toList();
    final workflows = [
      ...asList(_ws['workflows']),
      ...asList(_ws['workflowHistory']),
      ...asList(_ws['openingSnapshots']),
      ...asList(_ws['annualCloses']),
    ];

    final q = _search.text.trim().toLowerCase();
    final fJournals = journals.where((j) {
      if (q.isEmpty) return true;
      return '${j['documentNumber'] ?? ''} ${j['description'] ?? ''} ${j['state'] ?? ''} ${j['sourceType'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fAccounts = _lk.accounts.where((a) {
      if (q.isEmpty) return true;
      return '${a.label} ${a.raw['group'] ?? ''} ${a.raw['controlType'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    // Live debit / credit balance preview for Manual Adjustment Draft
    var draftDr = Decimal.zero;
    var draftCr = Decimal.zero;
    for (final l in _jLines) {
      draftDr += dParse(l.debit.text.trim());
      draftCr += dParse(l.credit.text.trim());
    }
    final isDraftBalanced = draftDr > Decimal.zero && draftDr == draftCr;

    final wfOptions = <String, String>{
      '': 'Select...',
      for (final wf in workflows.take(200))
        if ('${wf['id'] ?? ''}'.isNotEmpty)
          '${wf['id']}':
              '${wf['workflowType'] ?? wf['kind'] ?? 'WORKFLOW'} · ${wf['state'] ?? wf['status'] ?? 'STAGED'} · ${fmtDate('${wf['createdAt'] ?? ''}')}',
    };
    final activeWfId = wfOptions.containsKey(_workflowRecordId)
        ? _workflowRecordId
        : '';
    final selectedWf = workflows
        .where((w) => '${w['id'] ?? ''}' == activeWfId && activeWfId.isNotEmpty)
        .firstOrNull;

    return LuxuryModuleScaffold(
      title: 'Double-Entry Accounting',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.menu_book_rounded,
      searchController: _search,
      searchHint: 'Search Journal No., Narration, Account or Period...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: '+ Accounting setup',
          onPressed: _openAccountingSetupSheet,
          icon: const Icon(Icons.tune_rounded, color: Pal.goldSoft),
        ),
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: [
          ('LEDGER', 'Ledger (${journals.length})'),
          ('STATEMENTS', 'P&L / Balance Sheet'),
          ('CLOSE', 'Opening & Close'),
          ('COA', 'Accounts (${_lk.accounts.length})'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Hero Header Card (`Accounting ledger` + `+ Accounting setup` — image-29.png)
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
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
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onPressed: _openAccountingSetupSheet,
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Accounting setup'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.menu_book_rounded,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Accounting ledger',
                          style: T.body(
                            16,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Entity-scoped periods, controlled document numbers, balanced journals and linked reversals.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // =================================================================
            // TAB 1: ACCOUNTING LEDGER (`image-29.png`)
            // =================================================================
            if (_tab == 'LEDGER') ...[
              SaasFormCard(
                title: 'Manual adjustment draft',
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _draftExpanded = !_draftExpanded),
                  child: Text(_draftExpanded ? 'Hide' : 'Show'),
                ),
                child: !_draftExpanded
                    ? Text(
                        'Tap Show to draft a balanced manual adjustment journal.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LookupField(
                            label: 'Open period',
                            controller: _jPeriodId,
                            options: _lk.openPeriods(),
                            hint: 'Open period',
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: LookupField(
                                  label: 'Journal series',
                                  controller: _jSeriesId,
                                  options: _lk.seriesFor(const ['JOURNAL']),
                                  hint: 'Journal series',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: DatePickField(
                                  label: 'Business date',
                                  controller: _jDate,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label: 'Adjustment description',
                            controller: _jDesc,
                            hint: 'Adjustment description',
                          ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < _jLines.length; i++) ...[
                            if (i > 0) const SizedBox(height: 10),
                            SaasSubBox(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GoldDropdown<String>(
                                          value: _jLines[i].accountId.isEmpty
                                              ? null
                                              : _jLines[i].accountId,
                                          hint: 'Account',
                                          items: _lk.accounts
                                              .map(
                                                (a) => DropdownMenuItem(
                                                  value: a.id,
                                                  child: Text(
                                                    a.label,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                          onChanged: (v) => setState(
                                            () => _jLines[i].accountId = v ?? '',
                                          ),
                                        ),
                                      ),
                                      if (_jLines.length > 2)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 17,
                                            color: Pal.err,
                                          ),
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
                                    decoration: const InputDecoration(
                                      hintText: 'Line description',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const FieldLabel('Debit'),
                                            TextField(
                                              controller: _jLines[i].debit,
                                              style: T.mono(13.5),
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                decimal: true,
                                              ),
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const FieldLabel('Credit'),
                                            TextField(
                                              controller: _jLines[i].credit,
                                              style: T.mono(13.5),
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                decimal: true,
                                              ),
                                              onChanged: (_) => setState(() {}),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: () => setState(
                                  () => _jLines.add(_JournalDraftLine()),
                                ),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('Add line'),
                              ),
                              const Spacer(),
                              Flexible(
                                child: Text(
                                  'Dr ${inr(draftDr)} · Cr ${inr(draftCr)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.mono(
                                    11.5,
                                    color: isDraftBalanced
                                        ? Pal.ok
                                        : Pal.goldDeep,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SaasField(
                            label: 'Business reason (minimum 10 characters)',
                            controller: _jReason,
                            hint: 'Business reason (minimum 10 characters)',
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          RoyalGoldButton(
                            label: 'Save balanced draft',
                            icon: Icons.send_rounded,
                            busy: _busy,
                            onPressed: _busy ? null : _saveBalancedDraft,
                          ),
                        ],
                      ),
              ),

              const SizedBox(height: 12),

              // `Period control` card (`image-29.png`)
              SaasFormCard(
                title: 'Period control',
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _periodsExpanded = !_periodsExpanded),
                  child: Text(_periodsExpanded ? 'Hide' : 'Show'),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _periodActionReason,
                      maxLines: 2,
                      style: T.body(12.8),
                    ),
                    if (_periodsExpanded && allPeriods.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final p in allPeriods)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Pal.bgTint,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Pal.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${p['code'] ?? ''} · ${p['name'] ?? ''}',
                                      style: T.body(
                                        12.8,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${fmtDate('${p['startDate'] ?? ''}')} → ${fmtDate('${p['endDate'] ?? ''}')}',
                                      style: T.body(11.5, color: Pal.muted),
                                    ),
                                  ],
                                ),
                              ),
                              StatusPill('${p['state'] ?? 'OPEN'}'),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: _busy
                                    ? null
                                    : () {
                                        final isOpen =
                                            '${p['state']}' == 'OPEN';
                                        _runMutation(
                                          (api) => api.post(
                                            '/accounting/posting-periods/${p['id']}/${isOpen ? 'close' : 'reopen'}',
                                            idempotent: true,
                                            body: {
                                              'expectedVersion': asInt(
                                                p['version'],
                                                fallback: 1,
                                              ),
                                              'reason': _periodActionReason.text
                                                  .trim(),
                                            },
                                          ),
                                          isOpen
                                              ? 'Posting period closed.'
                                              : 'Posting period reopened.',
                                        );
                                      },
                                child: Text(
                                  '${p['state']}' == 'OPEN'
                                      ? 'Close'
                                      : 'Reopen',
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Ledger Journals List (`Date / document | Description | Status | Total | Action`)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'DATE / DOCUMENT · DESCRIPTION · STATUS · TOTAL · ACTION',
                  style: T.caps(10.5),
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 92))
              else if (fJournals.isEmpty)
                const SaasEmptyBox(
                  'No accounting ledger journals recorded yet.',
                )
              else
                for (final j in fJournals)
                  LuxuryRecordCard(
                    icon: Icons.menu_book_rounded,
                    code: '${j['documentNumber'] ?? 'DRAFT JOURNAL'}',
                    status: '${j['state'] ?? 'DRAFT'}',
                    onTap: () => _openJournalActionSheet(j),
                    lines: [
                      ('Date', fmtDate('${j['businessDate'] ?? ''}')),
                      if ('${j['description'] ?? ''}'.isNotEmpty)
                        ('Description', '${j['description']}'),
                      if ('${j['sourceType'] ?? ''}'.isNotEmpty)
                        ('Source', '${j['sourceType']}'),
                    ],
                    amountLabel: 'Total',
                    amountValue: inr(j['debitTotal'] ?? j['creditTotal']),
                    actions: [
                      GoldButton(
                        label: '${j['state']}' == 'DRAFT'
                            ? 'Post Journal'
                            : ('${j['state']}' == 'POSTED'
                                ? 'Reverse / Inspect'
                                : 'Inspect Lines'),
                        compact: true,
                        onPressed: () => _openJournalActionSheet(j),
                      ),
                    ],
                  ),
            ]

            // =================================================================
            // TAB 2: PROFIT & LOSS / BALANCE SHEET (`image-30.png`)
            // =================================================================
            else if (_tab == 'STATEMENTS') ...[
              SaasFormCard(
                title: 'Profit & Loss / Balance Sheet',
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
                      busy: _busy,
                      onPressed: _busy ? null : _generateStatement,
                    ),
                    if (_stmtResult != null) ...[
                      const SizedBox(height: 14),
                      if (_stmtResult!['derivedFromGl'] == true &&
                          _stmtResult!['kind'] == 'PROFIT_AND_LOSS')
                        SaasSubBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Profit & Loss (${_stmtResult!['startDate']} → ${_stmtResult!['endDate']})',
                                style: T.body(13.5, weight: FontWeight.w700),
                              ),
                              const Divider(height: 18),
                              Text('INCOME', style: T.caps(10.5)),
                              const SizedBox(height: 4),
                              if (asList(_stmtResult!['incomeRows']).isEmpty)
                                Text(
                                  'No posted income entries in period.',
                                  style: T.body(12, color: Pal.muted),
                                )
                              else
                                for (final r
                                    in asList(_stmtResult!['incomeRows']))
                                  KVRow('${r['label']}', inr(r['amount'])),
                              KVRow(
                                'Total Income',
                                inr(_stmtResult!['totalIncome']),
                                bold: true,
                              ),
                              const Divider(height: 18),
                              Text('EXPENSES', style: T.caps(10.5)),
                              const SizedBox(height: 4),
                              if (asList(_stmtResult!['expenseRows']).isEmpty)
                                Text(
                                  'No posted expense entries in period.',
                                  style: T.body(12, color: Pal.muted),
                                )
                              else
                                for (final r
                                    in asList(_stmtResult!['expenseRows']))
                                  KVRow('${r['label']}', inr(r['amount'])),
                              KVRow(
                                'Total Expenses',
                                inr(_stmtResult!['totalExpense']),
                                bold: true,
                              ),
                              const Divider(height: 18),
                              KVRow(
                                'Net Profit / (Loss)',
                                inr(_stmtResult!['netProfit']),
                                bold: true,
                              ),
                            ],
                          ),
                        )
                      else if (_stmtResult!['derivedFromGl'] == true &&
                          _stmtResult!['kind'] == 'BALANCE_SHEET')
                        SaasSubBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Balance Sheet (as of ${_stmtResult!['endDate']})',
                                style: T.body(13.5, weight: FontWeight.w700),
                              ),
                              const Divider(height: 18),
                              Text('ASSETS', style: T.caps(10.5)),
                              const SizedBox(height: 4),
                              for (final r in asList(_stmtResult!['assetRows']))
                                KVRow('${r['label']}', inr(r['amount'])),
                              KVRow(
                                'Total Assets',
                                inr(_stmtResult!['totalAssets']),
                                bold: true,
                              ),
                              const Divider(height: 18),
                              Text('LIABILITIES', style: T.caps(10.5)),
                              const SizedBox(height: 4),
                              for (final r
                                  in asList(_stmtResult!['liabilityRows']))
                                KVRow('${r['label']}', inr(r['amount'])),
                              KVRow(
                                'Total Liabilities',
                                inr(_stmtResult!['totalLiabilities']),
                                bold: true,
                              ),
                              const Divider(height: 18),
                              Text('EQUITY & SURPLUS', style: T.caps(10.5)),
                              const SizedBox(height: 4),
                              for (final r
                                  in asList(_stmtResult!['equityRows']))
                                KVRow('${r['label']}', inr(r['amount'])),
                              KVRow(
                                'Current Period Net Surplus',
                                inr(_stmtResult!['netProfit']),
                              ),
                              KVRow(
                                'Total Equity & Surplus',
                                inr(_stmtResult!['totalEquity']),
                                bold: true,
                              ),
                            ],
                          ),
                        )
                      else
                        SaasSubBox(
                          child: Column(
                            children: [
                              for (final a in asList(
                                _stmtResult!['accounts'] ??
                                    _stmtResult!['lines'] ??
                                    _stmtResult!['sections'],
                              ))
                                KVRow(
                                  '${a['code'] ?? ''} ${a['name'] ?? a['label'] ?? ''}'
                                      .trim(),
                                  inr(
                                    a['balance'] ??
                                        a['amount'] ??
                                        a['closingDebit'] ??
                                        '0.00',
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ]

            // =================================================================
            // TAB 3: OPENING DATA AND ANNUAL CLOSE (`image-30.png` & `image-31.png`)
            // =================================================================
            else if (_tab == 'CLOSE') ...[
              SaasFormCard(
                title: 'Opening data and annual close',
                subtitle:
                    'Entity-wide staged imports and year controls. Source snapshots are immutable; resolve exceptions in a new revision. All commands require an authorized role and audited reason.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SaasField(
                      label: 'Business reason',
                      controller: _closeReason,
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Accountant/source-control evidence',
                      controller: _closeEvidence,
                    ),
                    const SizedBox(height: 14),

                    // `Stage opening data` sub-card (`image-30.png` & `image-31.png`)
                    SaasSubBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Stage opening data',
                            style: T.body(14, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Use reviewed opening-data JSON with scoped account, branch, party and stock mappings. The entity must have no existing ledger, open items or stock. This imports balances and lineage without fake purchases.',
                            style: T.body(11.8, color: Pal.muted),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: _populateOpeningTemplate,
                                child: const Text('Create import template'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _pasteOpeningClipboard,
                                icon: const Icon(
                                  Icons.content_paste_rounded,
                                  size: 16,
                                ),
                                label: const Text('Paste JSON'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _openingJson,
                            maxLines: 6,
                            style: T.mono(12),
                            decoration: const InputDecoration(
                              hintText: '{ "cutoverDate": "...", ... }',
                            ),
                          ),
                          const SizedBox(height: 12),
                          RoyalGoldButton(
                            label: 'Validate & stage opening snapshot',
                            busy: _busy,
                            onPressed: _busy ? null : _stageOpeningSnapshot,
                          ),
                          const SizedBox(height: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(
                              () => _showMappingRefs = !_showMappingRefs,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    _showMappingRefs
                                        ? Icons.arrow_drop_down_rounded
                                        : Icons.arrow_right_rounded,
                                    size: 20,
                                    color: Pal.ink,
                                  ),
                                  const SizedBox(width: 2),
                                  Expanded(
                                    child: Text(
                                      'Account and master mapping references',
                                      style: T.body(
                                        12.2,
                                        color: Pal.ink,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_showMappingRefs) ...[
                            const Divider(height: 16),
                            Text('GL ACCOUNTS', style: T.caps(10)),
                            for (final a in _lk.accounts)
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: a.id));
                                  toast(context, 'Copied account UUID');
                                },
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${a.label} → ${a.id}',
                                    style: T.mono(11, color: Pal.muted),
                                  ),
                                ),
                              ),
                            if (_lk.branches.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('BRANCHES', style: T.caps(10)),
                              for (final b in _lk.branches)
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: b.id),
                                    );
                                    toast(context, 'Copied branch UUID');
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${b.label} → ${b.id}',
                                      style: T.mono(11, color: Pal.muted),
                                    ),
                                  ),
                                ),
                            ],
                            if (_lk.locations.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text('CUSTODY LOCATIONS', style: T.caps(10)),
                              for (final l in _lk.locations)
                                InkWell(
                                  onTap: () {
                                    Clipboard.setData(
                                      ClipboardData(text: l.id),
                                    );
                                    toast(context, 'Copied location UUID');
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '${l.label} → ${l.id}',
                                      style: T.mono(11, color: Pal.muted),
                                    ),
                                  ),
                                ),
                            ],
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // `Prepare annual close` sub-card (`image-31.png`)
                    SaasSubBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Prepare annual close',
                            style: T.body(14, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Completed financial year',
                            controller: _completedFyId,
                            options: _lk.financialYears,
                            hint: 'Select...',
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Contiguous next financial year',
                            controller: _nextFyId,
                            options: _lk.financialYears,
                            hint: 'Select...',
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Closing JOURNAL series',
                            controller: _closingSeriesId,
                            options: _lk.seriesFor(const ['JOURNAL']),
                            hint: 'Select...',
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Retained earnings equity account',
                            controller: _retainedEquityAcctId,
                            options: _lk.accountsByControl(const ['EQUITY']),
                            hint: 'Select...',
                          ),
                          const SizedBox(height: 12),
                          RoyalGoldButton(
                            label: 'Prepare close and control snapshot',
                            busy: _busy,
                            onPressed: _busy ? null : _prepareAnnualClose,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Profit/loss transfers to selected equity. Asset/liability balances continue through the cumulative ledger; no duplicate next-year opening journal is created.',
                            style: T.body(11.6, color: Pal.muted),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // `Workflow history · latest 200` (`image-31.png`)
                    SaasDropdown(
                      label: 'Workflow history · latest 200',
                      value: activeWfId,
                      options: wfOptions,
                      onChanged: (v) => setState(() => _workflowRecordId = v),
                    ),
                    if (selectedWf != null) ...[
                      const SizedBox(height: 10),
                      SaasSubBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${selectedWf['workflowType'] ?? selectedWf['kind'] ?? 'Workflow'} · Rev ${selectedWf['revision'] ?? 1}',
                                    style: T.body(
                                      13,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                StatusPill(
                                  '${selectedWf['state'] ?? selectedWf['status'] ?? 'STAGED'}',
                                ),
                              ],
                            ),
                            if ('${selectedWf['reason'] ?? ''}'.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${selectedWf['reason']}',
                                style: T.body(12, color: Pal.muted),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                GoldButton(
                                  label: 'Post / Execute Staged Workflow',
                                  compact: true,
                                  busy: _busy,
                                  onPressed: () {
                                    final isClose =
                                        '${selectedWf['workflowType'] ?? selectedWf['kind'] ?? ''}'
                                            .toUpperCase()
                                            .contains('CLOSE');
                                    _runMutation(
                                      (api) => api.post(
                                        isClose
                                            ? '/accounting/annual-close/${selectedWf['id']}/post'
                                            : '/accounting/opening-snapshots/${selectedWf['id']}/post',
                                        idempotent: true,
                                        body: {
                                          'expectedVersion': asInt(
                                            selectedWf['version'],
                                            fallback: 1,
                                          ),
                                          'reason': _closeReason.text
                                                  .trim()
                                                  .isNotEmpty
                                              ? _closeReason.text.trim()
                                              : _periodActionReason.text.trim(),
                                        },
                                      ),
                                      'Staged workflow posted.',
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ]

            // =================================================================
            // TAB 4: CHART OF ACCOUNTS & DOCUMENT SERIES
            // =================================================================
            else ...[
              if (_loading)
                const Panel(child: Skeleton(height: 92))
              else if (fAccounts.isEmpty)
                const SaasEmptyBox(
                  'No GL accounts configured yet. Tap + Accounting setup to add accounts.',
                )
              else
                for (final a in fAccounts)
                  LuxuryRecordCard(
                    icon: Icons.account_balance_outlined,
                    code: a.label,
                    status: '${a.raw['group'] ?? 'ACCOUNT'}',
                    lines: [
                      ('Control Type', '${a.raw['controlType'] ?? 'NONE'}'),
                      ('Currency', '${a.raw['currency'] ?? 'INR'}'),
                    ],
                    amountLabel: 'Group',
                    amountValue: '${a.raw['group'] ?? 'GL'}',
                  ),
            ],
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
  final _search = TextEditingController();
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
      _search, _periodId, _docSeriesId, _journalSeriesId, _partyId, _instrumentAcctId,
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

    final q = _search.text.trim().toLowerCase();
    final fOpen = openItems.where((o) {
      if (q.isEmpty) return true;
      return '${o['documentNumber'] ?? ''} ${asMap(o['party'])['displayName'] ?? ''} ${o['kind'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fSettlements = settlements.where((s) {
      if (q.isEmpty) return true;
      return '${s['documentNumber'] ?? ''} ${asMap(s['party'])['displayName'] ?? ''} ${s['method'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fClearings = clearings.where((c) {
      if (q.isEmpty) return true;
      return '${c['provider'] ?? ''} ${c['providerBatchRef'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Settlements & Cashup',
      icon: Icons.account_balance_wallet_outlined,
      searchController: _search,
      searchHint: 'Search by Party, Invoice or Settlement No...',
      onSearchChanged: (_) => setState(() {}),
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
          _showForm = false;
        }),
        tabs: [
          ('OPEN_ITEMS', 'Open Items (${openItems.length})'),
          ('RECEIPTS', 'Receipts (${settlements.length})'),
          ('DISBURSEMENTS', 'Disbursements'),
          ('REFUNDS', 'Refunds'),
          ('CLEARINGS', 'Clearings (${clearings.length})'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'Post Settlement / Receipt',
        onPressed: () => setState(() {
          if (_tab == 'OPEN_ITEMS') {
            _tab = 'RECEIPTS';
            _showForm = true;
          } else {
            _showForm = !_showForm;
          }
        }),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],

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

            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tab == 'OPEN_ITEMS')
              fOpen.isEmpty
                  ? const SaasEmptyBox('No open receivable or payable items.')
                  : Column(
                      children: [
                        for (final o in fOpen)
                          LuxuryRecordCard(
                            icon: Icons.receipt_long_outlined,
                            code: '${o['documentNumber'] ?? shortId('${o['id']}')}',
                            status: '${o['state'] ?? 'OPEN'}',
                            lines: [
                              ('Party', '${asMap(o['party'])['displayName'] ?? 'Counterparty'}'),
                              ('Date / Kind', '${fmtDate('${o['documentDate'] ?? ''}')} · ${o['kind'] ?? ''}'),
                              ('Original / Settled', '${inr(o['originalAmount'])} / ${inr(o['settledAmount'])}'),
                            ],
                            amountLabel: 'Open Amount',
                            amountValue: inr(o['openAmount']),
                          ),
                      ],
                    )
            else if (_tab == 'CLEARINGS')
              fClearings.isEmpty
                  ? const SaasEmptyBox('No provider clearings recorded yet. Tap + to post a clearing batch.')
                  : Column(
                      children: [
                        for (final c in fClearings)
                          LuxuryRecordCard(
                            icon: Icons.sync_alt_rounded,
                            code: '${c['provider'] ?? 'GATEWAY'} · ${c['providerBatchRef'] ?? shortId('${c['id']}')}',
                            status: 'POSTED',
                            lines: [
                              ('Settlement Date', fmtDate('${c['settlementDate'] ?? ''}')),
                              ('Gateway Fee', inr(c['feeAmount'])),
                            ],
                            amountLabel: 'Gross',
                            amountValue: inr(c['grossAmount'] ?? c['amount'] ?? '0.00'),
                          ),
                      ],
                    )
            else
              fSettlements.isEmpty
                  ? const SaasEmptyBox('No settlement documents recorded yet. Tap + to post a settlement.')
                  : Column(
                      children: [
                        for (final s in fSettlements)
                          LuxuryRecordCard(
                            icon: Icons.payments_outlined,
                            code: '${s['documentNumber'] ?? shortId('${s['id']}')}',
                            status: '${s['method'] ?? s['state'] ?? 'POSTED'}',
                            lines: [
                              ('Party', '${asMap(s['party'])['displayName'] ?? 'Counterparty'}'),
                              ('Date', fmtDate('${s['settlementDate'] ?? ''}')),
                            ],
                            amountLabel: 'Amount',
                            amountValue: inr(s['amount']),
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
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _showImport = false;
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
      _search, _bankAcctId, _statementId, _startDate, _endDate,
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
      setState(() => _showImport = false);
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
    final q = _search.text.trim().toLowerCase();
    bool isRecon(Map<String, dynamic> s) {
      final st = '${s['state'] ?? s['status'] ?? ''}'.toUpperCase();
      return st == 'RECONCILED' || st == 'SIGNED_OFF' || st == 'CLOSED';
    }

    final openCnt = _statements.where((s) => !isRecon(s)).length;
    final recCnt = _statements.where(isRecon).length;
    final filtered = _statements.where((s) {
      if (_filter == 'OPEN' && isRecon(s)) return false;
      if (_filter == 'RECONCILED' && !isRecon(s)) return false;
      if (q.isEmpty) return true;
      return '${s['externalStatementId'] ?? ''} ${s['id'] ?? ''} ${s['currency'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Banking & Reconciliation',
      icon: Icons.account_balance_rounded,
      searchController: _search,
      searchHint: 'Search by Statement ID / Reference...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${_statements.length})'),
          ('OPEN', 'Open ($openCnt)'),
          ('RECONCILED', 'Reconciled ($recCnt)'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showImport ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'Import Bank Statement CSV',
        onPressed: () => setState(() => _showImport = !_showImport),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            if (_showImport) ...[
              SaasFormCard(
                title: 'Import normalized bank CSV',
                subtitle:
                    'Required columns: transaction_date, direction, amount, description. Optional: value_date, reference, bank_transaction_id.',
                icon: Icons.upload_rounded,
                trailing: TextButton(
                  onPressed: () => setState(() => _showImport = false),
                  child: const Text('Close'),
                ),
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
                    GoldButton(
                      label: _busy ? 'Importing…' : 'Import Statement',
                      busy: _busy,
                      onPressed: _importStatement,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              const SaasEmptyBox('No bank statements found. Tap + to import a normalized bank CSV.')
            else
              for (final s in filtered)
                LuxuryRecordCard(
                  icon: Icons.account_balance_rounded,
                  code: '${s['externalStatementId'] ?? shortId('${s['id']}')}',
                  status: '${s['state'] ?? s['status'] ?? 'IMPORTED'}',
                  lines: [
                    ('Period', '${fmtDate('${s['startDate'] ?? ''}')} → ${fmtDate('${s['endDate'] ?? ''}')}'),
                    ('Opening', inr(s['openingBalance'])),
                  ],
                  amountLabel: 'Closing',
                  amountValue: inr(s['closingBalance']),
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
  final _search = TextEditingController();
  String _tab = 'OVERVIEW';
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
    _search.dispose();
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

    final q = _search.text.trim().toLowerCase();
    final fEntities = entities.where((e) {
      if (q.isEmpty) return true;
      return '${e['legalName'] ?? ''} ${e['name'] ?? ''} ${e['currency'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fElims = eliminations.where((el) {
      if (q.isEmpty) return true;
      return '${el['description'] ?? ''} ${el['reference'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Consolidated Chain Analytics',
      icon: Icons.hub_outlined,
      searchController: _search,
      searchHint: 'Search by Legal Entity or Elimination Ref...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: [
          ('OVERVIEW', 'Overview'),
          ('ENTITIES', 'Entities (${entities.length})'),
          ('ELIMINATIONS', 'Eliminations (${eliminations.length})'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
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
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_tab == 'ENTITIES') ...[
              if (fEntities.isEmpty)
                const SaasEmptyBox('No legal-entity comparison rows returned.')
              else
                for (final e in fEntities)
                  LuxuryRecordCard(
                    icon: Icons.domain_rounded,
                    code: '${e['legalName'] ?? e['name'] ?? 'Entity'}',
                    status: '${e['currency'] ?? 'INR'}',
                    lines: [
                      ('Authorized Branches', '${e['authorizedBranchCount'] ?? asList(e['branches']).length} branch(es)'),
                      if (e['revenue'] != null) ('Revenue', inr(e['revenue'])),
                    ],
                    amountLabel: 'Profit',
                    amountValue: inr(e['profit'] ?? '0.00'),
                  ),
            ] else if (_tab == 'ELIMINATIONS') ...[
              if (fElims.isEmpty)
                const SaasEmptyBox('No posted inter-entity elimination entries in the selected range.')
              else
                for (final el in fElims)
                  LuxuryRecordCard(
                    icon: Icons.compare_arrows_rounded,
                    code: '${el['reference'] ?? el['description'] ?? 'ELIMINATION'}',
                    status: 'BALANCED',
                    lines: [
                      if ('${el['description'] ?? ''}'.isNotEmpty) ('Description', '${el['description']}'),
                    ],
                    amountLabel: 'Eliminated',
                    amountValue: inr(el['amount']),
                  ),
            ] else ...[
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
                    label: 'REPORTED PROFIT',
                    value: inr('${reported['profit'] ?? _data['reportedProfit'] ?? '0.00'}'),
                  ),
                  (
                    label: 'CONSOLIDATED PROFIT',
                    value: inr('${consolidated['profit'] ?? _data['consolidatedProfit'] ?? '0.00'}'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LuxuryRecordCard(
                icon: Icons.assessment_outlined,
                code: 'Reported Ledger Totals',
                status: 'REPORTED',
                lines: [
                  ('Revenue', inr(reported['revenue'] ?? '0.00')),
                  ('Expense', inr(reported['expense'] ?? '0.00')),
                ],
                amountLabel: 'Net Profit',
                amountValue: inr(reported['profit'] ?? _data['reportedProfit'] ?? '0.00'),
              ),
              LuxuryRecordCard(
                icon: Icons.hub_outlined,
                code: 'After Consolidation Eliminations',
                status: balanced ? 'BALANCED' : 'VARIANCE',
                lines: [
                  ('Consolidated Revenue', inr(consolidated['revenue'] ?? '0.00')),
                  ('Consolidated Expense', inr(consolidated['expense'] ?? '0.00')),
                  for (final p in icPairs)
                    ('${p['entityPair'] ?? 'Pair'}', 'AR ${inr(p['receivable'])} / AP ${inr(p['payable'])}'),
                ],
                amountLabel: 'Consolidated Profit',
                amountValue: inr(consolidated['profit'] ?? _data['consolidatedProfit'] ?? '0.00'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef ConsolidatedAnalyticsScreen = ConsolidatedChainAnalyticsScreen;
