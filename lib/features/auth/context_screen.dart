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
    // One showroom only: skip the picker.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      if (app.options.length == 1) _pick(app.options.first);
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
      final diag = '${api.log.take(6).map((e) => '${e.method} ${e.path} -> ${e.status ?? 'no reply'}').join('\n')}'
          '${ctx == null ? '' : '\n\n${ctx.note}'}';
      if (mounted) {
        setState(() {
          _diag = diag;
          _error = ex.code == 'CSRF_REJECTED'
              ? 'The server blocked this request (security check). Tap the pulse icon on top, run the check and send the result.'
              : ex.message;
          _busyBranch = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    // tenant -> entity -> branches, in server order
    final grouped = <String, Map<String, List<ShowroomOption>>>{};
    for (final o in app.options) {
      grouped.putIfAbsent(o.tenantLabel, () => {}).putIfAbsent(o.entityName, () => []).add(o);
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Choose showroom'),
        actions: [
          IconButton(
            tooltip: 'API check',
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApiInspector())),
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          TextButton(onPressed: app.logout, child: const Text('Sign out')),
          const SizedBox(width: 8),
        ],
      ),
      body: app.options.isEmpty
          ? _Unreadable(raw: app.sessionRaw, onRetry: app.refreshSession)
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Text(
                  app.userName.isEmpty ? 'Pick where you are working today.' : 'Hello, ${app.userName}. Pick where you are working today.',
                  style: T.body(15, color: Pal.muted),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: T.body(14, color: Pal.danger, w: FontWeight.w700)),
                  ),
                if (_diag != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SelectableText('$kBuild\n$_diag', style: T.body(11.5, color: Pal.muted)),
                  ),
                for (final t in grouped.entries) ...[
                  SectionLabel(t.key),
                  for (final e in t.value.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Panel(
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          if (e.key.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                              child: Row(children: [
                                const Icon(Icons.account_balance_outlined, size: 18, color: Pal.muted),
                                const SizedBox(width: 10),
                                Expanded(child: Text(e.key, style: T.body(14, color: Pal.muted, w: FontWeight.w700))),
                              ]),
                            ),
                          for (var i = 0; i < e.value.length; i++) ...[
                            if (i > 0 || e.key.isNotEmpty) const Divider(),
                            InkWell(
                              onTap: _busyBranch != null ? null : () => _pick(e.value[i]),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                child: Row(children: [
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(e.value[i].branchLabel, style: T.display(19)),
                                      if (e.value[i].branchCode.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text('Branch code ${e.value[i].branchCode}', style: T.body(13, color: Pal.muted)),
                                      ],
                                    ]),
                                  ),
                                  _busyBranch == e.value[i].branchId
                                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                                      : const Icon(Icons.chevron_right_rounded, color: Pal.muted),
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

/// Shown when /session returned no showroom we can recognise.
class _Unreadable extends StatelessWidget {
  const _Unreadable({required this.raw, required this.onRetry});
  final String raw;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        Text('No showroom found for this account', style: T.display(22)),
        const SizedBox(height: 8),
        Text(
          'Either this user has no branch access yet, or the server sends showrooms in a shape the app does not recognise. This is exactly what the server returned:',
          style: T.body(14, color: Pal.muted),
        ),
        const SizedBox(height: 14),
        Panel(
          color: const Color(0xFFEFEDE6),
          child: SelectableText(raw.isEmpty ? '(empty)' : raw, style: T.body(12, color: Pal.text)),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: raw));
                if (context.mounted) toast(context, 'Copied. Paste it in the chat.');
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: FilledButton(onPressed: onRetry, child: const Text('Reload'))),
        ]),
      ],
    );
  }
}
