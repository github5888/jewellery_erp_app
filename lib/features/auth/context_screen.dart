import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/build.dart';
import '../../core/showrooms.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../billing/billing_controller.dart';
import '../debug/api_inspector.dart';

class ContextScreen extends StatefulWidget {
  const ContextScreen({super.key});
  @override
  State<ContextScreen> createState() => _ContextScreenState();
}

class _ContextScreenState extends State<ContextScreen> {
  final _search = TextEditingController();
  String? _busyBranch;
  String? _error;
  String? _diag;

  @override
  void initState() {
    super.initState();
    // Auto-enter when the user has exactly one showroom scope and hasn't come here via switcher.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.options.length == 1 && app.selectedBranchId.isEmpty) {
        _pick(app.options.first);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(ShowroomOption o) async {
    final app = context.read<AppState>();
    final billing = context.read<BillingController>();
    setState(() {
      _busyBranch = o.branchId;
      _error = null;
    });
    try {
      await app.selectContext(o);
      billing.reset();
    } on ApiException catch (ex) {
      final api = context.read<ApiClient>();
      final ctx = api.log.where((e) => e.path == '/session/context').firstOrNull;
      final diag =
          '${api.log.take(6).map((e) => '${e.method} ${e.path} -> ${e.status ?? 'no reply'}').join('\n')}'
          '${ctx == null ? '' : '\n\n${ctx.note}'}';
      if (mounted) {
        setState(() {
          _diag = diag;
          _error = ex.message;
          _busyBranch = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final q = _search.text.trim().toLowerCase();

    // Group: Tenant -> Legal Entity -> Branches
    final grouped = <String, Map<String, List<ShowroomOption>>>{};
    for (final o in app.options) {
      if (q.isNotEmpty &&
          !'${o.branchLabel} ${o.branchCode} ${o.entityName} ${o.tenantLabel}'
              .toLowerCase()
              .contains(q)) {
        continue;
      }
      grouped.putIfAbsent(o.tenantLabel, () => {}).putIfAbsent(o.entityName, () => []).add(o);
    }

    return LuxuryModuleScaffold(
      title: 'Select Showroom',
      icon: Icons.storefront_rounded,
      searchController: app.options.length > 2 ? _search : null,
      searchHint: 'Search by Showroom, Code or Legal Entity...',
      onSearchChanged: app.options.length > 2 ? (_) => setState(() {}) : null,
      actions: [
        IconButton(
          tooltip: 'API Diagnostics',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const ApiInspector()),
          ),
          icon: const Icon(Icons.monitor_heart_outlined, color: Pal.goldSoft),
        ),
        TextButton.icon(
          onPressed: app.logout,
          icon: const Icon(Icons.logout_rounded, size: 17, color: Pal.goldSoft),
          label: Text('Sign out', style: T.body(12.5, color: Pal.goldSoft, w: FontWeight.w700)),
        ),
      ],
      body: app.options.isEmpty
          ? _Unreadable(raw: app.sessionRaw, onRetry: app.refreshSession)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                LuxuryHeroCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: EnterpriseBadge('Working Context', icon: Icons.storefront_rounded),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(app.mfaEnrolled ? 'VERIFIED' : 'ACTIVE'),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      app.userName.isEmpty ? 'Choose your showroom' : 'Welcome, ${app.userName}',
                      style: T.display(22, color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Every inventory movement, rate book, and GST invoice is strictly isolated to your selected legal entity and showroom.',
                      style: T.body(12.8, color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ]),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: ErrorBlock(_error!),
                  ),
                if (_diag != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Panel(
                      color: Pal.surfaceAlt,
                      child: SelectableText('$kBuild\n$_diag', style: T.mono(11, color: Pal.muted)),
                    ),
                  ),
                for (final t in grouped.entries) ...[
                  SectionLabel(t.key),
                  for (final e in t.value.entries)
                    for (final o in e.value)
                      LuxuryRecordCard(
                        icon: Icons.storefront_outlined,
                        code: o.branchLabel,
                        status: o.branchId == app.selectedBranchId ? 'ACTIVE' : 'AVAILABLE',
                        onTap: _busyBranch != null ? null : () => _pick(o),
                        lines: [
                          if (e.key.isNotEmpty) ('Legal Entity', e.key),
                          ('Currency & Zone', '${o.currency} · ${o.timezone}'),
                        ],
                        amountLabel: _busyBranch == o.branchId ? 'Activating' : 'Branch Code',
                        amountValue: _busyBranch == o.branchId ? '...' : o.branchCode,
                      ),
                ],
              ],
            ),
    );
  }
}

class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.raw, required this.onRetry});
  final String raw;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        EmptyBlock(
          icon: Icons.store_mall_directory_outlined,
          title: 'No showroom scopes assigned',
          body: 'This account has no active showroom branch memberships yet, or requires administrator role assignment.',
        ),
        const SizedBox(height: 8),
        Panel(
          color: Pal.surfaceAlt,
          child: SelectableText(raw.isEmpty ? '(empty session payload)' : raw, style: T.mono(11.5)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: raw));
                if (context.mounted) toast(context, 'Session JSON copied to clipboard.');
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('Copy JSON'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: onRetry, child: const Text('Reload Session'))),
        ]),
      ],
    );
  }
}
