import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Counter cash-drawer shift: open at start of day, close with counted cash.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});
  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  Map<String, dynamic>? _shift;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _cash = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  bool get _isOpen {
    final s = _shift;
    if (s == null || s.isEmpty) return false;
    final st = '${s['status'] ?? 'OPEN'}'.toUpperCase();
    return st == 'OPEN';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/pos-shifts/current');
      if (mounted) setState(() => _shift = d == null ? null : asMap(d));
    } on ApiException catch (e) {
      // A 404 here simply means no shift is open.
      if (e.status == 404) {
        if (mounted) setState(() => _shift = null);
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _act(bool open) async {
    if (!isValidAmount(_cash.text)) {
      setState(() => _error = 'Enter the cash in the drawer, in rupees.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
            open ? '/pos-shifts/open' : '/pos-shifts/close',
            body: {open ? 'openingCash' : 'closingCash': normAmount(_cash.text)},
          );
      _cash.clear();
      await _load();
      if (mounted) toast(context, open ? 'Shift opened.' : 'Shift closed.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Counter shift')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
        if (_loading)
          const Panel(child: Skeleton(height: 70))
        else ...[
          Panel(
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(color: _isOpen ? Pal.okWash : const Color(0xFFEDEBE5), shape: BoxShape.circle),
                child: Icon(_isOpen ? Icons.lock_open_rounded : Icons.lock_outline_rounded, color: _isOpen ? Pal.ok : Pal.muted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_isOpen ? 'Shift is open' : 'No shift open', style: T.display(21)),
                  Text(_isOpen ? 'Billing is active on this counter.' : 'Open a shift before the first sale.', style: T.body(13.5, color: Pal.muted)),
                ]),
              ),
            ]),
          ),
          if (_isOpen && _shift != null) ...[
            const SizedBox(height: 12),
            Panel(
              child: Column(children: [
                for (final e in _shift!.entries.where((e) => e.value is! Map && e.value is! List && e.value != null && !e.key.toLowerCase().endsWith('id')).take(6))
                  KeyValue(humanize(e.key), _fmt(e.key, e.value)),
              ]),
            ),
          ],
          const SectionLabel('Cash in drawer'),
          TextField(
            controller: _cash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: T.display(24),
            decoration: InputDecoration(prefixText: '₹ ', hintText: '0.00', helperText: _isOpen ? 'Count the drawer before you close.' : 'Opening float for today.'),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: T.body(13.5, color: Pal.danger, w: FontWeight.w700))),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : () => _act(!_isOpen),
            child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : Text(_isOpen ? 'Close shift' : 'Open shift'),
          ),
        ],
      ]),
    );
  }

  String _fmt(String key, dynamic v) {
    final k = key.toLowerCase();
    final s = '$v';
    if (looksNumeric(s) && (k.contains('cash') || k.contains('amount') || k.contains('total'))) return inr(s);
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) return s.substring(0, 16).replaceFirst('T', '  ');
    return s;
  }
}
