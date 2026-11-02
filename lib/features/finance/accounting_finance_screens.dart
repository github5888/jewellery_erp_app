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
      final tb = await api.get(
        '/reports/trial-balance',
        query: {
          'startDate': _stmtStart.text.trim(),
          'asOfDate': _stmtEnd.text.trim(),
        },
      );
      final rawStmt = asMap(tb);
      if (!mounted) return;

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
    final auth = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = auth.tenantName.trim();
    final branchName = auth.branchName.trim();
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
// 2. SETTLEMENTS & CASHUP (`/payments`) — `image-65.png`..`image-68.png`
// ---------------------------------------------------------------------------

class SettlementsCashupScreen extends StatefulWidget {
  const SettlementsCashupScreen({super.key});
  @override
  State<SettlementsCashupScreen> createState() =>
      _SettlementsCashupScreenState();
}

class _ClearingLineDraft {
  const _ClearingLineDraft({
    required this.settlementDocumentId,
    required this.label,
    required this.grossAmount,
  });
  final String settlementDocumentId;
  final String label;
  final String grossAmount;
}

class _SettlementsCashupScreenState extends State<SettlementsCashupScreen> {
  final _search = TextEditingController();
  // 'OPEN_ITEMS' | 'RECEIPTS' | 'DISBURSEMENTS' | 'REFUNDS' | 'CLEARINGS'
  String _tab = 'OPEN_ITEMS';
  // null | 'RECEIPT' | 'DISBURSEMENT' | 'REFUND'
  String? _activeForm;

  Map<String, dynamic> _ws = const {};
  List<Map<String, dynamic>> _salesInvoices = const [];
  List<Map<String, dynamic>> _salesCreditNotes = const [];
  WorkspaceLookup _lk = WorkspaceLookup();

  bool _loading = true;
  bool _busy = false;
  bool _showPostingGov = false;
  String? _error;

  // Shared Posting Governance Defaults (auto-populated from `/accounting/workspace`)
  final _periodCtrl = TextEditingController();
  final _docSeriesCtrl = TextEditingController();
  final _jrnSeriesCtrl = TextEditingController();
  final _govReasonCtrl = TextEditingController();

  // 1. `Post Customer Receipt` (`image-65.png`)
  final _rcptInvoiceOrItemCtrl = TextEditingController();
  final _rcptPartyIdCtrl = TextEditingController();
  final _rcptOpenItemIdCtrl = TextEditingController();
  final _rcptClearingAcctCtrl = TextEditingController();
  String _rcptMethod = 'UPI';
  final _rcptAmountCtrl = TextEditingController();
  final _rcptRefCtrl = TextEditingController();
  final _rcptOpenBalCtrl = TextEditingController();

  // 2. `Post Supplier Disbursement` (`image-66.png`)
  final _disbSupplierCtrl = TextEditingController();
  final _disbInstrumentCtrl = TextEditingController();
  String _disbMethod = 'BANK_TRANSFER';
  final _disbAmountCtrl = TextEditingController();
  final _disbRefCtrl = TextEditingController();
  final _disbOpenItemCtrl = TextEditingController();

  // 3. `Post Customer Refund` (`image-67.png`)
  final _refCustomerCtrl = TextEditingController();
  final _refCreditNoteCtrl = TextEditingController();
  final _refInstrumentCtrl = TextEditingController();
  final _refAmountCtrl = TextEditingController();
  final _refRefCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _search,
      _periodCtrl,
      _docSeriesCtrl,
      _jrnSeriesCtrl,
      _govReasonCtrl,
      _rcptInvoiceOrItemCtrl,
      _rcptPartyIdCtrl,
      _rcptOpenItemIdCtrl,
      _rcptClearingAcctCtrl,
      _rcptAmountCtrl,
      _rcptRefCtrl,
      _rcptOpenBalCtrl,
      _disbSupplierCtrl,
      _disbInstrumentCtrl,
      _disbAmountCtrl,
      _disbRefCtrl,
      _disbOpenItemCtrl,
      _refCustomerCtrl,
      _refCreditNoteCtrl,
      _refInstrumentCtrl,
      _refAmountCtrl,
      _refRefCtrl,
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
      final res = await Future.wait<dynamic>([
        api.get('/payments'),
        api.get('/sales', quiet: true).catchError((_) => const <String, dynamic>{}),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final ws = asMap(res[0]);
      final salesMap = asMap(res[1]);
      final lk = res[2] as WorkspaceLookup;

      if (_periodCtrl.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _periodCtrl.text = lk.openPeriods().first.id;
      }
      if (_docSeriesCtrl.text.isEmpty) {
        final s = lk.seriesFor(
          const ['SETTLEMENT', 'RECEIPT', 'PAYMENT', 'DISBURSEMENT'],
        );
        if (s.isNotEmpty) {
          _docSeriesCtrl.text = s.first.id;
        } else if (lk.series.isNotEmpty) {
          _docSeriesCtrl.text = lk.series.first.id;
        }
      }
      if (_jrnSeriesCtrl.text.isEmpty) {
        final j = lk.seriesFor(const ['JOURNAL']);
        if (j.isNotEmpty) _jrnSeriesCtrl.text = j.first.id;
      }

      final clearingAccts = lk.accountsByControl(
        const ['PAYMENT_CLEARING', 'BANK', 'CASH'],
      );
      if (_rcptClearingAcctCtrl.text.isEmpty && clearingAccts.isNotEmpty) {
        _rcptClearingAcctCtrl.text = clearingAccts.first.id;
      }
      if (_disbInstrumentCtrl.text.isEmpty && clearingAccts.isNotEmpty) {
        _disbInstrumentCtrl.text = clearingAccts.first.id;
      }
      if (_refInstrumentCtrl.text.isEmpty && clearingAccts.isNotEmpty) {
        _refInstrumentCtrl.text = clearingAccts.first.id;
      }

      setState(() {
        _ws = ws;
        _salesInvoices = asList(
          salesMap,
          keys: const ['invoices', 'salesInvoices'],
        );
        _salesCreditNotes = asList(salesMap, keys: const ['creditNotes']);
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesSettlementTab(Map<String, dynamic> s, String tab) {
    final kind =
        '${s['kind'] ?? s['settlementKind'] ?? s['type'] ?? s['direction'] ?? ''}'
            .toUpperCase();
    if (tab == 'RECEIPTS') {
      if (kind.isEmpty) return true;
      return kind.contains('RECEIPT') ||
          kind.contains('INBOUND') ||
          kind.contains('CUSTOMER_RECEIPT') ||
          kind == 'IN';
    }
    if (tab == 'DISBURSEMENTS') {
      return kind.contains('DISBURSE') ||
          kind.contains('SUPPLIER') ||
          kind.contains('OUTBOUND') ||
          kind.contains('PAYOUT') ||
          kind == 'OUT';
    }
    if (tab == 'REFUNDS') {
      return kind.contains('REFUND');
    }
    return true;
  }

  List<LookupOption> _customerInvoiceOptions() {
    final opts = <LookupOption>[];
    final seenIds = <String>{};
    for (final o in asList(_ws['openItems'])) {
      final kind = '${o['kind'] ?? o['openItemKind'] ?? ''}'.toUpperCase();
      if (kind.contains('PAYABLE') || kind.contains('SUPPLIER')) continue;
      final id = '${o['id'] ?? ''}';
      if (id.isEmpty || !seenIds.add(id)) continue;
      final partyName =
          '${asMap(o['party'])['displayName'] ?? o['partyName'] ?? 'Customer'}';
      final openAmt = '${o['openAmount'] ?? o['originalAmount'] ?? '0.00'}';
      opts.add(
        LookupOption(
          id: id,
          label:
              '${o['documentNumber'] ?? shortId(id)} · $partyName · Open ${inr(openAmt)}',
          raw: {...o, '_isOpenItem': true},
        ),
      );
    }
    for (final inv in _salesInvoices) {
      if ('${inv['state']}'.toUpperCase() != 'POSTED') continue;
      final id = '${inv['id'] ?? ''}';
      if (id.isEmpty || !seenIds.add(id)) continue;
      final custName =
          '${asMap(inv['customer'])['displayName'] ?? inv['customerName'] ?? 'Customer'}';
      final openAmt =
          '${inv['outstandingAmount'] ?? inv['openAmount'] ?? inv['totalAmount'] ?? '0.00'}';
      opts.add(
        LookupOption(
          id: id,
          label:
              '${inv['documentNumber'] ?? shortId(id)} · $custName · ${inr(openAmt)}',
          raw: {...inv, '_isSalesInvoice': true},
        ),
      );
    }
    return opts;
  }

  List<LookupOption> _supplierOpenItemOptions() {
    return asList(_ws['openItems'])
        .where((o) {
          final kind = '${o['kind'] ?? o['openItemKind'] ?? ''}'.toUpperCase();
          return kind.isEmpty ||
              kind.contains('PAYABLE') ||
              kind.contains('SUPPLIER') ||
              kind.contains('AP');
        })
        .map(
          (o) => LookupOption(
            id: '${o['id']}',
            label:
                '${o['documentNumber'] ?? shortId('${o['id']}')} · ${asMap(o['party'])['displayName'] ?? ''} · Open ${inr(o['openAmount'])}',
            raw: o,
          ),
        )
        .toList();
  }

  List<LookupOption> _creditNoteAndRefundItemOptions() {
    final opts = <LookupOption>[];
    final seen = <String>{};
    for (final o in asList(_ws['openItems'])) {
      final kind = '${o['kind'] ?? o['openItemKind'] ?? ''}'.toUpperCase();
      if (kind.contains('CREDIT') ||
          kind.contains('ADVANCE') ||
          kind.contains('REFUND') ||
          !kind.contains('PAYABLE')) {
        final id = '${o['id'] ?? ''}';
        if (id.isNotEmpty && seen.add(id)) {
          opts.add(
            LookupOption(
              id: id,
              label:
                  '${o['documentNumber'] ?? shortId(id)} · ${asMap(o['party'])['displayName'] ?? 'Customer'} · ${inr(o['openAmount'])}',
              raw: {...o, '_isOpenItem': true},
            ),
          );
        }
      }
    }
    for (final cn in _salesCreditNotes) {
      final id = '${cn['id'] ?? ''}';
      if (id.isNotEmpty && seen.add(id)) {
        opts.add(
          LookupOption(
            id: id,
            label:
                '${cn['documentNumber'] ?? shortId(id)} · ${asMap(cn['customer'])['displayName'] ?? 'Customer'} · ${inr(cn['totalAmount'])}',
            raw: {...cn, '_isCreditNote': true},
          ),
        );
      }
    }
    return opts;
  }

  bool _ensurePostingGovernance(String fallbackReason) {
    if (_periodCtrl.text.trim().isEmpty ||
        _docSeriesCtrl.text.trim().isEmpty ||
        _jrnSeriesCtrl.text.trim().isEmpty) {
      setState(() {
        _showPostingGov = true;
        _error =
            'Select Posting Period, Settlement Document Series, and Journal Series before posting.';
      });
      return false;
    }
    if (_govReasonCtrl.text.trim().isEmpty) {
      _govReasonCtrl.text = fallbackReason;
    }
    return true;
  }

  Future<void> _submitCustomerReceipt() async {
    final clearingAcct = _rcptClearingAcctCtrl.text.trim();
    final amt = _rcptAmountCtrl.text.trim();
    final ref = _rcptRefCtrl.text.trim();

    var partyId = _rcptPartyIdCtrl.text.trim();
    var openItemId = _rcptOpenItemIdCtrl.text.trim();
    final pickedId = _rcptInvoiceOrItemCtrl.text.trim();

    if (pickedId.isNotEmpty) {
      final match = _customerInvoiceOptions()
          .where((o) => o.id == pickedId)
          .firstOrNull;
      if (match != null) {
        final raw = match.raw;
        partyId = partyId.isNotEmpty
            ? partyId
            : '${raw['partyId'] ?? raw['customerPartyId'] ?? asMap(raw['party'])['id'] ?? asMap(raw['customer'])['id'] ?? ''}';
        if (raw['_isOpenItem'] == true) {
          openItemId = openItemId.isNotEmpty ? openItemId : match.id;
        } else {
          final docNum = '${raw['documentNumber'] ?? ''}'.trim();
          for (final oi in asList(_ws['openItems'])) {
            if ('${oi['sourceId'] ?? ''}' == match.id ||
                (docNum.isNotEmpty && '${oi['documentNumber'] ?? ''}' == docNum)) {
              openItemId = '${oi['id']}';
              break;
            }
          }
        }
      }
    }

    if (partyId.isEmpty || clearingAcct.isEmpty || !isValidAmount(amt)) {
      setState(
        () => _error =
            'Select Customer Invoice (or Customer Party), Payment Clearing Account, and enter a valid Amount INR.',
      );
      return;
    }
    if ((_rcptMethod == 'UPI' || _rcptMethod == 'CARD') && ref.isEmpty) {
      setState(
        () => _error =
            'Payment Reference / UTR is required when Method is $_rcptMethod.',
      );
      return;
    }
    if (!_ensurePostingGovernance(
      'Recorded customer payment receipt against showroom invoice.',
    )) {
      return;
    }

    final normAmt = normAmount(amt);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/payments/customer-receipts',
        idempotent: true,
        body: {
          'partyId': partyId,
          'method': _rcptMethod,
          'settlementDate': todayIso(),
          'currency': 'INR',
          'amount': normAmt,
          'instrumentAccountId': clearingAcct,
          if (_rcptMethod == 'UPI' || _rcptMethod == 'CARD')
            'providerReference': ref
          else if (ref.isNotEmpty)
            'paymentReference': ref,
          'postingPeriodId': _periodCtrl.text.trim(),
          'documentSeriesId': _docSeriesCtrl.text.trim(),
          'journalSeriesId': _jrnSeriesCtrl.text.trim(),
          'allocations': [
            if (openItemId.isNotEmpty)
              {
                'openItemId': openItemId,
                'amount': normAmt,
              },
          ],
          'reason': _govReasonCtrl.text.trim().length >= 10
              ? _govReasonCtrl.text.trim()
              : 'Recorded customer payment receipt against showroom invoice.',
        },
      );
      if (!mounted) return;
      _rcptInvoiceOrItemCtrl.clear();
      _rcptPartyIdCtrl.clear();
      _rcptOpenItemIdCtrl.clear();
      _rcptAmountCtrl.clear();
      _rcptRefCtrl.clear();
      _rcptOpenBalCtrl.clear();
      setState(() => _activeForm = null);
      toast(context, 'Customer receipt posted.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitSupplierDisbursement() async {
    final partyId = _disbSupplierCtrl.text.trim();
    final instrId = _disbInstrumentCtrl.text.trim();
    final amt = _disbAmountCtrl.text.trim();
    final ref = _disbRefCtrl.text.trim();
    final openItemId = _disbOpenItemCtrl.text.trim();

    if (partyId.isEmpty || instrId.isEmpty || !isValidAmount(amt)) {
      setState(
        () => _error =
            'Provide Supplier Party UUID, Instrument / Bank Account UUID, and valid Amount INR.',
      );
      return;
    }
    if ((_disbMethod == 'UPI' || _disbMethod == 'CARD') && ref.isEmpty) {
      setState(
        () => _error =
            'Payment Reference / UTR is required when Method is $_disbMethod.',
      );
      return;
    }
    if (!_ensurePostingGovernance(
      'Posted outbound supplier payment disbursement.',
    )) {
      return;
    }

    final normAmt = normAmount(amt);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/payments/supplier-disbursements',
        idempotent: true,
        body: {
          'partyId': partyId,
          'method': _disbMethod,
          'settlementDate': todayIso(),
          'currency': 'INR',
          'amount': normAmt,
          'instrumentAccountId': instrId,
          if (_disbMethod == 'UPI' || _disbMethod == 'CARD')
            'providerReference': ref
          else if (ref.isNotEmpty)
            'paymentReference': ref,
          'postingPeriodId': _periodCtrl.text.trim(),
          'documentSeriesId': _docSeriesCtrl.text.trim(),
          'journalSeriesId': _jrnSeriesCtrl.text.trim(),
          'allocations': [
            if (openItemId.isNotEmpty)
              {
                'openItemId': openItemId,
                'amount': normAmt,
              },
          ],
          'reason': _govReasonCtrl.text.trim().length >= 10
              ? _govReasonCtrl.text.trim()
              : 'Posted outbound supplier payment disbursement.',
        },
      );
      if (!mounted) return;
      _disbSupplierCtrl.clear();
      _disbAmountCtrl.clear();
      _disbRefCtrl.clear();
      _disbOpenItemCtrl.clear();
      setState(() => _activeForm = null);
      toast(context, 'Supplier disbursement posted.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitCustomerRefund() async {
    var partyId = _refCustomerCtrl.text.trim();
    final cnOrItemId = _refCreditNoteCtrl.text.trim();
    final instrId = _refInstrumentCtrl.text.trim();
    final amt = _refAmountCtrl.text.trim();
    final ref = _refRefCtrl.text.trim();

    var resolvedOpenItemId = cnOrItemId;
    if (cnOrItemId.isNotEmpty) {
      final match = _creditNoteAndRefundItemOptions()
          .where((o) => o.id == cnOrItemId)
          .firstOrNull;
      if (match != null) {
        final raw = match.raw;
        if (partyId.isEmpty) {
          partyId =
              '${raw['partyId'] ?? raw['customerPartyId'] ?? asMap(raw['party'])['id'] ?? asMap(raw['customer'])['id'] ?? ''}';
        }
        if (raw['_isCreditNote'] == true) {
          final docNum = '${raw['documentNumber'] ?? ''}'.trim();
          for (final oi in asList(_ws['openItems'])) {
            if ('${oi['sourceId'] ?? ''}' == cnOrItemId ||
                (docNum.isNotEmpty && '${oi['documentNumber'] ?? ''}' == docNum)) {
              resolvedOpenItemId = '${oi['id']}';
              break;
            }
          }
        }
      }
    }

    if (partyId.isEmpty ||
        resolvedOpenItemId.isEmpty ||
        instrId.isEmpty ||
        !isValidAmount(amt)) {
      setState(
        () => _error =
            'Provide Customer Party UUID, Credit Note UUID, Instrument / Bank Account UUID, and valid Refund Amount INR.',
      );
      return;
    }
    if (!_ensurePostingGovernance(
      'Disbursed customer refund payment against open credit note.',
    )) {
      return;
    }

    final normAmt = normAmount(amt);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/payments/customer-refunds',
        idempotent: true,
        body: {
          'partyId': partyId,
          'creditNoteId': cnOrItemId,
          'method': 'BANK_TRANSFER',
          'settlementDate': todayIso(),
          'currency': 'INR',
          'amount': normAmt,
          'instrumentAccountId': instrId,
          if (ref.isNotEmpty) 'paymentReference': ref,
          'postingPeriodId': _periodCtrl.text.trim(),
          'documentSeriesId': _docSeriesCtrl.text.trim(),
          'journalSeriesId': _jrnSeriesCtrl.text.trim(),
          'allocations': [
            {
              'openItemId': resolvedOpenItemId,
              'amount': normAmt,
            },
          ],
          'reason': _govReasonCtrl.text.trim().length >= 10
              ? _govReasonCtrl.text.trim()
              : 'Disbursed customer refund payment against open credit note.',
        },
      );
      if (!mounted) return;
      _refCustomerCtrl.clear();
      _refCreditNoteCtrl.clear();
      _refAmountCtrl.clear();
      _refRefCtrl.clear();
      setState(() => _activeForm = null);
      toast(context, 'Customer refund posted.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openProviderClearingSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _ProviderClearingBatchSheet(
        ws: _ws,
        lk: _lk,
        onSaved: _load,
      ),
    );
  }

  Future<void> _openSettlementManageSheet(Map<String, dynamic> s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _SettlementManageSheet(
        settlement: s,
        ws: _ws,
        lk: _lk,
        onSaved: _load,
      ),
    );
  }

  Widget _buildPostingGovernanceToggle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            onPressed: () =>
                setState(() => _showPostingGov = !_showPostingGov),
            icon: Icon(
              _showPostingGov
                  ? Icons.expand_less_rounded
                  : Icons.tune_rounded,
              size: 16,
            ),
            label: Text(
              _showPostingGov
                  ? 'Hide posting period & series'
                  : 'Posting period, series & audit note',
            ),
          ),
        ),
        if (_showPostingGov) ...[
          const SizedBox(height: 6),
          SaasSubBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Posting Period',
                  controller: _periodCtrl,
                  options: _lk.openPeriods(),
                  hint: '-- Select open period --',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LookupField(
                        label: 'Settlement Series',
                        controller: _docSeriesCtrl,
                        options: _lk.series,
                        hint: '-- Select series --',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LookupField(
                        label: 'Journal Series',
                        controller: _jrnSeriesCtrl,
                        options: _lk.seriesFor(const ['JOURNAL']),
                        hint: '-- Select journal series --',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Audit Business Reason (optional override)',
                  controller: _govReasonCtrl,
                  hint: 'Recorded showroom treasury settlement.',
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContextualButton() {
    switch (_tab) {
      case 'DISBURSEMENTS':
        return GoldButton(
          label: _activeForm == 'DISBURSEMENT' ? 'Close Form' : 'Make Payment',
          icon: Icons.north_east_rounded,
          compact: true,
          onPressed: () => setState(() {
            _activeForm =
                _activeForm == 'DISBURSEMENT' ? null : 'DISBURSEMENT';
            _error = null;
          }),
        );
      case 'REFUNDS':
        return GoldButton(
          label: _activeForm == 'REFUND' ? 'Close Form' : 'Post Refund',
          icon: Icons.sync_rounded,
          compact: true,
          onPressed: () => setState(() {
            _activeForm = _activeForm == 'REFUND' ? null : 'REFUND';
            _error = null;
          }),
        );
      case 'CLEARINGS':
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            minimumSize: const Size(0, 36),
          ),
          onPressed: _openProviderClearingSheet,
          icon: const Icon(Icons.sync_alt_rounded, size: 15),
          label: const Text('Record Batch'),
        );
      default:
        return GoldButton(
          label: _tab == 'RECEIPTS' && _activeForm == 'RECEIPT'
              ? 'Close Form'
              : 'Receive Payment',
          icon: Icons.south_west_rounded,
          compact: true,
          onPressed: () => setState(() {
            if (_tab != 'RECEIPTS') {
              _tab = 'RECEIPTS';
              _activeForm = 'RECEIPT';
            } else {
              _activeForm = _activeForm == 'RECEIPT' ? null : 'RECEIPT';
            }
            _error = null;
          }),
        );
    }
  }

  Widget _buildTableHeaderStrip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9.5),
      decoration: BoxDecoration(
        color: Pal.surfaceAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Pal.line),
      ),
      child: Text(
        text,
        style: T.body(11.3, weight: FontWeight.w700, color: Pal.ink),
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

    final openItems = asList(_ws['openItems']);
    final settlements = [
      ...asList(_ws['settlements']),
      if (_ws['settlements'] == null) ...asList(_ws['receipts']),
      if (_ws['settlements'] == null) ...asList(_ws['disbursements']),
      if (_ws['settlements'] == null) ...asList(_ws['refunds']),
    ];
    final clearings = asList(_ws['providerClearings'] ?? _ws['clearings']);

    final q = _search.text.trim().toLowerCase();
    final fOpen = openItems.where((o) {
      if (q.isEmpty) return true;
      return '${o['documentNumber'] ?? ''} ${asMap(o['party'])['displayName'] ?? ''} ${o['kind'] ?? ''} ${asMap(o['account'])['name'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fSettlements = settlements.where((s) {
      if (!_matchesSettlementTab(s, _tab)) return false;
      if (q.isEmpty) return true;
      return '${s['documentNumber'] ?? ''} ${asMap(s['party'])['displayName'] ?? ''} ${s['method'] ?? ''} ${s['paymentReference'] ?? ''} ${s['providerReference'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fClearings = clearings.where((c) {
      if (q.isEmpty) return true;
      return '${c['provider'] ?? ''} ${c['providerBatchRef'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final clearingAccts = _lk.accountsByControl(
      const ['PAYMENT_CLEARING', 'BANK', 'CASH'],
    );
    final allInstrumentAccts =
        clearingAccts.isNotEmpty ? clearingAccts : _lk.accounts;
    final customerInvOpts = _customerInvoiceOptions();
    final supplierPartyOpts = _lk.partiesByRole(
      const ['SUPPLIER', 'VENDOR', 'KARIGAR', 'REFINER', 'BULLION_DEALER'],
    );
    final customerPartyOpts = _lk.partiesByRole(
      const ['CUSTOMER', 'WHOLESALE'],
    );

    return LuxuryModuleScaffold(
      title: 'Settlements & Cashup',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.account_balance_wallet_outlined,
      searchController: _search,
      searchHint: 'Search Doc #, Party, Method, Reference or Batch Ref...',
      onSearchChanged: (_) => setState(() {}),
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Top Workspace Card (`Treasury, Settlements and Open Items` — `image-65..68.png`)
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Pal.goldTint,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Pal.borderGold),
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 19,
                          color: Pal.goldDeep,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Treasury, Settlements and Open Items',
                              style: T.body(
                                16,
                                weight: FontWeight.w800,
                                color: Pal.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Real-time AR/AP subledger open items, partial settlements, customer advances, and bank/card clearing.',
                              style: T.body(12.2, color: Pal.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5.5,
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
                            Text(
                              gold999 != null &&
                                      decOrZero(gold999.sell) > Decimal.zero
                                  ? 'Bullion 24K: ${inr(gold999.sell)} / g'
                                  : 'Bullion rates: No published rate',
                              style: T.body(
                                11.4,
                                weight: FontWeight.w700,
                                color: Pal.goldDeep,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildContextualButton(),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5 Exact Pill Tabs (`Open Items (0)` | `Receipts` | `Disbursements` | `Refunds` | `Provider Clearings (0)`)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Pal.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Pal.line),
                      ),
                      child: Row(
                        children: [
                          for (final t in [
                            ('OPEN_ITEMS', 'Open Items (${openItems.length})'),
                            ('RECEIPTS', 'Receipts'),
                            ('DISBURSEMENTS', 'Disbursements'),
                            ('REFUNDS', 'Refunds'),
                            (
                              'CLEARINGS',
                              'Provider Clearings (${clearings.length})',
                            ),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(9),
                                onTap: () => setState(() {
                                  _tab = t.$1;
                                  _error = null;
                                  if (t.$1 == 'RECEIPTS') {
                                    _activeForm = 'RECEIPT';
                                  } else if (t.$1 == 'DISBURSEMENTS') {
                                    _activeForm = 'DISBURSEMENT';
                                  } else if (t.$1 == 'REFUNDS') {
                                    _activeForm = 'REFUND';
                                  } else {
                                    _activeForm = null;
                                  }
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: _tab == t.$1
                                        ? const LinearGradient(
                                            colors: [
                                              Color(0xFFCFA234),
                                              Color(0xFFB38620),
                                            ],
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Text(
                                    t.$2,
                                    style: T.body(
                                      12.2,
                                      color: _tab == t.$1
                                          ? Colors.white
                                          : Pal.ink,
                                      weight: _tab == t.$1
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
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

            const SizedBox(height: 14),

            // INLINE FORM 1: `Post Customer Receipt` (`image-65.png`)
            if (_tab == 'RECEIPTS' && _activeForm == 'RECEIPT') ...[
              SaasFormCard(
                title: 'Post Customer Receipt',
                subtitle:
                    'Record cash, UPI, card, or bank receipt and allocate against invoice',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Select customer invoice',
                      controller: _rcptInvoiceOrItemCtrl,
                      options: customerInvOpts,
                      hint: 'Select customer invoice',
                      optional: true,
                      onSelected: (opt) {
                        if (opt == null) return;
                        final raw = opt.raw;
                        final pid =
                            '${raw['partyId'] ?? raw['customerPartyId'] ?? asMap(raw['party'])['id'] ?? asMap(raw['customer'])['id'] ?? ''}';
                        final openBal =
                            '${raw['openAmount'] ?? raw['outstandingAmount'] ?? raw['totalAmount'] ?? ''}';
                        setState(() {
                          if (pid.isNotEmpty) _rcptPartyIdCtrl.text = pid;
                          if (raw['_isOpenItem'] == true) {
                            _rcptOpenItemIdCtrl.text = opt.id;
                          } else {
                            _rcptOpenItemIdCtrl.clear();
                          }
                          if (openBal.isNotEmpty) {
                            _rcptOpenBalCtrl.text = normAmount(openBal);
                            if (_rcptAmountCtrl.text.trim().isEmpty) {
                              _rcptAmountCtrl.text = normAmount(openBal);
                            }
                          }
                        });
                      },
                    ),
                    if (_rcptInvoiceOrItemCtrl.text.trim().isEmpty &&
                        customerPartyOpts.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      LookupField(
                        label: 'Customer Party (for unallocated advance)',
                        controller: _rcptPartyIdCtrl,
                        options: customerPartyOpts,
                        hint: '-- Select Customer Party --',
                        optional: true,
                      ),
                    ],
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Select payment clearing account',
                      controller: _rcptClearingAcctCtrl,
                      options: allInstrumentAccts,
                      hint: 'Select payment clearing account',
                    ),
                    const SizedBox(height: 10),
                    SaasDropdown(
                      label: 'Payment Method',
                      value: _rcptMethod,
                      options: const {
                        'UPI': 'UPI',
                        'CASH': 'Cash',
                        'CARD': 'Card',
                        'BANK_TRANSFER': 'NEFT / RTGS Bank Transfer',
                        'CHEQUE': 'Cheque',
                      },
                      onChanged: (v) => setState(() => _rcptMethod = v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Amount INR',
                            controller: _rcptAmountCtrl,
                            hint: 'Amount INR',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Open invoice balance',
                            controller: _rcptOpenBalCtrl,
                            hint: 'Open invoice balance',
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Payment Reference / UTR (if provided)',
                      controller: _rcptRefCtrl,
                      hint: 'Payment Reference / UTR (if provided)',
                      mono: true,
                    ),
                    const SizedBox(height: 4),
                    _buildPostingGovernanceToggle(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        GoldButton(
                          label: 'Post Receipt',
                          busy: _busy,
                          onPressed: _busy ? null : _submitCustomerReceipt,
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _activeForm = null),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // INLINE FORM 2: `Post Supplier Disbursement` (`image-66.png`)
            if (_tab == 'DISBURSEMENTS' && _activeForm == 'DISBURSEMENT') ...[
              SaasFormCard(
                title: 'Post Supplier Disbursement',
                subtitle:
                    'Record bank or cash payment and allocate against supplier bill',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Supplier Party UUID',
                      controller: _disbSupplierCtrl,
                      options: supplierPartyOpts.isNotEmpty
                          ? supplierPartyOpts
                          : _lk.parties,
                      hint: 'Supplier Party UUID',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Instrument / Bank Account UUID',
                      controller: _disbInstrumentCtrl,
                      options: allInstrumentAccts,
                      hint: 'Instrument / Bank Account UUID',
                    ),
                    const SizedBox(height: 10),
                    SaasDropdown(
                      label: 'Payment Method',
                      value: _disbMethod,
                      options: const {
                        'BANK_TRANSFER': 'NEFT / RTGS Bank Transfer',
                        'UPI': 'UPI',
                        'CASH': 'Cash',
                        'CHEQUE': 'Cheque',
                        'CARD': 'Card',
                      },
                      onChanged: (v) => setState(() => _disbMethod = v),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Amount INR',
                            controller: _disbAmountCtrl,
                            hint: 'Amount INR',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Payment Reference / UTR',
                            controller: _disbRefCtrl,
                            hint: 'Payment Reference / UTR',
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Subledger Open Item UUID (optional)',
                      controller: _disbOpenItemCtrl,
                      options: _supplierOpenItemOptions(),
                      hint: 'Subledger Open Item UUID (optional)',
                      optional: true,
                      onSelected: (opt) {
                        if (opt == null) return;
                        if (_disbAmountCtrl.text.trim().isEmpty) {
                          final openRem =
                              '${opt.raw['openAmount'] ?? ''}'.trim();
                          if (openRem.isNotEmpty) {
                            setState(
                              () => _disbAmountCtrl.text = normAmount(openRem),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 4),
                    _buildPostingGovernanceToggle(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        GoldButton(
                          label: 'Post Disbursement',
                          busy: _busy,
                          onPressed:
                              _busy ? null : _submitSupplierDisbursement,
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _activeForm = null),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            // INLINE FORM 3: `Post Customer Refund` (`image-67.png`)
            if (_tab == 'REFUNDS' && _activeForm == 'REFUND') ...[
              SaasFormCard(
                title: 'Post Customer Refund',
                subtitle:
                    'Disburse refund payment against open customer credit note',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Customer Party UUID',
                      controller: _refCustomerCtrl,
                      options: customerPartyOpts.isNotEmpty
                          ? customerPartyOpts
                          : _lk.parties,
                      hint: 'Customer Party UUID',
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Credit Note UUID',
                      controller: _refCreditNoteCtrl,
                      options: _creditNoteAndRefundItemOptions(),
                      hint: 'Credit Note UUID',
                      onSelected: (opt) {
                        if (opt == null) return;
                        final raw = opt.raw;
                        final pid =
                            '${raw['partyId'] ?? raw['customerPartyId'] ?? asMap(raw['party'])['id'] ?? asMap(raw['customer'])['id'] ?? ''}';
                        final amt =
                            '${raw['openAmount'] ?? raw['totalAmount'] ?? ''}';
                        setState(() {
                          if (pid.isNotEmpty &&
                              _refCustomerCtrl.text.trim().isEmpty) {
                            _refCustomerCtrl.text = pid;
                          }
                          if (amt.isNotEmpty &&
                              _refAmountCtrl.text.trim().isEmpty) {
                            _refAmountCtrl.text = normAmount(amt);
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Instrument / Bank Account UUID',
                      controller: _refInstrumentCtrl,
                      options: allInstrumentAccts,
                      hint: 'Instrument / Bank Account UUID',
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Refund Amount INR',
                            controller: _refAmountCtrl,
                            hint: 'Refund Amount INR',
                            mono: true,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Payment Reference / UTR',
                            controller: _refRefCtrl,
                            hint: 'Payment Reference / UTR',
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _buildPostingGovernanceToggle(),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        GoldButton(
                          label: 'Post Refund',
                          busy: _busy,
                          onPressed: _busy ? null : _submitCustomerRefund,
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _activeForm = null),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_loading)
              const Panel(child: Skeleton(height: 92))
            else if (_tab == 'OPEN_ITEMS') ...[
              _buildTableHeaderStrip(
                'Doc # · Date · Counterparty · Kind · GL Account · Original · Settled · Open Amount · State',
              ),
              const SizedBox(height: 10),
              if (fOpen.isEmpty)
                const SaasEmptyBox('No active AR/AP open items found.')
              else
                for (final o in fOpen)
                  LuxuryRecordCard(
                    icon: Icons.receipt_long_outlined,
                    pdfDocumentType: 'SUBLEDGER OPEN ITEM',
                    code: '${o['documentNumber'] ?? shortId('${o['id']}')}',
                    status: '${o['state'] ?? 'OPEN'}',
                    lines: [
                      (
                        'Date',
                        fmtDate('${o['documentDate'] ?? o['createdAt'] ?? ''}'),
                      ),
                      (
                        'Counterparty',
                        '${asMap(o['party'])['displayName'] ?? o['partyName'] ?? '—'}',
                      ),
                      ('Kind', '${o['kind'] ?? o['openItemKind'] ?? 'AR/AP'}'),
                      (
                        'GL Account',
                        '${asMap(o['account'])['code'] ?? ''} ${asMap(o['account'])['name'] ?? ''}'
                                .trim()
                                .isEmpty
                            ? '—'
                            : '${asMap(o['account'])['code'] ?? ''} ${asMap(o['account'])['name'] ?? ''}'
                                .trim(),
                      ),
                      (
                        'Original / Settled',
                        '${inr(o['originalAmount'])} / ${inr(o['settledAmount'])}',
                      ),
                    ],
                    amountLabel: 'Open Amount',
                    amountValue: inr(o['openAmount']),
                    actions: [
                      GoldButton(
                        label: '${o['kind'] ?? ''}'
                                .toUpperCase()
                                .contains('PAYABLE')
                            ? 'Make Payment'
                            : 'Receive Payment',
                        compact: true,
                        onPressed: () {
                          final isPayable = '${o['kind'] ?? ''}'
                              .toUpperCase()
                              .contains('PAYABLE');
                          final pid =
                              '${o['partyId'] ?? asMap(o['party'])['id'] ?? ''}';
                          final openAmt = normAmount('${o['openAmount'] ?? ''}');
                          setState(() {
                            if (isPayable) {
                              _tab = 'DISBURSEMENTS';
                              _activeForm = 'DISBURSEMENT';
                              _disbSupplierCtrl.text = pid;
                              _disbOpenItemCtrl.text = '${o['id']}';
                              _disbAmountCtrl.text = openAmt;
                            } else {
                              _tab = 'RECEIPTS';
                              _activeForm = 'RECEIPT';
                              _rcptInvoiceOrItemCtrl.text = '${o['id']}';
                              _rcptPartyIdCtrl.text = pid;
                              _rcptOpenItemIdCtrl.text = '${o['id']}';
                              _rcptOpenBalCtrl.text = openAmt;
                              _rcptAmountCtrl.text = openAmt;
                            }
                          });
                        },
                      ),
                    ],
                  ),
            ] else if (_tab == 'CLEARINGS') ...[
              _buildTableHeaderStrip(
                'Date · Batch Ref · Gross Amount · Provider Fee · Net Bank Deposited · Batched Receipts · State',
              ),
              const SizedBox(height: 10),
              if (fClearings.isEmpty)
                const SaasEmptyBox(
                  'No provider clearing batches recorded yet.',
                )
              else
                for (final c in fClearings)
                  LuxuryRecordCard(
                    icon: Icons.sync_alt_rounded,
                    pdfDocumentType: 'PROVIDER CLEARING BATCH',
                    code:
                        '${c['provider'] ?? 'GATEWAY'} · ${c['providerBatchRef'] ?? shortId('${c['id']}')}',
                    status: '${c['state'] ?? 'POSTED'}',
                    lines: [
                      (
                        'Date',
                        fmtDate(
                          '${c['settlementDate'] ?? c['clearingDate'] ?? ''}',
                        ),
                      ),
                      (
                        'Gross / Provider Fee',
                        '${inr(c['grossAmount'])} / ${inr(c['feeAmount'])}',
                      ),
                      (
                        'Batched Receipts',
                        '${c['batchedReceiptsCount'] ?? asList(c['lines']).length}',
                      ),
                    ],
                    amountLabel: 'Net Bank Deposited',
                    amountValue: inr(
                      c['netBankAmount'] ??
                          c['netAmount'] ??
                          (dParse(c['grossAmount']) - dParse(c['feeAmount'])),
                    ),
                  ),
            ] else ...[
              _buildTableHeaderStrip(
                'Settlement Date · Doc # · Party · Direction · Method · Amount · Allocated / Unallocated · Reference · State',
              ),
              const SizedBox(height: 10),
              if (fSettlements.isEmpty)
                SaasEmptyBox(
                  _tab == 'DISBURSEMENTS'
                      ? 'No supplier disbursements recorded yet.'
                      : _tab == 'REFUNDS'
                          ? 'No customer refunds recorded yet.'
                          : 'No customer receipts recorded yet.',
                )
              else
                for (final s in fSettlements)
                  LuxuryRecordCard(
                    icon: Icons.payments_outlined,
                    pdfDocumentType: _tab == 'DISBURSEMENTS'
                        ? 'SUPPLIER DISBURSEMENT'
                        : _tab == 'REFUNDS'
                            ? 'CUSTOMER REFUND'
                            : 'PAYMENT RECEIPT',
                    code: '${s['documentNumber'] ?? shortId('${s['id']}')}',
                    status: '${s['state'] ?? 'POSTED'}',
                    onTap: () => _openSettlementManageSheet(s),
                    lines: [
                      (
                        'Settlement Date',
                        fmtDate('${s['settlementDate'] ?? ''}'),
                      ),
                      (
                        'Party',
                        '${asMap(s['party'])['displayName'] ?? s['partyName'] ?? '—'}',
                      ),
                      (
                        'Direction · Method',
                        '${s['direction'] ?? s['kind'] ?? _tab} · ${s['method'] ?? '—'}',
                      ),
                      (
                        'Allocated / Unallocated',
                        '${inr(s['allocatedAmount'])} / ${inr(s['unallocatedAmount'])}',
                      ),
                      if ('${s['paymentReference'] ?? s['providerReference'] ?? ''}'
                          .isNotEmpty)
                        (
                          'Reference',
                          '${s['paymentReference'] ?? s['providerReference']}',
                        ),
                    ],
                    amountLabel: 'Amount',
                    amountValue: inr(s['amount']),
                    actions: [
                      GoldButton(
                        label: 'Manage',
                        compact: true,
                        onPressed: () => _openSettlementManageSheet(s),
                      ),
                    ],
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProviderClearingBatchSheet extends StatefulWidget {
  const _ProviderClearingBatchSheet({
    required this.ws,
    required this.lk,
    required this.onSaved,
  });

  final Map<String, dynamic> ws;
  final WorkspaceLookup lk;
  final Future<void> Function() onSaved;

  @override
  State<_ProviderClearingBatchSheet> createState() =>
      _ProviderClearingBatchSheetState();
}

class _ProviderClearingBatchSheetState
    extends State<_ProviderClearingBatchSheet> {
  String _provider = 'RAZORPAY';
  final _batchRefCtrl = TextEditingController();
  final _dateCtrl = TextEditingController(text: todayIso());
  final _feeCtrl = TextEditingController(text: '0.00');
  late final TextEditingController _sourceAcctCtrl;
  late final TextEditingController _bankAcctCtrl;
  late final TextEditingController _feeAcctCtrl;
  late final TextEditingController _periodCtrl;
  late final TextEditingController _docSeriesCtrl;
  late final TextEditingController _jrnSeriesCtrl;
  final _docPickCtrl = TextEditingController();
  final _docGrossCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final List<_ClearingLineDraft> _lines = [];

  bool _saving = false;
  String? _sheetErr;

  @override
  void initState() {
    super.initState();
    final lk = widget.lk;
    _sourceAcctCtrl = TextEditingController(
      text: lk.accountsByControl(const ['PAYMENT_CLEARING']).isNotEmpty
          ? lk.accountsByControl(const ['PAYMENT_CLEARING']).first.id
          : '',
    );
    _bankAcctCtrl = TextEditingController(
      text: lk.accountsByControl(const ['BANK']).isNotEmpty
          ? lk.accountsByControl(const ['BANK']).first.id
          : '',
    );
    _feeAcctCtrl = TextEditingController(
      text: lk.accountsByControl(const ['EXPENSE']).isNotEmpty
          ? lk.accountsByControl(const ['EXPENSE']).first.id
          : '',
    );
    _periodCtrl = TextEditingController(
      text: lk.openPeriods().isNotEmpty ? lk.openPeriods().first.id : '',
    );
    _docSeriesCtrl = TextEditingController(
      text: lk.series.isNotEmpty ? lk.series.first.id : '',
    );
    _jrnSeriesCtrl = TextEditingController(
      text: lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
  }

  @override
  void dispose() {
    for (final c in [
      _batchRefCtrl,
      _dateCtrl,
      _feeCtrl,
      _sourceAcctCtrl,
      _bankAcctCtrl,
      _feeAcctCtrl,
      _periodCtrl,
      _docSeriesCtrl,
      _jrnSeriesCtrl,
      _docPickCtrl,
      _docGrossCtrl,
      _reasonCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settlements = asList(widget.ws['settlements']);
    final settlementOpts = settlements
        .map(
          (s) => LookupOption(
            id: '${s['id']}',
            label:
                '${s['documentNumber'] ?? shortId('${s['id']}')} · ${inr(s['amount'])} (${s['method'] ?? ''})',
            raw: s,
          ),
        )
        .toList();

    var totalGross = Decimal.zero;
    for (final l in _lines) {
      totalGross += dParse(l.grossAmount);
    }
    final feeDec = dParse(_feeCtrl.text);
    final netBank = totalGross > feeDec ? totalGross - feeDec : Decimal.zero;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        16,
        18,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_alt_rounded, color: Pal.gold, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Post Provider Clearing Batch',
                    style: T.body(17, weight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            if (_sheetErr != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(_sheetErr!),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SaasDropdown(
                    label: 'Gateway Provider',
                    value: _provider,
                    options: const {
                      'RAZORPAY': 'Razorpay',
                      'PINE_LABS': 'Pine Labs POS',
                      'HDFC_SMARTGATEWAY': 'HDFC SmartGateway',
                      'ICICI_EAZYPAY': 'ICICI Eazypay',
                    },
                    onChanged: (v) => setState(() => _provider = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SaasField(
                    label: 'Batch Reference',
                    controller: _batchRefCtrl,
                    mono: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DatePickField(
                    label: 'Clearing Date',
                    controller: _dateCtrl,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SaasField(
                    label: 'Provider Fee (INR)',
                    controller: _feeCtrl,
                    mono: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LookupField(
              label: 'Source Clearing GL Account',
              controller: _sourceAcctCtrl,
              options: widget.lk.accounts,
            ),
            const SizedBox(height: 10),
            LookupField(
              label: 'Destination Bank GL Account',
              controller: _bankAcctCtrl,
              options: widget.lk.accounts,
            ),
            const SizedBox(height: 10),
            LookupField(
              label: 'Gateway Fee Expense GL Account',
              controller: _feeAcctCtrl,
              options: widget.lk.accounts,
              optional: true,
            ),
            const SizedBox(height: 10),
            SaasSubBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Batched Receipt Settlement',
                    controller: _docPickCtrl,
                    options: settlementOpts,
                    onSelected: (opt) {
                      if (opt == null) return;
                      _docGrossCtrl.text =
                          normAmount('${opt.raw['amount'] ?? ''}');
                      setState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Gross Receipt Amount',
                          controller: _docGrossCtrl,
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: OutlinedButton(
                          onPressed: () {
                            if (_docPickCtrl.text.trim().isEmpty ||
                                !isValidAmount(_docGrossCtrl.text)) {
                              return;
                            }
                            setState(() {
                              _lines.add(
                                _ClearingLineDraft(
                                  settlementDocumentId:
                                      _docPickCtrl.text.trim(),
                                  label: shortId(_docPickCtrl.text.trim()),
                                  grossAmount: normAmount(_docGrossCtrl.text),
                                ),
                              );
                              _docPickCtrl.clear();
                              _docGrossCtrl.clear();
                            });
                          },
                          child: const Text('+ Add'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Net Bank Deposit: ${inr(netBank)} (${_lines.length} receipt(s))',
                    style: T.mono(11.5, color: Pal.goldDeep),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SaasField(
              label: 'Business Reason (10+ chars)',
              controller: _reasonCtrl,
            ),
            const SizedBox(height: 14),
            RoyalGoldButton(
              label: 'Post Provider Clearing Batch',
              busy: _saving,
              onPressed: _saving
                  ? null
                  : () async {
                      if (_batchRefCtrl.text.trim().isEmpty ||
                          _lines.isEmpty ||
                          _reasonCtrl.text.trim().length < 10) {
                        setState(
                          () => _sheetErr =
                              'Enter Batch Reference, add at least 1 receipt, and enter Business Reason (10+ chars).',
                        );
                        return;
                      }
                      setState(() {
                        _saving = true;
                        _sheetErr = null;
                      });
                      try {
                        await context.read<ApiClient>().post(
                          '/payments/provider-clearings',
                          idempotent: true,
                          body: {
                            'provider': _provider,
                            'providerBatchRef': _batchRefCtrl.text.trim(),
                            'settlementDate': _dateCtrl.text.trim(),
                            'feeAmount': normAmount(_feeCtrl.text),
                            'sourceClearingAccountId':
                                _sourceAcctCtrl.text.trim(),
                            'bankAccountId': _bankAcctCtrl.text.trim(),
                            if (_feeAcctCtrl.text.trim().isNotEmpty)
                              'feeExpenseAccountId': _feeAcctCtrl.text.trim(),
                            'postingPeriodId': _periodCtrl.text.trim(),
                            'documentSeriesId': _docSeriesCtrl.text.trim(),
                            'journalSeriesId': _jrnSeriesCtrl.text.trim(),
                            'lines': _lines
                                .map(
                                  (l) => {
                                    'settlementDocumentId':
                                        l.settlementDocumentId,
                                    'grossAmount': l.grossAmount,
                                  },
                                )
                                .toList(),
                            'reason': _reasonCtrl.text.trim(),
                          },
                        );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        await widget.onSaved();
                      } on ApiException catch (e) {
                        if (mounted) setState(() => _sheetErr = e.message);
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementManageSheet extends StatefulWidget {
  const _SettlementManageSheet({
    required this.settlement,
    required this.ws,
    required this.lk,
    required this.onSaved,
  });

  final Map<String, dynamic> settlement;
  final Map<String, dynamic> ws;
  final WorkspaceLookup lk;
  final Future<void> Function() onSaved;

  @override
  State<_SettlementManageSheet> createState() => _SettlementManageSheetState();
}

class _SettlementManageSheetState extends State<_SettlementManageSheet> {
  String _tab = 'ALLOCATE';
  final _openItemCtrl = TextEditingController();
  late final TextEditingController _allocAmtCtrl;
  late final TextEditingController _periodCtrl;
  late final TextEditingController _jrnSeriesCtrl;
  final _reasonCtrl = TextEditingController();
  bool _saving = false;
  String? _sheetErr;

  @override
  void initState() {
    super.initState();
    _allocAmtCtrl = TextEditingController(
      text: '${widget.settlement['unallocatedAmount'] ?? ''}',
    );
    _periodCtrl = TextEditingController(
      text: widget.lk.openPeriods().isNotEmpty
          ? widget.lk.openPeriods().first.id
          : '',
    );
    _jrnSeriesCtrl = TextEditingController(
      text: widget.lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? widget.lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
  }

  @override
  void dispose() {
    for (final c in [
      _openItemCtrl,
      _allocAmtCtrl,
      _periodCtrl,
      _jrnSeriesCtrl,
      _reasonCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settlement;
    final openItems = asList(widget.ws['openItems']);
    final partyId = '${s['partyId'] ?? asMap(s['party'])['id'] ?? ''}';
    final openOpts = openItems
        .where((o) {
          if (partyId.isEmpty) return true;
          final pid = '${o['partyId'] ?? asMap(o['party'])['id'] ?? ''}';
          return pid.isEmpty || pid == partyId;
        })
        .map(
          (o) => LookupOption(
            id: '${o['id']}',
            label:
                '${o['documentNumber'] ?? shortId('${o['id']}')} · Open ${inr(o['openAmount'])}',
            raw: o,
          ),
        )
        .toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        18,
        16,
        18,
        MediaQuery.of(context).viewInsets.bottom + 24,
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
                    'Manage Settlement · ${s['documentNumber'] ?? shortId('${s['id']}')}',
                    style: T.body(16, weight: FontWeight.w700),
                  ),
                ),
                StatusPill('${s['state'] ?? 'POSTED'}'),
                const SizedBox(width: 6),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            PillTabs<String>(
              value: _tab,
              onChanged: (v) => setState(() {
                _tab = v;
                _sheetErr = null;
              }),
              tabs: const [
                ('ALLOCATE', 'Allocate Unallocated'),
                ('REVERSE', 'Reverse Settlement'),
              ],
            ),
            if (_sheetErr != null) ...[
              const SizedBox(height: 10),
              ErrorBanner(_sheetErr!),
            ],
            const SizedBox(height: 12),
            if (_tab == 'ALLOCATE') ...[
              LookupField(
                label: 'Open AR/AP item',
                controller: _openItemCtrl,
                options: openOpts,
                hint: 'Select...',
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Allocation amount (INR)',
                controller: _allocAmtCtrl,
                mono: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Business reason (min 10 chars)',
                controller: _reasonCtrl,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              RoyalGoldButton(
                label: 'Allocate Advance to Open Item',
                busy: _saving,
                onPressed: _saving
                    ? null
                    : () async {
                        if (_openItemCtrl.text.trim().isEmpty ||
                            !isValidAmount(_allocAmtCtrl.text) ||
                            _reasonCtrl.text.trim().length < 10) {
                          setState(
                            () => _sheetErr =
                                'Select open item, valid amount, and reason (10+ chars).',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _sheetErr = null;
                        });
                        try {
                          await context.read<ApiClient>().post(
                            '/payments/settlements/${s['id']}/allocate',
                            idempotent: true,
                            body: {
                              'expectedVersion':
                                  asInt(s['version'], fallback: 1),
                              'allocations': [
                                {
                                  'openItemId': _openItemCtrl.text.trim(),
                                  'amount': normAmount(_allocAmtCtrl.text),
                                },
                              ],
                              'reason': _reasonCtrl.text.trim(),
                            },
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          await widget.onSaved();
                        } on ApiException catch (e) {
                          if (mounted) setState(() => _sheetErr = e.message);
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
              ),
            ] else ...[
              LookupField(
                label: 'Posting period',
                controller: _periodCtrl,
                options: widget.lk.openPeriods(),
                hint: 'Select...',
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Journal series',
                controller: _jrnSeriesCtrl,
                options: widget.lk.seriesFor(const ['JOURNAL']),
                hint: 'Select...',
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Reversal business reason (min 10 chars)',
                controller: _reasonCtrl,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              RoyalGoldButton(
                label: 'Reverse Settlement & Reopen AR/AP',
                busy: _saving,
                onPressed: _saving
                    ? null
                    : () async {
                        if (_periodCtrl.text.trim().isEmpty ||
                            _jrnSeriesCtrl.text.trim().isEmpty ||
                            _reasonCtrl.text.trim().length < 10) {
                          setState(
                            () => _sheetErr =
                                'Select posting period, journal series, and enter reason (10+ chars).',
                          );
                          return;
                        }
                        setState(() {
                          _saving = true;
                          _sheetErr = null;
                        });
                        try {
                          await context.read<ApiClient>().post(
                            '/payments/settlements/${s['id']}/reverse',
                            idempotent: true,
                            body: {
                              'expectedVersion':
                                  asInt(s['version'], fallback: 1),
                              'postingPeriodId': _periodCtrl.text.trim(),
                              'journalSeriesId': _jrnSeriesCtrl.text.trim(),
                              'reversalDate': todayIso(),
                              'reason': _reasonCtrl.text.trim(),
                            },
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context);
                          await widget.onSaved();
                        } on ApiException catch (e) {
                          if (mounted) setState(() => _sheetErr = e.message);
                        } finally {
                          if (mounted) setState(() => _saving = false);
                        }
                      },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. BANKING & RECONCILIATION (`/banking`) — `image-37.png`
// ---------------------------------------------------------------------------

class BankingReconciliationScreen extends StatefulWidget {
  const BankingReconciliationScreen({super.key});
  @override
  State<BankingReconciliationScreen> createState() =>
      _BankingReconciliationScreenState();
}

class _BankingReconciliationScreenState
    extends State<BankingReconciliationScreen> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _importExpanded = true;
  List<Map<String, dynamic>> _statements = [];
  List<LookupOption> _bankAccounts = const [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Exact fields from `image-37.png` (`Import normalized bank CSV`)
  final _bankAcctId = TextEditingController();
  final _statementId = TextEditingController();
  final _startDate = TextEditingController(text: todayIso());
  final _endDate = TextEditingController(text: todayIso());
  final _openingBal = TextEditingController();
  final _closingBal = TextEditingController();
  final _currency = TextEditingController(text: 'INR');
  final _csvText = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _search,
      _bankAcctId,
      _statementId,
      _startDate,
      _endDate,
      _openingBal,
      _closingBal,
      _currency,
      _csvText,
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
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final rawBank = asMap(res[0]);
      final lk = res[1] as WorkspaceLookup;
      final explicitBanks = asList(
        rawBank['bankAccounts'] ?? rawBank['accounts'],
      )
          .map(
            (b) => LookupOption(
              id: '${b['id'] ?? ''}',
              label:
                  '${b['code'] ?? b['accountNumber'] ?? ''} ${b['name'] ?? b['bankName'] ?? 'Bank Account'}'
                      .trim(),
              raw: b,
            ),
          )
          .where((o) => o.id.isNotEmpty)
          .toList();

      setState(() {
        _statements = asList(
          res[0],
          keys: const ['statements', 'bankStatements', 'items'],
        );
        _bankAccounts = explicitBanks.isNotEmpty
            ? explicitBanks
            : lk.accountsByControl(const ['BANK', 'ASSET']);
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _insertCsvHeader() {
    if (_csvText.text.trim().isEmpty) {
      setState(() {
        _csvText.text =
            'transaction_date,direction,amount,description,value_date,reference,bank_transaction_id\n';
      });
      toast(context, 'Normalized CSV header inserted.');
    }
  }

  Future<void> _pasteCsvClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = (data?.text ?? '').trim();
    if (txt.isEmpty) {
      if (mounted) toast(context, 'Clipboard is empty.', error: true);
      return;
    }
    setState(() => _csvText.text = txt);
    if (mounted) toast(context, 'CSV statement pasted from clipboard.');
  }

  Future<void> _importStatement() async {
    if (_bankAcctId.text.trim().isEmpty ||
        _statementId.text.trim().isEmpty ||
        _openingBal.text.trim().isEmpty ||
        _closingBal.text.trim().isEmpty ||
        _csvText.text.trim().isEmpty) {
      setState(
        () => _error =
            'Complete Bank account UUID, Statement ID, Opening/Closing balances, and normalized CSV statement content.',
      );
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
          'openingBalance': normAmount(_openingBal.text),
          'closingBalance': normAmount(_closingBal.text),
          'currency': _currency.text.trim().toUpperCase(),
          'csvContent': _csvText.text.trim(),
        },
      );
      if (!mounted) return;
      _statementId.clear();
      _csvText.clear();
      toast(context, 'Normalized bank CSV statement imported.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------------------
  // Reconciliation Lifecycle Modal: Auto-Match, Line Match, Exception, Close
  // -------------------------------------------------------------------------
  Future<void> _openStatementManageSheet(Map<String, dynamic> stmt) async {
    var actionTab = 'MATCH';
    final lines = asList(stmt['lines'] ?? stmt['statementLines']);
    final lineOpts = [
      for (final l in lines)
        if ('${l['id'] ?? ''}'.isNotEmpty)
          LookupOption(
            id: '${l['id']}',
            label:
                '${fmtDate('${l['transactionDate'] ?? ''}')} · ${l['direction'] ?? ''} ${inr(l['amount'])} · ${l['description'] ?? ''}',
            raw: l,
          ),
    ];

    final lineIdCtrl = TextEditingController(
      text: lineOpts.isNotEmpty ? lineOpts.first.id : '',
    );
    final journalIdCtrl = TextEditingController();
    var excKind = 'BANK_CHARGES';
    final offsetAcctCtrl = TextEditingController(
      text: _lk.accountsByControl(const ['EXPENSE']).isNotEmpty
          ? _lk.accountsByControl(const ['EXPENSE']).first.id
          : '',
    );
    final periodCtrl = TextEditingController(
      text: _lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : '',
    );
    final jrnSeriesCtrl = TextEditingController(
      text: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? _lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
    final reasonCtrl = TextEditingController();

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
                        'Reconcile · ${stmt['externalStatementId'] ?? shortId('${stmt['id']}')}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill(
                      '${stmt['state'] ?? stmt['status'] ?? 'IMPORTED'}',
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PillTabs<String>(
                  value: actionTab,
                  onChanged: (v) => setSheet(() {
                    actionTab = v;
                    sheetErr = null;
                  }),
                  tabs: const [
                    ('MATCH', 'Ledger Match'),
                    ('EXCEPTION', 'Exceptions'),
                    ('CLOSE', 'Maker-Checker Close'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (actionTab == 'MATCH') ...[
                  Text(
                    'Run deterministic auto-matching against posted GL bank entries, or link a specific statement line.',
                    style: T.body(12, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  RoyalGoldButton(
                    label: 'Run Deterministic Auto-Match',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/banking/statements/${stmt['id']}/auto-match',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(stmt['version'], fallback: 1),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(
                                context,
                                'Deterministic ledger auto-match completed.',
                              );
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                  const Divider(height: 24),
                  LookupField(
                    label: 'Statement line UUID',
                    controller: lineIdCtrl,
                    options: lineOpts,
                    optional: true,
                    hint: 'Select statement line...',
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Posted GL journal / line UUID',
                    controller: journalIdCtrl,
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Match audit reason (min 10 chars)',
                    controller: reasonCtrl,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: saving
                        ? null
                        : () async {
                            if (lineIdCtrl.text.trim().isEmpty ||
                                journalIdCtrl.text.trim().isEmpty ||
                                reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select statement line, GL journal UUID, and enter reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/banking/statement-lines/${lineIdCtrl.text.trim()}/match',
                                idempotent: true,
                                body: {
                                  'journalId': journalIdCtrl.text.trim(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Statement line matched to GL.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                    child: const Text('Match Selected Line to Ledger'),
                  ),
                ] else if (actionTab == 'EXCEPTION') ...[
                  LookupField(
                    label: 'Unmatched statement line',
                    controller: lineIdCtrl,
                    options: lineOpts,
                    hint: 'Select statement line...',
                  ),
                  const SizedBox(height: 10),
                  SaasDropdown(
                    label: 'Exception classification',
                    value: excKind,
                    options: const {
                      'BANK_CHARGES': 'Bank charges / fee adjustment',
                      'INTEREST_CREDIT': 'Bank interest credit',
                      'TIMING_DIFFERENCE': 'Timing difference carry-forward',
                      'DUPLICATE_OR_REVERSAL': 'Bank error / reversal pair',
                    },
                    onChanged: (v) => setSheet(() => excKind = v),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Offset GL account (for adjustment)',
                    controller: offsetAcctCtrl,
                    options: _lk.accounts,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: LookupField(
                          label: 'Posting period',
                          controller: periodCtrl,
                          options: _lk.openPeriods(),
                          optional: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LookupField(
                          label: 'Journal series',
                          controller: jrnSeriesCtrl,
                          options: _lk.seriesFor(const ['JOURNAL']),
                          optional: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Controlled exception reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Resolve Controlled Exception',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (lineIdCtrl.text.trim().isEmpty ||
                                reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select statement line and enter reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/banking/statement-lines/${lineIdCtrl.text.trim()}/exception',
                                idempotent: true,
                                body: {
                                  'classification': excKind,
                                  if (offsetAcctCtrl.text.trim().isNotEmpty)
                                    'offsetAccountId':
                                        offsetAcctCtrl.text.trim(),
                                  if (periodCtrl.text.trim().isNotEmpty)
                                    'postingPeriodId': periodCtrl.text.trim(),
                                  if (jrnSeriesCtrl.text.trim().isNotEmpty)
                                    'journalSeriesId':
                                        jrnSeriesCtrl.text.trim(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(
                                context,
                                'Controlled exception resolution recorded.',
                              );
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  Text(
                    'Maker submits reconciled statement for review; independent Checker approves & closes reconciliation.',
                    style: T.body(12, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Maker / Checker sign-off reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (reasonCtrl.text.trim().length < 10) {
                                    setSheet(
                                      () => sheetErr =
                                          'Enter sign-off reason (10+ chars).',
                                    );
                                    return;
                                  }
                                  setSheet(() {
                                    saving = true;
                                    sheetErr = null;
                                  });
                                  try {
                                    await context.read<ApiClient>().post(
                                      '/banking/statements/${stmt['id']}/submit',
                                      idempotent: true,
                                      body: {
                                        'expectedVersion':
                                            asInt(stmt['version'], fallback: 1),
                                        'reason': reasonCtrl.text.trim(),
                                      },
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    if (!mounted) return;
                                    toast(
                                      context,
                                      'Statement submitted for checker sign-off.',
                                    );
                                    _load();
                                  } on ApiException catch (e) {
                                    setSheet(() => sheetErr = e.message);
                                  } finally {
                                    if (ctx.mounted) {
                                      setSheet(() => saving = false);
                                    }
                                  }
                                },
                          child: const Text('Maker Submit'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RoyalGoldButton(
                          label: 'Checker Close',
                          busy: saving,
                          onPressed: saving
                              ? null
                              : () async {
                                  if (reasonCtrl.text.trim().length < 10) {
                                    setSheet(
                                      () => sheetErr =
                                          'Enter checker approval reason (10+ chars).',
                                    );
                                    return;
                                  }
                                  setSheet(() {
                                    saving = true;
                                    sheetErr = null;
                                  });
                                  try {
                                    await context.read<ApiClient>().post(
                                      '/banking/statements/${stmt['id']}/close',
                                      idempotent: true,
                                      body: {
                                        'expectedVersion':
                                            asInt(stmt['version'], fallback: 1),
                                        'reason': reasonCtrl.text.trim(),
                                      },
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    if (!mounted) return;
                                    toast(
                                      context,
                                      'Bank statement reconciliation closed.',
                                    );
                                    _load();
                                  } on ApiException catch (e) {
                                    setSheet(() => sheetErr = e.message);
                                  } finally {
                                    if (ctx.mounted) {
                                      setSheet(() => saving = false);
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    for (final c in [
      lineIdCtrl,
      journalIdCtrl,
      offsetAcctCtrl,
      periodCtrl,
      jrnSeriesCtrl,
      reasonCtrl,
    ]) {
      c.dispose();
    }
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
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
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

            // Hero Header Card (`Bank Reconciliation` — image-37.png)
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
                        Icons.account_balance_rounded,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bank Reconciliation',
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
                    'Deduplicated statement imports, deterministic ledger matching, controlled exceptions and maker-checker close.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // `Import normalized bank CSV` Card (`image-37.png`)
            SaasFormCard(
              title: 'Import normalized bank CSV',
              subtitle:
                  'Required columns: transaction_date, direction, amount, description. Optional: value_date, reference, bank_transaction_id.',
              icon: Icons.upload_rounded,
              trailing: TextButton(
                onPressed: () =>
                    setState(() => _importExpanded = !_importExpanded),
                child: Text(_importExpanded ? 'Hide' : 'Show'),
              ),
              child: !_importExpanded
                  ? Text(
                      'Tap Show to import a normalized bank CSV statement.',
                      style: T.body(12.2, color: Pal.muted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LookupField(
                          label: 'Bank account UUID',
                          controller: _bankAcctId,
                          options: _bankAccounts,
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
                            Expanded(
                              child: DatePickField(
                                label: 'From date',
                                controller: _startDate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DatePickField(
                                label: 'To date',
                                controller: _endDate,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Opening balance',
                                controller: _openingBal,
                                hint: 'Opening balance',
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'Closing balance',
                                controller: _closingBal,
                                hint: 'Closing balance',
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SaasField(
                          label: 'Currency',
                          controller: _currency,
                          mono: true,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pasteCsvClipboard,
                              icon: const Icon(
                                Icons.content_paste_rounded,
                                size: 16,
                              ),
                              label: const Text('Paste CSV'),
                            ),
                            OutlinedButton(
                              onPressed: _insertCsvHeader,
                              child: const Text('Insert CSV columns header'),
                            ),
                            Text(
                              'Choose / paste a CSV statement',
                              style: T.body(11.8, color: Pal.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _csvText,
                          maxLines: 5,
                          style: T.mono(12),
                          decoration: const InputDecoration(
                            hintText:
                                'transaction_date,direction,amount,description',
                          ),
                        ),
                        const SizedBox(height: 14),
                        RoyalGoldButton(
                          label: 'Import statement',
                          busy: _busy,
                          onPressed: _busy ? null : _importStatement,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Panel(child: Skeleton(height: 92))
            else if (filtered.isEmpty)
              const SaasEmptyBox('No bank statements imported.')
            else
              for (final s in filtered)
                LuxuryRecordCard(
                  icon: Icons.account_balance_rounded,
                  code: '${s['externalStatementId'] ?? shortId('${s['id']}')}',
                  status: '${s['state'] ?? s['status'] ?? 'IMPORTED'}',
                  onTap: () => _openStatementManageSheet(s),
                  lines: [
                    (
                      'Statement Period',
                      '${fmtDate('${s['startDate'] ?? ''}')} → ${fmtDate('${s['endDate'] ?? ''}')}',
                    ),
                    ('Opening Balance', inr(s['openingBalance'])),
                    (
                      'Lines',
                      '${asList(s['lines'] ?? s['statementLines']).length} transaction(s)',
                    ),
                  ],
                  amountLabel: 'Closing Balance',
                  amountValue: inr(s['closingBalance']),
                  actions: [
                    GoldButton(
                      label: 'Reconcile Statement',
                      compact: true,
                      onPressed: () => _openStatementManageSheet(s),
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
// 4. CONSOLIDATED CHAIN ANALYTICS (`/chain-analytics`) — `image-38..39.png`
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
      final d = await context.read<ApiClient>().get(
        '/chain-analytics',
        query: {
          'from': _fromDate.text.trim(),
          'to': _toDate.text.trim(),
          'startDate': _fromDate.text.trim(),
          'endDate': _toDate.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _data = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _miniMetricBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Pal.bgTint,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Pal.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.caps(9.6, color: Pal.muted),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.mono(13.5, weight: FontWeight.w700),
          ),
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

    final summary = asMap(_data['summary']).isNotEmpty
        ? asMap(_data['summary'])
        : _data;
    final reported = asMap(
      _data['reportedTotals'] ?? _data['reportedLedgerTotals'],
    );
    final consolidated = asMap(
      _data['consolidatedTotals'] ??
          _data['afterEliminations'] ??
          _data['afterConsolidationEliminations'],
    );
    final icPairs = asList(
      _data['intercompanyReconciliation'] ?? _data['entityPairs'],
    );
    final eliminations = asList(
      _data['eliminationSchedule'] ?? _data['eliminations'],
    );
    final entities = asList(
      _data['legalEntities'] ?? _data['legalEntityComparison'],
    );

    // Flatten or read `branchOperatingView` (`image-39.png`)
    final rawBranches = asList(
      _data['branches'] ?? _data['branchOperatingView'],
    );
    final branches = rawBranches.isNotEmpty
        ? rawBranches
        : [
            for (final e in entities)
              for (final b in asList(e['branches']))
                {
                  ...b,
                  if (b['legalEntityName'] == null)
                    'legalEntityName': e['legalName'] ?? e['name'],
                },
          ];

    final balanced = _data['intercompanyBalanced'] != false;
    final q = _search.text.trim().toLowerCase();

    final fEntities = entities.where((e) {
      if (q.isEmpty) return true;
      return '${e['legalName'] ?? ''} ${e['name'] ?? ''} ${e['currency'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fBranches = branches.where((b) {
      if (q.isEmpty) return true;
      return '${b['code'] ?? ''} ${b['name'] ?? ''} ${b['branchName'] ?? ''} ${b['legalEntityName'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final authEntitiesCnt =
        summary['authorizedEntities'] ??
        _data['authorizedEntityCount'] ??
        entities.length;
    final authBranchesCnt =
        summary['authorizedBranches'] ??
        _data['authorizedBranchCount'] ??
        branches.length;
    final repProfit =
        reported['profit'] ??
        reported['netProfit'] ??
        summary['reportedProfitInr'] ??
        _data['reportedProfit'] ??
        '0.00';
    final conProfit =
        consolidated['profit'] ??
        consolidated['netProfit'] ??
        summary['consolidatedProfitInr'] ??
        _data['consolidatedProfit'] ??
        '0.00';

    return LuxuryModuleScaffold(
      title: 'Consolidated Chain Analytics',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.bar_chart_rounded,
      searchController: _search,
      searchHint: 'Search Legal Entity or Showroom Branch...',
      onSearchChanged: (_) => setState(() {}),
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Hero Header Card + `From` / `To` Date Range (`image-38.png`)
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
                          'Consolidated Chain Analytics',
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
                    'Authorization-scoped entity and branch MIS with currency-separated financials, paired intercompany controls and traceable consolidation eliminations.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 12),
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
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (_loading)
              const Panel(child: Skeleton(height: 120))
            else ...[
              // 1. Exact 4 KPI Cards (`image-38.png`)
              SaasKpiGrid(
                items: [
                  (label: 'AUTHORIZED ENTITIES', value: '$authEntitiesCnt'),
                  (label: 'AUTHORIZED BRANCHES', value: '$authBranchesCnt'),
                  (label: 'REPORTED PROFIT · INR', value: inr(repProfit)),
                  (label: 'CONSOLIDATED PROFIT · INR', value: inr(conProfit)),
                ],
              ),

              const SizedBox(height: 12),

              // 2. `Reported ledger totals` & `After consolidation eliminations` (`image-38.png`)
              SaasFormCard(
                title: 'Reported ledger totals',
                child: Column(
                  children: [
                    KVRow('Revenue', inr(reported['revenue'] ?? '0.00')),
                    KVRow('Expense', inr(reported['expense'] ?? '0.00')),
                    KVRow('Net Profit', inr(repProfit), bold: true),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              SaasFormCard(
                title: 'After consolidation eliminations',
                child: Column(
                  children: [
                    KVRow(
                      'Consolidated Revenue',
                      inr(consolidated['revenue'] ?? '0.00'),
                    ),
                    KVRow(
                      'Consolidated Expense',
                      inr(consolidated['expense'] ?? '0.00'),
                    ),
                    KVRow('Consolidated Profit', inr(conProfit), bold: true),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 3. `Intercompany reconciliation` Card (`image-38.png`)
              SaasFormCard(
                title: 'Intercompany reconciliation',
                icon: Icons.balance_rounded,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: balanced ? Pal.okWash : Pal.warnWash,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        balanced
                            ? Icons.check_circle_outline_rounded
                            : Icons.warning_amber_rounded,
                        size: 13,
                        color: balanced ? Pal.ok : Pal.warn,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        balanced ? 'Balanced' : 'Variance',
                        style: T.body(
                          11.2,
                          weight: FontWeight.w700,
                          color: balanced ? Pal.ok : Pal.warn,
                        ),
                      ),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ENTITY PAIR · CURRENCY · RECEIVABLE · PAYABLE · DIFFERENCE',
                      style: T.caps(9.8),
                    ),
                    const Divider(height: 18),
                    if (icPairs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'No open intercompany balances in the authorized entity set.',
                          textAlign: TextAlign.center,
                          style: T.body(12.5, color: Pal.muted),
                        ),
                      )
                    else
                      for (final p in icPairs)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${p['entityPair'] ?? p['pair'] ?? 'Entity Pair'} (${p['currency'] ?? 'INR'})',
                                style: T.body(12.8, weight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Receivable ${inr(p['receivable'])} · Payable ${inr(p['payable'])} · Diff ${inr(p['difference'] ?? '0.00')}',
                                style: T.mono(11.6, color: Pal.muted),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // 4. `Elimination schedule` Card (`image-38.png` & `image-39.png`)
              SaasFormCard(
                title: 'Elimination schedule',
                subtitle:
                    'Receivable/payable elimination plus revenue, historical-cost and realized/unrealized transfer-margin adjustments. GST balances remain statutory legal-entity positions.',
                child: eliminations.isEmpty
                    ? Text(
                        'No inter-entity elimination adjustments in the selected period.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
                        children: [
                          for (final el in eliminations)
                            KVRow(
                              '${el['reference'] ?? ''} ${el['description'] ?? 'Elimination'}'
                                  .trim(),
                              inr(el['amount'] ?? '0.00'),
                            ),
                        ],
                      ),
              ),

              const SizedBox(height: 16),

              // 5. `Legal-entity comparison` (`image-39.png`)
              Text(
                'Legal-entity comparison',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (fEntities.isEmpty)
                const SaasEmptyBox('No authorized legal entities found.')
              else
                for (final e in fEntities)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Pal.card,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Pal.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${e['legalName'] ?? e['name'] ?? 'Legal Entity'}',
                                style: T.body(14.5, weight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${e['currency'] ?? 'INR'}',
                              style: T.mono(
                                11.5,
                                color: Pal.goldDeep,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e['authorizedBranchCount'] ?? asList(e['branches']).length} authorized branch(es) · ${e['currency'] ?? 'INR'}',
                          style: T.body(11.8, color: Pal.muted),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _miniMetricBox(
                                'EXTERNAL SALES',
                                inr(
                                  e['externalSales'] ??
                                      e['sales'] ??
                                      e['revenue'] ??
                                      '0.00',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _miniMetricBox(
                                'GROSS MARGIN',
                                inr(
                                  e['grossMargin'] ?? e['margin'] ?? '0.00',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _miniMetricBox(
                                'TAGGED FINE STOCK',
                                '${dStr6(dParse(e['taggedFineStockGrams'] ?? e['taggedFineGrams']))} g',
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _miniMetricBox(
                                'LOT FINE STOCK',
                                '${dStr6(dParse(e['lotFineStockGrams'] ?? e['lotFineGrams']))} g',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

              const SizedBox(height: 8),

              // 6. `Branch operating view` (`image-39.png`)
              Text(
                'Branch operating view',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'BRANCH · ENTITY · SALES · MARGIN · TAGGED FINE · LOT FINE',
                style: T.caps(9.8),
              ),
              const SizedBox(height: 8),
              if (fBranches.isEmpty)
                const SaasEmptyBox('No authorized showroom branches found.')
              else
                for (final b in fBranches)
                  LuxuryRecordCard(
                    icon: Icons.storefront_outlined,
                    code:
                        '${b['code'] ?? b['branchCode'] ?? ''} · ${b['name'] ?? b['branchName'] ?? 'Branch'}'
                            .replaceFirst(RegExp(r'^\s*·\s*'), ''),
                    status: '${b['currency'] ?? 'INR'}',
                    lines: [
                      (
                        'Entity',
                        '${b['legalEntityName'] ?? asMap(b['legalEntity'])['legalName'] ?? tenantName}',
                      ),
                      (
                        'Margin',
                        inr(b['grossMargin'] ?? b['margin'] ?? '0.00'),
                      ),
                      (
                        'Tagged fine',
                        '${dStr6(dParse(b['taggedFineStockGrams'] ?? b['taggedFineGrams']))} g',
                      ),
                      (
                        'Lot fine',
                        '${dStr6(dParse(b['lotFineStockGrams'] ?? b['lotFineGrams']))} g',
                      ),
                    ],
                    amountLabel: 'Sales',
                    amountValue: inr(
                      b['externalSales'] ?? b['sales'] ?? '0.00',
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
