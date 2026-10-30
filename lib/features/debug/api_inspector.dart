import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Shows what the server really answered, so screens can be matched to the
/// real API instead of guessed. Paste "Copy all" into the chat.
class ApiInspector extends StatefulWidget {
  const ApiInspector({super.key});
  @override
  State<ApiInspector> createState() => _ApiInspectorState();
}

class _ApiInspectorState extends State<ApiInspector> {
  bool _running = false;

  static const _checks = [
    '/session',
    '/rates',
    '/inventory',
    '/parties',
    '/pos-shifts/current',
    '/reports/sales-daily',
    '/reports/inventory-summary',
  ];

  Future<void> _run() async {
    final api = context.read<ApiClient>();
    setState(() => _running = true);
    for (final p in _checks) {
      try {
        await api.get(p);
      } catch (_) {}
      if (!mounted) return;
      setState(() {});
    }
    if (mounted) setState(() => _running = false);
  }

  Future<void> _copy(List<ApiLogEntry> log) async {
    final b = StringBuffer('Server: ${context.read<ApiClient>().baseUrl}\n\n');
    for (final e in log.reversed) {
      b.writeln('=== ${e.method} ${e.path} -> ${e.status ?? 'no response'}');
      b.writeln(e.body.length > 2500 ? '${e.body.substring(0, 2500)}\n...(cut)' : e.body);
      b.writeln(e.note);
      b.writeln();
    }
    await Clipboard.setData(ClipboardData(text: b.toString()));
    if (mounted) toast(context, 'Copied. Paste it in the chat.');
  }

  @override
  Widget build(BuildContext context) {
    final api = context.read<ApiClient>();
    final log = api.log;
    return Scaffold(
      appBar: AppBar(title: const Text('API check')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text(api.baseUrl, style: T.body(13, color: Pal.muted)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('Test endpoints'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: log.isEmpty ? null : () => _copy(log),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copy all'),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Sign in first, then tap Test endpoints. Passwords are never recorded.', style: T.body(12.5, color: Pal.muted)),
          const SizedBox(height: 16),
          if (log.isEmpty)
            const EmptyBlock(icon: Icons.monitor_heart_outlined, title: 'No requests yet', body: 'Sign in or tap Test endpoints, and every server reply shows up here.'),
          for (final e in log)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Panel(
                padding: EdgeInsets.zero,
                child: Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    title: Text('${e.method}  ${e.path}', style: T.body(14.5, w: FontWeight.w800)),
                    trailing: StatusPill(e.status == null ? 'No reply' : '${e.status}', tone: e.ok ? Tone.ok : Tone.bad),
                    children: [
                      Align(alignment: Alignment.centerLeft, child: SelectableText(e.body, style: T.body(12))),
                      const SizedBox(height: 10),
                      Align(alignment: Alignment.centerLeft, child: SelectableText(e.note, style: T.body(11.5, color: Pal.muted))),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
