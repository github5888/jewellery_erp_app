import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../billing/billing_controller.dart';
import '../customers/customers_screen.dart';

/// Old gold / silver intake. The preview below uses [Decimal] (never double),
/// mirroring the voucher payload in the API guide:
///   netPure = (gross - wastage) x purity/1000,  total = netPure x rate
class OldGoldScreen extends StatefulWidget {
  const OldGoldScreen({super.key});
  @override
  State<OldGoldScreen> createState() => _OldGoldScreenState();
}

class _OldGoldScreenState extends State<OldGoldScreen> {
  static const _purities = {
    'GOLD': ['999', '916', '750', '585'],
    'SILVER': ['999', '925'],
  };

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillRate());
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
    _rate.text = m?.buy ?? '';
    setState(() {});
  }

  ({Decimal netPure, Decimal total})? _calc() {
    if (!isValidWeight(_gross.text) || !isValidWeight(_wastage.text) || !isValidAmount(_rate.text)) {
      return null;
    }
    final g = Decimal.parse(_gross.text.trim());
    final w = Decimal.parse(_wastage.text.trim());
    if (w > g) return null;
    final fineness = Decimal.parse(_purity) * Decimal.parse('0.001');
    final np = ((g - w) * fineness).round(scale: 6);
    final total = (np * Decimal.parse(_rate.text.trim())).round(scale: 2);
    return (netPure: np, total: total);
  }

  String _purityLabel() {
    if (_purity == '999') return '999 (fine)';
    if (_metal == 'SILVER') return '$_purity (sterling)';
    const carats = {'916': '22K', '750': '18K', '585': '14K'};
    return carats[_purity] == null ? _purity : '$_purity (${carats[_purity]})';
  }

  Future<void> _submit() async {
    final c = _calc();
    if (c == null) {
      setState(() => _error = 'Check the weights and rate. Wastage can\'t exceed gross weight.');
      return;
    }
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
      final d = await context.read<ApiClient>().post('/old-metal/purchase-vouchers', body: body);
      if (!mounted) return;
      setState(() {
        _voucher = asMap(d);
        _savedTotal = '${_voucher!['totalValuation'] ?? c.total.toStringAsFixed(2)}';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _applyToBill() {
    final id = '${_voucher?['voucherId'] ?? _voucher?['id'] ?? ''}';
    if (id.isEmpty) {
      toast(context, 'The voucher has no ID to attach. Open the bill and add it from the web portal.', error: true);
      return;
    }
    context.read<BillingController>().addExchange(
          ExchangeCredit(
            voucherId: id,
            label: 'Old ${humanize(_metal)} $_purity, ${grams(_gross.text.trim())}',
            amount: normAmount(_savedTotal ?? '0'),
          ),
        );
    toast(context, 'Credit added to the open bill.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_voucher != null) return _done();
    final calc = _calc();
    return Scaffold(
      appBar: AppBar(title: const Text('Buy old metal')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Panel(
            onTap: () async {
              final p = await showCustomerPicker(context);
              if (p != null) setState(() => _customer = p);
            },
            child: Row(children: [
              const Icon(Icons.person_outline_rounded, color: Pal.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_customer?.name ?? 'Select customer (optional)',
                    style: T.body(15, w: _customer == null ? FontWeight.w700 : FontWeight.w800, color: _customer == null ? Pal.muted : Pal.text)),
              ),
              const Icon(Icons.chevron_right_rounded, color: Pal.muted),
            ]),
          ),
          const SectionLabel('Metal and purity'),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'GOLD', label: Text('Gold')), ButtonSegment(value: 'SILVER', label: Text('Silver'))],
            selected: {_metal},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Pal.ink,
              selectedForegroundColor: Colors.white,
              side: const BorderSide(color: Pal.line),
              textStyle: T.body(14, w: FontWeight.w800),
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
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _purities[_metal]!)
              ChoiceChip(
                label: Text(p),
                selected: _purity == p,
                showCheckmark: false,
                selectedColor: Pal.goldWash,
                side: BorderSide(color: _purity == p ? Pal.gold : Pal.line),
                labelStyle: T.body(14, w: FontWeight.w800, color: _purity == p ? const Color(0xFF7A5A1E) : Pal.text),
                onSelected: (_) {
                  setState(() {
                    _purity = p;
                    _rateTouched = false;
                  });
                  _prefillRate();
                },
              ),
          ]),
          const SectionLabel('Weights'),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Gross weight (g)'),
                TextField(controller: _gross, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(hintText: '15.000')),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Melt loss (g)'),
                TextField(controller: _wastage, onChanged: (_) => setState(() {}), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          const FieldLabel('Buy rate per gram'),
          TextField(
            controller: _rate,
            onChanged: (_) => setState(() => _rateTouched = true),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₹ ', helperText: "Filled from today's buy rate. Change it only if your manager agrees."),
          ),
          const SectionLabel('Payout'),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'EXCHANGE_CREDIT', label: Text('Exchange credit')), ButtonSegment(value: 'CASH', label: Text('Cash'))],
            selected: {_payout},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Pal.ink,
              selectedForegroundColor: Colors.white,
              side: const BorderSide(color: Pal.line),
              textStyle: T.body(14, w: FontWeight.w800),
            ),
            onSelectionChanged: (s) => setState(() => _payout = s.first),
          ),
          const SizedBox(height: 20),
          Panel(
            color: calc == null ? Colors.white : Pal.goldWash,
            child: calc == null
                ? Text('Enter gross weight and rate to see the valuation.', style: T.body(14, color: Pal.muted))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Valuation', style: T.body(13, color: const Color(0xFF7A5A1E), w: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(inr(calc.total.toStringAsFixed(2)), style: T.display(34)),
                    const SizedBox(height: 8),
                    KeyValue('Pure metal', grams(calc.netPure.toStringAsFixed(6), dp: 4)),
                    KeyValue('Purity', _purityLabel()),
                  ]),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: T.body(13.5, color: Pal.danger, w: FontWeight.w700))),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: (_busy || calc == null) ? null : _submit,
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Create purchase voucher'),
          ),
        ],
      ),
    );
  }

  Widget _done() {
    final exchange = _payout == 'EXCHANGE_CREDIT';
    return Scaffold(
      appBar: AppBar(title: const Text('Voucher created'), automaticallyImplyLeading: false),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(colors: [Pal.inkSoft, Pal.ink], begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Valuation', style: T.body(13.5, color: Colors.white70, w: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(inr(_savedTotal), style: T.display(40, color: Pal.goldSoft, w: FontWeight.w600)),
            const SizedBox(height: 10),
            Text('${_customer?.name ?? 'Walk-in'}  |  ${humanize(_metal)} $_purity  |  ${grams(_gross.text.trim())}', style: T.body(13.5, color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 18),
        if (exchange)
          FilledButton.icon(onPressed: _applyToBill, icon: const Icon(Icons.receipt_long_rounded), label: const Text('Apply credit to current bill')),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    );
  }
}
