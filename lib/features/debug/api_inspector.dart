import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/build.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

/// Live API Gateway Diagnostics & Request Inspector with 1-tap health ping.
class ApiInspector extends StatefulWidget {
  const ApiInspector({super.key});
  @override
  State<ApiInspector> createState() => _ApiInspectorState();
}

class _ApiInspectorState extends State<ApiInspector> {
  final _search = TextEditingController();
  String _filter = 'ALL';
  bool _pinging = false;
  String? _pingResult;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
    final q = _search.text.trim().toLowerCase();
    final okCnt = api.log.where((e) => e.ok).length;
    final errCnt = api.log.where((e) => !e.ok).length;
    final filtered = api.log.where((e) {
      if (_filter == 'OK' && !e.ok) return false;
      if (_filter == 'ERR' && e.ok) return false;
      if (q.isEmpty) return true;
      return '${e.method} ${e.path} ${e.status ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'API Gateway Diagnostics',
      icon: Icons.monitor_heart_outlined,
      searchController: _search,
      searchHint: 'Search by HTTP Method, Route or Status...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: 'Ping /health/live',
          onPressed: _pinging ? null : _pingHealth,
          icon: _pinging
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Pal.goldSoft))
              : const Icon(Icons.wifi_tethering_rounded, color: Pal.goldSoft),
        ),
        if (api.log.isNotEmpty)
          TextButton(
            onPressed: () {
              api.clearLog();
              setState(() {});
            },
            child: Text('Clear', style: T.body(12.5, color: Pal.goldSoft, w: FontWeight.w700)),
          ),
      ],
      topFilterBar: PillTabs<String>(
        value: _filter,
        onChanged: (v) => setState(() => _filter = v),
        tabs: [
          ('ALL', 'All (${api.log.length})'),
          ('OK', '2xx OK ($okCnt)'),
          ('ERR', 'Errors ($errCnt)'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          LuxuryHeroCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: EnterpriseBadge('Active API Gateway', icon: Icons.dns_outlined),
                  ),
                ),
                const SizedBox(width: 8),
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
          SectionLabel('Recent HTTP Calls (${filtered.length})'),
          if (filtered.isEmpty)
            const SaasEmptyBox(
              'No API calls match this filter. Every request, HTTP status, latency, and JSON payload appears here.',
            )
          else
            for (final e in filtered)
              LuxuryRecordCard(
                icon: e.ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                code: '${e.method} ${e.path}',
                status: e.ok ? '${e.status ?? 200} OK' : '${e.status ?? "ERR"} ERROR',
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
                lines: [
                  ('Timestamp', e.at.toIso8601String().substring(11, 19)),
                ],
                amountLabel: 'Latency',
                amountValue: '${e.durationMs}ms',
              ),
        ],
      ),
    );
  }
}
