import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

/// Read-only viewer for list/report endpoints whose exact shape is still
/// settling (approval memos, job work, procurement, rate fixing, reports).
/// Swap for a dedicated screen once the contracts package is wired in.
class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key, required this.title, required this.path, this.emptyTitle = 'Nothing here yet', this.emptyBody = 'Records created in the web portal or the app will show up here.'});
  final String title;
  final String path;
  final String emptyTitle;
  final String emptyBody;
  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  dynamic _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: RefreshIndicator(
        color: Pal.ink,
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: _children()),
      ),
    );
  }

  List<Widget> _children() {
    if (_loading) {
      return [for (var i = 0; i < 4; i++) const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 56)))];
    }
    if (_error != null) return [ErrorBlock(_error!, onRetry: _load)];
    final d = _data;
    final hasList = d is List || (d is Map && d.values.any((v) => v is List && v.isNotEmpty && v.first is Map));
    if (hasList) {
      final items = asList(d);
      if (items.isEmpty) return [EmptyBlock(icon: Icons.inbox_outlined, title: widget.emptyTitle, body: widget.emptyBody)];
      return [for (final m in items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _RecordTile(m))];
    }
    final map = asMap(d);
    final scalars = map.entries.where((e) => e.value is! Map && e.value is! List).toList();
    if (scalars.isEmpty) return [EmptyBlock(icon: Icons.inbox_outlined, title: widget.emptyTitle, body: widget.emptyBody)];
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
    if (k.contains('amount') || k.contains('value') || k.contains('credit') || k.contains('total') || k.contains('rate') || k.contains('balance') || k.contains('price')) {
      return inr(s);
    }
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) return s.substring(0, 10);
  return s;
}

class _RecordTile extends StatelessWidget {
  const _RecordTile(this.m);
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    const titleKeys = ['invoiceNumber', 'documentNumber', 'shiftNumber', 'memoNumber', 'voucherNumber', 'jobNumber', 'number', 'tag', 'reference', 'name', 'displayName', 'code', 'id'];
    String? titleKey;
    for (final k in titleKeys) {
      if (m[k] != null && '${m[k]}'.isNotEmpty) {
        titleKey = k;
        break;
      }
    }
    final status = m['status'] == null ? null : '${m['status']}';
    final rows = m.entries
        .where((e) => e.key != titleKey && e.key != 'status' && e.value is! Map && e.value is! List && e.value != null && !e.key.toLowerCase().endsWith('id') && '${e.value}'.isNotEmpty)
        .take(4)
        .toList();
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(titleKey == null ? 'Record' : '${m[titleKey]}', style: T.display(19), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (status != null) StatusPill(status),
        ]),
        if (rows.isNotEmpty) const SizedBox(height: 8),
        for (final e in rows) KeyValue(humanize(e.key), _fmt(e.key, e.value)),
      ]),
    );
  }
}
