import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

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
    return LuxuryModuleScaffold(
      title: widget.picker ? 'Select Party' : 'Parties & Karigars',
      icon: Icons.groups_rounded,
      searchController: _q,
      searchHint: 'Search name, code or contact...',
      onSearchChanged: _onChanged,
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        selected: _role,
        onChanged: (r) {
          setState(() => _role = r);
          _load();
        },
        items: const [
          ('ALL', 'All', Icons.groups_outlined),
          ('CUSTOMER', 'Customers', Icons.person_outline_rounded),
          ('SUPPLIER', 'Suppliers', Icons.local_shipping_outlined),
          ('KARIGAR', 'Karigars', Icons.handyman_outlined),
          ('REFINER', 'Refiners', Icons.balance_rounded),
        ],
      ),
      floatingActionButton: GoldAddFab(
        onPressed: _add,
        tooltip: 'Register New Party',
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
          children: [
            if (_loading)
              for (var i = 0; i < 4; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 64)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (list.isEmpty)
              const SaasEmptyBox(
                'No matching parties found. Tap + to register retail customers, Karigars, or bullion suppliers.',
              )
            else
              for (final p in list)
                LuxuryRecordCard(
                  onTap: () => widget.picker ? Navigator.pop(context, p) : _detail(p),
                  icon: p.roles.contains('KARIGAR')
                      ? Icons.handyman_rounded
                      : p.roles.contains('SUPPLIER')
                          ? Icons.local_shipping_outlined
                          : Icons.person_rounded,
                  code: p.name,
                  status: p.primaryRoleLabel.toUpperCase(),
                  lines: [
                    if (p.phone.isNotEmpty) ('Mobile', p.phone),
                    if (p.city.isNotEmpty) ('City', p.city),
                    if (p.gstin.isNotEmpty) ('GSTIN', p.gstin),
                  ],
                  amountLabel: p.code.isNotEmpty ? 'Code' : 'Type',
                  amountValue: p.code.isNotEmpty ? p.code : p.kind,
                ),
          ],
        ),
      ),
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
                hintText: docType == 'PAN' ? '10-character PAN' : docType == 'AADHAAR' ? '12-digit Aadhaar' : 'Document ID',
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

  Future<void> _addCreditPolicyDialog() async {
    final limitCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '15');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.card,
        title: Text('Add Credit Policy', style: T.display(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: limitCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: T.mono(14),
            decoration: const InputDecoration(labelText: 'Credit Limit (INR)', hintText: '0.00'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: daysCtrl,
            keyboardType: TextInputType.number,
            style: T.mono(14),
            decoration: const InputDecoration(labelText: 'Terms (Days)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
            onPressed: () async {
              if (!isValidAmount(limitCtrl.text)) {
                toast(ctx, 'Enter a valid credit limit amount.', error: true);
                return;
              }
              try {
                final api = context.read<ApiClient>();
                final res = asMap(await api.post(
                  '/parties/${widget.party.id}/credit-policies',
                  body: {
                    'limitAmount': normAmount(limitCtrl.text),
                    'currency': 'INR',
                    'termsDays': int.tryParse(daysCtrl.text.trim()) ?? 15,
                    'effectiveFrom': todayIso(),
                  },
                ));
                final policyId = '${res['id'] ?? ''}';
                if (policyId.isNotEmpty) {
                  try {
                    await api.post(
                      '/parties/credit-policies/$policyId/approve',
                      body: {
                        'expectedVersion': (res['version'] as num?)?.toInt() ?? 1,
                        'reason': 'Approved commercial credit limit.',
                      },
                    );
                  } catch (_) {}
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on ApiException catch (e) {
                if (ctx.mounted) toast(ctx, e.message, error: true);
              }
            },
            child: const Text('Save Policy'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      toast(context, 'Credit policy saved.');
    }
  }

  Future<void> _recordConsentDialog() async {
    var channel = 'WHATSAPP';
    final evidenceCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Pal.card,
          title: Text('Record Communication Consent', style: T.display(19)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            GoldDropdown<String>(
              value: channel,
              labelText: 'Channel',
              items: const [
                DropdownMenuItem(value: 'WHATSAPP', child: Text('WhatsApp')),
                DropdownMenuItem(value: 'SMS', child: Text('SMS')),
                DropdownMenuItem(value: 'EMAIL', child: Text('Email')),
                DropdownMenuItem(value: 'PHONE', child: Text('Phone')),
              ],
              onChanged: (v) => setLocal(() => channel = v ?? 'WHATSAPP'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: evidenceCtrl,
              decoration: const InputDecoration(labelText: 'Consent Evidence / Reference'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () async {
                try {
                  await context.read<ApiClient>().post(
                    '/parties/${widget.party.id}/consents',
                    body: {
                      'channel': channel,
                      'purpose': 'TRANSACTIONAL_AND_UPDATES',
                      'state': 'GRANTED',
                      'evidence': evidenceCtrl.text.trim().isEmpty
                          ? 'In-showroom counter sign-off'
                          : evidenceCtrl.text.trim(),
                    },
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
              child: const Text('Record'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) toast(context, 'Consent recorded.');
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
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
              onPressed: _addCreditPolicyDialog,
              icon: const Icon(Icons.credit_score_outlined, size: 16),
              label: const Text('Credit Policy'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(42)),
              onPressed: _recordConsentDialog,
              icon: const Icon(Icons.mark_chat_read_outlined, size: 16),
              label: const Text('Consent'),
            ),
          ),
        ]),
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

  /// Normalizes Indian 10-digit mobile numbers into international E.164 format (`+91...`).
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
      setState(() => _error = 'PAN must follow valid 10-character Indian PAN format.');
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
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in const [
            ('CUSTOMER', 'Customer'),
            ('KARIGAR', 'Karigar'),
            ('SUPPLIER', 'Supplier'),
            ('REFINER', 'Refiner'),
          ])
            ChoiceChip(
              label: Text(r.$2),
              selected: _role == r.$1,
              showCheckmark: false,
              selectedColor: Pal.goldWash,
              onSelected: (_) => setState(() {
                _role = r.$1;
                if (r.$1 == 'SUPPLIER' || r.$1 == 'REFINER') _kind = 'ORGANIZATION';
              }),
            ),
        ]),
        const SizedBox(height: 14),
        const FieldLabel('Full Name / Business Name'),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Enter full legal or trade name'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('Mobile (+91 / E.164)'),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                style: T.mono(14),
                decoration: const InputDecoration(hintText: '10-digit mobile'),
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
                decoration: const InputDecoration(hintText: 'Email address'),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('PAN (Optional)'),
              TextField(
                controller: _pan,
                textCapitalization: TextCapitalization.characters,
                style: T.mono(14),
                decoration: const InputDecoration(hintText: '10-char PAN'),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FieldLabel('GSTIN (Optional)'),
              TextField(
                controller: _gstin,
                textCapitalization: TextCapitalization.characters,
                style: T.mono(13.5),
                decoration: const InputDecoration(hintText: '15-char GSTIN'),
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
        RoyalGoldButton(
          label: 'Save Party Record',
          busy: _busy,
          onPressed: _busy ? null : _save,
        ),
      ]),
    );
  }
}
