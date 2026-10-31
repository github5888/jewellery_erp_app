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
  final _search = TextEditingController();
  String _tab = 'CONNECTIONS';
  bool _showForm = false;
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
      _search, _auditReason, _providerKey, _displayName, _endpoint, _credentialRef,
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

    final q = _search.text.trim().toLowerCase();
    final fConns = conns.where((c) {
      if (q.isEmpty) return true;
      return '${c['displayName'] ?? ''} ${c['providerKey'] ?? ''} ${c['capability'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fOps = ops.where((o) {
      if (q.isEmpty) return true;
      return '${o['operationType'] ?? ''} ${o['aggregateType'] ?? ''} ${o['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fHooks = hooks.where((h) {
      if (q.isEmpty) return true;
      return '${h['eventType'] ?? ''} ${h['providerKey'] ?? ''} ${h['id'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Provider Integrations',
      icon: Icons.cloud_sync_outlined,
      searchController: _search,
      searchHint: 'Search by Provider, Capability or Event...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _showForm = false;
        }),
        tabs: [
          ('CONNECTIONS', 'Connections (${conns.length})'),
          ('OPERATIONS', 'Operations (${ops.length})'),
          ('WEBHOOKS', 'Webhooks (${hooks.length})'),
        ],
      ),
      floatingActionButton: _tab == 'WEBHOOKS'
          ? null
          : GoldAddFab(
              icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
              tooltip: _tab == 'CONNECTIONS' ? 'New Provider Connection' : 'Queue Outbound Operation',
              onPressed: () => setState(() => _showForm = !_showForm),
            ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            SaasKpiGrid(
              items: [
                (label: 'CONNECTIONS', value: '${conns.length}'),
                (label: 'ACTIVE', value: '$activeCount'),
                (label: 'PENDING OPERATIONS', value: '$pendingOps'),
                (label: 'VERIFIED WEBHOOKS', value: '${hooks.length}'),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],
            if (_showForm) ...[
              const SizedBox(height: 12),
              SaasField(
                label: 'Audit reason',
                controller: _auditReason,
                hint: 'Reason required for state changes and outbound commands',
              ),
              const SizedBox(height: 12),
              if (_tab == 'CONNECTIONS')
                SaasFormCard(
                  title: 'Register provider connection',
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Save Draft Connection',
                        busy: _busy,
                        onPressed: _saveConnection,
                      ),
                    ],
                  ),
                )
              else
                SaasFormCard(
                  title: 'Prepare outbound operation',
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Queue Operation',
                        icon: Icons.send_rounded,
                        busy: _busy,
                        onPressed: _queueOperation,
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_tab == 'CONNECTIONS') ...[
              if (fConns.isEmpty)
                const SaasEmptyBox('No provider connections registered yet.')
              else
                for (final c in fConns)
                  LuxuryRecordCard(
                    icon: Icons.cloud_sync_outlined,
                    code: '${c['displayName'] ?? c['providerKey']}',
                    status: '${c['state'] ?? 'DRAFT'}',
                    lines: [
                      ('Provider Key', '${c['providerKey'] ?? ''}'),
                      ('Scope', '${c['scope'] ?? ''}'),
                    ],
                    amountLabel: 'Capability',
                    amountValue: '${c['capability'] ?? 'ADAPTER'}',
                    actions: [
                      if ('${c['state'] ?? 'DRAFT'}' == 'DRAFT')
                        GoldButton(
                          label: 'Approve',
                          compact: true,
                          busy: _busy,
                          onPressed: () async {
                            setState(() => _busy = true);
                            try {
                              await context.read<ApiClient>().post(
                                '/integrations/connections/${c['id']}/approve',
                                idempotent: true,
                                body: {
                                  'expectedVersion': asInt(c['version'], fallback: 1),
                                  'reason': _auditReason.text.trim().isEmpty
                                      ? 'Approved provider connection configuration.'
                                      : _auditReason.text.trim(),
                                },
                              );
                              if (mounted) _load();
                            } on ApiException catch (e) {
                              if (mounted) setState(() => _error = e.message);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                        ),
                      if ('${c['state'] ?? ''}' == 'APPROVED' || '${c['state'] ?? ''}' == 'DISABLED')
                        GoldButton(
                          label: 'Activate',
                          compact: true,
                          busy: _busy,
                          onPressed: () async {
                            setState(() => _busy = true);
                            try {
                              await context.read<ApiClient>().post(
                                '/integrations/connections/${c['id']}/activate',
                                idempotent: true,
                                body: {
                                  'expectedVersion': asInt(c['version'], fallback: 1),
                                  'reason': _auditReason.text.trim().isEmpty
                                      ? 'Activated provider connection for workspace.'
                                      : _auditReason.text.trim(),
                                },
                              );
                              if (mounted) _load();
                            } on ApiException catch (e) {
                              if (mounted) setState(() => _error = e.message);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                        ),
                      if ('${c['state'] ?? ''}' == 'ACTIVE')
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await context.read<ApiClient>().post(
                                      '/integrations/connections/${c['id']}/disable',
                                      idempotent: true,
                                      body: {
                                        'expectedVersion': asInt(c['version'], fallback: 1),
                                        'reason': _auditReason.text.trim().isEmpty
                                            ? 'Disabled provider connection.'
                                            : _auditReason.text.trim(),
                                      },
                                    );
                                    if (mounted) _load();
                                  } on ApiException catch (e) {
                                    if (mounted) setState(() => _error = e.message);
                                  } finally {
                                    if (mounted) setState(() => _busy = false);
                                  }
                                },
                          child: const Text('Disable'),
                        ),
                    ],
                  ),
            ] else if (_tab == 'OPERATIONS') ...[
              if (fOps.isEmpty)
                const SaasEmptyBox('No outbound operations recorded yet.')
              else
                for (final o in fOps)
                  LuxuryRecordCard(
                    icon: Icons.send_rounded,
                    code: '${o['operationType'] ?? shortId('${o['id']}')}',
                    status: '${o['state'] ?? o['status'] ?? 'PENDING'}',
                    lines: [
                      ('Aggregate', '${o['aggregateType'] ?? ''} · ${shortId('${o['aggregateId'] ?? ''}')}'),
                    ],
                    amountLabel: 'Retries',
                    amountValue: '${o['attemptCount'] ?? 0}',
                    actions: [
                      if ('${o['state'] ?? o['status'] ?? 'PENDING'}' == 'PENDING' ||
                          '${o['state'] ?? o['status'] ?? ''}' == 'QUEUED' ||
                          '${o['state'] ?? o['status'] ?? ''}' == 'FAILED')
                        GoldButton(
                          label: '${o['state'] ?? ''}' == 'FAILED' ? 'Retry' : 'Dispatch',
                          compact: true,
                          busy: _busy,
                          onPressed: () async {
                            setState(() => _busy = true);
                            try {
                              await context.read<ApiClient>().post(
                                '/integrations/operations/${o['id']}/${'${o['state'] ?? ''}' == 'FAILED' ? 'retry' : 'dispatch'}',
                                idempotent: true,
                                body: {
                                  'expectedVersion': asInt(o['version'], fallback: 1),
                                  'reason': _auditReason.text.trim().isEmpty
                                      ? 'Dispatched outbound provider operation.'
                                      : _auditReason.text.trim(),
                                },
                              );
                              if (mounted) _load();
                            } on ApiException catch (e) {
                              if (mounted) setState(() => _error = e.message);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                        ),
                    ],
                  ),
            ] else ...[
              if (fHooks.isEmpty)
                const SaasEmptyBox('No verified inbound provider webhooks received yet.')
              else
                for (final h in fHooks)
                  LuxuryRecordCard(
                    icon: Icons.webhook_rounded,
                    code: '${h['eventType'] ?? shortId('${h['id']}')}',
                    status: 'VERIFIED',
                    lines: [
                      ('Provider', '${h['providerKey'] ?? 'GATEWAY'}'),
                      if ('${h['receivedAt'] ?? ''}'.isNotEmpty) ('Received', fmtDateTime('${h['receivedAt']}')),
                    ],
                    amountLabel: 'Signature',
                    amountValue: 'Verified',
                  ),
            ],
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
  final _search = TextEditingController();
  late String _tab = widget.submissionsFocus ? 'SUBMISSIONS' : 'PROFILES';
  bool _showForm = false;
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
      _search, _auditReason, _sellerGstin, _legalName, _tradeName, _addr1, _addr2,
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

    final q = _search.text.trim().toLowerCase();
    final fSubs = submissions.where((s) {
      if (q.isEmpty) return true;
      return '${s['documentKind'] ?? ''} ${s['irn'] ?? ''} ${s['ewayBillNumber'] ?? ''} ${s['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fProfs = profiles.where((p) {
      if (q.isEmpty) return true;
      return '${p['sellerGstin'] ?? ''} ${p['registeredLegalName'] ?? ''} ${p['city'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: widget.submissionsFocus ? 'GST E-Invoices & Bills' : 'GST Registration & Transport',
      icon: Icons.verified_user_outlined,
      searchController: _search,
      searchHint: 'Search by IRN, E-Way Bill or GSTIN...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _showForm = false;
        }),
        tabs: [
          ('SUBMISSIONS', 'IRN & E-Way (${submissions.length})'),
          ('PROFILES', 'GST Profiles (${profiles.length})'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: _tab == 'PROFILES' ? 'New GST Profile' : 'Prepare IRN / E-Way Bill',
        onPressed: () => setState(() => _showForm = !_showForm),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            if (_showForm) ...[
              SaasField(
                label: 'Audit reason (required for commands)',
                controller: _auditReason,
              ),
              const SizedBox(height: 12),
              if (_tab == 'PROFILES')
                SaasFormCard(
                  title: 'Effective GST profile',
                  subtitle:
                      'Enter accountant-approved applicability and reporting rules for this legal entity.',
                  icon: Icons.shield_outlined,
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Save Draft Profile',
                        busy: _busy,
                        onPressed: _saveGstProfile,
                      ),
                    ],
                  ),
                )
              else
                SaasFormCard(
                  title: 'Prepare provider submission',
                  icon: Icons.local_shipping_outlined,
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Prepare & Queue',
                        busy: _busy,
                        onPressed: _prepareSubmission,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_tab == 'PROFILES') ...[
              if (fProfs.isEmpty)
                const SaasEmptyBox('No GST profiles configured yet.')
              else
                for (final p in fProfs)
                  LuxuryRecordCard(
                    icon: Icons.shield_outlined,
                    code: '${p['sellerGstin'] ?? 'GSTIN'}',
                    status: '${p['state'] ?? 'DRAFT'}',
                    lines: [
                      ('Legal Name', '${p['registeredLegalName'] ?? ''}'),
                      ('State / PIN', '${p['stateCode'] ?? ''} · ${p['postalCode'] ?? ''}'),
                    ],
                    amountLabel: 'Effective',
                    amountValue: fmtDate('${p['effectiveFrom'] ?? ''}'),
                    actions: [
                      if ('${p['state'] ?? 'DRAFT'}' == 'DRAFT')
                        GoldButton(
                          label: 'Approve',
                          compact: true,
                          busy: _busy,
                          onPressed: () async {
                            setState(() => _busy = true);
                            try {
                              await context.read<ApiClient>().post(
                                '/gst-compliance/profiles/${p['id']}/approve',
                                idempotent: true,
                                body: {
                                  'expectedVersion': asInt(p['version'], fallback: 1),
                                  'reason': _auditReason.text.trim().isEmpty
                                      ? 'Approved effective GSTIN compliance profile.'
                                      : _auditReason.text.trim(),
                                },
                              );
                              if (mounted) _load();
                            } on ApiException catch (e) {
                              if (mounted) setState(() => _error = e.message);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                        ),
                      if ('${p['state'] ?? ''}' == 'APPROVED')
                        GoldButton(
                          label: 'Activate',
                          compact: true,
                          busy: _busy,
                          onPressed: () async {
                            setState(() => _busy = true);
                            try {
                              await context.read<ApiClient>().post(
                                '/gst-compliance/profiles/${p['id']}/activate',
                                idempotent: true,
                                body: {
                                  'expectedVersion': asInt(p['version'], fallback: 1),
                                  'reason': _auditReason.text.trim().isEmpty
                                      ? 'Activated effective GSTIN compliance profile.'
                                      : _auditReason.text.trim(),
                                },
                              );
                              if (mounted) _load();
                            } on ApiException catch (e) {
                              if (mounted) setState(() => _error = e.message);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                        ),
                    ],
                  ),
            ] else ...[
              if (fSubs.isEmpty)
                const SaasEmptyBox('No statutory GST registrations prepared yet.')
              else
                for (final s in fSubs)
                  LuxuryRecordCard(
                    icon: Icons.verified_user_outlined,
                    code: '${s['irn'] ?? s['ewayBillNumber'] ?? shortId('${s['id']}')}',
                    status: '${s['state'] ?? 'QUEUED'}',
                    lines: [
                      ('Document Kind', '${s['documentKind'] ?? 'EINVOICE_IRN'}'),
                      if ('${s['placeOfSupply'] ?? ''}'.isNotEmpty) ('Place of Supply', '${s['placeOfSupply']}'),
                    ],
                    amountLabel: 'Stage',
                    amountValue: statusLabel('${s['state'] ?? 'QUEUED'}'),
                    actions: [
                      if ('${s['state'] ?? 'QUEUED'}' == 'QUEUED' || '${s['state'] ?? ''}' == 'PREPARED')
                        GoldButton(
                          label: 'Register',
                          compact: true,
                          busy: _busy,
                          onPressed: () async {
                            setState(() => _busy = true);
                            try {
                              await context.read<ApiClient>().post(
                                '/gst-compliance/submissions/${s['id']}/register',
                                idempotent: true,
                                body: {
                                  'expectedVersion': asInt(s['version'], fallback: 1),
                                  'reason': _auditReason.text.trim().isEmpty
                                      ? 'Submitted statutory IRN / E-way bill registration.'
                                      : _auditReason.text.trim(),
                                },
                              );
                              if (mounted) _load();
                            } on ApiException catch (e) {
                              if (mounted) setState(() => _error = e.message);
                            } finally {
                              if (mounted) setState(() => _busy = false);
                            }
                          },
                        ),
                    ],
                  ),
            ],
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
  final _search = TextEditingController();
  String _tab = 'PAPERS';
  bool _showForm = false;
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
      _search, _returnMonth, _commandReason, _itcEvidence, _gstr2bJson,
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

    final q = _search.text.trim().toLowerCase();
    final fPapers = papers.where((p) {
      if (q.isEmpty) return true;
      return 'rev ${p['revisionNumber'] ?? ''} ${p['state'] ?? ''} ${p['returnMonth'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fStmts = stmts.where((s) {
      if (q.isEmpty) return true;
      return '${s['returnMonth'] ?? ''} ${s['id'] ?? ''} ${s['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fExports = exports.where((ex) {
      if (q.isEmpty) return true;
      return '${ex['returnType'] ?? ''} ${ex['state'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'GST Returns & ITC Review',
      icon: Icons.description_outlined,
      searchController: _search,
      searchHint: 'Search by Return Month, Revision or Export...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _showForm = false;
        }),
        tabs: [
          ('PAPERS', 'Working Papers (${papers.length})'),
          ('GSTR2B', 'GSTR-2B (${stmts.length})'),
          ('EXPORTS', 'Exports (${exports.length})'),
        ],
      ),
      floatingActionButton: _tab == 'EXPORTS'
          ? null
          : GoldAddFab(
              icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
              tooltip: _tab == 'GSTR2B' ? 'Import GSTR-2B' : 'Prepare Working Paper',
              onPressed: () => setState(() => _showForm = !_showForm),
            ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
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
            const SizedBox(height: 12),
            SaasKpiGrid(
              items: [
                (label: 'POSTED OUTWARD LINES', value: '${_ws['postedOutwardLines'] ?? 0}'),
                (label: 'PURCHASE BOOKS', value: '${_ws['purchaseBookLines'] ?? _ws['purchaseBooks'] ?? 0}'),
                (label: 'WORKING-PAPER REVISIONS', value: '${papers.length}'),
              ],
            ),
            if (_error != null) ...[const SizedBox(height: 12), ErrorBanner(_error!, onRetry: _load)],

            if (_showForm) ...[
              const SizedBox(height: 12),
              SaasField(label: 'Command reason', controller: _commandReason),
              const SizedBox(height: 10),
              SaasField(label: 'ITC review evidence / reference', controller: _itcEvidence),
              const SizedBox(height: 12),
              if (_tab == 'GSTR2B')
                SaasFormCard(
                  title: 'Import & reconcile GSTR-2B',
                  subtitle: 'Use authorized records normalized to NORMALIZED_GSTR2B_V1.',
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Import Records',
                        busy: _busy,
                        onPressed: () => _runGstMutation(
                          (api) => api.post('/gst-returns/gstr2b/import', idempotent: true, body: {
                            'returnMonth': _returnMonth.text.trim(),
                            'reason': _commandReason.text.trim(),
                            'records': jsonDecode(_gstr2bJson.text.trim().isEmpty ? '[]' : _gstr2bJson.text.trim()),
                          }),
                          'GSTR-2B records imported.',
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
                      OutlinedButton.icon(
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
                        label: const Text('Build ITC Reconciliation'),
                      ),
                    ],
                  ),
                )
              else
                SaasFormCard(
                  title: 'Prepare GSTR working papers',
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Prepare Working-Paper Revision',
                        busy: _busy,
                        onPressed: () => _runGstMutation(
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
                      ),
                      if (paperOpts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        LookupField(
                          label: 'Select record',
                          controller: _selectedRecordId,
                          options: paperOpts,
                          hint: 'Select...',
                        ),
                      ],
                    ],
                  ),
                ),
            ],

            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_tab == 'PAPERS') ...[
              if (fPapers.isEmpty)
                const SaasEmptyBox('No working-paper revisions for this month.')
              else
                for (final p in fPapers)
                  LuxuryRecordCard(
                    icon: Icons.description_outlined,
                    code: 'Revision ${p['revisionNumber'] ?? 1} · ${p['returnMonth'] ?? _returnMonth.text}',
                    status: '${p['state'] ?? 'DRAFT'}',
                    lines: [
                      if ('${p['createdAt'] ?? ''}'.isNotEmpty) ('Prepared', fmtDateTime('${p['createdAt']}')),
                    ],
                    amountLabel: 'Stage',
                    amountValue: statusLabel('${p['state'] ?? 'DRAFT'}'),
                    actions: [
                      if ('${p['state'] ?? 'DRAFT'}' == 'DRAFT')
                        GoldButton(
                          label: 'Submit Review',
                          compact: true,
                          busy: _busy,
                          onPressed: () => _runGstMutation(
                            (api) => api.post(
                              '/gst-returns/working-papers/${p['id']}/submit',
                              idempotent: true,
                              body: {
                                'expectedVersion': asInt(p['version'], fallback: 1),
                                'reason': _commandReason.text.trim().isEmpty
                                    ? 'Submitted working paper for accountant review.'
                                    : _commandReason.text.trim(),
                              },
                            ),
                            'Working paper submitted for review.',
                          ),
                        ),
                      if ('${p['state'] ?? ''}' == 'SUBMITTED' || '${p['state'] ?? ''}' == 'IN_REVIEW')
                        GoldButton(
                          label: 'Approve',
                          compact: true,
                          busy: _busy,
                          onPressed: () => _runGstMutation(
                            (api) => api.post(
                              '/gst-returns/working-papers/${p['id']}/approve',
                              idempotent: true,
                              body: {
                                'expectedVersion': asInt(p['version'], fallback: 1),
                                'reason': _commandReason.text.trim().isEmpty
                                    ? 'Approved working-paper revision.'
                                    : _commandReason.text.trim(),
                              },
                            ),
                            'Working-paper revision approved.',
                          ),
                        ),
                      if ('${p['state'] ?? ''}' == 'APPROVED') ...[
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _runGstMutation(
                                    (api) => api.post(
                                      '/gst-returns/working-papers/${p['id']}/export',
                                      idempotent: true,
                                      body: {
                                        'returnType': 'GSTR1',
                                        'reason': _commandReason.text.trim().isEmpty
                                            ? 'Generated GSTR-1 preparation snapshot.'
                                            : _commandReason.text.trim(),
                                      },
                                    ),
                                    'GSTR-1 snapshot exported.',
                                  ),
                          child: const Text('Export GSTR-1'),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _runGstMutation(
                                    (api) => api.post(
                                      '/gst-returns/working-papers/${p['id']}/export',
                                      idempotent: true,
                                      body: {
                                        'returnType': 'GSTR3B',
                                        'reason': _commandReason.text.trim().isEmpty
                                            ? 'Generated GSTR-3B preparation snapshot.'
                                            : _commandReason.text.trim(),
                                      },
                                    ),
                                    'GSTR-3B snapshot exported.',
                                  ),
                          child: const Text('Export GSTR-3B'),
                        ),
                      ],
                    ],
                  ),
            ] else if (_tab == 'GSTR2B') ...[
              if (fStmts.isEmpty && recons.isEmpty)
                const SaasEmptyBox('No GSTR-2B statements imported for this month.')
              else ...[
                for (final s in fStmts)
                  LuxuryRecordCard(
                    icon: Icons.fact_check_outlined,
                    code: 'GSTR-2B · ${s['returnMonth'] ?? _returnMonth.text}',
                    status: '${s['state'] ?? 'IMPORTED'}',
                    lines: [
                      ('Statement Ref', shortId('${s['id'] ?? ''}')),
                      ('Reconciliations', '${recons.length} built'),
                    ],
                    amountLabel: 'Records',
                    amountValue: '${s['recordCount'] ?? asList(s['records']).length}',
                  ),
                for (final r in recons)
                  LuxuryRecordCard(
                    icon: Icons.rule_folder_outlined,
                    code: 'ITC Reconciliation · ${shortId('${r['id'] ?? ''}')}',
                    status: '${r['state'] ?? 'DRAFT'}',
                    lines: [
                      ('Return Month', '${r['returnMonth'] ?? _returnMonth.text}'),
                    ],
                    amountLabel: 'Stage',
                    amountValue: statusLabel('${r['state'] ?? 'DRAFT'}'),
                    actions: [
                      if ('${r['state'] ?? 'DRAFT'}' != 'APPROVED')
                        GoldButton(
                          label: 'Approve ITC Reconciliation',
                          compact: true,
                          busy: _busy,
                          onPressed: () => _runGstMutation(
                            (api) => api.post(
                              '/gst-returns/reconciliations/${r['id']}/approve',
                              idempotent: true,
                              body: {
                                'expectedVersion': asInt(r['version'], fallback: 1),
                                'reason': _commandReason.text.trim().isEmpty
                                    ? 'Approved GSTR-2B ITC reconciliation.'
                                    : _commandReason.text.trim(),
                                if (_itcEvidence.text.trim().isNotEmpty)
                                  'evidence': _itcEvidence.text.trim(),
                              },
                            ),
                            'ITC reconciliation approved.',
                          ),
                        ),
                    ],
                  ),
              ],
            ] else ...[
              if (fExports.isEmpty)
                const SaasEmptyBox('No approved GSTR preparation exports created yet.')
              else
                for (final ex in fExports)
                  LuxuryRecordCard(
                    icon: Icons.download_done_rounded,
                    code: '${ex['returnType'] ?? 'GSTR'} Snapshot',
                    status: '${ex['state'] ?? 'READY'}',
                    lines: [
                      ('Created', fmtDate('${ex['createdAt'] ?? ''}')),
                    ],
                    amountLabel: 'Status',
                    amountValue: '${ex['state'] ?? 'READY'}',
                  ),
            ],
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
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _showForm = false;
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
    for (final c in [_search, _partyId, _templateKey, _purpose, _bodyPreview]) {
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
      setState(() => _showForm = false);
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
    final q = _search.text.trim().toLowerCase();
    final sentCnt = dispatches.where((m) => '${m['state'] ?? ''}'.toUpperCase() == 'SENT').length;
    final queuedCnt = dispatches.where((m) => '${m['state'] ?? 'QUEUED'}'.toUpperCase() != 'SENT').length;
    final filtered = dispatches.where((m) {
      final st = '${m['state'] ?? 'QUEUED'}'.toUpperCase();
      if (_filter == 'SENT' && st != 'SENT') return false;
      if (_filter == 'QUEUED' && st == 'SENT') return false;
      if (q.isEmpty) return true;
      return '${m['channel'] ?? ''} ${m['templateKey'] ?? ''} ${asMap(m['party'])['displayName'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Customer Messaging',
      icon: Icons.chat_bubble_outline_rounded,
      searchController: _search,
      searchHint: 'Search by Channel, Template or Party...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${dispatches.length})'),
          ('QUEUED', 'Queued ($queuedCnt)'),
          ('SENT', 'Sent ($sentCnt)'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'Queue Notification',
        onPressed: () => setState(() => _showForm = !_showForm),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            if (_showForm) ...[
              SaasFormCard(
                title: 'Queue transactional notification',
                trailing: TextButton(
                  onPressed: () => setState(() => _showForm = false),
                  child: const Text('Close'),
                ),
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
                    GoldButton(
                      label: 'Queue Notification',
                      busy: _busy,
                      onPressed: _send,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (filtered.isEmpty)
              const SaasEmptyBox('No customer notifications found. Tap + to queue a notification.')
            else
              for (final m in filtered)
                LuxuryRecordCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  code: '${m['templateKey'] ?? shortId('${m['id']}')}',
                  status: '${m['state'] ?? 'QUEUED'}',
                  lines: [
                    ('Channel', '${m['channel'] ?? 'WHATSAPP'}'),
                    if ('${asMap(m['party'])['displayName'] ?? ''}'.isNotEmpty)
                      ('Recipient', '${asMap(m['party'])['displayName']}'),
                    if ('${m['purpose'] ?? ''}'.isNotEmpty) ('Purpose', '${m['purpose']}'),
                  ],
                  amountLabel: 'Dispatch',
                  amountValue: '${m['channel'] ?? 'MSG'}',
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
  final _search = TextEditingController();
  String _tab = 'TEMPLATES';
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
    for (final c in [_search, _sourceId, _renderTemplateKey, _tmplKey, _tmplName, _tmplBody]) {
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
    final q = _search.text.trim().toLowerCase();
    final fTemplates = _templates.where((t) {
      if (q.isEmpty) return true;
      return '${t['templateKey'] ?? ''} ${t['name'] ?? ''} ${t['layoutType'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Company & Invoice Print',
      icon: Icons.print_outlined,
      searchController: _search,
      searchHint: 'Search by Template Key, Name or Layout...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: [
          ('TEMPLATES', 'Templates (${_templates.length})'),
          ('PREVIEW', 'Render & Reprint'),
        ],
      ),
      floatingActionButton: _tab == 'TEMPLATES'
          ? GoldAddFab(
              icon: _showCreate ? Icons.close_rounded : Icons.add_rounded,
              tooltip: 'New Document Template',
              onPressed: () => setState(() => _showCreate = !_showCreate),
            )
          : null,
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],

            if (_showCreate && _tab == 'TEMPLATES') ...[
              SaasFormCard(
                title: 'Register document template',
                trailing: TextButton(
                  onPressed: () => setState(() => _showCreate = false),
                  child: const Text('Close'),
                ),
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
                      label: 'Save Template',
                      busy: _busy,
                      onPressed: _createTemplate,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_tab == 'PREVIEW')
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
                    GoldButton(
                      label: _busy ? 'Rendering…' : 'Render Document',
                      icon: Icons.visibility_outlined,
                      busy: _busy,
                      onPressed: _renderDoc,
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
              )
            else if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (fTemplates.isEmpty)
              const SaasEmptyBox('No document templates found. Tap + to register a print template.')
            else
              for (final t in fTemplates)
                LuxuryRecordCard(
                  icon: Icons.print_outlined,
                  code: '${t['name'] ?? t['templateKey']}',
                  status: '${t['state'] ?? 'ACTIVE'}',
                  lines: [
                    ('Key', '${t['templateKey'] ?? ''}'),
                    ('Layout', '${t['layout'] ?? t['layoutType'] ?? 'A4'}'),
                  ],
                  amountLabel: 'Version',
                  amountValue: 'v${t['version'] ?? 1}',
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
  final _search = TextEditingController();
  String _tab = 'BRANCHES';
  bool _showForm = false;
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
    for (final c in [_search, _legalName, _currency, _timezone, _branchEntityId, _branchCode, _branchName]) {
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
      setState(() => _showForm = false);
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
      setState(() => _showForm = false);
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
    final allBranches = <Map<String, dynamic>>[];
    for (final e in _entities) {
      for (final b in asList(e['branches'])) {
        allBranches.add({...b, '_entity': e});
      }
    }

    final q = _search.text.trim().toLowerCase();
    final fBranches = allBranches.where((b) {
      if (q.isEmpty) return true;
      final ent = asMap(b['_entity']);
      return '${b['code'] ?? ''} ${b['name'] ?? ''} ${ent['legalName'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fEntities = _entities.where((e) {
      if (q.isEmpty) return true;
      return '${e['legalName'] ?? ''} ${e['functionalCurrency'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Showroom Hierarchy',
      icon: Icons.apartment_rounded,
      searchController: _search,
      searchHint: 'Search by Showroom Branch or Legal Entity...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          _showForm = false;
        }),
        tabs: [
          ('BRANCHES', 'Branches (${allBranches.length})'),
          ('ENTITIES', 'Legal Entities (${_entities.length})'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: _tab == 'ENTITIES' ? 'New Legal Entity' : 'New Showroom Branch',
        onPressed: () => setState(() => _showForm = !_showForm),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            if (_showForm) ...[
              if (_tab == 'ENTITIES')
                SaasFormCard(
                  title: 'New legal entity',
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Create Legal Entity',
                        busy: _busy,
                        onPressed: _createEntity,
                      ),
                    ],
                  ),
                )
              else
                SaasFormCard(
                  title: 'New showroom branch',
                  trailing: TextButton(
                    onPressed: () => setState(() => _showForm = false),
                    child: const Text('Close'),
                  ),
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
                      GoldButton(
                        label: 'Create Branch',
                        busy: _busy,
                        onPressed: _createBranch,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_tab == 'ENTITIES') ...[
              if (fEntities.isEmpty)
                const SaasEmptyBox('No legal entities found. Tap + to create one.')
              else
                for (final e in fEntities)
                  LuxuryRecordCard(
                    icon: Icons.domain_rounded,
                    code: '${e['legalName'] ?? e['name']}',
                    status: '${e['functionalCurrency'] ?? 'INR'}',
                    lines: [
                      ('Timezone', '${e['timezone'] ?? 'Asia/Kolkata'}'),
                      ('Branches', '${asList(e['branches']).length} showroom(s)'),
                    ],
                    amountLabel: 'Currency',
                    amountValue: '${e['functionalCurrency'] ?? 'INR'}',
                  ),
            ] else ...[
              if (fBranches.isEmpty)
                const SaasEmptyBox('No showroom branches found. Tap + to create a showroom branch.')
              else
                for (final b in fBranches)
                  Builder(builder: (_) {
                    final ent = asMap(b['_entity']);
                    final isActive = app.selectedBranchId == '${b['id']}';
                    return LuxuryRecordCard(
                      icon: Icons.storefront_outlined,
                      code: '${b['name'] ?? b['code']}',
                      status: isActive ? 'ACTIVE' : 'AVAILABLE',
                      lines: [
                        ('Legal Entity', '${ent['legalName'] ?? ent['name'] ?? ''}'),
                        ('Currency', '${ent['functionalCurrency'] ?? 'INR'}'),
                      ],
                      amountLabel: 'Code',
                      amountValue: '${b['code'] ?? ''}',
                      actions: [
                        if (!isActive)
                          GoldButton(
                            label: 'Activate Showroom',
                            compact: true,
                            icon: Icons.check_circle_outline_rounded,
                            onPressed: () {
                              final tId = app.selectedTenantId;
                              if (tId.isNotEmpty) {
                                app.selectContextByIds(
                                  tenantId: tId,
                                  legalEntityId: '${ent['id']}',
                                  branchId: '${b['id']}',
                                  legalEntityName: '${ent['legalName'] ?? ent['name'] ?? ''}',
                                  branchDisplayName: '${b['name'] ?? ''}',
                                  branchDisplayCode: '${b['code'] ?? ''}',
                                );
                              }
                            },
                          ),
                      ],
                    );
                  }),
            ],
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
  final _search = TextEditingController();
  String _tab = 'ROLES';
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
    _search.dispose();
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
    final q = _search.text.trim().toLowerCase();
    final fRoles = roles.where((r) {
      if (q.isEmpty) return true;
      return '${r['name'] ?? ''} ${r['key'] ?? ''}'.toLowerCase().contains(q);
    }).toList();
    final fMembers = memberships.where((m) {
      if (q.isEmpty) return true;
      return '${asMap(m['user'])['displayName'] ?? ''} ${asMap(m['user'])['email'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fPerms = perms.where((p) {
      if (q.isEmpty) return true;
      return '${p['key'] ?? ''} ${p['description'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Access Control & Roles',
      icon: Icons.admin_panel_settings_outlined,
      searchController: _search,
      searchHint: 'Search by Role, Member Email or Permission...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _tab,
        onChanged: (v) => setState(() => _tab = v),
        tabs: [
          ('ROLES', 'Roles (${roles.length})'),
          ('MEMBERS', 'Members (${memberships.length})'),
          ('PERMS', 'Permissions (${perms.length})'),
        ],
      ),
      floatingActionButton: GoldAddFab(
        icon: _showRoleForm ? Icons.close_rounded : Icons.add_rounded,
        tooltip: 'New Role',
        onPressed: () => setState(() {
          _tab = 'ROLES';
          _showRoleForm = !_showRoleForm;
        }),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],

            if (_showRoleForm) ...[
              SaasFormCard(
                title: 'Create tenant role',
                trailing: TextButton(
                  onPressed: () => setState(() => _showRoleForm = false),
                  child: const Text('Close'),
                ),
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
                      label: 'Create Role',
                      busy: _busy,
                      onPressed: _createRole,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_tab == 'ROLES') ...[
              if (fRoles.isEmpty)
                const SaasEmptyBox('No roles configured yet. Tap + to create a tenant RBAC role.')
              else
                for (final r in fRoles)
                  LuxuryRecordCard(
                    icon: Icons.admin_panel_settings_outlined,
                    code: '${r['name'] ?? r['key']}',
                    status: 'ACTIVE',
                    lines: [
                      ('Role Key', '${r['key'] ?? ''}'),
                    ],
                    amountLabel: 'Permissions',
                    amountValue: '${asList(r['permissionKeys']).length} keys',
                  ),
            ] else if (_tab == 'MEMBERS') ...[
              if (fMembers.isEmpty)
                const SaasEmptyBox('No tenant memberships found.')
              else
                for (final m in fMembers)
                  LuxuryRecordCard(
                    icon: Icons.badge_outlined,
                    code: '${asMap(m['user'])['displayName'] ?? asMap(m['user'])['email'] ?? 'Member'}',
                    status: '${m['state'] ?? 'ACTIVE'}',
                    lines: [
                      ('Email', '${asMap(m['user'])['email'] ?? ''}'),
                    ],
                    amountLabel: 'Perm Version',
                    amountValue: 'v${m['permissionVersion'] ?? 1}',
                  ),
            ] else ...[
              if (fPerms.isEmpty)
                const SaasEmptyBox('No permission keys returned.')
              else
                for (final p in fPerms)
                  LuxuryRecordCard(
                    icon: Icons.vpn_key_outlined,
                    code: '${p['key'] ?? ''}',
                    status: 'RBAC',
                    lines: [
                      if ('${p['description'] ?? ''}'.isNotEmpty) ('Scope', '${p['description']}'),
                    ],
                  ),
            ],
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
  final _search = TextEditingController();
  String _filter = 'ALL';
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
    _search.dispose();
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
    final q = _search.text.trim().toLowerCase();
    final pendCnt = _grants.where((g) => '${g['state'] ?? ''}' == 'REQUESTED').length;
    final appCnt = _grants.where((g) => '${g['state'] ?? ''}' == 'APPROVED').length;
    final filtered = _grants.where((g) {
      final st = '${g['state'] ?? 'REQUESTED'}';
      if (_filter == 'REQUESTED' && st != 'REQUESTED') return false;
      if (_filter == 'APPROVED' && st != 'APPROVED') return false;
      if (q.isEmpty) return true;
      return '${asMap(asMap(g['operator'])['user'])['displayName'] ?? ''} ${g['reason'] ?? ''} ${g['mode'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Audit & Compliance',
      icon: Icons.policy_outlined,
      searchController: _search,
      searchHint: 'Search by Operator, Scope or Reason...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${_grants.length})'),
          ('REQUESTED', 'Pending ($pendCnt)'),
          ('APPROVED', 'Approved ($appCnt)'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            if (_error != null) ...[ErrorBanner(_error!, onRetry: _load), const SizedBox(height: 12)],
            SaasField(
              label: 'Decision reason (minimum 10 characters)',
              controller: _decisionReason,
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (filtered.isEmpty)
              const SaasEmptyBox('No platform support access grants in this filter.')
            else
              for (final g in filtered)
                LuxuryRecordCard(
                  icon: Icons.policy_outlined,
                  code: '${asMap(asMap(g['operator'])['user'])['displayName'] ?? 'Platform Support'}',
                  status: '${g['state'] ?? 'REQUESTED'}',
                  lines: [
                    ('Mode', '${g['mode'] ?? 'READ_ONLY'}'),
                    ('Reason', '${g['reason'] ?? ''}'),
                    ('Expires', fmtDateTime('${g['expiresAt'] ?? ''}')),
                  ],
                  amountLabel: 'Access',
                  amountValue: statusLabel('${g['state'] ?? 'REQUESTED'}'),
                  actions: [
                    if ('${g['state']}' == 'REQUESTED') ...[
                      GoldButton(
                        label: 'Approve',
                        compact: true,
                        busy: _busy,
                        onPressed: () => _decide(g, 'approve'),
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
    );
  }
}

typedef DocumentsPolicyScreen = CompanyInvoicePolicyScreen;
