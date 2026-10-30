import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/build.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Live API Gateway Diagnostics & Request Inspector with 1-tap health ping.
class ApiInspector extends StatefulWidget {
  const ApiInspector({super.key});
  @override
  State<ApiInspector> createState() => _ApiInspectorState();
}

class _ApiInspectorState extends State<ApiInspector> {
  bool _pinging = false;
  String? _pingResult;

  Future<void> _pingHealth() async {
    setState(() {
      _pinging = true;
      _pingResult = null;
    });
    try {
      final d = asMap(await context.read<ApiClient>().get('/health/live'));
      if (mounted) {
        setState(() => _pingResult = 'Gateway Healthy (${d['status'] ?? 'ok'})');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _pingResult = 'Error: ${e.message}');
    }
    if (mounted) setState(() => _pinging = false);
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiClient>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Gateway Diagnostics'),
        actions: [
          IconButton(
            tooltip: 'Ping /health/live',
            onPressed: _pinging ? null : _pingHealth,
            icon: _pinging
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering_rounded),
          ),
          if (api.log.isNotEmpty)
            TextButton(
              onPressed: () {
                api.clearLog();
                setState(() {});
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          LuxuryHeroCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const EnterpriseBadge('Active API Gateway', icon: Icons.dns_outlined),
                const Spacer(),
                Text(kBuildVersion, style: T.mono(11, color: Colors.white60)),
              ]),
              const SizedBox(height: 10),
              SelectableText(api.baseUrl, style: T.mono(13.5, color: Pal.goldSoft, w: FontWeight.w700)),
              if (_pingResult != null) ...[
                const SizedBox(height: 8),
                Text(
                  _pingResult!,
                  style: T.body(
                    12.5,
                    color: _pingResult!.startsWith('Error') ? const Color(0xFFFCA5A5) : const Color(0xFF6EE7B7),
                    w: FontWeight.w700,
                  ),
                ),
              ],
            ]),
          ),
          SectionLabel('Recent HTTP Calls (${api.log.length})'),
          if (api.log.isEmpty)
            const Panel(
              child: EmptyBlock(
                icon: Icons.http_rounded,
                title: 'No requests logged yet',
                body: 'Every API call, HTTP status, latency, and JSON payload appears here for instant field debugging.',
              ),
            )
          else
            for (final e in api.log)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => DraggableScrollableSheet(
                      expand: false,
                      initialChildSize: 0.72,
                      maxChildSize: 0.94,
                      builder: (ctx, sc) => ListView(
                        controller: sc,
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                        children: [
                          Row(children: [
                            Expanded(child: Text('${e.method} ${e.path}', style: T.mono(14, w: FontWeight.w700))),
                            IconButton(
                              tooltip: 'Copy JSON',
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: e.summary));
                                toast(ctx, 'Response payload copied.');
                              },
                            ),
                          ]),
                          Text('HTTP ${e.status ?? "ERR"} · ${e.durationMs}ms · ${e.at.toIso8601String()}', style: T.mono(11.5, color: Pal.muted)),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Pal.obsidian,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: SelectableText(
                              e.summary,
                              style: T.mono(12, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      StatusPill(
                        '${e.status ?? "ERR"}',
                        tone: e.ok ? Tone.ok : Tone.danger,
                      ),
                      const SizedBox(width: 8),
                      MonoTag(e.method),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.path,
                          style: T.mono(12.5, w: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text('${e.durationMs}ms', style: T.mono(11, color: Pal.muted)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      e.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: T.mono(11.2, color: Pal.muted),
                    ),
                  ]),
                ),
              ),
        ],
      ),
    );
  }
}
