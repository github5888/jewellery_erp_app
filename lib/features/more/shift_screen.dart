import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';

/// POS Counter Cash Drawer Shift Management.
/// Queries `/pos-shifts` (live endpoint on pos.hrpocket.in) with fallback to `/pos-shifts/current`.
class ShiftScreen extends StatefulWidget {
  const ShiftScreen({super.key});
  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final _search = TextEditingController();
  String _tab = 'DRAWER';
  Map<String, dynamic>? _activeShift;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  final _cash = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _cash.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _isOpen => _activeShift != null && _activeShift!.isNotEmpty;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      dynamic d;
      try {
        d = await context.read<ApiClient>().get('/pos-shifts');
      } on ApiException catch (e) {
        if (e.status == 404 || e.code == 'HTTP_ERROR') {
          d = await context.read<ApiClient>().get('/pos-shifts/current');
        } else {
          rethrow;
        }
      }
      _parseShiftResponse(d);
    } on ApiException catch (e) {
      if (e.status == 404 || e.code == 'HTTP_ERROR') {
        if (mounted) {
          setState(() {
            _activeShift = null;
            _history = [];
          });
        }
      } else if (mounted) {
        setState(() => _error = e.message);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _parseShiftResponse(dynamic d) {
    Map<String, dynamic>? current;
    var list = <Map<String, dynamic>>[];

    if (d is Map) {
      if (d['current'] is Map) {
        current = Map<String, dynamic>.from(d['current'] as Map);
      } else if (d['currentShift'] is Map) {
        current = Map<String, dynamic>.from(d['currentShift'] as Map);
      } else if (d['activeShift'] is Map) {
        current = Map<String, dynamic>.from(d['activeShift'] as Map);
      }
      if (d['shifts'] is List || d['items'] is List || d['history'] is List) {
        list = asList(d, keys: const ['shifts', 'items', 'history']);
      } else if (current == null && (d['id'] != null || d['status'] != null || d['openingCash'] != null)) {
        final single = Map<String, dynamic>.from(d);
        list = [single];
      }
    } else if (d is List) {
      list = asList(d);
    }

    if (current == null) {
      for (final s in list) {
        final st = '${s['status'] ?? s['state'] ?? ''}'.toUpperCase();
        if (st == 'OPEN' || st == 'ACTIVE') {
          current = s;
          break;
        }
      }
    } else {
      final st = '${current['status'] ?? current['state'] ?? 'OPEN'}'.toUpperCase();
      if (st != 'OPEN' && st != 'ACTIVE') current = null;
    }

    if (mounted) {
      setState(() {
        _activeShift = current;
        _history = list;
      });
    }
  }

  Future<void> _act(bool open) async {
    if (!isValidAmount(_cash.text)) {
      setState(() => _error = 'Enter a valid cash amount in INR (up to 2 decimal places).');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final amount = normAmount(_cash.text);
    final key = const Uuid().v4();
    try {
      await context.read<ApiClient>().post(
            open ? '/pos-shifts/open' : '/pos-shifts/close',
            idempotencyKey: key,
            body: {
              open ? 'openingCash' : 'closingCash': amount,
              if (_activeShift?['id'] != null && !open) 'shiftId': _activeShift!['id'],
              if (_notes.text.trim().isNotEmpty) 'remarks': _notes.text.trim(),
            },
          );
      _cash.clear();
      _notes.clear();
      await _load();
      if (mounted) {
        toast(context, open ? 'Counter shift opened.' : 'Counter shift reconciled & closed.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _busy = false);
  }

  String _pick(Map<String, dynamic> m, List<String> keys, [String fallback = '']) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final fHistory = _history.where((s) {
      if (q.isEmpty) return true;
      return '${_pick(s, ['shiftNumber', 'code', 'counterName'])} ${_pick(s, ['status', 'state'])}'
          .toLowerCase()
          .contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'POS Counter Shifts',
      icon: Icons.point_of_sale_rounded,
      searchController: _tab == 'HISTORY' ? _search : null,
      searchHint: 'Search by Shift # or Status...',
      onSearchChanged: _tab == 'HISTORY' ? (_) => setState(() {}) : null,
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
          ('DRAWER', _isOpen ? 'Active Drawer (Open)' : 'Counter Drawer'),
          ('HISTORY', 'Shift Register (${_history.length})'),
        ],
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
          children: [
            if (_loading) ...[
              const Panel(child: Skeleton(height: 110)),
              const SizedBox(height: 12),
              const Panel(child: Skeleton(height: 90)),
            ] else if (_tab == 'HISTORY') ...[
              if (fHistory.isEmpty)
                const SaasEmptyBox('No counter shift records found.')
              else
                for (final s in fHistory)
                  LuxuryRecordCard(
                    icon: Icons.point_of_sale_rounded,
                    code: _pick(s, ['shiftNumber', 'code', 'counterName'], 'Counter Shift'),
                    status: _pick(s, ['status', 'state'], 'CLOSED'),
                    lines: [
                      ('Opening Float', inr(_pick(s, ['openingCash', 'openingBalance'], '0.00'))),
                      if (_pick(s, ['openedAt', 'createdAt']).isNotEmpty)
                        ('Opened', formatDateTime(_pick(s, ['openedAt', 'createdAt']))),
                      if (_pick(s, ['closedAt']).isNotEmpty)
                        ('Closed', formatDateTime(_pick(s, ['closedAt']))),
                    ],
                    amountLabel: _pick(s, ['closingCash', 'closingBalance']).isNotEmpty
                        ? 'Closing Cash'
                        : 'Opening Float',
                    amountValue: inr(
                      _pick(
                        s,
                        ['closingCash', 'closingBalance', 'openingCash', 'openingBalance'],
                        '0.00',
                      ),
                    ),
                  ),
            ] else ...[
              LuxuryHeroCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: EnterpriseBadge(
                          _isOpen ? 'Drawer Active' : 'Drawer Closed',
                          icon: _isOpen ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(_isOpen ? 'OPEN' : 'CLOSED'),
                  ]),
                  const SizedBox(height: 14),
                  Text(
                    _isOpen ? 'Counter Shift is Open' : 'No Active Counter Shift',
                    style: T.display(23, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _isOpen
                        ? 'Cash receipts and POS quick-bills are being recorded in the active drawer.'
                        : 'Open a shift with your counted opening float before taking counter cash payments.',
                    style: T.body(12.8, color: Colors.white.withValues(alpha: 0.74)),
                  ),
                  if (_isOpen && _activeShift != null) ...[
                    const SizedBox(height: 14),
                    Divider(color: Colors.white.withValues(alpha: 0.14)),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('OPENING FLOAT', style: T.caps(9.5, color: Colors.white60)),
                          const SizedBox(height: 3),
                          Text(
                            inr(_pick(_activeShift!, ['openingCash', 'openingBalance', 'floatAmount'], '0.00')),
                            style: T.display(20, color: Pal.goldSoft),
                          ),
                        ]),
                      ),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('OPENED AT', style: T.caps(9.5, color: Colors.white60)),
                          const SizedBox(height: 3),
                          Text(
                            formatDateTime(_pick(_activeShift!, ['openedAt', 'createdAt', 'startTime'])),
                            style: T.body(12, color: Colors.white, w: FontWeight.w600),
                          ),
                        ]),
                      ),
                    ]),
                  ],
                ]),
              ),
              SectionLabel(_isOpen ? 'Reconcile & Close Drawer' : 'Start New Counter Shift'),
              SaasFormCard(
                title: _isOpen ? 'Counted Closing Cash' : 'Opening Cash Float',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  FieldLabel(_isOpen ? 'Counted Closing Cash (INR)' : 'Opening Cash Float (INR)'),
                  TextField(
                    controller: _cash,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: T.display(22),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      hintText: '0.00',
                      helperText: _isOpen
                          ? 'Count physical notes and coins in the drawer before closing.'
                          : 'Enter starting petty cash / float placed in the counter drawer.',
                    ),
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Reconciliation Notes (Optional)'),
                  TextField(
                    controller: _notes,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Counter 1 morning handover verified',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: T.body(13, color: Pal.danger, w: FontWeight.w700)),
                    ),
                  const SizedBox(height: 16),
                  RoyalGoldButton(
                    busy: _busy,
                    icon: _isOpen ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                    label: _isOpen ? 'Close & Reconcile Shift' : 'Open Counter Shift',
                    onPressed: _busy ? null : () => _act(!_isOpen),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
