import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customers/customers_screen.dart';
import '../inventory/scanner_page.dart';
import '../more/old_gold_screen.dart';
import 'billing_controller.dart';

class BillingScreen extends StatelessWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BillingController>();
    if (b.receipt != null) return _Receipt(receipt: b.receipt!);
    return Scaffold(
      appBar: AppBar(
        title: const Text('New bill'),
        actions: [
          if (b.lines.isNotEmpty || b.payments.isNotEmpty || b.exchanges.isNotEmpty)
            TextButton(onPressed: () => _confirmClear(context, b), child: const Text('Clear')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Panel(
            onTap: () async {
              final p = await showCustomerPicker(context);
              if (p != null && context.mounted) context.read<BillingController>().setCustomer(p);
            },
            child: Row(children: [
              const Icon(Icons.person_outline_rounded, color: Pal.muted),
              const SizedBox(width: 12),
              Expanded(
                child: b.customer == null
                    ? Text('Add customer (optional)', style: T.body(15, color: Pal.muted, w: FontWeight.w700))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.customer!.name, style: T.body(15.5, w: FontWeight.w800)),
                        if (b.customer!.phone.isNotEmpty) Text(b.customer!.phone, style: T.body(13, color: Pal.muted)),
                      ]),
              ),
              if (b.customer != null)
                IconButton(onPressed: () => b.setCustomer(null), icon: const Icon(Icons.close_rounded, size: 20))
              else
                const Icon(Icons.chevron_right_rounded, color: Pal.muted),
            ]),
          ),
          SectionLabel('Pieces', trailing: TextButton.icon(onPressed: () => _scan(context), icon: const Icon(Icons.qr_code_scanner_rounded, size: 18), label: const Text('Scan piece'))),
          if (b.lines.isEmpty)
            Panel(
              child: EmptyBlock(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan the first piece',
                body: 'Each scan reserves the piece for this counter so no one else can sell it.',
                action: FilledButton(onPressed: () => _scan(context), child: const Text('Open scanner')),
              ),
            )
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < b.lines.length; i++) ...[
                  if (i > 0) const Divider(),
                  _line(context, b, b.lines[i]),
                ],
              ]),
            ),
          SectionLabel('Old gold credit', trailing: TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const OldGoldScreen())), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Buy old gold'))),
          if (b.exchanges.isEmpty)
            Text('No exchange on this bill.', style: T.body(14, color: Pal.muted))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < b.exchanges.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text(b.exchanges[i].label, style: T.body(14.5, w: FontWeight.w800)),
                    subtitle: Text('Voucher ${b.exchanges[i].voucherId}', style: T.body(12.5, color: Pal.muted)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(inr(b.exchanges[i].amount), style: T.display(17)),
                      IconButton(onPressed: () => b.removeExchange(b.exchanges[i]), icon: const Icon(Icons.close_rounded, size: 20)),
                    ]),
                  ),
                ],
              ]),
            ),
          SectionLabel('Payments', trailing: TextButton.icon(onPressed: () => _addPayment(context), icon: const Icon(Icons.add_rounded, size: 18), label: const Text('Add payment'))),
          if (b.payments.isEmpty)
            Text('Add how the customer is paying, such as UPI or cash.', style: T.body(14, color: Pal.muted))
          else
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (var i = 0; i < b.payments.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text(paymentModes[b.payments[i].mode] ?? b.payments[i].mode, style: T.body(14.5, w: FontWeight.w800)),
                    subtitle: (b.payments[i].reference ?? '').isEmpty ? null : Text(b.payments[i].reference!, style: T.body(12.5, color: Pal.muted)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(inr(b.payments[i].amount), style: T.display(17)),
                      IconButton(onPressed: () => b.removePayment(b.payments[i]), icon: const Icon(Icons.close_rounded, size: 20)),
                    ]),
                  ),
                ],
              ]),
            ),
          const SectionLabel('Remarks'),
          TextField(
            onChanged: b.setRemarks,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Optional note on the invoice'),
          ),
        ],
      ),
      bottomNavigationBar: _CheckoutBar(b: b),
    );
  }

  Widget _line(BuildContext context, BillingController b, Article a) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, style: T.body(15, w: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('${a.barcode}  |  ${a.purity}  |  ${grams(a.net)} net', style: T.body(12.5, color: Pal.muted)),
              const SizedBox(height: 3),
              Text('Making ${rate(a.makingRate)}${a.makingType == 'PER_GRAM' ? ' per gram' : ''}', style: T.body(12.5, color: Pal.muted)),
            ]),
          ),
          IconButton(onPressed: () => b.removeLine(a), icon: const Icon(Icons.close_rounded, size: 20)),
        ]),
      );

  Future<void> _scan(BuildContext context) async {
    final billing = context.read<BillingController>();
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage(title: 'Scan piece to bill')));
    if (v == null || !context.mounted) return;
    try {
      final a = await billing.addByBarcode(v);
      if (context.mounted) toast(context, '${a.name} added.');
    } on ApiException catch (e) {
      if (context.mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _confirmClear(BuildContext context, BillingController b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.pearl,
        title: Text('Clear this bill?', style: T.display(20)),
        content: Text('Pieces, credits and payments will be removed. Reserved pieces stay reserved until their hold expires.', style: T.body(14, color: Pal.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep bill')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear bill')),
        ],
      ),
    );
    if (ok == true) b.reset();
  }

  Future<void> _addPayment(BuildContext context) async {
    final b = context.read<BillingController>();
    final p = await showModalBottomSheet<PaymentLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PaymentSheet(),
    );
    if (p != null) b.addPayment(p);
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.b});
  final BillingController b;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Pal.line))),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (b.error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Pal.dangerWash, borderRadius: BorderRadius.circular(12)),
              child: Text(b.error!, style: T.body(13.5, color: Pal.danger, w: FontWeight.w700)),
            ),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${b.lines.length} ${b.lines.length == 1 ? 'piece' : 'pieces'}', style: T.body(13, color: Pal.muted, w: FontWeight.w700)),
                Text('Paying ${b.paymentsTotalLabel}', style: T.display(19)),
              ]),
            ),
            SizedBox(
              width: 190,
              child: FilledButton(
                onPressed: b.canCheckout ? b.checkout : null,
                child: b.busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Create invoice'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Final totals and GST are calculated by the server.', style: T.body(12, color: Pal.muted)),
        ]),
      ),
    );
  }
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet();
  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  String _mode = 'UPI';
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  String? _err;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  void _save() {
    if (!isValidAmount(_amount.text)) {
      setState(() => _err = 'Enter an amount in rupees, up to 2 decimal places.');
      return;
    }
    Navigator.pop(
      context,
      PaymentLine(mode: _mode, amount: normAmount(_amount.text), reference: _mode == 'CASH' ? null : _ref.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Add payment', style: T.display(26)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in paymentModes.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: _mode == e.key,
              showCheckmark: false,
              selectedColor: Pal.ink,
              labelStyle: T.body(14, w: FontWeight.w800, color: _mode == e.key ? Colors.white : Pal.text),
              side: const BorderSide(color: Pal.line),
              onSelected: (_) => setState(() => _mode = e.key),
            ),
        ]),
        const SizedBox(height: 18),
        const FieldLabel('Amount'),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: T.display(24),
          decoration: const InputDecoration(prefixText: '₹ ', hintText: '0.00'),
        ),
        if (_mode != 'CASH') ...[
          const SizedBox(height: 14),
          const FieldLabel('Reference number'),
          TextField(controller: _ref, decoration: const InputDecoration(hintText: 'UPI or card transaction ID')),
        ],
        if (_err != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: T.body(13.5, color: Pal.danger, w: FontWeight.w700))),
        const SizedBox(height: 20),
        FilledButton(onPressed: _save, child: const Text('Add payment')),
      ]),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt({required this.receipt});
  final Map<String, dynamic> receipt;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    String g(List<String> keys, [String fallback = '0.00']) {
      for (final k in keys) {
        if (r[k] != null && '${r[k]}'.isNotEmpty) return '${r[k]}';
      }
      return fallback;
    }

    final status = g(['status', 'state'], 'CONFIRMED');
    final due = g(['balanceDue', 'outstandingAmount']);
    final settled = due == '0.00' || due == '0';
    return Scaffold(
      appBar: AppBar(title: const Text('Invoice created'), automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(colors: [Pal.inkSoft, Pal.ink], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: Pal.goldSoft, shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: Pal.ink),
                ),
                const SizedBox(width: 12),
                StatusPill(status, tone: Tone.gold),
              ]),
              const SizedBox(height: 18),
              Text(g(['invoiceNumber', 'documentNumber'], 'Invoice'), style: T.display(34, color: Colors.white)),
              const SizedBox(height: 4),
              Text(settled ? 'Paid in full' : 'Balance due ${inr(due)}', style: T.body(14.5, color: settled ? Pal.goldSoft : const Color(0xFFE9A24A), w: FontWeight.w700)),
            ]),
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(children: [
              KeyValue('Gross amount', inr(g(['grossAmount', 'taxableAmount']))),
              KeyValue('GST', inr(g(['gstAmount', 'taxAmount']))),
              KeyValue('Old gold credit', inr(g(['oldGoldCredit']))),
              const Divider(),
              KeyValue('Net payable', inr(g(['netPayable', 'totalAmount'])), strong: true),
              KeyValue('Paid', inr(g(['paidAmount', 'settledAmount']))),
              KeyValue('Balance due', inr(due), strong: true, valueColor: settled ? Pal.ok : Pal.danger),
            ]),
          ),
          const SizedBox(height: 14),
          Text('Printable PDF and WhatsApp sharing arrive once the document worker is live on the server.', style: T.body(13, color: Pal.muted)),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => context.read<BillingController>().reset(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Start next bill'),
          ),
        ],
      ),
    );
  }
}
