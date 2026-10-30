import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/build.dart';
import '../../core/showrooms.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../billing/billing_controller.dart';
import '../debug/api_inspector.dart';

class ContextScreen extends StatefulWidget {
  const ContextScreen({super.key});
  @override
  State<ContextScreen> createState() => _ContextScreenState();
}

class _ContextScreenState extends State<ContextScreen> {
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

    // Group: Tenant -> Legal Entity -> Branches
    final grouped = <String, Map<String, List<ShowroomOption>>>{};
    for (final o in app.options) {
      grouped.putIfAbsent(o.tenantLabel, () => {}).putIfAbsent(o.entityName, () => []).add(o);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [
          Container(
            width: 32,
            height: 32,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Pal.goldWash,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Pal.goldBorder),
            ),
            child: const GemMark(color: Pal.goldDeep),
          ),
          const SizedBox(width: 10),
          const Text('Select Showroom'),
        ]),
        actions: [
          IconButton(
            tooltip: 'API Diagnostics',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const ApiInspector()),
            ),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          TextButton.icon(
            onPressed: app.logout,
            icon: const Icon(Icons.logout_rounded, size: 17),
            label: const Text('Sign out'),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: app.options.isEmpty
          ? _Unreadable(raw: app.sessionRaw, onRetry: app.refreshSession)
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
              children: [
                LuxuryHeroCard(
                  padding: const EdgeInsets.all(18),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const EnterpriseBadge('Working Context', icon: Icons.storefront_rounded),
                      const Spacer(),
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Panel(
                        padding: EdgeInsets.zero,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (e.key.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                              decoration: const BoxDecoration(
                                color: Pal.surfaceAlt,
                                border: Border(bottom: BorderSide(color: Pal.line)),
                              ),
                              child: Row(children: [
                                const Icon(Icons.account_balance_rounded, size: 17, color: Pal.goldDeep),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(e.key, style: T.body(13.5, w: FontWeight.w700)),
                                    Text(
                                      '${e.value.first.currency} · ${e.value.first.timezone}',
                                      style: T.body(11.5, color: Pal.muted),
                                    ),
                                  ]),
                                ),
                              ]),
                            ),
                          for (var i = 0; i < e.value.length; i++) ...[
                            if (i > 0) const Divider(),
                            InkWell(
                              onTap: _busyBranch != null ? null : () => _pick(e.value[i]),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                child: Row(children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: e.value[i].branchId == app.selectedBranchId
                                          ? Pal.tealWash
                                          : Pal.goldWash,
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      size: 20,
                                      color: e.value[i].branchId == app.selectedBranchId
                                          ? Pal.teal
                                          : Pal.goldDeep,
                                    ),
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(e.value[i].branchLabel, style: T.display(17.5)),
                                      const SizedBox(height: 4),
                                      Row(children: [
                                        if (e.value[i].branchCode.isNotEmpty) ...[
                                          MonoTag(e.value[i].branchCode),
                                          const SizedBox(width: 8),
                                        ],
                                        Text('Vault & POS Ready', style: T.body(12, color: Pal.muted)),
                                      ]),
                                    ]),
                                  ),
                                  _busyBranch == e.value[i].branchId
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2.2),
                                        )
                                      : const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: Pal.muted),
                                ]),
                              ),
                            ),
                          ],
                        ]),
                      ),
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
