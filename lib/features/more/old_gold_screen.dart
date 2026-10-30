import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../billing/billing_controller.dart';
import '../customers/customers_screen.dart';

/// Old Gold / Silver Exchange & Bullion Appraisal.
/// - Exact Decimal arithmetic: netPure = (gross - wastage) * purity / 1000
/// - Queries `GET /old-metal` for purchase voucher register
/// - Submits `POST /old-metal/purchase-vouchers` and links directly to POS cart
class OldGoldScreen extends StatefulWidget {
  const OldGoldScreen({super.key, this.pickMode = false});
  final bool pickMode;
  @override
  State<OldGoldScreen> createState() => _OldGoldScreenState();
}

class _OldGoldScreenState extends State<OldGoldScreen> {
  static const _purities = {
    'GOLD': [
      ('999', '24K · 999'),
      ('916', '22K · 916'),
      ('750', '18K · 750'),
      ('585', '14K · 585'),
    ],
    'SILVER': [
      ('999', 'Fine · 999'),
      ('925', 'Sterling · 925'),
    ],
  };

  String _tab = 'APPRAISE';
  Party? _customer;
  String _metal = 'GOLD';
  String _purity = '916';
  String _payout = 'EXCHANGE_CREDIT';
  final _gross = TextEditingController();
  final _wastage = TextEditingController(text: '0');
  final _rate = TextEditingController();
  bool _rateTouched = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _voucher;
  String? _savedTotal;

  List<Map<String, dynamic>> _vouchers = [];
  bool _loadingHistory = false;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefillRate();
      _loadVouchers();
    });
  }

  @override
  void dispose() {
    _gross.dispose();
    _wastage.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _prefillRate() {
    if (_rateTouched) return;
    final m = context.read<RatesController>().find(_metal, _purity);
    if (m != null && m.buy != '0.00') {
      _rate.text = m.buy;
      setState(() {});
    }
  }

  Future<void> _loadVouchers() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/old-metal');
      if (mounted) {
        setState(() => _vouchers = asList(d, keys: const ['vouchers', 'purchaseVouchers', 'items', 'rows']));
      }
    } on ApiException catch (e) {
      if (e.status != 404 && mounted) {
        setState(() => _historyError = e.message);
      }
    }
    if (mounted) setState(() => _loadingHistory = false);
  }

  ({Decimal netWeight, Decimal netPure, Decimal total})? _calc() {
    if (!isValidWeight(_gross.text) || !isValidWeight(_wastage.text) || !isValidAmount(_rate.text)) {
      return null;
    }
    final g = Decimal.parse(_gross.text.trim());
    final w = Decimal.parse(_wastage.text.trim());
    if (g <= Decimal.zero || w > g) return null;
    final netWt = g - w;
    final fineness = Decimal.parse(_purity) * Decimal.parse('0.001');
    final np = (netWt * fineness).round(scale: 6);
    final total = (np * Decimal.parse(_rate.text.trim())).round(scale: 2);
    return (netWeight: netWt, netPure: np, total: total);
  }

  Future<void> _submit() async {
    final c = _calc();
    if (c == null) {
      setState(() => _error = 'Enter valid gross weight, wastage, and buy rate. Wastage cannot exceed gross weight.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = {
      if (_customer != null) 'customerId': _customer!.id,
      'metal': _metal,
      'assayedPurity': _purity,
      'grossWeightGrams': Decimal.parse(_gross.text.trim()).toStringAsFixed(6),
      'wastageDeductionGrams': Decimal.parse(_wastage.text.trim()).toStringAsFixed(6),
      'netPureGrams': c.netPure.toStringAsFixed(6),
      'appliedRatePerGram': normAmount(_rate.text),
      'totalValuation': c.total.toStringAsFixed(2),
      'payoutMode': _payout,
    };
    try {
      final d = await context.read<ApiClient>().post(
            '/old-metal/purchase-vouchers',
            body: body,
            idempotencyKey: const Uuid().v4(),
          );
      if (!mounted) return;
      final created = asMap(d);
      setState(() {
        _voucher = created;
        _savedTotal = '${created['totalValuation'] ?? c.total.toStringAsFixed(2)}';
      });
      _loadVouchers();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _applyMapToBill(Map<String, dynamic> v, {String? fallbackLabel, String? fallbackAmount}) {
    final id = '${v['voucherId'] ?? v['id'] ?? v['voucherNumber'] ?? ''}';
    if (id.isEmpty) {
      toast(context, 'Voucher ID unavailable to attach.', error: true);
      return;
    }
    final amt = normAmount('${v['totalValuation'] ?? v['amount'] ?? fallbackAmount ?? '0'}');
    final lbl = fallbackLabel ??
        'Old ${humanize('${v['metal'] ?? _metal}')} ${v['assayedPurity'] ?? _purity} · ${grams(v['grossWeightGrams'] ?? '0')}';
    final credit = ExchangeCredit(
      voucherId: id,
      label: lbl,
      amount: amt,
      fineWeight: '${v['netPureGrams'] ?? ''}',
    );
    context.read<BillingController>().addExchange(credit);
    toast(context, 'Old metal credit ${inr(amt)} attached to POS bill.');
    Navigator.pop(context, credit);
  }

  @override
  Widget build(BuildContext context) {
    if (_voucher != null) return _done();
    final calc = _calc();
    return LuxuryModuleScaffold(
      title: 'Old Metal Exchange',
      icon: Icons.recycling_rounded,
      actions: [
        if (_tab == 'HISTORY')
          IconButton(
            onPressed: _loadVouchers,
            icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
          ),
      ],
      topFilterBar: PillTabs<String>(
        selected: _tab,
        onChanged: (v) => setState(() => _tab = v),
        items: [
          ('APPRAISE', 'New Appraisal', Icons.scale_rounded),
          ('HISTORY', 'Voucher Register (${_vouchers.length})', Icons.receipt_long_outlined),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_tab == 'HISTORY') _buildHistory() else _buildAppraisal(calc),
        ],
      ),
    );
  }

  Widget _buildAppraisal(({Decimal netWeight, Decimal netPure, Decimal total})? calc) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Panel(
        onTap: () async {
          final p = await showCustomerPicker(context);
          if (p != null) setState(() => _customer = p);
        },
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: Pal.goldWash, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.person_outline_rounded, color: Pal.goldDeep, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _customer == null
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Link Customer (Optional)', style: T.body(14, w: FontWeight.w700)),
                    Text('Attach KYC party for old gold purchase compliance', style: T.body(12, color: Pal.muted)),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_customer!.name, style: T.body(14.5, w: FontWeight.w800)),
                    if (_customer!.phone.isNotEmpty)
                      Text(_customer!.phone, style: T.mono(12, color: Pal.muted)),
                  ]),
          ),
          if (_customer != null)
            IconButton(onPressed: () => setState(() => _customer = null), icon: const Icon(Icons.close_rounded, size: 18))
          else
            const Icon(Icons.chevron_right_rounded, color: Pal.muted),
        ]),
      ),
      const SectionLabel('Assayed Metal & Purity'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'GOLD', icon: Icon(Icons.workspace_premium_rounded, size: 17), label: Text('Gold Bullion')),
              ButtonSegment(value: 'SILVER', icon: Icon(Icons.toll_rounded, size: 17), label: Text('Silver')),
            ],
            selected: {_metal},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Pal.ink,
              selectedForegroundColor: Colors.white,
              side: const BorderSide(color: Pal.line),
              textStyle: T.body(13.5, w: FontWeight.w700),
            ),
            onSelectionChanged: (s) {
              setState(() {
                _metal = s.first;
                _purity = _metal == 'GOLD' ? '916' : '999';
                _rateTouched = false;
              });
              _prefillRate();
            },
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _purities[_metal]!)
              ChoiceChip(
                label: Text(p.$2),
                selected: _purity == p.$1,
                showCheckmark: false,
                selectedColor: Pal.goldWash,
                backgroundColor: Pal.surfaceAlt,
                side: BorderSide(color: _purity == p.$1 ? Pal.gold : Pal.line),
                labelStyle: T.body(
                  12.5,
                  w: FontWeight.w700,
                  color: _purity == p.$1 ? Pal.goldDeep : Pal.textSoft,
                ),
                onSelected: (_) {
                  setState(() {
                    _purity = p.$1;
                    _rateTouched = false;
                  });
                  _prefillRate();
                },
              ),
          ]),
        ]),
      ),
      const SectionLabel('Scale Weights & Buy Rate'),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Gross Weight (g)'),
                TextField(
                  controller: _gross,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: T.mono(15, w: FontWeight.w700),
                  decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Melt / Dust Loss (g)'),
                TextField(
                  controller: _wastage,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: T.mono(15, w: FontWeight.w700),
                  decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          const FieldLabel('Buy Rate per Pure Gram (INR)'),
          TextField(
            controller: _rate,
            onChanged: (_) => setState(() => _rateTouched = true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: T.mono(16, w: FontWeight.w700),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              hintText: '0.00',
              helperText: 'Auto-synced with showroom buy rate; override requires manager authorization.',
            ),
          ),
          const SizedBox(height: 16),
          const FieldLabel('Settlement Mode'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'EXCHANGE_CREDIT', label: Text('POS Exchange Credit')),
              ButtonSegment(value: 'CASH', label: Text('Direct Cash Payout')),
            ],
            selected: {_payout},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Pal.teal,
              selectedForegroundColor: Colors.white,
              side: const BorderSide(color: Pal.line),
              textStyle: T.body(13, w: FontWeight.w700),
            ),
            onSelectionChanged: (s) => setState(() => _payout = s.first),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      LuxuryHeroCard(
        child: calc == null
            ? Row(children: [
                const Icon(Icons.calculate_outlined, color: Pal.goldSoft, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Enter scale weight and buy rate above to compute exact Fine 999 valuation.',
                    style: T.body(13, color: Colors.white70),
                  ),
                ),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const EnterpriseBadge('Assayed Valuation', icon: Icons.verified_outlined),
                  const Spacer(),
                  Text('$_metal $_purity', style: T.mono(12, color: Pal.goldSoft)),
                ]),
                const SizedBox(height: 12),
                Text(
                  inr(calc.total.toStringAsFixed(2)),
                  style: T.display(32, color: Pal.goldSoft, w: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Divider(color: Colors.white.withValues(alpha: 0.14)),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Net Metal Wt', style: T.body(12.5, color: Colors.white70)),
                  Text(grams(calc.netWeight.toStringAsFixed(6)), style: T.mono(13, color: Colors.white)),
                ]),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Fine 999 Equivalent', style: T.body(12.5, color: Colors.white70)),
                  Text(fineGrams(calc.netPure.toStringAsFixed(6), fullPrecision: true), style: T.mono(13, color: Pal.goldSoft)),
                ]),
              ]),
      ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: T.body(13, color: Pal.danger, w: FontWeight.w700)),
        ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: (_busy || calc == null) ? null : _submit,
        style: FilledButton.styleFrom(backgroundColor: Pal.teal),
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
              )
            : const Icon(Icons.fact_check_outlined, size: 18),
        label: const Text('Issue Old Metal Purchase Voucher'),
      ),
    ]);
  }

  Widget _buildHistory() {
    if (_loadingHistory) {
      return Column(children: [
        for (var i = 0; i < 3; i++)
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 68))),
      ]);
    }
    if (_historyError != null) return ErrorBlock(_historyError!, onRetry: _loadVouchers);
    if (_vouchers.isEmpty) {
      return const Panel(
        child: EmptyBlock(
          icon: Icons.recycling_rounded,
          title: 'No old metal vouchers yet',
          body: 'Completed customer old gold and silver appraisals will appear here.',
        ),
      );
    }
    return Column(children: [
      for (final v in _vouchers)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    '${v['voucherNumber'] ?? v['documentNumber'] ?? v['code'] ?? 'Purchase Voucher'}',
                    style: T.display(17),
                  ),
                ),
                StatusPill('${v['status'] ?? v['state'] ?? v['payoutMode'] ?? 'ISSUED'}'),
              ]),
              const SizedBox(height: 8),
              KeyValue('Valuation', inr('${v['totalValuation'] ?? v['amount'] ?? '0.00'}'), strong: true),
              if (v['grossWeightGrams'] != null)
                KeyValue('Gross / Fine Wt', '${grams(v['grossWeightGrams'])} · ${fineGrams(v['netPureGrams'] ?? '0')} pure', mono: true),
              if (v['assayedPurity'] != null || v['metal'] != null)
                KeyValue('Assay', '${v['metal'] ?? 'GOLD'} ${v['assayedPurity'] ?? ''}'),
              if (v['createdAt'] != null) KeyValue('Date', formatDateTime(v['createdAt'])),
              if ('${v['payoutMode'] ?? 'EXCHANGE_CREDIT'}' == 'EXCHANGE_CREDIT' &&
                  '${v['status'] ?? ''}'.toUpperCase() != 'REDEEMED') ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _applyMapToBill(v),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                  label: const Text('Attach Credit to POS Bill'),
                ),
              ],
            ]),
          ),
        ),
    ]);
  }

  Widget _done() {
    final exchange = _payout == 'EXCHANGE_CREDIT';
    return Scaffold(
      appBar: AppBar(title: const Text('Purchase Voucher Issued'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          LuxuryHeroCard(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: EnterpriseBadge('Voucher Confirmed', icon: Icons.verified_rounded),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(_payout, tone: Tone.gold),
              ]),
              const SizedBox(height: 14),
              Text(inr(_savedTotal), style: T.display(36, color: Pal.goldSoft)),
              const SizedBox(height: 6),
              Text(
                '${_customer?.name ?? 'Walk-in Customer'} · ${humanize(_metal)} $_purity · ${grams(_gross.text.trim())}',
                style: T.body(13, color: Colors.white70),
              ),
              if (_voucher?['voucherNumber'] != null || _voucher?['id'] != null) ...[
                const SizedBox(height: 10),
                Text(
                  'Ref: ${_voucher!['voucherNumber'] ?? _voucher!['voucherId'] ?? _voucher!['id']}',
                  style: T.mono(12, color: Colors.white60),
                ),
              ],
            ]),
          ),
          const SizedBox(height: 18),
          if (exchange)
            FilledButton.icon(
              onPressed: () => _applyMapToBill(
                _voucher!,
                fallbackLabel: 'Old ${humanize(_metal)} $_purity · ${grams(_gross.text.trim())}',
                fallbackAmount: _savedTotal,
              ),
              style: FilledButton.styleFrom(backgroundColor: Pal.teal),
              icon: const Icon(Icons.receipt_long_rounded, size: 18),
              label: const Text('Apply Credit to Current POS Bill'),
            ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
