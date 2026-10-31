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
// 2. SETTLEMENTS & CASHUP (`/payments`) — `image-32..36.png`
// ---------------------------------------------------------------------------

class SettlementsCashupScreen extends StatefulWidget {
  const SettlementsCashupScreen({super.key});
  @override
  State<SettlementsCashupScreen> createState() =>
      _SettlementsCashupScreenState();
}

class _AllocationDraft {
  const _AllocationDraft({
    required this.openItemId,
    required this.label,
    required this.amount,
  });
  final String openItemId;
  final String label;
  final String amount;
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
  String _tab = 'OPEN_ITEMS';
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
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
    try {
      final res = await Future.wait([
        api.get('/payments'),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _ws = asMap(res[0]);
        _lk = res[1] as WorkspaceLookup;
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

  // -------------------------------------------------------------------------
  // Modal Sheet: Receive Payment / Make Payment / Post Refund (`image-33..35`)
  // -------------------------------------------------------------------------
  Future<void> _openSettlementActionSheet({
    required String mode, // RECEIPTS | DISBURSEMENTS | REFUNDS
    Map<String, dynamic>? prefillOpenItem,
  }) async {
    final openItems = asList(_ws['openItems']);
    final isDisburse = mode == 'DISBURSEMENTS';
    final isRefund = mode == 'REFUNDS';

    final title = isDisburse
        ? 'Make Payment'
        : isRefund
            ? 'Post Refund'
            : 'Receive Payment';
    final endpoint = isDisburse
        ? '/payments/supplier-disbursements'
        : isRefund
            ? '/payments/customer-refunds'
            : '/payments/customer-receipts';

    final partyCtrl = TextEditingController(
      text: prefillOpenItem != null
          ? '${prefillOpenItem['partyId'] ?? asMap(prefillOpenItem['party'])['id'] ?? ''}'
          : '',
    );
    final instrumentCtrl = TextEditingController(
      text: _lk
              .accountsByControl(
                const ['CASH', 'BANK', 'PAYMENT_CLEARING'],
              )
              .isNotEmpty
          ? _lk
              .accountsByControl(
                const ['CASH', 'BANK', 'PAYMENT_CLEARING'],
              )
              .first
              .id
          : '',
    );
    var method = (isDisburse || isRefund) ? 'BANK_TRANSFER' : 'UPI';
    final dateCtrl = TextEditingController(text: todayIso());
    final amtCtrl = TextEditingController(
      text: prefillOpenItem != null
          ? '${prefillOpenItem['openAmount'] ?? ''}'
          : '',
    );
    final payRefCtrl = TextEditingController();
    final provRefCtrl = TextEditingController();

    final allocItemCtrl = TextEditingController();
    final allocAmtCtrl = TextEditingController();
    final allocations = <_AllocationDraft>[
      if (prefillOpenItem != null &&
          '${prefillOpenItem['id'] ?? ''}'.isNotEmpty &&
          isValidAmount('${prefillOpenItem['openAmount'] ?? ''}'))
        _AllocationDraft(
          openItemId: '${prefillOpenItem['id']}',
          label:
              '${prefillOpenItem['documentNumber'] ?? shortId('${prefillOpenItem['id']}')} · Open ${inr(prefillOpenItem['openAmount'])}',
          amount: normAmount('${prefillOpenItem['openAmount']}'),
        ),
    ];

    final periodCtrl = TextEditingController(
      text: _lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : '',
    );
    final docSeriesCtrl = TextEditingController(
      text: _lk
              .seriesFor(
                const ['SETTLEMENT', 'RECEIPT', 'PAYMENT', 'DISBURSEMENT'],
              )
              .isNotEmpty
          ? _lk
              .seriesFor(
                const ['SETTLEMENT', 'RECEIPT', 'PAYMENT', 'DISBURSEMENT'],
              )
              .first
              .id
          : (_lk.series.isNotEmpty ? _lk.series.first.id : ''),
    );
    final jrnSeriesCtrl = TextEditingController(
      text: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? _lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
    final reasonCtrl = TextEditingController();

    final methodOptions = (isDisburse || isRefund)
        ? const {
            'BANK_TRANSFER': 'Bank Transfer (NEFT/RTGS/IMPS)',
            'CASH': 'Cash',
            'CHEQUE': 'Cheque',
          }
        : const {
            'UPI': 'UPI',
            'CARD': 'Card',
            'BANK_TRANSFER': 'Bank Transfer',
            'CASH': 'Cash',
            'CHEQUE': 'Cheque',
          };

    final roleFilter = isDisburse
        ? const ['SUPPLIER', 'VENDOR', 'KARIGAR', 'REFINER', 'BULLION_DEALER']
        : const ['CUSTOMER', 'WHOLESALE'];

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
        builder: (ctx, setSheet) {
          final partyFilter = partyCtrl.text.trim();
          final openOpts = openItems
              .where((o) {
                if (partyFilter.isEmpty) return true;
                final pid = '${o['partyId'] ?? asMap(o['party'])['id'] ?? ''}';
                return pid.isEmpty || pid == partyFilter;
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

          var allocatedTotal = Decimal.zero;
          for (final a in allocations) {
            allocatedTotal += dParse(a.amount);
          }
          final grossAmt = dParse(amtCtrl.text);
          final unallocatedAmt = grossAmt > allocatedTotal
              ? grossAmt - allocatedTotal
              : Decimal.zero;

          return Padding(
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
                      Icon(
                        isDisburse
                            ? Icons.north_east_rounded
                            : isRefund
                                ? Icons.replay_rounded
                                : Icons.south_west_rounded,
                        color: Pal.gold,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
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
                    isDisburse
                        ? 'Post outbound supplier/karigar settlement to AP subledger and general ledger.'
                        : isRefund
                            ? 'Refund customer credit / advance balance with balanced GL posting.'
                            : 'Record customer receipt, partial invoice settlement, or unallocated advance.',
                    style: T.body(12, color: Pal.muted),
                  ),
                  if (sheetErr != null) ...[
                    const SizedBox(height: 10),
                    ErrorBanner(sheetErr!),
                  ],
                  const SizedBox(height: 12),

                  LookupField(
                    label: isDisburse ? 'Counterparty (Supplier / Karigar)' : 'Party (Customer)',
                    controller: partyCtrl,
                    options: _lk.partiesByRole(roleFilter),
                    hint: 'Select...',
                    onSelected: (_) => setSheet(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasDropdown(
                          label: 'Method',
                          value: method,
                          options: methodOptions,
                          onChanged: (v) => setSheet(() => method = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DatePickField(
                          label: 'Settlement date',
                          controller: dateCtrl,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const FieldLabel('Amount (INR)'),
                            TextField(
                              controller: amtCtrl,
                              style: T.mono(13.5),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => setSheet(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: (method == 'CARD' || method == 'UPI')
                            ? SaasField(
                                label: 'Provider ref (UTR / Auth)',
                                controller: provRefCtrl,
                                mono: true,
                              )
                            : SaasField(
                                label: 'Payment reference',
                                controller: payRefCtrl,
                                mono: true,
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Instrument GL account (Cash / Bank / Clearing)',
                    controller: instrumentCtrl,
                    options: _lk.accountsByControl(
                      const ['CASH', 'BANK', 'PAYMENT_CLEARING'],
                    ),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 12),

                  // Open Item Allocations Builder
                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isRefund
                                    ? 'Credit Open Item Allocation (Required)'
                                    : 'AR/AP Open Item Allocations (Optional for Advance)',
                                style: T.body(12.2, weight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LookupField(
                          label: 'Open item',
                          controller: allocItemCtrl,
                          options: openOpts,
                          optional: !isRefund,
                          hint: 'Select open item...',
                          onSelected: (opt) {
                            if (allocAmtCtrl.text.trim().isEmpty) {
                              final openRem =
                                  '${opt.raw['openAmount'] ?? ''}'.trim();
                              if (openRem.isNotEmpty) {
                                allocAmtCtrl.text = openRem;
                              }
                            }
                            setSheet(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Allocated amount',
                                controller: allocAmtCtrl,
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: OutlinedButton(
                                onPressed: () {
                                  if (allocItemCtrl.text.trim().isEmpty ||
                                      !isValidAmount(allocAmtCtrl.text)) {
                                    setSheet(
                                      () => sheetErr =
                                          'Select an open item and valid allocation amount.',
                                    );
                                    return;
                                  }
                                  final lbl = openOpts
                                          .where(
                                            (o) =>
                                                o.id ==
                                                allocItemCtrl.text.trim(),
                                          )
                                          .firstOrNull
                                          ?.label ??
                                      allocItemCtrl.text.trim();
                                  setSheet(() {
                                    allocations.add(
                                      _AllocationDraft(
                                        openItemId: allocItemCtrl.text.trim(),
                                        label: lbl,
                                        amount: normAmount(allocAmtCtrl.text),
                                      ),
                                    );
                                    allocItemCtrl.clear();
                                    allocAmtCtrl.clear();
                                    sheetErr = null;
                                  });
                                },
                                child: const Text('+ Add'),
                              ),
                            ),
                          ],
                        ),
                        for (var i = 0; i < allocations.length; i++) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${allocations[i].label} → ₹${allocations[i].amount}',
                                  style: T.body(11.8, weight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Pal.err,
                                ),
                                onPressed: () =>
                                    setSheet(() => allocations.removeAt(i)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Allocated: ${inr(allocatedTotal)} · Unallocated / Advance: ${inr(unallocatedAmt)}',
                          style: T.mono(11.2, color: Pal.goldDeep),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Posting period',
                    controller: periodCtrl,
                    options: _lk.openPeriods(),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: LookupField(
                          label: 'Document series',
                          controller: docSeriesCtrl,
                          options: _lk.series,
                          hint: 'Select...',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LookupField(
                          label: 'Journal series',
                          controller: jrnSeriesCtrl,
                          options: _lk.seriesFor(const ['JOURNAL']),
                          hint: 'Select...',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Business reason (minimum 10 characters)',
                    controller: reasonCtrl,
                    hint: 'Business reason (minimum 10 characters)',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: title,
                    icon: isDisburse
                        ? Icons.north_east_rounded
                        : isRefund
                            ? Icons.replay_rounded
                            : Icons.south_west_rounded,
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            // Auto-add typed single allocation if user didn't tap `+ Add`
                            if (allocations.isEmpty &&
                                allocItemCtrl.text.trim().isNotEmpty) {
                              final autoAmt = allocAmtCtrl.text.trim().isNotEmpty
                                  ? allocAmtCtrl.text.trim()
                                  : amtCtrl.text.trim();
                              if (isValidAmount(autoAmt)) {
                                allocations.add(
                                  _AllocationDraft(
                                    openItemId: allocItemCtrl.text.trim(),
                                    label: allocItemCtrl.text.trim(),
                                    amount: normAmount(autoAmt),
                                  ),
                                );
                              }
                            }
                            if (partyCtrl.text.trim().isEmpty ||
                                instrumentCtrl.text.trim().isEmpty ||
                                !isValidAmount(amtCtrl.text) ||
                                periodCtrl.text.trim().isEmpty ||
                                docSeriesCtrl.text.trim().isEmpty ||
                                jrnSeriesCtrl.text.trim().isEmpty ||
                                reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Complete Party, Amount, Instrument GL account, Posting period, Series, and Business reason (10+ chars).',
                              );
                              return;
                            }
                            if ((method == 'CARD' || method == 'UPI') &&
                                provRefCtrl.text.trim().isEmpty) {
                              setSheet(
                                () => sheetErr =
                                    'Provider reference is required for Card / UPI settlements.',
                              );
                              return;
                            }
                            if (isRefund && allocations.isEmpty) {
                              setSheet(
                                () => sheetErr =
                                    'Select the credit / unallocated open item to refund.',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                endpoint,
                                idempotent: true,
                                body: {
                                  'partyId': partyCtrl.text.trim(),
                                  'method': method,
                                  'settlementDate': dateCtrl.text.trim(),
                                  'currency': 'INR',
                                  'amount': normAmount(amtCtrl.text),
                                  'instrumentAccountId':
                                      instrumentCtrl.text.trim(),
                                  if (method == 'CARD' || method == 'UPI')
                                    'providerReference':
                                        provRefCtrl.text.trim()
                                  else if (payRefCtrl.text.trim().length >= 2)
                                    'paymentReference': payRefCtrl.text.trim(),
                                  'postingPeriodId': periodCtrl.text.trim(),
                                  'documentSeriesId': docSeriesCtrl.text.trim(),
                                  'journalSeriesId': jrnSeriesCtrl.text.trim(),
                                  'allocations': allocations
                                      .map(
                                        (a) => {
                                          'openItemId': a.openItemId,
                                          'amount': a.amount,
                                        },
                                      )
                                      .toList(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, '$title posted to subledger & GL.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    for (final c in [
      partyCtrl,
      instrumentCtrl,
      dateCtrl,
      amtCtrl,
      payRefCtrl,
      provRefCtrl,
      allocItemCtrl,
      allocAmtCtrl,
      periodCtrl,
      docSeriesCtrl,
      jrnSeriesCtrl,
      reasonCtrl,
    ]) {
      c.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // Modal Sheet: Post Provider Clearing Batch (`image-36.png`)
  // -------------------------------------------------------------------------
  Future<void> _openProviderClearingSheet() async {
    final settlements = asList(_ws['settlements']);
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

    var provider = 'RAZORPAY';
    final batchRefCtrl = TextEditingController();
    final dateCtrl = TextEditingController(text: todayIso());
    final feeCtrl = TextEditingController(text: '0.00');
    final sourceAcctCtrl = TextEditingController(
      text: _lk.accountsByControl(const ['PAYMENT_CLEARING']).isNotEmpty
          ? _lk.accountsByControl(const ['PAYMENT_CLEARING']).first.id
          : '',
    );
    final bankAcctCtrl = TextEditingController(
      text: _lk.accountsByControl(const ['BANK']).isNotEmpty
          ? _lk.accountsByControl(const ['BANK']).first.id
          : '',
    );
    final feeAcctCtrl = TextEditingController(
      text: _lk.accountsByControl(const ['EXPENSE']).isNotEmpty
          ? _lk.accountsByControl(const ['EXPENSE']).first.id
          : '',
    );
    final periodCtrl = TextEditingController(
      text: _lk.openPeriods().isNotEmpty ? _lk.openPeriods().first.id : '',
    );
    final docSeriesCtrl = TextEditingController(
      text: _lk.series.isNotEmpty ? _lk.series.first.id : '',
    );
    final jrnSeriesCtrl = TextEditingController(
      text: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
          ? _lk.seriesFor(const ['JOURNAL']).first.id
          : '',
    );
    final docPickCtrl = TextEditingController();
    final docGrossCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final lines = <_ClearingLineDraft>[];

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
        builder: (ctx, setSheet) {
          var totalGross = Decimal.zero;
          for (final l in lines) {
            totalGross += dParse(l.grossAmount);
          }
          final feeDec = dParse(feeCtrl.text);
          final netBank = totalGross > feeDec
              ? totalGross - feeDec
              : Decimal.zero;

          return Padding(
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
                      const Icon(
                        Icons.sync_alt_rounded,
                        color: Pal.gold,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Post Provider Clearing Batch',
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
                    'Clear batched Card / UPI receipts into your bank GL account with gateway fee deduction.',
                    style: T.body(12, color: Pal.muted),
                  ),
                  if (sheetErr != null) ...[
                    const SizedBox(height: 10),
                    ErrorBanner(sheetErr!),
                  ],
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: SaasDropdown(
                          label: 'Gateway / Provider',
                          value: provider,
                          options: const {
                            'RAZORPAY': 'RAZORPAY',
                            'PINE_LABS': 'PINE_LABS',
                            'PAYTM': 'PAYTM',
                            'HDFC_POS': 'HDFC_POS',
                            'ICICI_POS': 'ICICI_POS',
                            'OTHER': 'OTHER',
                          },
                          onChanged: (v) => setSheet(() => provider = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Batch reference',
                          controller: batchRefCtrl,
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
                          label: 'Settlement date',
                          controller: dateCtrl,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const FieldLabel('Provider fee (INR)'),
                            TextField(
                              controller: feeCtrl,
                              style: T.mono(13.5),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) => setSheet(() {}),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Source payment clearing GL account',
                    controller: sourceAcctCtrl,
                    options: _lk.accountsByControl(
                      const ['PAYMENT_CLEARING', 'ASSET'],
                    ),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Destination bank GL account',
                    controller: bankAcctCtrl,
                    options: _lk.accountsByControl(const ['BANK', 'ASSET']),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Gateway fee expense GL account',
                    controller: feeAcctCtrl,
                    options: _lk.accountsByControl(const ['EXPENSE']),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 12),

                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Batched Card / UPI Receipts',
                          style: T.body(12.2, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        LookupField(
                          label: 'Settlement receipt document',
                          controller: docPickCtrl,
                          options: settlementOpts,
                          hint: 'Select receipt...',
                          onSelected: (opt) {
                            final a = '${opt.raw['amount'] ?? ''}'.trim();
                            if (a.isNotEmpty) docGrossCtrl.text = a;
                            setSheet(() {});
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Gross amount (INR)',
                                controller: docGrossCtrl,
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: OutlinedButton(
                                onPressed: () {
                                  if (docPickCtrl.text.trim().isEmpty ||
                                      !isValidAmount(docGrossCtrl.text)) {
                                    setSheet(
                                      () => sheetErr =
                                          'Select a receipt document and valid gross amount.',
                                    );
                                    return;
                                  }
                                  final lbl = settlementOpts
                                          .where(
                                            (o) =>
                                                o.id ==
                                                docPickCtrl.text.trim(),
                                          )
                                          .firstOrNull
                                          ?.label ??
                                      docPickCtrl.text.trim();
                                  setSheet(() {
                                    lines.add(
                                      _ClearingLineDraft(
                                        settlementDocumentId:
                                            docPickCtrl.text.trim(),
                                        label: lbl,
                                        grossAmount:
                                            normAmount(docGrossCtrl.text),
                                      ),
                                    );
                                    docPickCtrl.clear();
                                    docGrossCtrl.clear();
                                    sheetErr = null;
                                  });
                                },
                                child: const Text('+ Add'),
                              ),
                            ),
                          ],
                        ),
                        for (var i = 0; i < lines.length; i++) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${lines[i].label} · ₹${lines[i].grossAmount}',
                                  style: T.body(11.8, weight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Pal.err,
                                ),
                                onPressed: () =>
                                    setSheet(() => lines.removeAt(i)),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          'Gross: ${inr(totalGross)} · Fee: ${inr(feeDec)} · Net Bank: ${inr(netBank)}',
                          style: T.mono(11.2, color: Pal.goldDeep),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Posting period',
                    controller: periodCtrl,
                    options: _lk.openPeriods(),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: LookupField(
                          label: 'Document series',
                          controller: docSeriesCtrl,
                          options: _lk.series,
                          hint: 'Select...',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LookupField(
                          label: 'Journal series',
                          controller: jrnSeriesCtrl,
                          options: _lk.seriesFor(const ['JOURNAL']),
                          hint: 'Select...',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Business reason (minimum 10 characters)',
                    controller: reasonCtrl,
                    hint: 'Business reason (minimum 10 characters)',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Post Provider Clearing',
                    icon: Icons.sync_alt_rounded,
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (lines.isEmpty &&
                                docPickCtrl.text.trim().isNotEmpty &&
                                isValidAmount(docGrossCtrl.text)) {
                              lines.add(
                                _ClearingLineDraft(
                                  settlementDocumentId: docPickCtrl.text.trim(),
                                  label: docPickCtrl.text.trim(),
                                  grossAmount: normAmount(docGrossCtrl.text),
                                ),
                              );
                            }
                            if (batchRefCtrl.text.trim().isEmpty ||
                                sourceAcctCtrl.text.trim().isEmpty ||
                                bankAcctCtrl.text.trim().isEmpty ||
                                feeAcctCtrl.text.trim().isEmpty ||
                                periodCtrl.text.trim().isEmpty ||
                                docSeriesCtrl.text.trim().isEmpty ||
                                jrnSeriesCtrl.text.trim().isEmpty ||
                                lines.isEmpty ||
                                reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Complete Batch ref, GL accounts, at least 1 receipt line, Posting period/series, and Business reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/payments/provider-clearings',
                                idempotent: true,
                                body: {
                                  'provider': provider,
                                  'providerBatchRef': batchRefCtrl.text.trim(),
                                  'settlementDate': dateCtrl.text.trim(),
                                  'feeAmount': feeCtrl.text.trim().isEmpty
                                      ? '0.00'
                                      : normAmount(feeCtrl.text),
                                  'sourceAccountId':
                                      sourceAcctCtrl.text.trim(),
                                  'bankAccountId': bankAcctCtrl.text.trim(),
                                  'feeAccountId': feeAcctCtrl.text.trim(),
                                  'postingPeriodId': periodCtrl.text.trim(),
                                  'documentSeriesId': docSeriesCtrl.text.trim(),
                                  'journalSeriesId': jrnSeriesCtrl.text.trim(),
                                  'lines': lines
                                      .map(
                                        (l) => {
                                          'settlementDocumentId':
                                              l.settlementDocumentId,
                                          'grossAmount': l.grossAmount,
                                        },
                                      )
                                      .toList(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(
                                context,
                                'Provider clearing batch posted to bank GL.',
                              );
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    for (final c in [
      batchRefCtrl,
      dateCtrl,
      feeCtrl,
      sourceAcctCtrl,
      bankAcctCtrl,
      feeAcctCtrl,
      periodCtrl,
      docSeriesCtrl,
      jrnSeriesCtrl,
      docPickCtrl,
      docGrossCtrl,
      reasonCtrl,
    ]) {
      c.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // Lifecycle Sheet on Existing Settlement: Allocate Advance / Reverse
  // -------------------------------------------------------------------------
  Future<void> _openSettlementManageSheet(Map<String, dynamic> s) async {
    final openItems = asList(_ws['openItems']);
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

    var tab = 'ALLOCATE';
    final openItemCtrl = TextEditingController();
    final allocAmtCtrl = TextEditingController(
      text: '${s['unallocatedAmount'] ?? ''}',
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
                        'Manage Settlement · ${s['documentNumber'] ?? shortId('${s['id']}')}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${s['state'] ?? 'POSTED'}'),
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
                  value: tab,
                  onChanged: (v) => setSheet(() {
                    tab = v;
                    sheetErr = null;
                  }),
                  tabs: const [
                    ('ALLOCATE', 'Allocate Unallocated'),
                    ('REVERSE', 'Reverse Settlement'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (tab == 'ALLOCATE') ...[
                  LookupField(
                    label: 'Open AR/AP item',
                    controller: openItemCtrl,
                    options: openOpts,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Allocation amount (INR)',
                    controller: allocAmtCtrl,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Business reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Allocate Advance to Open Item',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (openItemCtrl.text.trim().isEmpty ||
                                !isValidAmount(allocAmtCtrl.text) ||
                                reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select open item, valid amount, and reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
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
                                      'openItemId': openItemCtrl.text.trim(),
                                      'amount': normAmount(allocAmtCtrl.text),
                                    },
                                  ],
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Unallocated balance allocated.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  LookupField(
                    label: 'Posting period',
                    controller: periodCtrl,
                    options: _lk.openPeriods(),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Journal series',
                    controller: jrnSeriesCtrl,
                    options: _lk.seriesFor(const ['JOURNAL']),
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Reversal business reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Reverse Settlement & Reopen AR/AP',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (periodCtrl.text.trim().isEmpty ||
                                jrnSeriesCtrl.text.trim().isEmpty ||
                                reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Select posting period, journal series, and enter reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/payments/settlements/${s['id']}/reverse',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(s['version'], fallback: 1),
                                  'postingPeriodId': periodCtrl.text.trim(),
                                  'journalSeriesId': jrnSeriesCtrl.text.trim(),
                                  'reversalDate': todayIso(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Settlement reversed.');
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
      openItemCtrl,
      allocAmtCtrl,
      periodCtrl,
      jrnSeriesCtrl,
      reasonCtrl,
    ]) {
      c.dispose();
    }
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

    return LuxuryModuleScaffold(
      title: 'Settlements & Cashup',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.account_balance_wallet_outlined,
      searchController: _search,
      searchHint: 'Search Doc #, Counterparty, Method or Batch Ref...',
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Hero Header Card (`Treasury, Settlements and Open Items` — image-32..36.png)
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
                        Icons.account_balance_wallet_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Treasury, Settlements and Open Items',
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
                    'Real-time AR/AP subledger open items, partial settlements, customer advances, and bank/card clearing.',
                    style: T.body(12.2, color: Pal.muted),
                  ),

                  // Tab-specific Golden CTA Buttons (`image-33..36.png`)
                  if (_tab == 'RECEIPTS') ...[
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Receive Payment',
                      icon: Icons.south_west_rounded,
                      onPressed: () =>
                          _openSettlementActionSheet(mode: 'RECEIPTS'),
                    ),
                  ] else if (_tab == 'DISBURSEMENTS') ...[
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Make Payment',
                      icon: Icons.north_east_rounded,
                      onPressed: () =>
                          _openSettlementActionSheet(mode: 'DISBURSEMENTS'),
                    ),
                  ] else if (_tab == 'REFUNDS') ...[
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Post Refund',
                      icon: Icons.replay_rounded,
                      onPressed: () =>
                          _openSettlementActionSheet(mode: 'REFUNDS'),
                    ),
                  ] else if (_tab == 'CLEARINGS') ...[
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Post Provider Clearing',
                      icon: Icons.sync_alt_rounded,
                      onPressed: _openProviderClearingSheet,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            if (_loading)
              const Panel(child: Skeleton(height: 92))

            // 1. OPEN ITEMS (`image-32.png`)
            // Columns: Doc # | Date | Counterparty | Kind | GL Account | Original | Settled | Open Amount | State
            else if (_tab == 'OPEN_ITEMS') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'DOC # · DATE · COUNTERPARTY · KIND · GL ACCOUNT · ORIGINAL · SETTLED · OPEN AMOUNT · STATE',
                  style: T.caps(10),
                ),
              ),
              const SizedBox(height: 8),
              if (fOpen.isEmpty)
                const SaasEmptyBox('No active AR/AP open items found.')
              else
                for (final o in fOpen)
                  LuxuryRecordCard(
                    icon: Icons.receipt_long_outlined,
                    code: '${o['documentNumber'] ?? shortId('${o['id']}')}',
                    status: '${o['state'] ?? 'OPEN'}',
                    lines: [
                      ('Date', fmtDate('${o['documentDate'] ?? o['createdAt'] ?? ''}')),
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
                        onPressed: () => _openSettlementActionSheet(
                          mode: '${o['kind'] ?? ''}'
                                  .toUpperCase()
                                  .contains('PAYABLE')
                              ? 'DISBURSEMENTS'
                              : 'RECEIPTS',
                          prefillOpenItem: o,
                        ),
                      ),
                    ],
                  ),
            ]

            // 5. PROVIDER CLEARINGS (`image-36.png`)
            // Columns: Date | Batch Ref | Gross Amount | Provider Fee | Net Bank Deposited | Batched Receipts | State
            else if (_tab == 'CLEARINGS') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'DATE · BATCH REF · GROSS AMOUNT · PROVIDER FEE · NET BANK DEPOSITED · BATCHED RECEIPTS · STATE',
                  style: T.caps(10),
                ),
              ),
              const SizedBox(height: 8),
              if (fClearings.isEmpty)
                const SaasEmptyBox(
                  'No provider clearing batches recorded yet.',
                )
              else
                for (final c in fClearings)
                  LuxuryRecordCard(
                    icon: Icons.sync_alt_rounded,
                    code:
                        '${c['provider'] ?? 'GATEWAY'} · ${c['providerBatchRef'] ?? shortId('${c['id']}')}',
                    status: '${c['state'] ?? 'POSTED'}',
                    lines: [
                      (
                        'Date',
                        fmtDate('${c['settlementDate'] ?? c['clearingDate'] ?? ''}'),
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
            ]

            // 2, 3, 4. RECEIPTS / DISBURSEMENTS / REFUNDS (`image-33..35.png`)
            // Columns: Settlement Date | Doc # | Party | Direction | Method | Amount | Allocated / Unallocated | Reference | State
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'SETTLEMENT DATE · DOC # · PARTY · DIRECTION · METHOD · AMOUNT · ALLOCATED / UNALLOCATED · REFERENCE · STATE',
                  style: T.caps(10),
                ),
              ),
              const SizedBox(height: 8),
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
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
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
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
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
