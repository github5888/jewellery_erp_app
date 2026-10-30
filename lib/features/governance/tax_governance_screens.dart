import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

// ---------------------------------------------------------------------------
// 1. PROVIDER INTEGRATIONS (`/integrations`) — Screenshot (692)
// ---------------------------------------------------------------------------

class ProviderIntegrationsScreen extends StatefulWidget {
  const ProviderIntegrationsScreen({super.key});
  @override
  State<ProviderIntegrationsScreen> createState() => _ProviderIntegrationsScreenState();
}

class _ProviderIntegrationsScreenState extends State<ProviderIntegrationsScreen> {
  Map<String, dynamic> _ws = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _auditReason = TextEditingController();

  // Register provider connection (Screenshot 692 left card)
  String _capability = 'PAYMENT';
  final _providerKey = TextEditingController();
  final _displayName = TextEditingController();
  String _scope = 'LEGAL_ENTITY';
  final _endpoint = TextEditingController();
  final _credentialRef = TextEditingController();
  final _webhookRef = TextEditingController();
  final _adapterJson = TextEditingController(text: '{}');

  // Prepare outbound operation (Screenshot 692 right card)
  final _activeConnId = TextEditingController();
  final _operationType = TextEditingController();
  final _aggregateType = TextEditingController();
  final _aggregateUuid = TextEditingController();
  final _aggregateVersion = TextEditingController(text: '1');
  final _payloadJson = TextEditingController(text: '{}');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _auditReason, _providerKey, _displayName, _endpoint, _credentialRef,
      _webhookRef, _adapterJson, _activeConnId, _operationType,
      _aggregateType, _aggregateUuid, _aggregateVersion, _payloadJson,
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
      final d = await context.read<ApiClient>().get('/integrations');
      if (!mounted) return;
      setState(() => _ws = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveConnection() async {
    if (_providerKey.text.trim().isEmpty || _displayName.text.trim().isEmpty) {
      setState(() => _error = 'Enter Provider key and Display name.');
      return;
    }
    Map<String, dynamic> cfg = {};
    try {
      final decoded = jsonDecode(_adapterJson.text.trim().isEmpty ? '{}' : _adapterJson.text.trim());
      if (decoded is Map) cfg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      setState(() => _error = 'Adapter configuration JSON must be a valid JSON object.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/integrations/connections',
        idempotent: true,
        body: {
          'capability': _capability,
          'providerKey': _providerKey.text.trim().toUpperCase(),
          'displayName': _displayName.text.trim(),
          'scope': _scope,
          if (_endpoint.text.trim().isNotEmpty) 'endpointUrl': _endpoint.text.trim(),
          if (_credentialRef.text.trim().isNotEmpty)
            'credentialSecretRef': _credentialRef.text.trim(),
          if (_webhookRef.text.trim().isNotEmpty)
            'webhookSecretRef': _webhookRef.text.trim(),
          'adapterConfig': cfg,
          if (_auditReason.text.trim().isNotEmpty) 'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      _providerKey.clear();
      _displayName.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft provider connection saved.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _queueOperation() async {
    if (_activeConnId.text.trim().isEmpty ||
        _operationType.text.trim().isEmpty ||
        _aggregateType.text.trim().isEmpty ||
        _aggregateUuid.text.trim().isEmpty) {
      setState(() => _error = 'Select Active connection and fill Operation type, Aggregate type, and Aggregate UUID.');
      return;
    }
    Map<String, dynamic> payload = {};
    try {
      final decoded = jsonDecode(_payloadJson.text.trim().isEmpty ? '{}' : _payloadJson.text.trim());
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      setState(() => _error = 'Immutable payload JSON must be a valid JSON object.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/integrations/operations',
        idempotent: true,
        body: {
          'connectionId': _activeConnId.text.trim(),
          'operationType': _operationType.text.trim().toUpperCase(),
          'aggregateType': _aggregateType.text.trim(),
          'aggregateId': _aggregateUuid.text.trim(),
          'aggregateVersion': int.tryParse(_aggregateVersion.text.trim()) ?? 1,
          'payload': payload,
          if (_auditReason.text.trim().isNotEmpty) 'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      _aggregateUuid.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outbound provider operation queued.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conns = asList(_ws['connections']);
    final ops = asList(_ws['operations'] ?? _ws['outboundOperations']);
    final hooks = asList(_ws['webhooks'] ?? _ws['webhookEvents']);
    final activeCount = conns.where((c) => '${c['state'] ?? c['status']}' == 'ACTIVE').length;
    final pendingOps = ops.where((o) => '${o['state'] ?? o['status']}' == 'PENDING').length;

    final connOpts = conns
        .map((c) => LookupOption(
              id: '${c['id']}',
              label: '${c['displayName'] ?? c['providerKey']} (${c['capability'] ?? ''})',
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.hub_outlined,
              title: 'Provider Integrations',
              subtitle:
                  'Tenant-scoped adapters, secret references, outbound retries, and verified webhooks.',
            ),
            const SizedBox(height: 14),
            SaasKpiGrid(
              items: [
                (label: 'CONNECTIONS', value: '${conns.length}'),
                (label: 'ACTIVE', value: '$activeCount'),
                (label: 'PENDING OPERATIONS', value: '$pendingOps'),
                (label: 'VERIFIED WEBHOOKS', value: '${hooks.length}'),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasField(
              label: 'Audit reason',
              controller: _auditReason,
              hint: 'Reason required for state changes and outbound commands',
            ),
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Register provider connection',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SaasDropdown(
                          label: 'Capability',
                          value: _capability,
                          options: const {
                            'PAYMENT': 'PAYMENT',
                            'GST': 'GST',
                            'MESSAGING': 'MESSAGING',
                            'EXPORT': 'EXPORT',
                          },
                          onChanged: (v) => setState(() => _capability = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Provider key',
                          controller: _providerKey,
                          hint: 'RAZORPAY_PROD',
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Display name',
                          controller: _displayName,
                          hint: 'Production payment gateway',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasDropdown(
                          label: 'Scope',
                          value: _scope,
                          options: const {
                            'LEGAL_ENTITY': 'Entire legal entity',
                            'BRANCH': 'Current branch',
                          },
                          onChanged: (v) => setState(() => _scope = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'HTTPS endpoint (optional)',
                    controller: _endpoint,
                    hint: 'https://provider.example/api/',
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Credential secret ref',
                          controller: _credentialRef,
                          hint: 'env:PAYMENT_API_KEY',
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Webhook secret ref',
                          controller: _webhookRef,
                          hint: 'env:PAYMENT_WEBHOOK_SECRET',
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Adapter configuration JSON',
                    controller: _adapterJson,
                    mono: true,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _saveConnection,
                      child: const Text('Save draft connection'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Prepare outbound operation',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Active connection',
                    controller: _activeConnId,
                    options: connOpts,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Operation type',
                          controller: _operationType,
                          hint: 'PAYMENT_CREATE',
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Aggregate type',
                          controller: _aggregateType,
                          hint: 'settlement_document',
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: SaasField(
                          label: 'Aggregate UUID',
                          controller: _aggregateUuid,
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Aggregate version',
                          controller: _aggregateVersion,
                          mono: true,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Immutable payload JSON',
                    controller: _payloadJson,
                    mono: true,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _queueOperation,
                      icon: const Icon(Icons.send_rounded, size: 15),
                      label: const Text('Queue operation'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (conns.isEmpty)
              const SaasEmptyBox('No provider connections registered yet.')
            else
              for (final c in conns)
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
                                '${c['displayName'] ?? c['providerKey']} · ${c['capability']}',
                                style: T.body(14, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${c['state'] ?? 'DRAFT'}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        KVRow('Provider Key / Scope', '${c['providerKey']} · ${c['scope']}'),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. GST REGISTRATION & TRANSPORT (`/gst-compliance`) — Screenshots (693-694)
// ---------------------------------------------------------------------------

class GstRegistrationTransportScreen extends StatefulWidget {
  const GstRegistrationTransportScreen({super.key, this.submissionsFocus = false});
  final bool submissionsFocus;
  @override
  State<GstRegistrationTransportScreen> createState() =>
      _GstRegistrationTransportScreenState();
}

class _GstRegistrationTransportScreenState
    extends State<GstRegistrationTransportScreen> {
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _auditReason = TextEditingController();

  // Effective GST profile (Screenshots 693 & 694)
  final _sellerGstin = TextEditingController();
  final _legalName = TextEditingController();
  final _tradeName = TextEditingController();
  final _addr1 = TextEditingController();
  final _addr2 = TextEditingController();
  final _city = TextEditingController();
  final _stateCode = TextEditingController();
  final _pinCode = TextEditingController();
  final _ewayThreshold = TextEditingController();
  final _reportingWindowDays = TextEditingController();
  final _stockHoldMinutes = TextEditingController(text: '120');
  final _effectiveFrom = TextEditingController(text: todayIso());
  final _effectiveUntil = TextEditingController();
  bool _enableEinvoice = false;
  bool _requireIrnForRegistered = false;
  bool _enableThresholdEway = false;

  // Prepare provider submission (Screenshot 693 right card)
  String _docKind = 'EINVOICE_IRN';
  final _invoiceId = TextEditingController();
  final _taxConnId = TextEditingController();
  final _openPeriodId = TextEditingController();
  final _invSeriesId = TextEditingController();
  final _placeOfSupply = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _auditReason, _sellerGstin, _legalName, _tradeName, _addr1, _addr2,
      _city, _stateCode, _pinCode, _ewayThreshold, _reportingWindowDays,
      _stockHoldMinutes, _effectiveFrom, _effectiveUntil, _invoiceId,
      _taxConnId, _openPeriodId, _invSeriesId, _placeOfSupply,
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
        api.get('/gst-compliance'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeAccounting: true,
          includeSales: true,
          includeIntegrations: true,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _ws = asMap(res[0]);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveGstProfile() async {
    if (_sellerGstin.text.trim().length != 15 ||
        _legalName.text.trim().isEmpty ||
        _stateCode.text.trim().length != 2) {
      setState(() => _error = 'Enter 15-char Seller GSTIN, Registered legal name, and 2-digit GST state code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/gst-compliance/profiles',
        idempotent: true,
        body: {
          'sellerGstin': _sellerGstin.text.trim().toUpperCase(),
          'registeredLegalName': _legalName.text.trim(),
          if (_tradeName.text.trim().isNotEmpty) 'tradeName': _tradeName.text.trim(),
          'addressLine1': _addr1.text.trim(),
          if (_addr2.text.trim().isNotEmpty) 'addressLine2': _addr2.text.trim(),
          'city': _city.text.trim(),
          'stateCode': _stateCode.text.trim(),
          'postalCode': _pinCode.text.trim(),
          if (_ewayThreshold.text.trim().isNotEmpty)
            'ewayBillThresholdAmount': _ewayThreshold.text.trim(),
          if (_reportingWindowDays.text.trim().isNotEmpty)
            'reportingWindowDays': int.tryParse(_reportingWindowDays.text.trim()) ?? 3,
          'stockHoldMinutes': int.tryParse(_stockHoldMinutes.text.trim()) ?? 120,
          'effectiveFrom': _effectiveFrom.text.trim(),
          if (_effectiveUntil.text.trim().isNotEmpty)
            'effectiveTo': _effectiveUntil.text.trim(),
          'enableEinvoiceRegistration': _enableEinvoice,
          'requireIrnForRegisteredCustomers': _requireIrnForRegistered,
          'enableThresholdEwayBillControl': _enableThresholdEway,
          if (_auditReason.text.trim().isNotEmpty) 'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft GST profile saved.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareSubmission() async {
    if (_invoiceId.text.trim().isEmpty || _taxConnId.text.trim().isEmpty) {
      setState(() => _error = 'Select Invoice and Tax provider connection.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/gst-compliance/submissions',
        idempotent: true,
        body: {
          'documentKind': _docKind,
          'salesInvoiceId': _invoiceId.text.trim(),
          'providerConnectionId': _taxConnId.text.trim(),
          if (_openPeriodId.text.trim().isNotEmpty)
            'postingPeriodId': _openPeriodId.text.trim(),
          if (_invSeriesId.text.trim().isNotEmpty)
            'documentSeriesId': _invSeriesId.text.trim(),
          if (_placeOfSupply.text.trim().isNotEmpty)
            'placeOfSupplyStateCode': _placeOfSupply.text.trim(),
          if (_auditReason.text.trim().isNotEmpty) 'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GST provider submission prepared & queued.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profiles = asList(_ws['profiles'] ?? _ws['gstProfiles']);
    final submissions = asList(_ws['submissions'] ?? _ws['gstSubmissions']);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.submissionsFocus ? 'GST E-Invoices & Bills' : 'GST Registration & Transport'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.verified_user_outlined,
              title: widget.submissionsFocus
                  ? 'GST E-Invoices & E-Way Bills'
                  : 'GST Registration & Transport',
              subtitle:
                  'Prepare registered-customer invoices, review provider evidence and track registration before posting or dispatch.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasField(
              label: 'Audit reason (required for commands)',
              controller: _auditReason,
            ),
            const SizedBox(height: 14),

            if (!widget.submissionsFocus) ...[
              SaasFormCard(
                title: 'Effective GST profile',
                subtitle:
                    'Enter accountant-approved applicability and reporting rules for this legal entity.',
                icon: Icons.shield_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SaasField(label: 'Seller GSTIN', controller: _sellerGstin, mono: true),
                    const SizedBox(height: 10),
                    SaasField(label: 'Registered legal name', controller: _legalName),
                    const SizedBox(height: 10),
                    SaasField(label: 'Trade name', controller: _tradeName),
                    const SizedBox(height: 10),
                    SaasField(label: 'Address line 1', controller: _addr1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: SaasField(label: 'Address line 2', controller: _addr2)),
                        const SizedBox(width: 10),
                        Expanded(child: SaasField(label: 'City / location', controller: _city)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: SaasField(label: 'GST state code', controller: _stateCode, mono: true)),
                        const SizedBox(width: 10),
                        Expanded(child: SaasField(label: 'PIN code', controller: _pinCode, mono: true)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Approved e-way bill threshold (INR)',
                            controller: _ewayThreshold,
                            mono: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Approved reporting window (days)',
                            controller: _reportingWindowDays,
                            mono: true,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Stock hold (minutes)',
                      controller: _stockHoldMinutes,
                      mono: true,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: DatePickField(label: 'Effective from', controller: _effectiveFrom)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DatePickField(
                            label: 'Effective until (optional)',
                            controller: _effectiveUntil,
                            optional: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasCheckRow(
                      label: 'Enable e-invoice registration',
                      value: _enableEinvoice,
                      onChanged: (v) => setState(() => _enableEinvoice = v),
                    ),
                    SaasCheckRow(
                      label: 'Require IRN for registered customers',
                      value: _requireIrnForRegistered,
                      onChanged: (v) => setState(() => _requireIrnForRegistered = v),
                    ),
                    SaasCheckRow(
                      label: 'Enable threshold-based e-way bill control',
                      value: _enableThresholdEway,
                      onChanged: (v) => setState(() => _enableThresholdEway = v),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _saveGstProfile,
                        child: const Text('Save draft profile'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            SaasFormCard(
              title: 'Prepare provider submission',
              icon: Icons.local_shipping_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasDropdown(
                    label: 'Document kind',
                    value: _docKind,
                    options: const {
                      'EINVOICE_IRN': 'E-invoice / IRN',
                      'EWAY_BILL': 'E-way bill',
                    },
                    onChanged: (v) => setState(() => _docKind = v),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Invoice',
                    controller: _invoiceId,
                    options: _lk.invoices,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Tax provider connection',
                    controller: _taxConnId,
                    options: _lk.connections,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: LookupField(
                          label: 'Open posting period',
                          controller: _openPeriodId,
                          options: _lk.openPeriods(),
                          hint: 'Select...',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: LookupField(
                          label: 'Invoice series',
                          controller: _invSeriesId,
                          options: _lk.seriesFor(const ['INVOICE', 'SALES']),
                          hint: 'Select...',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Place of supply (GST state code)',
                    controller: _placeOfSupply,
                    mono: true,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _prepareSubmission,
                      child: const Text('Prepare & queue'),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            Text('GST profiles', style: T.body(14.5, w: FontWeight.w800)),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (profiles.isEmpty)
              const SaasEmptyBox('No GST profile configured.')
            else
              for (final p in profiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('${p['sellerGstin']} · ${p['registeredLegalName'] ?? ''}', style: T.mono(13, w: FontWeight.w700)),
                            ),
                            StatusChip('${p['state'] ?? 'DRAFT'}'),
                          ],
                        ),
                        const SizedBox(height: 4),
                        KVRow('State / PIN', '${p['stateCode'] ?? ''} · ${p['postalCode'] ?? ''}'),
                      ],
                    ),
                  ),
                ),

            const SizedBox(height: 16),
            Text('Registration, cancellation & recovery', style: T.body(14.5, w: FontWeight.w800)),
            const SizedBox(height: 8),
            if (submissions.isEmpty)
              const SaasEmptyBox('No GST submission prepared.')
            else
              for (final s in submissions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('${s['documentKind'] ?? 'EINVOICE'} · ${s['irn'] ?? shortId('${s['id']}')}', style: T.mono(12.8, w: FontWeight.w700)),
                            ),
                            StatusChip('${s['state'] ?? 'QUEUED'}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. GST RETURNS & ITC REVIEW (`/gst-returns`) — Screenshots (695-696)
// ---------------------------------------------------------------------------

class GstReturnsItcScreen extends StatefulWidget {
  const GstReturnsItcScreen({super.key});
  @override
  State<GstReturnsItcScreen> createState() => _GstReturnsItcScreenState();
}

class _GstReturnsItcScreenState extends State<GstReturnsItcScreen> {
  final _returnMonth = TextEditingController(text: todayIso().substring(0, 7));
  Map<String, dynamic> _ws = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _commandReason = TextEditingController();
  final _itcEvidence = TextEditingController();

  // 1. Import & reconcile GSTR-2B (Screenshot 695-696)
  final _gstr2bJson = TextEditingController();
  final _importedStmtId = TextEditingController();

  // 2. Prepare GSTR working papers (Screenshot 695-696)
  final _approvedReconId = TextEditingController();
  final _b2clThreshold = TextEditingController();
  final _mappingsJson = TextEditingController();

  // Working papers & approvals
  final _selectedRecordId = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _returnMonth, _commandReason, _itcEvidence, _gstr2bJson,
      _importedStmtId, _approvedReconId, _b2clThreshold,
      _mappingsJson, _selectedRecordId,
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
      final d = await context.read<ApiClient>().get('/gst-returns', query: {
        'returnMonth': _returnMonth.text.trim(),
        'period': _returnMonth.text.trim(),
      });
      if (!mounted) return;
      setState(() => _ws = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _createMappingTemplate() {
    setState(() {
      _mappingsJson.text = const JsonEncoder.withIndent('  ').convert({
        'schema': 'GST_RETURN_MAPPING_V1',
        'hsnOverrides': [],
        'placeOfSupplyOverrides': [],
        'itcReversals': [],
      });
    });
  }

  Future<void> _runGstMutation(Future<void> Function(ApiClient api) fn, String msg) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await fn(context.read<ApiClient>());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stmts = asList(_ws['importedStatements'] ?? _ws['gstr2bStatements']);
    final recons = asList(_ws['reconciliations'] ?? _ws['itcReconciliations']);
    final papers = asList(_ws['workingPapers'] ?? _ws['revisions']);
    final exports = asList(_ws['exports'] ?? _ws['exportHistory']);

    final stmtOpts = stmts
        .map((s) => LookupOption(id: '${s['id']}', label: '${s['returnMonth'] ?? ''} · ${shortId('${s['id']}')}', raw: s))
        .toList();
    final reconOpts = recons
        .map((r) => LookupOption(id: '${r['id']}', label: '${r['state'] ?? ''} · ${shortId('${r['id']}')}', raw: r))
        .toList();
    final paperOpts = papers
        .map((p) => LookupOption(id: '${p['id']}', label: 'Rev ${p['revisionNumber'] ?? 1} · ${p['state'] ?? ''}', raw: p))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('GST Returns & ITC Review'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.description_outlined,
              title: 'GST Returns & ITC Review',
              subtitle:
                  'Entity-wide GSTR-1 and GSTR-3B working papers, authorized GSTR-2B imports, and evidence-backed eligibility review.',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SaasField(
                    label: 'Return month (YYYY-MM)',
                    controller: _returnMonth,
                    mono: true,
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: OutlinedButton(onPressed: _load, child: const Text('Load month')),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SaasKpiGrid(
              items: [
                (label: 'POSTED OUTWARD LINES', value: '${_ws['postedOutwardLines'] ?? 0}'),
                (label: 'PURCHASE BOOKS', value: '${_ws['purchaseBookLines'] ?? _ws['purchaseBooks'] ?? 0}'),
                (label: 'WORKING-PAPER REVISIONS', value: '${papers.length}'),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasField(label: 'Command reason', controller: _commandReason),
            const SizedBox(height: 10),
            SaasField(label: 'ITC review evidence / reference', controller: _itcEvidence),

            // 1. Import & reconcile GSTR-2B
            const SizedBox(height: 14),
            SaasFormCard(
              title: '1. Import & reconcile GSTR-2B',
              subtitle:
                  'Use authorized records normalized to NORMALIZED_GSTR2B_V1. The source JSON format and field definitions are in the return runbook.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasField(
                    label: 'Normalized GSTR-2B records',
                    controller: _gstr2bJson,
                    mono: true,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () => _runGstMutation(
                                (api) => api.post('/gst-returns/gstr2b/import', idempotent: true, body: {
                                  'returnMonth': _returnMonth.text.trim(),
                                  'reason': _commandReason.text.trim(),
                                  'records': jsonDecode(_gstr2bJson.text.trim().isEmpty ? '[]' : _gstr2bJson.text.trim()),
                                }),
                                'GSTR-2B records imported.',
                              ),
                      child: const Text('Import records'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LookupField(
                    label: 'Imported statement',
                    controller: _importedStmtId,
                    options: stmtOpts,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _runGstMutation(
                                (api) => api.post('/gst-returns/reconciliations', idempotent: true, body: {
                                  'returnMonth': _returnMonth.text.trim(),
                                  'importedStatementId': _importedStmtId.text.trim(),
                                  'reason': _commandReason.text.trim(),
                                  if (_itcEvidence.text.trim().isNotEmpty)
                                    'evidence': _itcEvidence.text.trim(),
                                }),
                                'ITC reconciliation built.',
                              ),
                      icon: const Icon(Icons.sync_rounded, size: 15),
                      label: const Text('Build reconciliation'),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Prepare GSTR working papers
            const SizedBox(height: 14),
            SaasFormCard(
              title: '2. Prepare GSTR working papers',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Approved ITC reconciliation',
                    controller: _approvedReconId,
                    options: reconOpts,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Accountant-approved B2CL threshold (INR)',
                    controller: _b2clThreshold,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _createMappingTemplate,
                      child: const Text('Create mapping template from posted sources'),
                    ),
                  ),
                  SaasField(
                    label: 'Reviewed HSN, place-of-supply, tax heads and reversal mappings',
                    controller: _mappingsJson,
                    mono: true,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy
                          ? null
                          : () => _runGstMutation(
                                (api) => api.post('/gst-returns/working-papers', idempotent: true, body: {
                                  'returnMonth': _returnMonth.text.trim(),
                                  if (_approvedReconId.text.trim().isNotEmpty)
                                    'reconciliationId': _approvedReconId.text.trim(),
                                  if (_b2clThreshold.text.trim().isNotEmpty)
                                    'b2clThresholdAmount': _b2clThreshold.text.trim(),
                                  'mappings': jsonDecode(_mappingsJson.text.trim().isEmpty ? '{}' : _mappingsJson.text.trim()),
                                  'reason': _commandReason.text.trim(),
                                }),
                                'Working-paper revision prepared.',
                              ),
                      child: const Text('Prepare revision'),
                    ),
                  ),
                ],
              ),
            ),

            // Working papers & approvals (Screenshot 696)
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Working papers & approvals',
              child: LookupField(
                label: 'Select record',
                controller: _selectedRecordId,
                options: paperOpts,
                hint: 'Select...',
              ),
            ),

            // Export history (Screenshot 696)
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Export history',
              subtitle:
                  'Downloads contain approved preparation snapshots. They do not represent GST filing acknowledgements.',
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : exports.isEmpty
                      ? Text('No approved export created.', style: T.body(13, color: Pal.muted))
                      : Column(
                          children: [
                            for (final ex in exports)
                              KVRow('${ex['returnType'] ?? 'GSTR'} · ${fmtDate('${ex['createdAt'] ?? ''}')}', '${ex['state'] ?? 'READY'}'),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. CUSTOMER MESSAGING (`/messaging`)
// ---------------------------------------------------------------------------

class CustomerMessagingScreen extends StatefulWidget {
  const CustomerMessagingScreen({super.key});
  @override
  State<CustomerMessagingScreen> createState() => _CustomerMessagingScreenState();
}

class _CustomerMessagingScreenState extends State<CustomerMessagingScreen> {
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _partyId = TextEditingController();
  String _channel = 'WHATSAPP';
  final _templateKey = TextEditingController();
  final _purpose = TextEditingController(text: 'TRANSACTIONAL_NOTICES');
  final _bodyPreview = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_partyId, _templateKey, _purpose, _bodyPreview]) {
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
        api.get('/messaging'),
        WorkspaceLookup.load(api, includeParties: true),
      ]);
      if (!mounted) return;
      setState(() {
        _ws = asMap(res[0]);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_partyId.text.trim().isEmpty || _templateKey.text.trim().isEmpty) {
      setState(() => _error = 'Select recipient party and template key.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/messaging/dispatches',
        idempotent: true,
        body: {
          'partyId': _partyId.text.trim(),
          'channel': _channel,
          'templateKey': _templateKey.text.trim().toUpperCase(),
          'purpose': _purpose.text.trim().toUpperCase(),
          if (_bodyPreview.text.trim().isNotEmpty) 'message': _bodyPreview.text.trim(),
        },
      );
      if (!mounted) return;
      _bodyPreview.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consent-verified message queued.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dispatches = asList(_ws['dispatches'] ?? _ws['messages'] ?? _ws['items']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Messaging'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Customer Messaging & Notifications',
              subtitle:
                  'Consent-verified WhatsApp, SMS, and Email dispatch for invoices, repair ready alerts, and custom order updates.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Queue transactional notification',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(
                    label: 'Recipient party',
                    controller: _partyId,
                    options: _lk.parties,
                    hint: 'Select...',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasDropdown(
                          label: 'Channel',
                          value: _channel,
                          options: const {
                            'WHATSAPP': 'WHATSAPP',
                            'SMS': 'SMS',
                            'EMAIL': 'EMAIL',
                          },
                          onChanged: (v) => setState(() => _channel = v),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'Purpose',
                          controller: _purpose,
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Template key',
                    controller: _templateKey,
                    hint: 'INVOICE_ISSUED',
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Message parameters / note (optional)',
                    controller: _bodyPreview,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _send,
                      child: const Text('Queue notification'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (dispatches.isEmpty)
              const SaasEmptyBox('No customer notifications dispatched yet.')
            else
              for (final m in dispatches)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('${m['channel']} · ${m['templateKey'] ?? ''}', style: T.body(13.8, w: FontWeight.w700)),
                            ),
                            StatusChip('${m['state'] ?? 'QUEUED'}'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. COMPANY & INVOICE PRINT (`/documents/templates` & `/documents/render`)
// ---------------------------------------------------------------------------

class CompanyInvoicePolicyScreen extends StatefulWidget {
  const CompanyInvoicePolicyScreen({super.key});
  @override
  State<CompanyInvoicePolicyScreen> createState() => _CompanyInvoicePolicyScreenState();
}

class _CompanyInvoicePolicyScreenState extends State<CompanyInvoicePolicyScreen> {
  List<Map<String, dynamic>> _templates = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _showCreate = false;
  Map<String, dynamic>? _renderedPreview;

  // Generate / Preview Document (`DocumentsPanel.tsx`)
  String _sourceType = 'SALES_INVOICE';
  final _sourceId = TextEditingController();
  final _renderTemplateKey = TextEditingController();

  // Create Document Template (`createDocumentTemplateSchema`)
  final _tmplKey = TextEditingController();
  final _tmplName = TextEditingController();
  String _layoutType = 'A4';
  final _tmplBody = TextEditingController();
  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_sourceId, _renderTemplateKey, _tmplKey, _tmplName, _tmplBody]) {
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
        api.get('/documents/templates'),
        WorkspaceLookup.load(api, includeParties: false, includeSales: true),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = asList(res[0], keys: const ['templates', 'items']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _renderDoc() async {
    if (_sourceId.text.trim().isEmpty) {
      setState(() => _error = 'Provide Document Source UUID.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().post(
        '/documents/render',
        body: {
          'sourceType': _sourceType,
          'sourceId': _sourceId.text.trim(),
          if (_renderTemplateKey.text.trim().isNotEmpty)
            'templateKey': _renderTemplateKey.text.trim().toUpperCase(),
        },
      );
      if (!mounted) return;
      setState(() => _renderedPreview = asMap(res));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTemplate() async {
    if (_tmplKey.text.trim().length < 3 ||
        _tmplName.text.trim().length < 3 ||
        _tmplBody.text.trim().length < 10) {
      setState(() => _error = 'Enter Template Key (3+ chars), Name, and HTML Template Body (10+ chars).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/documents/templates',
        idempotent: true,
        body: {
          'templateKey': _tmplKey.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9_]'), '_'),
          'name': _tmplName.text.trim(),
          'layoutType': _layoutType,
          'templateBody': _tmplBody.text.trim(),
          'isDefault': _isDefault,
        },
      );
      if (!mounted) return;
      setState(() => _showCreate = false);
      _tmplKey.clear();
      _tmplName.clear();
      _tmplBody.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document template registered.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Company & Invoice Print'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.print_outlined,
              title: 'Document Templates and Print Rendering',
              subtitle:
                  'Immutable document versioning, legal print snapshots, A4 and Thermal roll print layouts.',
              trailing: OutlinedButton.icon(
                onPressed: () => setState(() => _showCreate = !_showCreate),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: Text(_showCreate ? 'Close' : 'New template'),
              ),
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],

            if (_showCreate) ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'Register document template',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Template Key (A4_TAX_INVOICE)',
                            controller: _tmplKey,
                            mono: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasDropdown(
                            label: 'Layout',
                            value: _layoutType,
                            options: const {
                              'A4': 'A4',
                              'THERMAL_ROLL': 'THERMAL_ROLL',
                            },
                            onChanged: (v) => setState(() => _layoutType = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(label: 'Template name', controller: _tmplName),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'HTML template body',
                      controller: _tmplBody,
                      mono: true,
                      maxLines: 5,
                    ),
                    const SizedBox(height: 8),
                    SaasCheckRow(
                      label: 'Set as default layout template',
                      value: _isDefault,
                      onChanged: (v) => setState(() => _isDefault = v),
                    ),
                    const SizedBox(height: 10),
                    GoldButton(
                      label: 'Save template',
                      busy: _busy,
                      onPressed: _createTemplate,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Generate / Preview Document',
              subtitle:
                  'Provide document source UUID to render or reprint an official invoice, return note, or receipt.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasDropdown(
                    label: 'Source type',
                    value: _sourceType,
                    options: const {
                      'SALES_INVOICE': 'Sales Invoice',
                      'CREDIT_NOTE': 'Sales Credit Note',
                      'PURCHASE_RETURN': 'Purchase Return / Debit Note',
                      'SETTLEMENT_RECEIPT': 'Settlement Receipt',
                      'PARTY_STATEMENT': 'Party Statement',
                    },
                    onChanged: (v) => setState(() => _sourceType = v),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Document Source UUID',
                    controller: _sourceId,
                    options: _sourceType == 'SALES_INVOICE' ? _lk.invoices : const [],
                    hint: 'Document Source UUID (e.g. Sales Invoice ID)',
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Template key (optional)',
                    controller: _renderTemplateKey,
                    mono: true,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _renderDoc,
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: Text(_busy ? 'Rendering…' : 'Render Document'),
                    ),
                  ),
                  if (_renderedPreview != null) ...[
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Document Preview · ${_renderedPreview!['documentNumber'] ?? ''}',
                            style: T.body(13.8, w: FontWeight.w700),
                          ),
                          Text(
                            'Reprint Count: ${_renderedPreview!['reprintCount'] ?? 0} · Hash: ${shortId('${_renderedPreview!['contentHash'] ?? ''}')}',
                            style: T.mono(11.5, color: Pal.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_templates.isEmpty)
              const SaasEmptyBox('No document templates registered yet.')
            else
              for (final t in _templates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text('${t['templateKey']} · ${t['name']}', style: T.body(14, w: FontWeight.w700)),
                            ),
                            StatusChip('${t['state'] ?? 'ACTIVE'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Layout / Version', '${t['layout'] ?? t['layoutType'] ?? 'A4'} · v${t['version'] ?? 1}'),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. SHOWROOM HIERARCHY (`/organization`)
// ---------------------------------------------------------------------------

class ShowroomHierarchyScreen extends StatefulWidget {
  const ShowroomHierarchyScreen({super.key});
  @override
  State<ShowroomHierarchyScreen> createState() => _ShowroomHierarchyScreenState();
}

class _ShowroomHierarchyScreenState extends State<ShowroomHierarchyScreen> {
  List<Map<String, dynamic>> _entities = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _legalName = TextEditingController();
  final _currency = TextEditingController(text: 'INR');
  final _timezone = TextEditingController(text: 'Asia/Kolkata');

  final _branchEntityId = TextEditingController();
  final _branchCode = TextEditingController();
  final _branchName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_legalName, _currency, _timezone, _branchEntityId, _branchCode, _branchName]) {
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
      final d = await context.read<ApiClient>().get('/organization');
      if (!mounted) return;
      final list = asList(d, keys: const ['legalEntities', 'entities', 'items']);
      if (_branchEntityId.text.isEmpty && list.isNotEmpty) {
        _branchEntityId.text = '${list.first['id'] ?? ''}';
      }
      setState(() => _entities = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createEntity() async {
    if (_legalName.text.trim().length < 2) {
      setState(() => _error = 'Enter Legal entity name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/organization/legal-entities', body: {
        'legalName': _legalName.text.trim(),
        'functionalCurrency': _currency.text.trim().toUpperCase(),
        'timezone': _timezone.text.trim(),
      });
      if (!mounted) return;
      _legalName.clear();
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBranch() async {
    if (_branchEntityId.text.trim().isEmpty ||
        _branchCode.text.trim().isEmpty ||
        _branchName.text.trim().length < 2) {
      setState(() => _error = 'Select Legal entity and enter Branch code & name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/organization/branches', body: {
        'legalEntityId': _branchEntityId.text.trim(),
        'code': _branchCode.text.trim().toUpperCase(),
        'name': _branchName.text.trim(),
      });
      if (!mounted) return;
      _branchCode.clear();
      _branchName.clear();
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final entOpts = _entities
        .map((e) => LookupOption(id: '${e['id']}', label: '${e['legalName'] ?? e['name']}', raw: e))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Showroom Hierarchy'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.apartment_rounded,
              title: 'Showroom Hierarchy & Legal Entities',
              subtitle:
                  'Multi-entity and multi-branch showroom structure with isolated GST, document numbering, and vault custody.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'New legal entity',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasField(label: 'Legal name', controller: _legalName),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: SaasField(label: 'Currency', controller: _currency, mono: true)),
                      const SizedBox(width: 10),
                      Expanded(child: SaasField(label: 'Timezone', controller: _timezone, mono: true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _createEntity,
                      child: const Text('Create legal entity'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SaasFormCard(
              title: 'New showroom branch',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LookupField(label: 'Legal entity', controller: _branchEntityId, options: entOpts),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: SaasField(label: 'Branch code (HQ)', controller: _branchCode, mono: true)),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: SaasField(label: 'Showroom name', controller: _branchName)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _createBranch,
                      child: const Text('Create branch'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              for (final e in _entities)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SaasFormCard(
                    title: '${e['legalName'] ?? e['name']}',
                    subtitle: '${e['functionalCurrency'] ?? 'INR'} · ${e['timezone'] ?? 'Asia/Kolkata'}',
                    child: Column(
                      children: [
                        for (final b in asList(e['branches']))
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text('${b['code']} · ${b['name']}', style: T.body(13.5, w: FontWeight.w700)),
                            trailing: app.session?.selectedContext?.branchId == '${b['id']}'
                                ? const StatusChip('ACTIVE')
                                : OutlinedButton(
                                    onPressed: () {
                                      final tId = app.session?.selectedContext?.tenantId ?? '';
                                      if (tId.isNotEmpty) {
                                        app.selectContext(
                                          tenantId: tId,
                                          legalEntityId: '${e['id']}',
                                          branchId: '${b['id']}',
                                        );
                                      }
                                    },
                                    child: const Text('Activate'),
                                  ),
                          ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. ACCESS CONTROL & ROLES (`/access`) — AccessPanel.tsx + contracts
// ---------------------------------------------------------------------------

class AccessControlScreen extends StatefulWidget {
  const AccessControlScreen({super.key});
  @override
  State<AccessControlScreen> createState() => _AccessControlScreenState();
}

class _AccessControlScreenState extends State<AccessControlScreen> {
  Map<String, dynamic> _access = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _showRoleForm = false;

  final _roleKey = TextEditingController();
  final _roleName = TextEditingController();
  final Set<String> _selectedPerms = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _roleKey.dispose();
    _roleName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/access');
      if (!mounted) return;
      setState(() => _access = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createRole() async {
    // Zod `createRoleRequestSchema`: lowercase kebab-case `^[a-z][a-z0-9-]*$`
    final sanitizedKey = _roleKey.text
        .trim()
        .toLowerCase()
        .replaceAll('_', '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '');
    if (sanitizedKey.length < 2 || _roleName.text.trim().length < 2 || _selectedPerms.isEmpty) {
      setState(() => _error = 'Enter lowercase role key (e.g. showroom-manager), role name, and at least 1 permission.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post('/access/roles', body: {
        'key': sanitizedKey,
        'name': _roleName.text.trim(),
        'permissionKeys': _selectedPerms.toList()..sort(),
      });
      if (!mounted) return;
      _roleKey.clear();
      _roleName.clear();
      setState(() {
        _selectedPerms.clear();
        _showRoleForm = false;
      });
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = asList(_access['permissions']);
    final roles = asList(_access['roles']);
    final memberships = asList(_access['memberships']);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Access Control & Roles'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            SaasModuleHeader(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Access and roles',
              subtitle: 'Tenant-scoped roles, permissions and member assignments.',
              trailing: OutlinedButton.icon(
                onPressed: () => setState(() => _showRoleForm = !_showRoleForm),
                icon: const Icon(Icons.add_rounded, size: 15),
                label: Text(_showRoleForm ? 'Close' : 'New role'),
              ),
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],

            if (_showRoleForm) ...[
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'Create tenant role',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Role key (kebab-case)',
                            controller: _roleKey,
                            hint: 'vault-supervisor',
                            mono: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(label: 'Role name', controller: _roleName),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const FieldLabel('Permissions'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in perms)
                          FilterChip(
                            label: Text('${p['key']}', style: T.mono(11)),
                            selected: _selectedPerms.contains('${p['key']}'),
                            onSelected: (sel) => setState(() {
                              final k = '${p['key']}';
                              if (sel) {
                                _selectedPerms.add(k);
                              } else {
                                _selectedPerms.remove(k);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GoldButton(
                      label: 'Create role',
                      busy: _busy,
                      onPressed: _createRole,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Roles (${roles.length})',
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : roles.isEmpty
                      ? const SaasEmptyBox('No roles configured yet.')
                      : Column(
                          children: [
                            for (final r in roles)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: SaasSubBox(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${r['name']} (${r['key']})', style: T.body(13.8, w: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${asList(r['permissionKeys']).length} permissions',
                                        style: T.body(11.8, color: Pal.muted),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
            ),

            const SizedBox(height: 14),
            SaasFormCard(
              title: 'Memberships (${memberships.length})',
              child: memberships.isEmpty
                  ? const SaasEmptyBox('No tenant memberships found.')
                  : Column(
                      children: [
                        for (final m in memberships)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SaasSubBox(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${asMap(m['user'])['displayName'] ?? ''}',
                                          style: T.body(13.5, w: FontWeight.w700),
                                        ),
                                        Text(
                                          '${asMap(m['user'])['email'] ?? ''} · v${m['permissionVersion'] ?? 1}',
                                          style: T.body(11.8, color: Pal.muted),
                                        ),
                                      ],
                                    ),
                                  ),
                                  StatusChip('${m['state'] ?? 'ACTIVE'}'),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. AUDIT & COMPLIANCE (`/support-grants`) — TenantSupportPanel.tsx + contracts
// ---------------------------------------------------------------------------

class AuditComplianceScreen extends StatefulWidget {
  const AuditComplianceScreen({super.key});
  @override
  State<AuditComplianceScreen> createState() => _AuditComplianceScreenState();
}

class _AuditComplianceScreenState extends State<AuditComplianceScreen> {
  List<Map<String, dynamic>> _grants = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _decisionReason = TextEditingController(
    text: 'Reviewed tenant support request scope and duration.',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _decisionReason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/support-grants');
      if (!mounted) return;
      setState(() => _grants = asList(d, keys: const ['grants', 'supportGrants', 'items']));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> grant, String decision) async {
    if (_decisionReason.text.trim().length < 10) {
      setState(() => _error = 'Decision reason must be at least 10 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Zod `supportGrantDecisionSchema`: `{ expectedVersion, decisionReason }`
      await context.read<ApiClient>().post(
        '/support-grants/${grant['id']}/$decision',
        body: {
          'expectedVersion': asInt(grant['version'], fallback: 1),
          'decisionReason': _decisionReason.text.trim(),
        },
      );
      if (!mounted) return;
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit & Compliance'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            const SaasModuleHeader(
              icon: Icons.policy_outlined,
              title: 'Support Governance & Audit Controls',
              subtitle:
                  'Time-boxed support access grants, explicit tenant approval/revocation, and immutable audit reason enforcement.',
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            const SizedBox(height: 14),
            SaasField(
              label: 'Decision reason (minimum 10 characters)',
              controller: _decisionReason,
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_grants.isEmpty)
              const SaasEmptyBox('No platform support access grants requested.')
            else
              for (final g in _grants)
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
                                '${asMap(asMap(g['operator'])['user'])['displayName'] ?? 'Platform Support'} · ${g['mode']}',
                                style: T.body(14, w: FontWeight.w700),
                              ),
                            ),
                            StatusChip('${g['state'] ?? 'REQUESTED'}'),
                          ],
                        ),
                        const SizedBox(height: 6),
                        KVRow('Reason', '${g['reason'] ?? ''}'),
                        KVRow('Expires At', fmtDateTime('${g['expiresAt'] ?? ''}')),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            if ('${g['state']}' == 'REQUESTED') ...[
                              ElevatedButton(
                                onPressed: _busy ? null : () => _decide(g, 'approve'),
                                child: const Text('Approve'),
                              ),
                              OutlinedButton(
                                onPressed: _busy ? null : () => _decide(g, 'reject'),
                                child: const Text('Reject'),
                              ),
                            ],
                            if ('${g['state']}' == 'APPROVED')
                              OutlinedButton(
                                onPressed: _busy ? null : () => _decide(g, 'revoke'),
                                child: const Text('Revoke'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

typedef DocumentsPolicyScreen = CompanyInvoicePolicyScreen;
