import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Party> _all = [];
  bool _loading = true;
  String? _error;
  String _q = '';

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
      final d = await context.read<ApiClient>().get('/parties');
      if (mounted) setState(() => _all = Party.listFrom(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final p = await showCreateCustomer(context);
    if (p != null) {
      setState(() => _all = [p, ..._all]);
      if (mounted) toast(context, '${p.name} added.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _all.where((p) => p.matches(_q)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text('Add customer', style: T.body(14.5, w: FontWeight.w800, color: Colors.white)),
      ),
      body: RefreshIndicator(
        color: Pal.ink,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 100),
          children: [
            TextField(
              onChanged: (v) => setState(() => _q = v),
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(
                hintText: 'Search by name or phone',
                prefixIcon: Icon(Icons.search_rounded, color: Pal.muted),
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              for (var i = 0; i < 5; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 40))),
            if (_error != null) ErrorBlock(_error!, onRetry: _load),
            if (!_loading && _error == null && list.isEmpty)
              EmptyBlock(
                icon: Icons.people_outline_rounded,
                title: _q.isEmpty ? 'No customers yet' : 'No match for "$_q"',
                body: _q.isEmpty ? 'Add your first customer to bill faster next time.' : 'Check the spelling or add them as a new customer.',
              ),
            for (final p in list)
              Padding(padding: const EdgeInsets.only(bottom: 10), child: CustomerTile(party: p, onTap: () => _detail(p))),
          ],
        ),
      ),
    );
  }

  void _detail(Party p) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.name, style: T.display(26)),
          const SizedBox(height: 12),
          KeyValue('Phone', p.phone.isEmpty ? 'Not added' : p.phone),
          KeyValue('PAN', p.pan.isEmpty ? 'Not added' : p.pan),
          KeyValue('GSTIN', p.gstin.isEmpty ? 'Not added' : p.gstin),
        ]),
      ),
    );
  }
}

class CustomerTile extends StatelessWidget {
  const CustomerTile({super.key, required this.party, required this.onTap});
  final Party party;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final initial = party.name.trim().isEmpty ? '?' : party.name.trim()[0].toUpperCase();
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Pal.goldWash, shape: BoxShape.circle),
          child: Text(initial, style: T.display(19, color: const Color(0xFF7A5A1E))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(party.name, style: T.body(15.5, w: FontWeight.w800)),
            if (party.phone.isNotEmpty) Text(party.phone, style: T.body(13, color: Pal.muted)),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: Pal.muted),
      ]),
    );
  }
}

/// Bottom sheet that lets the counter pick (or create) a customer.
Future<Party?> showCustomerPicker(BuildContext context) {
  return showModalBottomSheet<Party>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _Picker(),
  );
}

class _Picker extends StatefulWidget {
  const _Picker();
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  List<Party> _all = [];
  bool _loading = true;
  String? _error;
  String _q = '';

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
      final d = await context.read<ApiClient>().get('/parties');
      if (mounted) setState(() => _all = Party.listFrom(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = _all.where((p) => p.matches(_q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.82,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text('Select customer', style: T.display(24))),
            TextButton.icon(
              onPressed: () async {
                final p = await showCreateCustomer(context);
                if (p != null && context.mounted) Navigator.pop(context, p);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('New'),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'Search by name or phone', prefixIcon: Icon(Icons.search_rounded, color: Pal.muted)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? ErrorBlock(_error!, onRetry: _load)
                    : list.isEmpty
                        ? const EmptyBlock(icon: Icons.person_search_rounded, title: 'No customers found', body: 'Try another name or number, or add a new customer.')
                        : ListView.separated(
                            itemCount: list.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => CustomerTile(party: list[i], onTap: () => Navigator.pop(context, list[i])),
                          ),
          ),
        ]),
      ),
    );
  }
}

Future<Party?> showCreateCustomer(BuildContext context) {
  return showModalBottomSheet<Party>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CreateCustomer(),
  );
}

class _CreateCustomer extends StatefulWidget {
  const _CreateCustomer();
  @override
  State<_CreateCustomer> createState() => _CreateCustomerState();
}

class _CreateCustomerState extends State<_CreateCustomer> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _pan = TextEditingController();
  final _gst = TextEditingController();
  String? _err;
  bool _busy = false;

  static final _panRe = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
  static final _gstRe = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]$');

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _pan.dispose();
    _gst.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final pan = _pan.text.trim().toUpperCase();
    final gst = _gst.text.trim().toUpperCase();
    String? problem;
    if (name.isEmpty) {
      problem = 'Enter the customer\'s name.';
    } else if (phone.isNotEmpty && !RegExp(r'^\d{10}$').hasMatch(phone)) {
      problem = 'Phone number should be 10 digits.';
    } else if (pan.isNotEmpty && !_panRe.hasMatch(pan)) {
      problem = 'PAN looks wrong. It should read like ABCDE1234F.';
    } else if (gst.isNotEmpty && !_gstRe.hasMatch(gst)) {
      problem = 'GSTIN should be 15 characters, like 27ABCDE1234F1Z5.';
    }
    if (problem != null) {
      setState(() => _err = problem);
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await context.read<ApiClient>().post('/parties', body: {
        'name': name,
        if (phone.isNotEmpty) 'phone': phone,
        if (pan.isNotEmpty) 'pan': pan,
        if (gst.isNotEmpty) 'gstin': gst,
      });
      final map = asMap(d);
      if (map['name'] == null && map['displayName'] == null) map['name'] = name;
      if (map['phone'] == null && phone.isNotEmpty) map['phone'] = phone;
      if (mounted) Navigator.pop(context, Party(map));
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 0, 22, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('New customer', style: T.display(26)),
        const SizedBox(height: 18),
        const FieldLabel('Name'),
        TextField(controller: _name, textCapitalization: TextCapitalization.words),
        const SizedBox(height: 14),
        const FieldLabel('Phone'),
        TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 10, decoration: const InputDecoration(counterText: '')),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('PAN (optional)'),
              TextField(controller: _pan, textCapitalization: TextCapitalization.characters, maxLength: 10, decoration: const InputDecoration(counterText: '')),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('GSTIN (optional)'),
              TextField(controller: _gst, textCapitalization: TextCapitalization.characters, maxLength: 15, decoration: const InputDecoration(counterText: '')),
            ]),
          ),
        ]),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(_err!, style: T.body(13.5, color: Pal.danger, w: FontWeight.w700)),
          ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Text('Save customer'),
        ),
      ]),
    );
  }
}
