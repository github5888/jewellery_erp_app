import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

/// Parties & Karigars (`PartiesPanel.tsx` — `image-22.png`).
/// Entity-scoped customers, suppliers, karigars and refiners with protected KYC and credit controls.
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
  late bool _showCreateForm = !widget.picker;
  List<Party> _items = [];
  bool _loading = true;
  bool _creating = false;
  String? _error;

  // Exact inline Create Party fields from `image-22.png`
  final _partyCode = TextEditingController();
  String _partyKind = 'ORGANIZATION';
  final _displayName = TextEditingController();
  final _legalName = TextEditingController();
  late String _createRole = widget.initialRole ?? 'SUPPLIER';
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _gstin = TextEditingController();
  final _gstStateCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [
      _q,
      _partyCode,
      _displayName,
      _legalName,
      _email,
      _phone,
      _gstin,
      _gstStateCode,
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
    try {
      final q = _q.text.trim();
      final d = await context.read<ApiClient>().get(
        '/parties',
        query: {
          if (_role != 'ALL') 'role': _role,
          if (q.isNotEmpty) 'q': q,
        },
      );
      if (mounted) {
        setState(
          () => _items = asList(
            d,
            keys: const ['parties', 'items', 'rows'],
          ).map(Party.fromJson).toList(),
        );
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
          p.legalName.toLowerCase().contains(s) ||
          p.code.toLowerCase().contains(s) ||
          p.phone.toLowerCase().contains(s) ||
          p.email.toLowerCase().contains(s) ||
          p.gstin.toLowerCase().contains(s);
    }).toList();
  }

  String? _normalizeE164(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s()-]'), '');
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('+') &&
        RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)) {
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

  String _generatePartyCode(String role, String name) {
    final prefix = switch (role) {
      'KARIGAR' => 'KRG',
      'SUPPLIER' => 'SUP',
      'REFINER' => 'REF',
      _ => 'CUST',
    };
    final slug = name.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final head = slug.isEmpty
        ? 'PT'
        : slug.substring(0, slug.length > 4 ? 4 : slug.length);
    final tail = (DateTime.now().millisecondsSinceEpoch % 100000)
        .toString()
        .padLeft(5, '0');
    return '$prefix-$head-$tail';
  }

  Future<void> _submitInlineParty() async {
    final disp = _displayName.text.trim();
    final legal = _legalName.text.trim().isEmpty ? disp : _legalName.text.trim();
    if (disp.length < 2) {
      setState(
        () => _error = 'Enter display name (minimum 2 characters).',
      );
      return;
    }

    final code = _partyCode.text.trim().isEmpty
        ? _generatePartyCode(_createRole, disp)
        : _partyCode.text.trim().toUpperCase();

    final rawPhone = _phone.text.trim();
    final e164 = _normalizeE164(rawPhone);
    if (rawPhone.isNotEmpty && e164 == null) {
      setState(
        () => _error = 'Enter a valid 10-digit mobile number or +E.164 phone.',
      );
      return;
    }

    final email = _email.text.trim().toLowerCase();
    if (email.isNotEmpty && !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    final gst = _gstin.text.trim().toUpperCase();
    if (gst.isNotEmpty &&
        !RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gst)) {
      setState(
        () => _error = 'GSTIN must be a valid 15-character Indian GST number.',
      );
      return;
    }

    final stateCode = _gstStateCode.text.trim().isNotEmpty
        ? _gstStateCode.text.trim()
        : (gst.length >= 2 ? gst.substring(0, 2) : '');
    if (gst.isNotEmpty && !RegExp(r'^\d{2}$').hasMatch(stateCode)) {
      setState(
        () => _error = 'GST state code must be a 2-digit Indian state code.',
      );
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final api = context.read<ApiClient>();
      final contacts = <Map<String, dynamic>>[
        if (e164 != null)
          {
            'kind': 'PHONE',
            'label': 'Primary Mobile',
            'value': e164,
            'isPrimary': true,
          },
        if (email.isNotEmpty)
          {
            'kind': 'EMAIL',
            'label': 'Email',
            'value': email,
            'isPrimary': e164 == null,
          },
      ];
      final taxRegs = <Map<String, dynamic>>[
        if (gst.isNotEmpty)
          {
            'registrationType': 'GSTIN',
            'registrationNumber': gst,
            'legalName': legal,
            'stateCode': stateCode,
            'effectiveFrom': todayIso(),
          },
      ];

      final res = await api.post(
        '/parties',
        idempotent: true,
        body: {
          'code': code,
          'kind': _partyKind,
          'displayName': disp,
          'legalName': legal,
          'roles': [_createRole],
          'contacts': contacts,
          'addresses': const <Map<String, dynamic>>[],
          'taxRegistrations': taxRegs,
        },
      );
      if (!mounted) return;
      final created = Party.fromJson(asMap(res));
      _partyCode.clear();
      _displayName.clear();
      _legalName.clear();
      _email.clear();
      _phone.clear();
      _gstin.clear();
      _gstStateCode.clear();
      toast(context, '${created.name} created.');
      if (widget.picker) {
        Navigator.pop(context, created);
      } else {
        _load();
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'MFA_REQUIRED'
              ? 'Two-factor authentication is required by tenant policy to create master parties.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _openQuickPickerSheet() async {
    final p = await showModalBottomSheet<Party>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => NewPartySheet(
        defaultRole: _role == 'ALL' ? 'CUSTOMER' : _role,
      ),
    );
    if (p == null || !mounted) return;
    if (widget.picker) {
      Navigator.pop(context, p);
    } else {
      _load();
    }
  }

  void _detail(Party p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _PartyDetailSheet(
        party: p,
        onUpdated: _load,
      ),
    );
  }

  String _taxSummary(Party p) {
    final parts = <String>[];
    if (p.email.isNotEmpty) parts.add(p.email);
    if (p.phone.isNotEmpty) parts.add(p.phone);
    if (p.gstin.isNotEmpty) {
      final regs = asList(p.raw['taxRegistrations']);
      final st = regs.isNotEmpty ? '${regs.first['stateCode'] ?? ''}'.trim() : '';
      parts.add(st.isNotEmpty ? 'GSTIN ${p.gstin} ($st)' : 'GSTIN ${p.gstin}');
    }
    return parts.isEmpty ? 'No contact / tax on file' : parts.join(' · ');
  }

  String _kycSummary(Party p) {
    final docs = asList(
      p.raw,
      keys: const ['kycDocuments', 'kyc', 'protectedKyc'],
    );
    if (docs.isEmpty) {
      return p.pan.isNotEmpty ? 'PAN ${p.pan}' : 'Protected · Tap to view / add';
    }
    return docs
        .map(
          (k) =>
              '${k['documentType'] ?? 'KYC'}: ${k['maskedIdentifier'] ?? 'Protected'}',
        )
        .join(' · ');
  }

  String _creditSummary(Party p) {
    final policies = asList(p.raw['creditPolicies']);
    if (policies.isEmpty) return 'No credit policy';
    final first = policies.first;
    final lim = inr(first['limitAmount']);
    final days = '${first['termsDays'] ?? ''}'.trim();
    final st = '${first['state'] ?? first['status'] ?? 'ACTIVE'}'.toUpperCase();
    return [
      lim,
      if (days.isNotEmpty) '${days}d',
      st,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final list = _filtered;

    return LuxuryModuleScaffold(
      title: widget.picker ? 'Select Party' : 'Parties & Karigars',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
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
      floatingActionButton: widget.picker
          ? GoldAddFab(
              onPressed: _openQuickPickerSheet,
              tooltip: 'Register New Party',
            )
          : null,
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            if (!widget.picker) ...[
              // Hero header card (`Parties and commercial policy` — image-22.png)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Pal.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Pal.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Pal.goldTint,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Pal.borderGold),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.toll_rounded,
                            size: 13,
                            color: Pal.goldDeep,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              gold999 != null
                                  ? 'Bullion 24K: Fine 999 Board Active · ${inr(gold999.sell)}/g'
                                  : 'Bullion 24K: Fine 999 Board Active',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.body(
                                11.5,
                                weight: FontWeight.w700,
                                color: Pal.goldDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(
                            Icons.contact_page_outlined,
                            size: 20,
                            color: Pal.gold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Parties and commercial policy',
                                style: T.body(
                                  16,
                                  weight: FontWeight.w700,
                                  color: Pal.ink,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Entity-scoped customers, suppliers, karigars and refiners with protected KYC and credit controls.',
                                style: T.body(12.2, color: Pal.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        GoldButton(
                          label: _showCreateForm ? 'Close' : '+ Party',
                          compact: true,
                          onPressed: () => setState(
                            () => _showCreateForm = !_showCreateForm,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (_showCreateForm) ...[
                const SizedBox(height: 12),
                // Exact inline Create Party card from image-22.png formatted for phone
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _partyCode,
                              textCapitalization: TextCapitalization.characters,
                              style: T.mono(13.5),
                              decoration: InputDecoration(
                                hintText: 'Party code',
                                suffixIcon: IconButton(
                                  tooltip: 'Auto-generate party code',
                                  icon: const Icon(
                                    Icons.auto_awesome_outlined,
                                    size: 17,
                                    color: Pal.goldDeep,
                                  ),
                                  onPressed: () => setState(() {
                                    _partyCode.text = _generatePartyCode(
                                      _createRole,
                                      _displayName.text,
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: GoldDropdown<String>(
                              value: _partyKind,
                              items: const [
                                DropdownMenuItem(
                                  value: 'ORGANIZATION',
                                  child: Text('Organization'),
                                ),
                                DropdownMenuItem(
                                  value: 'INDIVIDUAL',
                                  child: Text('Individual'),
                                ),
                              ],
                              onChanged: (v) => setState(
                                () => _partyKind = v ?? 'ORGANIZATION',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _displayName,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                hintText: 'Display name',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _legalName,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                hintText: 'Legal name',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: GoldDropdown<String>(
                              value: _createRole,
                              items: const [
                                DropdownMenuItem(
                                  value: 'SUPPLIER',
                                  child: Text('SUPPLIER'),
                                ),
                                DropdownMenuItem(
                                  value: 'CUSTOMER',
                                  child: Text('CUSTOMER'),
                                ),
                                DropdownMenuItem(
                                  value: 'KARIGAR',
                                  child: Text('KARIGAR'),
                                ),
                                DropdownMenuItem(
                                  value: 'REFINER',
                                  child: Text('REFINER'),
                                ),
                              ],
                              onChanged: (v) => setState(
                                () => _createRole = v ?? 'SUPPLIER',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                hintText: 'Email',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        style: T.mono(13.5),
                        decoration: const InputDecoration(
                          hintText: 'Mobile (+91 / 10-digit optional)',
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _gstin,
                              textCapitalization: TextCapitalization.characters,
                              style: T.mono(13),
                              decoration: const InputDecoration(
                                hintText: 'GSTIN (optional)',
                              ),
                              onChanged: (v) {
                                final clean = v.trim();
                                if (clean.length >= 2 &&
                                    RegExp(r'^\d{2}').hasMatch(clean) &&
                                    _gstStateCode.text.trim().isEmpty) {
                                  _gstStateCode.text = clean.substring(0, 2);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _gstStateCode,
                              keyboardType: TextInputType.number,
                              style: T.mono(13),
                              decoration: const InputDecoration(
                                hintText: 'GST state code',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      RoyalGoldButton(
                        label: 'Create party',
                        busy: _creating,
                        onPressed: _creating ? null : _submitInlineParty,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 14),
            ],

            if (_loading)
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Panel(child: Skeleton(height: 68)),
                )
            else if (list.isEmpty)
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: const BoxDecoration(
                        color: Pal.bgTint,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(15),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            Text(
                              'Party',
                              style: T.body(
                                11.5,
                                weight: FontWeight.w700,
                                color: Pal.inkSoft,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Text(
                              'Contact / tax',
                              style: T.body(
                                11.5,
                                weight: FontWeight.w700,
                                color: Pal.inkSoft,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Text(
                              'Protected KYC',
                              style: T.body(
                                11.5,
                                weight: FontWeight.w700,
                                color: Pal.inkSoft,
                              ),
                            ),
                            const SizedBox(width: 24),
                            Text(
                              'Credit policy',
                              style: T.body(
                                11.5,
                                weight: FontWeight.w700,
                                color: Pal.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Pal.divider),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 26,
                      ),
                      child: Center(
                        child: Text(
                          'No parties recorded yet.',
                          style: T.body(13, color: Pal.muted),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final p in list)
                LuxuryRecordCard(
                  onTap: () =>
                      widget.picker ? Navigator.pop(context, p) : _detail(p),
                  icon: p.roles.contains('KARIGAR')
                      ? Icons.handyman_rounded
                      : p.roles.contains('SUPPLIER')
                          ? Icons.local_shipping_outlined
                          : p.roles.contains('REFINER')
                              ? Icons.factory_outlined
                              : Icons.person_rounded,
                  code: p.name,
                  status: p.roles.join(' · '),
                  lines: [
                    if (p.legalName.isNotEmpty && p.legalName != p.name)
                      ('Legal Name', p.legalName),
                    ('Contact / Tax', _taxSummary(p)),
                    ('Protected KYC', _kycSummary(p)),
                    ('Credit Policy', _creditSummary(p)),
                  ],
                  amountLabel: p.code.isNotEmpty ? 'Code' : 'Kind',
                  amountValue: p.code.isNotEmpty ? p.code : p.kind,
                  actions: widget.picker
                      ? const []
                      : [
                          GoldButton(
                            label: 'KYC & Credit Policy',
                            compact: true,
                            onPressed: () => _detail(p),
                          ),
                        ],
                ),
          ],
        ),
      ),
    );
  }
}

class _PartyDetailSheet extends StatefulWidget {
  const _PartyDetailSheet({
    required this.party,
    required this.onUpdated,
  });
  final Party party;
  final VoidCallback onUpdated;
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
      final d = await context.read<ApiClient>().get(
            '/parties/${widget.party.id}/kyc',
          );
      if (mounted) {
        setState(
          () => _kyc = asList(d, keys: const ['kycDocuments', 'items', 'kyc']),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _kycHint = e.code == 'MFA_REQUIRED'
              ? 'Enroll 2FA in Operations > Security to view encrypted KYC.'
              : e.message,
        );
      }
    }
    if (mounted) setState(() => _loadingKyc = false);
  }

  Future<void> _addKycDialog() async {
    final idCtrl = TextEditingController();
    var docType = 'PAN';
    var saving = false;
    String? modalErr;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Pal.card,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Add Protected KYC',
                        style: T.body(17, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in const ['PAN', 'AADHAAR', 'PASSPORT'])
                      ChoiceChip(
                        label: Text(t),
                        selected: docType == t,
                        showCheckmark: false,
                        selectedColor: Pal.goldWash,
                        onSelected: (_) => setLocal(() => docType = t),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: idCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: T.mono(14.5),
                  decoration: InputDecoration(
                    hintText: docType == 'PAN'
                        ? '10-character PAN'
                        : docType == 'AADHAAR'
                            ? '12-digit Aadhaar'
                            : 'Passport / Document ID',
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: 'Save KYC',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            final ident = idCtrl.text.trim().toUpperCase();
                            if (ident.isEmpty) {
                              setLocal(
                                () => modalErr = 'Enter document identifier.',
                              );
                              return;
                            }
                            setLocal(() {
                              saving = true;
                              modalErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/parties/${widget.party.id}/kyc',
                                idempotent: true,
                                body: {
                                  'documentType': docType,
                                  'identifier': ident,
                                },
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } on ApiException catch (e) {
                              setLocal(() => modalErr = e.message);
                            } finally {
                              if (ctx.mounted) setLocal(() => saving = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    idCtrl.dispose();
    if (ok == true) {
      _fetchKyc();
      widget.onUpdated();
    }
  }

  Future<void> _addCreditPolicyDialog() async {
    final limitCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '15');
    final reasonCtrl = TextEditingController();
    var saving = false;
    String? modalErr;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Pal.card,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Commercial Credit Policy',
                        style: T.body(17, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 12),
                SaasField(
                  label: 'Credit Limit (INR)',
                  controller: limitCtrl,
                  hint: '0.00',
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Credit Terms (Days)',
                  controller: daysCtrl,
                  mono: true,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Approval reason (optional, min 10 chars to approve immediately)',
                  controller: reasonCtrl,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: 'Save Credit Policy',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (!isValidAmount(limitCtrl.text)) {
                              setLocal(
                                () => modalErr = 'Enter a valid credit limit amount.',
                              );
                              return;
                            }
                            final approvalReason = reasonCtrl.text.trim();
                            if (approvalReason.isNotEmpty &&
                                approvalReason.length < 10) {
                              setLocal(
                                () => modalErr =
                                    'Approval reason must be at least 10 characters.',
                              );
                              return;
                            }
                            setLocal(() {
                              saving = true;
                              modalErr = null;
                            });
                            try {
                              final api = context.read<ApiClient>();
                              final res = asMap(
                                await api.post(
                                  '/parties/${widget.party.id}/credit-policies',
                                  idempotent: true,
                                  body: {
                                    'limitAmount': normAmount(limitCtrl.text),
                                    'currency': 'INR',
                                    'termsDays':
                                        int.tryParse(daysCtrl.text.trim()) ?? 15,
                                    'effectiveFrom': todayIso(),
                                  },
                                ),
                              );
                              final policyId = '${res['id'] ?? ''}';
                              if (policyId.isNotEmpty &&
                                  approvalReason.length >= 10) {
                                await api.post(
                                  '/parties/credit-policies/$policyId/approve',
                                  idempotent: true,
                                  body: {
                                    'expectedVersion':
                                        (res['version'] as num?)?.toInt() ?? 1,
                                    'reason': approvalReason,
                                  },
                                );
                              }
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } on ApiException catch (e) {
                              setLocal(() => modalErr = e.message);
                            } finally {
                              if (ctx.mounted) setLocal(() => saving = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    limitCtrl.dispose();
    daysCtrl.dispose();
    reasonCtrl.dispose();
    if (ok == true && mounted) {
      toast(context, 'Credit policy recorded.');
      widget.onUpdated();
    }
  }

  Future<void> _recordConsentDialog() async {
    var channel = 'WHATSAPP';
    final evidenceCtrl = TextEditingController();
    var saving = false;
    String? modalErr;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Dialog(
          backgroundColor: Pal.card,
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Communication Consent',
                        style: T.body(17, weight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                if (modalErr != null) ...[
                  const SizedBox(height: 8),
                  ErrorBanner(modalErr!),
                ],
                const SizedBox(height: 12),
                const FieldLabel('Channel'),
                GoldDropdown<String>(
                  value: channel,
                  items: const [
                    DropdownMenuItem(value: 'WHATSAPP', child: Text('WhatsApp')),
                    DropdownMenuItem(value: 'SMS', child: Text('SMS')),
                    DropdownMenuItem(value: 'EMAIL', child: Text('Email')),
                    DropdownMenuItem(value: 'PHONE', child: Text('Phone')),
                  ],
                  onChanged: (v) => setLocal(() => channel = v ?? 'WHATSAPP'),
                ),
                const SizedBox(height: 12),
                SaasField(
                  label: 'Consent Evidence / Reference',
                  controller: evidenceCtrl,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: GoldButton(
                    label: 'Record Consent',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            final ev = evidenceCtrl.text.trim();
                            if (ev.length < 3) {
                              setLocal(
                                () => modalErr =
                                    'Enter consent evidence / reference (min 3 chars).',
                              );
                              return;
                            }
                            setLocal(() {
                              saving = true;
                              modalErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/parties/${widget.party.id}/consents',
                                idempotent: true,
                                body: {
                                  'channel': channel,
                                  'purpose': 'TRANSACTIONAL_AND_UPDATES',
                                  'state': 'GRANTED',
                                  'evidence': ev,
                                },
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } on ApiException catch (e) {
                              setLocal(() => modalErr = e.message);
                            } finally {
                              if (ctx.mounted) setLocal(() => saving = false);
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    evidenceCtrl.dispose();
    if (ok == true && mounted) {
      toast(context, 'Consent recorded.');
      widget.onUpdated();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.party;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        28 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(p.name, style: T.display(22))),
              StatusPill(p.kind, tone: Tone.gold),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (p.code.isNotEmpty) MonoTag(p.code),
              for (final r in p.roles) Chip2(r, gold: r == 'CUSTOMER'),
            ],
          ),
          const SizedBox(height: 14),
          Panel(
            color: Pal.surfaceAlt,
            child: Column(
              children: [
                if (p.legalName.isNotEmpty) KeyValue('Legal Name', p.legalName),
                if (p.phone.isNotEmpty)
                  KeyValue('Primary Mobile', p.phone, mono: true),
                if (p.email.isNotEmpty) KeyValue('Email', p.email),
                if (p.city.isNotEmpty) KeyValue('City / Location', p.city),
                if (p.gstin.isNotEmpty) KeyValue('GSTIN', p.gstin, mono: true),
                if (p.creditLimit.isNotEmpty)
                  KeyValue(
                    'Credit Limit',
                    inr(p.creditLimit),
                    strong: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                  onPressed: _addCreditPolicyDialog,
                  icon: const Icon(Icons.credit_score_outlined, size: 16),
                  label: const Text('Credit Policy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(42),
                  ),
                  onPressed: _recordConsentDialog,
                  icon: const Icon(Icons.mark_chat_read_outlined, size: 16),
                  label: const Text('Consent'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('PROTECTED KYC VAULT', style: T.caps(10.5)),
              const Spacer(),
              TextButton.icon(
                onPressed: _addKycDialog,
                icon: const Icon(Icons.add_moderator_outlined, size: 16),
                label: const Text('Add PAN / ID'),
              ),
            ],
          ),
          if (_loadingKyc)
            const Skeleton(height: 44)
          else if (_kycHint != null)
            Text(_kycHint!, style: T.body(12.2, color: Pal.muted))
          else if (_kyc.isEmpty)
            Text(
              'No KYC document vaulted yet.',
              style: T.body(12.2, color: Pal.muted),
            )
          else
            for (final k in _kyc)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Panel(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Chip2('${k['documentType'] ?? 'KYC'}', gold: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${k['maskedIdentifier'] ?? 'Protected'}',
                          style: T.mono(13.5, w: FontWeight.w700),
                        ),
                      ),
                      StatusPill('${k['verificationState'] ?? 'RECORDED'}'),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

Future<Party?> showCustomerPicker(BuildContext context, {String? role}) =>
    Navigator.push<Party>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CustomersScreen(
          picker: true,
          initialRole: role ?? 'CUSTOMER',
        ),
      ),
    );

/// Quick Party creation sheet for modal pickers (`POS Billing`, `Old Gold`).
class NewPartySheet extends StatefulWidget {
  const NewPartySheet({super.key, this.defaultRole = 'CUSTOMER'});
  final String defaultRole;
  @override
  State<NewPartySheet> createState() => _NewPartySheetState();
}

class _NewPartySheetState extends State<NewPartySheet> {
  final _code = TextEditingController();
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
    for (final c in [_code, _name, _phone, _email, _pan, _gstin]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _normalizeE164(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[\s()-]'), '');
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('+') &&
        RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(cleaned)) {
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
    final head = slug.isEmpty
        ? 'PT'
        : slug.substring(0, slug.length > 4 ? 4 : slug.length);
    final tail = (DateTime.now().millisecondsSinceEpoch % 100000)
        .toString()
        .padLeft(5, '0');
    return '$prefix-$head-$tail';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(
        () => _error = 'Enter full legal or display name (min 2 characters).',
      );
      return;
    }
    final rawPhone = _phone.text.trim();
    final e164 = _normalizeE164(rawPhone);
    if (rawPhone.isNotEmpty && e164 == null) {
      setState(
        () => _error = 'Enter a valid 10-digit mobile number or +E.164 phone.',
      );
      return;
    }
    final gst = _gstin.text.trim().toUpperCase();
    if (gst.isNotEmpty &&
        !RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(gst)) {
      setState(
        () => _error = 'GSTIN must be a valid 15-character Indian GST number.',
      );
      return;
    }
    final pan = _pan.text.trim().toUpperCase();
    if (pan.isNotEmpty && !RegExp(r'^[A-Z]{5}\d{4}[A-Z]$').hasMatch(pan)) {
      setState(
        () => _error = 'PAN must follow valid 10-character Indian PAN format.',
      );
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
          {
            'kind': 'PHONE',
            'label': 'Primary Mobile',
            'value': e164,
            'isPrimary': true,
          },
        if (_email.text.trim().isNotEmpty)
          {
            'kind': 'EMAIL',
            'label': 'Email',
            'value': _email.text.trim().toLowerCase(),
            'isPrimary': e164 == null,
          },
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

      final code = _code.text.trim().isEmpty
          ? _autoPartyCode(_role, name)
          : _code.text.trim().toUpperCase();

      final d = await api.post(
        '/parties',
        idempotent: true,
        body: {
          'code': code,
          'kind': gst.isNotEmpty ? 'ORGANIZATION' : _kind,
          'displayName': name,
          'legalName': name,
          'roles': [_role],
          'contacts': contacts,
          'addresses': const <Map<String, dynamic>>[],
          'taxRegistrations': taxRegs,
        },
      );

      final created = Party.fromJson(asMap(d));
      if (pan.isNotEmpty && created.id.isNotEmpty) {
        try {
          await api.post(
            '/parties/${created.id}/kyc',
            idempotent: true,
            body: {
              'documentType': 'PAN',
              'identifier': pan,
            },
          );
        } catch (_) {}
      }

      if (mounted) {
        toast(context, '${created.name} registered.');
        Navigator.pop(context, created);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'MFA_REQUIRED'
              ? 'Two-factor authentication is required by tenant policy to create master parties.'
              : e.message,
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        18,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Register Enterprise Party', style: T.display(22)),
          const SizedBox(height: 14),
          const FieldLabel('Party Role'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
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
                    if (r.$1 == 'SUPPLIER' || r.$1 == 'REFINER') {
                      _kind = 'ORGANIZATION';
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SaasField(
            label: 'Party code (optional — auto if blank)',
            controller: _code,
            mono: true,
          ),
          const SizedBox(height: 12),
          SaasField(
            label: 'Display / Legal Name',
            controller: _name,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SaasField(
                  label: 'Mobile (+91 / E.164)',
                  controller: _phone,
                  mono: true,
                  keyboardType: TextInputType.phone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SaasField(
                  label: 'Email (Optional)',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SaasField(
                  label: 'PAN (Optional)',
                  controller: _pan,
                  mono: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SaasField(
                  label: 'GSTIN (Optional)',
                  controller: _gstin,
                  mono: true,
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ErrorBanner(_error!),
            ),
          const SizedBox(height: 18),
          RoyalGoldButton(
            label: 'Create party',
            busy: _busy,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
