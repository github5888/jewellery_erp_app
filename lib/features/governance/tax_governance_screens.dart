import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../debug/api_inspector.dart';

String _gStr(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
  for (final k in keys) {
    final v = m[k];
    if (v is Map) {
      final inner = v['displayName'] ?? v['legalName'] ?? v['name'] ?? v['code'];
      if (inner != null && '$inner'.isNotEmpty) return '$inner';
    } else if (v != null && '$v'.isNotEmpty && v is! List) {
      return '$v';
    }
  }
  return fallback;
}

// ============================================================================
// 1. PROVIDER INTEGRATIONS — Screenshot 692 (`/integrations`)
// ============================================================================

class ProviderIntegrationsScreen extends StatefulWidget {
  const ProviderIntegrationsScreen({super.key});
  @override
  State<ProviderIntegrationsScreen> createState() => _ProviderIntegrationsScreenState();
}

class _ProviderIntegrationsScreenState extends State<ProviderIntegrationsScreen> {
  String _tab = 'CONN';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> _ws = const {};
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _operations = [];

  final _auditReasonCtrl = TextEditingController();

  // Register provider connection (Screenshot 692)
  String _capability = 'PAYMENT';
  final _providerKeyCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  String _scope = 'BRANCH';
  final _endpointCtrl = TextEditingController();
  final _credSecretCtrl = TextEditingController();
  final _webhookSecretCtrl = TextEditingController();
  final _adapterJsonCtrl = TextEditingController(text: '{\n  "timeoutMs": 5000\n}');

  // Prepare outbound operation
  final _connIdCtrl = TextEditingController();
  final _opKindCtrl = TextEditingController();
  final _corrRefCtrl = TextEditingController();
  final _opPayloadCtrl = TextEditingController(text: '{}');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _auditReasonCtrl.dispose();
    _providerKeyCtrl.dispose();
    _displayNameCtrl.dispose();
    _endpointCtrl.dispose();
    _credSecretCtrl.dispose();
    _webhookSecretCtrl.dispose();
    _adapterJsonCtrl.dispose();
    _connIdCtrl.dispose();
    _opKindCtrl.dispose();
    _corrRefCtrl.dispose();
    _opPayloadCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/integrations');
      if (!mounted) return;
      final m = asMap(d);
      setState(() {
        _ws = m;
        _connections = asList(m['connections'] ?? d, keys: const ['connections', 'providers', 'items']);
        _operations = asList(m['operations'] ?? m['outboundOperations'] ?? const []);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveConnection() async {
    if (_auditReasonCtrl.text.trim().length < 5) {
      toast(context, 'Enter Audit reason before registering a provider connection.', error: true);
      return;
    }
    if (_providerKeyCtrl.text.trim().isEmpty || _displayNameCtrl.text.trim().isEmpty) {
      toast(context, 'Enter Provider key and Display name.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final adapterConfig = _adapterJsonCtrl.text.trim().isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(_adapterJsonCtrl.text.trim());
      await context.read<ApiClient>().post(
        '/integrations',
        idempotencyKey: const Uuid().v4(),
        body: {
          'capability': _capability,
          'providerKey': _providerKeyCtrl.text.trim(),
          'displayName': _displayNameCtrl.text.trim(),
          'scope': _scope,
          'endpointUrl': _endpointCtrl.text.trim(),
          'credentialSecretRef': _credSecretCtrl.text.trim(),
          if (_webhookSecretCtrl.text.trim().isNotEmpty) 'webhookSecretRef': _webhookSecretCtrl.text.trim(),
          'adapterConfig': adapterConfig,
          'reason': _auditReasonCtrl.text.trim(),
        },
      );
      _providerKeyCtrl.clear();
      _displayNameCtrl.clear();
      await _load();
      if (mounted) toast(context, 'Draft provider connection saved.');
    } on FormatException {
      if (mounted) toast(context, 'Adapter configuration must be valid JSON.', error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _prepareOperation() async {
    if (_auditReasonCtrl.text.trim().length < 5) {
      toast(context, 'Enter Audit reason before queueing an outbound operation.', error: true);
      return;
    }
    if (_connIdCtrl.text.trim().isEmpty || _opKindCtrl.text.trim().isEmpty) {
      toast(context, 'Select Connection and enter Operation kind.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final payload = jsonDecode(_opPayloadCtrl.text.trim());
      await context.read<ApiClient>().post(
        '/integrations/operations',
        idempotencyKey: const Uuid().v4(),
        body: {
          'connectionId': _connIdCtrl.text.trim(),
          'operationKind': _opKindCtrl.text.trim(),
          if (_corrRefCtrl.text.trim().isNotEmpty) 'correlationRef': _corrRefCtrl.text.trim(),
          'payload': payload,
          'reason': _auditReasonCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) toast(context, 'Outbound operation prepared.');
    } on FormatException {
      if (mounted) toast(context, 'Payload must be valid JSON.', error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _connections.where((c) => '${c['state']}'.toUpperCase() == 'ACTIVE').length;
    final connOpts = _connections
        .map((c) => LookupOption(
              id: '${c['id'] ?? ''}',
              label: '${c['displayName'] ?? c['providerKey'] ?? 'Connection'} (${c['capability'] ?? ''})',
              raw: c,
            ))
        .where((o) => o.id.isNotEmpty)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Integrations'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.cloud_sync_outlined,
              badge: 'Gateway Governance',
              title: 'Provider Integration Foundation',
              subtitle:
                  'Controlled adapter registry, outbound operation queue, signed webhook verification, and secret-reference governance.',
            ),
            const SizedBox(height: 14),
            ResponsiveGrid2(children: [
              MetricTile(
                label: 'Connections',
                value: '${_ws['connectionsCount'] ?? _connections.length}',
                icon: Icons.link_rounded,
              ),
              MetricTile(
                label: 'Active',
                value: '${_ws['activeCount'] ?? activeCount}',
                icon: Icons.check_circle_outline_rounded,
              ),
              MetricTile(
                label: 'Pending Operations',
                value: '${_ws['pendingOperationsCount'] ?? _operations.length}',
                icon: Icons.schedule_rounded,
              ),
              MetricTile(
                label: 'Verified Webhooks',
                value: '${_ws['verifiedWebhooksCount'] ?? 0}',
                icon: Icons.verified_user_outlined,
              ),
            ]),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Audit reason (required for every provider command)'),
                TextField(
                  controller: _auditReasonCtrl,
                  decoration: const InputDecoration(hintText: 'Ticket / compliance authorization note'),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: const [
                ('CONN', 'Register Connection', Icons.settings_ethernet_rounded),
                ('OPS', 'Outbound Operations', Icons.send_outlined),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 110))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'CONN') ...[
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Register provider connection', style: T.display(18)),
                  const SizedBox(height: 14),
                  ResponsiveGrid2(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Capability'),
                      GoldDropdown<String>(
                        value: _capability,
                        items: const [
                          DropdownMenuItem(value: 'PAYMENT', child: Text('PAYMENT')),
                          DropdownMenuItem(value: 'GST_EINVOICE', child: Text('GST_EINVOICE')),
                          DropdownMenuItem(value: 'MESSAGING', child: Text('MESSAGING')),
                          DropdownMenuItem(value: 'WEBHOOK', child: Text('WEBHOOK')),
                        ],
                        onChanged: (v) => setState(() => _capability = v ?? 'PAYMENT'),
                      ),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Scope'),
                      GoldDropdown<String>(
                        value: _scope,
                        items: const [
                          DropdownMenuItem(value: 'BRANCH', child: Text('Branch')),
                          DropdownMenuItem(value: 'LEGAL_ENTITY', child: Text('Legal entity')),
                        ],
                        onChanged: (v) => setState(() => _scope = v ?? 'BRANCH'),
                      ),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  const FieldLabel('Provider key'),
                  TextField(controller: _providerKeyCtrl, style: T.mono(13.5), decoration: const InputDecoration(hintText: 'razorpay / clear-gst / whatsapp-cloud')),
                  const SizedBox(height: 12),
                  const FieldLabel('Display name'),
                  TextField(controller: _displayNameCtrl),
                  const SizedBox(height: 12),
                  const FieldLabel('HTTPS endpoint'),
                  TextField(controller: _endpointCtrl, style: T.mono(13), decoration: const InputDecoration(hintText: 'https://api.provider.example')),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Credential secret ref'),
                      TextField(controller: _credSecretCtrl, style: T.mono(13)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Webhook secret ref (opt)'),
                      TextField(controller: _webhookSecretCtrl, style: T.mono(13)),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  const FieldLabel('Adapter configuration JSON'),
                  TextField(controller: _adapterJsonCtrl, maxLines: 3, style: T.mono(12)),
                  const SizedBox(height: 16),
                  RoyalGoldButton(
                    label: 'Save draft connection',
                    icon: Icons.save_outlined,
                    busy: _busy,
                    onPressed: _saveConnection,
                  ),
                ]),
              ),
              const SectionLabel('Registered Connections'),
              if (_connections.isEmpty)
                const Panel(
                  child: EmptyBlock(
                    icon: Icons.cloud_off_rounded,
                    title: 'No provider connections configured',
                    body: 'Register payment, GST IRP, or messaging adapters above.',
                  ),
                )
              else
                for (final c in _connections)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(_gStr(c, ['displayName', 'providerKey'], 'Provider'), style: T.display(17))),
                          StatusPill(_gStr(c, ['state'], 'DRAFT')),
                        ]),
                        const SizedBox(height: 6),
                        KeyValue('Capability', _gStr(c, ['capability'], '-'), mono: true),
                        if (_gStr(c, ['endpointUrl']).isNotEmpty)
                          KeyValue('Endpoint', _gStr(c, ['endpointUrl']), mono: true),
                      ]),
                    ),
                  ),
            ] else ...[
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Prepare outbound operation', style: T.display(18)),
                  const SizedBox(height: 14),
                  LookupField(label: 'Connection', controller: _connIdCtrl, options: connOpts),
                  const SizedBox(height: 12),
                  const FieldLabel('Operation kind'),
                  TextField(controller: _opKindCtrl, style: T.mono(13.5)),
                  const SizedBox(height: 12),
                  const FieldLabel('Idempotency / correlation ref'),
                  TextField(controller: _corrRefCtrl, style: T.mono(13.5)),
                  const SizedBox(height: 12),
                  const FieldLabel('Payload JSON'),
                  TextField(controller: _opPayloadCtrl, maxLines: 4, style: T.mono(12)),
                  const SizedBox(height: 16),
                  RoyalGoldButton(
                    label: 'Prepare outbound operation',
                    icon: Icons.send_outlined,
                    busy: _busy,
                    onPressed: _prepareOperation,
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. GST REGISTRATION & TRANSPORT — Screenshots 693–694 (`/gst-compliance`)
// ============================================================================

class GstRegistrationTransportScreen extends StatefulWidget {
  const GstRegistrationTransportScreen({super.key});
  @override
  State<GstRegistrationTransportScreen> createState() => _GstRegistrationTransportScreenState();
}

class _GstRegistrationTransportScreenState extends State<GstRegistrationTransportScreen> {
  String _tab = 'PROFILE';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _submissions = [];

  final _auditReasonCtrl = TextEditingController();

  // Effective GST profile (Screenshots 693–694)
  final _gstinCtrl = TextEditingController();
  final _legalNameCtrl = TextEditingController();
  final _tradeNameCtrl = TextEditingController();
  final _addr1Ctrl = TextEditingController();
  final _addr2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCodeCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _ewayThresholdCtrl = TextEditingController(text: '50000.00');
  final _windowDaysCtrl = TextEditingController(text: '30');
  final _stockHoldCtrl = TextEditingController(text: '120');
  final _effFromCtrl = TextEditingController(text: todayIso());
  final _effUntilCtrl = TextEditingController();
  bool _enableEinvoice = false;
  bool _requireIrn = false;
  bool _enableEwayControl = false;

  // Prepare provider submission
  String _docKind = 'E_INVOICE_IRN';
  final _invoiceCtrl = TextEditingController();
  final _providerConnCtrl = TextEditingController();
  final _periodCtrl = TextEditingController();
  final _seriesCtrl = TextEditingController();
  final _posStateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _auditReasonCtrl.dispose();
    _gstinCtrl.dispose();
    _legalNameCtrl.dispose();
    _tradeNameCtrl.dispose();
    _addr1Ctrl.dispose();
    _addr2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCodeCtrl.dispose();
    _pinCtrl.dispose();
    _ewayThresholdCtrl.dispose();
    _windowDaysCtrl.dispose();
    _stockHoldCtrl.dispose();
    _effFromCtrl.dispose();
    _effUntilCtrl.dispose();
    _invoiceCtrl.dispose();
    _providerConnCtrl.dispose();
    _periodCtrl.dispose();
    _seriesCtrl.dispose();
    _posStateCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/gst-compliance'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeSales: true,
          includeIntegrations: true,
          includeAccounting: true,
        ),
      ]);
      if (!mounted) return;
      final ws = asMap(res[0]);
      setState(() {
        _profiles = asList(ws['profiles'] ?? ws['gstProfiles'] ?? const []);
        _submissions = asList(ws['submissions'] ?? ws['registrations'] ?? const []);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    if (_auditReasonCtrl.text.trim().length < 5) {
      toast(context, 'Enter Audit reason before saving GST profile.', error: true);
      return;
    }
    if (_gstinCtrl.text.trim().isEmpty || _legalNameCtrl.text.trim().isEmpty) {
      toast(context, 'Enter Seller GSTIN and Registered legal name.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/gst-compliance/profiles',
        idempotencyKey: const Uuid().v4(),
        body: {
          'sellerGstin': _gstinCtrl.text.trim().toUpperCase(),
          'registeredLegalName': _legalNameCtrl.text.trim(),
          'tradeName': _tradeNameCtrl.text.trim(),
          'addressLine1': _addr1Ctrl.text.trim(),
          'addressLine2': _addr2Ctrl.text.trim(),
          'city': _cityCtrl.text.trim(),
          'stateCode': _stateCodeCtrl.text.trim(),
          'postalCode': _pinCtrl.text.trim(),
          'ewayBillThresholdInr': normAmount(_ewayThresholdCtrl.text),
          'reportingWindowDays': int.tryParse(_windowDaysCtrl.text.trim()) ?? 30,
          'stockHoldMinutes': int.tryParse(_stockHoldCtrl.text.trim()) ?? 120,
          'effectiveFrom': _effFromCtrl.text.trim(),
          if (_effUntilCtrl.text.trim().isNotEmpty) 'effectiveUntil': _effUntilCtrl.text.trim(),
          'enableEinvoiceRegistration': _enableEinvoice,
          'requireIrnForRegisteredCustomers': _requireIrn,
          'enableThresholdEwayControl': _enableEwayControl,
          'reason': _auditReasonCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) toast(context, 'Draft GST profile saved.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _prepareSubmission() async {
    if (_auditReasonCtrl.text.trim().length < 5) {
      toast(context, 'Enter Audit reason before queueing IRP / E-way submission.', error: true);
      return;
    }
    if (_invoiceCtrl.text.trim().isEmpty) {
      toast(context, 'Select an Invoice.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/gst-compliance/submissions',
        idempotencyKey: const Uuid().v4(),
        body: {
          'documentKind': _docKind,
          'invoiceId': _invoiceCtrl.text.trim(),
          if (_providerConnCtrl.text.trim().isNotEmpty) 'providerConnectionId': _providerConnCtrl.text.trim(),
          if (_periodCtrl.text.trim().isNotEmpty) 'postingPeriodId': _periodCtrl.text.trim(),
          if (_seriesCtrl.text.trim().isNotEmpty) 'documentSeriesId': _seriesCtrl.text.trim(),
          'placeOfSupplyStateCode': _posStateCtrl.text.trim(),
          'reason': _auditReasonCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) toast(context, 'GST provider submission prepared & queued.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GST Registration & Transport'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.verified_user_outlined,
              badge: 'IRP & E-Way Governance',
              title: 'GST Registration & Transport',
              subtitle:
                  'Prepare registered-customer invoices, review provider evidence and track IRN / E-way bill registration before posting or dispatch.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Audit reason (required for commands)'),
                TextField(
                  controller: _auditReasonCtrl,
                  decoration: const InputDecoration(hintText: 'Accountant / GST officer authorization note'),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: const [
                ('PROFILE', 'Effective GST Profile', Icons.shield_outlined),
                ('SUBMIT', 'IRN & E-Way Queue', Icons.local_shipping_outlined),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 110))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'PROFILE') ...[
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Effective GST profile', style: T.display(18)),
                  const SizedBox(height: 4),
                  Text(
                    'Enter accountant-approved applicability and reporting rules for this legal entity.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Seller GSTIN'),
                  TextField(
                    controller: _gstinCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: T.mono(13.5),
                    decoration: const InputDecoration(hintText: '15-character GSTIN'),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Registered legal name'),
                  TextField(controller: _legalNameCtrl),
                  const SizedBox(height: 12),
                  const FieldLabel('Trade name'),
                  TextField(controller: _tradeNameCtrl),
                  const SizedBox(height: 12),
                  const FieldLabel('Address line 1'),
                  TextField(controller: _addr1Ctrl),
                  const SizedBox(height: 12),
                  const FieldLabel('Address line 2'),
                  TextField(controller: _addr2Ctrl),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('City / location'),
                      TextField(controller: _cityCtrl),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('GST state code'),
                      TextField(controller: _stateCodeCtrl, style: T.mono(13.5), decoration: const InputDecoration(hintText: '09 / 27')),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('PIN code'),
                      TextField(controller: _pinCtrl, keyboardType: TextInputType.number, style: T.mono(13.5)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Stock hold (minutes)'),
                      TextField(controller: _stockHoldCtrl, keyboardType: TextInputType.number, style: T.mono(13.5)),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('E-way threshold (INR)'),
                      TextField(controller: _ewayThresholdCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), style: T.mono(13.5)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const FieldLabel('Reporting window (days)'),
                      TextField(controller: _windowDaysCtrl, keyboardType: TextInputType.number, style: T.mono(13.5)),
                    ]),
                  ]),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    DatePickField(label: 'Effective from', controller: _effFromCtrl),
                    DatePickField(label: 'Effective until', controller: _effUntilCtrl, optional: true),
                  ]),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: Pal.goldWash,
                    title: Text('Enable e-invoice registration', style: T.body(13.2, w: FontWeight.w600)),
                    value: _enableEinvoice,
                    onChanged: (v) => setState(() => _enableEinvoice = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: Pal.goldWash,
                    title: Text('Require IRN for registered customers', style: T.body(13.2, w: FontWeight.w600)),
                    value: _requireIrn,
                    onChanged: (v) => setState(() => _requireIrn = v),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeTrackColor: Pal.goldWash,
                    title: Text('Enable threshold-based e-way bill control', style: T.body(13.2, w: FontWeight.w600)),
                    value: _enableEwayControl,
                    onChanged: (v) => setState(() => _enableEwayControl = v),
                  ),
                  const SizedBox(height: 12),
                  RoyalGoldButton(
                    label: 'Save draft profile',
                    icon: Icons.verified_outlined,
                    busy: _busy,
                    onPressed: _saveProfile,
                  ),
                ]),
              ),
              const SectionLabel('GST Profiles'),
              if (_profiles.isEmpty)
                const Panel(
                  child: EmptyBlock(
                    icon: Icons.shield_outlined,
                    title: 'No GST profile configured',
                    body: 'Save an effective GST profile above to govern IRN & E-way bill thresholds.',
                  ),
                )
              else
                for (final p in _profiles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(_gStr(p, ['sellerGstin', 'gstin'], 'GSTIN'), style: T.mono(15, w: FontWeight.w700))),
                          StatusPill(_gStr(p, ['state'], 'DRAFT')),
                        ]),
                        const SizedBox(height: 6),
                        KeyValue('Legal Name', _gStr(p, ['registeredLegalName', 'legalName'], '-')),
                      ]),
                    ),
                  ),
            ] else ...[
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Prepare provider submission', style: T.display(18)),
                  const SizedBox(height: 14),
                  const FieldLabel('Document kind'),
                  GoldDropdown<String>(
                    value: _docKind,
                    items: const [
                      DropdownMenuItem(value: 'E_INVOICE_IRN', child: Text('E-invoice / IRN')),
                      DropdownMenuItem(value: 'E_WAY_BILL', child: Text('E-way bill')),
                    ],
                    onChanged: (v) => setState(() => _docKind = v ?? 'E_INVOICE_IRN'),
                  ),
                  const SizedBox(height: 12),
                  LookupField(label: 'Invoice', controller: _invoiceCtrl, options: _lookup.invoices),
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Tax provider connection',
                    controller: _providerConnCtrl,
                    options: _lookup.connections,
                  ),
                  const SizedBox(height: 12),
                  ResponsiveGrid2(children: [
                    LookupField(label: 'Open posting period', controller: _periodCtrl, options: _lookup.openPeriods()),
                    LookupField(label: 'Invoice series', controller: _seriesCtrl, options: _lookup.seriesFor(const ['INVOICE', 'SALES'])),
                  ]),
                  const SizedBox(height: 12),
                  const FieldLabel('Place of supply (GST state code)'),
                  TextField(controller: _posStateCtrl, style: T.mono(13.5), decoration: const InputDecoration(hintText: '2-digit GST state code')),
                  const SizedBox(height: 16),
                  RoyalGoldButton(
                    label: 'Prepare & queue',
                    icon: Icons.send_outlined,
                    busy: _busy,
                    onPressed: _prepareSubmission,
                  ),
                ]),
              ),
              const SectionLabel('Registration, Cancellation & Recovery'),
              if (_submissions.isEmpty)
                const Panel(
                  child: EmptyBlock(
                    icon: Icons.local_shipping_outlined,
                    title: 'No GST submission prepared',
                    body: 'Prepared IRN and E-way bill submissions appear here with ack numbers and recovery controls.',
                  ),
                )
              else
                for (final s in _submissions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Panel(
                      child: Row(children: [
                        Expanded(child: Text(_gStr(s, ['irn', 'documentKind', 'id'], 'GST Submission'), style: T.body(13.5, w: FontWeight.w700))),
                        StatusPill(_gStr(s, ['state', 'status'], 'QUEUED')),
                      ]),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 3. GST RETURNS & ITC REVIEW — Screenshots 695–696 (`/gst-returns`)
// ============================================================================

class GstReturnsItcScreen extends StatefulWidget {
  const GstReturnsItcScreen({super.key});
  @override
  State<GstReturnsItcScreen> createState() => _GstReturnsItcScreenState();
}

class _GstReturnsItcScreenState extends State<GstReturnsItcScreen> {
  String _tab = 'GSTR2B';
  late String _returnMonth =
      '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
  bool _loading = true;
  bool _busy = false;
  String? _error;

  Map<String, dynamic> _ws = const {};
  final _reasonCtrl = TextEditingController();
  final _evidenceCtrl = TextEditingController();

  // 1. Import & reconcile GSTR-2B
  final _gstr2bJsonCtrl = TextEditingController();
  final _importedStmtCtrl = TextEditingController();

  // 2. Prepare GSTR working papers
  final _approvedReconCtrl = TextEditingController();
  final _b2clThresholdCtrl = TextEditingController(text: '250000.00');
  final _mappingsJsonCtrl = TextEditingController();

  // 3. Working papers & approvals
  final _selectedPaperCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _evidenceCtrl.dispose();
    _gstr2bJsonCtrl.dispose();
    _importedStmtCtrl.dispose();
    _approvedReconCtrl.dispose();
    _b2clThresholdCtrl.dispose();
    _mappingsJsonCtrl.dispose();
    _selectedPaperCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/gst-returns', query: {
        'returnMonth': _returnMonth,
        'period': _returnMonth,
      });
      if (mounted) setState(() => _ws = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _returnMonth = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
      });
      _load();
    }
  }

  Future<void> _importGstr2b() async {
    if (_reasonCtrl.text.trim().length < 5) {
      toast(context, 'Enter Command reason first.', error: true);
      return;
    }
    if (_gstr2bJsonCtrl.text.trim().isEmpty) {
      toast(context, 'Paste NORMALIZED_GSTR2B_V1 JSON records.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final parsed = jsonDecode(_gstr2bJsonCtrl.text.trim());
      await context.read<ApiClient>().post(
        '/gst-returns/gstr2b/import',
        idempotencyKey: const Uuid().v4(),
        body: {
          'returnMonth': _returnMonth,
          'records': parsed,
          'reason': _reasonCtrl.text.trim(),
          'evidence': _evidenceCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) toast(context, 'GSTR-2B records imported.');
    } on FormatException {
      if (mounted) toast(context, 'Invalid JSON in GSTR-2B records.', error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _buildReconciliation() async {
    if (_importedStmtCtrl.text.trim().isEmpty) {
      toast(context, 'Select an Imported statement first.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/gst-returns/gstr2b/reconcile',
        idempotencyKey: const Uuid().v4(),
        body: {
          'returnMonth': _returnMonth,
          'statementId': _importedStmtCtrl.text.trim(),
          'reason': _reasonCtrl.text.trim(),
          'evidence': _evidenceCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) toast(context, 'ITC reconciliation built.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  void _populateMappingTemplate() {
    setState(() {
      _mappingsJsonCtrl.text = const JsonEncoder.withIndent('  ').convert({
        'format': 'REVIEWED_GST_MAPPING_V1',
        'returnMonth': _returnMonth,
        'b2clThresholdInr': normAmount(_b2clThresholdCtrl.text),
        'hsnOverrides': const [],
        'itcReversals': const [],
      });
    });
  }

  Future<void> _prepareWorkingPaper() async {
    if (_reasonCtrl.text.trim().length < 5) {
      toast(context, 'Enter Command reason first.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final mappings = _mappingsJsonCtrl.text.trim().isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(_mappingsJsonCtrl.text.trim());
      await context.read<ApiClient>().post(
        '/gst-returns/working-papers',
        idempotencyKey: const Uuid().v4(),
        body: {
          'returnMonth': _returnMonth,
          if (_approvedReconCtrl.text.trim().isNotEmpty) 'reconciliationId': _approvedReconCtrl.text.trim(),
          'b2clThresholdInr': normAmount(_b2clThresholdCtrl.text),
          'mappings': mappings,
          'reason': _reasonCtrl.text.trim(),
          'evidence': _evidenceCtrl.text.trim(),
        },
      );
      await _load();
      if (mounted) toast(context, 'GSTR working paper revision prepared.');
    } on FormatException {
      if (mounted) toast(context, 'Reviewed mappings must be valid JSON.', error: true);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final statements = asList(_ws['importedStatements'] ?? _ws['gstr2bStatements'] ?? const []);
    final recons = asList(_ws['reconciliations'] ?? const []);
    final papers = asList(_ws['workingPapers'] ?? _ws['revisions'] ?? const []);
    final exports = asList(_ws['exports'] ?? _ws['exportHistory'] ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('GST Returns & ITC Review'),
        actions: [
          TextButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_today_outlined, size: 15),
            label: Text(_returnMonth, style: T.mono(12.5, color: Pal.goldDeep)),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.description_outlined,
              badge: 'GSTR-1 · GSTR-3B · GSTR-2B',
              title: 'GST Returns & ITC Review',
              subtitle:
                  'Entity-wide GSTR-1 and GSTR-3B working papers, authorized GSTR-2B imports, and evidence-backed ITC eligibility review.',
            ),
            const SizedBox(height: 14),
            ResponsiveGrid2(children: [
              MetricTile(
                label: 'Posted Outward Lines',
                value: '${_ws['postedOutwardLinesCount'] ?? _ws['postedOutwardLines'] ?? 0}',
                icon: Icons.receipt_long_outlined,
              ),
              MetricTile(
                label: 'Purchase Books',
                value: '${_ws['purchaseBooksCount'] ?? _ws['purchaseBooks'] ?? 0}',
                icon: Icons.shopping_bag_outlined,
              ),
              MetricTile(
                label: 'Working-Paper Revisions',
                value: '${_ws['workingPaperRevisionsCount'] ?? papers.length}',
                icon: Icons.layers_outlined,
              ),
              MetricTile(
                label: 'Return Period',
                value: _returnMonth,
                icon: Icons.calendar_month_outlined,
                onTap: _pickMonth,
              ),
            ]),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Command reason'),
                TextField(controller: _reasonCtrl, decoration: const InputDecoration(hintText: 'Monthly GST return preparation reason')),
                const SizedBox(height: 10),
                const FieldLabel('ITC review evidence / reference'),
                TextField(controller: _evidenceCtrl, decoration: const InputDecoration(hintText: '2B portal snapshot / CA sign-off ref')),
              ]),
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: const [
                ('GSTR2B', '1. GSTR-2B Import', Icons.download_done_rounded),
                ('PAPERS', '2. Working Papers', Icons.assignment_outlined),
                ('EXPORTS', '3. Approvals & Exports', Icons.verified_outlined),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 110))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'GSTR2B')
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('1. Import & reconcile GSTR-2B', style: T.display(18)),
                  const SizedBox(height: 4),
                  Text(
                    'Use authorized records normalized to NORMALIZED_GSTR2B_V1.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Normalized GSTR-2B records'),
                  TextField(
                    controller: _gstr2bJsonCtrl,
                    maxLines: 5,
                    style: T.mono(12),
                    decoration: const InputDecoration(hintText: '[ { "supplierGstin": "...", ... } ]'),
                  ),
                  const SizedBox(height: 12),
                  RoyalGoldButton(
                    label: 'Import records',
                    icon: Icons.upload_file_outlined,
                    busy: _busy,
                    onPressed: _importGstr2b,
                  ),
                  const SizedBox(height: 14),
                  LookupField(
                    label: 'Imported statement',
                    controller: _importedStmtCtrl,
                    options: statements
                        .map((s) => LookupOption(id: '${s['id'] ?? ''}', label: '${s['statementNumber'] ?? s['id']}'))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _buildReconciliation,
                    icon: const Icon(Icons.sync_rounded, size: 17),
                    label: const Text('Build reconciliation'),
                  ),
                ]),
              )
            else if (_tab == 'PAPERS')
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('2. Prepare GSTR working papers', style: T.display(18)),
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Approved ITC reconciliation',
                    controller: _approvedReconCtrl,
                    options: recons
                        .map((r) => LookupOption(id: '${r['id'] ?? ''}', label: '${r['id']} (${r['state'] ?? ''})'))
                        .toList(),
                    optional: true,
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Accountant-approved B2CL threshold (INR)'),
                  TextField(
                    controller: _b2clThresholdCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: T.mono(13.5),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _populateMappingTemplate,
                      icon: const Icon(Icons.auto_fix_high_outlined, size: 16),
                      label: const Text('Create mapping template from posted sources'),
                    ),
                  ),
                  const FieldLabel('Reviewed HSN, place-of-supply, tax heads and reversal mappings'),
                  TextField(
                    controller: _mappingsJsonCtrl,
                    maxLines: 5,
                    style: T.mono(12),
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Prepare revision',
                    icon: Icons.fact_check_outlined,
                    busy: _busy,
                    onPressed: _prepareWorkingPaper,
                  ),
                ]),
              )
            else ...[
              Panel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Working papers & approvals', style: T.display(18)),
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Select record',
                    controller: _selectedPaperCtrl,
                    options: papers
                        .map((p) => LookupOption(id: '${p['id'] ?? ''}', label: 'Rev ${p['revision'] ?? 1} · ${p['state'] ?? 'DRAFT'}'))
                        .toList(),
                  ),
                ]),
              ),
              const SectionLabel('Export History'),
              if (exports.isEmpty)
                const Panel(
                  child: EmptyBlock(
                    icon: Icons.folder_zip_outlined,
                    title: 'No approved export created',
                    body: 'Downloads contain approved preparation snapshots and do not represent GST filing acknowledgements.',
                  ),
                )
              else
                for (final ex in exports)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Panel(
                      child: Row(children: [
                        Expanded(child: Text(_gStr(ex, ['fileName', 'format', 'id'], 'GST Export'), style: T.body(13.5, w: FontWeight.w700))),
                        StatusPill(_gStr(ex, ['state'], 'READY')),
                      ]),
                    ),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 4. CUSTOMER MESSAGING — `/messaging`
// ============================================================================

class CustomerMessagingScreen extends StatefulWidget {
  const CustomerMessagingScreen({super.key});
  @override
  State<CustomerMessagingScreen> createState() => _CustomerMessagingScreenState();
}

class _CustomerMessagingScreenState extends State<CustomerMessagingScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _partyCtrl = TextEditingController();
  String _channel = 'WHATSAPP';
  final _templateCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _partyCtrl.dispose();
    _templateCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/messaging'),
        WorkspaceLookup.load(api, includeParties: true),
      ]);
      if (!mounted) return;
      setState(() {
        _messages = asList(res[0], keys: const ['messages', 'dispatches', 'templates', 'items', 'rows']);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    if (_partyCtrl.text.trim().isEmpty || _bodyCtrl.text.trim().isEmpty) {
      toast(context, 'Select recipient party and enter message content.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<ApiClient>().post(
        '/messaging',
        idempotencyKey: const Uuid().v4(),
        body: {
          'partyId': _partyCtrl.text.trim(),
          'channel': _channel,
          if (_templateCtrl.text.trim().isNotEmpty) 'templateKey': _templateCtrl.text.trim(),
          'body': _bodyCtrl.text.trim(),
          'message': _bodyCtrl.text.trim(),
        },
      );
      _bodyCtrl.clear();
      await _load();
      if (mounted) toast(context, 'Consent-verified notification queued.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Messaging'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.chat_bubble_outline_rounded,
              badge: 'Consent-Gated Outreach',
              title: 'Customer Messaging & Alerts',
              subtitle:
                  'Send invoice, custom-order, repair-ready, and rate-alert notifications across WhatsApp, SMS, and Email with consent verification.',
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Queue Patron Notification', style: T.display(18)),
                const SizedBox(height: 14),
                LookupField(
                  label: 'Recipient Party',
                  controller: _partyCtrl,
                  options: _lookup.parties,
                ),
                const SizedBox(height: 12),
                ResponsiveGrid2(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Channel'),
                    GoldDropdown<String>(
                      value: _channel,
                      items: const [
                        DropdownMenuItem(value: 'WHATSAPP', child: Text('WhatsApp')),
                        DropdownMenuItem(value: 'SMS', child: Text('SMS')),
                        DropdownMenuItem(value: 'EMAIL', child: Text('Email')),
                      ],
                      onChanged: (v) => setState(() => _channel = v ?? 'WHATSAPP'),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const FieldLabel('Template key (opt)'),
                    TextField(controller: _templateCtrl, style: T.mono(13)),
                  ]),
                ]),
                const SizedBox(height: 12),
                const FieldLabel('Message body'),
                TextField(
                  controller: _bodyCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(hintText: 'Order status / invoice link / pickup intimation'),
                ),
                const SizedBox(height: 16),
                RoyalGoldButton(
                  label: 'Queue Notification',
                  icon: Icons.send_rounded,
                  busy: _busy,
                  onPressed: _send,
                ),
              ]),
            ),
            const SectionLabel('Dispatch Log'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_messages.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.mark_chat_unread_outlined,
                  title: 'No customer messages queued yet',
                  body: 'Consent-checked WhatsApp, SMS, and email dispatches appear here.',
                ),
              )
            else
              for (final m in _messages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_gStr(m, ['channel', 'templateKey', 'name'], 'Message'), style: T.body(13.5, w: FontWeight.w700)),
                          Text(_gStr(m, ['body', 'recipient', 'createdAt'], ''), style: T.body(12, color: Pal.muted)),
                        ]),
                      ),
                      StatusPill(_gStr(m, ['state', 'status'], 'QUEUED')),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 5. COMPANY & INVOICE PRINT POLICY / E-INVOICE STUDIO (`/documents/templates`)
// ============================================================================

class DocumentsPolicyScreen extends StatefulWidget {
  const DocumentsPolicyScreen({super.key});
  @override
  State<DocumentsPolicyScreen> createState() => _DocumentsPolicyScreenState();
}

class _DocumentsPolicyScreenState extends State<DocumentsPolicyScreen> {
  WorkspaceLookup _lookup = WorkspaceLookup();
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _invoiceCtrl = TextEditingController();
  String? _renderedHtmlPreview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final res = await Future.wait<dynamic>([
        api.get('/documents/templates'),
        WorkspaceLookup.load(api, includeParties: false, includeSales: true),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = asList(res[0]);
        _lookup = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createTemplateDialog() async {
    final keyCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final contentCtrl = TextEditingController(text: '<div><h1>Tax Invoice {{documentNumber}}</h1></div>');
    String layout = 'A4';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Pal.card,
          title: Text('New Print Template', style: T.display(19)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: keyCtrl, style: T.mono(13.5), decoration: const InputDecoration(labelText: 'Template Key (e.g. SALES_INVOICE_A4)')),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Template Name')),
              const SizedBox(height: 10),
              GoldDropdown<String>(
                value: layout,
                labelText: 'Print Layout',
                items: const [
                  DropdownMenuItem(value: 'A4', child: Text('A4 Showroom Laser')),
                  DropdownMenuItem(value: 'THERMAL_ROLL', child: Text('Thermal Counter Roll')),
                ],
                onChanged: (v) => setLocal(() => layout = v ?? 'A4'),
              ),
              const SizedBox(height: 10),
              TextField(controller: contentCtrl, maxLines: 4, style: T.mono(12), decoration: const InputDecoration(labelText: 'HTML Content Template')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () async {
                try {
                  await context.read<ApiClient>().post('/documents/templates', body: {
                    'templateKey': keyCtrl.text.trim().toUpperCase(),
                    'name': nameCtrl.text.trim(),
                    'layout': layout,
                    'contentTemplate': contentCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _renderInvoice() async {
    if (_invoiceCtrl.text.trim().isEmpty) {
      toast(context, 'Select a Sales Invoice to render.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = asMap(await context.read<ApiClient>().post('/documents/render', body: {
        'sourceType': 'SALES_INVOICE',
        'sourceId': _invoiceCtrl.text.trim(),
      }));
      setState(() => _renderedHtmlPreview = '${res['renderedHtml'] ?? res['documentNumber'] ?? 'Rendered OK'}');
      if (mounted) toast(context, 'Immutable invoice print snapshot rendered.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice Policy & Print Studio'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.print_outlined,
              badge: 'Document Governance',
              title: 'Company & Invoice Print Policy',
              subtitle:
                  'Manage versioned A4 & thermal invoice templates, hash-verified reprints, and GST tax invoice rendering.',
              trailing: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Pal.goldBright,
                  foregroundColor: Pal.ink,
                  minimumSize: const Size(112, 38),
                ),
                onPressed: _createTemplateDialog,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text('Template', style: T.body(12.5, color: Pal.ink, w: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 14),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Render GST Invoice Document', style: T.display(18)),
                const SizedBox(height: 12),
                LookupField(
                  label: 'Sales Invoice',
                  controller: _invoiceCtrl,
                  options: _lookup.invoices,
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  label: 'Render Immutable Print Copy',
                  icon: Icons.picture_as_pdf_outlined,
                  busy: _busy,
                  onPressed: _renderInvoice,
                ),
                if (_renderedHtmlPreview != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Pal.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Pal.line),
                    ),
                    child: Text(
                      _renderedHtmlPreview!.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: T.mono(11.5),
                    ),
                  ),
                ],
              ]),
            ),
            SectionLabel('Print Templates (${_templates.length})'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_templates.isEmpty)
              Panel(
                child: EmptyBlock(
                  icon: Icons.print_outlined,
                  title: 'No custom print templates yet',
                  body: 'Create A4 laser or thermal roll GST invoice templates for your showrooms.',
                  actionLabel: 'New Template',
                  onAction: _createTemplateDialog,
                ),
              )
            else
              for (final t in _templates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${t['name'] ?? t['templateKey']}', style: T.display(17)),
                          const SizedBox(height: 4),
                          Text('${t['templateKey']} · ${t['layout']} · v${t['version'] ?? 1}', style: T.mono(11.5, color: Pal.muted)),
                        ]),
                      ),
                      StatusPill('${t['state'] ?? 'ACTIVE'}'),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 6. SHOWROOM HIERARCHY — `/organization`
// ============================================================================

class ShowroomHierarchyScreen extends StatefulWidget {
  const ShowroomHierarchyScreen({super.key});
  @override
  State<ShowroomHierarchyScreen> createState() => _ShowroomHierarchyScreenState();
}

class _ShowroomHierarchyScreenState extends State<ShowroomHierarchyScreen> {
  List<Map<String, dynamic>> _entities = [];
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
      final d = await context.read<ApiClient>().get('/organization');
      if (mounted) setState(() => _entities = asList(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addBranchDialog() async {
    if (_entities.isEmpty) return;
    var entityId = '${_entities.first['id']}';
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Pal.card,
          title: Text('Add Showroom Branch', style: T.display(19)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            GoldDropdown<String>(
              value: entityId,
              labelText: 'Legal Entity',
              items: [
                for (final e in _entities)
                  DropdownMenuItem(value: '${e['id']}', child: Text('${e['legalName']}')),
              ],
              onChanged: (v) => setLocal(() => entityId = v ?? entityId),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              style: T.mono(13.5),
              labelText: 'Branch Code (e.g. LKO-01)',
            ),
            const SizedBox(height: 10),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Showroom Name')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () async {
                try {
                  await context.read<ApiClient>().post('/organization/branches', body: {
                    'legalEntityId': entityId,
                    'code': codeCtrl.text.trim().toUpperCase(),
                    'name': nameCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
              child: const Text('Create Branch'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Showroom Hierarchy'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.apartment_rounded,
              badge: 'Enterprise Structure',
              title: 'Showroom & Legal Entity Hierarchy',
              subtitle: 'Authorized legal entities, functional currencies, timezones, and operating showrooms.',
              trailing: _entities.isEmpty
                  ? null
                  : FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Pal.goldBright,
                        foregroundColor: Pal.ink,
                        minimumSize: const Size(112, 38),
                      ),
                      onPressed: _addBranchDialog,
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: Text('+ Branch', style: T.body(12.5, color: Pal.ink, w: FontWeight.w800)),
                    ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 100))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else
              for (final e in _entities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${e['legalName']}', style: T.display(18.5))),
                        StatusPill('${e['state'] ?? 'ACTIVE'}'),
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        '${e['functionalCurrency'] ?? 'INR'} · ${e['timezone'] ?? 'Asia/Kolkata'}',
                        style: T.body(12.2, color: Pal.muted),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      for (final b in asList(e['branches']))
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(children: [
                            const Icon(Icons.storefront_outlined, size: 16, color: Pal.goldDeep),
                            const SizedBox(width: 8),
                            MonoTag('${b['code'] ?? ''}'),
                            const SizedBox(width: 8),
                            Expanded(child: Text('${b['name'] ?? ''}', style: T.body(13.5, w: FontWeight.w700))),
                            StatusPill('${b['state'] ?? 'ACTIVE'}'),
                          ]),
                        ),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 7. ACCESS CONTROL & ROLES — `/access`
// ============================================================================

class AccessControlScreen extends StatefulWidget {
  const AccessControlScreen({super.key});
  @override
  State<AccessControlScreen> createState() => _AccessControlScreenState();
}

class _AccessControlScreenState extends State<AccessControlScreen> {
  String _tab = 'MEMBERS';
  Map<String, dynamic> _access = const {};
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
      final d = await context.read<ApiClient>().get('/access');
      if (mounted) setState(() => _access = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createRoleDialog(List<Map<String, dynamic>> perms) async {
    final keyCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: Pal.card,
          title: Text('Create Custom Role', style: T.display(19)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: keyCtrl,
                  textCapitalization: TextCapitalization.characters,
                  style: T.mono(13.5),
                  labelText: 'Role Key (e.g. VAULT_MANAGER)',
                ),
                const SizedBox(height: 10),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Role Name')),
                const SizedBox(height: 12),
                Text('PERMISSIONS (${selected.length} selected)', style: T.caps(10, color: Pal.goldDeep)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final p in perms)
                    FilterChip(
                      label: Text('${p['key']}', style: T.mono(11)),
                      selected: selected.contains('${p['key']}'),
                      selectedColor: Pal.goldWash,
                      onSelected: (on) => setLocal(() {
                        if (on) {
                          selected.add('${p['key']}');
                        } else {
                          selected.remove('${p['key']}');
                        }
                      }),
                    ),
                ]),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(110, 42)),
              onPressed: () async {
                try {
                  await context.read<ApiClient>().post('/access/roles', body: {
                    'key': keyCtrl.text.trim().toUpperCase(),
                    'name': nameCtrl.text.trim(),
                    'permissionKeys': selected.toList(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  if (ctx.mounted) toast(ctx, e.message, error: true);
                }
              },
              child: const Text('Save Role'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final members = asList(_access['memberships'] ?? const []);
    final roles = asList(_access['roles'] ?? const []);
    final perms = asList(_access['permissions'] ?? const []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Control & Roles'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.admin_panel_settings_outlined,
              badge: 'ISO/IEC 27001 RBAC',
              title: 'Access Control & Roles',
              subtitle:
                  'Manage workspace members, least-privilege showroom scopes, and versioned RBAC permission matrices.',
              trailing: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: Pal.goldBright,
                  foregroundColor: Pal.ink,
                  minimumSize: const Size(106, 38),
                ),
                onPressed: () => _createRoleDialog(perms),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: Text('+ Role', style: T.body(12.5, color: Pal.ink, w: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 14),
            PillTabs<String>(
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
              items: [
                ('MEMBERS', 'Members (${members.length})', Icons.people_outline_rounded),
                ('ROLES', 'Roles (${roles.length})', Icons.verified_user_outlined),
              ],
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Panel(child: Skeleton(height: 100))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'MEMBERS')
              for (final m in members)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                            '${asMap(m['user'])['displayName'] ?? 'Workspace Member'}',
                            style: T.display(17.5),
                          ),
                        ),
                        StatusPill('${m['state'] ?? 'ACTIVE'}'),
                      ]),
                      const SizedBox(height: 4),
                      Text('${asMap(m['user'])['email'] ?? ''}', style: T.body(12.5, color: Pal.muted)),
                      const SizedBox(height: 8),
                      KeyValue('Assigned Roles', '${(m['roleIds'] as List?)?.length ?? 0} role(s)'),
                      KeyValue('Branch Scopes', '${(m['branchScopes'] as List?)?.length ?? 0} showroom(s)'),
                    ]),
                  ),
                )
            else
              for (final r in roles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text('${r['name'] ?? r['key']}', style: T.display(17.5))),
                        MonoTag('${r['key'] ?? ''}'),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final pk in (r['permissionKeys'] as List? ?? const []).take(12))
                          Chip2('$pk', mono: true, gold: false),
                      ]),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 8. AUDIT & COMPLIANCE / SUPPORT GRANTS — `/support-grants` + API Diagnostics
// ============================================================================

class AuditComplianceScreen extends StatefulWidget {
  const AuditComplianceScreen({super.key});
  @override
  State<AuditComplianceScreen> createState() => _AuditComplianceScreenState();
}

class _AuditComplianceScreenState extends State<AuditComplianceScreen> {
  List<Map<String, dynamic>> _grants = [];
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
      final d = await context.read<ApiClient>().get('/support-grants');
      if (mounted) setState(() => _grants = asList(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _act(String grantId, String action) async {
    try {
      await context.read<ApiClient>().post(
        '/support-grants/$grantId/$action',
        idempotencyKey: const Uuid().v4(),
        body: {'reason': 'Tenant administrator $action action from mobile governance console.'},
      );
      await _load();
      if (mounted) toast(context, 'Support grant updated ($action).');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit & Compliance'),
        actions: [
          IconButton(
            tooltip: 'API Gateway Diagnostics',
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApiInspector())),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.policy_outlined,
              badge: 'Tenant Sovereignty',
              title: 'Audit, Support Grants & Compliance',
              subtitle:
                  'Approve, reject, or revoke time-boxed platform support access grants. Every operator action is cryptographically attributed.',
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApiInspector())),
              icon: const Icon(Icons.receipt_long_outlined, size: 17),
              label: const Text('Inspect Live API Request & Security Audit Log'),
            ),
            const SectionLabel('Support Access Grants'),
            if (_loading)
              const Panel(child: Skeleton(height: 80))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_grants.isEmpty)
              const Panel(
                child: EmptyBlock(
                  icon: Icons.verified_user_outlined,
                  title: 'Zero external support grants active',
                  body: 'Your tenant data is strictly isolated. Any platform support access request requires explicit tenant approval here.',
                ),
              )
            else
              for (final g in _grants)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Panel(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(_gStr(g, ['mode', 'id'], 'Support Grant'), style: T.display(17))),
                        StatusPill(_gStr(g, ['state', 'status'], 'REQUESTED')),
                      ]),
                      const SizedBox(height: 6),
                      if (_gStr(g, ['reason']).isNotEmpty) KeyValue('Reason', _gStr(g, ['reason'])),
                      if (_gStr(g, ['expiresAt']).isNotEmpty) KeyValue('Expires', formatDateTime(_gStr(g, ['expiresAt']))),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, children: [
                        if ('${g['state']}'.toUpperCase() == 'REQUESTED') ...[
                          FilledButton(
                            style: FilledButton.styleFrom(minimumSize: const Size(100, 38)),
                            onPressed: () => _act('${g['id']}', 'approve'),
                            child: const Text('Approve'),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(100, 38)),
                            onPressed: () => _act('${g['id']}', 'reject'),
                            child: const Text('Reject'),
                          ),
                        ],
                        if ('${g['state']}'.toUpperCase() == 'APPROVED' || '${g['state']}'.toUpperCase() == 'ACTIVE')
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Pal.danger,
                              minimumSize: const Size(110, 38),
                            ),
                            onPressed: () => _act('${g['id']}', 'revoke'),
                            child: const Text('Revoke Access'),
                          ),
                      ]),
                    ]),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
