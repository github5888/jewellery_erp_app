import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../billing/billing_controller.dart';
import '../supply/supply_production_screens.dart';

/// Old Gold Exchange (`M4 RETAIL CONTROLS · Old Metal & Exchange` — `pos.hrpocket.in/old-metal`,
/// `image-9.png`, `image-10.png`, `image-11.png`, `image-12.png`) formatted cleanly for mobile phones
/// and wired to live `/old-metal`, `/parties`, `/materials`, `/rates`, `/inventory`, `/sales`,
/// and `/accounting/workspace` endpoints.
class OldGoldScreen extends StatefulWidget {
  const OldGoldScreen({super.key, this.pickMode = false});
  final bool pickMode;

  @override
  State<OldGoldScreen> createState() => _OldGoldScreenState();
}

class _IntakeLineDraft {
  _IntakeLineDraft({
    String defaultMetalId = '',
    String defaultPurityId = '',
    String defaultLocationId = '',
  })  : descCtrl = TextEditingController(),
        metalIdCtrl = TextEditingController(text: defaultMetalId),
        purityIdCtrl = TextEditingController(text: defaultPurityId),
        locationIdCtrl = TextEditingController(text: defaultLocationId),
        grossGramsCtrl = TextEditingController(),
        nonMetalDeductCtrl = TextEditingController(text: '0.000000');

  final TextEditingController descCtrl;
  final TextEditingController metalIdCtrl;
  final TextEditingController purityIdCtrl;
  final TextEditingController locationIdCtrl;
  final TextEditingController grossGramsCtrl;
  final TextEditingController nonMetalDeductCtrl;

  void dispose() {
    descCtrl.dispose();
    metalIdCtrl.dispose();
    purityIdCtrl.dispose();
    locationIdCtrl.dispose();
    grossGramsCtrl.dispose();
    nonMetalDeductCtrl.dispose();
  }
}

class _OldGoldScreenState extends State<OldGoldScreen> {
  static const _uuid = Uuid();

  final _search = TextEditingController();
  // 'INTAKE' | 'POLICY' | 'PURCHASE' | 'SETTLEMENT'
  late String _tab = widget.pickMode ? 'PURCHASE' : 'INTAKE';
  // Sub-mode inside SETTLEMENT: 'CONTRA' (`Exchange against sale`) | 'PAYOUT' (`Pay customer`)
  String _settlementMode = 'CONTRA';

  List<Map<String, dynamic>> _intakes = [];
  List<Map<String, dynamic>> _policies = [];
  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _settlements = [];
  List<LookupOption> _rateVersionOpts = [];
  WorkspaceLookup _lk = WorkspaceLookup();

  bool _loading = true;
  bool _busy = false;
  String? _error;

  // ---------------------------------------------------------------------------
  // 1. INTAKE (`image-9.png` — Receive Customer Scrap Metal Custody)
  // ---------------------------------------------------------------------------
  final _inCustomerId = TextEditingController();
  final _inConsentUuid = TextEditingController();
  final _inDate = TextEditingController(text: todayIso());
  final _inAckRef = TextEditingController();
  final List<_IntakeLineDraft> _inLines = [_IntakeLineDraft()];

  // ---------------------------------------------------------------------------
  // 2. POLICY (`image-10.png` — Versioned Old Metal Policy)
  // ---------------------------------------------------------------------------
  final _polCode = TextEditingController();
  final _polName = TextEditingController();
  final _polMinFineness = TextEditingController(text: '500.000000');
  final _polFineDeduct = TextEditingController(text: '0.00000000');
  final _polRateDiscount = TextEditingController(text: '0.00000000');
  final _polEffFrom = TextEditingController(text: todayIso());
  final _polEffTo = TextEditingController();

  // ---------------------------------------------------------------------------
  // 3. PURCHASE (`image-11.png` — Acquisition Posting Config)
  // ---------------------------------------------------------------------------
  final _purDate = TextEditingController(text: todayIso());
  final _purPolicyId = TextEditingController();
  final _purRateVerId = TextEditingController();
  final _purUnitId = TextEditingController();
  final _purTargetLocId = TextEditingController();
  final _purInvAcctId = TextEditingController();
  final _purPayAcctId = TextEditingController();
  final _purPeriodId = TextEditingController();
  final _purDocSeriesId = TextEditingController();
  final _purJournalSeriesId = TextEditingController();

  // ---------------------------------------------------------------------------
  // 4. SETTLEMENT (`image-12.png` — Exchange against sale & Pay customer)
  // ---------------------------------------------------------------------------
  final _contraPurchaseId = TextEditingController();
  final _contraSalesInvId = TextEditingController();
  final _contraAmount = TextEditingController();
  final _contraDate = TextEditingController(text: todayIso());
  final _contraPeriodId = TextEditingController();
  final _contraDocSeriesId = TextEditingController();
  final _contraJournalSeriesId = TextEditingController();

  final _payPurchaseId = TextEditingController();
  final _payAmount = TextEditingController();
  String _payMethod = 'BANK_TRANSFER';
  final _payDate = TextEditingController(text: todayIso());
  final _payInstrumentAcctId = TextEditingController();
  final _payReference = TextEditingController();
  final _payPeriodId = TextEditingController();
  final _payDocSeriesId = TextEditingController();
  final _payJournalSeriesId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWorkspace();
  }

  @override
  void dispose() {
    for (final l in _inLines) {
      l.dispose();
    }
    for (final c in [
      _search,
      _inCustomerId,
      _inConsentUuid,
      _inDate,
      _inAckRef,
      _polCode,
      _polName,
      _polMinFineness,
      _polFineDeduct,
      _polRateDiscount,
      _polEffFrom,
      _polEffTo,
      _purDate,
      _purPolicyId,
      _purRateVerId,
      _purUnitId,
      _purTargetLocId,
      _purInvAcctId,
      _purPayAcctId,
      _purPeriodId,
      _purDocSeriesId,
      _purJournalSeriesId,
      _contraPurchaseId,
      _contraSalesInvId,
      _contraAmount,
      _contraDate,
      _contraPeriodId,
      _contraDocSeriesId,
      _contraJournalSeriesId,
      _payPurchaseId,
      _payAmount,
      _payDate,
      _payInstrumentAcctId,
      _payReference,
      _payPeriodId,
      _payDocSeriesId,
      _payJournalSeriesId,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _pick(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty && '$v' != 'null') return '$v';
    }
    return fallback;
  }

  Future<void> _loadWorkspace() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait<dynamic>([
        api.get('/old-metal').catchError((Object e) {
          if (e is ApiException && (e.status == 404 || e.code == 'HTTP_ERROR')) {
            return <String, dynamic>{};
          }
          throw e;
        }),
        api.get('/rates').catchError((_) => <String, dynamic>{}),
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeInventory: true,
          includeMaterials: true,
          includeAccounting: true,
          includeSales: true,
        ),
      ]);
      if (!mounted) return;

      final d = results[0];
      final ratesRaw = results[1];
      final lk = results[2] as WorkspaceLookup;

      var intakes = <Map<String, dynamic>>[];
      var policies = <Map<String, dynamic>>[];
      var purchases = <Map<String, dynamic>>[];
      var settlements = <Map<String, dynamic>>[];

      if (d is Map) {
        intakes = asList(
          d,
          keys: const ['intakes', 'custodyIntakes', 'scrapIntakes'],
        );
        policies = asList(
          d,
          keys: const ['policies', 'policyVersions', 'deductionPolicies'],
        );
        purchases = asList(
          d,
          keys: const ['purchases', 'purchaseVouchers', 'vouchers', 'oldMetalPurchases'],
        );
        settlements = asList(
          d,
          keys: const ['settlements', 'contraSettlements', 'payouts'],
        );
      } else if (d is List) {
        purchases = asList(d);
      }

      // Published Rate Versions for Purchase tab (`Board Spot Rate Version`)
      final rvOpts = <LookupOption>[];
      for (final book in asList(ratesRaw, keys: const ['rateBooks', 'books', 'items'])) {
        final bookName = '${book['name'] ?? book['code'] ?? 'Rate Book'}';
        for (final v in asList(book['versions'])) {
          if ('${v['state']}' == 'PUBLISHED') {
            final vid = '${v['id'] ?? ''}';
            if (vid.isNotEmpty) {
              rvOpts.add(
                LookupOption(
                  id: vid,
                  label: '$bookName · v${v['versionNumber'] ?? 1} (PUBLISHED)',
                  raw: v,
                ),
              );
            }
          }
        }
      }

      // Populate smart workspace defaults for dropdowns when empty
      for (final ln in _inLines) {
        if (ln.metalIdCtrl.text.isEmpty && lk.metals.isNotEmpty) {
          ln.metalIdCtrl.text = lk.metals.first.id;
          final p = lk.puritiesForMetal(ln.metalIdCtrl.text);
          if (p.isNotEmpty) ln.purityIdCtrl.text = p.first.id;
        }
        if (ln.locationIdCtrl.text.isEmpty && lk.locations.isNotEmpty) {
          ln.locationIdCtrl.text = lk.locations.first.id;
        }
      }

      final approvedPol = policies
          .where((p) =>
              '${p['state'] ?? p['status'] ?? ''}'.toUpperCase() == 'APPROVED' ||
              '${p['state'] ?? p['status'] ?? ''}'.toUpperCase() == 'PUBLISHED' ||
              '${p['state'] ?? p['status'] ?? ''}'.toUpperCase() == 'ACTIVE')
          .firstOrNull;
      if (_purPolicyId.text.isEmpty && (approvedPol != null || policies.isNotEmpty)) {
        _purPolicyId.text = '${(approvedPol ?? policies.first)['id'] ?? ''}';
      }
      if (_purRateVerId.text.isEmpty && rvOpts.isNotEmpty) {
        _purRateVerId.text = rvOpts.first.id;
      }
      if (_purUnitId.text.isEmpty && lk.units.isNotEmpty) {
        _purUnitId.text = lk.units.first.id;
      }
      if (_purTargetLocId.text.isEmpty && lk.locations.isNotEmpty) {
        _purTargetLocId.text = lk.locations.first.id;
      }
      if (_purInvAcctId.text.isEmpty) {
        final invAccts = lk.accountsByControl(const ['INVENTORY', 'ASSET']);
        if (invAccts.isNotEmpty) _purInvAcctId.text = invAccts.first.id;
      }
      if (_purPayAcctId.text.isEmpty) {
        final payAccts =
            lk.accountsByControl(const ['SUPPLIER_PAYABLE', 'CUSTOMER_PAYABLE', 'LIABILITY']);
        if (payAccts.isNotEmpty) _purPayAcctId.text = payAccts.first.id;
      }

      final openPeriods = lk.openPeriods();
      final jvSeries = lk.seriesFor(const ['JOURNAL']);
      final docSeries = lk.series;

      for (final ctrl in [_purPeriodId, _contraPeriodId, _payPeriodId]) {
        if (ctrl.text.isEmpty && openPeriods.isNotEmpty) {
          ctrl.text = openPeriods.first.id;
        }
      }
      for (final ctrl in [
        _purJournalSeriesId,
        _contraJournalSeriesId,
        _payJournalSeriesId,
      ]) {
        if (ctrl.text.isEmpty && jvSeries.isNotEmpty) {
          ctrl.text = jvSeries.first.id;
        }
      }
      for (final ctrl in [_purDocSeriesId, _contraDocSeriesId, _payDocSeriesId]) {
        if (ctrl.text.isEmpty && docSeries.isNotEmpty) {
          ctrl.text = docSeries.first.id;
        }
      }
      if (_payInstrumentAcctId.text.isEmpty) {
        final bankOrCash = lk.accountsByControl(const ['BANK', 'CASH', 'ASSET']);
        if (bankOrCash.isNotEmpty) _payInstrumentAcctId.text = bankOrCash.first.id;
      }

      setState(() {
        _intakes = intakes;
        _policies = policies;
        _purchases = purchases;
        _settlements = settlements;
        _rateVersionOpts = rvOpts;
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _postWithFallbacks(
    List<String> candidatePaths,
    Map<String, dynamic> body,
    String okMsg, {
    VoidCallback? onSuccessReset,
  }) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      ApiException? lastErr;
      var succeeded = false;
      for (var i = 0; i < candidatePaths.length; i++) {
        try {
          await api.post(
            candidatePaths[i],
            idempotencyKey: _uuid.v4(),
            body: body,
          );
          succeeded = true;
          break;
        } on ApiException catch (e) {
          lastErr = e;
          final isNotFound = e.status == 404 || e.code == 'HTTP_ERROR';
          if (!isNotFound || i == candidatePaths.length - 1) {
            rethrow;
          }
        }
      }
      if (!succeeded && lastErr != null) throw lastErr;
      onSuccessReset?.call();
      if (!mounted) return;
      toast(context, okMsg);
      await _loadWorkspace();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // MUTATIONS ACROSS ALL 4 TABS (`INTAKE`, `POLICY`, `PURCHASE`, `SETTLEMENT`)
  // ---------------------------------------------------------------------------

  Future<void> _submitReceiveCustody() async {
    if (_inCustomerId.text.trim().isEmpty) {
      setState(() => _error = 'Select a Customer before receiving scrap metal custody.');
      return;
    }
    if (_inConsentUuid.text.trim().isEmpty) {
      setState(
        () => _error =
            'Enter or tap the generate icon to populate Consent Record UUID.',
      );
      return;
    }
    if (_inAckRef.text.trim().length < 2) {
      setState(() => _error = 'Enter Customer Ack Ref (Acknowledgement reference).');
      return;
    }
    for (final l in _inLines) {
      if (l.descCtrl.text.trim().length < 2 ||
          l.metalIdCtrl.text.trim().isEmpty ||
          l.purityIdCtrl.text.trim().isEmpty ||
          l.locationIdCtrl.text.trim().isEmpty ||
          !isValidWeight(l.grossGramsCtrl.text)) {
        setState(
          () => _error =
              'Complete Description, Metal, Declared Purity, Custody Location, and Gross Grams on every intake line.',
        );
        return;
      }
    }

    await _postWithFallbacks(
      const ['/old-metal/intakes', '/old-metal/custody-intakes'],
      {
        'customerPartyId': _inCustomerId.text.trim(),
        'consentRecordId': _inConsentUuid.text.trim(),
        'intakeDate': _inDate.text.trim().isEmpty ? todayIso() : _inDate.text.trim(),
        'customerAcknowledgementRef': _inAckRef.text.trim(),
        'reason':
            'Received customer old metal custody against signed acknowledgement ${_inAckRef.text.trim()}.',
        'lines': [
          for (final l in _inLines)
            {
              'description': l.descCtrl.text.trim(),
              'metalId': l.metalIdCtrl.text.trim(),
              'declaredPurityGradeId': l.purityIdCtrl.text.trim(),
              'custodyLocationId': l.locationIdCtrl.text.trim(),
              'grossWeightGrams': normWeight6(l.grossGramsCtrl.text),
              'nonMetalDeductionGrams': normWeight6(
                l.nonMetalDeductCtrl.text.trim().isEmpty
                    ? '0'
                    : l.nonMetalDeductCtrl.text.trim(),
              ),
            },
        ],
      },
      'Customer scrap metal custody received.',
      onSuccessReset: () {
        _inAckRef.clear();
        _inConsentUuid.clear();
        for (var i = _inLines.length - 1; i >= 1; i--) {
          _inLines[i].dispose();
          _inLines.removeAt(i);
        }
        _inLines.first.descCtrl.clear();
        _inLines.first.grossGramsCtrl.clear();
        _inLines.first.nonMetalDeductCtrl.text = '0.000000';
      },
    );
  }

  Future<void> _submitCreatePolicyVersion() async {
    if (_polCode.text.trim().isEmpty || _polName.text.trim().length < 2) {
      setState(() => _error = 'Enter Policy code and Policy name.');
      return;
    }
    await _postWithFallbacks(
      const ['/old-metal/policies', '/old-metal/policy-versions'],
      {
        'code': _polCode.text.trim().toUpperCase(),
        'name': _polName.text.trim(),
        'minimumFinenessPerThousand': _polMinFineness.text.trim().isEmpty
            ? '500.000000'
            : _polMinFineness.text.trim(),
        'fineDeductionRatio': _polFineDeduct.text.trim().isEmpty
            ? '0.00000000'
            : _polFineDeduct.text.trim(),
        'rateDiscountRatio': _polRateDiscount.text.trim().isEmpty
            ? '0.00000000'
            : _polRateDiscount.text.trim(),
        'effectiveFrom':
            _polEffFrom.text.trim().isEmpty ? todayIso() : _polEffFrom.text.trim(),
        if (_polEffTo.text.trim().isNotEmpty) 'effectiveTo': _polEffTo.text.trim(),
        'reason':
            'Created old-metal buyback deduction policy ${_polCode.text.trim().toUpperCase()}.',
      },
      'Old metal policy version created.',
      onSuccessReset: () {
        _polCode.clear();
        _polName.clear();
      },
    );
  }

  Future<void> _approvePolicy(Map<String, dynamic> pol) async {
    final id = '${pol['id'] ?? ''}';
    if (id.isEmpty) return;
    await _postWithFallbacks(
      [
        '/old-metal/policies/$id/approve',
        '/old-metal/policy-versions/$id/approve',
      ],
      {
        'expectedVersion': asInt(pol['version'], fallback: 1),
        'reason': 'Approved old-metal deduction and buyback policy version.',
      },
      'Old metal policy approved.',
    );
  }

  Future<void> _acquirePurchaseFromIntake(Map<String, dynamic> intake) async {
    final intakeId = '${intake['id'] ?? ''}';
    if (intakeId.isEmpty) return;
    if (_purPolicyId.text.trim().isEmpty ||
        _purRateVerId.text.trim().isEmpty ||
        _purUnitId.text.trim().isEmpty ||
        _purTargetLocId.text.trim().isEmpty ||
        _purInvAcctId.text.trim().isEmpty ||
        _purPayAcctId.text.trim().isEmpty ||
        _purPeriodId.text.trim().isEmpty ||
        _purDocSeriesId.text.trim().isEmpty ||
        _purJournalSeriesId.text.trim().isEmpty) {
      setState(
        () => _error =
            'Select Policy, Rate Version, Weight Unit, Target Location, GL Accounts, Posting Period, Document Series, and Journal Series above.',
      );
      return;
    }

    await _postWithFallbacks(
      [
        '/old-metal/purchases',
        '/old-metal/intakes/$intakeId/purchase',
        '/old-metal/purchase-vouchers',
      ],
      {
        'intakeId': intakeId,
        'expectedIntakeVersion': asInt(intake['version'], fallback: 1),
        'purchaseDate': _purDate.text.trim().isEmpty ? todayIso() : _purDate.text.trim(),
        'policyVersionId': _purPolicyId.text.trim(),
        'policyId': _purPolicyId.text.trim(),
        'rateVersionId': _purRateVerId.text.trim(),
        'unitId': _purUnitId.text.trim(),
        'targetLocationId': _purTargetLocId.text.trim(),
        'inventoryAccountId': _purInvAcctId.text.trim(),
        'payableAccountId': _purPayAcctId.text.trim(),
        'postingPeriodId': _purPeriodId.text.trim(),
        'documentSeriesId': _purDocSeriesId.text.trim(),
        'journalSeriesId': _purJournalSeriesId.text.trim(),
        'reason': 'Posted old-metal purchase voucher from assay-approved customer intake.',
      },
      'Old metal purchase voucher posted.',
    );
  }

  Future<void> _submitContraSettlement() async {
    final purId = _contraPurchaseId.text.trim();
    if (purId.isEmpty ||
        _contraSalesInvId.text.trim().isEmpty ||
        !isValidAmount(_contraAmount.text) ||
        _contraPeriodId.text.trim().isEmpty ||
        _contraDocSeriesId.text.trim().isEmpty ||
        _contraJournalSeriesId.text.trim().isEmpty) {
      setState(
        () => _error =
            'Complete oldMetalPurchaseId, salesInvoiceId, amount, settlement date, postingPeriodId, documentSeriesId, and journalSeriesId.',
      );
      return;
    }

    await _postWithFallbacks(
      [
        '/old-metal/settlements/sale-contra',
        '/old-metal/purchases/$purId/settle-against-sale',
        '/old-metal/contra-settlements',
      ],
      {
        'oldMetalPurchaseId': purId,
        'salesInvoiceId': _contraSalesInvId.text.trim(),
        'amount': normAmount(_contraAmount.text),
        'settlementDate':
            _contraDate.text.trim().isEmpty ? todayIso() : _contraDate.text.trim(),
        'postingPeriodId': _contraPeriodId.text.trim(),
        'documentSeriesId': _contraDocSeriesId.text.trim(),
        'journalSeriesId': _contraJournalSeriesId.text.trim(),
        'reason': 'Explicit contra settlement of old-metal purchase credit against showroom sale.',
      },
      'Contra sale settlement posted.',
      onSuccessReset: () => _contraAmount.clear(),
    );
  }

  Future<void> _submitCustomerPayout() async {
    final purId = _payPurchaseId.text.trim();
    if (purId.isEmpty ||
        !isValidAmount(_payAmount.text) ||
        _payInstrumentAcctId.text.trim().isEmpty ||
        _payPeriodId.text.trim().isEmpty ||
        _payDocSeriesId.text.trim().isEmpty ||
        _payJournalSeriesId.text.trim().isEmpty) {
      setState(
        () => _error =
            'Complete oldMetalPurchaseId, amount, method, date, instrumentAccountId, postingPeriodId, documentSeriesId, and journalSeriesId.',
      );
      return;
    }

    await _postWithFallbacks(
      [
        '/old-metal/settlements/payouts',
        '/old-metal/purchases/$purId/payout',
        '/old-metal/payouts',
      ],
      {
        'oldMetalPurchaseId': purId,
        'amount': normAmount(_payAmount.text),
        'method': _payMethod,
        'settlementDate':
            _payDate.text.trim().isEmpty ? todayIso() : _payDate.text.trim(),
        'instrumentAccountId': _payInstrumentAcctId.text.trim(),
        if (_payReference.text.trim().isNotEmpty)
          'paymentReference': _payReference.text.trim(),
        'postingPeriodId': _payPeriodId.text.trim(),
        'documentSeriesId': _payDocSeriesId.text.trim(),
        'journalSeriesId': _payJournalSeriesId.text.trim(),
        'reason': 'Direct customer payout settlement against posted old-metal purchase.',
      },
      'Customer old-metal payout posted.',
      onSuccessReset: () {
        _payAmount.clear();
        _payReference.clear();
      },
    );
  }

  void _attachPurchaseToPosBill(Map<String, dynamic> v) {
    final id = _pick(v, ['id', 'voucherId', 'documentNumber', 'voucherNumber']);
    if (id.isEmpty) {
      toast(context, 'Purchase voucher ID unavailable.', error: true);
      return;
    }
    final amt = normAmount(
      _pick(
        v,
        ['outstandingAmount', 'payableAmount', 'netPayableAmount', 'totalValuation', 'amount'],
        '0.00',
      ),
    );
    final docNo = _pick(v, ['documentNumber', 'voucherNumber', 'code'], shortId(id));
    final fine = _pick(v, ['netFineWeightGrams', 'fineWeightGrams', 'netPureGrams']);
    final credit = ExchangeCredit(
      voucherId: id,
      label: 'Old Metal Voucher $docNo',
      amount: amt,
      fineWeight: fine,
    );
    context.read<BillingController>().addExchange(credit);
    toast(context, 'Old metal credit ${inr(amt)} attached to POS Quick Bill.');
    if (widget.pickMode) {
      Navigator.pop(context, credit);
    }
  }

  Future<void> _showApproveAssaySheet(Map<String, dynamic> intake) async {
    final lines = asList(intake['lines']);
    final purityCtrl = TextEditingController(
      text: lines.isNotEmpty
          ? '${lines.first['declaredPurityGradeId'] ?? lines.first['assayedPurityGradeId'] ?? ''}'
          : (_lk.purityGrades.isNotEmpty ? _lk.purityGrades.first.id : ''),
    );
    final finenessCtrl = TextEditingController(text: '916.000000');
    final meltLossCtrl = TextEditingController(text: '0.000000');
    final assayRefCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool sheetBusy = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Assay & Approve Intake',
                style: T.display(20),
              ),
              const SizedBox(height: 4),
              Text(
                'Record XRF / touchstone assay results and approve customer scrap intake for acquisition.',
                style: T.body(12.2, color: Pal.muted),
              ),
              const SizedBox(height: 12),
              LookupField(
                label: 'Assayed Purity Grade',
                controller: purityCtrl,
                options: _lk.purityGrades,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SaasField(
                      label: 'Assayed Fineness ‰',
                      controller: finenessCtrl,
                      mono: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SaasField(
                      label: 'Melting / Dust Loss g',
                      controller: meltLossCtrl,
                      mono: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Assay Certificate / XRF Ref',
                controller: assayRefCtrl,
                hint: 'XRF-ASSAY-01',
                mono: true,
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Assay Approval Reason (min 5 chars)',
                controller: reasonCtrl,
                hint: 'Verified XRF reading with customer sign-off',
              ),
              if (sheetErr != null) ...[
                const SizedBox(height: 10),
                Text(sheetErr!, style: T.body(12.5, color: Pal.danger, w: FontWeight.w700)),
              ],
              const SizedBox(height: 14),
              RoyalGoldButton(
                busy: sheetBusy,
                label: 'Approve Assay',
                onPressed: sheetBusy
                    ? null
                    : () async {
                        if (reasonCtrl.text.trim().length < 5) {
                          setLocal(() => sheetErr = 'Enter assay approval reason (min 5 chars).');
                          return;
                        }
                        setLocal(() {
                          sheetBusy = true;
                          sheetErr = null;
                        });
                        final intakeId = '${intake['id']}';
                        final api = context.read<ApiClient>();
                        try {
                          final payload = <String, dynamic>{
                            'expectedVersion': asInt(intake['version'], fallback: 1),
                            'assayedDate': todayIso(),
                            if (assayRefCtrl.text.trim().isNotEmpty)
                              'assayReference': assayRefCtrl.text.trim(),
                            'reason': reasonCtrl.text.trim(),
                            if (lines.isNotEmpty)
                              'lines': [
                                for (final ln in lines)
                                  {
                                    if (ln['id'] != null) 'intakeLineId': '${ln['id']}',
                                    'assayedPurityGradeId': purityCtrl.text.trim(),
                                    'assayedFinenessPerThousand': finenessCtrl.text.trim(),
                                    'meltingLossGrams': normWeight6(
                                      meltLossCtrl.text.trim().isEmpty
                                          ? '0'
                                          : meltLossCtrl.text.trim(),
                                    ),
                                  },
                              ],
                          };
                          final paths = [
                            '/old-metal/intakes/$intakeId/approve-assay',
                            '/old-metal/intakes/$intakeId/assay',
                            '/old-metal/intakes/$intakeId/approve',
                          ];
                          ApiException? lastE;
                          var ok = false;
                          for (var i = 0; i < paths.length; i++) {
                            try {
                              await api.post(paths[i], idempotencyKey: _uuid.v4(), body: payload);
                              ok = true;
                              break;
                            } on ApiException catch (e) {
                              lastE = e;
                              if ((e.status != 404 && e.code != 'HTTP_ERROR') ||
                                  i == paths.length - 1) {
                                rethrow;
                              }
                            }
                          }
                          if (!ok && lastE != null) throw lastE;
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          toast(context, 'Intake assay approved.');
                          await _loadWorkspace();
                        } on ApiException catch (e) {
                          setLocal(() => sheetErr = e.message);
                        } finally {
                          if (ctx.mounted) setLocal(() => sheetBusy = false);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );

    purityCtrl.dispose();
    finenessCtrl.dispose();
    meltLossCtrl.dispose();
    assayRefCtrl.dispose();
    reasonCtrl.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999');
    final bullionActive = gold999 != null && decOrZero(gold999.sell) > Decimal.zero;
    final showroomContext = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    return LuxuryModuleScaffold(
      title: 'Old Gold Exchange',
      icon: Icons.recycling_rounded,
      searchController: _search,
      searchHint: 'Search customer, ack ref, policy or voucher...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: 'Refresh Old Metal Workspace',
          onPressed: _loadWorkspace,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _error = null;
        }),
        tabs: const [
          ('INTAKE', 'INTAKE'),
          ('POLICY', 'POLICY'),
          ('PURCHASE', 'PURCHASE'),
          ('SETTLEMENT', 'SETTLEMENT'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _loadWorkspace,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
          children: [
            // Website Sub-Header (`M4 RETAIL CONTROLS · Old Metal & Exchange` from `image-9..12.png`)
            Panel(
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'M4 RETAIL CONTROLS',
                    style: T.caps(10, color: const Color(0xFFB45309), letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Old Metal & Exchange',
                    style: T.body(17, color: Pal.ink, w: FontWeight.w800),
                  ),
                  if (showroomContext.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      showroomContext,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.body(11.8, color: Pal.muted, w: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    'Customer custody, assay approval, versioned deductions, acquisition posting and explicit sale settlement.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const MaterialsRatesScreen(),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: bullionActive ? const Color(0xFFFBF3DC) : Pal.warnWash,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(
                          color: bullionActive
                              ? const Color(0xFFE5CC82)
                              : Pal.warn.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.toll_rounded,
                            size: 13.5,
                            color: bullionActive ? Pal.goldDeep : Pal.warn,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            bullionActive
                                ? 'Bullion 24K: Fine 999 Board Active'
                                : 'Bullion 24K: Configure Rate Board',
                            style: T.body(
                              11.2,
                              color: bullionActive ? Pal.goldDeep : Pal.warn,
                              w: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!, onRetry: _loadWorkspace),
            ],

            const SizedBox(height: 12),

            if (_loading &&
                _intakes.isEmpty &&
                _policies.isEmpty &&
                _purchases.isEmpty) ...[
              const Panel(child: Skeleton(height: 160)),
              const SizedBox(height: 12),
              const Panel(child: Skeleton(height: 110)),
            ] else if (_tab == 'INTAKE') ...[
              _buildIntakeTab(),
            ] else if (_tab == 'POLICY') ...[
              _buildPolicyTab(),
            ] else if (_tab == 'PURCHASE') ...[
              _buildPurchaseTab(),
            ] else ...[
              _buildSettlementTab(),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: INTAKE (`image-9.png` — Receive Customer Scrap Metal Custody)
  // ---------------------------------------------------------------------------

  Widget _buildIntakeTab() {
    final q = _search.text.trim().toLowerCase();
    final fIntakes = _intakes.where((it) {
      if (q.isEmpty) return true;
      final hay =
          '${_pick(it, ['documentNumber', 'intakeNumber', 'customerAcknowledgementRef'])} ${asMap(it['customer'])['displayName'] ?? ''} ${_pick(it, ['state', 'status'])}'
              .toLowerCase();
      return hay.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasFormCard(
          title: 'Receive Customer Scrap Metal Custody',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LookupField(
                label: 'Customer',
                controller: _inCustomerId,
                options: _lk.parties,
                hint: 'Select Customer...',
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Consent Record UUID',
                controller: _inConsentUuid,
                hint: 'Old-metal consent UUID',
                mono: true,
                trailing: IconButton(
                  tooltip: 'Generate Consent UUID',
                  icon: const Icon(
                    Icons.auto_fix_high_rounded,
                    size: 18,
                    color: Pal.goldDeep,
                  ),
                  onPressed: () => setState(() => _inConsentUuid.text = _uuid.v4()),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DatePickField(
                      label: 'Intake Date',
                      controller: _inDate,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SaasField(
                      label: 'Customer Ack Ref',
                      controller: _inAckRef,
                      hint: 'Acknowledgement reference',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Dynamic Intake Lines (`+ Add intake line`)
              for (var i = 0; i < _inLines.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                Builder(builder: (_) {
                  final ln = _inLines[i];
                  final purities = _lk.puritiesForMetal(ln.metalIdCtrl.text.trim());
                  return SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Intake Line #${i + 1}',
                              style: T.body(12.2, color: Pal.goldDeep, w: FontWeight.w800),
                            ),
                            const Spacer(),
                            if (_inLines.length > 1)
                              TextButton(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Pal.danger,
                                ),
                                onPressed: () => setState(() {
                                  _inLines[i].dispose();
                                  _inLines.removeAt(i);
                                }),
                                child: const Text('Remove'),
                              ),
                          ],
                        ),
                        SaasField(
                          label: 'Description',
                          controller: ln.descCtrl,
                          hint: 'Description',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: LookupField(
                                label: 'Metal',
                                controller: ln.metalIdCtrl,
                                options: _lk.metals,
                                hint: 'Select Metal',
                                onSelected: (opt) {
                                  setState(() {
                                    ln.purityIdCtrl.clear();
                                    if (opt != null) {
                                      final p = _lk.puritiesForMetal(opt.id);
                                      if (p.isNotEmpty) ln.purityIdCtrl.text = p.first.id;
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LookupField(
                                label: 'Declared Purity',
                                controller: ln.purityIdCtrl,
                                options: purities.isNotEmpty ? purities : _lk.purityGrades,
                                hint: 'Select Purity',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LookupField(
                          label: 'Custody Location',
                          controller: ln.locationIdCtrl,
                          options: _lk.locations,
                          hint: 'Select Location',
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Gross Grams',
                                controller: ln.grossGramsCtrl,
                                hint: 'Gross grams',
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'Non-Metal Deduct',
                                controller: ln.nonMetalDeductCtrl,
                                hint: '0.000000',
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],

              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 38),
                  ),
                  onPressed: () {
                    final defMetal = _lk.metals.isNotEmpty ? _lk.metals.first.id : '';
                    final defPur = defMetal.isNotEmpty &&
                            _lk.puritiesForMetal(defMetal).isNotEmpty
                        ? _lk.puritiesForMetal(defMetal).first.id
                        : '';
                    final defLoc = _lk.locations.isNotEmpty ? _lk.locations.first.id : '';
                    setState(
                      () => _inLines.add(
                        _IntakeLineDraft(
                          defaultMetalId: defMetal,
                          defaultPurityId: defPur,
                          defaultLocationId: defLoc,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('Add intake line'),
                ),
              ),
              const SizedBox(height: 14),
              RoyalGoldButton(
                busy: _busy,
                label: 'Receive custody',
                onPressed: _busy ? null : _submitReceiveCustody,
              ),
            ],
          ),
        ),

        if (fIntakes.isNotEmpty) ...[
          SectionLabel('Customer Custody Intakes (${fIntakes.length})'),
          for (final it in fIntakes)
            Builder(builder: (_) {
              final st = _pick(it, ['state', 'status'], 'RECEIVED').toUpperCase();
              final canAssay = st == 'RECEIVED' ||
                  st == 'OPEN' ||
                  st == 'DRAFT' ||
                  st == 'PENDING_ASSAY';
              final isApproved = st.contains('APPROVED');
              return LuxuryRecordCard(
                icon: Icons.inbox_outlined,
                code: _pick(
                  it,
                  ['documentNumber', 'intakeNumber', 'customerAcknowledgementRef'],
                  shortId('${it['id'] ?? 'INT'}'),
                ),
                status: st,
                lines: [
                  ('Customer', '${asMap(it['customer'])['displayName'] ?? '-'}'),
                  if (_pick(it, ['intakeDate']).isNotEmpty)
                    ('Intake Date', fmtDate(_pick(it, ['intakeDate']))),
                  if (_pick(it, ['customerAcknowledgementRef']).isNotEmpty)
                    ('Ack Ref', _pick(it, ['customerAcknowledgementRef'])),
                ],
                amountLabel: 'Lines',
                amountValue: '${asList(it['lines']).length} item(s)',
                actions: [
                  if (canAssay)
                    GoldButton(
                      label: 'Approve Assay',
                      compact: true,
                      busy: _busy,
                      onPressed: () => _showApproveAssaySheet(it),
                    ),
                  if (isApproved)
                    GoldButton(
                      label: 'Proceed to Purchase',
                      compact: true,
                      onPressed: () => setState(() => _tab = 'PURCHASE'),
                    ),
                ],
              );
            }),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: POLICY (`image-10.png` — Create Version + Policy Table)
  // ---------------------------------------------------------------------------

  Widget _buildPolicyTab() {
    final q = _search.text.trim().toLowerCase();
    final fPolicies = _policies.where((p) {
      if (q.isEmpty) return true;
      return '${_pick(p, ['code', 'policyCode'])} ${_pick(p, ['name', 'policyName'])} ${_pick(p, ['state', 'status'])}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasFormCard(
          title: 'Versioned Old Metal Deduction Policy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: SaasField(
                      label: 'Policy code',
                      controller: _polCode,
                      hint: 'Policy code',
                      mono: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SaasField(
                      label: 'Policy name',
                      controller: _polName,
                      hint: 'Policy name',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Minimum fineness (‰)',
                controller: _polMinFineness,
                hint: '500.000000',
                mono: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SaasField(
                      label: 'Fine deduction',
                      controller: _polFineDeduct,
                      hint: '0.00000000',
                      mono: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SaasField(
                      label: 'Rate discount',
                      controller: _polRateDiscount,
                      hint: '0.00000000',
                      mono: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DatePickField(
                      label: 'Effective from',
                      controller: _polEffFrom,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DatePickField(
                      label: 'Effective to',
                      controller: _polEffTo,
                      optional: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RoyalGoldButton(
                busy: _busy,
                label: 'Create version',
                onPressed: _busy ? null : _submitCreatePolicyVersion,
              ),
            ],
          ),
        ),

        const SectionLabel(
          'Policies (Policy · Minimum · Fine deduction · Rate discount · State)',
        ),
        if (fPolicies.isEmpty)
          const SaasEmptyBox(
            'No old-metal deduction policies configured yet. Create & approve a policy version above.',
          )
        else
          for (final pol in fPolicies)
            Builder(builder: (_) {
              final st = _pick(pol, ['state', 'status'], 'DRAFT').toUpperCase();
              return LuxuryRecordCard(
                icon: Icons.rule_folder_outlined,
                code:
                    '${_pick(pol, ['code', 'policyCode'])} · ${_pick(pol, ['name', 'policyName'])}',
                status: st,
                lines: [
                  (
                    'Minimum Fineness',
                    '${_pick(pol, ['minimumFinenessPerThousand', 'minFineness'], '500.000000')}‰',
                  ),
                  (
                    'Fine Deduction',
                    _pick(pol, ['fineDeductionRatio', 'fineDeductionRate'], '0.00000000'),
                  ),
                  (
                    'Rate Discount',
                    _pick(pol, ['rateDiscountRatio', 'rateDiscountRate'], '0.00000000'),
                  ),
                  if (_pick(pol, ['effectiveFrom']).isNotEmpty)
                    ('Effective From', fmtDate(_pick(pol, ['effectiveFrom']))),
                ],
                actions: [
                  if (st == 'DRAFT')
                    GoldButton(
                      label: 'Approve',
                      compact: true,
                      busy: _busy,
                      onPressed: () => _approvePolicy(pol),
                    ),
                ],
              );
            }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: PURCHASE (`image-11.png` — 10 Config Fields + Assay-Approved Intakes + Vouchers)
  // ---------------------------------------------------------------------------

  Widget _buildPurchaseTab() {
    final policyOpts = _policies.map((p) {
      final id = '${p['id'] ?? ''}';
      return LookupOption(
        id: id,
        label:
            '${_pick(p, ['code', 'policyCode'])} · ${_pick(p, ['name', 'policyName'])} (${_pick(p, ['state', 'status'], 'DRAFT')})',
        raw: p,
      );
    }).where((o) => o.id.isNotEmpty).toList();

    final approvedIntakes = _intakes.where((it) {
      final st = _pick(it, ['state', 'status']).toUpperCase();
      return st.contains('APPROVED') && !st.contains('PURCHASED');
    }).toList();

    final q = _search.text.trim().toLowerCase();
    final fPurchases = _purchases.where((v) {
      if (q.isEmpty) return true;
      return '${_pick(v, ['documentNumber', 'voucherNumber', 'code'])} ${asMap(v['customer'])['displayName'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 10 Acquisition Posting Config Fields (`image-11.png`)
        SaasFormCard(
          title: 'Old Metal Purchase Posting Config',
          subtitle:
              'Configure policy, spot rate version, custody vault, and GL control accounts to acquire assay-approved intakes.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DatePickField(
                label: 'Purchase Date',
                controller: _purDate,
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Old Metal Policy',
                controller: _purPolicyId,
                options: policyOpts,
                hint: 'Select Policy...',
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Board Spot Rate Version',
                controller: _purRateVerId,
                options: _rateVersionOpts,
                hint: 'Select Rate Version...',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: LookupField(
                      label: 'Weight Unit',
                      controller: _purUnitId,
                      options: _lk.units,
                      hint: 'Select Unit...',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LookupField(
                      label: 'Target Inventory Location',
                      controller: _purTargetLocId,
                      options: _lk.locations,
                      hint: 'Select Location...',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Inventory Asset Account',
                controller: _purInvAcctId,
                options: _lk.accounts,
                hint: 'Select Inventory Account...',
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Payable Account',
                controller: _purPayAcctId,
                options: _lk.accounts,
                hint: 'Select Payable Account...',
              ),
              const SizedBox(height: 10),
              LookupField(
                label: 'Posting Period',
                controller: _purPeriodId,
                options: _lk.openPeriods().isNotEmpty ? _lk.openPeriods() : _lk.periods,
                hint: 'Select Period...',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: LookupField(
                      label: 'Document Series',
                      controller: _purDocSeriesId,
                      options: _lk.series,
                      hint: 'Select Document Series...',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LookupField(
                      label: 'Journal Series',
                      controller: _purJournalSeriesId,
                      options: _lk.seriesFor(const ['JOURNAL']).isNotEmpty
                          ? _lk.seriesFor(const ['JOURNAL'])
                          : _lk.series,
                      hint: 'Select Journal Series...',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Table 1: Assay-approved intake (`image-11.png` middle section)
        const SectionLabel(
          'Assay-approved intake (Intake · Customer · Fine weight · Action)',
        ),
        if (approvedIntakes.isEmpty)
          const SaasEmptyBox(
            'No assay-approved intakes awaiting purchase posting. Receive custody & approve assay in INTAKE first.',
          )
        else
          for (final it in approvedIntakes)
            LuxuryRecordCard(
              icon: Icons.verified_outlined,
              code: _pick(
                it,
                ['documentNumber', 'intakeNumber', 'customerAcknowledgementRef'],
                shortId('${it['id'] ?? 'INT'}'),
              ),
              status: _pick(it, ['state', 'status'], 'ASSAY_APPROVED'),
              lines: [
                ('Customer', '${asMap(it['customer'])['displayName'] ?? '-'}'),
              ],
              amountLabel: 'Fine Weight',
              amountValue: fineGrams(
                _pick(it, ['assayedFineWeightGrams', 'totalFineWeightGrams'], '0.000000'),
              ),
              actions: [
                GoldButton(
                  label: 'Post Purchase',
                  compact: true,
                  busy: _busy,
                  onPressed: () => _acquirePurchaseFromIntake(it),
                ),
              ],
            ),

        // Table 2: Posted Purchase Vouchers (`Voucher · Customer · Gross · Deductions · Payable · Outstanding`)
        const SectionLabel(
          'Old Metal Vouchers (Voucher · Customer · Gross · Deductions · Payable · Outstanding)',
        ),
        if (fPurchases.isEmpty)
          const SaasEmptyBox('No old-metal purchase vouchers posted yet.')
        else
          for (final v in fPurchases)
            Builder(builder: (_) {
              final vid = '${v['id'] ?? v['voucherId'] ?? ''}';
              final payable = _pick(
                v,
                ['payableAmount', 'netPayableAmount', 'totalValuation', 'amount'],
                '0.00',
              );
              final outstanding = _pick(
                v,
                ['outstandingAmount', 'openAmount', 'balanceAmount'],
                payable,
              );
              return LuxuryRecordCard(
                icon: Icons.recycling_rounded,
                code: _pick(
                  v,
                  ['documentNumber', 'voucherNumber', 'code'],
                  shortId(vid.isEmpty ? 'OMV' : vid),
                ),
                status: _pick(v, ['state', 'status'], 'POSTED'),
                lines: [
                  (
                    'Customer',
                    '${asMap(v['customer'])['displayName'] ?? v['customerName'] ?? '-'}',
                  ),
                  (
                    'Gross / Deductions',
                    '${grams(_pick(v, ['grossWeightGrams'], '0'))} · Deduct ${_pick(v, ['deductionWeightGrams', 'deductionAmount'], '0')}',
                  ),
                  ('Payable', inr(payable)),
                ],
                amountLabel: 'Outstanding',
                amountValue: inr(outstanding),
                actions: [
                  GoldButton(
                    label: 'Settle',
                    compact: true,
                    onPressed: () => setState(() {
                      _contraPurchaseId.text = vid;
                      _contraAmount.text = normAmount(outstanding);
                      _payPurchaseId.text = vid;
                      _payAmount.text = normAmount(outstanding);
                      _tab = 'SETTLEMENT';
                    }),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 35),
                    ),
                    onPressed: () => _attachPurchaseToPosBill(v),
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 15),
                    label: const Text('Attach to POS'),
                  ),
                ],
              );
            }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: SETTLEMENT (`image-12.png` — Exchange against sale & Pay customer)
  // ---------------------------------------------------------------------------

  Widget _buildSettlementTab() {
    final purchaseOpts = _purchases.map((v) {
      final id = '${v['id'] ?? v['voucherId'] ?? ''}';
      final docNo = _pick(v, ['documentNumber', 'voucherNumber', 'code'], shortId(id));
      final outAmt = _pick(
        v,
        ['outstandingAmount', 'payableAmount', 'totalValuation', 'amount'],
        '0.00',
      );
      return LookupOption(
        id: id,
        label: '$docNo · ${asMap(v['customer'])['displayName'] ?? 'Customer'} · ${inr(outAmt)}',
        raw: v,
      );
    }).where((o) => o.id.isNotEmpty).toList();

    final openPeriods =
        _lk.openPeriods().isNotEmpty ? _lk.openPeriods() : _lk.periods;
    final journalSeries = _lk.seriesFor(const ['JOURNAL']).isNotEmpty
        ? _lk.seriesFor(const ['JOURNAL'])
        : _lk.series;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Mobile sub-selector between the two `image-12.png` settlement cards
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'CONTRA',
              icon: Icon(Icons.swap_horiz_rounded, size: 17),
              label: Text('Exchange against sale'),
            ),
            ButtonSegment(
              value: 'PAYOUT',
              icon: Icon(Icons.account_balance_wallet_outlined, size: 17),
              label: Text('Pay customer'),
            ),
          ],
          selected: {_settlementMode},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            selectedBackgroundColor: Pal.gold,
            selectedForegroundColor: Colors.white,
            side: const BorderSide(color: Pal.line),
            textStyle: T.body(12.5, w: FontWeight.w700),
          ),
          onSelectionChanged: (s) => setState(() => _settlementMode = s.first),
        ),
        const SizedBox(height: 12),

        if (_settlementMode == 'CONTRA')
          // Left card in `image-12.png`: `Exchange against sale`
          SaasFormCard(
            title: 'Exchange against sale',
            subtitle:
                'Explicitly offset posted old-metal purchase payable against an open customer sales invoice.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Old Metal Purchase (oldMetalPurchaseId)',
                  controller: _contraPurchaseId,
                  options: purchaseOpts,
                  hint: 'oldMetalPurchaseId',
                  onSelected: (opt) {
                    if (opt != null) {
                      final outAmt = _pick(
                        opt.raw,
                        ['outstandingAmount', 'payableAmount', 'totalValuation', 'amount'],
                      );
                      if (outAmt.isNotEmpty) {
                        setState(() => _contraAmount.text = normAmount(outAmt));
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Sales Invoice (salesInvoiceId)',
                  controller: _contraSalesInvId,
                  options: _lk.invoices,
                  hint: 'salesInvoiceId',
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Amount (INR)',
                  controller: _contraAmount,
                  hint: 'amount',
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                DatePickField(
                  label: 'Settlement Date',
                  controller: _contraDate,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Posting Period (postingPeriodId)',
                  controller: _contraPeriodId,
                  options: openPeriods,
                  hint: 'postingPeriodId',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Document Series (documentSeriesId)',
                  controller: _contraDocSeriesId,
                  options: _lk.series,
                  hint: 'documentSeriesId',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Journal Series (journalSeriesId)',
                  controller: _contraJournalSeriesId,
                  options: journalSeries,
                  hint: 'journalSeriesId',
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  busy: _busy,
                  label: 'Post contra settlement',
                  onPressed: _busy ? null : _submitContraSettlement,
                ),
              ],
            ),
          )
        else
          // Right card in `image-12.png`: `Pay customer`
          SaasFormCard(
            title: 'Pay customer',
            subtitle:
                'Disburse direct bank transfer, UPI, or cash payout against an old-metal purchase.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Old Metal Purchase (oldMetalPurchaseId)',
                  controller: _payPurchaseId,
                  options: purchaseOpts,
                  hint: 'oldMetalPurchaseId',
                  onSelected: (opt) {
                    if (opt != null) {
                      final outAmt = _pick(
                        opt.raw,
                        ['outstandingAmount', 'payableAmount', 'totalValuation', 'amount'],
                      );
                      if (outAmt.isNotEmpty) {
                        setState(() => _payAmount.text = normAmount(outAmt));
                      }
                    }
                  },
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Amount (INR)',
                  controller: _payAmount,
                  hint: 'amount',
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                SaasDropdown(
                  label: 'Method',
                  value: _payMethod,
                  options: const {
                    'BANK_TRANSFER': 'Bank transfer',
                    'CASH': 'Cash',
                    'UPI': 'UPI',
                    'CHEQUE': 'Cheque',
                  },
                  onChanged: (v) => setState(() => _payMethod = v),
                ),
                const SizedBox(height: 10),
                DatePickField(
                  label: 'Payout Date',
                  controller: _payDate,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Instrument Account (instrumentAccountId)',
                  controller: _payInstrumentAcctId,
                  options: _lk.accounts,
                  hint: 'instrumentAccountId',
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Payment Reference (paymentReference)',
                  controller: _payReference,
                  hint: 'paymentReference',
                  mono: true,
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Posting Period (postingPeriodId)',
                  controller: _payPeriodId,
                  options: openPeriods,
                  hint: 'postingPeriodId',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Document Series (documentSeriesId)',
                  controller: _payDocSeriesId,
                  options: _lk.series,
                  hint: 'documentSeriesId',
                ),
                const SizedBox(height: 10),
                LookupField(
                  label: 'Journal Series (journalSeriesId)',
                  controller: _payJournalSeriesId,
                  options: journalSeries,
                  hint: 'journalSeriesId',
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  busy: _busy,
                  label: 'Post payout',
                  onPressed: _busy ? null : _submitCustomerPayout,
                ),
              ],
            ),
          ),

        if (_settlements.isNotEmpty) ...[
          SectionLabel('Posted Old-Metal Settlements (${_settlements.length})'),
          for (final st in _settlements)
            LuxuryRecordCard(
              icon: Icons.task_alt_rounded,
              code: _pick(
                st,
                ['documentNumber', 'settlementNumber', 'paymentReference'],
                shortId('${st['id'] ?? 'SET'}'),
              ),
              status: _pick(st, ['kind', 'method', 'state'], 'POSTED'),
              lines: [
                if (_pick(st, ['settlementDate']).isNotEmpty)
                  ('Settlement Date', fmtDate(_pick(st, ['settlementDate']))),
              ],
              amountLabel: 'Settled Amount',
              amountValue: inr(_pick(st, ['amount'], '0.00')),
            ),
        ],
      ],
    );
  }
}
