import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/device_bridge.dart';
import '../../core/format.dart';
import '../../core/pdf_export.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

// ---------------------------------------------------------------------------
// 1. PROVIDER INTEGRATIONS (`/integrations`) — `image-40..41.png`
// ---------------------------------------------------------------------------

class ProviderIntegrationsScreen extends StatefulWidget {
  const ProviderIntegrationsScreen({super.key});
  @override
  State<ProviderIntegrationsScreen> createState() =>
      _ProviderIntegrationsScreenState();
}

class _ProviderIntegrationsScreenState
    extends State<ProviderIntegrationsScreen> {
  final _search = TextEditingController();
  String _tab = 'CONNECTIONS';
  bool _connFormExpanded = true;
  bool _opFormExpanded = true;
  Map<String, dynamic> _ws = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _auditReason = TextEditingController();

  // `Register provider connection` (`image-40.png`)
  String _capability = 'PAYMENT';
  final _providerKey = TextEditingController();
  final _displayName = TextEditingController();
  String _scope = 'LEGAL_ENTITY';
  final _endpoint = TextEditingController();
  final _credentialRef = TextEditingController();
  final _webhookRef = TextEditingController();
  final _adapterJson = TextEditingController(text: '{}');

  // `Prepare outbound operation` (`image-40.png`)
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
      _search,
      _auditReason,
      _providerKey,
      _displayName,
      _endpoint,
      _credentialRef,
      _webhookRef,
      _adapterJson,
      _activeConnId,
      _operationType,
      _aggregateType,
      _aggregateUuid,
      _aggregateVersion,
      _payloadJson,
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
      final decoded = jsonDecode(
        _adapterJson.text.trim().isEmpty ? '{}' : _adapterJson.text.trim(),
      );
      if (decoded is Map) cfg = Map<String, dynamic>.from(decoded);
    } catch (_) {
      setState(
        () => _error =
            'Adapter configuration JSON must be a valid JSON object.',
      );
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
          if (_endpoint.text.trim().isNotEmpty)
            'endpointUrl': _endpoint.text.trim(),
          if (_credentialRef.text.trim().isNotEmpty)
            'credentialSecretRef': _credentialRef.text.trim(),
          if (_webhookRef.text.trim().isNotEmpty)
            'webhookSecretRef': _webhookRef.text.trim(),
          'adapterConfig': cfg,
          if (_auditReason.text.trim().isNotEmpty)
            'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      _providerKey.clear();
      _displayName.clear();
      toast(context, 'Draft provider connection saved.');
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
      setState(
        () => _error =
            'Select Active connection and fill Operation type, Aggregate type, and Aggregate UUID.',
      );
      return;
    }
    Map<String, dynamic> payload = {};
    try {
      final decoded = jsonDecode(
        _payloadJson.text.trim().isEmpty ? '{}' : _payloadJson.text.trim(),
      );
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      setState(
        () => _error = 'Immutable payload JSON must be a valid JSON object.',
      );
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
          if (_auditReason.text.trim().isNotEmpty)
            'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      _aggregateUuid.clear();
      toast(context, 'Outbound provider operation queued.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------------------
  // Connection Lifecycle Sheet: Activate / Suspend / Rotate Secret Refs
  // -------------------------------------------------------------------------
  Future<void> _openConnectionControlSheet(Map<String, dynamic> c) async {
    var actionTab = 'STATE';
    final credRefCtrl = TextEditingController(
      text: '${c['credentialSecretRef'] ?? ''}',
    );
    final hookRefCtrl = TextEditingController(
      text: '${c['webhookSecretRef'] ?? ''}',
    );
    final reasonCtrl = TextEditingController(text: _auditReason.text.trim());
    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Manage Connection · ${c['displayName'] ?? c['providerKey'] ?? ''}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${c['state'] ?? c['status'] ?? 'DRAFT'}'),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PillTabs<String>(
                  value: actionTab,
                  onChanged: (v) => setSheet(() {
                    actionTab = v;
                    sheetErr = null;
                  }),
                  tabs: const [
                    ('STATE', 'Activate / Suspend'),
                    ('SECRETS', 'Rotate Secret Refs'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (actionTab == 'STATE') ...[
                  SaasField(
                    label: 'Audit reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (reasonCtrl.text.trim().length < 10) {
                                    setSheet(
                                      () => sheetErr =
                                          'Enter audit reason (10+ chars).',
                                    );
                                    return;
                                  }
                                  setSheet(() {
                                    saving = true;
                                    sheetErr = null;
                                  });
                                  try {
                                    await context.read<ApiClient>().post(
                                      '/integrations/connections/${c['id']}/suspend',
                                      idempotent: true,
                                      body: {
                                        'expectedVersion':
                                            asInt(c['version'], fallback: 1),
                                        'reason': reasonCtrl.text.trim(),
                                      },
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    if (!mounted) return;
                                    toast(context, 'Connection suspended.');
                                    _load();
                                  } on ApiException catch (e) {
                                    setSheet(() => sheetErr = e.message);
                                  } finally {
                                    if (ctx.mounted) {
                                      setSheet(() => saving = false);
                                    }
                                  }
                                },
                          child: const Text('Suspend'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RoyalGoldButton(
                          label: 'Activate Connection',
                          busy: saving,
                          onPressed: saving
                              ? null
                              : () async {
                                  if (reasonCtrl.text.trim().length < 10) {
                                    setSheet(
                                      () => sheetErr =
                                          'Enter audit reason (10+ chars).',
                                    );
                                    return;
                                  }
                                  setSheet(() {
                                    saving = true;
                                    sheetErr = null;
                                  });
                                  try {
                                    await context.read<ApiClient>().post(
                                      '/integrations/connections/${c['id']}/activate',
                                      idempotent: true,
                                      body: {
                                        'expectedVersion':
                                            asInt(c['version'], fallback: 1),
                                        'reason': reasonCtrl.text.trim(),
                                      },
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);
                                    if (!mounted) return;
                                    toast(context, 'Connection activated.');
                                    _load();
                                  } on ApiException catch (e) {
                                    setSheet(() => sheetErr = e.message);
                                  } finally {
                                    if (ctx.mounted) {
                                      setSheet(() => saving = false);
                                    }
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SaasField(
                    label: 'Credential secret ref',
                    controller: credRefCtrl,
                    hint: 'env:PAYMENT_API_KEY',
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Webhook secret ref',
                    controller: hookRefCtrl,
                    hint: 'env:PAYMENT_WEBHOOK_SECRET',
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Rotation audit reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Rotate Secret References',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter rotation reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/integrations/connections/${c['id']}/rotate-secrets',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(c['version'], fallback: 1),
                                  if (credRefCtrl.text.trim().isNotEmpty)
                                    'credentialSecretRef':
                                        credRefCtrl.text.trim(),
                                  if (hookRefCtrl.text.trim().isNotEmpty)
                                    'webhookSecretRef': hookRefCtrl.text.trim(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'Secret references rotated.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    for (final ctrl in [credRefCtrl, hookRefCtrl, reasonCtrl]) {
      ctrl.dispose();
    }
  }

  // -------------------------------------------------------------------------
  // Outbound Operation Control: Immutable Attempt & Unknown-Outcome Reconcile
  // -------------------------------------------------------------------------
  Future<void> _openOperationControlSheet(Map<String, dynamic> op) async {
    var outcome = 'SUCCEEDED';
    final extRefCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: _auditReason.text.trim());
    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Operation Control · ${op['operationType'] ?? shortId('${op['id']}')}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${op['state'] ?? op['status'] ?? 'PENDING'}'),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Dispatch an immutable attempt or reconcile an unknown provider outcome.',
                  style: T.body(12, color: Pal.muted),
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),
                RoyalGoldButton(
                  label: 'Execute Immutable Attempt',
                  busy: saving,
                  onPressed: saving
                      ? null
                      : () async {
                          setSheet(() {
                            saving = true;
                            sheetErr = null;
                          });
                          try {
                            await context.read<ApiClient>().post(
                              '/integrations/operations/${op['id']}/execute',
                              idempotent: true,
                              body: {
                                'expectedVersion':
                                    asInt(op['version'], fallback: 1),
                                if (reasonCtrl.text.trim().isNotEmpty)
                                  'reason': reasonCtrl.text.trim(),
                              },
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            toast(context, 'Immutable provider attempt recorded.');
                            _load();
                          } on ApiException catch (e) {
                            setSheet(() => sheetErr = e.message);
                          } finally {
                            if (ctx.mounted) setSheet(() => saving = false);
                          }
                        },
                ),
                const Divider(height: 24),
                SaasDropdown(
                  label: 'Unknown-outcome reconciliation state',
                  value: outcome,
                  options: const {
                    'SUCCEEDED': 'Confirmed Succeeded at Provider',
                    'FAILED_TERMINAL': 'Confirmed Terminal Failure',
                    'RETRYABLE': 'Mark Retryable',
                  },
                  onChanged: (v) => setSheet(() => outcome = v),
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'External provider reference / evidence',
                  controller: extRefCtrl,
                  mono: true,
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Reconciliation audit reason (min 10 chars)',
                  controller: reasonCtrl,
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (reasonCtrl.text.trim().length < 10) {
                            setSheet(
                              () => sheetErr =
                                  'Enter reconciliation reason (10+ chars).',
                            );
                            return;
                          }
                          setSheet(() {
                            saving = true;
                            sheetErr = null;
                          });
                          try {
                            await context.read<ApiClient>().post(
                              '/integrations/operations/${op['id']}/reconcile',
                              idempotent: true,
                              body: {
                                'expectedVersion':
                                    asInt(op['version'], fallback: 1),
                                'outcome': outcome,
                                if (extRefCtrl.text.trim().isNotEmpty)
                                  'providerReference': extRefCtrl.text.trim(),
                                'reason': reasonCtrl.text.trim(),
                              },
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            toast(context, 'Operation outcome reconciled.');
                            _load();
                          } on ApiException catch (e) {
                            setSheet(() => sheetErr = e.message);
                          } finally {
                            if (ctx.mounted) setSheet(() => saving = false);
                          }
                        },
                  child: const Text('Reconcile Unknown Outcome'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    extRefCtrl.dispose();
    reasonCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = auth.tenantName.trim();
    final branchName = auth.branchName.trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final conns = asList(_ws['connections']);
    final ops = asList(
      _ws['operations'] ??
          _ws['externalOperations'] ??
          _ws['outboundOperations'],
    );
    final hooks = asList(
      _ws['webhooks'] ?? _ws['webhookInbox'] ?? _ws['webhookEvents'],
    );
    final activeCount = conns
        .where((c) => '${c['state'] ?? c['status']}'.toUpperCase() == 'ACTIVE')
        .length;
    final pendingOps = ops.where((o) {
      final st = '${o['state'] ?? o['status']}'.toUpperCase();
      return st == 'PENDING' || st == 'QUEUED' || st == 'UNKNOWN_OUTCOME';
    }).length;

    final connOpts = conns
        .map(
          (c) => LookupOption(
            id: '${c['id']}',
            label:
                '${c['displayName'] ?? c['providerKey']} (${c['capability'] ?? ''})',
            raw: c,
          ),
        )
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
      return '${h['eventType'] ?? ''} ${h['externalEventId'] ?? ''} ${h['providerKey'] ?? ''} ${h['payloadDigest'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Provider Integrations',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.cloud_sync_outlined,
      searchController: _search,
      searchHint: 'Search Provider, Operation or Webhook...',
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
          ('CONNECTIONS', 'Connections (${conns.length})'),
          ('OPERATIONS', 'External Ops (${ops.length})'),
          ('WEBHOOKS', 'Webhook Inbox (${hooks.length})'),
        ],
      ),
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

            // Hero Header Card (`Provider Integrations` — image-40.png)
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
                    children: [
                      const Icon(
                        Icons.cloud_sync_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Provider Integrations',
                          style: T.body(
                            16,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tenant-isolated payment, GST, messaging and export connections with secret references, signed webhooks, immutable attempts and unknown-outcome reconciliation.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Exact 4 KPI Cards (`image-40.png`)
            SaasKpiGrid(
              items: [
                (label: 'CONNECTIONS', value: '${conns.length}'),
                (label: 'ACTIVE', value: '$activeCount'),
                (label: 'PENDING OPERATIONS', value: '$pendingOps'),
                (label: 'VERIFIED WEBHOOKS', value: '${hooks.length}'),
              ],
            ),

            const SizedBox(height: 12),

            // Shared `Audit reason` (`image-40.png`)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Pal.border),
              ),
              child: SaasField(
                label: 'Audit reason',
                controller: _auditReason,
              ),
            ),

            const SizedBox(height: 12),

            // TAB 1: CONNECTIONS (`Register provider connection` + `Connections` — image-40..41.png)
            if (_tab == 'CONNECTIONS') ...[
              SaasFormCard(
                title: 'Register provider connection',
                icon: Icons.key_rounded,
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _connFormExpanded = !_connFormExpanded),
                  child: Text(_connFormExpanded ? 'Hide' : 'Show'),
                ),
                child: !_connFormExpanded
                    ? Text(
                        'Tap Show to register a payment, GST, messaging or export provider connection.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
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
                                  onChanged: (v) =>
                                      setState(() => _capability = v),
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
                            maxLines: 2,
                          ),
                          const SizedBox(height: 14),
                          RoyalGoldButton(
                            label: 'Save draft connection',
                            icon: Icons.verified_user_outlined,
                            busy: _busy,
                            onPressed: _busy ? null : _saveConnection,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'Connections',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 92))
              else if (fConns.isEmpty)
                const SaasEmptyBox(
                  'No provider connections registered in the authorized workspace.',
                )
              else
                for (final c in fConns)
                  LuxuryRecordCard(
                    enablePdfDownload: false,
                    icon: Icons.cloud_sync_outlined,
                    code: '${c['displayName'] ?? c['providerKey']}',
                    status: '${c['state'] ?? 'DRAFT'}',
                    onTap: () => _openConnectionControlSheet(c),
                    lines: [
                      ('Provider Key', '${c['providerKey'] ?? ''}'),
                      ('Scope', '${c['scope'] ?? ''}'),
                      if ('${c['endpointUrl'] ?? ''}'.isNotEmpty)
                        ('Endpoint', '${c['endpointUrl']}'),
                    ],
                    amountLabel: 'Capability',
                    amountValue: '${c['capability'] ?? 'ADAPTER'}',
                    actions: [
                      GoldButton(
                        label: 'Manage Connection',
                        compact: true,
                        onPressed: () => _openConnectionControlSheet(c),
                      ),
                    ],
                  ),
            ]

            // TAB 2: EXTERNAL OPERATIONS (`Prepare outbound operation` + `External operations` — image-40..41.png)
            else if (_tab == 'OPERATIONS') ...[
              SaasFormCard(
                title: 'Prepare outbound operation',
                icon: Icons.send_outlined,
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _opFormExpanded = !_opFormExpanded),
                  child: Text(_opFormExpanded ? 'Hide' : 'Show'),
                ),
                child: !_opFormExpanded
                    ? Text(
                        'Tap Show to prepare and queue an outbound provider operation.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
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
                            maxLines: 2,
                          ),
                          const SizedBox(height: 14),
                          RoyalGoldButton(
                            label: 'Queue operation',
                            icon: Icons.send_rounded,
                            busy: _busy,
                            onPressed: _busy ? null : _queueOperation,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'External operations',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'CREATED · PROVIDER / OPERATION · AGGREGATE · STATE · ATTEMPTS · CONTROL',
                style: T.caps(9.8),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 92))
              else if (fOps.isEmpty)
                const SaasEmptyBox('No external operations have been queued.')
              else
                for (final o in fOps)
                  LuxuryRecordCard(
                    icon: Icons.send_rounded,
                    code: '${o['operationType'] ?? shortId('${o['id']}')}',
                    status: '${o['state'] ?? o['status'] ?? 'PENDING'}',
                    onTap: () => _openOperationControlSheet(o),
                    lines: [
                      if ('${o['createdAt'] ?? ''}'.isNotEmpty)
                        ('Created', fmtDateTime('${o['createdAt']}')),
                      (
                        'Aggregate',
                        '${o['aggregateType'] ?? ''} · ${shortId('${o['aggregateId'] ?? ''}')}',
                      ),
                    ],
                    amountLabel: 'Attempts',
                    amountValue: '${o['attemptCount'] ?? o['attempts'] ?? 0}',
                    actions: [
                      GoldButton(
                        label: 'Control',
                        compact: true,
                        onPressed: () => _openOperationControlSheet(o),
                      ),
                    ],
                  ),
            ]

            // TAB 3: WEBHOOK INBOX (`Webhook inbox` — image-41.png)
            else ...[
              Row(
                children: [
                  const Icon(
                    Icons.webhook_rounded,
                    size: 18,
                    color: Pal.goldDeep,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Webhook inbox',
                    style: T.body(14.5, weight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'VERIFIED · EXTERNAL EVENT · STATE · PAYLOAD DIGEST',
                style: T.caps(9.8),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 92))
              else if (fHooks.isEmpty)
                const SaasEmptyBox(
                  'No signed provider webhook has been received.',
                )
              else
                for (final h in fHooks)
                  LuxuryRecordCard(
                    enablePdfDownload: false,
                    icon: Icons.webhook_rounded,
                    code:
                        '${h['eventType'] ?? h['externalEventId'] ?? shortId('${h['id']}')}',
                    status: '${h['state'] ?? 'VERIFIED'}',
                    lines: [
                      if ('${h['verifiedAt'] ?? h['receivedAt'] ?? ''}'
                          .isNotEmpty)
                        (
                          'Verified',
                          fmtDateTime(
                            '${h['verifiedAt'] ?? h['receivedAt']}',
                          ),
                        ),
                      if ('${h['payloadDigest'] ?? h['digest'] ?? ''}'
                          .isNotEmpty)
                        (
                          'Payload Digest',
                          '${h['payloadDigest'] ?? h['digest']}',
                        ),
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
// 2. GST REGISTRATION & TRANSPORT (`/gst-compliance`) — `image-42..43.png`
// ---------------------------------------------------------------------------

class GstRegistrationTransportScreen extends StatefulWidget {
  const GstRegistrationTransportScreen({
    super.key,
    this.submissionsFocus = false,
  });
  final bool submissionsFocus;
  @override
  State<GstRegistrationTransportScreen> createState() =>
      _GstRegistrationTransportScreenState();
}

class _GstRegistrationTransportScreenState
    extends State<GstRegistrationTransportScreen> {
  final _search = TextEditingController();
  late String _tab = widget.submissionsFocus ? 'SUBMISSIONS' : 'PROFILES';
  bool _profileFormExpanded = true;
  bool _subFormExpanded = true;
  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  final _auditReason = TextEditingController();

  // `Effective GST profile` (`image-42..43.png`)
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

  // `Prepare provider submission` (`image-42.png`)
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
      _search,
      _auditReason,
      _sellerGstin,
      _legalName,
      _tradeName,
      _addr1,
      _addr2,
      _city,
      _stateCode,
      _pinCode,
      _ewayThreshold,
      _reportingWindowDays,
      _stockHoldMinutes,
      _effectiveFrom,
      _effectiveUntil,
      _invoiceId,
      _taxConnId,
      _openPeriodId,
      _invSeriesId,
      _placeOfSupply,
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
      final lk = res[1] as WorkspaceLookup;
      if (_openPeriodId.text.isEmpty && lk.openPeriods().isNotEmpty) {
        _openPeriodId.text = lk.openPeriods().first.id;
      }
      if (_invSeriesId.text.isEmpty) {
        final s = lk.seriesFor(const ['INVOICE', 'SALES']);
        if (s.isNotEmpty) _invSeriesId.text = s.first.id;
      }
      setState(() {
        _ws = asMap(res[0]);
        _lk = lk;
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
      setState(
        () => _error =
            'Enter 15-character Seller GSTIN, Registered legal name, and 2-digit GST state code.',
      );
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
          if (_tradeName.text.trim().isNotEmpty)
            'tradeName': _tradeName.text.trim(),
          'addressLine1': _addr1.text.trim(),
          if (_addr2.text.trim().isNotEmpty)
            'addressLine2': _addr2.text.trim(),
          'city': _city.text.trim(),
          'stateCode': _stateCode.text.trim(),
          'postalCode': _pinCode.text.trim(),
          if (_ewayThreshold.text.trim().isNotEmpty)
            'ewayBillThresholdAmount': normAmount(_ewayThreshold.text),
          if (_reportingWindowDays.text.trim().isNotEmpty)
            'reportingWindowDays':
                int.tryParse(_reportingWindowDays.text.trim()) ?? 3,
          'stockHoldMinutes':
              int.tryParse(_stockHoldMinutes.text.trim()) ?? 120,
          'effectiveFrom': _effectiveFrom.text.trim(),
          if (_effectiveUntil.text.trim().isNotEmpty)
            'effectiveTo': _effectiveUntil.text.trim(),
          'enableEinvoiceRegistration': _enableEinvoice,
          'requireIrnForRegisteredCustomers': _requireIrnForRegistered,
          'enableThresholdEwayBillControl': _enableThresholdEway,
          if (_auditReason.text.trim().isNotEmpty)
            'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      toast(context, 'Draft GST profile saved.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareSubmission() async {
    if (_invoiceId.text.trim().isEmpty || _taxConnId.text.trim().isEmpty) {
      setState(
        () => _error = 'Select Invoice and Tax provider connection.',
      );
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
          if (_auditReason.text.trim().isNotEmpty)
            'reason': _auditReason.text.trim(),
        },
      );
      if (!mounted) return;
      toast(context, 'GST provider submission prepared & queued.');
      _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -------------------------------------------------------------------------
  // GST Profile Lifecycle Modal: Approve / Retire
  // -------------------------------------------------------------------------
  Future<void> _openProfileLifecycleSheet(Map<String, dynamic> p) async {
    final reasonCtrl = TextEditingController(text: _auditReason.text.trim());
    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'GST Profile · ${p['sellerGstin'] ?? ''}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${p['state'] ?? 'DRAFT'}'),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),
                SaasField(
                  label: 'Audit reason (min 10 chars)',
                  controller: reasonCtrl,
                  maxLines: 2,
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  label: 'Approve & Activate GST Profile',
                  busy: saving,
                  onPressed: saving
                      ? null
                      : () async {
                          if (reasonCtrl.text.trim().length < 10) {
                            setSheet(
                              () => sheetErr = 'Enter audit reason (10+ chars).',
                            );
                            return;
                          }
                          setSheet(() {
                            saving = true;
                            sheetErr = null;
                          });
                          try {
                            await context.read<ApiClient>().post(
                              '/gst-compliance/profiles/${p['id']}/approve',
                              idempotent: true,
                              body: {
                                'expectedVersion':
                                    asInt(p['version'], fallback: 1),
                                'reason': reasonCtrl.text.trim(),
                              },
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            if (!mounted) return;
                            toast(context, 'GST profile approved & active.');
                            _load();
                          } on ApiException catch (e) {
                            setSheet(() => sheetErr = e.message);
                          } finally {
                            if (ctx.mounted) setSheet(() => saving = false);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    reasonCtrl.dispose();
  }

  // -------------------------------------------------------------------------
  // GST Submission Lifecycle: Registration, Cancellation & Recovery (`image-43`)
  // -------------------------------------------------------------------------
  Future<void> _openSubmissionLifecycleSheet(Map<String, dynamic> s) async {
    var actionTab = 'REGISTER';
    final irnCtrl = TextEditingController(text: '${s['irn'] ?? ''}');
    final ackNoCtrl = TextEditingController(text: '${s['ackNumber'] ?? ''}');
    final ewayCtrl = TextEditingController(
      text: '${s['ewayBillNumber'] ?? ''}',
    );
    var cancelCode = 'DATA_ENTRY_MISTAKE';
    var recoveryAction = 'RETRY_SUBMISSION';
    final reasonCtrl = TextEditingController(text: _auditReason.text.trim());
    var saving = false;
    String? sheetErr;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            16,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Submission · ${s['documentKind'] ?? 'EINVOICE_IRN'}',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    StatusPill('${s['state'] ?? 'QUEUED'}'),
                    const SizedBox(width: 6),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: saving ? null : () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                PillTabs<String>(
                  value: actionTab,
                  onChanged: (v) => setSheet(() {
                    actionTab = v;
                    sheetErr = null;
                  }),
                  tabs: const [
                    ('REGISTER', 'Registration'),
                    ('CANCEL', 'Cancellation'),
                    ('RECOVER', 'Recovery'),
                  ],
                ),
                if (sheetErr != null) ...[
                  const SizedBox(height: 10),
                  ErrorBanner(sheetErr!),
                ],
                const SizedBox(height: 12),

                if (actionTab == 'REGISTER') ...[
                  SaasField(
                    label: 'IRP Registered IRN (64-char hash, optional if GSP)',
                    controller: irnCtrl,
                    mono: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: SaasField(
                          label: 'Acknowledgement No.',
                          controller: ackNoCtrl,
                          mono: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SaasField(
                          label: 'E-Way Bill No.',
                          controller: ewayCtrl,
                          mono: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Audit reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Confirm Registration & Post Evidence',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter audit reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/gst-compliance/submissions/${s['id']}/register',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(s['version'], fallback: 1),
                                  if (irnCtrl.text.trim().isNotEmpty)
                                    'irn': irnCtrl.text.trim(),
                                  if (ackNoCtrl.text.trim().isNotEmpty)
                                    'ackNumber': ackNoCtrl.text.trim(),
                                  if (ewayCtrl.text.trim().isNotEmpty)
                                    'ewayBillNumber': ewayCtrl.text.trim(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(
                                context,
                                'GST registration evidence confirmed.',
                              );
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else if (actionTab == 'CANCEL') ...[
                  SaasDropdown(
                    label: 'Statutory cancellation reason code',
                    value: cancelCode,
                    options: const {
                      'DUPLICATE': '1 · Duplicate IRN / E-Way Bill',
                      'DATA_ENTRY_MISTAKE': '2 · Data entry mistake',
                      'ORDER_CANCELLED': '3 · Order cancelled',
                      'OTHERS': '4 · Others',
                    },
                    onChanged: (v) => setSheet(() => cancelCode = v),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Cancellation audit reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Cancel Registration',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter cancellation reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/gst-compliance/submissions/${s['id']}/cancel',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(s['version'], fallback: 1),
                                  'cancellationCode': cancelCode,
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'GST registration cancelled.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ] else ...[
                  SaasDropdown(
                    label: 'Recovery action',
                    value: recoveryAction,
                    options: const {
                      'RETRY_SUBMISSION': 'Retry GSP provider submission',
                      'RELEASE_STOCK_HOLD': 'Release expired stock hold',
                      'MARK_REJECTED': 'Mark terminal rejection for correction',
                    },
                    onChanged: (v) => setSheet(() => recoveryAction = v),
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Recovery audit reason (min 10 chars)',
                    controller: reasonCtrl,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 14),
                  RoyalGoldButton(
                    label: 'Execute Recovery',
                    busy: saving,
                    onPressed: saving
                        ? null
                        : () async {
                            if (reasonCtrl.text.trim().length < 10) {
                              setSheet(
                                () => sheetErr =
                                    'Enter recovery reason (10+ chars).',
                              );
                              return;
                            }
                            setSheet(() {
                              saving = true;
                              sheetErr = null;
                            });
                            try {
                              await context.read<ApiClient>().post(
                                '/gst-compliance/submissions/${s['id']}/recover',
                                idempotent: true,
                                body: {
                                  'expectedVersion':
                                      asInt(s['version'], fallback: 1),
                                  'recoveryAction': recoveryAction,
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              if (!mounted) return;
                              toast(context, 'GST submission recovery executed.');
                              _load();
                            } on ApiException catch (e) {
                              setSheet(() => sheetErr = e.message);
                            } finally {
                              if (ctx.mounted) setSheet(() => saving = false);
                            }
                          },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    for (final ctrl in [irnCtrl, ackNoCtrl, ewayCtrl, reasonCtrl]) {
      ctrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = auth.tenantName.trim();
    final branchName = auth.branchName.trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final profiles = asList(_ws['profiles'] ?? _ws['gstProfiles']);
    final submissions = asList(_ws['submissions'] ?? _ws['gstSubmissions']);

    final gstConns = _lk.connections.where((c) {
      final cap = '${c.raw['capability'] ?? ''}'.toUpperCase();
      return cap.isEmpty || cap == 'GST';
    }).toList();

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
      title: widget.submissionsFocus
          ? 'GST E-Invoices & Bills'
          : 'GST Registration & Transport',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.verified_user_outlined,
      searchController: _search,
      searchHint: 'Search by GSTIN, IRN or E-Way Bill...',
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
          ('PROFILES', 'Effective GST Profile (${profiles.length})'),
          ('SUBMISSIONS', 'IRN & E-Way Bills (${submissions.length})'),
        ],
      ),
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

            // Hero Header Card (`GST Registration & Transport` — image-42.png)
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
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GST Registration & Transport',
                          style: T.body(
                            16,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Prepare registered-customer invoices, review provider evidence and track registration before posting or dispatch.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Shared `Audit reason (required for commands)` (`image-42.png`)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Pal.border),
              ),
              child: SaasField(
                label: 'Audit reason (required for commands)',
                controller: _auditReason,
              ),
            ),

            const SizedBox(height: 12),

            // TAB 1: EFFECTIVE GST PROFILE (`image-42..43.png`)
            if (_tab == 'PROFILES') ...[
              SaasFormCard(
                title: 'Effective GST profile',
                subtitle:
                    'Enter accountant-approved applicability and reporting rules for this legal entity.',
                icon: Icons.verified_user_outlined,
                trailing: TextButton(
                  onPressed: () => setState(
                    () => _profileFormExpanded = !_profileFormExpanded,
                  ),
                  child: Text(_profileFormExpanded ? 'Hide' : 'Show'),
                ),
                child: !_profileFormExpanded
                    ? Text(
                        'Tap Show to configure the effective GST profile for this legal entity.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Seller GSTIN',
                                  controller: _sellerGstin,
                                  mono: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasField(
                                  label: 'Registered legal name',
                                  controller: _legalName,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Trade name',
                                  controller: _tradeName,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasField(
                                  label: 'Address line 1',
                                  controller: _addr1,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Address line 2',
                                  controller: _addr2,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasField(
                                  label: 'City / location',
                                  controller: _city,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'GST state code',
                                  controller: _stateCode,
                                  mono: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasField(
                                  label: 'PIN code',
                                  controller: _pinCode,
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
                                  label: 'Approved e-way bill threshold (INR)',
                                  controller: _ewayThreshold,
                                  mono: true,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
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
                              Expanded(
                                child: DatePickField(
                                  label: 'Effective from',
                                  controller: _effectiveFrom,
                                ),
                              ),
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
                            onChanged: (v) =>
                                setState(() => _enableEinvoice = v),
                          ),
                          SaasCheckRow(
                            label: 'Require IRN for registered customers',
                            value: _requireIrnForRegistered,
                            onChanged: (v) =>
                                setState(() => _requireIrnForRegistered = v),
                          ),
                          SaasCheckRow(
                            label: 'Enable threshold-based e-way bill control',
                            value: _enableThresholdEway,
                            onChanged: (v) =>
                                setState(() => _enableThresholdEway = v),
                          ),
                          const SizedBox(height: 14),
                          RoyalGoldButton(
                            label: 'Save draft profile',
                            busy: _busy,
                            onPressed: _busy ? null : _saveGstProfile,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'GST profiles',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 92))
              else if (fProfs.isEmpty)
                const SaasEmptyBox('No GST profile configured.')
              else
                for (final p in fProfs)
                  LuxuryRecordCard(
                    enablePdfDownload: false,
                    icon: Icons.verified_user_outlined,
                    code: '${p['sellerGstin'] ?? 'GSTIN'}',
                    status: '${p['state'] ?? 'DRAFT'}',
                    onTap: () => _openProfileLifecycleSheet(p),
                    lines: [
                      ('Legal Name', '${p['registeredLegalName'] ?? ''}'),
                      (
                        'State / PIN',
                        '${p['stateCode'] ?? ''} · ${p['postalCode'] ?? ''}',
                      ),
                    ],
                    amountLabel: 'Effective From',
                    amountValue: fmtDate('${p['effectiveFrom'] ?? ''}'),
                    actions: [
                      GoldButton(
                        label: 'Manage Profile',
                        compact: true,
                        onPressed: () => _openProfileLifecycleSheet(p),
                      ),
                    ],
                  ),
            ]

            // TAB 2: PREPARE PROVIDER SUBMISSION & REGISTRATION/CANCELLATION/RECOVERY (`image-42..43.png`)
            else ...[
              SaasFormCard(
                title: 'Prepare provider submission',
                icon: Icons.local_shipping_outlined,
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _subFormExpanded = !_subFormExpanded),
                  child: Text(_subFormExpanded ? 'Hide' : 'Show'),
                ),
                child: !_subFormExpanded
                    ? Text(
                        'Tap Show to prepare an E-invoice / IRN or E-way bill submission.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
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
                            options: gstConns.isNotEmpty
                                ? gstConns
                                : _lk.connections,
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
                                  options: _lk.seriesFor(
                                    const ['INVOICE', 'SALES'],
                                  ),
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
                          const SizedBox(height: 14),
                          RoyalGoldButton(
                            label: 'Prepare & queue',
                            busy: _busy,
                            onPressed: _busy ? null : _prepareSubmission,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'Registration, cancellation & recovery',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 92))
              else if (fSubs.isEmpty)
                const SaasEmptyBox('No GST submission prepared.')
              else
                for (final s in fSubs)
                  LuxuryRecordCard(
                    icon: Icons.verified_user_outlined,
                    code:
                        '${s['irn'] ?? s['ewayBillNumber'] ?? shortId('${s['id']}')}',
                    status: '${s['state'] ?? 'QUEUED'}',
                    onTap: () => _openSubmissionLifecycleSheet(s),
                    lines: [
                      (
                        'Document Kind',
                        '${s['documentKind'] ?? 'EINVOICE_IRN'}',
                      ),
                      if ('${s['placeOfSupply'] ?? s['placeOfSupplyStateCode'] ?? ''}'
                          .isNotEmpty)
                        (
                          'Place of Supply',
                          '${s['placeOfSupply'] ?? s['placeOfSupplyStateCode']}',
                        ),
                      if ('${s['ackNumber'] ?? ''}'.isNotEmpty)
                        ('Ack No.', '${s['ackNumber']}'),
                    ],
                    amountLabel: 'Stage',
                    amountValue: statusLabel('${s['state'] ?? 'QUEUED'}'),
                    actions: [
                      GoldButton(
                        label: 'Manage Registration',
                        compact: true,
                        onPressed: () => _openSubmissionLifecycleSheet(s),
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
// 3. GST RETURNS & ITC REVIEW (`/gst-returns`) — `image-44..45.png`
// ---------------------------------------------------------------------------

class GstReturnsItcScreen extends StatefulWidget {
  const GstReturnsItcScreen({super.key});
  @override
  State<GstReturnsItcScreen> createState() => _GstReturnsItcScreenState();
}

class _GstReturnsItcScreenState extends State<GstReturnsItcScreen> {
  static const List<String> _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final _search = TextEditingController();
  String _tab = 'GSTR2B';
  bool _importExpanded = true;
  bool _papersExpanded = true;
  final _returnMonth = TextEditingController(text: todayIso().substring(0, 7));

  Map<String, dynamic> _ws = const {};
  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Shared governance inputs (`image-44.png`)
  final _commandReason = TextEditingController();
  final _itcEvidence = TextEditingController();

  // 1. Import & reconcile GSTR-2B (`image-44..45.png`)
  final _gstr2bJson = TextEditingController();
  String _gstr2bFileLabel = 'No file chosen';
  final _importedStmtId = TextEditingController();

  // 2. Prepare GSTR working papers (`image-44..45.png`)
  final _approvedReconId = TextEditingController();
  final _b2clThreshold = TextEditingController();
  final _mappingsJson = TextEditingController();
  String _mappingsFileLabel = 'No file chosen';

  // Working papers & approvals (`image-45.png`)
  final _selectedRecordId = TextEditingController();
  String _exportReturnType = 'GSTR1';

  @override
  void initState() {
    super.initState();
    _selectedRecordId.addListener(_onRecordSelectionChanged);
    _load();
  }

  void _onRecordSelectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selectedRecordId.removeListener(_onRecordSelectionChanged);
    for (final c in [
      _search,
      _returnMonth,
      _commandReason,
      _itcEvidence,
      _gstr2bJson,
      _importedStmtId,
      _approvedReconId,
      _b2clThreshold,
      _mappingsJson,
      _selectedRecordId,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _formatReturnMonthDisplay(String ym) {
    final parts = ym.trim().split('-');
    if (parts.length == 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null && m >= 1 && m <= 12) {
        return '${_monthNames[m - 1]}, $y';
      }
    }
    return ym;
  }

  Future<void> _pickReturnMonth() async {
    final parts = _returnMonth.text.trim().split('-');
    int selYear = int.tryParse(parts.isNotEmpty ? parts[0] : '') ??
        int.parse(todayIso().substring(0, 4));
    int selMonth = int.tryParse(parts.length > 1 ? parts[1] : '') ??
        int.parse(todayIso().substring(5, 7));

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) => AlertDialog(
            backgroundColor: Pal.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Pal.borderGold),
            ),
            title: Text(
              'Select Return Month',
              style: T.body(16, weight: FontWeight.w700, color: Pal.ink),
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () => setModal(() => selYear -= 1),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text(
                        '$selYear',
                        style: T.mono(
                          16,
                          weight: FontWeight.w700,
                          color: Pal.ink,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setModal(() => selYear += 1),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(12, (idx) {
                      final m = idx + 1;
                      final active = m == selMonth;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setModal(() => selMonth = m),
                        child: Container(
                          width: 68,
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? Pal.goldTint : Pal.bgTint,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: active ? Pal.gold : Pal.border,
                            ),
                          ),
                          child: Text(
                            _monthNames[idx].substring(0, 3),
                            style: T.body(
                              12.5,
                              weight:
                                  active ? FontWeight.w700 : FontWeight.w500,
                              color: active ? Pal.goldDeep : Pal.ink,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              GoldButton(
                label: 'Apply Month',
                compact: true,
                onPressed: () {
                  final mm = selMonth.toString().padLeft(2, '0');
                  Navigator.of(ctx).pop('$selYear-$mm');
                },
              ),
            ],
          ),
        );
      },
    );

    if (picked != null && picked != _returnMonth.text.trim()) {
      setState(() => _returnMonth.text = picked);
      await _load();
    }
  }

  Future<dynamic> _postFirstLive(
    ApiClient api,
    List<String> candidatePaths,
    Map<String, dynamic> body,
  ) async {
    ApiException? lastErr;
    for (var i = 0; i < candidatePaths.length; i++) {
      try {
        return await api.post(
          candidatePaths[i],
          idempotent: true,
          body: body,
        );
      } on ApiException catch (e) {
        lastErr = e;
        if (e.status == 404 && i + 1 < candidatePaths.length) {
          continue;
        }
        rethrow;
      }
    }
    throw lastErr ?? ApiException('HTTP_ERROR', 'Request failed.');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ym = _returnMonth.text.trim();
      final d = await context.read<ApiClient>().get(
        '/gst-returns',
        query: {
          'returnMonth': ym,
          'period': ym,
        },
      );
      if (!mounted) return;
      setState(() => _ws = asMap(d));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _metricCount(dynamic val, [dynamic fallback]) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is List) return val.length;
    if (val is String) {
      final parsed = int.tryParse(val.trim());
      if (parsed != null) return parsed;
    }
    if (fallback != null) return _metricCount(fallback);
    return 0;
  }

  Future<void> _pasteClipboardInto(
    TextEditingController target, {
    required bool isGstr2b,
  }) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = (data?.text ?? '').trim();
    if (!mounted) return;
    if (txt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clipboard is empty. Copy JSON content first.'),
        ),
      );
      return;
    }
    setState(() {
      target.text = txt;
      final label = 'Clipboard JSON (${txt.length} chars)';
      if (isGstr2b) {
        _gstr2bFileLabel = label;
      } else {
        _mappingsFileLabel = label;
      }
    });
  }

  void _createMappingTemplate() {
    final outward = asList(
      _ws['outwardLines'] ?? _ws['postedOutwardSources'] ?? const [],
    );
    final purchases = asList(
      _ws['purchaseBookEntries'] ?? _ws['purchaseSources'] ?? const [],
    );
    final hsnOverrides = <Map<String, dynamic>>[];
    final posOverrides = <Map<String, dynamic>>[];
    final itcReversals = <Map<String, dynamic>>[];

    final seenHsn = <String>{};
    for (final line in outward) {
      final hsn = '${line['hsnCode'] ?? line['hsn'] ?? ''}'.trim();
      if (hsn.isNotEmpty && seenHsn.add(hsn)) {
        hsnOverrides.add({
          'sourceHsn': hsn,
          'reviewedHsn': hsn,
          'uqc': '${line['uqc'] ?? 'GMS'}',
        });
      }
      final pos =
          '${line['placeOfSupply'] ?? line['placeOfSupplyStateCode'] ?? ''}'
              .trim();
      final docId = '${line['documentId'] ?? line['invoiceId'] ?? ''}'.trim();
      if (pos.isNotEmpty && docId.isNotEmpty) {
        posOverrides.add({
          'documentId': docId,
          'placeOfSupplyStateCode': pos,
        });
      }
    }

    for (final entry in purchases) {
      final rev = '${entry['reversalRule'] ?? ''}'.trim();
      final docId = '${entry['id'] ?? entry['documentId'] ?? ''}'.trim();
      if (rev.isNotEmpty && docId.isNotEmpty) {
        itcReversals.add({
          'purchaseDocumentId': docId,
          'rule': rev,
        });
      }
    }

    final templateObj = <String, dynamic>{
      'schema': 'GST_WORKING_PAPER_MAPPING_V1',
      'returnMonth': _returnMonth.text.trim(),
      'hsnMappings': hsnOverrides,
      'placeOfSupplyMappings': posOverrides,
      'taxHeadAdjustments': <Map<String, dynamic>>[],
      'itcReversals': itcReversals,
    };

    setState(() {
      _mappingsJson.text =
          const JsonEncoder.withIndent('  ').convert(templateObj);
      _mappingsFileLabel = 'Template from posted sources';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mapping template generated from posted workspace sources.'),
      ),
    );
  }

  Future<void> _importGstr2b() async {
    final reason = _commandReason.text.trim();
    if (reason.isEmpty) {
      setState(
        () => _error = 'Enter Command reason before importing GSTR-2B records.',
      );
      return;
    }
    final raw = _gstr2bJson.text.trim();
    if (raw.isEmpty) {
      setState(
        () => _error =
            'Provide normalized GSTR-2B JSON records (NORMALIZED_GSTR_2B_V1).',
      );
      return;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      setState(() => _error = 'Invalid GSTR-2B JSON: ${e.message}');
      return;
    }

    final List<dynamic> records = decoded is List
        ? decoded
        : (decoded is Map && decoded['records'] is List
            ? decoded['records'] as List<dynamic>
            : <dynamic>[decoded]);

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ym = _returnMonth.text.trim();
      final evidence = _itcEvidence.text.trim();
      await _postFirstLive(
        context.read<ApiClient>(),
        const [
          '/gst-returns/gstr2b-imports',
          '/gst-returns/gstr2b/import',
          '/gst-returns/imports',
        ],
        {
          'returnMonth': ym,
          'period': ym,
          'schema': 'NORMALIZED_GSTR_2B_V1',
          'format': 'NORMALIZED_GSTR_2B_V1',
          'records': records,
          'reason': reason,
          'auditReason': reason,
          if (evidence.isNotEmpty) 'evidenceReference': evidence,
          if (evidence.isNotEmpty) 'evidence': evidence,
        },
      );
      if (!mounted) return;
      _gstr2bJson.clear();
      setState(() => _gstr2bFileLabel = 'No file chosen');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Normalized GSTR-2B records imported.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buildReconciliation() async {
    final reason = _commandReason.text.trim();
    final stmtId = _importedStmtId.text.trim();
    if (stmtId.isEmpty) {
      setState(
        () => _error = 'Select an Imported statement before building reconciliation.',
      );
      return;
    }
    if (reason.isEmpty) {
      setState(
        () => _error = 'Enter Command reason before building ITC reconciliation.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ym = _returnMonth.text.trim();
      final evidence = _itcEvidence.text.trim();
      await _postFirstLive(
        context.read<ApiClient>(),
        const [
          '/gst-returns/itc-reconciliations',
          '/gst-returns/reconciliations',
        ],
        {
          'returnMonth': ym,
          'period': ym,
          'importedStatementId': stmtId,
          'gstr2bImportId': stmtId,
          'statementId': stmtId,
          'reason': reason,
          'auditReason': reason,
          if (evidence.isNotEmpty) 'evidenceReference': evidence,
          if (evidence.isNotEmpty) 'evidence': evidence,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ITC reconciliation built cleanly.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareRevision() async {
    final reason = _commandReason.text.trim();
    if (reason.isEmpty) {
      setState(
        () => _error = 'Enter Command reason before preparing working papers.',
      );
      return;
    }

    final rawMap = _mappingsJson.text.trim();
    dynamic mappingsObj = <String, dynamic>{};
    if (rawMap.isNotEmpty) {
      try {
        mappingsObj = jsonDecode(rawMap);
      } on FormatException catch (e) {
        setState(() => _error = 'Invalid mappings JSON: ${e.message}');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ym = _returnMonth.text.trim();
      final reconId = _approvedReconId.text.trim();
      final b2cl = _b2clThreshold.text.trim();
      final evidence = _itcEvidence.text.trim();
      await _postFirstLive(
        context.read<ApiClient>(),
        const [
          '/gst-returns/working-papers',
          '/gst-returns/revisions',
        ],
        {
          'returnMonth': ym,
          'period': ym,
          if (reconId.isNotEmpty) 'itcReconciliationId': reconId,
          if (reconId.isNotEmpty) 'reconciliationId': reconId,
          if (b2cl.isNotEmpty) 'b2clThresholdInr': b2cl,
          if (b2cl.isNotEmpty) 'b2clThresholdAmount': b2cl,
          'mappings': mappingsObj,
          'reason': reason,
          'auditReason': reason,
          if (evidence.isNotEmpty) 'evidenceReference': evidence,
          if (evidence.isNotEmpty) 'evidence': evidence,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GSTR working-paper revision prepared.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approveSelectedRecord(Map<String, dynamic> rec, String kind) async {
    final reason = _commandReason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Enter Command reason before approving.');
      return;
    }
    final id = '${rec['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    final evidence = _itcEvidence.text.trim();

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final paths = kind == 'RECON'
          ? <String>[
              '/gst-returns/itc-reconciliations/$id/approve',
              '/gst-returns/reconciliations/$id/approve',
            ]
          : <String>[
              '/gst-returns/working-papers/$id/approve',
              '/gst-returns/revisions/$id/approve',
            ];
      await _postFirstLive(
        context.read<ApiClient>(),
        paths,
        {
          'reason': reason,
          'auditReason': reason,
          if (evidence.isNotEmpty) 'evidenceReference': evidence,
          if (evidence.isNotEmpty) 'evidence': evidence,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            kind == 'RECON'
                ? 'ITC reconciliation approved.'
                : 'Working-paper revision approved.',
          ),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createExportSnapshot(Map<String, dynamic> paper) async {
    final reason = _commandReason.text.trim();
    if (reason.isEmpty) {
      setState(
        () => _error = 'Enter Command reason before creating an approved export.',
      );
      return;
    }
    final id = '${paper['id'] ?? ''}'.trim();
    if (id.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _postFirstLive(
        context.read<ApiClient>(),
        [
          '/gst-returns/working-papers/$id/exports',
          '/gst-returns/exports',
        ],
        {
          'workingPaperId': id,
          'returnType': _exportReturnType,
          'returnMonth': _returnMonth.text.trim(),
          'reason': reason,
          'auditReason': reason,
          if (_itcEvidence.text.trim().isNotEmpty)
            'evidenceReference': _itcEvidence.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approved $_exportReturnType preparation snapshot created.'),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openItcLineDecisionModal(
    String reconId,
    Map<String, dynamic> line,
  ) async {
    String decision =
        '${line['decision'] ?? line['eligibility'] ?? 'ELIGIBLE'}'.toUpperCase();
    if (!const {'ELIGIBLE', 'INELIGIBLE', 'DEFERRED', 'REVERSED'}
        .contains(decision)) {
      decision = 'ELIGIBLE';
    }
    final noteCtrl = TextEditingController(
      text: '${line['reviewNote'] ?? line['evidenceReference'] ?? _itcEvidence.text}',
    );
    final lineId = '${line['id'] ?? line['lineId'] ?? ''}'.trim();
    if (lineId.isEmpty) {
      noteCtrl.dispose();
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            18,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Review ITC Eligibility Line',
                style: T.body(16, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Supplier: ${line['supplierGstin'] ?? '—'} · Doc: ${line['invoiceNumber'] ?? line['documentNumber'] ?? shortId(lineId)}',
                style: T.mono(12, color: Pal.muted),
              ),
              const SizedBox(height: 12),
              SaasDropdown(
                label: 'Eligibility decision',
                value: decision,
                options: const {
                  'ELIGIBLE': 'Eligible ITC',
                  'INELIGIBLE': 'Ineligible (Block)',
                  'DEFERRED': 'Defer to next period',
                  'REVERSED': 'Reverse ITC',
                },
                onChanged: (v) => setModal(() => decision = v),
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Evidence / review note',
                controller: noteCtrl,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              RoyalGoldButton(
                label: 'Save Line Decision',
                busy: _busy,
                onPressed: () async {
                  final reason = _commandReason.text.trim();
                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter Command reason on screen first.'),
                      ),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop();
                  setState(() => _busy = true);
                  try {
                    await _postFirstLive(
                      context.read<ApiClient>(),
                      [
                        '/gst-returns/itc-reconciliations/$reconId/lines/$lineId/decision',
                        '/gst-returns/reconciliations/$reconId/lines/$lineId/decision',
                      ],
                      {
                        'decision': decision,
                        'eligibility': decision,
                        'reason': reason,
                        'auditReason': reason,
                        if (noteCtrl.text.trim().isNotEmpty)
                          'evidenceReference': noteCtrl.text.trim(),
                        if (noteCtrl.text.trim().isNotEmpty)
                          'note': noteCtrl.text.trim(),
                      },
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ITC line decision recorded.')),
                    );
                    await _load();
                  } on ApiException catch (e) {
                    if (mounted) setState(() => _error = e.message);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
    noteCtrl.dispose();
  }

  Future<void> _downloadExportSnapshot(Map<String, dynamic> ex) async {
    final id = '${ex['id'] ?? ''}'.trim();
    if (id.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final payload = await context
          .read<ApiClient>()
          .get('/gst-returns/exports/$id/download');
      if (!mounted) return;
      final formatted = const JsonEncoder.withIndent('  ').convert(payload);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Pal.card,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.92,
          minChildSize: 0.45,
          builder: (ctx, scrollCtrl) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${ex['returnType'] ?? 'GSTR'} Approved Snapshot',
                        style: T.body(16, weight: FontWeight.w700),
                      ),
                    ),
                    GoldButton(
                      label: 'Copy JSON',
                      compact: true,
                      icon: Icons.copy_rounded,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: formatted));
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('Preparation snapshot copied to clipboard.'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Preparation snapshot only — does not represent GST portal filing acknowledgement.',
                  style: T.body(11.8, color: Pal.muted),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Pal.bgTint,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Pal.border),
                    ),
                    child: SingleChildScrollView(
                      controller: scrollCtrl,
                      child: SelectableText(
                        formatted,
                        style: T.mono(11.5, color: Pal.ink),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildJsonFileRow({
    required String fileLabel,
    required VoidCallback onChoose,
    required VoidCallback? onClear,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Pal.bgTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Pal.border),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onChoose,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Pal.borderGold),
              ),
              child: Text(
                'Choose file',
                style: T.body(
                  12,
                  weight: FontWeight.w700,
                  color: Pal.goldDeep,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fileLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(12, color: Pal.muted),
            ),
          ),
          if (onClear != null)
            InkWell(
              onTap: onClear,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Pal.muted),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = auth.tenantName.trim();
    final branchName = auth.branchName.trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final summary = asMap(_ws['summary'] ?? _ws['counts']);
    final stmts = asList(
      _ws['importedStatements'] ??
          _ws['gstr2bStatements'] ??
          _ws['gstr2bImports'],
    );
    final recons = asList(
      _ws['itcReconciliations'] ?? _ws['reconciliations'],
    );
    final papers = asList(
      _ws['workingPapers'] ?? _ws['revisions'],
    );
    final exports = asList(
      _ws['exports'] ?? _ws['exportHistory'],
    );

    final outwardCount = _metricCount(
      summary['postedOutwardLines'] ??
          _ws['postedOutwardLinesCount'] ??
          _ws['postedOutwardLines'],
    );
    final purchaseBooksCount = _metricCount(
      summary['purchaseBooks'] ??
          _ws['purchaseBookCount'] ??
          _ws['purchaseBooks'] ??
          _ws['purchaseBookLines'],
    );
    final revisionsCount = _metricCount(
      summary['workingPaperRevisions'] ?? _ws['workingPaperRevisionsCount'],
      papers.length,
    );

    final stmtOpts = stmts
        .map(
          (s) => LookupOption(
            id: '${s['id']}',
            label:
                '${s['returnMonth'] ?? _returnMonth.text} · ${s['state'] ?? 'IMPORTED'} · ${shortId('${s['id']}')}',
            raw: s,
          ),
        )
        .toList();

    final reconOpts = recons
        .map(
          (r) => LookupOption(
            id: '${r['id']}',
            label:
                '${r['state'] ?? 'DRAFT'} · ${r['returnMonth'] ?? _returnMonth.text} · ${shortId('${r['id']}')}',
            raw: r,
          ),
        )
        .toList();

    final combinedApprovalOpts = <LookupOption>[
      for (final p in papers)
        LookupOption(
          id: 'PAPER:${p['id']}',
          label:
              'Working Paper Rev ${p['revisionNumber'] ?? 1} · ${p['state'] ?? 'DRAFT'} (${p['returnMonth'] ?? _returnMonth.text})',
          raw: p,
        ),
      for (final r in recons)
        LookupOption(
          id: 'RECON:${r['id']}',
          label:
              'ITC Reconciliation · ${r['state'] ?? 'DRAFT'} · ${shortId('${r['id']}')}',
          raw: r,
        ),
    ];

    Map<String, dynamic>? selectedApprovalRec;
    String selectedApprovalKind = '';
    final selVal = _selectedRecordId.text.trim();
    if (selVal.startsWith('PAPER:')) {
      final targetId = selVal.substring(6);
      selectedApprovalKind = 'PAPER';
      for (final p in papers) {
        if ('${p['id']}' == targetId) {
          selectedApprovalRec = p;
          break;
        }
      }
    } else if (selVal.startsWith('RECON:')) {
      final targetId = selVal.substring(6);
      selectedApprovalKind = 'RECON';
      for (final r in recons) {
        if ('${r['id']}' == targetId) {
          selectedApprovalRec = r;
          break;
        }
      }
    }

    final q = _search.text.trim().toLowerCase();
    final fStmts = stmts.where((s) {
      if (q.isEmpty) return true;
      return '${s['returnMonth'] ?? ''} ${s['id'] ?? ''} ${s['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fRecons = recons.where((r) {
      if (q.isEmpty) return true;
      return '${r['returnMonth'] ?? ''} ${r['id'] ?? ''} ${r['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fPapers = papers.where((p) {
      if (q.isEmpty) return true;
      return 'rev ${p['revisionNumber'] ?? ''} ${p['state'] ?? ''} ${p['returnMonth'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fExports = exports.where((ex) {
      if (q.isEmpty) return true;
      return '${ex['returnType'] ?? ''} ${ex['state'] ?? ''} ${ex['id'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'GST Returns & ITC Review',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.description_outlined,
      searchController: _search,
      searchHint: 'Search statements, reconciliations, revisions, exports...',
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
          ('GSTR2B', '1. GSTR-2B & ITC (${stmts.length})'),
          ('PAPERS', '2. Working Papers (${papers.length})'),
          ('APPROVALS', 'Approvals & Exports (${exports.length})'),
        ],
      ),
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

            // Hero Header Card + `Return month` selector (`image-44.png`)
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
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'GST Returns & ITC Review',
                          style: T.body(
                            16,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Entity-wide GSTR-1 and GSTR-3B working papers, authorized GSTR-2B imports, and evidence-backed eligibility review.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Return month',
                    style: T.body(
                      11.8,
                      weight: FontWeight.w600,
                      color: Pal.muted,
                    ),
                  ),
                  const SizedBox(height: 5),
                  InkWell(
                    borderRadius: BorderRadius.circular(11),
                    onTap: _pickReturnMonth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: Pal.bgTint,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: Pal.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatReturnMonthDisplay(_returnMonth.text),
                              style: T.body(
                                13.5,
                                weight: FontWeight.w600,
                                color: Pal.ink,
                              ),
                            ),
                          ),
                          Text(
                            _returnMonth.text.trim(),
                            style: T.mono(11.5, color: Pal.muted),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 16,
                            color: Pal.goldDeep,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 3 KPI Cards (`POSTED OUTWARD LINES`, `PURCHASE BOOKS`, `WORKING-PAPER REVISIONS` — `image-44.png`)
            SaasKpiGrid(
              items: [
                (label: 'POSTED OUTWARD LINES', value: '$outwardCount'),
                (label: 'PURCHASE BOOKS', value: '$purchaseBooksCount'),
                (label: 'WORKING-PAPER REVISIONS', value: '$revisionsCount'),
              ],
            ),

            const SizedBox(height: 12),

            // Shared `Command reason` & `ITC review evidence / reference` (`image-44.png`)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasField(
                    label: 'Command reason',
                    controller: _commandReason,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'ITC review evidence / reference',
                    controller: _itcEvidence,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // TAB 1: `1. Import & reconcile GSTR-2B` (`image-44..45.png`)
            if (_tab == 'GSTR2B') ...[
              SaasFormCard(
                title: '1. Import & reconcile GSTR-2B',
                subtitle:
                    'Use authorized records normalized to NORMALIZED_GSTR_2B_V1. The source JSON format and field definitions are in the return runbook.',
                icon: Icons.fact_check_outlined,
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _importExpanded = !_importExpanded),
                  child: Text(_importExpanded ? 'Hide' : 'Show'),
                ),
                child: !_importExpanded
                    ? Text(
                        'Tap Show to import normalized GSTR-2B records or build an ITC reconciliation.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildJsonFileRow(
                            fileLabel: _gstr2bFileLabel,
                            onChoose: () => _pasteClipboardInto(
                              _gstr2bJson,
                              isGstr2b: true,
                            ),
                            onClear: _gstr2bJson.text.isEmpty
                                ? null
                                : () => setState(() {
                                      _gstr2bJson.clear();
                                      _gstr2bFileLabel = 'No file chosen';
                                    }),
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label: 'Normalized GSTR-2B records',
                            controller: _gstr2bJson,
                            mono: true,
                            maxLines: 5,
                            onChanged: (v) {
                              final next = v.trim().isEmpty
                                  ? 'No file chosen'
                                  : 'JSON ready (${v.trim().length} chars)';
                              if (next != _gstr2bFileLabel) {
                                setState(() => _gstr2bFileLabel = next);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          RoyalGoldButton(
                            label: 'Import records',
                            busy: _busy,
                            onPressed: _busy ? null : _importGstr2b,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Divider(height: 1, color: Pal.divider),
                          ),
                          LookupField(
                            label: 'Imported statement',
                            controller: _importedStmtId,
                            options: stmtOpts,
                            hint: 'Select...',
                          ),
                          const SizedBox(height: 12),
                          RoyalGoldButton(
                            label: 'Build reconciliation',
                            icon: Icons.sync_rounded,
                            busy: _busy,
                            onPressed: _busy ? null : _buildReconciliation,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'Imported GSTR-2B statements',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 88))
              else if (fStmts.isEmpty)
                const SaasEmptyBox(
                  'No GSTR-2B statement imported for this return month.',
                )
              else
                for (final s in fStmts)
                  LuxuryRecordCard(
                    icon: Icons.upload_file_outlined,
                    code:
                        'GSTR-2B · ${s['returnMonth'] ?? _returnMonth.text} · ${shortId('${s['id']}')}',
                    status: '${s['state'] ?? 'IMPORTED'}',
                    onTap: () => setState(() {
                      _importedStmtId.text = '${s['id']}';
                      _importExpanded = true;
                    }),
                    lines: [
                      (
                        'Schema',
                        '${s['schema'] ?? s['format'] ?? 'NORMALIZED_GSTR_2B_V1'}',
                      ),
                      if ('${s['createdAt'] ?? ''}'.isNotEmpty)
                        ('Imported', fmtDateTime('${s['createdAt']}')),
                    ],
                    amountLabel: 'Records',
                    amountValue:
                        '${s['recordCount'] ?? asList(s['records']).length}',
                  ),
              if (fRecons.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'ITC reconciliations',
                  style: T.body(14.5, weight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final r in fRecons)
                  LuxuryRecordCard(
                    icon: Icons.rule_folder_outlined,
                    code: 'ITC Recon · ${shortId('${r['id']}')}',
                    status: '${r['state'] ?? 'DRAFT'}',
                    onTap: () => setState(() {
                      _selectedRecordId.text = 'RECON:${r['id']}';
                      _tab = 'APPROVALS';
                    }),
                    lines: [
                      ('Return Month', '${r['returnMonth'] ?? _returnMonth.text}'),
                      ('Lines', '${asList(r['lines']).length}'),
                    ],
                    amountLabel: 'Stage',
                    amountValue: statusLabel('${r['state'] ?? 'DRAFT'}'),
                    actions: [
                      GoldButton(
                        label: 'Review & Approve',
                        compact: true,
                        onPressed: () => setState(() {
                          _selectedRecordId.text = 'RECON:${r['id']}';
                          _tab = 'APPROVALS';
                        }),
                      ),
                    ],
                  ),
              ],
            ]

            // TAB 2: `2. Prepare GSTR working papers` (`image-44..45.png`)
            else if (_tab == 'PAPERS') ...[
              SaasFormCard(
                title: '2. Prepare GSTR working papers',
                icon: Icons.assignment_outlined,
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _papersExpanded = !_papersExpanded),
                  child: Text(_papersExpanded ? 'Hide' : 'Show'),
                ),
                child: !_papersExpanded
                    ? Text(
                        'Tap Show to prepare a GSTR-1 / GSTR-3B working-paper revision.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
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
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: _createMappingTemplate,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'Create mapping template from posted sources',
                                  style: T.body(
                                    12.8,
                                    weight: FontWeight.w700,
                                    color: Pal.goldDeep,
                                  ).copyWith(
                                    decoration: TextDecoration.underline,
                                    decorationColor: Pal.goldDeep,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildJsonFileRow(
                            fileLabel: _mappingsFileLabel,
                            onChoose: () => _pasteClipboardInto(
                              _mappingsJson,
                              isGstr2b: false,
                            ),
                            onClear: _mappingsJson.text.isEmpty
                                ? null
                                : () => setState(() {
                                      _mappingsJson.clear();
                                      _mappingsFileLabel = 'No file chosen';
                                    }),
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label:
                                'Reviewed HSN, place-of-supply, tax heads and reversal mappings',
                            controller: _mappingsJson,
                            mono: true,
                            maxLines: 5,
                            onChanged: (v) {
                              final next = v.trim().isEmpty
                                  ? 'No file chosen'
                                  : 'JSON ready (${v.trim().length} chars)';
                              if (next != _mappingsFileLabel) {
                                setState(() => _mappingsFileLabel = next);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          RoyalGoldButton(
                            label: 'Prepare revision',
                            busy: _busy,
                            onPressed: _busy ? null : _prepareRevision,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              Text(
                'Working-paper revisions',
                style: T.body(14.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Panel(child: Skeleton(height: 88))
              else if (fPapers.isEmpty)
                const SaasEmptyBox(
                  'No working-paper revisions prepared for this return month.',
                )
              else
                for (final p in fPapers)
                  LuxuryRecordCard(
                    icon: Icons.description_outlined,
                    code:
                        'Revision ${p['revisionNumber'] ?? 1} · ${p['returnMonth'] ?? _returnMonth.text}',
                    status: '${p['state'] ?? 'DRAFT'}',
                    onTap: () => setState(() {
                      _selectedRecordId.text = 'PAPER:${p['id']}';
                      _tab = 'APPROVALS';
                    }),
                    lines: [
                      if ('${p['b2clThresholdInr'] ?? p['b2clThresholdAmount'] ?? ''}'
                          .isNotEmpty)
                        (
                          'B2CL Threshold',
                          inr(p['b2clThresholdInr'] ?? p['b2clThresholdAmount']),
                        ),
                      if ('${p['createdAt'] ?? ''}'.isNotEmpty)
                        ('Prepared', fmtDateTime('${p['createdAt']}')),
                    ],
                    amountLabel: 'Stage',
                    amountValue: statusLabel('${p['state'] ?? 'DRAFT'}'),
                    actions: [
                      GoldButton(
                        label: 'Open in Approvals',
                        compact: true,
                        onPressed: () => setState(() {
                          _selectedRecordId.text = 'PAPER:${p['id']}';
                          _tab = 'APPROVALS';
                        }),
                      ),
                    ],
                  ),
            ]

            // TAB 3: `Working papers & approvals` + `Export history` (`image-45.png`)
            else ...[
              SaasFormCard(
                title: 'Working papers & approvals',
                icon: Icons.verified_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Select record',
                      controller: _selectedRecordId,
                      options: combinedApprovalOpts,
                      hint: 'Select...',
                    ),
                    if (selectedApprovalRec != null) ...[
                      const SizedBox(height: 12),
                      SaasSubBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    selectedApprovalKind == 'RECON'
                                        ? 'ITC Reconciliation · ${shortId('${selectedApprovalRec['id']}')}'
                                        : 'Working Paper Rev ${selectedApprovalRec['revisionNumber'] ?? 1}',
                                    style: T.body(
                                      13.5,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                StatusPill(
                                  '${selectedApprovalRec['state'] ?? 'DRAFT'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            if (selectedApprovalKind == 'RECON') ...[
                              Text(
                                'Lines reviewed: ${asList(selectedApprovalRec['lines']).length}',
                                style: T.body(12.2, color: Pal.muted),
                              ),
                              if (asList(selectedApprovalRec['lines'])
                                  .isNotEmpty) ...[
                                const SizedBox(height: 8),
                                for (final line
                                    in asList(selectedApprovalRec['lines'])
                                        .take(15))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(8),
                                      onTap: () => _openItcLineDecisionModal(
                                        '${selectedApprovalRec!['id']}',
                                        line,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Pal.card,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border:
                                              Border.all(color: Pal.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '${line['supplierGstin'] ?? 'GSTIN'} · ${line['invoiceNumber'] ?? line['documentNumber'] ?? shortId('${line['id']}')}',
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: T.mono(11.5),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            StatusPill(
                                              '${line['decision'] ?? line['eligibility'] ?? line['bucket'] ?? 'REVIEW'}',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                              const SizedBox(height: 10),
                              RoyalGoldButton(
                                label: 'Approve ITC reconciliation',
                                busy: _busy,
                                onPressed: _busy
                                    ? null
                                    : () => _approveSelectedRecord(
                                          selectedApprovalRec!,
                                          'RECON',
                                        ),
                              ),
                            ] else ...[
                              Text(
                                'Return month: ${selectedApprovalRec['returnMonth'] ?? _returnMonth.text}',
                                style: T.body(12.2, color: Pal.muted),
                              ),
                              const SizedBox(height: 10),
                              if ('${selectedApprovalRec['state'] ?? 'DRAFT'}'
                                      .toUpperCase() !=
                                  'APPROVED')
                                RoyalGoldButton(
                                  label: 'Approve working paper',
                                  busy: _busy,
                                  onPressed: _busy
                                      ? null
                                      : () => _approveSelectedRecord(
                                            selectedApprovalRec!,
                                            'PAPER',
                                          ),
                                )
                              else ...[
                                SaasDropdown(
                                  label: 'Export return snapshot type',
                                  value: _exportReturnType,
                                  options: const {
                                    'GSTR1': 'GSTR-1 Preparation Snapshot',
                                    'GSTR3B': 'GSTR-3B Preparation Snapshot',
                                    'PACKAGE': 'Combined GSTR Package',
                                  },
                                  onChanged: (v) =>
                                      setState(() => _exportReturnType = v),
                                ),
                                const SizedBox(height: 10),
                                RoyalGoldButton(
                                  label: 'Create approved export',
                                  icon: Icons.download_done_rounded,
                                  busy: _busy,
                                  onPressed: _busy
                                      ? null
                                      : () => _createExportSnapshot(
                                            selectedApprovalRec!,
                                          ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'Export history',
                subtitle:
                    'Downloads contain approved preparation snapshots. They do not represent GST filing acknowledgements.',
                icon: Icons.history_edu_outlined,
                child: _loading
                    ? const Skeleton(height: 76)
                    : fExports.isEmpty
                        ? const SaasEmptyBox('No approved export created.')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final ex in fExports)
                                LuxuryRecordCard(
                                  icon: Icons.download_done_rounded,
                                  code:
                                      '${ex['returnType'] ?? 'GSTR'} · ${ex['returnMonth'] ?? _returnMonth.text}',
                                  status: '${ex['state'] ?? 'APPROVED'}',
                                  onTap: () => _downloadExportSnapshot(ex),
                                  lines: [
                                    (
                                      'Snapshot Ref',
                                      shortId('${ex['id'] ?? ''}'),
                                    ),
                                    if ('${ex['createdAt'] ?? ''}'.isNotEmpty)
                                      (
                                        'Created',
                                        fmtDateTime('${ex['createdAt']}'),
                                      ),
                                  ],
                                  amountLabel: 'Snapshot',
                                  amountValue:
                                      statusLabel('${ex['state'] ?? 'READY'}'),
                                  actions: [
                                    GoldButton(
                                      label: 'Download Snapshot',
                                      compact: true,
                                      icon: Icons.download_rounded,
                                      onPressed: () =>
                                          _downloadExportSnapshot(ex),
                                    ),
                                  ],
                                ),
                            ],
                          ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. CUSTOMER MESSAGING (`/messaging`) — `image-46..47.png`
// ---------------------------------------------------------------------------

class CustomerMessagingScreen extends StatefulWidget {
  const CustomerMessagingScreen({super.key});
  @override
  State<CustomerMessagingScreen> createState() =>
      _CustomerMessagingScreenState();
}

class _CustomerMessagingScreenState extends State<CustomerMessagingScreen> {
  final _search = TextEditingController();
  String _tab = 'TEMPLATES';
  bool _tplFormExpanded = true;
  bool _consentBoxExpanded = false;

  Map<String, dynamic> _ws = const {};
  WorkspaceLookup _lk = WorkspaceLookup();
  List<LookupOption> _recipientOpts = const [];
  bool _loading = true;
  bool _findingCustomers = false;
  bool _busy = false;
  String? _error;

  // Shared governance inputs (`image-46.png`)
  final _commandReason = TextEditingController();
  final _consentEvidence = TextEditingController();

  // 1. Create an immutable template revision (`image-46..47.png`)
  final _templateKey = TextEditingController();
  String _channel = 'SMS';
  final _consentPurpose = TextEditingController();
  final _locale = TextEditingController(text: 'en_IN');
  final _variableNames = TextEditingController();
  final _providerMappingId = TextEditingController();
  final _providerTemplateRef = TextEditingController();
  final _bodyTemplate = TextEditingController();

  // 2. Compose with current consent (`image-47.png`)
  final _approvedTemplateId = TextEditingController();
  final _customerPrefix = TextEditingController();
  final _recipientContactId = TextEditingController();
  final _businessKey = TextEditingController();
  final _expireMinutes = TextEditingController(text: '60');
  final Map<String, TextEditingController> _varCtrls = {};

  // Inline customer consent update helper
  String _consentAction = 'GRANT';

  @override
  void initState() {
    super.initState();
    _approvedTemplateId.addListener(_syncTemplateVariableControllers);
    _load();
  }

  @override
  void dispose() {
    _approvedTemplateId.removeListener(_syncTemplateVariableControllers);
    for (final c in [
      _search,
      _commandReason,
      _consentEvidence,
      _templateKey,
      _consentPurpose,
      _locale,
      _variableNames,
      _providerMappingId,
      _providerTemplateRef,
      _bodyTemplate,
      _approvedTemplateId,
      _customerPrefix,
      _recipientContactId,
      _businessKey,
      _expireMinutes,
      ..._varCtrls.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _templates =>
      asList(_ws['templates'] ?? _ws['templateRevisions']);

  Map<String, dynamic>? get _selectedTemplate {
    final id = _approvedTemplateId.text.trim();
    if (id.isEmpty) return null;
    for (final t in _templates) {
      if ('${t['id']}' == id) return t;
    }
    return null;
  }

  List<String> _extractTemplateVars(Map<String, dynamic>? tpl) {
    if (tpl == null) return const [];
    final out = <String>[];
    final seen = <String>{};
    final rawVars = tpl['variableNames'] ?? tpl['variables'];
    if (rawVars is List) {
      for (final v in rawVars) {
        final s = '$v'.trim();
        if (s.isNotEmpty && seen.add(s)) out.add(s);
      }
    } else if (rawVars is String && rawVars.trim().isNotEmpty) {
      for (final part in rawVars.split(',')) {
        final s = part.trim();
        if (s.isNotEmpty && seen.add(s)) out.add(s);
      }
    }
    final body =
        '${tpl['body'] ?? tpl['bodyTemplate'] ?? tpl['plainTextBody'] ?? ''}';
    for (final m in RegExp(r'\{\{\s*([A-Za-z0-9_]+)\s*\}\}').allMatches(body)) {
      final name = (m.group(1) ?? '').trim();
      if (name.isNotEmpty && seen.add(name)) out.add(name);
    }
    return out;
  }

  void _syncTemplateVariableControllers() {
    final vars = _extractTemplateVars(_selectedTemplate);
    for (final v in vars) {
      _varCtrls.putIfAbsent(v, () => TextEditingController());
    }
    if (mounted) setState(() {});
  }

  String _renderLivePreview(Map<String, dynamic> tpl) {
    var txt =
        '${tpl['body'] ?? tpl['bodyTemplate'] ?? tpl['plainTextBody'] ?? ''}';
    for (final entry in _varCtrls.entries) {
      final val = entry.value.text.trim();
      if (val.isNotEmpty) {
        txt = txt.replaceAll(
          RegExp('\\{\\{\\s*${RegExp.escape(entry.key)}\\s*\\}\\}'),
          val,
        );
      }
    }
    return txt;
  }

  Future<dynamic> _postFirstLive(
    ApiClient api,
    List<String> candidatePaths,
    Map<String, dynamic> body,
  ) async {
    ApiException? lastErr;
    for (var i = 0; i < candidatePaths.length; i++) {
      try {
        return await api.post(
          candidatePaths[i],
          idempotent: true,
          body: body,
        );
      } on ApiException catch (e) {
        lastErr = e;
        if (e.status == 404 && i + 1 < candidatePaths.length) {
          continue;
        }
        rethrow;
      }
    }
    throw lastErr ?? ApiException('HTTP_ERROR', 'Request failed.');
  }

  LookupOption _mapRecipientOption(Map<String, dynamic> r) {
    final id =
        '${r['contactId'] ?? r['id'] ?? r['partyId'] ?? r['customerId'] ?? ''}';
    final name =
        '${r['displayName'] ?? r['customerName'] ?? r['name'] ?? asMap(r['party'])['displayName'] ?? id}';
    final code = '${r['code'] ?? r['customerCode'] ?? ''}'.trim();
    final contact =
        '${r['destination'] ?? r['phone'] ?? r['mobile'] ?? r['email'] ?? r['contactValue'] ?? ''}'
            .trim();
    final ch = '${r['channel'] ?? ''}'.trim();
    final consent =
        '${r['consentStatus'] ?? r['consentState'] ?? ''}'.trim();
    final parts = <String>[
      if (code.isNotEmpty) '$code · $name' else name,
      if (contact.isNotEmpty) contact,
      if (ch.isNotEmpty) ch,
      if (consent.isNotEmpty) consent,
    ];
    return LookupOption(id: id, label: parts.join(' · '), raw: r);
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
        WorkspaceLookup.load(
          api,
          includeParties: true,
          includeIntegrations: true,
        ),
      ]);
      if (!mounted) return;
      final wsMap = asMap(res[0]);
      final lk = res[1] as WorkspaceLookup;
      final initialRecips = asList(
        wsMap['recipients'] ?? wsMap['recipientContacts'] ?? const [],
      ).map(_mapRecipientOption).where((o) => o.id.isNotEmpty).toList();

      setState(() {
        _ws = wsMap;
        _lk = lk;
        if (initialRecips.isNotEmpty) {
          _recipientOpts = initialRecips;
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _findCustomers() async {
    final prefix = _customerPrefix.text.trim();
    final tpl = _selectedTemplate;
    final tplChannel = '${tpl?['channel'] ?? ''}'.trim();
    final tplPurpose =
        '${tpl?['consentPurpose'] ?? tpl?['purpose'] ?? ''}'.trim();

    setState(() {
      _findingCustomers = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get(
        '/messaging/recipients',
        query: {
          if (prefix.isNotEmpty) 'q': prefix,
          if (prefix.isNotEmpty) 'prefix': prefix,
          if (prefix.isNotEmpty) 'search': prefix,
          if (tplChannel.isNotEmpty) 'channel': tplChannel,
          if (tplPurpose.isNotEmpty) 'consentPurpose': tplPurpose,
          if (tplPurpose.isNotEmpty) 'purpose': tplPurpose,
        },
      );
      if (!mounted) return;
      final rawList = d is List
          ? d
          : asList(
              asMap(d)['recipients'] ??
                  asMap(d)['items'] ??
                  asMap(d)['contacts'] ??
                  asMap(d)['customers'],
            );
      final opts = rawList
          .map((e) => _mapRecipientOption(asMap(e)))
          .where((o) => o.id.isNotEmpty)
          .toList();

      setState(() {
        _recipientOpts = opts;
        if (opts.length == 1) {
          _recipientContactId.text = opts.first.id;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            opts.isEmpty
                ? 'No matching customer contacts found.'
                : 'Found ${opts.length} customer contact(s).',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _findingCustomers = false);
    }
  }

  Future<void> _createDraftRevision() async {
    final key = _templateKey.text.trim();
    final purpose = _consentPurpose.text.trim();
    final body = _bodyTemplate.text.trim();
    final reason = _commandReason.text.trim();

    if (key.isEmpty || purpose.isEmpty || body.isEmpty) {
      setState(
        () => _error =
            'Template key, Exact consent purpose, and Plain-text message body are required.',
      );
      return;
    }
    if (reason.isEmpty) {
      setState(
        () => _error =
            'Enter Command reason before creating a template revision.',
      );
      return;
    }

    final vars = _variableNames.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final locale = _locale.text.trim().isEmpty ? 'en_IN' : _locale.text.trim();
    final provMapId = _providerMappingId.text.trim();
    final provRef = _providerTemplateRef.text.trim();
    final evidence = _consentEvidence.text.trim();

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _postFirstLive(
        context.read<ApiClient>(),
        const [
          '/messaging/templates',
          '/messaging/template-revisions',
        ],
        {
          'templateKey': key,
          'channel': _channel,
          'consentPurpose': purpose,
          'purpose': purpose,
          'locale': locale,
          'variableNames': vars,
          if (provMapId.isNotEmpty) 'providerConnectionId': provMapId,
          if (provMapId.isNotEmpty) 'providerMappingId': provMapId,
          if (provRef.isNotEmpty) 'providerTemplateReference': provRef,
          'body': body,
          'plainTextBody': body,
          'bodyTemplate': body,
          'reason': reason,
          'auditReason': reason,
          if (evidence.isNotEmpty) 'evidenceReference': evidence,
          if (evidence.isNotEmpty) 'consentEvidence': evidence,
        },
      );
      if (!mounted) return;
      _bodyTemplate.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Immutable draft template revision created.'),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _governTemplate(Map<String, dynamic> tpl, String action) async {
    final reason = _commandReason.text.trim();
    if (reason.isEmpty) {
      setState(
        () => _error = 'Enter Command reason before governing a template.',
      );
      return;
    }
    final id = '${tpl['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    final evidence = _consentEvidence.text.trim();

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final paths = action == 'APPROVE'
          ? <String>[
              '/messaging/templates/$id/approve',
              '/messaging/template-revisions/$id/approve',
            ]
          : <String>[
              '/messaging/templates/$id/retire',
              '/messaging/templates/$id/deactivate',
              '/messaging/templates/$id/archive',
            ];
      await _postFirstLive(
        context.read<ApiClient>(),
        paths,
        {
          'reason': reason,
          'auditReason': reason,
          if (evidence.isNotEmpty) 'evidenceReference': evidence,
          if (evidence.isNotEmpty) 'consentEvidence': evidence,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'APPROVE'
                ? 'Template revision approved.'
                : 'Template revision retired.',
          ),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _updateRecipientConsent() async {
    final reason = _commandReason.text.trim();
    final evidence = _consentEvidence.text.trim();
    final recipId = _recipientContactId.text.trim();
    final tpl = _selectedTemplate;
    final purpose =
        '${tpl?['consentPurpose'] ?? tpl?['purpose'] ?? _consentPurpose.text}'
            .trim();
    final ch = '${tpl?['channel'] ?? _channel}'.trim();

    if (recipId.isEmpty || purpose.isEmpty) {
      setState(
        () => _error =
            'Select Recipient contact and Approved template (or enter Exact consent purpose) first.',
      );
      return;
    }
    if (reason.isEmpty || evidence.isEmpty) {
      setState(
        () => _error =
            'Both Command reason and Template / customer consent evidence are required for consent updates.',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final matchedRecip = _recipientOpts.where((o) => o.id == recipId).toList();
      final partyId = matchedRecip.isNotEmpty
          ? '${matchedRecip.first.raw['partyId'] ?? matchedRecip.first.raw['customerId'] ?? asMap(matchedRecip.first.raw['party'])['id'] ?? recipId}'
              .trim()
          : recipId;
      await _postFirstLive(
        context.read<ApiClient>(),
        [
          if (partyId.isNotEmpty) '/parties/$partyId/consents',
          '/messaging/consents',
          '/messaging/recipients/$recipId/consents',
        ],
        {
          'recipientContactId': recipId,
          'contactId': recipId,
          'partyId': recipId,
          'channel': ch,
          'consentPurpose': purpose,
          'purpose': purpose,
          'state': _consentAction == 'GRANT' ? 'GRANTED' : 'WITHDRAWN',
          'action': _consentAction,
          'reason': reason,
          'auditReason': reason,
          'evidenceReference': evidence,
          'consentEvidence': evidence,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _consentAction == 'GRANT'
                ? 'Exact-purpose customer consent recorded.'
                : 'Customer consent withdrawn.',
          ),
        ),
      );
      await _findCustomers();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _composeMessage({required bool liveSend}) async {
    final tplId = _approvedTemplateId.text.trim();
    final recipId = _recipientContactId.text.trim();
    final bizKey = _businessKey.text.trim();
    final reason = _commandReason.text.trim();
    final expMin = int.tryParse(_expireMinutes.text.trim()) ?? 60;

    if (tplId.isEmpty || recipId.isEmpty || bizKey.isEmpty) {
      setState(
        () => _error =
            'Approved template, Recipient contact, and Unique business key are required.',
      );
      return;
    }
    if (expMin < 1 || expMin > 1440) {
      setState(
        () => _error = 'Expire after minutes must be between 1 and 1440.',
      );
      return;
    }
    if (reason.isEmpty) {
      setState(
        () => _error = 'Enter Command reason before capturing or sending.',
      );
      return;
    }

    final varsMap = <String, String>{};
    for (final v in _extractTemplateVars(_selectedTemplate)) {
      varsMap[v] = (_varCtrls[v]?.text ?? '').trim();
    }

    final evidence = _consentEvidence.text.trim();
    LookupOption? chosenRecip;
    for (final o in _recipientOpts) {
      if (o.id == recipId) {
        chosenRecip = o;
        break;
      }
    }
    final rawRecip = chosenRecip?.raw ?? const <String, dynamic>{};

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _postFirstLive(
        context.read<ApiClient>(),
        liveSend
            ? const [
                '/messaging/messages',
                '/messaging/messages/send',
              ]
            : const [
                '/messaging/messages',
                '/messaging/messages/test-capture',
                '/messaging/messages/capture-test',
              ],
        {
          'templateId': tplId,
          'templateRevisionId': tplId,
          'recipientContactId': recipId,
          'contactId': '${rawRecip['contactId'] ?? recipId}',
          if ('${rawRecip['partyId'] ?? rawRecip['customerId'] ?? ''}'
              .isNotEmpty)
            'partyId': '${rawRecip['partyId'] ?? rawRecip['customerId']}',
          'variables': varsMap,
          'businessKey': bizKey,
          'expireAfterMinutes': expMin,
          'mode': liveSend ? 'LIVE' : 'TEST_CAPTURE',
          'deliveryMode': liveSend ? 'LIVE' : 'TEST_CAPTURE',
          'testCapture': !liveSend,
          'reason': reason,
          'auditReason': reason,
          if (evidence.isNotEmpty) 'evidenceReference': evidence,
          if (evidence.isNotEmpty) 'consentEvidence': evidence,
        },
      );
      if (!mounted) return;
      _businessKey.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            liveSend
                ? 'Live customer message queued with verified consent.'
                : 'Test message captured — no external send performed.',
          ),
        ),
      );
      await _load();
      if (mounted) setState(() => _tab = 'HISTORY');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMessageDetailSheet(Map<String, dynamic> msg) async {
    final id = '${msg['id'] ?? ''}'.trim();
    if (id.isEmpty) return;

    Map<String, dynamic> detail = msg;
    setState(() => _busy = true);
    try {
      final res =
          await context.read<ApiClient>().get('/messaging/messages/$id');
      detail = asMap(res).isEmpty ? msg : asMap(res);
    } on ApiException {
      detail = msg;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    final attempts = asList(detail['attempts'] ?? detail['deliveryAttempts']);
    final bodyTxt =
        '${detail['renderedBody'] ?? detail['body'] ?? detail['plainTextBody'] ?? ''}';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${detail['templateKey'] ?? 'Message'} · ${detail['channel'] ?? 'SMS'}',
                      style: T.body(16, weight: FontWeight.w700),
                    ),
                  ),
                  StatusPill('${detail['state'] ?? detail['status'] ?? 'CAPTURED'}'),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Business key: ${detail['businessKey'] ?? '—'} · Mode: ${detail['mode'] ?? detail['deliveryMode'] ?? 'TEST_CAPTURE'}',
                style: T.mono(11.8, color: Pal.muted),
              ),
              if (bodyTxt.isNotEmpty) ...[
                const SizedBox(height: 12),
                SaasSubBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rendered Plain-Text Body',
                        style: T.caps(10.5, color: Pal.muted),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        bodyTxt,
                        style: T.body(13, color: Pal.ink),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Delivery Attempts (${attempts.length})',
                style: T.body(13.5, weight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if (attempts.isEmpty)
                const SaasEmptyBox(
                  'No external provider attempt executed (test capture or pending).',
                )
              else
                for (final a in attempts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SaasSubBox(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Attempt #${a['attemptNumber'] ?? 1} · ${fmtDateTime('${a['createdAt'] ?? ''}')}',
                              style: T.mono(11.5),
                            ),
                          ),
                          StatusPill('${a['outcome'] ?? a['state'] ?? 'LOGGED'}'),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = auth.tenantName.trim();
    final branchName = auth.branchName.trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final statusObj = asMap(_ws['status'] ?? _ws['capabilities']);
    final liveEnabled = (_ws['liveMessagingEnabled'] == true) ||
        (_ws['liveEnabled'] == true) ||
        (statusObj['liveMessagingEnabled'] == true) ||
        (statusObj['externalSendEnabled'] == true);
    final bannerText = '${_ws['statusMessage'] ?? statusObj['message'] ?? ''}'
            .trim()
            .isNotEmpty
        ? '${_ws['statusMessage'] ?? statusObj['message']}'.trim()
        : (liveEnabled
            ? 'Live customer messaging is enabled. Test capture is also available.'
            : 'Test capture is available. Live customer messaging is disabled.');

    final templates = _templates;
    final messages = asList(
      _ws['messages'] ?? _ws['messageHistory'] ?? _ws['dispatches'],
    ).take(200).toList();

    final messagingConns = <LookupOption>[
      for (final m in asList(_ws['providerMappings']))
        LookupOption(
          id: '${m['id']}',
          label: '${m['displayName'] ?? m['providerKey'] ?? shortId('${m['id']}')}',
          raw: m,
        ),
      for (final c in _lk.connections)
        if ('${c.raw['capability'] ?? ''}'.toUpperCase().isEmpty ||
            '${c.raw['capability'] ?? ''}'.toUpperCase() == 'MESSAGING')
          c,
    ];

    final approvedTplOpts = templates
        .map(
          (t) => LookupOption(
            id: '${t['id']}',
            label:
                '${t['templateKey'] ?? 'TPL'} · v${t['revisionNumber'] ?? t['version'] ?? 1} · ${t['channel'] ?? 'SMS'} · ${t['state'] ?? 'DRAFT'}',
            raw: t,
          ),
        )
        .toList();

    final recipientOptions = _recipientOpts.isNotEmpty
        ? _recipientOpts
        : _lk.parties;

    final selectedTpl = _selectedTemplate;
    final selectedVars = _extractTemplateVars(selectedTpl);

    final q = _search.text.trim().toLowerCase();
    final fTemplates = templates.where((t) {
      if (q.isEmpty) return true;
      return '${t['templateKey'] ?? ''} ${t['channel'] ?? ''} ${t['consentPurpose'] ?? ''} ${t['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final fMessages = messages.where((m) {
      if (q.isEmpty) return true;
      return '${m['templateKey'] ?? ''} ${m['channel'] ?? ''} ${m['businessKey'] ?? ''} ${m['state'] ?? ''} ${asMap(m['party'])['displayName'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Customer Messaging',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.chat_bubble_outline_rounded,
      searchController: _search,
      searchHint: 'Search templates, consent purpose or message history...',
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
          ('TEMPLATES', 'Templates (${templates.length})'),
          ('COMPOSE', 'Compose'),
          ('HISTORY', 'Message History (${messages.length})'),
        ],
      ),
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

            // Hero Header Card + `Refresh status` + Capability Banner (`image-46.png`)
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Customer Messaging',
                              style: T.body(
                                16,
                                weight: FontWeight.w700,
                                color: Pal.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Approved plain-text templates, exact-purpose consent and traceable delivery attempts.',
                              style: T.body(12.2, color: Pal.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _loading ? null : _load,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          side: const BorderSide(color: Pal.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Refresh status',
                          style: T.body(
                            12,
                            weight: FontWeight.w600,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Pal.goldTint,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Pal.borderGold),
                    ),
                    child: Text(
                      bannerText,
                      style: T.body(
                        12.4,
                        weight: FontWeight.w600,
                        color: Pal.goldDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Shared `Command reason` & `Template / customer consent evidence` (`image-46.png`)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasField(
                    label: 'Command reason',
                    controller: _commandReason,
                  ),
                  const SizedBox(height: 10),
                  SaasField(
                    label: 'Template / customer consent evidence',
                    controller: _consentEvidence,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // TAB 1: `Create an immutable template revision` + `Template governance` (`image-46..47.png`)
            if (_tab == 'TEMPLATES') ...[
              SaasFormCard(
                title: 'Create an immutable template revision',
                icon: Icons.mark_chat_read_outlined,
                trailing: TextButton(
                  onPressed: () =>
                      setState(() => _tplFormExpanded = !_tplFormExpanded),
                  child: Text(_tplFormExpanded ? 'Hide' : 'Show'),
                ),
                child: !_tplFormExpanded
                    ? Text(
                        'Tap Show to create a new plain-text template revision.',
                        style: T.body(12.2, color: Pal.muted),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Template key',
                                  controller: _templateKey,
                                  mono: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasDropdown(
                                  label: 'Channel',
                                  value: _channel,
                                  options: const {
                                    'SMS': 'SMS',
                                    'WHATSAPP': 'WhatsApp',
                                    'EMAIL': 'Email',
                                  },
                                  onChanged: (v) =>
                                      setState(() => _channel = v),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label: 'Exact consent purpose',
                            controller: _consentPurpose,
                            mono: true,
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: SaasField(
                                  label: 'Locale',
                                  controller: _locale,
                                  mono: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: SaasField(
                                  label: 'Variable names (comma separated)',
                                  controller: _variableNames,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          LookupField(
                            label: 'Provider mapping (optional for test)',
                            controller: _providerMappingId,
                            options: messagingConns,
                            hint: 'Select...',
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label: 'Provider template reference',
                            controller: _providerTemplateRef,
                            mono: true,
                          ),
                          const SizedBox(height: 10),
                          SaasField(
                            label:
                                'Plain-text message body · use {{variableName}}',
                            controller: _bodyTemplate,
                            maxLines: 4,
                          ),
                          const SizedBox(height: 14),
                          RoyalGoldButton(
                            label: 'Create draft revision',
                            busy: _busy,
                            onPressed: _busy ? null : _createDraftRevision,
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 14),
              SaasFormCard(
                title: 'Template governance',
                subtitle:
                    'Content cannot change after creation. Create a new revision for changes. Approval requires another user.',
                icon: Icons.gavel_rounded,
                child: _loading
                    ? const Skeleton(height: 76)
                    : fTemplates.isEmpty
                        ? const SaasEmptyBox(
                            'No template revisions created in this workspace yet.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final t in fTemplates)
                                LuxuryRecordCard(
                                  icon: Icons.article_outlined,
                                  code:
                                      '${t['templateKey'] ?? 'TEMPLATE'} · v${t['revisionNumber'] ?? t['version'] ?? 1}',
                                  status: '${t['state'] ?? 'DRAFT'}',
                                  lines: [
                                    (
                                      'Channel / Locale',
                                      '${t['channel'] ?? 'SMS'} · ${t['locale'] ?? 'en_IN'}',
                                    ),
                                    (
                                      'Consent Purpose',
                                      '${t['consentPurpose'] ?? t['purpose'] ?? '—'}',
                                    ),
                                    if ('${t['body'] ?? t['plainTextBody'] ?? ''}'
                                        .isNotEmpty)
                                      (
                                        'Body',
                                        '${t['body'] ?? t['plainTextBody']}',
                                      ),
                                  ],
                                  amountLabel: 'Stage',
                                  amountValue:
                                      statusLabel('${t['state'] ?? 'DRAFT'}'),
                                  actions: [
                                    if ('${t['state'] ?? 'DRAFT'}'
                                            .toUpperCase() ==
                                        'DRAFT')
                                      GoldButton(
                                        label: 'Approve',
                                        compact: true,
                                        onPressed: _busy
                                            ? null
                                            : () =>
                                                _governTemplate(t, 'APPROVE'),
                                      ),
                                    if ('${t['state'] ?? ''}'.toUpperCase() !=
                                        'RETIRED')
                                      OutlinedButton(
                                        onPressed: _busy
                                            ? null
                                            : () =>
                                                _governTemplate(t, 'RETIRE'),
                                        child: const Text('Retire'),
                                      ),
                                  ],
                                ),
                            ],
                          ),
              ),
            ]

            // TAB 2: `Compose with current consent` (`image-47.png`)
            else if (_tab == 'COMPOSE') ...[
              SaasFormCard(
                title: 'Compose with current consent',
                icon: Icons.send_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LookupField(
                      label: 'Approved template',
                      controller: _approvedTemplateId,
                      options: approvedTplOpts,
                      hint: 'Select...',
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Customer name or code prefix',
                      controller: _customerPrefix,
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GoldButton(
                        label: 'Find customers',
                        busy: _findingCustomers,
                        icon: Icons.person_search_outlined,
                        onPressed: _findingCustomers ? null : _findCustomers,
                      ),
                    ),
                    const SizedBox(height: 10),
                    LookupField(
                      label: 'Recipient contact',
                      controller: _recipientContactId,
                      options: recipientOptions,
                      hint: 'Select...',
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(
                          () => _consentBoxExpanded = !_consentBoxExpanded,
                        ),
                        icon: Icon(
                          _consentBoxExpanded
                              ? Icons.expand_less_rounded
                              : Icons.verified_user_outlined,
                          size: 16,
                        ),
                        label: Text(
                          _consentBoxExpanded
                              ? 'Hide customer consent update'
                              : 'Record / update customer consent',
                        ),
                      ),
                    ),
                    if (_consentBoxExpanded) ...[
                      SaasSubBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SaasDropdown(
                              label: 'Consent state command',
                              value: _consentAction,
                              options: const {
                                'GRANT': 'Grant exact-purpose consent',
                                'WITHDRAW': 'Withdraw consent',
                              },
                              onChanged: (v) =>
                                  setState(() => _consentAction = v),
                            ),
                            const SizedBox(height: 10),
                            GoldButton(
                              label: 'Apply Consent Record',
                              compact: true,
                              busy: _busy,
                              onPressed:
                                  _busy ? null : _updateRecipientConsent,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (selectedVars.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SaasSubBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Template Variables',
                              style: T.body(12.5, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            for (final vName in selectedVars) ...[
                              SaasField(
                                label: '{{$vName}}',
                                controller: _varCtrls[vName]!,
                                onChanged: (_) => setState(() {}),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (selectedTpl != null) ...[
                              Text(
                                'Plain-text preview',
                                style: T.caps(10.5, color: Pal.muted),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _renderLivePreview(selectedTpl),
                                style: T.body(12.2, color: Pal.ink),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    SaasField(
                      label:
                          'Unique business key (use separate test/live keys)',
                      controller: _businessKey,
                      mono: true,
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Expire after minutes (1–1440)',
                      controller: _expireMinutes,
                      mono: true,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                    RoyalGoldButton(
                      label: 'Capture test · no external send',
                      busy: _busy,
                      onPressed: _busy
                          ? null
                          : () => _composeMessage(liveSend: false),
                    ),
                    if (liveEnabled) ...[
                      const SizedBox(height: 10),
                      GoldButton(
                        label: 'Send live message',
                        busy: _busy,
                        icon: Icons.send_rounded,
                        onPressed: _busy
                            ? null
                            : () => _composeMessage(liveSend: true),
                      ),
                    ],
                  ],
                ),
              ),
            ]

            // TAB 3: `Message history · latest 200` (`image-47.png`)
            else ...[
              SaasFormCard(
                title: 'Message history · latest 200',
                icon: Icons.history_rounded,
                child: _loading
                    ? const Skeleton(height: 88)
                    : fMessages.isEmpty
                        ? const SaasEmptyBox(
                            'No customer messages recorded yet.',
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final m in fMessages)
                                LuxuryRecordCard(
                                  icon: Icons.chat_bubble_outline_rounded,
                                  code:
                                      '${m['templateKey'] ?? shortId('${m['id']}')} · ${m['channel'] ?? 'SMS'}',
                                  status:
                                      '${m['state'] ?? m['status'] ?? 'CAPTURED'}',
                                  onTap: () => _openMessageDetailSheet(m),
                                  lines: [
                                    if ('${m['recipientDisplay'] ?? asMap(m['party'])['displayName'] ?? m['destination'] ?? ''}'
                                        .isNotEmpty)
                                      (
                                        'Recipient',
                                        '${m['recipientDisplay'] ?? asMap(m['party'])['displayName'] ?? m['destination']}',
                                      ),
                                    if ('${m['businessKey'] ?? ''}'.isNotEmpty)
                                      ('Business Key', '${m['businessKey']}'),
                                    if ('${m['createdAt'] ?? ''}'.isNotEmpty)
                                      (
                                        'Recorded',
                                        fmtDateTime('${m['createdAt']}'),
                                      ),
                                  ],
                                  amountLabel: 'Mode',
                                  amountValue:
                                      '${m['mode'] ?? m['deliveryMode'] ?? 'TEST'}',
                                ),
                            ],
                          ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. GST E-INVOICES & BILLS — Document Templates & Print Rendering (`image-48.png`)
// ---------------------------------------------------------------------------

class GstEInvoicesBillsScreen extends StatefulWidget {
  const GstEInvoicesBillsScreen({
    super.key,
    this.pageTitle = 'GST E-Invoices & Bills',
  });

  final String pageTitle;

  @override
  State<GstEInvoicesBillsScreen> createState() =>
      _GstEInvoicesBillsScreenState();
}


class _GstEInvoicesBillsScreenState extends State<GstEInvoicesBillsScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _templates = [];
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _showCreate = false;
  bool _showTemplateKeyOverride = false;
  Map<String, dynamic>? _renderedPreview;

  // Generate / Preview Document (`image-48.png`)
  String _sourceType = 'SALES_INVOICE';
  final _sourceId = TextEditingController();
  final _renderTemplateKey = TextEditingController();

  // Register Document Template (`POST /documents/templates`)
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
    for (final c in [
      _search,
      _sourceId,
      _renderTemplateKey,
      _tmplKey,
      _tmplName,
      _tmplBody,
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
        api.get('/documents/templates'),
        WorkspaceLookup.load(api, includeParties: false, includeSales: true),
      ]);
      if (!mounted) return;
      setState(() {
        _templates = asList(res[0], keys: const ['templates', 'items', 'rows']);
        _lk = res[1] as WorkspaceLookup;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openRenderedSnapshotSheet(Map<String, dynamic> snap) async {
    final htmlOrText =
        '${snap['renderedHtml'] ?? snap['html'] ?? snap['renderedContent'] ?? snap['content'] ?? const JsonEncoder.withIndent('  ').convert(snap)}';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.94,
        minChildSize: 0.45,
        builder: (ctx, scrollCtrl) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Print Snapshot · ${snap['documentNumber'] ?? _sourceType}',
                      style: T.body(15.8, weight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  GoldButton(
                    label: 'Download PDF',
                    compact: true,
                    icon: Icons.download_rounded,
                    onPressed: () {
                      final docNum =
                          '${snap['documentNumber'] ?? shortId('${snap['id'] ?? _sourceId.text}')}';
                      final plainLines = htmlOrText
                          .replaceAll(RegExp(r'<[^>]+>'), ' ')
                          .replaceAll('&nbsp;', ' ')
                          .replaceAll('&amp;', '&')
                          .split('\n')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .take(40)
                          .toList();
                      ErpPdfExporter.downloadSpec(
                        context,
                        renderedHtml:
                            htmlOrText.contains('<') ? htmlOrText : null,
                        spec: PdfDocumentSpec(
                          documentType: humanize(_sourceType).toUpperCase(),
                          documentNumber: docNum,
                          title: 'Official Rendered $_sourceType ($docNum)',
                          status:
                              'Layout ${snap['layoutType'] ?? snap['layout'] ?? 'A4'}',
                          metaPairs: [
                            ('Document Type', humanize(_sourceType)),
                            ('Document #', docNum),
                            (
                              'Layout',
                              '${snap['layoutType'] ?? snap['layout'] ?? 'A4'}',
                            ),
                            ('Reprint #', '${snap['reprintCount'] ?? 0}'),
                          ],
                          columns: const [
                            PdfTableColumn('Rendered Document Line', flex: 1),
                          ],
                          rows: [
                            for (final pl in plainLines) [pl],
                          ],
                        ),
                      );
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      DeviceBridge.printHtmlDocument(
                        html: htmlOrText.contains('<')
                            ? htmlOrText
                            : '<pre style="font-family:monospace;padding:24px;">$htmlOrText</pre>',
                        jobName:
                            '${snap['documentNumber'] ?? _sourceType}',
                      );
                    },
                    icon: const Icon(Icons.print_outlined, size: 16),
                    label: const Text('Print / Save PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: htmlOrText));
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Rendered print output copied to clipboard.',
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copy'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Layout: ${snap['layoutType'] ?? snap['layout'] ?? 'A4'} · Reprint #${snap['reprintCount'] ?? 0} · Hash: ${shortId('${snap['contentHash'] ?? snap['snapshotHash'] ?? ''}')}',
                style: T.mono(11.5, color: Pal.muted),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Pal.bgTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Pal.border),
                  ),
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    child: SelectableText(
                      htmlOrText,
                      style: T.mono(11.5, color: Pal.ink),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renderDoc() async {
    final srcId = _sourceId.text.trim();
    if (srcId.isEmpty) {
      setState(
        () => _error =
            'Provide Document Source UUID (e.g. Sales Invoice ID) before rendering.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().post(
        '/documents/render',
        idempotent: true,
        body: {
          'sourceType': _sourceType,
          'documentType': _sourceType,
          'sourceId': srcId,
          if (_renderTemplateKey.text.trim().isNotEmpty)
            'templateKey': _renderTemplateKey.text.trim().toUpperCase(),
        },
      );
      if (!mounted) return;
      final previewMap = asMap(res);
      setState(() => _renderedPreview = previewMap);
      await _openRenderedSnapshotSheet(previewMap);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createTemplate() async {
    final cleanKey = _tmplKey.text
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9_]'), '_');
    if (cleanKey.length < 3 ||
        _tmplName.text.trim().length < 3 ||
        _tmplBody.text.trim().length < 10) {
      setState(
        () => _error =
            'Enter Template Key (3+ chars), Name, and Print Template Body (10+ chars).',
      );
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
          'templateKey': cleanKey,
          'name': _tmplName.text.trim(),
          'layoutType': _layoutType,
          'layout': _layoutType,
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
        const SnackBar(
          content: Text('Immutable document template version registered.'),
        ),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _governTemplateState(
    Map<String, dynamic> tmpl,
    String action,
  ) async {
    final id = '${tmpl['id'] ?? ''}'.trim();
    if (id.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/documents/templates/$id/$action',
        idempotent: true,
        body: const {},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Document template $action completed.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = auth.tenantName.trim();
    final branchName = auth.branchName.trim();
    final workspaceSub = [
      if (tenantName.isNotEmpty) tenantName,
      if (branchName.isNotEmpty) branchName,
    ].join(' · ');

    final q = _search.text.trim().toLowerCase();
    final fTemplates = _templates.where((t) {
      if (q.isEmpty) return true;
      return '${t['templateKey'] ?? ''} ${t['name'] ?? ''} ${t['layout'] ?? t['layoutType'] ?? ''} ${t['state'] ?? ''}'
          .toLowerCase()
          .contains(q);
    }).toList();

    final sourceOptions = _sourceType == 'SALES_INVOICE'
        ? _lk.invoices
        : (_sourceType == 'PROFORMA_ESTIMATE' ? _lk.estimates : const <LookupOption>[]);

    return LuxuryModuleScaffold(
      title: widget.pageTitle,
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
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
      floatingActionButton: GoldAddFab(
        icon: _showCreate ? Icons.close_rounded : Icons.add_rounded,
        tooltip: _showCreate ? 'Close Form' : 'Register Document Template',
        onPressed: () => setState(() => _showCreate = !_showCreate),
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 88),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Hero Header Card (`Document Templates and Print Rendering` — image-48.png)
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
                    children: [
                      const Icon(
                        Icons.print_outlined,
                        size: 20,
                        color: Pal.gold,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Document Templates and Print Rendering',
                          style: T.body(
                            16,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Immutable document versioning, legal print snapshots, A4 and Thermal roll print layouts.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Optional New Template Form (toggled via + FAB)
            if (_showCreate) ...[
              SaasFormCard(
                title: 'Register document template',
                subtitle:
                    'Register an immutable A4 or Thermal Roll print layout version.',
                icon: Icons.note_add_outlined,
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
                            label: 'Template Key',
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
                              'A4': 'A4 Legal Layout',
                              'THERMAL_ROLL': 'Thermal Roll (80mm)',
                            },
                            onChanged: (v) => setState(() => _layoutType = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Name',
                      controller: _tmplName,
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Print template body (HTML / layout markup)',
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
                    const SizedBox(height: 12),
                    RoyalGoldButton(
                      label: 'Register Template Version',
                      busy: _busy,
                      onPressed: _busy ? null : _createTemplate,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Card 1: `Generate / Preview Document` (`image-48.png`)
            SaasFormCard(
              title: 'Generate / Preview Document',
              subtitle:
                  'Provide document source UUID to render or reprint an official invoice, return note, or receipt.',
              icon: Icons.visibility_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SaasDropdown(
                    label: 'Document Type',
                    value: _sourceType,
                    options: const {
                      'SALES_INVOICE': 'Sales Invoice',
                      'CREDIT_NOTE': 'Sales Return / Credit Note',
                      'PURCHASE_RETURN': 'Purchase Return / Debit Note',
                      'SETTLEMENT_RECEIPT': 'Settlement Receipt',
                      'OLD_METAL_PURCHASE': 'Old Metal Purchase',
                      'APPROVAL_MEMO': 'Approval Memo',
                      'STOCK_TRANSFER': 'Stock Transfer',
                      'JOB_WORK_VOUCHER': 'Job Work Voucher',
                      'PARTY_STATEMENT': 'Party Statement',
                    },
                    onChanged: (v) => setState(() => _sourceType = v),
                  ),
                  const SizedBox(height: 10),
                  LookupField(
                    label: 'Document Source UUID',
                    controller: _sourceId,
                    options: sourceOptions,
                    hint: 'Document Source UUID (e.g. Sales Invoice ID)',
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => _showTemplateKeyOverride =
                            !_showTemplateKeyOverride,
                      ),
                      icon: Icon(
                        _showTemplateKeyOverride
                            ? Icons.expand_less_rounded
                            : Icons.tune_rounded,
                        size: 15,
                      ),
                      label: Text(
                        _showTemplateKeyOverride
                            ? 'Hide template key override'
                            : 'Specify template key override (optional)',
                      ),
                    ),
                  ),
                  if (_showTemplateKeyOverride) ...[
                    SaasField(
                      label: 'Template Key (optional)',
                      controller: _renderTemplateKey,
                      mono: true,
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  RoyalGoldButton(
                    label: 'Render Document',
                    icon: Icons.visibility_outlined,
                    busy: _busy,
                    onPressed: _busy ? null : _renderDoc,
                  ),
                  if (_renderedPreview != null) ...[
                    const SizedBox(height: 12),
                    SaasSubBox(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Snapshot · ${_renderedPreview!['documentNumber'] ?? _sourceType}',
                                  style: T.body(13.2, weight: FontWeight.w700),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Reprints: ${_renderedPreview!['reprintCount'] ?? 0} · Hash: ${shortId('${_renderedPreview!['contentHash'] ?? ''}')}',
                                  style: T.mono(11.5, color: Pal.muted),
                                ),
                              ],
                            ),
                          ),
                          GoldButton(
                            label: 'Open',
                            compact: true,
                            onPressed: () =>
                                _openRenderedSnapshotSheet(_renderedPreview!),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Card 2: Document Templates Table / List (`Template Key · Name · Layout · Version · State · Created` — `image-48.png`)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Pal.bgTint,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Pal.border),
              ),
              child: Text(
                'Template Key · Name · Layout · Version · State · Created',
                style: T.body(11.5, weight: FontWeight.w700, color: Pal.ink),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Panel(child: Skeleton(height: 88))
            else if (fTemplates.isEmpty)
              const SaasEmptyBox('No document templates registered yet.')
            else
              for (final t in fTemplates)
                LuxuryRecordCard(
                  icon: Icons.print_outlined,
                  code:
                      '${t['templateKey'] ?? 'TEMPLATE'} · ${t['name'] ?? ''}',
                  status: '${t['state'] ?? 'ACTIVE'}',
                  onTap: () {
                    setState(() {
                      _renderTemplateKey.text = '${t['templateKey'] ?? ''}';
                      _showTemplateKeyOverride = true;
                    });
                  },
                  lines: [
                    (
                      'Layout / Version',
                      '${t['layout'] ?? t['layoutType'] ?? 'A4'} · v${t['version'] ?? 1}',
                    ),
                    if ('${t['createdAt'] ?? ''}'.isNotEmpty)
                      ('Created', fmtDateTime('${t['createdAt']}')),
                  ],
                  amountLabel: 'Version',
                  amountValue: 'v${t['version'] ?? 1}',
                  actions: [
                    if ('${t['state'] ?? ''}'.toUpperCase() == 'DRAFT')
                      GoldButton(
                        label: 'Activate',
                        compact: true,
                        onPressed: _busy
                            ? null
                            : () => _governTemplateState(t, 'activate'),
                      ),
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _renderTemplateKey.text =
                              '${t['templateKey'] ?? ''}';
                          _showTemplateKeyOverride = true;
                        });
                      },
                      child: const Text('Use Key'),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 6. SHOWROOM HIERARCHY (`/organization`) — `image-69.png`
// ---------------------------------------------------------------------------

class ShowroomHierarchyScreen extends StatefulWidget {
  const ShowroomHierarchyScreen({super.key});
  @override
  State<ShowroomHierarchyScreen> createState() =>
      _ShowroomHierarchyScreenState();
}

class _ShowroomHierarchyScreenState extends State<ShowroomHierarchyScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _entities = [];
  bool _loading = true;
  final bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _normalizeOrganization(
    dynamic raw,
    AppState app,
  ) {
    final root = raw is Map
        ? asMap(raw['organization'] ?? raw['workspace'] ?? raw)
        : <String, dynamic>{};

    final rawEntities = raw is List
        ? asList(raw)
        : asList(root, keys: const ['legalEntities', 'entities', 'items']);
    final topBranches = raw is Map
        ? asList(root['branches'])
        : const <Map<String, dynamic>>[];

    final byId = <String, Map<String, dynamic>>{};
    for (final e in rawEntities) {
      final eid = '${e['id'] ?? e['legalEntityId'] ?? ''}'.trim();
      if (eid.isEmpty) continue;
      final branchList = <Map<String, dynamic>>[...asList(e['branches'])];
      byId[eid] = {
        ...e,
        'id': eid,
        'legalName': '${e['legalName'] ?? e['name'] ?? 'Legal Entity'}',
        'branches': branchList,
      };
    }

    // Attach sibling top-level `branches` if `/organization` returned them flat
    for (final b in topBranches) {
      final bid = '${b['id'] ?? b['branchId'] ?? ''}'.trim();
      final eid =
          '${b['legalEntityId'] ?? asMap(b['legalEntity'])['id'] ?? ''}'.trim();
      if (bid.isEmpty || eid.isEmpty) continue;
      final ent = byId.putIfAbsent(eid, () {
        final leMap = asMap(b['legalEntity']);
        return {
          'id': eid,
          'legalName':
              '${leMap['legalName'] ?? leMap['name'] ?? (app.entityName.isNotEmpty ? app.entityName : 'Legal Entity')}',
          'branches': <Map<String, dynamic>>[],
        };
      });
      final list = ent['branches'] as List<Map<String, dynamic>>;
      if (!list.any((x) => '${x['id'] ?? x['branchId']}' == bid)) {
        list.add({...b, 'id': bid});
      }
    }

    // Merge known entities & branches from active session (`AppState.options`)
    for (final opt in app.options) {
      if (opt.entityId.isEmpty) continue;
      final ent = byId.putIfAbsent(
        opt.entityId,
        () => {
          'id': opt.entityId,
          'legalName': opt.entityName.isNotEmpty
              ? opt.entityName
              : (app.tenantName.isNotEmpty ? app.tenantName : 'Legal Entity'),
          'functionalCurrency': opt.currency,
          'timezone': opt.timezone,
          'branches': <Map<String, dynamic>>[],
        },
      );
      final list = ent['branches'] as List<Map<String, dynamic>>;
      if (opt.branchId.isNotEmpty &&
          !list.any((x) => '${x['id'] ?? x['branchId']}' == opt.branchId)) {
        list.add({
          'id': opt.branchId,
          'code': opt.branchCode,
          'name': opt.branchName,
          'state': 'ACTIVE',
        });
      }
    }

    if (byId.isEmpty && app.selectedEntityId.isNotEmpty) {
      byId[app.selectedEntityId] = {
        'id': app.selectedEntityId,
        'legalName': app.entityName.isNotEmpty
            ? app.entityName
            : (app.tenantName.isNotEmpty ? app.tenantName : 'Legal Entity'),
        'functionalCurrency': app.currency,
        'timezone': app.timezone,
        'branches': <Map<String, dynamic>>[
          if (app.selectedBranchId.isNotEmpty)
            {
              'id': app.selectedBranchId,
              'code': app.branchCode,
              'name': app.branchName,
              'state': 'ACTIVE',
            },
        ],
      };
    }

    return byId.values.toList();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = context.read<AppState>();
    try {
      final d = await context
          .read<ApiClient>()
          .get('/organization', forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() => _entities = _normalizeOrganization(d, app));
    } on ApiException catch (e) {
      if (!mounted) return;
      final fallback = _normalizeOrganization(const <String, dynamic>{}, app);
      setState(() {
        if (fallback.isNotEmpty) _entities = fallback;
        _error = e.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openAddBranchModal({Map<String, dynamic>? presetEntity}) async {
    final app = context.read<AppState>();
    var availableEntities = <Map<String, dynamic>>[..._entities];
    if (availableEntities.isEmpty) {
      availableEntities = _normalizeOrganization(const <String, dynamic>{}, app);
    }
    if (availableEntities.isEmpty) {
      await _openAddEntityModal();
      return;
    }

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _AddShowroomBranchDialog(
        entities: availableEntities,
        presetEntity: presetEntity,
      ),
    );
    if (created == true && mounted) {
      await context.read<AppState>().refreshSession();
      if (mounted) {
        await _load(forceRefresh: true);
      }
    }
  }

  Future<void> _openAddEntityModal() async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _AddLegalEntityDialog(),
    );
    if (created == true && mounted) {
      await context.read<AppState>().refreshSession();
      if (mounted) {
        await _load(forceRefresh: true);
      }
    }
  }

  void _activateShowroom(
    AppState app,
    Map<String, dynamic> ent,
    Map<String, dynamic> branch,
  ) {
    final tId = app.selectedTenantId;
    if (tId.isEmpty) return;
    final bId = '${branch['id'] ?? ''}';
    final bCode = '${branch['code'] ?? ''}';
    final bName = '${branch['name'] ?? ''}';
    final eName = '${ent['legalName'] ?? ent['name'] ?? ''}';
    app.selectContextByIds(
      tenantId: tId,
      legalEntityId: '${ent['id'] ?? ''}',
      branchId: bId,
      legalEntityName: eName,
      branchDisplayName: bName,
      branchDisplayCode: bCode,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Active showroom switched to $bCode · $bName'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final workspaceSub = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    final effectiveEntities = _entities.isNotEmpty
        ? _entities
        : _normalizeOrganization(const <String, dynamic>{}, app);

    final q = _search.text.trim().toLowerCase();
    final filteredEntities = <Map<String, dynamic>>[];
    for (final e in effectiveEntities) {
      final branches = asList(e['branches']);
      if (q.isEmpty) {
        filteredEntities.add({...e, '_filteredBranches': branches});
      } else {
        final entMatch =
            '${e['legalName'] ?? e['name'] ?? ''} ${e['functionalCurrency'] ?? ''} ${e['timezone'] ?? ''}'
                .toLowerCase()
                .contains(q);
        final matchingBranches = branches.where((b) {
          return '${b['code'] ?? ''} ${b['name'] ?? ''}'
              .toLowerCase()
              .contains(q);
        }).toList();
        if (entMatch || matchingBranches.isNotEmpty) {
          filteredEntities.add({
            ...e,
            '_filteredBranches': entMatch && matchingBranches.isEmpty
                ? branches
                : matchingBranches,
          });
        }
      }
    }

    return LuxuryModuleScaffold(
      title: 'Showroom Hierarchy',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.apartment_rounded,
      searchController: _search,
      searchHint: 'Search by Branch Code, Showroom Name or Legal Entity...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: () => _load(forceRefresh: true),
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: () => _load(forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: () => _load(forceRefresh: true)),
              const SizedBox(height: 12),
            ],

            // Main `Organization Hierarchy` Card (`image-69.png` background)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(18),
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
                                : 'Bullion rates: No published rate',
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
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Organization Hierarchy',
                              style: T.body(
                                17,
                                weight: FontWeight.w800,
                                color: Pal.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Authorized legal entities, GSTIN profiles, and showroom branches.',
                              style: T.body(12.2, color: Pal.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GoldButton(
                        label: '+ Add Branch',
                        compact: true,
                        busy: _busy,
                        onPressed:
                            _busy ? null : () => _openAddBranchModal(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_loading && effectiveEntities.isEmpty)
                    const Skeleton(height: 120)
                  else if (filteredEntities.isEmpty)
                    const SaasEmptyBox(
                      'No legal entities or showroom branches match your filter.',
                    )
                  else
                    for (var idx = 0; idx < filteredEntities.length; idx++) ...[
                      if (idx > 0) const SizedBox(height: 12),
                      Builder(
                        builder: (_) {
                          final ent = filteredEntities[idx];
                          final branches = asList(ent['_filteredBranches']);
                          final ccy =
                              '${ent['functionalCurrency'] ?? ent['currency'] ?? 'INR'}'
                                  .trim();
                          final tz =
                              '${ent['timezone'] ?? 'Asia/Kolkata'}'.trim();
                          final gstin =
                              '${ent['gstin'] ?? ent['sellerGstin'] ?? ''}'
                                  .trim();

                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Pal.bgTint,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Pal.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFBF3DC),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: const Color(0xFFEBD79C),
                                        ),
                                      ),
                                      child: const Icon(
                                        Icons.apartment_rounded,
                                        size: 19,
                                        color: Pal.goldDeep,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${ent['legalName'] ?? ent['name'] ?? 'Legal Entity'}',
                                            style: T.body(
                                              15,
                                              weight: FontWeight.w800,
                                              color: Pal.ink,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              'Currency: $ccy',
                                              'Timezone: $tz',
                                              if (gstin.isNotEmpty)
                                                'GSTIN: $gstin',
                                            ].join(' · '),
                                            style: T.body(
                                              11.6,
                                              color: Pal.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (branches.isEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    child: Text(
                                      'No showroom branches created under this legal entity yet.',
                                      style: T.body(12, color: Pal.muted),
                                    ),
                                  )
                                else
                                  for (var bIdx = 0;
                                      bIdx < branches.length;
                                      bIdx++) ...[
                                    if (bIdx > 0)
                                      const SizedBox(height: 6),
                                    Builder(
                                      builder: (_) {
                                        final b = branches[bIdx];
                                        final isCurrent =
                                            app.selectedBranchId ==
                                                '${b['id']}';
                                        return InkWell(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          onTap: () =>
                                              _activateShowroom(app, ent, b),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                              horizontal: 4,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 7,
                                                  height: 7,
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Pal.gold,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                if ('${b['code'] ?? ''}'
                                                    .isNotEmpty) ...[
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        6,
                                                      ),
                                                      border: Border.all(
                                                        color: Pal.border,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${b['code']}',
                                                      style: T.mono(
                                                        11.5,
                                                        weight: FontWeight.w700,
                                                        color: Pal.ink,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                ],
                                                Expanded(
                                                  child: Text(
                                                    '${b['name'] ?? ''}',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: T.body(
                                                      13.5,
                                                      weight: isCurrent
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: Pal.ink,
                                                    ),
                                                  ),
                                                ),
                                                if (isCurrent)
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2.5,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Pal.goldTint,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                        999,
                                                      ),
                                                      border: Border.all(
                                                        color: Pal.borderGold,
                                                      ),
                                                    ),
                                                    child: Text(
                                                      'ACTIVE',
                                                      style: T.caps(
                                                        9,
                                                        color: Pal.goldDeep,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exact 1:1 `Add Showroom Branch` modal (`image-69.png`)
class _AddShowroomBranchDialog extends StatefulWidget {
  const _AddShowroomBranchDialog({
    required this.entities,
    this.presetEntity,
  });

  final List<Map<String, dynamic>> entities;
  final Map<String, dynamic>? presetEntity;

  @override
  State<_AddShowroomBranchDialog> createState() =>
      _AddShowroomBranchDialogState();
}

class _AddShowroomBranchDialogState extends State<_AddShowroomBranchDialog> {
  late String _selectedEntityId;
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _codeMissing = false;
  bool _nameMissing = false;
  String? _modalError;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedEntityId =
        '${widget.presetEntity?['id'] ?? widget.entities.first['id'] ?? ''}';
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cleanCode = _codeCtrl.text.trim().toUpperCase();
    final cleanName = _nameCtrl.text.trim();
    if (cleanCode.isEmpty || cleanName.isEmpty) {
      setState(() {
        _codeMissing = cleanCode.isEmpty;
        _nameMissing = cleanName.isEmpty;
      });
      return;
    }

    setState(() {
      _busy = true;
      _codeMissing = false;
      _nameMissing = false;
      _modalError = null;
    });

    final api = context.read<ApiClient>();
    Map<String, dynamic> activeEntity = widget.entities.first;
    for (final e in widget.entities) {
      if ('${e['id']}' == _selectedEntityId) {
        activeEntity = e;
        break;
      }
    }
    final tz = '${activeEntity['timezone'] ?? 'Asia/Kolkata'}'.trim();

    final attempts = <Future<dynamic> Function()>[
      () => api.post(
            '/organization/branches',
            idempotent: true,
            body: {
              'legalEntityId': _selectedEntityId,
              'code': cleanCode,
              'name': cleanName,
            },
          ),
      () => api.post(
            '/organization/branches',
            idempotent: true,
            body: {
              'legalEntityId': _selectedEntityId,
              'code': cleanCode,
              'name': cleanName,
              'timezone': tz.isEmpty ? 'Asia/Kolkata' : tz,
            },
          ),
      () => api.post(
            '/organization/legal-entities/$_selectedEntityId/branches',
            idempotent: true,
            body: {
              'code': cleanCode,
              'name': cleanName,
            },
          ),
    ];

    try {
      ApiException? lastErr;
      var ok = false;
      for (var i = 0; i < attempts.length; i++) {
        try {
          await attempts[i]();
          ok = true;
          break;
        } on ApiException catch (e) {
          lastErr = e;
          if ((e.status == 400 ||
                  e.status == 404 ||
                  e.status == 405 ||
                  e.status == 422) &&
              i + 1 < attempts.length) {
            continue;
          }
          rethrow;
        }
      }
      if (!ok && lastErr != null) throw lastErr;

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Showroom branch $cleanCode · $cleanName created.'),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _modalError = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var activeEntity = widget.entities.first;
    for (final e in widget.entities) {
      if ('${e['id']}' == _selectedEntityId) {
        activeEntity = e;
        break;
      }
    }
    final entityTitle =
        '${activeEntity['legalName'] ?? activeEntity['name'] ?? 'Legal Entity'}';
    final screenW = MediaQuery.sizeOf(context).width;
    final dialogW = (screenW - 32).clamp(260.0, 410.0);

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Pal.gold, width: 1.5),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Pal.danger, width: 1.3),
    );

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5EEDB),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      size: 19,
                      color: Color(0xFF8C6A14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add Showroom Branch',
                      style: T.body(
                        18.5,
                        weight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                entityTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.body(13, color: const Color(0xFF64748B)),
              ),
              const SizedBox(height: 20),
              if (_modalError != null) ...[
                ErrorBanner(_modalError!),
                const SizedBox(height: 12),
              ],
              if (widget.entities.length > 1) ...[
                SaasDropdown(
                  label: 'LEGAL ENTITY',
                  value: _selectedEntityId,
                  options: {
                    for (final e in widget.entities)
                      '${e['id']}':
                          '${e['legalName'] ?? e['name'] ?? e['id']}',
                  },
                  onChanged: (v) => setState(() => _selectedEntityId = v),
                ),
                const SizedBox(height: 14),
              ],
              Text(
                'BRANCH CODE',
                style: T.caps(10.8, color: const Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                style: T.body(14, color: const Color(0xFF0F172A)),
                onChanged: (_) {
                  if (_codeMissing) setState(() => _codeMissing = false);
                },
                decoration: InputDecoration(
                  hintText: 'e.g. A-03',
                  hintStyle: T.body(13.8, color: const Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  focusedBorder: focusedBorder,
                  errorBorder: errorBorder,
                  focusedErrorBorder: errorBorder,
                  errorText:
                      _codeMissing ? 'Please fill in this field.' : null,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'BRANCH NAME',
                style: T.caps(10.8, color: const Color(0xFF475569)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _nameCtrl,
                style: T.body(14, color: const Color(0xFF0F172A)),
                onChanged: (_) {
                  if (_nameMissing) setState(() => _nameMissing = false);
                },
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'e.g. City Centre Mall Showroom',
                  hintStyle: T.body(13.8, color: const Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  focusedBorder: focusedBorder,
                  errorBorder: errorBorder,
                  focusedErrorBorder: errorBorder,
                  errorText:
                      _nameMissing ? 'Please fill in this field.' : null,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 22, bottom: 16),
                child: Divider(height: 1, color: Color(0xFFF1F5F9)),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: T.body(
                        14,
                        weight: FontWeight.w500,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GoldButton(
                    label: 'Create Branch',
                    compact: true,
                    busy: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddLegalEntityDialog extends StatefulWidget {
  const _AddLegalEntityDialog();

  @override
  State<_AddLegalEntityDialog> createState() => _AddLegalEntityDialogState();
}

class _AddLegalEntityDialogState extends State<_AddLegalEntityDialog> {
  final _legalNameCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController(text: 'INR');
  final _tzCtrl = TextEditingController(text: 'Asia/Kolkata');
  String? _modalError;
  bool _busy = false;

  @override
  void dispose() {
    _legalNameCtrl.dispose();
    _currencyCtrl.dispose();
    _tzCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_legalNameCtrl.text.trim().length < 2) {
      setState(() => _modalError = 'Please fill in Registered Legal Name.');
      return;
    }
    setState(() {
      _busy = true;
      _modalError = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/organization/legal-entities',
        idempotent: true,
        body: {
          'legalName': _legalNameCtrl.text.trim(),
          'functionalCurrency': _currencyCtrl.text.trim().isEmpty
              ? 'INR'
              : _currencyCtrl.text.trim().toUpperCase(),
          'timezone': _tzCtrl.text.trim().isEmpty
              ? 'Asia/Kolkata'
              : _tzCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Legal entity created.')),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _modalError = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Pal.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add Legal Entity',
                style: T.body(17.5, weight: FontWeight.w800, color: Pal.ink),
              ),
              const SizedBox(height: 14),
              if (_modalError != null) ...[
                ErrorBanner(_modalError!),
                const SizedBox(height: 12),
              ],
              SaasField(
                label: 'REGISTERED LEGAL NAME',
                controller: _legalNameCtrl,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SaasField(
                      label: 'CURRENCY',
                      controller: _currencyCtrl,
                      mono: true,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SaasField(
                      label: 'TIMEZONE',
                      controller: _tzCtrl,
                      mono: true,
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1, color: Pal.divider),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  GoldButton(
                    label: 'Create Legal Entity',
                    compact: true,
                    busy: _busy,
                    onPressed: _busy ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. ACCESS CONTROL & ROLES (`/access`, `/support-grants`) — `image-70.png`
// ---------------------------------------------------------------------------

const Map<String, String> _kErpPermissionCatalog = <String, String>{
  'accounting.fiscal.approve':
      'Independently approve fiscal workflow snapshots',
  'accounting.fiscal.post':
      'Post approved opening/closing/reopening atomically',
  'accounting.fiscal.prepare': 'Prepare annual close and linked reopening',
  'accounting.fiscal.read':
      'Read entity-wide opening and fiscal-close evidence',
  'accounting.journal.create': 'Create manual journal drafts',
  'accounting.journal.post': 'Post balanced journals',
  'accounting.journal.read': 'Read ledger accounts, periods and journals',
  'accounting.journal.reverse': 'Reverse posted journals with audit reason',
  'accounting.period.manage': 'Open, lock and reopen accounting posting periods',
  'access.members.manage': 'Assign and update tenant member role scopes',
  'access.read': 'Read tenant roles, permissions and member assignments',
  'access.roles.manage': 'Create and update tenant-scoped roles and permissions',
  'approvals.memo.issue': 'Issue showroom approval memos and consignments',
  'approvals.memo.read': 'Read approval memos and open consignment items',
  'approvals.memo.settle': 'Return or convert approval memo items to sales',
  'banking.account.manage': 'Create and configure bank and settlement accounts',
  'banking.read': 'Read bank statements, clearings and reconciliations',
  'banking.reconcile': 'Import bank statements and match ledger lines',
  'chain_analytics.read': 'Read multi-branch chain performance analytics',
  'custom_orders.create': 'Book custom jewellery orders and customer advances',
  'custom_orders.manage': 'Update custom order milestones, quotes and delivery',
  'custom_orders.read': 'Read custom orders and workshop progress',
  'documents.render': 'Render and print governed showroom documents and PDFs',
  'documents.templates.manage':
      'Create, clone and publish invoice/document templates',
  'documents.templates.read': 'Read document templates and invoice profile',
  'gst_compliance.einvoice.manage':
      'Generate, cancel and reconcile e-Invoices and e-Way bills',
  'gst_compliance.read': 'Read GST registrations, HSN policies and compliance',
  'gst_returns.export': 'Generate and download GSTR-1 / GSTR-3B return exports',
  'gst_returns.prepare': 'Prepare GST return working papers and 2B matches',
  'gst_returns.read': 'Read GST return periods, filings and reconciliations',
  'integrations.manage': 'Configure webhooks, ERP connectors and API keys',
  'integrations.read': 'Read integration connectors and delivery logs',
  'inter_entity.trade.manage':
      'Create, dispatch and settle inter-entity bullion/stock trades',
  'inter_entity.trade.read': 'Read inter-entity trades and paired settlements',
  'inventory.adjust': 'Record governed stock adjustments and physical counts',
  'inventory.lot.manage': 'Create and split metal/stone inventory lots',
  'inventory.read': 'Read tagged showroom stock, lots and vault balances',
  'inventory.tag.create': 'Create and print barcoded/RFID ornament tags',
  'inventory.tag.manage': 'Update ornament tag attributes, status and location',
  'job_work.issue': 'Issue bullion and stones to karigars / workshops',
  'job_work.read': 'Read karigar job orders, balances and wastage',
  'job_work.receive': 'Receive finished ornaments and settle karigar wastage',
  'materials.manage': 'Configure metals, purity grades and item categories',
  'materials.read': 'Read metal masters, purities and making rules',
  'messaging.read': 'Read customer WhatsApp/SMS notifications and consents',
  'messaging.send': 'Dispatch transactional invoices and campaign alerts',
  'old_metal.intake.create': 'Record old gold/silver buyback melting intakes',
  'old_metal.policy.manage': 'Configure old metal purity deduction policies',
  'old_metal.read': 'Read old metal buyback registers and assay valuations',
  'organization.branch.manage': 'Create and update showroom branches',
  'organization.entity.manage':
      'Create and configure legal entities and invoice profiles',
  'organization.read': 'Read organization hierarchy, entities and branches',
  'parties.manage': 'Create and update customer, supplier and karigar profiles',
  'parties.read': 'Read party directory, KYC details and ledger balances',
  'payments.allocate': 'Allocate receipts and disbursements against open bills',
  'payments.create':
      'Record customer receipts, supplier payouts and customer refunds',
  'payments.read': 'Read showroom settlements, instruments and open items',
  'payments.reverse': 'Reverse posted settlements with governed audit reason',
  'pos_shifts.close': 'Count tender drawers and close POS cashier shifts',
  'pos_shifts.open': 'Open showroom POS cashier shifts and float balances',
  'pos_shifts.read': 'Read POS shifts, cashups and variance reports',
  'procurement.grn.post': 'Receive supplier bullion/ornament goods receipts',
  'procurement.invoice.post': 'Post supplier purchase bills and input GST',
  'procurement.order.create': 'Create supplier purchase orders',
  'procurement.read': 'Read purchase orders, GRNs and supplier bills',
  'rate_fixing.manage': 'Book and settle unfixed bullion rate-cut contracts',
  'rate_fixing.read': 'Read open bullion rate-fixing contracts and exposures',
  'rates.manage': 'Create rate books and draft showroom metal rate versions',
  'rates.publish': 'Publish live showroom gold, silver and platinum rates',
  'rates.read': 'Read live and historical showroom bullion rate boards',
  'refining.manage': 'Issue old metal lots to refinery and post assay outturn',
  'refining.read': 'Read refinery batches, melting losses and fine recovery',
  'repairs.create': 'Accept customer ornament repair jobs and estimates',
  'repairs.manage': 'Update repair workshop status, charges and delivery',
  'repairs.read': 'Read repair intake register and workshop tickets',
  'reports.accounting.read':
      'Read Trial Balance, General Ledger, Party Statement and Ageing',
  'reports.inventory.read': 'Read Stock Valuation and Gross Margin reports',
  'sales.credit_note.post': 'Create and post governed sales returns/credit notes',
  'sales.estimate.create': 'Create showroom price estimates and proforma slips',
  'sales.invoice.create': 'Create draft POS sales invoices',
  'sales.invoice.post': 'Finalize and post showroom tax invoices',
  'sales.read': 'Read showroom estimates, sales invoices and credit notes',
  'stock_transfers.dispatch': 'Create and dispatch inter-branch stock transfers',
  'stock_transfers.read': 'Read inter-branch stock transfer manifests',
  'stock_transfers.receive': 'Verify and receive incoming branch stock transfers',
  'support_grants.manage': 'Approve, revoke or expire platform support grants',
  'support_grants.read': 'Read time-limited platform support access grants',
};

class AccessControlScreen extends StatefulWidget {
  const AccessControlScreen({super.key});
  @override
  State<AccessControlScreen> createState() => _AccessControlScreenState();
}

class _AccessControlScreenState extends State<AccessControlScreen> {
  final _search = TextEditingController();
  Map<String, dynamic> _access = {};
  Map<String, dynamic> _org = {};
  List<Map<String, dynamic>> _grants = [];
  bool _loading = true;
  final bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _accessRoot {
    if (_access['workspace'] is Map) return asMap(_access['workspace']);
    if (_access['access'] is Map) return asMap(_access['access']);
    return _access;
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait<dynamic>([
        api.get('/access', forceRefresh: forceRefresh),
        api
            .get('/organization', forceRefresh: forceRefresh)
            .catchError((_) => <String, dynamic>{}),
        api
            .get('/support-grants', forceRefresh: forceRefresh)
            .catchError((_) => <String, dynamic>{}),
      ]);
      if (!mounted) return;
      setState(() {
        _access = asMap(results[0]);
        _org = asMap(results[1]);
        _grants = asList(
          results[2],
          keys: const ['grants', 'supportGrants', 'items'],
        );
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _allOrgBranches() {
    final byId = <String, Map<String, dynamic>>{};
    final orgRoot = _org['organization'] is Map
        ? asMap(_org['organization'])
        : _org;
    for (final e in asList(orgRoot, keys: const ['legalEntities', 'entities'])) {
      for (final b in asList(e['branches'])) {
        final bid = '${b['id'] ?? b['branchId'] ?? ''}'.trim();
        if (bid.isNotEmpty) byId[bid] = {...b, 'id': bid};
      }
    }
    for (final b in asList(orgRoot['branches'])) {
      final bid = '${b['id'] ?? b['branchId'] ?? ''}'.trim();
      if (bid.isNotEmpty) byId[bid] = {...b, 'id': bid};
    }
    for (final opt in context.read<AppState>().options) {
      if (opt.branchId.isNotEmpty) {
        byId.putIfAbsent(
          opt.branchId,
          () => {
            'id': opt.branchId,
            'code': opt.branchCode,
            'name': opt.branchName,
          },
        );
      }
    }
    return byId.values.toList();
  }

  String _humanizePermKey(String key) {
    if (_kErpPermissionCatalog.containsKey(key)) {
      return _kErpPermissionCatalog[key]!;
    }
    final parts = key
        .split(RegExp(r'[._:-]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'Governed workspace permission';
    if (parts.length == 1) return 'Allow ${parts.first} operations';
    final action = parts.last;
    final subject = parts.sublist(0, parts.length - 1).join(' ');
    return '${action[0].toUpperCase()}${action.substring(1)} $subject';
  }

  List<({String key, String description})> _extractPermissionCatalog() {
    final byKey = <String, String>{};

    void absorbItem(dynamic p) {
      if (p is String) {
        final k = p.trim();
        if (k.isNotEmpty) {
          byKey.putIfAbsent(k, () => _humanizePermKey(k));
        }
      } else if (p is Map) {
        final inner = p['permission'] is Map ? asMap(p['permission']) : p;
        final k =
            '${inner['key'] ?? inner['permissionKey'] ?? inner['code'] ?? inner['id'] ?? p['permissionKey'] ?? p['key'] ?? ''}'
                .trim();
        if (k.isEmpty) return;
        final desc =
            '${inner['description'] ?? inner['summary'] ?? inner['label'] ?? inner['name'] ?? p['description'] ?? ''}'
                .trim();
        if (desc.isNotEmpty && desc != k) {
          byKey[k] = desc;
        } else {
          byKey.putIfAbsent(k, () => _humanizePermKey(k));
        }
      }
    }

    void absorbCollection(dynamic raw) {
      if (raw is Iterable) {
        for (final item in raw) {
          absorbItem(item);
        }
      } else if (raw is Map) {
        for (final entry in raw.entries) {
          final k = '${entry.key}'.trim();
          final v = entry.value;
          if (k.contains('.') && (v is String || v is bool || v is Map)) {
            if (v is String && v.trim().isNotEmpty) {
              byKey[k] = v.trim();
            } else if (v is Map) {
              absorbItem({'key': k, ...v});
            } else {
              byKey.putIfAbsent(k, () => _humanizePermKey(k));
            }
          } else if (v is Iterable) {
            for (final item in v) {
              absorbItem(item);
            }
          }
        }
      }
    }

    final root = _accessRoot;
    for (final mapCandidate in [_access, root]) {
      for (final field in const [
        'permissions',
        'permissionCatalog',
        'availablePermissions',
        'allPermissions',
        'catalog',
        'permissionGroups',
      ]) {
        absorbCollection(mapCandidate[field]);
      }
    }

    final roles = asList(root, keys: const ['roles', 'tenantRoles', 'items']);
    for (final r in roles) {
      absorbCollection(r['permissions']);
      absorbCollection(r['permissionKeys']);
      absorbCollection(r['rolePermissions']);
      absorbCollection(r['grantedPermissions']);
    }

    final sessionUser = context.read<AppState>().user;
    absorbCollection(sessionUser['permissions']);
    absorbCollection(sessionUser['permissionKeys']);

    // Guarantee non-empty catalog when `/access` returns summary counts only
    if (byKey.isEmpty) {
      byKey.addAll(_kErpPermissionCatalog);
    }

    final list = [
      for (final e in byKey.entries) (key: e.key, description: e.value),
    ];
    list.sort((a, b) => a.key.compareTo(b.key));
    return list;
  }

  Set<String> _rolePermSet(Map<String, dynamic> role) {
    final out = <String>{};
    for (final field in const [
      'permissionKeys',
      'permissions',
      'rolePermissions',
      'grantedPermissions',
    ]) {
      final raw = role[field];
      if (raw is Iterable) {
        for (final p in raw) {
          if (p is String && p.trim().isNotEmpty) {
            out.add(p.trim());
          } else if (p is Map) {
            final inner = p['permission'] is Map ? asMap(p['permission']) : p;
            final k =
                '${inner['key'] ?? inner['permissionKey'] ?? inner['code'] ?? p['permissionKey'] ?? ''}'
                    .trim();
            if (k.isNotEmpty) out.add(k);
          }
        }
      }
    }
    return out;
  }

  int _rolePermCount(Map<String, dynamic> role) {
    final explicitCount = asInt(
      role['permissionCount'] ??
          asMap(role['_count'])['permissions'] ??
          asMap(role['_count'])['rolePermissions'],
    );
    if (explicitCount > 0) return explicitCount;
    return _rolePermSet(role).length;
  }

  Future<void> _openRoleModal({Map<String, dynamic>? existingRole}) async {
    final catalog = _extractPermissionCatalog();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _TenantRoleDialog(
        catalog: catalog,
        existingRole: existingRole,
        initialPermissions:
            existingRole != null ? _rolePermSet(existingRole) : const {},
      ),
    );
    if (saved == true && mounted) {
      await _load(forceRefresh: true);
    }
  }

  Future<void> _openEditMemberModal(
    Map<String, dynamic> member,
    List<Map<String, dynamic>> roles,
  ) async {
    final user = asMap(member['user']);
    final memberName =
        '${user['displayName'] ?? member['displayName'] ?? user['email'] ?? 'Member'}';
    final memberEmail = '${user['email'] ?? member['email'] ?? ''}';
    final membershipId = '${member['id'] ?? ''}'.trim();
    final branches = _allOrgBranches();

    final selRoleIds = <String>{};
    if (member['roleIds'] is Iterable) {
      for (final id in member['roleIds'] as Iterable) {
        if ('$id'.isNotEmpty) selRoleIds.add('$id');
      }
    }
    for (final r in asList(member, keys: const ['roles', 'assignments', 'roleAssignments'])) {
      final rid = '${r['roleId'] ?? asMap(r['role'])['id'] ?? r['id'] ?? ''}'.trim();
      if (rid.isNotEmpty) selRoleIds.add(rid);
    }

    final selBranchIds = <String>{};
    if (member['branchIds'] is Iterable) {
      for (final id in member['branchIds'] as Iterable) {
        if ('$id'.isNotEmpty) selBranchIds.add('$id');
      }
    }
    for (final b in asList(member, keys: const ['branches', 'branchScopes', 'scopes'])) {
      final bid = '${b['branchId'] ?? asMap(b['branch'])['id'] ?? b['id'] ?? ''}'.trim();
      if (bid.isNotEmpty) selBranchIds.add(bid);
    }
    if (selBranchIds.isEmpty) {
      for (final b in branches) {
        final bid = '${b['id'] ?? ''}'.trim();
        if (bid.isNotEmpty) selBranchIds.add(bid);
      }
    }

    final reasonCtrl = TextEditingController(
      text: 'Updated member role and showroom branch assignments.',
    );
    String? modalError;
    bool modalBusy = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> saveAssignments() async {
            if (membershipId.isEmpty) return;
            if (selRoleIds.isEmpty) {
              setModal(() => modalError = 'Select at least 1 role.');
              return;
            }
            setModal(() {
              modalBusy = true;
              modalError = null;
            });
            final api = context.read<ApiClient>();
            final rList = selRoleIds.toList();
            final bList = selBranchIds.toList();
            final payload = <String, dynamic>{
              'expectedVersion': asInt(
                member['permissionVersion'] ?? member['version'],
                fallback: 1,
              ),
              'roleIds': rList,
              'branchIds': bList,
              'assignments': [
                for (final rid in rList)
                  {
                    'roleId': rid,
                    'branchIds': bList,
                  },
              ],
              if (reasonCtrl.text.trim().isNotEmpty)
                'reason': reasonCtrl.text.trim(),
            };

            try {
              final attempts = <Future<dynamic> Function()>[
                () => api.put(
                      '/access/memberships/$membershipId/assignments',
                      idempotent: true,
                      body: payload,
                    ),
                () => api.patch(
                      '/access/memberships/$membershipId',
                      idempotent: true,
                      body: payload,
                    ),
                () => api.put(
                      '/access/memberships/$membershipId',
                      idempotent: true,
                      body: payload,
                    ),
                () => api.post(
                      '/access/memberships/$membershipId/assignments',
                      idempotent: true,
                      body: payload,
                    ),
              ];
              ApiException? lastErr;
              var succeeded = false;
              for (var i = 0; i < attempts.length; i++) {
                try {
                  await attempts[i]();
                  succeeded = true;
                  break;
                } on ApiException catch (e) {
                  lastErr = e;
                  if ((e.status == 404 || e.status == 405) &&
                      i + 1 < attempts.length) {
                    continue;
                  }
                  rethrow;
                }
              }
              if (!succeeded && lastErr != null) throw lastErr;

              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Updated assignments for $memberName.'),
                ),
              );
              await _load();
            } on ApiException catch (e) {
              if (ctx.mounted) {
                setModal(() {
                  modalBusy = false;
                  modalError = e.message;
                });
              }
            }
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            maxChildSize: 0.94,
            minChildSize: 0.5,
            builder: (ctx, scrollCtrl) => Padding(
              padding: EdgeInsets.fromLTRB(
                18,
                16,
                18,
                MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: ListView(
                controller: scrollCtrl,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Edit Member Access',
                              style: T.body(16.5, weight: FontWeight.w800),
                            ),
                            Text(
                              memberEmail.isNotEmpty
                                  ? '$memberName · $memberEmail'
                                  : memberName,
                              style: T.body(12.2, color: Pal.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (modalError != null) ...[
                    ErrorBanner(modalError!),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    'Assigned Roles',
                    style: T.body(13.2, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  for (final r in roles)
                    SaasCheckRow(
                      label:
                          '${r['displayName'] ?? r['name'] ?? r['key']} (${r['key'] ?? ''})',
                      value: selRoleIds.contains('${r['id']}'),
                      onChanged: (v) => setModal(() {
                        final id = '${r['id']}';
                        if (v) {
                          selRoleIds.add(id);
                        } else {
                          selRoleIds.remove(id);
                        }
                      }),
                    ),
                  if (branches.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Authorized Branch Scopes',
                      style: T.body(13.2, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    for (final b in branches)
                      SaasCheckRow(
                        label: '${b['code'] ?? ''} · ${b['name'] ?? ''}',
                        value: selBranchIds.contains('${b['id']}'),
                        onChanged: (v) => setModal(() {
                          final id = '${b['id']}';
                          if (v) {
                            selBranchIds.add(id);
                          } else {
                            selBranchIds.remove(id);
                          }
                        }),
                      ),
                  ],
                  const SizedBox(height: 12),
                  SaasField(
                    label: 'Audit reason',
                    controller: reasonCtrl,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            modalBusy ? null : () => Navigator.of(ctx).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 10),
                      GoldButton(
                        label: 'Save Member Access',
                        compact: true,
                        busy: modalBusy,
                        onPressed: modalBusy ? null : saveAssignments,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    reasonCtrl.dispose();
  }

  Future<void> _decideGrant(Map<String, dynamic> g, String decision) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: Text(
          '${decision[0].toUpperCase()}${decision.substring(1)} Support Grant',
          style: T.body(16, weight: FontWeight.w800),
        ),
        content: SaasField(
          label: 'DECISION REASON (MIN 10 CHARS)',
          controller: reasonCtrl,
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          GoldButton(
            label: decision.toUpperCase(),
            compact: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    reasonCtrl.dispose();
    if (ok != true || !mounted) return;
    if (reason.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Decision reason must be at least 10 characters.'),
        ),
      );
      return;
    }
    try {
      await context.read<ApiClient>().post(
        '/support-grants/${g['id']}/$decision',
        idempotent: true,
        body: {
          'expectedVersion': asInt(g['version'], fallback: 1),
          'decisionReason': reason,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Support grant $decision completed.')),
      );
      _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Pal.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final workspaceSub = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    final root = _accessRoot;
    final allRoles = asList(root, keys: const ['roles', 'tenantRoles', 'items']);
    final q = _search.text.trim().toLowerCase();
    final roles = allRoles
        .where(
          (r) =>
              q.isEmpty ||
              '${r['name'] ?? ''} ${r['displayName'] ?? ''} ${r['key'] ?? ''}'
                  .toLowerCase()
                  .contains(q),
        )
        .toList();
    final members = asList(
      root,
      keys: const ['memberships', 'members', 'users'],
    )
        .where((m) {
          if (q.isEmpty) return true;
          final u = asMap(m['user']);
          return '${u['displayName'] ?? m['displayName'] ?? ''} ${u['email'] ?? m['email'] ?? ''}'
              .toLowerCase()
              .contains(q);
        })
        .toList();

    return LuxuryModuleScaffold(
      title: 'Access Control & Roles',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.admin_panel_settings_rounded,
      searchController: _search,
      searchHint: 'Search roles, permission keys or members...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          onPressed: () => _load(forceRefresh: true),
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: () => _load(forceRefresh: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: () => _load(forceRefresh: true)),
              const SizedBox(height: 12),
            ],

            // `Access and roles` Header + `+ Create role` button (`image-70.png`)
            Container(
              padding: const EdgeInsets.all(15),
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
                                : 'Bullion rates: No published rate',
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
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.verified_user_outlined,
                        size: 20,
                        color: Pal.goldDeep,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Access and roles',
                              style: T.body(
                                17,
                                weight: FontWeight.w800,
                                color: Pal.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Tenant-scoped roles, permissions and member assignments.',
                              style: T.body(12, color: Pal.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      GoldButton(
                        label: '+ Create role',
                        compact: true,
                        busy: _busy,
                        onPressed: _busy ? null : () => _openRoleModal(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // `Roles` Card (`image-70.png`)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.vpn_key_outlined,
                        size: 17,
                        color: Pal.goldDeep,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Roles',
                        style: T.body(
                          14.5,
                          weight: FontWeight.w800,
                          color: Pal.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading && _access.isEmpty)
                    const Skeleton(height: 68)
                  else if (roles.isEmpty)
                    const SaasEmptyBox('No tenant roles found.')
                  else
                    for (var i = 0; i < roles.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1, color: Pal.divider),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${roles[i]['displayName'] ?? roles[i]['name'] ?? roles[i]['key'] ?? 'Role'}',
                                  style: T.body(
                                    14,
                                    weight: FontWeight.w700,
                                    color: Pal.ink,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_rolePermCount(roles[i])} permissions',
                                  style: T.body(12, color: Pal.muted),
                                ),
                              ],
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _openRoleModal(existingRole: roles[i]),
                            icon: const Icon(Icons.edit_outlined, size: 14),
                            label: const Text('Edit'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: Pal.ink,
                              side: const BorderSide(color: Pal.border),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 7,
                              ),
                              textStyle: T.body(12, weight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // `Members` Card (`image-70.png`)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Pal.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.people_outline_rounded,
                        size: 18,
                        color: Pal.goldDeep,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Members',
                        style: T.body(
                          14.5,
                          weight: FontWeight.w800,
                          color: Pal.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading && _access.isEmpty)
                    const Skeleton(height: 68)
                  else if (members.isEmpty)
                    const SaasEmptyBox(
                      'No tenant member assignments returned.',
                    )
                  else
                    for (var i = 0; i < members.length; i++) ...[
                      if (i > 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Divider(height: 1, color: Pal.divider),
                        ),
                      Builder(
                        builder: (_) {
                          final m = members[i];
                          final u = asMap(m['user']);
                          final roleObjs = asList(
                            m,
                            keys: const ['roles', 'roleAssignments', 'scopes'],
                          );
                          final roleLabel = roleObjs.isNotEmpty
                              ? roleObjs
                                    .map(
                                      (r) =>
                                          '${asMap(r['role'])['name'] ?? r['roleName'] ?? r['name'] ?? r['key'] ?? ''}',
                                    )
                                    .where((s) => s.isNotEmpty)
                                    .join(', ')
                              : '${m['roleName'] ?? m['state'] ?? 'Active'}';
                          return Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${u['displayName'] ?? m['displayName'] ?? u['email'] ?? m['email'] ?? 'Member'}',
                                      style: T.body(
                                        14,
                                        weight: FontWeight.w700,
                                        color: Pal.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if ('${u['email'] ?? m['email'] ?? ''}'
                                            .isNotEmpty)
                                          '${u['email'] ?? m['email']}',
                                        if (roleLabel.isNotEmpty) roleLabel,
                                      ].join(' · '),
                                      style: T.body(12, color: Pal.muted),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _openEditMemberModal(m, allRoles),
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 14,
                                ),
                                label: const Text('Edit'),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  foregroundColor: Pal.ink,
                                  side: const BorderSide(color: Pal.border),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 11,
                                    vertical: 7,
                                  ),
                                  textStyle: T.body(
                                    12,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                ],
              ),
            ),
            const SizedBox(height: 18),

            // `Support access` Section (`image-70.png` bottom)
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF3DC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEBD79C)),
                  ),
                  child: const Icon(
                    Icons.headset_mic_outlined,
                    size: 18,
                    color: Pal.goldDeep,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Support access',
                        style: T.body(
                          16,
                          weight: FontWeight.w800,
                          color: Pal.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tenant-controlled, time-limited platform support grants.',
                        style: T.body(12, color: Pal.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Pal.border),
              ),
              child: _grants.isEmpty
                  ? const SaasEmptyBox(
                      'No active or pending platform support grants.',
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < _grants.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1, color: Pal.divider),
                            ),
                          Builder(
                            builder: (_) {
                              final g = _grants[i];
                              final st =
                                  '${g['state'] ?? g['status'] ?? 'REQUESTED'}'
                                      .toUpperCase();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${g['ticketReference'] ?? g['reason'] ?? 'Support Grant'}',
                                          style: T.body(
                                            13.5,
                                            weight: FontWeight.w700,
                                            color: Pal.ink,
                                          ),
                                        ),
                                      ),
                                      StatusChip(st),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Scope: ${g['scope'] ?? 'READ_ONLY'} · Expires: ${formatDate(g['expiresAt'])}',
                                    style: T.body(12, color: Pal.muted),
                                  ),
                                  if (st == 'REQUESTED' ||
                                      st == 'PENDING' ||
                                      st == 'APPROVED' ||
                                      st == 'ACTIVE') ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (st == 'REQUESTED' ||
                                            st == 'PENDING') ...[
                                          OutlinedButton(
                                            onPressed: () =>
                                                _decideGrant(g, 'approve'),
                                            child: const Text('Approve'),
                                          ),
                                          OutlinedButton(
                                            onPressed: () =>
                                                _decideGrant(g, 'reject'),
                                            child: const Text('Reject'),
                                          ),
                                        ],
                                        if (st == 'APPROVED' || st == 'ACTIVE')
                                          OutlinedButton(
                                            onPressed: () =>
                                                _decideGrant(g, 'revoke'),
                                            child: const Text('Revoke'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Exact 1:1 `Create tenant role` modal (`image-70.png`) — keyboard-safe & overflow-free
class _TenantRoleDialog extends StatefulWidget {
  const _TenantRoleDialog({
    required this.catalog,
    this.existingRole,
    this.initialPermissions = const {},
  });

  final List<({String key, String description})> catalog;
  final Map<String, dynamic>? existingRole;
  final Set<String> initialPermissions;

  @override
  State<_TenantRoleDialog> createState() => _TenantRoleDialogState();
}

class _TenantRoleDialogState extends State<_TenantRoleDialog> {
  late final TextEditingController _roleKeyCtrl;
  late final TextEditingController _displayNameCtrl;
  final _scrollCtrl = ScrollController();
  late final Set<String> _selectedPerms;

  bool _keyMissing = false;
  bool _nameMissing = false;
  String? _modalError;
  bool _busy = false;

  bool get _isEdit => widget.existingRole != null;

  @override
  void initState() {
    super.initState();
    final r = widget.existingRole;
    _roleKeyCtrl = TextEditingController(
      text: r != null ? '${r['key'] ?? r['roleKey'] ?? ''}' : '',
    );
    _displayNameCtrl = TextEditingController(
      text: r != null ? '${r['displayName'] ?? r['name'] ?? ''}' : '',
    );
    _selectedPerms = {...widget.initialPermissions};
  }

  @override
  void dispose() {
    _roleKeyCtrl.dispose();
    _displayNameCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  String _slugifyKey(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  Future<void> _submit() async {
    final sanitizedKey = _slugifyKey(_roleKeyCtrl.text);
    final disp = _displayNameCtrl.text.trim();
    if ((!_isEdit && sanitizedKey.isEmpty) || disp.isEmpty) {
      setState(() {
        _keyMissing = !_isEdit && sanitizedKey.isEmpty;
        _nameMissing = disp.isEmpty;
      });
      return;
    }
    if (_selectedPerms.isEmpty) {
      setState(() {
        _modalError = 'Select at least one permission for this role.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _keyMissing = false;
      _nameMissing = false;
      _modalError = null;
    });

    final api = context.read<ApiClient>();
    final sortedPerms = _selectedPerms.toList()..sort();

    try {
      if (_isEdit) {
        final roleId = '${widget.existingRole!['id'] ?? ''}'.trim();
        final ver = asInt(widget.existingRole!['version'], fallback: 1);
        final attempts = <Future<dynamic> Function()>[
          () => api.patch(
                '/access/roles/$roleId',
                idempotent: true,
                body: {
                  'name': disp,
                  'permissionKeys': sortedPerms,
                  'expectedVersion': ver,
                },
              ),
          () => api.patch(
                '/access/roles/$roleId',
                idempotent: true,
                body: {
                  'displayName': disp,
                  'permissionKeys': sortedPerms,
                  'expectedVersion': ver,
                },
              ),
          () => api.put(
                '/access/roles/$roleId',
                idempotent: true,
                body: {
                  'name': disp,
                  'permissionKeys': sortedPerms,
                },
              ),
          () => api.post(
                '/access/roles/$roleId/permissions',
                idempotent: true,
                body: {
                  'name': disp,
                  'permissionKeys': sortedPerms,
                },
              ),
        ];
        ApiException? lastErr;
        var ok = false;
        for (var i = 0; i < attempts.length; i++) {
          try {
            await attempts[i]();
            ok = true;
            break;
          } on ApiException catch (e) {
            lastErr = e;
            if ((e.status == 400 ||
                    e.status == 404 ||
                    e.status == 405 ||
                    e.status == 422) &&
                i + 1 < attempts.length) {
              continue;
            }
            rethrow;
          }
        }
        if (!ok && lastErr != null) throw lastErr;
      } else {
        final createAttempts = <Future<dynamic> Function()>[
          () => api.post(
                '/access/roles',
                idempotent: true,
                body: {
                  'key': sanitizedKey,
                  'name': disp,
                  'permissionKeys': sortedPerms,
                },
              ),
          () => api.post(
                '/access/roles',
                idempotent: true,
                body: {
                  'key': sanitizedKey,
                  'displayName': disp,
                  'permissionKeys': sortedPerms,
                },
              ),
          () => api.post(
                '/access/roles',
                idempotent: true,
                body: {
                  'roleKey': sanitizedKey,
                  'displayName': disp,
                  'permissionKeys': sortedPerms,
                },
              ),
          () => api.post(
                '/access/roles',
                idempotent: true,
                body: {
                  'key': sanitizedKey,
                  'name': disp,
                  'permissions': sortedPerms,
                },
              ),
        ];

        ApiException? lastErr;
        var ok = false;
        for (var i = 0; i < createAttempts.length; i++) {
          try {
            await createAttempts[i]();
            ok = true;
            break;
          } on ApiException catch (e) {
            lastErr = e;
            if ((e.status == 400 || e.status == 422) &&
                i + 1 < createAttempts.length) {
              continue;
            }
            rethrow;
          }
        }
        if (!ok && lastErr != null) throw lastErr;
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _isEdit
                ? 'Tenant role "$disp" updated.'
                : 'Tenant role "$disp" created.',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _modalError = e.message;
        });
      }
    }
  }

  Widget _buildRoleInput({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool readOnly = false,
    bool hasError = false,
    required ValueChanged<String> onChanged,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Pal.gold, width: 1.5),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Pal.danger, width: 1.3),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: T.body(
            12.8,
            weight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          readOnly: readOnly,
          style: T.body(13.8, color: const Color(0xFF0F172A)),
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: T.body(13.5, color: const Color(0xFF94A3B8)),
            filled: true,
            fillColor: readOnly ? const Color(0xFFF8FAFC) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 11,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: focusedBorder,
            errorBorder: errorBorder,
            focusedErrorBorder: errorBorder,
            errorText: hasError ? 'Please fill in this field.' : null,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final kbBottom = MediaQuery.viewInsetsOf(context).bottom;
    final dialogW = (screenSize.width - 24).clamp(260.0, 520.0);
    final availableHeight = (screenSize.height - kbBottom - 32).clamp(
      240.0,
      640.0,
    );
    final scrollAreaHeight = (availableHeight - 62).clamp(170.0, 565.0);

    final keyField = _buildRoleInput(
      label: 'Role key',
      controller: _roleKeyCtrl,
      hint: 'inventory-controller',
      readOnly: _isEdit,
      hasError: _keyMissing,
      onChanged: (_) {
        if (_keyMissing) {
          setState(() => _keyMissing = false);
        }
      },
    );
    final nameField = _buildRoleInput(
      label: 'Display name',
      controller: _displayNameCtrl,
      hasError: _nameMissing,
      onChanged: (_) {
        if (_nameMissing) {
          setState(() => _nameMissing = false);
        }
      },
    );

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        width: dialogW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: scrollAreaHeight,
              child: Scrollbar(
                controller: _scrollCtrl,
                child: CustomScrollView(
                  controller: _scrollCtrl,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isEdit
                                  ? 'Edit tenant role'
                                  : 'Create tenant role',
                              style: T.body(
                                18.5,
                                weight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Choose the minimum permissions required for this role.',
                              style: T.body(
                                13,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_modalError != null) ...[
                              ErrorBanner(_modalError!),
                              const SizedBox(height: 12),
                            ],
                            if (dialogW < 310)
                              Column(
                                children: [
                                  keyField,
                                  const SizedBox(height: 12),
                                  nameField,
                                ],
                              )
                            else
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: keyField),
                                  const SizedBox(width: 12),
                                  Expanded(child: nameField),
                                ],
                              ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Permissions',
                                    style: T.body(
                                      13.2,
                                      weight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (_selectedPerms.isNotEmpty)
                                  Text(
                                    '${_selectedPerms.length} selected',
                                    style: T.body(
                                      11.8,
                                      weight: FontWeight.w700,
                                      color: Pal.goldDeep,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final item = widget.catalog[i];
                            final checked = _selectedPerms.contains(item.key);
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom: i + 1 < widget.catalog.length ? 8 : 0,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () {
                                  setState(() {
                                    if (checked) {
                                      _selectedPerms.remove(item.key);
                                    } else {
                                      _selectedPerms.add(item.key);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    11,
                                    14,
                                    11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: checked
                                        ? const Color(0xFFFFFCF3)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: checked
                                          ? Pal.borderGold
                                          : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 22,
                                        child: Checkbox(
                                          value: checked,
                                          activeColor: Pal.gold,
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          side: const BorderSide(
                                            color: Color(0xFF94A3B8),
                                            width: 1.4,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          onChanged: (v) {
                                            setState(() {
                                              if (v == true) {
                                                _selectedPerms.add(item.key);
                                              } else {
                                                _selectedPerms.remove(item.key);
                                              }
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.key,
                                              style: T.body(
                                                13.2,
                                                weight: FontWeight.w700,
                                                color: const Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              item.description,
                                              style: T.body(
                                                12.2,
                                                color: const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: widget.catalog.length,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: T.body(
                        13.8,
                        weight: FontWeight.w500,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GoldButton(
                    label: _isEdit ? 'Save role' : 'Create role',
                    compact: true,
                    busy: _busy,
                    onPressed: _busy ? null : _submit,
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
// 8. COMPANY & INVOICE PROFILE (`/organization/invoice-profile`) — `image-59..61.png`
// ---------------------------------------------------------------------------

class CompanyInvoiceProfileScreen extends StatefulWidget {
  const CompanyInvoiceProfileScreen({super.key});
  @override
  State<CompanyInvoiceProfileScreen> createState() =>
      _CompanyInvoiceProfileScreenState();
}

class _CompanyInvoiceProfileScreenState
    extends State<CompanyInvoiceProfileScreen> {
  static const int _maxLogoBytes = 512 * 1024;

  String _loadedBranchId = '';
  Map<String, dynamic> _rawEnvelope = const {};
  Map<String, dynamic> _profileMap = const {};
  Uint8List? _logoBytes;
  String _maskedBankAccount = '';

  bool _loading = true;
  bool _savingEntity = false;
  bool _savingProfile = false;
  bool _uploadingLogo = false;
  String? _error;

  // Card 1: `Legal entity identity` (`image-59.png`)
  final _legalEntityName = TextEditingController();
  final _entityChangeReason = TextEditingController(
    text: 'Correct legal entity name for company billing profile.',
  );

  // Card 4: `Showroom identity` (`image-60.png`)
  final _tradeStoreName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _city = TextEditingController();
  final _stateUt = TextEditingController();
  final _pinCode = TextEditingController();
  final _country = TextEditingController(text: 'India');

  // Card 5: `Bank and UPI collection` (`image-61.png`)
  final _bankName = TextEditingController();
  final _accountHolder = TextEditingController();
  final _accountNumber = TextEditingController();
  final _ifsc = TextEditingController();
  final _businessUpi = TextEditingController();

  // Card 6: `Invoice policy and signatory` (`image-61.png`)
  final _signatoryName = TextEditingController();
  final _signatoryTitle = TextEditingController(text: 'Authorised Signatory');
  final _declarationTerms = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final branchId = context.watch<AppState>().selectedBranchId;
    if (_loadedBranchId != branchId || (_loadedBranchId.isEmpty && _loading)) {
      _loadedBranchId = branchId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void dispose() {
    for (final c in [
      _legalEntityName,
      _entityChangeReason,
      _tradeStoreName,
      _phone,
      _email,
      _addressLine1,
      _addressLine2,
      _city,
      _stateUt,
      _pinCode,
      _country,
      _bankName,
      _accountHolder,
      _accountNumber,
      _ifsc,
      _businessUpi,
      _signatoryName,
      _signatoryTitle,
      _declarationTerms,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _pickStr(Map<String, dynamic> m, List<String> keys, [String def = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.trim().isNotEmpty) {
        return '$v'.trim();
      }
    }
    return def;
  }

  String _pickExistingKey(
    Map<String, dynamic> m,
    List<String> candidates,
    String fallback,
  ) {
    for (final k in candidates) {
      if (m.containsKey(k)) return k;
    }
    return fallback;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    final app = context.read<AppState>();
    try {
      final query = <String, dynamic>{
        if (app.selectedBranchId.isNotEmpty) 'branchId': app.selectedBranchId,
        if (app.selectedEntityId.isNotEmpty)
          'legalEntityId': app.selectedEntityId,
      };
      final results = await Future.wait<dynamic>([
        api.get('/organization/invoice-profile', query: query),
        api.getBytes('/organization/invoice-profile/logo', query: query),
      ]);
      if (!mounted) return;

      final env = asMap(results[0]);
      final nestedProfile = asMap(
        env['profile'] ?? env['invoiceProfile'] ?? env['branchProfile'],
      );
      final p = nestedProfile.isNotEmpty ? nestedProfile : env;
      final entObj = asMap(env['legalEntity']);
      final showroomObj = asMap(env['showroomIdentity'] ?? env['showroom']);
      final bankObj = asMap(env['bankCollection'] ?? env['bank']);
      final policyObj = asMap(env['invoicePolicy'] ?? env['signatory']);

      final merged = <String, dynamic>{
        ...p,
        ...showroomObj,
        ...bankObj,
        ...policyObj,
      };

      final entityLegalName = _pickStr(
        entObj.isNotEmpty ? entObj : env,
        const ['legalName', 'legalEntityName', 'name'],
        app.entityName,
      );

      String termsText = '';
      final rawTerms = merged['declarationTerms'] ??
          merged['invoiceTerms'] ??
          merged['terms'] ??
          merged['declarations'];
      if (rawTerms is List) {
        termsText = rawTerms
            .map((e) => '$e'.trim())
            .where((s) => s.isNotEmpty)
            .join('\n');
      } else if (rawTerms is String) {
        termsText = rawTerms.trim();
      }

      Uint8List? logo = results[1] as Uint8List?;
      if (logo == null) {
        final inlineB64 = _pickStr(
          merged,
          const ['logoDataUrl', 'logoBase64', 'logoContentBase64'],
        );
        if (inlineB64.isNotEmpty) {
          try {
            final comma = inlineB64.indexOf(',');
            logo = base64Decode(
              comma >= 0 ? inlineB64.substring(comma + 1) : inlineB64,
            );
          } catch (_) {}
        }
      }

      app.setShowroomLogo(logo, branchId: app.selectedBranchId);

      setState(() {
        _rawEnvelope = env;
        _profileMap = merged;
        _logoBytes = logo;

        _legalEntityName.text = entityLegalName;
        _tradeStoreName.text = _pickStr(
          merged,
          const ['tradeName', 'storeName', 'tradeOrStoreName'],
        );
        _phone.text = _pickStr(merged, const ['phone', 'contactPhone']);
        _email.text = _pickStr(merged, const ['email', 'contactEmail']);
        _addressLine1.text = _pickStr(merged, const ['addressLine1']);
        _addressLine2.text = _pickStr(merged, const ['addressLine2']);
        _city.text = _pickStr(merged, const ['city']);
        _stateUt.text = _pickStr(
          merged,
          const ['state', 'stateOrUnionTerritory', 'stateName'],
        );
        _pinCode.text = _pickStr(
          merged,
          const ['pinCode', 'postalCode', 'pincode'],
        );
        _country.text = _pickStr(merged, const ['country'], 'India');

        _bankName.text = _pickStr(merged, const ['bankName']);
        _accountHolder.text = _pickStr(
          merged,
          const ['accountHolder', 'accountHolderName'],
        );
        // Always leave accountNumber input blank so saved masked account stays intact unless edited (`image-61.png`)
        _accountNumber.clear();
        _maskedBankAccount = _pickStr(
          merged,
          const [
            'maskedAccountNumber',
            'accountNumberMasked',
            'bankAccountMasked',
          ],
        );
        _ifsc.text = _pickStr(merged, const ['ifsc', 'ifscCode']);
        _businessUpi.text = _pickStr(
          merged,
          const ['upiId', 'businessUpiId', 'upiVpa'],
        );

        _signatoryName.text = _pickStr(
          merged,
          const [
            'authorisedSignatoryName',
            'authorizedSignatoryName',
            'signatoryName',
          ],
        );
        _signatoryTitle.text = _pickStr(
          merged,
          const ['signatoryTitle'],
          'Authorised Signatory',
        );
        _declarationTerms.text = termsText;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final appFallback = context.read<AppState>();
      if (_legalEntityName.text.isEmpty && appFallback.entityName.isNotEmpty) {
        _legalEntityName.text = appFallback.entityName;
      }
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveLegalEntityName() async {
    final name = _legalEntityName.text.trim();
    final reason = _entityChangeReason.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Enter a valid Legal entity name.');
      return;
    }
    if (reason.length < 5) {
      setState(
        () => _error =
            'Provide Change reason (audit record) before updating legal entity identity.',
      );
      return;
    }

    final app = context.read<AppState>();
    final api = context.read<ApiClient>();
    final entObj = asMap(_rawEnvelope['legalEntity']);
    final entityId = _pickStr(
      entObj,
      const ['id'],
      app.selectedEntityId,
    );

    setState(() {
      _savingEntity = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'legalName': name,
        'reason': reason,
      };
      final attempts = <Future<dynamic> Function()>[
        () => api.patch(
              '/organization/invoice-profile/legal-entity',
              idempotent: true,
              body: body,
            ),
        () => api.put(
              '/organization/invoice-profile/legal-entity',
              idempotent: true,
              body: body,
            ),
        if (entityId.isNotEmpty)
          () => api.patch(
                '/organization/legal-entities/$entityId',
                idempotent: true,
                body: body,
              ),
        if (entityId.isNotEmpty)
          () => api.put(
                '/organization/legal-entities/$entityId',
                idempotent: true,
                body: body,
              ),
        () => api.post(
              '/organization/invoice-profile/legal-entity',
              idempotent: true,
              body: body,
            ),
      ];

      ApiException? lastErr;
      var ok = false;
      for (var i = 0; i < attempts.length; i++) {
        try {
          await attempts[i]();
          ok = true;
          break;
        } on ApiException catch (e) {
          lastErr = e;
          if ((e.status == 404 || e.status == 405) &&
              i + 1 < attempts.length) {
            continue;
          }
          rethrow;
        }
      }
      if (!ok && lastErr != null) throw lastErr;

      await app.refreshSession();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Legal entity name updated.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _savingEntity = false);
    }
  }

  String? _detectImageMime(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  Future<void> _openUploadLogoModal() async {
    Uint8List? stagedBytes;
    String? stagedMime;
    String stagedName = 'showroom-logo.png';
    String? modalError;
    bool modalBusy = false;
    bool pickingPhoto = false;

    void stageValidatedBytes(
      Uint8List decoded,
      String fallbackName,
      void Function(void Function()) setModal,
    ) {
      if (decoded.length > _maxLogoBytes) {
        setModal(() {
          stagedBytes = null;
          stagedMime = null;
          modalError =
              'Selected photo exceeds 512 KB (${(decoded.length / 1024).toStringAsFixed(1)} KB). Choose a smaller logo image.';
        });
        return;
      }
      final mime = _detectImageMime(decoded);
      if (mime == null) {
        setModal(() {
          stagedBytes = null;
          stagedMime = null;
          modalError = 'Only PNG, JPEG, or WebP images are permitted.';
        });
        return;
      }
      setModal(() {
        stagedBytes = decoded;
        stagedMime = mime;
        stagedName = fallbackName;
        modalError = null;
      });
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Pal.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> pickFromDevice(String mode) async {
            setModal(() {
              pickingPhoto = true;
              modalError = null;
            });
            try {
              final picked = await DeviceBridge.pickLogoImage(
                mode: mode,
                maxBytes: 500 * 1024,
              );
              if (!ctx.mounted) return;
              if (picked != null) {
                stageValidatedBytes(picked.bytes, picked.fileName, setModal);
              }
            } on PlatformException catch (e) {
              if (ctx.mounted) {
                setModal(
                  () => modalError = e.message ?? 'Could not open device photos.',
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                setModal(() => modalError = 'Unable to pick photo: $e');
              }
            } finally {
              if (ctx.mounted) {
                setModal(() => pickingPhoto = false);
              }
            }
          }

          Future<void> uploadNow() async {
            if (stagedBytes == null || stagedMime == null) {
              setModal(
                () => modalError =
                    'Select your logo from Device Photos or Files first.',
              );
              return;
            }
            setModal(() {
              modalBusy = true;
              modalError = null;
            });
            final api = context.read<ApiClient>();
            final ext = stagedMime == 'image/png'
                ? 'png'
                : (stagedMime == 'image/webp' ? 'webp' : 'jpg');
            final filename =
                stagedName.isNotEmpty ? stagedName : 'showroom-logo.$ext';
            final b64 = base64Encode(stagedBytes!);
            final dataUrl = 'data:$stagedMime;base64,$b64';

            try {
              final attempts = <Future<dynamic> Function()>[
                () => api.uploadBytes(
                      'PUT',
                      '/organization/invoice-profile/logo',
                      bytes: stagedBytes!,
                      filename: filename,
                      mimeType: stagedMime!,
                      fieldName: 'logo',
                    ),
                () => api.uploadBytes(
                      'POST',
                      '/organization/invoice-profile/logo',
                      bytes: stagedBytes!,
                      filename: filename,
                      mimeType: stagedMime!,
                      fieldName: 'logo',
                    ),
                () => api.uploadBytes(
                      'PUT',
                      '/organization/invoice-profile/logo',
                      bytes: stagedBytes!,
                      filename: filename,
                      mimeType: stagedMime!,
                      fieldName: 'file',
                    ),
                () => api.put(
                      '/organization/invoice-profile/logo',
                      idempotent: true,
                      body: {
                        'mimeType': stagedMime,
                        'contentBase64': b64,
                        'dataUrl': dataUrl,
                        'fileName': filename,
                      },
                    ),
                () => api.post(
                      '/organization/invoice-profile/logo',
                      idempotent: true,
                      body: {
                        'mimeType': stagedMime,
                        'contentBase64': b64,
                        'dataUrl': dataUrl,
                        'fileName': filename,
                      },
                    ),
              ];

              ApiException? lastErr;
              var ok = false;
              for (var i = 0; i < attempts.length; i++) {
                try {
                  await attempts[i]();
                  ok = true;
                  break;
                } on ApiException catch (e) {
                  lastErr = e;
                  if ((e.status == 400 ||
                          e.status == 404 ||
                          e.status == 405 ||
                          e.status == 415) &&
                      i + 1 < attempts.length) {
                    continue;
                  }
                  rethrow;
                }
              }
              if (!ok && lastErr != null) throw lastErr;

              if (mounted) {
                final app = context.read<AppState>();
                app.setShowroomLogo(stagedBytes, branchId: app.selectedBranchId);
                setState(() => _logoBytes = stagedBytes);
              }
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Showroom logo uploaded privately.'),
                ),
              );
              await _load();
            } on ApiException catch (e) {
              if (ctx.mounted) {
                setModal(() {
                  modalBusy = false;
                  modalError = e.message;
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Upload Showroom Logo',
                              style: T.body(17, weight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'PNG, JPEG, or WebP · up to 512 KB. Stored privately in this tenant and branch\'s database scope.',
                              style: T.body(12, color: Pal.muted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (modalError != null) ...[
                    ErrorBanner(modalError!),
                    const SizedBox(height: 12),
                  ],

                  // Native Device Photos / Gallery Card Button (`image-63.png` upgrade)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: (pickingPhoto || modalBusy)
                        ? null
                        : () => pickFromDevice('photos'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBF5E4),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Pal.goldBorder, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Pal.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Pal.goldBorder),
                            ),
                            child: pickingPhoto
                                ? const Padding(
                                    padding: EdgeInsets.all(11),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.photo_library_outlined,
                                    color: Pal.goldDeep,
                                    size: 22,
                                  ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Upload from Device Photos',
                                  style: T.body(
                                    14.5,
                                    color: Pal.ink,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Choose your showroom or company logo from phone gallery',
                                  style: T.body(12, color: Pal.muted),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Pal.goldDeep,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: (pickingPhoto || modalBusy)
                        ? null
                        : () => pickFromDevice('files'),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('Browse Device Files / Downloads'),
                  ),

                  if (stagedBytes != null) ...[
                    const SizedBox(height: 14),
                    SaasSubBox(
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Pal.goldBorder),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                stagedBytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected Logo Ready',
                                  style: T.body(13.5, weight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$stagedMime · ${(stagedBytes!.length / 1024).toStringAsFixed(1)} KB',
                                  style: T.mono(11.8, color: Pal.ok),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Clear selection',
                            onPressed: modalBusy
                                ? null
                                : () => setModal(() {
                                      stagedBytes = null;
                                      stagedMime = null;
                                    }),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  RoyalGoldButton(
                    icon: Icons.cloud_upload_outlined,
                    label: 'Upload logo',
                    busy: modalBusy,
                    onPressed: (modalBusy || stagedBytes == null)
                        ? null
                        : uploadNow,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _removeLogo() async {
    setState(() {
      _uploadingLogo = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().delete(
        '/organization/invoice-profile/logo',
        idempotent: true,
      );
      if (!mounted) return;
      final app = context.read<AppState>();
      app.setShowroomLogo(null, branchId: app.selectedBranchId);
      setState(() => _logoBytes = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Showroom logo removed.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  Future<void> _saveInvoiceProfile() async {
    final termsLines = _declarationTerms.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (termsLines.length > 8) {
      setState(
        () => _error =
            'Declaration / invoice terms permits at most 8 lines (currently ${termsLines.length}).',
      );
      return;
    }

    final tradeKey = _pickExistingKey(
      _profileMap,
      const ['tradeName', 'storeName', 'tradeOrStoreName'],
      'tradeName',
    );
    final stateKey = _pickExistingKey(
      _profileMap,
      const ['state', 'stateOrUnionTerritory', 'stateName'],
      'state',
    );
    final pinKey = _pickExistingKey(
      _profileMap,
      const ['pinCode', 'postalCode', 'pincode'],
      'pinCode',
    );
    final holderKey = _pickExistingKey(
      _profileMap,
      const ['accountHolder', 'accountHolderName'],
      'accountHolder',
    );
    final ifscKey = _pickExistingKey(
      _profileMap,
      const ['ifsc', 'ifscCode'],
      'ifsc',
    );
    final upiKey = _pickExistingKey(
      _profileMap,
      const ['upiId', 'businessUpiId', 'upiVpa'],
      'upiId',
    );
    final sigNameKey = _pickExistingKey(
      _profileMap,
      const [
        'authorisedSignatoryName',
        'authorizedSignatoryName',
        'signatoryName',
      ],
      'authorisedSignatoryName',
    );
    final termsKey = _pickExistingKey(
      _profileMap,
      const ['declarationTerms', 'invoiceTerms', 'terms'],
      'declarationTerms',
    );
    final termsWasString = _profileMap[termsKey] is String;

    final payload = <String, dynamic>{
      tradeKey: _tradeStoreName.text.trim(),
      'phone': _phone.text.trim(),
      'email': _email.text.trim(),
      'addressLine1': _addressLine1.text.trim(),
      'addressLine2': _addressLine2.text.trim(),
      'city': _city.text.trim(),
      stateKey: _stateUt.text.trim(),
      pinKey: _pinCode.text.trim(),
      'country': _country.text.trim().isEmpty ? 'India' : _country.text.trim(),
      'bankName': _bankName.text.trim(),
      holderKey: _accountHolder.text.trim(),
      if (_accountNumber.text.trim().isNotEmpty)
        'accountNumber': _accountNumber.text.trim(),
      ifscKey: _ifsc.text.trim().toUpperCase(),
      upiKey: _businessUpi.text.trim(),
      sigNameKey: _signatoryName.text.trim(),
      'signatoryTitle': _signatoryTitle.text.trim().isEmpty
          ? 'Authorised Signatory'
          : _signatoryTitle.text.trim(),
      termsKey: termsWasString ? termsLines.join('\n') : termsLines,
    };

    setState(() {
      _savingProfile = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final attempts = <Future<dynamic> Function()>[
        () => api.put(
              '/organization/invoice-profile',
              idempotent: true,
              body: payload,
            ),
        () => api.patch(
              '/organization/invoice-profile',
              idempotent: true,
              body: payload,
            ),
        () => api.post(
              '/organization/invoice-profile',
              idempotent: true,
              body: payload,
            ),
      ];

      ApiException? lastErr;
      var ok = false;
      for (var i = 0; i < attempts.length; i++) {
        try {
          await attempts[i]();
          ok = true;
          break;
        } on ApiException catch (e) {
          lastErr = e;
          if ((e.status == 404 || e.status == 405) &&
              i + 1 < attempts.length) {
            continue;
          }
          rethrow;
        }
      }
      if (!ok && lastErr != null) throw lastErr;

      if (!mounted) return;
      _accountNumber.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Showroom invoice profile saved.')),
      );
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');

    final activeEntityTitle = app.entityName.trim().isNotEmpty
        ? app.entityName.trim()
        : (_legalEntityName.text.trim().isNotEmpty
            ? _legalEntityName.text.trim()
            : 'Active Legal Entity');
    final activeBranchTitle = app.branchName.trim().isNotEmpty
        ? app.branchName.trim()
        : 'Active Showroom';
    final workspaceSub = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    return LuxuryModuleScaffold(
      title: 'Company & Invoice Profile',
      subtitle: workspaceSub.isEmpty ? null : workspaceSub,
      icon: Icons.request_quote_outlined,
      actions: [
        IconButton(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 44),
          children: [
            if (_error != null) ...[
              ErrorBanner(_error!, onRetry: _load),
              const SizedBox(height: 12),
            ],

            // Hero Header + Active Context + Blue Governance Banner (`image-59.png`)
            Container(
              padding: const EdgeInsets.all(15),
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
                                : 'Bullion rates: No published rate',
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
                  Text(
                    'Company & Invoice Profile',
                    style: T.body(17, weight: FontWeight.w800, color: Pal.ink),
                  ),
                  const SizedBox(height: 5),
                  RichText(
                    text: TextSpan(
                      style: T.body(12.2, color: Pal.muted),
                      children: [
                        const TextSpan(text: 'Active legal entity: '),
                        TextSpan(
                          text: activeEntityTitle,
                          style: T.body(
                            12.2,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                        const TextSpan(text: ' · Active branch: '),
                        TextSpan(
                          text: '$activeBranchTitle.',
                          style: T.body(
                            12.2,
                            weight: FontWeight.w700,
                            color: Pal.ink,
                          ),
                        ),
                        const TextSpan(
                          text:
                              ' Switch showroom from the dashboard header to edit another branch.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ShowroomHierarchyScreen(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          'Switch active showroom branch →',
                          style: T.body(
                            12,
                            weight: FontWeight.w700,
                            color: Pal.goldDeep,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: Text(
                      'Legal entity identity is edited here. GSTIN and registered seller details are managed in the separately permissioned GST Compliance workspace.',
                      style: T.body(12, color: const Color(0xFF0C4A6E)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            if (_loading)
              const Panel(child: Skeleton(height: 140))
            else ...[
              // Card 1: `Legal entity identity` (`image-59.png`)
              SaasFormCard(
                title: 'Legal entity identity',
                icon: Icons.domain_rounded,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SaasField(
                      label: 'Legal entity name',
                      controller: _legalEntityName,
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Change reason (audit record)',
                      controller: _entityChangeReason,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed:
                            _savingEntity ? null : _saveLegalEntityName,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          side: const BorderSide(color: Pal.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _savingEntity
                              ? 'Saving…'
                              : 'Save legal entity name',
                          style: T.body(
                            13,
                            weight: FontWeight.w600,
                            color: Pal.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Card 2: `GST registration` (`image-59.png`)
              SaasFormCard(
                title: 'GST registration',
                subtitle:
                    'GSTIN, registered name, effective dates, and approval history are managed in the dedicated GST Compliance workspace with its own permissions and maker-checker approval.',
                icon: Icons.verified_user_outlined,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            const GstRegistrationTransportScreen(),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      side: const BorderSide(color: Pal.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      'Open GST compliance workspace',
                      style: T.body(
                        13,
                        weight: FontWeight.w600,
                        color: Pal.ink,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Card 3: `Showroom logo` (`image-60.png`)
              SaasFormCard(
                title: 'Showroom logo',
                icon: Icons.image_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_logoBytes != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Pal.bgTint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Pal.border),
                        ),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _logoBytes!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Private showroom logo stored (${(_logoBytes!.length / 1024).toStringAsFixed(1)} KB)',
                                style: T.body(12.2, color: Pal.ink),
                              ),
                            ),
                            TextButton(
                              onPressed: _uploadingLogo ? null : _removeLogo,
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    OutlinedButton(
                      onPressed:
                          _uploadingLogo ? null : _openUploadLogoModal,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        side: const BorderSide(color: Pal.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'Upload logo',
                        style: T.body(
                          13,
                          weight: FontWeight.w600,
                          color: Pal.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'PNG, JPEG, or WebP · up to 512 KB. Stored privately in this tenant and branch\'s database scope.',
                      style: T.body(11.6, color: Pal.muted),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Card 4: `Showroom identity` (`image-60.png`)
              SaasFormCard(
                title: 'Showroom identity',
                icon: Icons.storefront_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SaasField(
                      label: 'Trade / store name',
                      controller: _tradeStoreName,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Phone',
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            mono: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Email',
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Address line 1',
                      controller: _addressLine1,
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Address line 2',
                      controller: _addressLine2,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'City',
                            controller: _city,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'State / Union Territory',
                            controller: _stateUt,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'PIN code',
                            controller: _pinCode,
                            mono: true,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Country',
                            controller: _country,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Card 5: `Bank and UPI collection` (`image-61.png`)
              SaasFormCard(
                title: 'Bank and UPI collection',
                subtitle:
                    'Bank account is masked after saving. Leave the account field blank to keep the saved account number.',
                icon: Icons.account_balance_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_maskedBankAccount.isNotEmpty) ...[
                      SaasSubBox(
                        child: Text(
                          'Saved bank account: $_maskedBankAccount',
                          style: T.mono(
                            12,
                            weight: FontWeight.w700,
                            color: Pal.goldDeep,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Bank name',
                            controller: _bankName,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Account holder',
                            controller: _accountHolder,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Account number',
                            controller: _accountNumber,
                            mono: true,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'IFSC',
                            controller: _ifsc,
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label: 'Business UPI ID / VPA',
                      controller: _businessUpi,
                      mono: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Card 6: `Invoice policy and signatory` (`image-61.png`)
              SaasFormCard(
                title: 'Invoice policy and signatory',
                icon: Icons.draw_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SaasField(
                            label: 'Authorised signatory name',
                            controller: _signatoryName,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Signatory title',
                            controller: _signatoryTitle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(
                      label:
                          'Declaration / invoice terms (one per line, up to 8)',
                      controller: _declarationTerms,
                      maxLines: 5,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Bottom Golden CTA (`Save invoice profile` — image-61.png)
              RoyalGoldButton(
                label: 'Save invoice profile',
                busy: _savingProfile,
                onPressed: _savingProfile ? null : _saveInvoiceProfile,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef CompanyInvoicePolicyScreen = CompanyInvoiceProfileScreen;
typedef DocumentsPolicyScreen = CompanyInvoiceProfileScreen;
typedef AuditComplianceScreen = AccessControlScreen;
