import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../billing/billing_controller.dart';
import 'scanner_page.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, this.onJumpToBilling});
  final VoidCallback? onJumpToBilling;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  String _tab = 'ARTICLES';
  String _statusFilter = 'ALL';
  List<Article> _articles = [];
  List<MaterialLotItem> _lots = [];
  List<StockLocationItem> _locations = [];
  List<ReservationItem> _reservations = [];
  List<Map<String, dynamic>> _transformations = [];
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
      final d = await context.read<ApiClient>().get('/inventory');
      if (!mounted) return;
      if (d is Map && d.containsKey('articles')) {
        setState(() {
          _articles = asList(d, keys: const ['articles']).map(Article.fromJson).toList();
          _lots = asList(d, keys: const ['materialLots']).map(MaterialLotItem.fromJson).toList();
          _locations = asList(d, keys: const ['locations']).map(StockLocationItem.fromJson).toList();
          _reservations = asList(d, keys: const ['reservations']).map(ReservationItem.fromJson).toList();
          _transformations = asList(d, keys: const ['materialTransformations']);
        });
      } else {
        setState(() {
          _articles = asList(d).map(Article.fromJson).toList();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Article> get _filteredArticles {
    final q = _search.text.trim().toLowerCase();
    return _articles.where((a) {
      if (_statusFilter != 'ALL' && a.status.toUpperCase() != _statusFilter) return false;
      if (q.isEmpty) return true;
      return a.barcode.toLowerCase().contains(q) ||
          a.name.toLowerCase().contains(q) ||
          a.metal.toLowerCase().contains(q) ||
          a.purity.toLowerCase().contains(q) ||
          a.locationName.toLowerCase().contains(q);
    }).toList();
  }

  Decimal get _totalFineGrams {
    var sum = Decimal.zero;
    for (final a in _articles) {
      if (a.status.toUpperCase() != 'SOLD') {
        sum += decOrZero(a.fineWeight);
      }
    }
    for (final l in _lots) {
      sum += decOrZero(l.fineGrams);
    }
    return sum;
  }

  Future<void> _scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (code == null || !mounted) return;
    _search.text = code;
    setState(() => _tab = 'ARTICLES');
    final exact = _articles.where((a) => a.barcode.toUpperCase() == code.toUpperCase()).toList();
    if (exact.isNotEmpty) {
      _showArticleSheet(exact.first);
    } else {
      await _lookupByTag(code);
    }
  }

  Future<void> _lookupByTag(String code) async {
    try {
      final d = await context.read<ApiClient>().get('/inventory', query: {'barcode': code});
      if (!mounted) return;
      Article? found;
      if (d is Map && d['articles'] is List) {
        final list = asList(d, keys: const ['articles']).map(Article.fromJson).toList();
        for (final a in list) {
          if (a.barcode.toUpperCase() == code.toUpperCase()) {
            found = a;
            break;
          }
        }
      } else {
        final m = asMap(d);
        if (m['barcode'] != null || m['tag'] != null) found = Article.fromJson(m);
      }
      if (found != null) {
        _showArticleSheet(found);
      } else {
        toast(context, 'No ornament matched tag "$code".', error: true);
      }
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
  }

  Future<void> _receiveSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReceiveArticleSheet(locations: _locations),
    );
    if (created == true) _load();
  }

  Future<void> _receiveLotSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReceiveMaterialLotSheet(locations: _locations),
    );
    if (created == true) _load();
  }

  Future<void> _createLocationSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateLocationSheet(),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredArticles;
    final availableCount = _articles.where((a) => a.isAvailable).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault & Tagged Stock'),
        actions: [
          IconButton(
            tooltip: 'Scan Tag',
            onPressed: _scan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
          ),
          IconButton(
            tooltip: 'Refresh Vault',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _receiveSheet,
        backgroundColor: Pal.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_box_outlined),
        label: Text('Receive Piece', style: T.body(13.5, color: Colors.white, w: FontWeight.w700)),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search tag, ornament, purity or vault…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 50,
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Pal.obsidian,
                  foregroundColor: Pal.goldSoft,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 50),
                ),
                onPressed: _scan,
                child: const Icon(Icons.qr_code_scanner_rounded),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: PillTabs<String>(
            selected: _tab,
            onChanged: (v) => setState(() => _tab = v),
            items: [
              ('ARTICLES', 'Tagged (${_articles.length})', Icons.diamond_outlined),
              ('LOTS', 'Bullion Lots (${_lots.length})', Icons.layers_outlined),
              ('VAULTS', 'Vaults (${_locations.length})', Icons.account_balance_outlined),
              ('TRANSFORM', 'Transform (${_transformations.length})', Icons.merge_type_rounded),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: Pal.teal,
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 96),
              children: [
                // Custody Summary Strip
                Panel(
                  color: Pal.obsidian,
                  borderColor: Pal.goldBright.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(children: [
                    Expanded(
                      child: _statCol('AVAILABLE', '$availableCount / ${_articles.length} pcs'),
                    ),
                    Container(width: 1, height: 28, color: Colors.white12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: _statCol('BULLION LOTS', '${_lots.length} active'),
                      ),
                    ),
                    Container(width: 1, height: 28, color: Colors.white12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: _statCol('PURE 999 WT', fineGrams(_totalFineGrams.toString()), gold: true),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  for (var i = 0; i < 4; i++)
                    const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 82)))
                else if (_error != null)
                  ErrorBlock(_error!, onRetry: _load)
                else if (_tab == 'ARTICLES') ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final f in const [
                        ('ALL', 'All Pieces'),
                        ('AVAILABLE', 'Available'),
                        ('RESERVED', 'Reserved'),
                        ('SOLD', 'Sold'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 10),
                          child: ChoiceChip(
                            label: Text(f.$2),
                            selected: _statusFilter == f.$1,
                            showCheckmark: false,
                            selectedColor: Pal.goldWash,
                            onSelected: (_) => setState(() => _statusFilter = f.$1),
                          ),
                        ),
                    ]),
                  ),
                  if (filtered.isEmpty)
                    Panel(
                      child: EmptyBlock(
                        icon: Icons.diamond_outlined,
                        title: 'No matching tagged pieces',
                        body: 'Receive ornaments into a showroom vault or counter tray, or scan another tag.',
                        actionLabel: 'Receive Piece',
                        onAction: _receiveSheet,
                      ),
                    )
                  else
                    for (final a in filtered)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ArticleCard(article: a, onTap: () => _showArticleSheet(a)),
                      ),
                ] else if (_tab == 'LOTS') ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ElevatedButton.icon(
                        onPressed: _receiveLotSheet,
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Receive fungible material lot'),
                      ),
                    ),
                  ),
                  if (_lots.isEmpty)
                    const Panel(
                      child: EmptyBlock(
                        icon: Icons.layers_outlined,
                        title: 'No fungible bullion lots',
                        body: 'Pure gold bars, granules, and scrap lots received into the vault appear here.',
                      ),
                    )
                  else
                    for (final l in _lots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Panel(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              MonoTag(l.lotCode),
                              const SizedBox(width: 8),
                              Chip2('${l.metal} ${l.purityLabel}', gold: true),
                              const Spacer(),
                              StatusPill(l.form),
                            ]),
                            const SizedBox(height: 8),
                            KeyValue('Vault Location', l.locationName.isEmpty ? '-' : l.locationName),
                            KeyValue('Gross Quantity', grams(l.quantityGrams), mono: true),
                            KeyValue('Pure 999 Content', fineGrams(l.fineGrams), strong: true, valueColor: Pal.goldDeep),
                          ]),
                        ),
                      ),
                ] else if (_tab == 'TRANSFORM') ...[
                  _MaterialTransformationView(
                    transformations: _transformations,
                    onTransformed: _load,
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton.icon(
                        onPressed: _createLocationSheet,
                        icon: const Icon(Icons.add_location_alt_outlined, size: 17),
                        label: const Text('New stock location'),
                      ),
                    ),
                  ),
                  if (_locations.isEmpty)
                    const Panel(
                      child: EmptyBlock(
                        icon: Icons.account_balance_outlined,
                        title: 'No vault locations configured',
                        body: 'Configure showroom vaults and display trays on the web portal.',
                      ),
                    )
                  else
                    for (final loc in _locations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Panel(
                          child: Row(children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: loc.type == 'VAULT' ? Pal.goldWash : Pal.tealWash,
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                loc.type == 'VAULT' ? Icons.lock_outline_rounded : Icons.storefront_outlined,
                                color: loc.type == 'VAULT' ? Pal.goldDeep : Pal.teal,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(loc.name, style: T.body(14.5, w: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Row(children: [
                                  MonoTag(loc.code),
                                  const SizedBox(width: 6),
                                  Text(loc.type, style: T.caps(9.5, color: Pal.muted)),
                                ]),
                              ]),
                            ),
                            Text(
                              '${_articles.where((a) => a.locationId == loc.id).length} pcs',
                              style: T.mono(13, w: FontWeight.w700),
                            ),
                          ]),
                        ),
                      ),
                  if (_reservations.isNotEmpty) ...[
                    SectionLabel('Active Custody Reservations (${_reservations.length})'),
                    for (final r in _reservations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Panel(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              MonoTag(r.articleTag.isEmpty ? r.id.substring(0, 8) : r.articleTag),
                              const Spacer(),
                              StatusPill(r.state),
                            ]),
                            const SizedBox(height: 8),
                            KeyValue('Reference', r.referenceType),
                            if (r.expiresAt.isNotEmpty) KeyValue('Hold Expires', formatDateTime(r.expiresAt)),
                          ]),
                        ),
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _statCol(String label, String val, {bool gold = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: T.caps(9, color: Colors.white60)),
        const SizedBox(height: 3),
        Text(
          val,
          style: T.mono(12.5, color: gold ? Pal.goldSoft : Colors.white, w: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ]);

  void _showArticleSheet(Article a) {
    final rates = context.read<RatesController>();
    final mRate = rates.find(a.metal, a.purity.isEmpty ? '916' : a.purity);
    final estMetal = (mRate != null && decOrZero(mRate.sell) > Decimal.zero)
        ? (decOrZero(a.effectiveNetWeight) * decOrZero(mRate.sell)).round(scale: 2)
        : Decimal.zero;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(a.name.isEmpty ? a.barcode : a.name, style: T.display(22))),
            if (a.status.isNotEmpty) StatusPill(a.status),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            MonoTag(a.barcode),
            Chip2('${a.metal} ${a.karatLabel}', gold: true),
            if (a.locationName.isNotEmpty) Chip2(a.locationName),
          ]),
          const SizedBox(height: 14),
          WeightBreakdownBar(
            grossGrams: a.grossWeight,
            netGrams: a.effectiveNetWeight,
            stoneGrams: a.stoneWeight,
            fineGramsValue: a.fineWeight,
          ),
          const SizedBox(height: 12),
          Panel(
            color: Pal.surfaceAlt,
            child: Column(children: [
              KeyValue('Gross Weight', grams(a.grossWeight), mono: true),
              KeyValue('Net Metal Weight', grams(a.effectiveNetWeight), mono: true),
              if (decOrZero(a.stoneWeight) > Decimal.zero)
                KeyValue('Stone / Kundan Wt', grams(a.stoneWeight), mono: true),
              if (a.fineWeight.isNotEmpty && decOrZero(a.fineWeight) > Decimal.zero)
                KeyValue('Pure Fine 999 Wt', fineGrams(a.fineWeight), mono: true, strong: true),
              if (a.carryingCost.isNotEmpty && decOrZero(a.carryingCost) > Decimal.zero)
                KeyValue('Vault Carrying Cost', inr(a.carryingCost), mono: true),
              if (estMetal > Decimal.zero)
                KeyValue('Est. Live Metal Value', inr(estMetal.toStringAsFixed(2)), strong: true, valueColor: Pal.teal),
              if (a.makingCharges.isNotEmpty && decOrZero(a.makingCharges) > Decimal.zero)
                KeyValue('Making Charges', inr(a.makingCharges), mono: true),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Pal.teal),
            onPressed: a.status.toUpperCase() == 'SOLD'
                ? null
                : () async {
                    final billing = context.read<BillingController>();
                    Navigator.pop(ctx);
                    final added = await billing.addArticle(a);
                    if (!mounted) return;
                    if (added) {
                      toast(context, '${a.barcode} added to POS Bill.');
                      widget.onJumpToBilling?.call();
                    } else if (billing.error != null) {
                      toast(context, billing.error!, error: true);
                    }
                  },
            icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
            label: const Text('Add Ornament to POS Bill'),
          ),
        ]),
      ),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, required this.onTap});
  final Article article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = article;
    return Panel(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Pal.goldWash,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Pal.gold.withValues(alpha: 0.45)),
            ),
            child: const Icon(Icons.diamond_outlined, size: 19, color: Pal.goldDeep),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                a.name.isEmpty ? a.barcode : a.name,
                style: T.body(15, w: FontWeight.w800),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Row(children: [
                MonoTag(a.barcode),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    a.locationName.isEmpty ? '${a.metal} ${a.karatLabel}' : a.locationName,
                    style: T.body(11.8, color: Pal.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          if (a.status.isNotEmpty) StatusPill(a.status),
        ]),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: Pal.surfaceAlt,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(children: [
            Chip2('${a.metal} ${a.karatLabel}', gold: true),
            const Spacer(),
            Text('Gross ${grams(a.grossWeight)}', style: T.mono(12, color: Pal.muted)),
            const SizedBox(width: 10),
            Text('Net ${grams(a.effectiveNetWeight)}', style: T.mono(12.5, w: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }
}

class _ReceiveArticleSheet extends StatefulWidget {
  const _ReceiveArticleSheet({required this.locations});
  final List<StockLocationItem> locations;
  @override
  State<_ReceiveArticleSheet> createState() => _ReceiveArticleSheetState();
}

class _ReceiveArticleSheetState extends State<_ReceiveArticleSheet> {
  final _tag = TextEditingController();
  final _desc = TextEditingController();
  final _gross = TextEditingController();
  final _net = TextEditingController();
  final _cost = TextEditingController();

  String? _locationId;
  List<Map<String, dynamic>> _metals = [];
  String? _metalId;
  String? _purityGradeId;
  bool _loadingMeta = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.locations.isNotEmpty) _locationId = widget.locations.first.id;
    _loadMaterials();
  }

  @override
  void dispose() {
    _tag.dispose();
    _desc.dispose();
    _gross.dispose();
    _net.dispose();
    _cost.dispose();
    super.dispose();
  }

  Future<void> _loadMaterials() async {
    try {
      final d = await context.read<ApiClient>().get('/materials');
      final list = asList(d, keys: const ['metals']);
      if (mounted) {
        setState(() {
          _metals = list;
          if (list.isNotEmpty) {
            final gold = list.firstWhere((m) => '${m['code']}' == 'GOLD', orElse: () => list.first);
            _metalId = '${gold['id']}';
            final grades = gold['purityGrades'] is List ? (gold['purityGrades'] as List) : const [];
            if (grades.isNotEmpty) {
              final g22 = grades.firstWhere(
                (g) => g is Map && '${g['code']}'.contains('22'),
                orElse: () => grades.first,
              );
              if (g22 is Map) _purityGradeId = '${g22['id']}';
            }
          }
          _loadingMeta = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  List<Map<String, dynamic>> get _gradesForSelectedMetal {
    final m = _metals.where((x) => '${x['id']}' == _metalId).toList();
    if (m.isEmpty || m.first['purityGrades'] is! List) return const [];
    return (m.first['purityGrades'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Future<void> _submit() async {
    if (_locationId == null || _locationId!.isEmpty) {
      setState(() => _err = 'No stock location available in this branch.');
      return;
    }
    if (_metalId == null || _purityGradeId == null) {
      setState(() => _err = 'Select metal & purity grade.');
      return;
    }
    if (_desc.text.trim().length < 3) {
      setState(() => _err = 'Enter ornament description (min 3 chars).');
      return;
    }
    if (!isValidWeight(_gross.text) || !isValidWeight(_net.text) || !isValidAmount(_cost.text)) {
      setState(() => _err = 'Enter valid gross weight, net metal weight, and carrying cost.');
      return;
    }
    if (decOrZero(_net.text) > decOrZero(_gross.text)) {
      setState(() => _err = 'Net metal weight cannot exceed gross weight.');
      return;
    }

    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      const uuid = Uuid();
      await context.read<ApiClient>().post(
        '/inventory/articles/receive',
        idempotencyKey: uuid.v4(),
        body: {
          'locationId': _locationId,
          'tag': _tag.text.trim().toUpperCase(),
          'description': _desc.text.trim(),
          'grossWeightGrams': normWeight6(_gross.text),
          'ownershipKind': 'ENTITY',
          'sourceType': 'OPENING_STOCK',
          'sourceId': uuid.v4(),
          'businessDate': todayIso(),
          'reason': 'Mobile showroom vault inward tag registration',
          'carryingCost': normAmount(_cost.text),
          'currency': 'INR',
          'components': [
            {
              'metalId': _metalId,
              'purityGradeId': _purityGradeId,
              'weightGrams': normWeight6(_net.text),
            },
          ],
        },
      );
      if (mounted) {
        toast(context, 'Tagged ornament ${_tag.text.trim().toUpperCase()} received into vault.');
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _err = e.code == 'MFA_REQUIRED'
            ? 'Two-factor authentication is required to receive vault stock. Enroll 2FA in Operations > Security.'
            : e.message);
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final grades = _gradesForSelectedMetal;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Receive Tagged Ornament', style: T.display(22)),
        const SizedBox(height: 14),
        if (_loadingMeta)
          const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()))
        else ...[
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Ornament Tag'),
                TextField(
                  controller: _tag,
                  style: T.mono(13.5),
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'Tag / Barcode'),
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Vault / Tray'),
                GoldDropdown<String>(
                  value: _locationId,
                  items: [
                    for (final l in widget.locations)
                      DropdownMenuItem(value: l.id, child: Text(l.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _locationId = v),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          const FieldLabel('Ornament Description'),
          TextField(
            controller: _desc,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Enter ornament description'),
          ),
          const SizedBox(height: 12),
          if (grades.isNotEmpty) ...[
            const FieldLabel('Purity Grade'),
            Wrap(spacing: 8, runSpacing: 6, children: [
              for (final g in grades)
                ChoiceChip(
                  label: Text('${g['displayName'] ?? g['code']}'),
                  selected: _purityGradeId == '${g['id']}',
                  showCheckmark: false,
                  selectedColor: Pal.goldWash,
                  onSelected: (_) => setState(() => _purityGradeId = '${g['id']}'),
                ),
            ]),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Gross Wt (g)'),
                TextField(
                  controller: _gross,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: T.mono(14),
                  decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
                  onChanged: (v) {
                    if (_net.text.isEmpty) _net.text = v;
                  },
                ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Net Metal Wt (g)'),
                TextField(
                  controller: _net,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: T.mono(14),
                  decoration: const InputDecoration(hintText: '0.000', suffixText: 'g'),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          const FieldLabel('Carrying Cost / Valuation (INR)'),
          TextField(
            controller: _cost,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: T.mono(15, w: FontWeight.w700),
            decoration: const InputDecoration(prefixText: '₹ ', hintText: '0.00'),
          ),
          if (_err != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: T.body(13, color: Pal.danger, w: FontWeight.w700))),
          const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: Pal.teal),
          child: _busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : const Text('Receive Into Showroom Custody'),
        ),
        ],
      ]),
    );
  }
}

class _CreateLocationSheet extends StatefulWidget {
  const _CreateLocationSheet();
  @override
  State<_CreateLocationSheet> createState() => _CreateLocationSheetState();
}

class _CreateLocationSheetState extends State<_CreateLocationSheet> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  String _type = 'VAULT';
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().isEmpty || _name.text.trim().length < 2) {
      setState(() => _err = 'Enter location code and name.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await context.read<ApiClient>().post('/inventory/locations', body: {
        'code': _code.text.trim().toUpperCase(),
        'name': _name.text.trim(),
        'type': _type,
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New Stock Location', style: T.display(20)),
          const SizedBox(height: 12),
          SaasField(label: 'Code (VAULT_MAIN)', controller: _code, mono: true),
          const SizedBox(height: 10),
          SaasField(label: 'Location name', controller: _name),
          const SizedBox(height: 10),
          SaasDropdown(
            label: 'Custody type',
            value: _type,
            options: const {
              'VAULT': 'VAULT',
              'COUNTER': 'COUNTER',
              'TRANSIT': 'TRANSIT',
              'QUARANTINE': 'QUARANTINE',
              'EXTERNAL_CUSTODY': 'EXTERNAL_CUSTODY',
              'CUSTOMER_CUSTODY': 'CUSTOMER_CUSTODY',
            },
            onChanged: (v) => setState(() => _type = v),
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: T.body(12.5, color: Pal.danger, w: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          GoldButton(label: 'Create Location', busy: _busy, onPressed: _submit),
        ],
      ),
    );
  }
}

class _ReceiveMaterialLotSheet extends StatefulWidget {
  const _ReceiveMaterialLotSheet({required this.locations});
  final List<StockLocationItem> locations;
  @override
  State<_ReceiveMaterialLotSheet> createState() => _ReceiveMaterialLotSheetState();
}

class _ReceiveMaterialLotSheetState extends State<_ReceiveMaterialLotSheet> {
  final _lotCode = TextEditingController();
  final _desc = TextEditingController();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _reason = TextEditingController(
    text: 'Authorized showroom receipt of fungible bullion material lot.',
  );

  WorkspaceLookup _lk = WorkspaceLookup();
  final _locationId = TextEditingController();
  final _metalId = TextEditingController();
  final _purityId = TextEditingController();
  final _unitId = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.locations.isNotEmpty) _locationId.text = widget.locations.first.id;
    _init();
  }

  @override
  void dispose() {
    for (final c in [_lotCode, _desc, _qty, _cost, _reason, _locationId, _metalId, _purityId, _unitId]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final lk = await WorkspaceLookup.load(
      context.read<ApiClient>(),
      includeParties: false,
      includeInventory: true,
      includeMaterials: true,
    );
    if (!mounted) return;
    if (lk.metals.isNotEmpty) _metalId.text = lk.metals.first.id;
    if (lk.units.isNotEmpty) _unitId.text = lk.units.first.id;
    setState(() {
      _lk = lk;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_locationId.text.trim().isEmpty ||
        _lotCode.text.trim().isEmpty ||
        _desc.text.trim().length < 3 ||
        _metalId.text.trim().isEmpty ||
        _purityId.text.trim().isEmpty ||
        _unitId.text.trim().isEmpty ||
        !isValidWeight(_qty.text) ||
        !isValidAmount(_cost.text)) {
      setState(() => _err = 'Complete location, lot code, description, metal, purity, unit, quantity, and carrying cost.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      const uuid = Uuid();
      await context.read<ApiClient>().post(
        '/inventory/material-lots/receive',
        idempotencyKey: uuid.v4(),
        body: {
          'locationId': _locationId.text.trim(),
          'lotCode': _lotCode.text.trim().toUpperCase(),
          'description': _desc.text.trim(),
          'metalId': _metalId.text.trim(),
          'purityGradeId': _purityId.text.trim(),
          'unitId': _unitId.text.trim(),
          'quantity': normWeight6(_qty.text),
          'ownershipKind': 'ENTITY',
          'sourceType': 'OPENING_STOCK',
          'sourceId': uuid.v4(),
          'businessDate': todayIso(),
          'reason': _reason.text.trim(),
          'carryingCost': normAmount(_cost.text),
          'currency': 'INR',
          'costMethod': 'FIFO',
        },
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Receive Fungible Material Lot', style: T.display(20)),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else ...[
            LookupField(label: 'Location', controller: _locationId, options: _lk.locations),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: SaasField(label: 'Lot code', controller: _lotCode, mono: true)),
                const SizedBox(width: 10),
                Expanded(child: LookupField(label: 'Unit', controller: _unitId, options: _lk.units)),
              ],
            ),
            const SizedBox(height: 10),
            SaasField(label: 'Description', controller: _desc),
            const SizedBox(height: 10),
            LookupField(
              label: 'Metal',
              controller: _metalId,
              options: _lk.metals,
              onSelected: (_) => setState(() => _purityId.clear()),
            ),
            const SizedBox(height: 10),
            LookupField(
              label: 'Purity grade',
              controller: _purityId,
              options: _lk.puritiesForMetal(_metalId.text.trim()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SaasField(
                    label: 'Quantity',
                    controller: _qty,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SaasField(
                    label: 'Carrying cost (INR)',
                    controller: _cost,
                    mono: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SaasField(label: 'Authorization reason (min 10 chars)', controller: _reason),
            if (_err != null) ...[
              const SizedBox(height: 10),
              Text(_err!, style: T.body(12.5, color: Pal.danger, w: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            GoldButton(label: 'Receive Material Lot', busy: _busy, onPressed: _submit),
          ],
        ],
      ),
    );
  }
}

/// 1:1 mobile version of `MaterialTransformationPanel.tsx` (`POST /inventory/material-lots/transform`).
class _MaterialTransformationView extends StatefulWidget {
  const _MaterialTransformationView({
    required this.transformations,
    required this.onTransformed,
  });

  final List<Map<String, dynamic>> transformations;
  final VoidCallback onTransformed;

  @override
  State<_MaterialTransformationView> createState() => _MaterialTransformationViewState();
}

class _MaterialTransformationViewState extends State<_MaterialTransformationView> {
  WorkspaceLookup _lk = WorkspaceLookup();
  bool _loading = true;
  bool _busy = false;
  String? _err;

  final _businessDate = TextEditingController(text: todayIso());
  final _inputBalanceId = TextEditingController();
  final _inputQtyGrams = TextEditingController();
  int _expectedBalanceVersion = 1;

  final _outLotCode = TextEditingController();
  final _outDesc = TextEditingController();
  final _outLocationId = TextEditingController();
  final _outPurityId = TextEditingController();
  final _outUnitId = TextEditingController();
  final _outQty = TextEditingController();

  final _approvedLoss = TextEditingController(text: '0');
  final _lossReason = TextEditingController();
  final _reason = TextEditingController(
    text: 'Authorized material transformation with measured input and output weights.',
  );

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in [
      _businessDate, _inputBalanceId, _inputQtyGrams, _outLotCode, _outDesc,
      _outLocationId, _outPurityId, _outUnitId, _outQty, _approvedLoss, _lossReason, _reason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final lk = await WorkspaceLookup.load(
      context.read<ApiClient>(),
      includeParties: false,
      includeInventory: true,
      includeMaterials: true,
    );
    if (!mounted) return;
    if (lk.units.isNotEmpty) _outUnitId.text = lk.units.first.id;
    setState(() {
      _lk = lk;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    if (_inputBalanceId.text.trim().isEmpty ||
        _inputQtyGrams.text.trim().isEmpty ||
        _outLotCode.text.trim().isEmpty ||
        _outDesc.text.trim().length < 3 ||
        _outLocationId.text.trim().isEmpty ||
        _outPurityId.text.trim().isEmpty ||
        _outUnitId.text.trim().isEmpty ||
        _outQty.text.trim().isEmpty) {
      setState(() => _err = 'Select source lot balance and fill all output lot fields.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      const uuid = Uuid();
      final loss = _approvedLoss.text.trim().isEmpty ? '0' : _approvedLoss.text.trim();
      await context.read<ApiClient>().post(
        '/inventory/material-lots/transform',
        idempotencyKey: uuid.v4(),
        body: {
          'inputs': [
            {
              'balanceId': _inputBalanceId.text.trim(),
              'expectedBalanceVersion': _expectedBalanceVersion,
              'quantityGrams': _inputQtyGrams.text.trim(),
            },
          ],
          'outputs': [
            {
              'locationId': _outLocationId.text.trim(),
              'lotCode': _outLotCode.text.trim().toUpperCase(),
              'description': _outDesc.text.trim(),
              'purityGradeId': _outPurityId.text.trim(),
              'unitId': _outUnitId.text.trim(),
              'quantity': _outQty.text.trim(),
            },
          ],
          'approvedLossFineWeightGrams': loss,
          if (loss != '0' && _lossReason.text.trim().isNotEmpty)
            'lossApprovalReason': _lossReason.text.trim(),
          'sourceType': 'MATERIAL_TRANSFORMATION',
          'sourceId': uuid.v4(),
          'businessDate': _businessDate.text.trim(),
          'reason': _reason.text.trim(),
        },
      );
      if (!mounted) return;
      _outLotCode.clear();
      _outDesc.clear();
      _outQty.clear();
      toast(context, 'Material transformation posted.');
      widget.onTransformed();
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SaasFormCard(
          title: 'Material transformation',
          subtitle: 'Fine-metal and historical cost are conserved across immutable lot genealogy.',
          icon: Icons.merge_type_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DatePickField(label: 'Business date', controller: _businessDate),
              const SizedBox(height: 10),
              LookupField(
                label: 'Input lot balance',
                controller: _inputBalanceId,
                options: _lk.lotBalances,
                hint: 'Select source lot and custody',
                onSelected: (opt) {
                  if (opt != null) {
                    setState(() {
                      _expectedBalanceVersion = asInt(opt.raw['balanceVersion'] ?? opt.raw['version'], fallback: 1);
                      _inputQtyGrams.text = '${opt.raw['quantityGrams'] ?? ''}';
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              SaasField(
                label: 'Input gross grams',
                controller: _inputQtyGrams,
                mono: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              SaasSubBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Output lot', style: T.body(13.2, w: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: SaasField(label: 'Output lot code', controller: _outLotCode, mono: true)),
                        const SizedBox(width: 10),
                        Expanded(child: LookupField(label: 'Output location', controller: _outLocationId, options: _lk.locations)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SaasField(label: 'Description', controller: _outDesc),
                    const SizedBox(height: 10),
                    LookupField(label: 'Output purity', controller: _outPurityId, options: _lk.purityGrades),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: LookupField(label: 'Unit', controller: _outUnitId, options: _lk.units)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SaasField(
                            label: 'Output qty',
                            controller: _outQty,
                            mono: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SaasField(
                      label: 'Approved fine loss g',
                      controller: _approvedLoss,
                      mono: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SaasField(label: 'Loss approval reason', controller: _lossReason),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SaasField(label: 'Authorization reason', controller: _reason),
              if (_err != null) ...[
                const SizedBox(height: 10),
                Text(_err!, style: T.body(12.5, color: Pal.danger, w: FontWeight.w700)),
              ],
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Posting…' : 'Post transformation'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SaasFormCard(
          title: 'Recent genealogy',
          subtitle: 'Posted batches are immutable and traceable in both directions.',
          child: widget.transformations.isEmpty
              ? const SaasEmptyBox('No material transformations posted yet.')
              : Column(
                  children: [
                    for (final item in widget.transformations)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SaasSubBox(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${fmtDate('${item['businessDate'] ?? ''}')} · ${inr(item['totalCarryingCost'])}',
                                style: T.body(13.2, w: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              KVRow(
                                'In / Out Fine',
                                '${grams(item['inputFineWeightGrams'])} → ${grams(item['outputFineWeightGrams'])} (loss ${grams(item['approvedLossFineWeightGrams'])})',
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
