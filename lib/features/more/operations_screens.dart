import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customers/customers_screen.dart';
import '../inventory/scanner_page.dart';

String _firstStr(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v is Map) {
      final inner = v['displayName'] ?? v['name'] ?? v['code'] ?? v['tag'];
      if (inner != null && '$inner'.isNotEmpty) return '$inner';
    } else if (v != null && '$v'.isNotEmpty && v is! List) {
      return '$v';
    }
  }
  return fallback;
}

// ============================================================================
// 1. APPROVAL MEMOS (JANGAD) — GET /approval-memos, POST /approval-memos, POST /:id/return
// ============================================================================

class ApprovalMemosScreen extends StatefulWidget {
  const ApprovalMemosScreen({super.key});
  @override
  State<ApprovalMemosScreen> createState() => _ApprovalMemosScreenState();
}

class _ApprovalMemosScreenState extends State<ApprovalMemosScreen> {
  List<Map<String, dynamic>> _memos = [];
  bool _loading = true;
  String? _error;
  String? _returningId;

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
    try {
      final d = await context.read<ApiClient>().get('/approval-memos');
      if (mounted) {
        setState(() => _memos = asList(d, keys: const ['memos', 'approvalMemos', 'items', 'rows']));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _returnMemo(Map<String, dynamic> memo) async {
    final id = _firstStr(memo, ['id', 'memoId']);
    if (id.isEmpty) return;
    setState(() => _returningId = id);
    try {
      await context.read<ApiClient>().post(
            '/approval-memos/$id/return',
            idempotencyKey: const Uuid().v4(),
            body: {'reason': 'Returned to showroom custody and inspected.'},
          );
      await _load();
      if (mounted) toast(context, 'Jangad memo returned to vault custody.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _returningId = null);
  }

  Future<void> _issueSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateJangadSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approval Memos (Jangad)'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _issueSheet,
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text('Issue Jangad', style: T.body(13.5, color: Colors.white, w: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: Pal.teal,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
          children: [
            LuxuryHeroCard(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const EnterpriseBadge('Custody Handover', icon: Icons.handshake_outlined),
                const SizedBox(height: 10),
                Text('VIP & Agent Jangad Register', style: T.display(21, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  'Track ornaments handed out on approval to VIP patrons or sales executives with full Fine 999 custody accountability.',
                  style: T.body(12.5, color: Colors.white70),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 76)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_memos.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.handshake_outlined,
                  title: 'No active Jangad memos',
                  body: 'Tap "Issue Jangad" to record ornaments handed out on approval.',
                ),
              )
            else
              for (final m in _memos)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _memoCard(m),
                ),
          ],
        ),
      ),
    );
  }

  Widget _memoCard(Map<String, dynamic> m) {
    final id = _firstStr(m, ['id', 'memoId']);
    final status = _firstStr(m, ['status', 'state'], 'ON_APPROVAL');
    final canReturn = ['OPEN', 'ISSUED', 'ON_APPROVAL', 'ACTIVE'].contains(status.toUpperCase());
    final party = _firstStr(m, ['customer', 'party', 'customerName', 'partyName'], 'VIP Patron');
    final wt = _firstStr(m, ['grossWeightGrams', 'totalWeightGrams', 'netWeightGrams']);
    final val = _firstStr(m, ['estimatedValue', 'totalAmount', 'valuation']);
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              _firstStr(m, ['memoNumber', 'documentNumber', 'code'], 'Jangad Memo'),
              style: T.display(17.5),
            ),
          ),
          StatusPill(status),
        ]),
        const SizedBox(height: 8),
        KeyValue('Recipient / Party', party, strong: true),
        if (wt.isNotEmpty) KeyValue('Handed Weight', grams(wt), mono: true),
        if (val.isNotEmpty) KeyValue('Declared Value', inr(val), mono: true),
        if (_firstStr(m, ['dueDate', 'expiresAt']).isNotEmpty)
          KeyValue('Return Due', formatDate(_firstStr(m, ['dueDate', 'expiresAt']))),
        if (_firstStr(m, ['createdAt', 'issueDate']).isNotEmpty)
          KeyValue('Issued On', formatDateTime(_firstStr(m, ['createdAt', 'issueDate']))),
        if (canReturn && id.isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _returningId == id ? null : () => _returnMemo(m),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
            icon: _returningId == id
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.assignment_return_outlined, size: 17),
            label: const Text('Mark Returned to Vault'),
          ),
        ],
      ]),
    );
  }
}

class _CreateJangadSheet extends StatefulWidget {
  const _CreateJangadSheet();
  @override
  State<_CreateJangadSheet> createState() => _CreateJangadSheetState();
}

class _CreateJangadSheetState extends State<_CreateJangadSheet> {
  Party? _party;
  final _barcode = TextEditingController();
  final _notes = TextEditingController();
  int _days = 3;
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _barcode.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_party == null) {
      setState(() => _err = 'Select the customer or agent receiving the piece.');
      return;
    }
    if (_barcode.text.trim().isEmpty) {
      setState(() => _err = 'Scan or enter the article tag / barcode.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final api = context.read<ApiClient>();
      // Resolve articleId from barcode if available
      String? articleId;
      try {
        final inv = await api.get('/inventory', query: {'barcode': _barcode.text.trim()});
        final articles = asList(inv, keys: const ['articles']);
        if (articles.isNotEmpty) {
          final match = articles.firstWhere(
            (a) => '${a['tag'] ?? a['barcode']}'.toUpperCase() == _barcode.text.trim().toUpperCase(),
            orElse: () => articles.first,
          );
          articleId = '${match['id'] ?? match['articleId'] ?? ''}';
        } else {
          final single = asMap(inv);
          articleId = '${single['articleId'] ?? single['id'] ?? ''}';
        }
      } catch (_) {}

      final due = DateTime.now().add(Duration(days: _days)).toUtc().toIso8601String();
      await api.post(
        '/approval-memos',
        idempotencyKey: const Uuid().v4(),
        body: {
          'customerId': _party!.id,
          'partyId': _party!.id,
          'barcode': _barcode.text.trim().toUpperCase(),
          if (articleId != null && articleId.isNotEmpty) 'articleId': articleId,
          if (articleId != null && articleId.isNotEmpty) 'articleIds': [articleId],
          'dueDate': due.substring(0, 10),
          'expiresAt': due,
          if (_notes.text.trim().isNotEmpty) 'remarks': _notes.text.trim(),
        },
      );
      if (mounted) {
        toast(context, 'Jangad approval memo issued.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Issue Approval Memo (Jangad)', style: T.display(22)),
        const SizedBox(height: 16),
        Panel(
          onTap: () async {
            final p = await showCustomerPicker(context);
            if (p != null) setState(() => _party = p);
          },
          child: Row(children: [
            const Icon(Icons.person_outline_rounded, color: Pal.goldDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _party?.name ?? 'Select VIP Customer / Agent',
                style: T.body(14, w: FontWeight.w700, color: _party == null ? Pal.muted : Pal.text),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Pal.muted),
          ]),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Piece Barcode / Tag'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _barcode,
              textCapitalization: TextCapitalization.characters,
              style: T.mono(14),
              decoration: const InputDecoration(hintText: 'Enter tag / barcode'),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 50,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(50, 50)),
              onPressed: () async {
                final v = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScannerPage()));
                if (v != null) setState(() => _barcode.text = v);
              },
              child: const Icon(Icons.qr_code_scanner_rounded),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        const FieldLabel('Approval Return Window'),
        Wrap(spacing: 8, children: [
          for (final d in const [1, 3, 7, 14])
            ChoiceChip(
              label: Text('$d ${d == 1 ? 'Day' : 'Days'}'),
              selected: _days == d,
              showCheckmark: false,
              selectedColor: Pal.goldWash,
              onSelected: (_) => setState(() => _days = d),
            ),
        ]),
        const SizedBox(height: 14),
        const FieldLabel('Handover Remarks'),
        TextField(controller: _notes, decoration: const InputDecoration(hintText: 'Bridal trial handover')),
        if (_err != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: T.body(13, color: Pal.danger, w: FontWeight.w700))),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Pal.teal),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Text('Issue Jangad Handover'),
        ),
      ]),
    );
  }
}

// ============================================================================
// 2. RATE FIXING / ADVANCE BOOKING — GET /rate-fixing, POST /rate-fixing
// ============================================================================

class RateFixingScreen extends StatefulWidget {
  const RateFixingScreen({super.key});
  @override
  State<RateFixingScreen> createState() => _RateFixingScreenState();
}

class _RateFixingScreenState extends State<RateFixingScreen> {
  List<Map<String, dynamic>> _locks = [];
  bool _loading = true;
  String? _error;

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
    try {
      final d = await context.read<ApiClient>().get('/rate-fixing');
      if (mounted) {
        setState(() => _locks = asList(d, keys: const ['rateFixings', 'bookings', 'items', 'rows']));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _bookSheet() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BookRateSheet(),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rate Fixing & Advances'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bookSheet,
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.lock_clock_rounded),
        label: Text('Lock Gold Rate', style: T.body(13.5, color: Colors.white, w: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: Pal.teal,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
          children: [
            LuxuryHeroCard(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const EnterpriseBadge('Price Hedge', icon: Icons.lock_clock_rounded),
                const SizedBox(height: 10),
                Text('Customer Bullion Rate Locks', style: T.display(21, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  'Lock today\'s live showroom gold/silver rate against customer advance receipts for upcoming bridal or custom orders.',
                  style: T.body(12.5, color: Colors.white70),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 76)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_locks.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.lock_clock_rounded,
                  title: 'No active rate-lock bookings',
                  body: 'Tap "Lock Gold Rate" to book a customer advance at today\'s bullion rate.',
                ),
              )
            else
              for (final r in _locks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _firstStr(r, ['bookingNumber', 'documentNumber', 'referenceNumber', 'code'], 'Rate Lock'),
                            style: T.display(17.5),
                          ),
                        ),
                        StatusPill(_firstStr(r, ['status', 'state'], 'ACTIVE')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Customer', _firstStr(r, ['customer', 'party', 'customerName'], 'Customer'), strong: true),
                      if (_firstStr(r, ['metal', 'purity']).isNotEmpty)
                        KeyValue('Metal / Purity', '${_firstStr(r, ['metal'], 'GOLD')} ${_firstStr(r, ['purity'], '916')}'),
                      if (_firstStr(r, ['lockedRatePerGram', 'ratePerGram', 'lockedRate']).isNotEmpty)
                        KeyValue('Locked Rate / g', rate(_firstStr(r, ['lockedRatePerGram', 'ratePerGram', 'lockedRate'])), mono: true),
                      if (_firstStr(r, ['bookedWeightGrams', 'weightGrams']).isNotEmpty)
                        KeyValue('Booked Weight', grams(_firstStr(r, ['bookedWeightGrams', 'weightGrams'])), mono: true),
                      if (_firstStr(r, ['advanceAmount', 'amount']).isNotEmpty)
                        KeyValue('Advance Paid', inr(_firstStr(r, ['advanceAmount', 'amount'])), strong: true, valueColor: Pal.teal),
                      if (_firstStr(r, ['expiresAt', 'validUntil']).isNotEmpty)
                        KeyValue('Valid Until', formatDate(_firstStr(r, ['expiresAt', 'validUntil']))),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _BookRateSheet extends StatefulWidget {
  const _BookRateSheet();
  @override
  State<_BookRateSheet> createState() => _BookRateSheetState();
}

class _BookRateSheetState extends State<_BookRateSheet> {
  Party? _party;
  String _purity = '916';
  final _weight = TextEditingController();
  final _rate = TextEditingController();
  final _advance = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final m = context.read<RatesController>().find('GOLD', _purity);
      if (m != null && m.sell != '0.00') {
        setState(() => _rate.text = m.sell);
      }
    });
  }

  @override
  void dispose() {
    _weight.dispose();
    _rate.dispose();
    _advance.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_party == null) {
      setState(() => _err = 'Select the customer booking the rate.');
      return;
    }
    if (!isValidWeight(_weight.text) || !isValidAmount(_rate.text) || !isValidAmount(_advance.text)) {
      setState(() => _err = 'Enter valid weight (g), rate per gram, and advance received.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await context.read<ApiClient>().post(
            '/rate-fixing',
            idempotencyKey: const Uuid().v4(),
            body: {
              'customerId': _party!.id,
              'partyId': _party!.id,
              'metal': 'GOLD',
              'purity': _purity,
              'bookedWeightGrams': normWeight6(_weight.text),
              'lockedRatePerGram': normAmount(_rate.text),
              'advanceAmount': normAmount(_advance.text),
              'paymentMode': 'UPI',
            },
          );
      if (mounted) {
        toast(context, 'Gold rate locked for ${_party!.name}.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Book Customer Rate Lock', style: T.display(22)),
        const SizedBox(height: 16),
        Panel(
          onTap: () async {
            final p = await showCustomerPicker(context);
            if (p != null) setState(() => _party = p);
          },
          child: Row(children: [
            const Icon(Icons.person_outline_rounded, color: Pal.goldDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _party?.name ?? 'Select Customer',
                style: T.body(14, w: FontWeight.w700, color: _party == null ? Pal.muted : Pal.text),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Pal.muted),
          ]),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Gold Purity'),
        Wrap(spacing: 8, children: [
          for (final p in const [('999', '24K · 999'), ('916', '22K · 916'), ('750', '18K · 750')])
            ChoiceChip(
              label: Text(p.$2),
              selected: _purity == p.$1,
              showCheckmark: false,
              selectedColor: Pal.goldWash,
              onSelected: (_) {
                setState(() => _purity = p.$1);
                final m = context.read<RatesController>().find('GOLD', p.$1);
                if (m != null && m.sell != '0.00') _rate.text = m.sell;
              },
            ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Target Weight (g)'),
              TextField(
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: T.mono(15),
                decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Locked Rate / g'),
              TextField(
                controller: _rate,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: T.mono(15),
                decoration: const InputDecoration(prefixText: '₹ '),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        const FieldLabel('Advance Payment Received (INR)'),
        TextField(
          controller: _advance,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: T.mono(16, w: FontWeight.w700),
          decoration: const InputDecoration(prefixText: '₹ ', hintText: '0.00'),
        ),
        if (_err != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: T.body(13, color: Pal.danger, w: FontWeight.w700))),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Pal.teal),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Text('Confirm Rate Lock'),
        ),
      ]),
    );
  }
}

// ============================================================================
// 3. KARIGAR JOB WORK — GET /job-work, POST /job-work/issues, POST /job-work/receipts
// ============================================================================

class JobWorkScreen extends StatefulWidget {
  const JobWorkScreen({super.key});
  @override
  State<JobWorkScreen> createState() => _JobWorkScreenState();
}

class _JobWorkScreenState extends State<JobWorkScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;
  String? _error;

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
    try {
      final d = await context.read<ApiClient>().get('/job-work');
      if (mounted) {
        setState(() => _jobs = asList(d, keys: const ['orders', 'issues', 'jobWorks', 'items', 'rows']));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _issueGoldSheet() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _KarigarIssueSheet(),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Karigar Job Work'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _issueGoldSheet,
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.handyman_outlined),
        label: Text('Issue Bullion', style: T.body(13.5, color: Colors.white, w: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: Pal.teal,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 96),
          children: [
            LuxuryHeroCard(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const EnterpriseBadge('Artisan Custody', icon: Icons.handyman_outlined),
                const SizedBox(height: 10),
                Text('Karigar Bullion Ledger', style: T.display(21, color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  'Issue pure/alloyed gold to master artisans, monitor wastage tolerances, and reconcile received handcrafted ornaments.',
                  style: T.body(12.5, color: Colors.white70),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 76)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_jobs.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.handyman_outlined,
                  title: 'No active Karigar job orders',
                  body: 'Tap "Issue Bullion" to issue gold to a Karigar for ornament fabrication.',
                ),
              )
            else
              for (final j in _jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            _firstStr(j, ['jobNumber', 'voucherNumber', 'documentNumber', 'code'], 'Karigar Order'),
                            style: T.display(17.5),
                          ),
                        ),
                        StatusPill(_firstStr(j, ['status', 'state'], 'ISSUED')),
                      ]),
                      const SizedBox(height: 8),
                      KeyValue('Karigar / Artisan', _firstStr(j, ['karigar', 'party', 'karigarName', 'artisanName'], 'Artisan'), strong: true),
                      if (_firstStr(j, ['issuedWeightGrams', 'grossWeightGrams', 'weightGrams']).isNotEmpty)
                        KeyValue('Issued Metal', grams(_firstStr(j, ['issuedWeightGrams', 'grossWeightGrams', 'weightGrams'])), mono: true),
                      if (_firstStr(j, ['fineWeightGrams', 'issuedFineGrams']).isNotEmpty)
                        KeyValue('Fine 999 Wt', fineGrams(_firstStr(j, ['fineWeightGrams', 'issuedFineGrams'])), mono: true),
                      if (_firstStr(j, ['receivedWeightGrams']).isNotEmpty)
                        KeyValue('Received Wt', grams(_firstStr(j, ['receivedWeightGrams'])), mono: true),
                      if (_firstStr(j, ['dueDate', 'expectedDate']).isNotEmpty)
                        KeyValue('Expected Receipt', formatDate(_firstStr(j, ['dueDate', 'expectedDate']))),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _KarigarIssueSheet extends StatefulWidget {
  const _KarigarIssueSheet();
  @override
  State<_KarigarIssueSheet> createState() => _KarigarIssueSheetState();
}

class _KarigarIssueSheetState extends State<_KarigarIssueSheet> {
  Party? _karigar;
  String _purity = '999';
  final _weight = TextEditingController();
  final _desc = TextEditingController();
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _weight.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_karigar == null) {
      setState(() => _err = 'Select the Karigar / artisan party.');
      return;
    }
    if (!isValidWeight(_weight.text)) {
      setState(() => _err = 'Enter valid bullion weight in grams.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await context.read<ApiClient>().post(
            '/job-work/issues',
            idempotencyKey: const Uuid().v4(),
            body: {
              'karigarId': _karigar!.id,
              'partyId': _karigar!.id,
              'metal': 'GOLD',
              'purity': _purity,
              'grossWeightGrams': normWeight6(_weight.text),
              'description': _desc.text.trim().isEmpty ? '22K Ornament Fabrication' : _desc.text.trim(),
            },
          );
      if (mounted) {
        toast(context, 'Bullion issue voucher created for ${_karigar!.name}.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Issue Gold to Karigar', style: T.display(22)),
        const SizedBox(height: 16),
        Panel(
          onTap: () async {
            final p = await showCustomerPicker(context);
            if (p != null) setState(() => _karigar = p);
          },
          child: Row(children: [
            const Icon(Icons.engineering_outlined, color: Pal.goldDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _karigar?.name ?? 'Select Karigar / Artisan',
                style: T.body(14, w: FontWeight.w700, color: _karigar == null ? Pal.muted : Pal.text),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Pal.muted),
          ]),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Issued Gold Purity'),
        Wrap(spacing: 8, children: [
          for (final p in const [('999', 'Fine 999'), ('916', '22K · 916'), ('750', '18K · 750')])
            ChoiceChip(
              label: Text(p.$2),
              selected: _purity == p.$1,
              showCheckmark: false,
              selectedColor: Pal.goldWash,
              onSelected: (_) => setState(() => _purity = p.$1),
            ),
        ]),
        const SizedBox(height: 14),
        const FieldLabel('Issued Weight (g)'),
        TextField(
          controller: _weight,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: T.mono(16, w: FontWeight.w700),
          decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
        ),
        const SizedBox(height: 14),
        const FieldLabel('Job Instructions / Design Spec'),
        TextField(controller: _desc, decoration: const InputDecoration(hintText: 'Ornament specification / notes')),
        if (_err != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: T.body(13, color: Pal.danger, w: FontWeight.w700))),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Pal.teal),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Text('Record Bullion Issue'),
        ),
      ]),
    );
  }
}

// ============================================================================
// 4. PROCUREMENT WORKSPACE — Matches ProcurementPanel.tsx (GET /procurement)
// ============================================================================

class ProcurementScreen extends StatefulWidget {
  const ProcurementScreen({super.key});
  @override
  State<ProcurementScreen> createState() => _ProcurementScreenState();
}

class _ProcurementScreenState extends State<ProcurementScreen> {
  String _tab = 'PO';
  List<Map<String, dynamic>> _pos = [];
  List<Map<String, dynamic>> _grns = [];
  List<Map<String, dynamic>> _bills = [];
  List<Map<String, dynamic>> _returns = [];
  bool _loading = true;
  String? _error;

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
    try {
      final d = await context.read<ApiClient>().get('/procurement');
      if (!mounted) return;
      if (d is Map) {
        setState(() {
          _pos = asList(d, keys: const ['purchaseOrders']);
          _grns = asList(d, keys: const ['goodsReceipts']);
          _bills = asList(d, keys: const ['supplierBills']);
          _returns = asList(d, keys: const ['purchaseReturns']);
        });
      } else {
        setState(() => _pos = asList(d));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Procurement & Inward'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.teal,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
          children: [
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: [
                ('PO', 'Purchase Orders (${_pos.length})', Icons.shopping_bag_outlined),
                ('GRN', 'Goods Receipts (${_grns.length})', Icons.inventory_outlined),
                ('BILLS', 'Supplier Bills (${_bills.length})', Icons.receipt_outlined),
                ('RET', 'Returns (${_returns.length})', Icons.keyboard_return_rounded),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 82)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else
              ..._buildActiveList(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActiveList() {
    final rows = switch (_tab) {
      'PO' => _pos,
      'GRN' => _grns,
      'BILLS' => _bills,
      _ => _returns,
    };
    if (rows.isEmpty) {
      return [
        Panel(
          child: EmptyBlock(
            icon: Icons.local_shipping_outlined,
            title: 'No records in this register',
            body: 'Supplier purchase orders, inward QC receipts, and bills created on the portal sync here live.',
          ),
        ),
      ];
    }
    return [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    _firstStr(r, ['documentNumber', 'supplierInvoiceNumber', 'supplierDeliveryNote', 'id'], 'Procurement Doc').length > 22
                        ? _firstStr(r, ['documentNumber', 'supplierInvoiceNumber', 'supplierDeliveryNote', 'id']).substring(0, 13).toUpperCase()
                        : _firstStr(r, ['documentNumber', 'supplierInvoiceNumber', 'supplierDeliveryNote', 'id'], 'Procurement Doc'),
                    style: T.display(17),
                  ),
                ),
                StatusPill(_firstStr(r, ['state', 'status', 'matchState'], 'POSTED')),
              ]),
              const SizedBox(height: 8),
              KeyValue('Supplier', _firstStr(r, ['supplier'], 'Bullion Supplier'), strong: true),
              if (_firstStr(r, ['orderDate', 'receiptDate', 'postingDate', 'returnDate']).isNotEmpty)
                KeyValue('Date', formatDate(_firstStr(r, ['orderDate', 'receiptDate', 'postingDate', 'returnDate']))),
              if (_firstStr(r, ['subtotal', 'netAmount', 'acceptedNetAmount']).isNotEmpty)
                KeyValue('Net Value', inr(_firstStr(r, ['subtotal', 'netAmount', 'acceptedNetAmount'])), mono: true),
              if (_firstStr(r, ['taxAmount']).isNotEmpty)
                KeyValue('GST Input', inr(_firstStr(r, ['taxAmount'])), mono: true),
              if (_firstStr(r, ['totalAmount']).isNotEmpty)
                KeyValue('Total Amount', inr(_firstStr(r, ['totalAmount'])), strong: true),
              if (r['lines'] is List)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${(r['lines'] as List).length} line item(s)',
                    style: T.body(12, color: Pal.muted, w: FontWeight.w600),
                  ),
                ),
            ]),
          ),
        ),
    ];
  }
}
