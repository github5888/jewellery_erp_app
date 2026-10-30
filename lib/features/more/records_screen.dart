import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

/// Formatted enterprise register fallback for custom or future endpoints.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({
    super.key,
    required this.title,
    required this.path,
    this.emptyTitle = 'No records yet',
    this.emptyBody = 'Records created on the web portal or mobile app will synchronize here live.',
  });
  final String title;
  final String path;
  final String emptyTitle;
  final String emptyBody;
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _search = TextEditingController();
  dynamic _data;
  bool _loading = true;
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await context.read<ApiClient>().get(widget.path);
      if (mounted) setState(() => _data = d);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return LuxuryModuleScaffold(
      title: widget.title,
      icon: Icons.folder_open_rounded,
      searchController: _search,
      searchHint: 'Search records...',
      onSearchChanged: (_) => setState(() {}),
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
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: _children(),
        ),
      ),
    );
  }

  List<Widget> _children() {
    if (_loading) {
      return [
        for (var i = 0; i < 4; i++)
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 60))),
      ];
    }
    if (_error != null) return [ErrorBlock(_error!, onRetry: _load)];
    final d = _data;
    final hasList =
        d is List || (d is Map && d.values.any((v) => v is List && v.isNotEmpty && v.first is Map));
    if (hasList) {
      final q = _search.text.trim().toLowerCase();
      final items = asList(d).where((m) {
        if (q.isEmpty) return true;
        return m.values.map((v) => '$v').join(' ').toLowerCase().contains(q);
      }).toList();
      if (items.isEmpty) {
        return [SaasEmptyBox(widget.emptyBody)];
      }
      return [for (final m in items) _RecordTile(m)];
    }
    final map = asMap(d);
    final scalars = map.entries.where((e) => e.value is! Map && e.value is! List).toList();
    if (scalars.isEmpty) {
      return [SaasEmptyBox(widget.emptyBody)];
    }
    return [
      Panel(child: Column(children: [for (final e in scalars) KeyValue(humanize(e.key), _fmt(e.key, e.value))])),
    ];
  }
}

String _fmt(String key, dynamic v) {
  if (v == null) return '-';
  final k = key.toLowerCase();
  final s = '$v';
  if (looksNumeric(s)) {
    if (k.contains('weight') || k.contains('gram')) return grams(s);
    if (k.contains('amount') ||
        k.contains('value') ||
        k.contains('credit') ||
        k.contains('total') ||
        k.contains('rate') ||
        k.contains('balance') ||
        k.contains('price') ||
        k.contains('cost')) {
      return inr(s);
    }
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return formatDate(s);
  return s;
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.m);
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    const titleKeys = [
      'invoiceNumber',
      'documentNumber',
      'shiftNumber',
      'memoNumber',
      'voucherNumber',
      'jobNumber',
      'number',
      'tag',
      'reference',
      'name',
      'displayName',
      'code',
      'id',
    ];
    String? titleKey;
    for (final k in titleKeys) {
      if (m[k] != null && '${m[k]}'.isNotEmpty) {
        titleKey = k;
        break;
      }
    }
    final status = (m['status'] ?? m['state']) == null ? null : '${m['status'] ?? m['state']}';
    final rows = m.entries
        .where((e) =>
            e.key != titleKey &&
            e.key != 'status' &&
            e.key != 'state' &&
            e.value is! Map &&
            e.value is! List &&
            e.value != null &&
            !e.key.toLowerCase().endsWith('id') &&
            '${e.value}'.isNotEmpty)
        .take(5)
        .toList();
    return LuxuryRecordCard(
      icon: Icons.description_outlined,
      code: titleKey == null ? 'Record' : '${m[titleKey]}',
      status: status ?? 'RECORD',
      lines: [
        for (final e in rows) (humanize(e.key), _fmt(e.key, e.value)),
      ],
    );
  }
}
