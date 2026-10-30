import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../customers/customers_screen.dart';
import '../inventory/scanner_page.dart';
import '../more/old_gold_screen.dart';
import 'billing_controller.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key});
  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final _barcode = TextEditingController();
  String _tab = 'POS';

  @override
  void dispose() {
    _barcode.dispose();
    super.dispose();
  }

  Future<void> _scan(BillingController c) async {
    final v = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (v != null) c.scanAndAdd(v);
  }

  Future<void> _editMaking(BillingController c, int index) async {
    final line = c.lines[index];
    final ctrl = TextEditingController(text: line.makingCharge);
    final updated = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Making Charges · ${line.article.barcode}', style: T.display(20)),
          const SizedBox(height: 6),
          Text('Metal value: ${inr(line.metalValue.toStringAsFixed(2))} (${grams(line.article.effectiveNetWeight)} @ ${rate(line.ratePerGram)})', style: T.body(12.5, color: Pal.muted)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final pctVal in const [8, 12, 16, 20])
              ActionChip(
                label: Text('$pctVal%'),
                backgroundColor: Pal.goldWash,
                onPressed: () {
                  final mc = (line.metalValue * Decimal.fromInt(pctVal) / Decimal.fromInt(100))
                      .toDecimal(scaleOnInfinitePrecision: 6)
                      .round(scale: 2);
                  ctrl.text = mc.toStringAsFixed(2);
                },
              ),
          ]),
          const SizedBox(height: 12),
          const FieldLabel('Making Charge (INR)'),
          TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: T.mono(16, w: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '₹ '),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Pal.teal),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Update Line Making Charge'),
          ),
        ]),
      ),
    );
    if (updated != null && (isValidAmount(updated) || updated == '0' || updated == '0.00')) {
      c.updateMakingCharge(index, updated);
    }
  }

  Future<void> _addPayment(BillingController c) async {
    String mode = 'UPI';
    final rem = c.remainingBalanceDecimal;
    final amt = TextEditingController(text: rem > Decimal.zero ? rem.toStringAsFixed(2) : '');
    final ref = TextEditingController();
    final res = await showModalBottomSheet<PayEntry>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Record Payment Tender', style: T.display(22)),
            const SizedBox(height: 14),
            const FieldLabel('Payment Mode'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in const [
                ('UPI', 'UPI QR'),
                ('CARD', 'Card POS'),
                ('CASH', 'Cash'),
                ('BANK_TRANSFER', 'RTGS / NEFT'),
              ])
                ChoiceChip(
                  label: Text(m.$2),
                  selected: mode == m.$1,
                  showCheckmark: false,
                  selectedColor: Pal.goldWash,
                  onSelected: (_) => setLocal(() => mode = m.$1),
                ),
            ]),
            const SizedBox(height: 14),
            const FieldLabel('Tender Amount (INR)'),
            TextField(
              controller: amt,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: T.mono(18, w: FontWeight.w700),
              decoration: const InputDecoration(prefixText: '₹ ', hintText: '0.00'),
            ),
            if (mode != 'CASH') ...[
              const SizedBox(height: 12),
              const FieldLabel('UTR / RRN / Auth Reference (Optional)'),
              TextField(
                controller: ref,
                style: T.mono(14),
                decoration: const InputDecoration(hintText: 'Transaction / UTR reference'),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Pal.teal),
              onPressed: () {
                if (!isValidAmount(amt.text)) return;
                Navigator.pop(ctx, PayEntry(mode, normAmount(amt.text), reference: ref.text.trim()));
              },
              child: const Text('Add Payment Split'),
            ),
          ]),
        ),
      ),
    );
    if (res != null) c.addPayment(res.mode, res.amount, reference: res.reference);
  }

  Future<void> _checkout(BillingController c) async {
    final receipt = await c.checkout();
    if (receipt == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InvoiceReceiptSheet(receipt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<BillingController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Counter & Sales'),
        actions: [
          if (_tab == 'POS' && (c.lines.isNotEmpty || c.customer != null || c.payments.isNotEmpty || c.oldGold != null))
            TextButton.icon(
              onPressed: c.busy ? null : c.clear,
              icon: const Icon(Icons.restart_alt_rounded, size: 17, color: Pal.danger),
              label: Text('Reset', style: T.body(13, color: Pal.danger, w: FontWeight.w700)),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          child: PillTabs<String>(
            selected: _tab,
            onChanged: (v) => setState(() => _tab = v),
            items: [
              ('POS', c.lines.isEmpty ? 'Counter POS Bill' : 'Counter POS (${c.lines.length})', Icons.point_of_sale_rounded),
              ('REGISTER', 'Sales Register', Icons.receipt_long_outlined),
            ],
          ),
        ),
        Expanded(
          child: _tab == 'POS' ? _buildPosCart(c) : const _SalesRegisterView(),
        ),
      ]),
    );
  }

  Widget _buildPosCart(BillingController c) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 36),
      children: [
        // 1. Customer Card
        const SectionLabel('1 · Patron / Customer'),
        Panel(
          onTap: () async {
            final p = await showCustomerPicker(context);
            if (p != null) c.setCustomer(p);
          },
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.customer == null ? Pal.surfaceAlt : Pal.goldWash,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.customer == null ? Pal.line : Pal.gold.withValues(alpha: 0.45),
                ),
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: c.customer == null ? Pal.muted : Pal.goldDeep,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: c.customer == null
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Select or Register Customer', style: T.body(14.5, w: FontWeight.w700)),
                      Text('Tap to search mobile, name, GSTIN or PAN', style: T.body(12, color: Pal.muted)),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.customer!.name, style: T.body(15, w: FontWeight.w800)),
                      Text(
                        [
                          if (c.customer!.phone.isNotEmpty) c.customer!.phone,
                          if (c.customer!.gstin.isNotEmpty) 'GSTIN: ${c.customer!.gstin}',
                        ].isEmpty
                            ? c.customer!.code
                            : [
                                if (c.customer!.phone.isNotEmpty) c.customer!.phone,
                                if (c.customer!.gstin.isNotEmpty) 'GSTIN: ${c.customer!.gstin}',
                              ].join(' · '),
                        style: T.body(12, color: Pal.muted),
                      ),
                    ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Pal.muted),
          ]),
        ),

        // 2. Ornament Cart
        SectionLabel('2 · Tagged Ornaments (${c.lines.length})'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _barcode,
              textCapitalization: TextCapitalization.characters,
              style: T.mono(14),
              decoration: const InputDecoration(
                hintText: 'Scan or enter ornament tag',
                prefixIcon: Icon(Icons.sell_outlined, size: 19),
              ),
              onSubmitted: (s) {
                c.scanAndAdd(s);
                _barcode.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Pal.obsidian,
                foregroundColor: Pal.goldSoft,
                padding: EdgeInsets.zero,
                minimumSize: const Size(50, 50),
              ),
              onPressed: c.busy ? null : () => _scan(c),
              child: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        if (c.lines.isEmpty)
          Panel(
            color: Pal.surfaceAlt,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                const Icon(Icons.qr_code_2_rounded, color: Pal.muted, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Scan ornament string tags with the camera or add pieces directly from the Vault tab.',
                    style: T.body(12.8, color: Pal.muted),
                  ),
                ),
              ]),
            ),
          )
        else
          for (var i = 0; i < c.lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CartLineCard(
                line: c.lines[i],
                onEditMaking: () => _editMaking(c, i),
                onRemove: () => c.removeAt(i),
              ),
            ),

        // 3. Old Gold Exchange Credit
        const SectionLabel('3 · Old Gold Trade-In (Optional)'),
        if (c.oldGold == null)
          OutlinedButton.icon(
            onPressed: () async {
              final v = await Navigator.push<ExchangeCredit>(
                context,
                MaterialPageRoute(builder: (_) => const OldGoldScreen(pickMode: true)),
              );
              if (v != null) c.setOldGold(v);
            },
            icon: const Icon(Icons.recycling_rounded, size: 18),
            label: const Text('Appraise & Attach Old Gold Credit'),
          )
        else
          Panel(
            color: Pal.goldWash,
            borderColor: Pal.gold.withValues(alpha: 0.55),
            child: Row(children: [
              const Icon(Icons.recycling_rounded, color: Pal.goldDeep, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.oldGold!.label.isEmpty ? 'Old Gold Voucher Credit' : c.oldGold!.label, style: T.body(13.5, w: FontWeight.w800)),
                  if (c.oldGold!.fineWeight.isNotEmpty)
                    Text('Fine 999: ${fineGrams(c.oldGold!.fineWeight)}', style: T.mono(11.5, color: Pal.goldDeep)),
                ]),
              ),
              Text('− ${inr(c.oldGold!.credit)}', style: T.display(18, color: Pal.goldDeep)),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => c.setOldGold(null),
              ),
            ]),
          ),

        // 4. Multi-Tender Payments
        SectionLabel('4 · Payment Split (${inr(c.paidTotal)})'),
        if (c.lines.isNotEmpty && c.remainingBalanceDecimal > Decimal.zero) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final quick in const [
              ('UPI', '1-Tap Full UPI', Icons.qr_code_rounded),
              ('CARD', 'Full Card', Icons.credit_card_rounded),
              ('CASH', 'Full Cash', Icons.payments_outlined),
            ])
              ActionChip(
                avatar: Icon(quick.$3, size: 15, color: Pal.teal),
                label: Text(quick.$2, style: T.body(12, color: Pal.teal, w: FontWeight.w700)),
                backgroundColor: Pal.tealWash,
                side: BorderSide(color: Pal.teal.withValues(alpha: 0.3)),
                onPressed: () => c.fillRemainingBalance(quick.$1),
              ),
          ]),
          const SizedBox(height: 8),
        ],
        for (var i = 0; i < c.payments.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Chip2(humanize(c.payments[i].mode)),
                if (c.payments[i].reference.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  MonoTag(c.payments[i].reference),
                ],
                const Spacer(),
                Text(inr(c.payments[i].amount), style: T.mono(14.5, w: FontWeight.w700)),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Pal.muted),
                  onPressed: () => c.removePayment(i),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(
          onPressed: () => _addPayment(c),
          icon: const Icon(Icons.add_card_rounded, size: 18),
          label: const Text('Add Custom Payment Split'),
        ),

        // 5. Live GST Tax Invoice Summary Card
        if (c.lines.isNotEmpty) ...[
          const SizedBox(height: 18),
          LuxuryHeroCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const EnterpriseBadge('GST Tax Invoice Preview', icon: Icons.verified_outlined),
              const SizedBox(height: 12),
              _darkRow('Bullion Metal Value', inr(c.metalSubtotal.toStringAsFixed(2))),
              _darkRow('Artisan Making Charges', inr(c.makingSubtotal.toStringAsFixed(2))),
              _darkRow('GST (3.00% Jewellery)', inr(c.gstSubtotal.toStringAsFixed(2))),
              if (c.oldGold != null)
                _darkRow('Less: Old Gold Exchange', '− ${inr(c.oldGold!.credit)}', accent: Pal.goldSoft),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(color: Colors.white.withValues(alpha: 0.16)),
              ),
              Row(children: [
                Text('NET PAYABLE', style: T.caps(10.5, color: Colors.white70)),
                const Spacer(),
                Text(inr(c.netPayableDecimal.toStringAsFixed(2)), style: T.display(26, color: Pal.goldSoft)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                Text(
                  c.remainingBalanceDecimal == Decimal.zero
                      ? 'Tender Balanced'
                      : 'Balance Due: ${inr(c.remainingBalanceDecimal.toStringAsFixed(2))}',
                  style: T.mono(
                    12,
                    color: c.remainingBalanceDecimal == Decimal.zero ? const Color(0xFF6EE7B7) : Colors.white70,
                  ),
                ),
                const Spacer(),
                Text('Paid: ${inr(c.paidTotal)}', style: T.mono(12, color: Colors.white)),
              ]),
            ]),
          ),
        ],

        if (c.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Panel(
              color: Pal.dangerWash,
              borderColor: Pal.danger.withValues(alpha: 0.35),
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, size: 18, color: Pal.danger),
                const SizedBox(width: 8),
                Expanded(child: Text(c.error!, style: T.body(12.8, color: Pal.danger, w: FontWeight.w700))),
              ]),
            ),
          ),

        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: c.busy ? null : () => _checkout(c),
          style: FilledButton.styleFrom(backgroundColor: Pal.teal),
          icon: c.busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.receipt_long_rounded, size: 19),
          label: Text(
            c.lines.isEmpty
                ? 'Issue GST Tax Invoice'
                : 'Issue GST Invoice · ${inr(c.netPayableDecimal.toStringAsFixed(2))}',
          ),
        ),
      ],
    );
  }

  Widget _darkRow(String k, String v, {Color? accent}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(children: [
          Expanded(child: Text(k, style: T.body(12.8, color: Colors.white70))),
          Text(v, style: T.mono(13, color: accent ?? Colors.white, w: FontWeight.w600)),
        ]),
      );
}

class _CartLineCard extends StatelessWidget {
  const _CartLineCard({
    required this.line,
    required this.onEditMaking,
    required this.onRemove,
  });
  final CartLine line;
  final VoidCallback onEditMaking;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final a = line.article;
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name.isEmpty ? a.barcode : a.name, style: T.body(15, w: FontWeight.w800)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                MonoTag(a.barcode),
                Chip2('${a.metal} ${a.karatLabel}', gold: true),
                StatusPill(line.reservationId != null ? 'HELD 15M' : 'IN CART'),
              ]),
            ]),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Pal.muted),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Pal.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            KeyValue('Net Wt × Rate', '${grams(a.effectiveNetWeight)} × ${rate(line.ratePerGram)}', mono: true),
            KeyValue('Metal Value', inr(line.metalValue.toStringAsFixed(2)), mono: true),
            InkWell(
              onTap: onEditMaking,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Text('Making Charges', style: T.body(12.8, color: Pal.teal, w: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 13, color: Pal.teal),
                  const Spacer(),
                  Text(inr(line.makingCharge), style: T.mono(13, color: Pal.teal, w: FontWeight.w700)),
                ]),
              ),
            ),
            KeyValue('GST (3%)', inr(line.gstAmount.toStringAsFixed(2)), mono: true),
            const Divider(),
            KeyValue('Line Total', inr(line.lineTotal.toStringAsFixed(2)), strong: true),
          ]),
        ),
      ]),
    );
  }
}

class _InvoiceReceiptSheet extends StatelessWidget {
  const _InvoiceReceiptSheet(this.r);
  final Map<String, dynamic> r;

  @override
  Widget build(BuildContext context) {
    final invNo = '${r['invoiceNumber'] ?? r['documentNumber'] ?? r['id'] ?? 'POS-INV'}';
    final total = '${r['totalAmount'] ?? r['grandTotal'] ?? r['netAmount'] ?? '0.00'}';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 30),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        LuxuryHeroCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const EnterpriseBadge('GST Tax Invoice Issued', icon: Icons.verified_rounded),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.copy_rounded, size: 17, color: Colors.white70),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: invNo));
                  toast(context, 'Invoice number copied.');
                },
              ),
            ]),
            const SizedBox(height: 10),
            Text(invNo, style: T.display(22, color: Colors.white)),
            const SizedBox(height: 6),
            Text(inr(total), style: T.display(30, color: Pal.goldSoft)),
          ]),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(children: [
            if (r['customerName'] != null) KeyValue('Patron', '${r['customerName']}', strong: true),
            if (r['metalSubtotal'] != null) KeyValue('Metal Value', inr(r['metalSubtotal']), mono: true),
            if (r['makingSubtotal'] != null) KeyValue('Making Charges', inr(r['makingSubtotal']), mono: true),
            if (r['gstAmount'] != null) KeyValue('GST (3%)', inr(r['gstAmount']), mono: true),
            if (r['oldGoldCredit'] != null) KeyValue('Old Gold Credit', '− ${inr(r['oldGoldCredit'])}', mono: true),
            if (r['paidAmount'] != null) KeyValue('Tender Collected', inr(r['paidAmount']), strong: true, valueColor: Pal.ok),
          ]),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Done · Start Next Bill'),
        ),
      ]),
    );
  }
}

class _SalesRegisterView extends StatefulWidget {
  const _SalesRegisterView();
  @override
  State<_SalesRegisterView> createState() => _SalesRegisterViewState();
}

class _SalesRegisterViewState extends State<_SalesRegisterView> {
  String _sub = 'INVOICES';
  List<Map<String, dynamic>> _invoices = [];
  List<Map<String, dynamic>> _estimates = [];
  List<Map<String, dynamic>> _credits = [];
  List<Map<String, dynamic>> _taxProfiles = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _activeForm; // null | 'TAX' | 'INVOICE' | 'CN'

  // Controlled Sales Posting Config
  final _periodId = TextEditingController();
  final _invSeriesId = TextEditingController();
  final _cnSeriesId = TextEditingController();
  final _jvSeriesId = TextEditingController();
  final _recvAcctId = TextEditingController();
  final _revAcctId = TextEditingController();
  final _taxAcctId = TextEditingController();
  final _cogsAcctId = TextEditingController();
  final _invAcctId = TextEditingController();

  // Tax Profile form (`createTaxProfileSchema`)
  final _tpCode = TextEditingController();
  final _tpName = TextEditingController();
  final _tpRate = TextEditingController(text: '3');
  final _tpEffFrom = TextEditingController(text: todayIso());
  bool _tpSynthetic = false;

  // Create Invoice from Estimate (`createSalesInvoiceSchema`)
  final _estId = TextEditingController();
  final _invDate = TextEditingController(text: todayIso());

  // Create Credit Note (`createCreditNoteSchema`)
  final _cnInvId = TextEditingController();
  final _cnDate = TextEditingController(text: todayIso());
  final _cnReason = TextEditingController();
  final _cnLineReason = TextEditingController();
  String _cnDisposition = 'RESTOCK';
  final _cnRestockLocId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _periodId, _invSeriesId, _cnSeriesId, _jvSeriesId, _recvAcctId,
      _revAcctId, _taxAcctId, _cogsAcctId, _invAcctId,
      _tpCode, _tpName, _tpRate, _tpEffFrom, _estId, _invDate,
      _cnInvId, _cnDate, _cnReason, _cnLineReason, _cnRestockLocId,
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
        api.get('/sales'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeInventory: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final d = asMap(res[0]);
      final lk = res[1] as WorkspaceLookup;
      if (_periodId.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _periodId.text = lk.openPeriods().first.id;
      }
      if (_jvSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['JOURNAL']);
        if (s.isNotEmpty) _jvSeriesId.text = s.first.id;
      }
      if (_invSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['SALES_INVOICE', 'INVOICE']);
        if (s.isNotEmpty) _invSeriesId.text = s.first.id;
      }
      if (_cnSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['CREDIT_NOTE', 'RETURN']);
        if (s.isNotEmpty) _cnSeriesId.text = s.first.id;
      }
      if (_recvAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['CUSTOMER_RECEIVABLE']);
        if (a.isNotEmpty) _recvAcctId.text = a.first.id;
      }
      if (_revAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['INCOME']);
        if (a.isNotEmpty) _revAcctId.text = a.first.id;
      }
      if (_taxAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['TAX_OUTPUT']);
        if (a.isNotEmpty) _taxAcctId.text = a.first.id;
      }
      if (_cogsAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['EXPENSE']);
        if (a.isNotEmpty) _cogsAcctId.text = a.first.id;
      }
      if (_invAcctId.text.isEmpty) {
        final a = lk.accountsByControl(const ['INVENTORY']);
        if (a.isNotEmpty) _invAcctId.text = a.first.id;
      }
      setState(() {
        _invoices = asList(d, keys: const ['invoices', 'salesInvoices']);
        _estimates = asList(d, keys: const ['estimates']);
        _credits = asList(d, keys: const ['creditNotes']);
        _taxProfiles = asList(d, keys: const ['taxProfiles']);
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mutate(Future<void> Function(ApiClient api) fn, String msg) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn(context.read<ApiClient>());
      if (!mounted) return;
      setState(() => _activeForm = null);
      toast(context, msg);
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estOpts = _estimates
        .map((e) => LookupOption(
              id: '${e['id']}',
              label: '${e['quoteNumber']} · ${asMap(e['customer'])['displayName'] ?? ''} · ${inr(e['totalAmount'])}',
              raw: e,
            ))
        .toList();
    final invOpts = _invoices
        .map((inv) => LookupOption(
              id: '${inv['id']}',
              label: '${inv['documentNumber'] ?? shortId('${inv['id']}')} · ${asMap(inv['customer'])['displayName'] ?? ''} · ${inr(inv['totalAmount'])}',
              raw: inv,
            ))
        .toList();

    return RefreshIndicator(
      color: Pal.gold,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          PillTabs<String>(
            value: _sub,
            onChanged: (v) => setState(() => _sub = v),
            tabs: [
              ('INVOICES', 'Invoices (${_invoices.length})'),
              ('ESTIMATES', 'Estimates (${_estimates.length})'),
              ('CREDITS', 'Credit Notes (${_credits.length})'),
              ('TAX_PROFILES', 'Tax Profiles (${_taxProfiles.length})'),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _activeForm = _activeForm == 'TAX' ? null : 'TAX'),
                  icon: const Icon(Icons.percent_rounded, size: 15),
                  label: const Text('+ Tax Profile'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _activeForm = _activeForm == 'INVOICE' ? null : 'INVOICE'),
                  icon: const Icon(Icons.receipt_long_rounded, size: 15),
                  label: const Text('+ Invoice from Estimate'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _activeForm = _activeForm == 'CN' ? null : 'CN'),
                  icon: const Icon(Icons.assignment_return_outlined, size: 15),
                  label: const Text('+ Credit Note'),
                ),
              ],
            ),
          ),
          if (_error != null) ...[const SizedBox(height: 10), ErrorBanner(_error!, onRetry: _load)],

          if (_activeForm == 'TAX') ...[
            const SizedBox(height: 12),
            SaasFormCard(
              title: 'New GST Tax Profile',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: SaasField(label: 'Code (GST_3)', controller: _tpCode, mono: true)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Rate (%)',
                          controller: _tpRate,
                          mono: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(label: 'Tax profile name', controller: _tpName),
                  const SizedBox(height: 10),
                  DatePickField(label: 'Effective from', controller: _tpEffFrom),
                  const SizedBox(height: 8),
                  SaasCheckRow(
                    label: 'Synthetic test profile only',
                    value: _tpSynthetic,
                    onChanged: (v) => setState(() => _tpSynthetic = v),
                  ),
                  const SizedBox(height: 10),
                  GoldButton(
                    label: 'Create Tax Profile',
                    busy: _busy,
                    onPressed: () => _mutate(
                      (api) => api.post('/sales/tax-profiles', body: {
                        'code': _tpCode.text.trim().toUpperCase(),
                        'name': _tpName.text.trim(),
                        'ratePercent': _tpRate.text.trim(),
                        'syntheticTestOnly': _tpSynthetic,
                        'effectiveFrom': _tpEffFrom.text.trim(),
                      }),
                      'Tax profile created.',
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_activeForm == 'INVOICE') ...[
            const SizedBox(height: 12),
            SaasFormCard(
              title: 'Create Sales Invoice from Estimate',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(label: 'Estimate', controller: _estId, options: estOpts),
                  const SizedBox(height: 10),
                  DatePickField(label: 'Invoice date', controller: _invDate),
                  const SizedBox(height: 10),
                  LookupField(label: 'Receivable account', controller: _recvAcctId, options: _lk.accounts),
                  const SizedBox(height: 10),
                  LookupField(label: 'Revenue account', controller: _revAcctId, options: _lk.accounts),
                  const SizedBox(height: 10),
                  LookupField(label: 'Output tax account', controller: _taxAcctId, options: _lk.accounts, optional: true),
                  const SizedBox(height: 10),
                  LookupField(label: 'COGS account', controller: _cogsAcctId, options: _lk.accounts),
                  const SizedBox(height: 10),
                  LookupField(label: 'Inventory account', controller: _invAcctId, options: _lk.accounts),
                  const SizedBox(height: 12),
                  GoldButton(
                    label: 'Create Sales Invoice',
                    busy: _busy,
                    onPressed: () => _mutate(
                      (api) => api.post('/sales/invoices', idempotent: true, body: {
                        'estimateId': _estId.text.trim(),
                        'invoiceDate': _invDate.text.trim(),
                        'reservationExpiresAt': DateTime.now().toUtc().add(const Duration(hours: 4)).toIso8601String(),
                        'receivableAccountId': _recvAcctId.text.trim(),
                        'revenueAccountId': _revAcctId.text.trim(),
                        if (_taxAcctId.text.trim().isNotEmpty) 'outputTaxAccountId': _taxAcctId.text.trim(),
                        'cogsAccountId': _cogsAcctId.text.trim(),
                        'inventoryAccountId': _invAcctId.text.trim(),
                      }),
                      'Draft sales invoice created.',
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_activeForm == 'CN') ...[
            const SizedBox(height: 12),
            SaasFormCard(
              title: 'New Sales Credit Note / Return',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(label: 'Posted Sales Invoice', controller: _cnInvId, options: invOpts),
                  const SizedBox(height: 10),
                  DatePickField(label: 'Credit note date', controller: _cnDate),
                  const SizedBox(height: 10),
                  SaasDropdown(
                    label: 'Disposition',
                    value: _cnDisposition,
                    options: const {
                      'RESTOCK': 'RESTOCK',
                      'QUARANTINE': 'QUARANTINE',
                      'SCRAP': 'SCRAP',
                    },
                    onChanged: (v) => setState(() => _cnDisposition = v),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Restock location (optional)',
                    controller: _cnRestockLocId,
                    options: _lk.locations,
                    optional: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(label: 'Line return reason (min 5 chars)', controller: _cnLineReason),
                  const SizedBox(height: 10),
                  SaasField(label: 'Credit note reason (min 10 chars)', controller: _cnReason),
                  const SizedBox(height: 12),
                  GoldButton(
                    label: 'Create Credit Note',
                    busy: _busy,
                    onPressed: () {
                      final inv = _invoices.where((i) => '${i['id']}' == _cnInvId.text.trim()).firstOrNull;
                      final invLines = asList(inv?['lines']);
                      if (invLines.isEmpty) {
                        setState(() => _error = 'Select a sales invoice with at least one line.');
                        return;
                      }
                      _mutate(
                        (api) => api.post('/sales/credit-notes', idempotent: true, body: {
                          'salesInvoiceId': _cnInvId.text.trim(),
                          'creditNoteDate': _cnDate.text.trim(),
                          'reason': _cnReason.text.trim(),
                          'lines': [
                            {
                              'salesInvoiceLineId': '${invLines.first['id']}',
                              'returnReason': _cnLineReason.text.trim(),
                              'qcState': 'PASSED',
                              'disposition': _cnDisposition,
                              if (_cnRestockLocId.text.trim().isNotEmpty)
                                'restockLocationId': _cnRestockLocId.text.trim(),
                            },
                          ],
                        }),
                        'Sales credit note draft created.',
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
          if (_loading)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_sub == 'TAX_PROFILES')
            _taxProfiles.isEmpty
                ? const SaasEmptyBox('No tax profiles configured yet.')
                : Column(
                    children: [
                      for (final tp in _taxProfiles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SectionCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('${tp['code']} · ${tp['name']}', style: T.body(14, w: FontWeight.w700)),
                                    ),
                                    StatusChip('${tp['state'] ?? 'DRAFT'}'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                KVRow('Rate / Effective', '${tp['ratePercent']}% · ${fmtDate('${tp['effectiveFrom'] ?? ''}')}', bold: true),
                                if ('${tp['state']}' == 'DRAFT') ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _mutate(
                                                (api) => api.post('/sales/tax-profiles/${tp['id']}/approve', body: {
                                                  'expectedVersion': asInt(tp['version'], fallback: 1),
                                                  'reason': 'Approved GST tax profile after statutory rate verification.',
                                                }),
                                                'Tax profile approved.',
                                              ),
                                      child: const Text('Approve'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
          else if (_sub == 'ESTIMATES')
            _estimates.isEmpty
                ? const SaasEmptyBox('No estimates generated yet.')
                : Column(
                    children: [
                      for (final est in _estimates)
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
                                        '${est['quoteNumber']} · ${asMap(est['customer'])['displayName'] ?? ''}',
                                        style: T.body(14, w: FontWeight.w700),
                                      ),
                                    ),
                                    StatusChip('${est['state'] ?? 'OPEN'}'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                KVRow('Metal / Making', '${inr(est['metalValue'])} / ${inr(est['makingAmount'])}'),
                                KVRow('Tax / Total', '${inr(est['taxAmount'])} / ${inr(est['totalAmount'])}', bold: true),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
          else if (_sub == 'CREDITS')
            _credits.isEmpty
                ? const SaasEmptyBox('No sales credit notes recorded yet.')
                : Column(
                    children: [
                      for (final cn in _credits)
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
                                        '${cn['documentNumber'] ?? shortId('${cn['id']}')} · ${asMap(cn['customer'])['displayName'] ?? ''}',
                                        style: T.body(14, w: FontWeight.w700),
                                      ),
                                    ),
                                    StatusChip('${cn['state'] ?? 'DRAFT'}'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                KVRow('Reason', '${cn['reason'] ?? ''}'),
                                KVRow('Total Amount', inr(cn['totalAmount']), bold: true),
                                if ('${cn['state']}' == 'DRAFT' || '${cn['state']}' == 'APPROVED') ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed: _busy
                                          ? null
                                          : () {
                                              if ('${cn['state']}' == 'DRAFT') {
                                                _mutate(
                                                  (api) => api.post('/sales/credit-notes/${cn['id']}/approve', body: {
                                                    'expectedVersion': asInt(cn['version'], fallback: 1),
                                                    'reason': 'Approved sales return credit note after QC verification.',
                                                  }),
                                                  'Credit note approved.',
                                                );
                                              } else {
                                                _mutate(
                                                  (api) => api.post('/sales/credit-notes/${cn['id']}/post', idempotent: true, body: {
                                                    'expectedVersion': asInt(cn['version'], fallback: 1),
                                                    'postingPeriodId': _periodId.text.trim(),
                                                    'documentSeriesId': _cnSeriesId.text.trim(),
                                                    'journalSeriesId': _jvSeriesId.text.trim(),
                                                    'reason': 'Posted approved sales credit note to inventory & AR.',
                                                  }),
                                                  'Credit note posted.',
                                                );
                                              }
                                            },
                                      child: Text('${cn['state']}' == 'DRAFT' ? 'Approve' : 'Post Return'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  )
          else
            _invoices.isEmpty
                ? const SaasEmptyBox('No sales invoices created yet.')
                : Column(
                    children: [
                      for (final inv in _invoices)
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
                                        '${inv['documentNumber'] ?? shortId('${inv['id']}')} · ${asMap(inv['customer'])['displayName'] ?? ''}',
                                        style: T.body(14, w: FontWeight.w700),
                                      ),
                                    ),
                                    StatusChip('${inv['state'] ?? 'DRAFT'}'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                KVRow('Date', fmtDate('${inv['invoiceDate'] ?? ''}')),
                                KVRow('Taxable / Tax', '${inr(inv['taxableAmount'])} / ${inr(inv['taxAmount'])}'),
                                KVRow('Total / Outstanding', '${inr(inv['totalAmount'])} / ${inr(inv['outstandingAmount'])}', bold: true),
                                if ('${inv['state']}' == 'DRAFT') ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed: _busy
                                          ? null
                                          : () => _mutate(
                                                (api) => api.post('/sales/invoices/${inv['id']}/post', idempotent: true, body: {
                                                  'expectedVersion': asInt(inv['version'], fallback: 1),
                                                  'postingPeriodId': _periodId.text.trim(),
                                                  'documentSeriesId': _invSeriesId.text.trim(),
                                                  'journalSeriesId': _jvSeriesId.text.trim(),
                                                  'reason': 'Posted showroom sales invoice to AR & inventory ledger.',
                                                }),
                                                'Sales invoice posted.',
                                              ),
                                      child: const Text('Post Invoice'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
        ],
      ),
    );
  }
}
