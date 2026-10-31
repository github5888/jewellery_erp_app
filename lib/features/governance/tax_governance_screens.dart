import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
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
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
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
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
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
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
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
      await _postFirstLive(
        context.read<ApiClient>(),
        [
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
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
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

typedef CompanyInvoicePolicyScreen = GstEInvoicesBillsScreen;

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
                  GoldButton(
                    label: 'Copy Output',
                    compact: true,
                    icon: Icons.copy_rounded,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: htmlOrText));
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Rendered print output copied to clipboard.'),
                          ),
                        );
                      }
                    },
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
    final auth = context.watch<AuthController>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999') ?? rates.find('GOLD', '24K');
    final tenantName = (auth.tenantName ?? '').trim();
    final branchName = (auth.branchName ?? '').trim();
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
