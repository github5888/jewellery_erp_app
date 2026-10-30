import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Parties & CRM Directory matching `PartiesPanel.tsx` on `pos.hrpocket.in`.
/// Supports Customers, Karigars, Suppliers, and Refiners with GSTIN & KYC (PAN/Aadhaar).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key, this.picker = false, this.initialRole});
  final bool picker;
  final String? initialRole;
  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  late String _role = widget.initialRole ?? (widget.picker ? 'CUSTOMER' : 'ALL');
  List<Party> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = _q.text.trim();
      final d = await context.read<ApiClient>().get('/parties', query: {
        if (_role != 'ALL') 'role': _role,
        if (q.isNotEmpty) 'q': q,
      });
      if (mounted) {
        setState(() => _items = asList(d, keys: const ['parties', 'items', 'rows']).map(Party.fromJson).toList());
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _onChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), _load);
  }

  List<Party> get _filtered {
    final s = _q.text.trim().toLowerCase();
    if (s.isEmpty) return _items;
    return _items.where((p) {
      return p.name.toLowerCase().contains(s) ||
          p.code.toLowerCase().contains(s) ||
          p.phone.toLowerCase().contains(s) ||
          p.email.toLowerCase().contains(s) ||
          p.gstin.toLowerCase().contains(s);
    }).toList();
  }

  Future<void> _add() async {
    final p = await showModalBottomSheet<Party>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NewPartySheet(defaultRole: _role == 'ALL' ? 'CUSTOMER' : _role),
    );
    if (p == null || !mounted) return;
    if (widget.picker) {
      Navigator.pop(context, p);
    } else {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.picker ? 'Select Party' : 'Parties & CRM'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text('New Party', style: T.body(13.5, color: Colors.white, w: FontWeight.w700)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          child: TextField(
            controller: _q,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search name, mobile, code or GSTIN…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _q.clear();
                        _load();
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: PillTabs<String>(
            selected: _role,
            onChanged: (r) {
              setState(() => _role = r);
              _load();
            },
            items: const [
              ('ALL', 'All Parties', Icons.groups_outlined),
              ('CUSTOMER', 'Customers', Icons.person_outline_rounded),
              ('KARIGAR', 'Karigars', Icons.handyman_outlined),
              ('SUPPLIER', 'Suppliers', Icons.local_shipping_outlined),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: Pal.teal,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
              children: [
                if (_loading)
                  for (var i = 0; i < 4; i++)
                    const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 64)))
                else if (_error != null)
                  ErrorBlock(_error!, onRetry: _load)
                else if (list.isEmpty)
                  Panel(
                    child: EmptyBlock(
                      icon: Icons.people_outline_rounded,
                      title: 'No matching parties',
                      body: 'Register retail customers, VIP patrons, Karigar artisans, or bullion suppliers with KYC.',
                      actionLabel: 'Register Party',
                      onAction: _add,
                    ),
                  )
                else
                  for (final p in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Panel(
                        onTap: () => widget.picker ? Navigator.pop(context, p) : _detail(p),
                        child: Row(children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: p.roles.contains('KARIGAR')
                                  ? Pal.tealWash
                                  : p.roles.contains('SUPPLIER')
                                      ? Pal.surfaceAlt
                                      : Pal.goldWash,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: p.roles.contains('KARIGAR')
                                    ? Pal.teal.withValues(alpha: 0.35)
                                    : Pal.gold.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                              style: T.display(
                                18,
                                color: p.roles.contains('KARIGAR') ? Pal.teal : Pal.goldDeep,
                              ),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Flexible(
                                  child: Text(
                                    p.name,
                                    style: T.body(15, w: FontWeight.w800),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (p.code.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  MonoTag(p.code),
                                ],
                              ]),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  if (p.phone.isNotEmpty) p.phone,
                                  if (p.city.isNotEmpty) p.city,
                                  if (p.gstin.isNotEmpty) 'GSTIN',
                                ].isEmpty
                                    ? p.kind
                                    : [
                                        if (p.phone.isNotEmpty) p.phone,
                                        if (p.city.isNotEmpty) p.city,
                                        if (p.gstin.isNotEmpty) 'GST Registered',
                                      ].join(' · '),
                                style: T.body(12.2, color: Pal.muted),
                              ),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Chip2(p.primaryRoleLabel, gold: p.roles.contains('CUSTOMER')),
                        ]),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  void _detail(Party p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PartyDetailSheet(party: p),
    );
  }
}

class _PartyDetailSheet extends StatefulWidget {
  const _PartyDetailSheet({required this.party});
  final Party party;
  @override
  State<_PartyDetailSheet> createState() => _PartyDetailSheetState();
}

class _PartyDetailSheetState extends State<_PartyDetailSheet> {
  List<Map<String, dynamic>> _kyc = [];
  bool _loadingKyc = true;
  String? _kycHint;

  @override
  void initState() {
    super.initState();
    _fetchKyc();
  }

  Future<void> _fetchKyc() async {
    setState(() {
      _loadingKyc = true;
      _kycHint = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/parties/${widget.party.id}/kyc');
      if (mounted) setState(() => _kyc = asList(d));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _kycHint = e.code == 'MFA_REQUIRED'
            ? 'Enroll 2FA in Operations > Security to view encrypted KYC.'
            : e.message);
      }
    }
    if (mounted) setState(() => _loadingKyc = false);
  }

  Future<void> _addKycDialog() async {
    final panCtrl = TextEditingController();
    String docType = 'PAN';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Pal.card,
          title: Text('Add KYC Document', style: T.display(20)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final t in const ['PAN', 'AADHAAR', 'PASSPORT'])
                ChoiceChip(
                  label: Text(t),
                  selected: docType == t,
                  showCheckmark: false,
                  selectedColor: Pal.goldWash,
                  onSelected: (_) => setLocal(() => docType = t),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: panCtrl,
              textCapitalization: TextCapitalization.characters,
              style: T.mono(15),
              decoration: InputDecoration(
                hintText: docType == 'PAN' ? 'ABCDE1234F' : docType == 'AADHAAR' ? '12-digit Aadhaar' : 'Identifier',
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () async {
                try {
                  await context.read<ApiClient>().post(
                    '/parties/${widget.party.id}/kyc',
                    body: {'documentType': docType, 'identifier': panCtrl.text.trim().toUpperCase()},
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
              child: const Text('Save KYC'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _fetchKyc();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.party;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: Text(p.name, style: T.display(23))),
          StatusPill(p.kind, tone: Tone.gold),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (p.code.isNotEmpty) MonoTag(p.code),
          for (final r in p.roles) Chip2(r, gold: r == 'CUSTOMER'),
        ]),
        const SizedBox(height: 14),
        Panel(
          color: Pal.surfaceAlt,
          child: Column(children: [
            if (p.phone.isNotEmpty) KeyValue('Primary Mobile', p.phone, mono: true),
            if (p.email.isNotEmpty) KeyValue('Email', p.email),
            if (p.city.isNotEmpty) KeyValue('City / Location', p.city),
            if (p.gstin.isNotEmpty) KeyValue('GSTIN', p.gstin, mono: true),
            if (p.pan.isNotEmpty) KeyValue('PAN (on file)', p.pan, mono: true),
            if (p.creditLimit.isNotEmpty) KeyValue('Approved Credit Limit', inr(p.creditLimit), strong: true),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Text('KYC COMPLIANCE VAULT', style: T.caps(10.5)),
          const Spacer(),
          TextButton.icon(
            onPressed: _addKycDialog,
            icon: const Icon(Icons.add_moderator_outlined, size: 16),
            label: const Text('Add PAN / ID'),
          ),
        ]),
        if (_loadingKyc)
          const Skeleton(height: 44)
        else if (_kycHint != null)
          Text(_kycHint!, style: T.body(12.2, color: Pal.muted))
        else if (_kyc.isEmpty)
          Text(
            'No KYC document vaulted yet. PAN is mandatory for high-value bullion bills above ₹2,00,000.',
            style: T.body(12.2, color: Pal.muted),
          )
        else
          for (final k in _kyc)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Panel(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(children: [
                  Chip2('${k['documentType'] ?? 'KYC'}', gold: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('${k['maskedIdentifier'] ?? '****'}', style: T.mono(13.5, w: FontWeight.w700)),
                  ),
                  StatusPill('${k['verificationState'] ?? 'RECORDED'}'),
                ]),
              ),
            ),
      ]),
    );
  }
}

Future<Party?> showCustomerPicker(BuildContext context, {String? role}) => Navigator.push<Party>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CustomersScreen(picker: true, initialRole: role ?? 'CUSTOMER'),
      ),
    );

/// Contract-aligned Party creation sheet (`createPartySchema` + optional `addPartyKycSchema`).
/// Automatically normalizes 10-digit Indian mobile numbers to `+91XXXXXXXXXX` E.164 format.
class NewPartySheet extends StatefulWidget {
  const NewPartySheet({super.key, this.defaultRole = 'CUSTOMER'});
  final String defaultRole;
  @override
  State<NewPartySheet> createState() => _NewPartySheetState();
}

class _NewPartySheetState extends State<NewPartySheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _pan = TextEditingController();
  final _gstin = TextEditingController();
  late String _role = widget.defaultRole;
  String _kind = 'INDIVIDUAL';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _pan.dispose();
    _gstin.dispose();
    super.dispose();
  }

  /// Normalizes Indian 10-digit numbers (`9876543210` / `09876543210`) into E.164 `+919876543210`.
  String? _normalizeE164(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s()-]'), '');
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('+') && RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)) {
      return cleaned;
    }
    final digits = cleaned.replaceAll(RegExp(r'^0+'), '');
    if (RegExp(r'^[6-9]\d{9}$').hasMatch(digits)) {
      return '+91$digits';
    }
    if (RegExp(r'^91[6-9]\d{9}$').hasMatch(digits)) {
      return '+$digits';
    }
    return null;
  }

  String _autoPartyCode(String role, String name) {
    final prefix = switch (role) {
      'KARIGAR' => 'KRG',
      'SUPPLIER' => 'SUP',
      'REFINER' => 'REF',
      _ => 'CUST',
    };
    final slug = name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final head = slug.isEmpty ? 'X' : slug.substring(0, slug.length > 4 ? 4 : slug.length);
    final tail = (DateTime.now().millisecondsSinceEpoch % 100000).toString().padLeft(5, '0');
    return '$prefix-$head-$tail';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter full legal or display name (min 2 characters).');
      return;
    }
    final rawPhone = _phone.text.trim();
    final e164 = _normalizeE164(rawPhone);
    if (rawPhone.isNotEmpty && e164 == null) {
      setState(() => _error = 'Enter a valid 10-digit mobile number or +E.164 phone.');
      return;
    }
    final gst = _gstin.text.trim().toUpperCase();
    if (gst.isNotEmpty && !RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gst)) {
      setState(() => _error = 'GSTIN must be a valid 15-character Indian GST number.');
      return;
    }
    final pan = _pan.text.trim().toUpperCase();
    if (pan.isNotEmpty && !RegExp(r'^[A-Z]{5}\d{4}[A-Z]$').hasMatch(pan)) {
      setState(() => _error = 'PAN must follow 10-character format (e.g. ABCDE1234F).');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final contacts = <Map<String, dynamic>>[
        if (e164 != null)
          {'kind': 'PHONE', 'label': 'Primary Mobile', 'value': e164, 'isPrimary': true},
        if (_email.text.trim().isNotEmpty)
          {'kind': 'EMAIL', 'label': 'Email', 'value': _email.text.trim().toLowerCase(), 'isPrimary': e164 == null},
      ];
      final taxRegs = <Map<String, dynamic>>[
        if (gst.isNotEmpty)
          {
            'registrationType': 'GSTIN',
            'registrationNumber': gst,
            'legalName': name,
            'stateCode': gst.substring(0, 2),
            'effectiveFrom': todayIso(),
          },
      ];

      final d = await api.post('/parties', body: {
        'code': _autoPartyCode(_role, name),
        'kind': gst.isNotEmpty ? 'ORGANIZATION' : _kind,
        'displayName': name,
        'legalName': name,
        'roles': [_role],
        'contacts': contacts,
        'addresses': const <Map<String, dynamic>>[],
        'taxRegistrations': taxRegs,
      });

      final created = Party.fromJson(asMap(d));
      if (pan.isNotEmpty && created.id.isNotEmpty) {
        try {
          await api.post('/parties/${created.id}/kyc', body: {
            'documentType': 'PAN',
            'identifier': pan,
          });
        } catch (_) {
          // Non-fatal if session lacks KYC MFA privilege; party record itself succeeded.
        }
      }

      if (mounted) {
        toast(context, '${created.name} registered.');
        Navigator.pop(context, created);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _error = e.code == 'MFA_REQUIRED'
            ? 'Two-factor authentication is required by tenant policy to create master parties. Enroll 2FA in Operations > Security.'
            : e.message);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Register Enterprise Party', style: T.display(22)),
        const SizedBox(height: 14),
        const FieldLabel('Party Role'),
        Wrap(spacing: 8, children: [
          for (final r in const [
            ('CUSTOMER', 'Customer'),
            ('KARIGAR', 'Karigar'),
            ('SUPPLIER', 'Supplier'),
          ])
            ChoiceChip(
              label: Text(r.$2),
              selected: _role == r.$1,
              showCheckmark: false,
              selectedColor: Pal.goldWash,
              onSelected: (_) => setState(() {
                _role = r.$1;
                if (r.$1 == 'SUPPLIER') _kind = 'ORGANIZATION';
              }),
            ),
        ]),
        const SizedBox(height: 14),
        const FieldLabel('Full Name / Business Name'),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Ananya Verma / Malabar Bullion House'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Mobile (India +91 / E.164)'),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: T.mono(14),
                decoration: const InputDecoration(hintText: '9876543210'),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Email (Optional)'),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(hintText: 'patron@mail.com'),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('PAN (For Bills > ₹2L)'),
              TextField(
                controller: _pan,
                textCapitalization: TextCapitalization.characters,
                style: T.mono(14),
                decoration: const InputDecoration(hintText: 'ABCDE1234F'),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('GSTIN (B2B Optional)'),
              TextField(
                controller: _gstin,
                textCapitalization: TextCapitalization.characters,
                style: T.mono(13.5),
                decoration: const InputDecoration(hintText: '27AAACB1234F1Z5'),
              ),
            ]),
          ),
        ]),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: T.body(13, color: Pal.danger, w: FontWeight.w700)),
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: Pal.teal),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Text('Save Party Record'),
        ),
      ]),
    );
  }
}
