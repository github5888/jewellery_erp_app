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
                ] else ...[
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
    _tag.text = 'JWL-${DateTime.now().year}-${(DateTime.now().millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
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
                TextField(controller: _tag, style: T.mono(13.5), textCapitalization: TextCapitalization.characters),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FieldLabel('Vault / Tray'),
                DropdownButtonFormField<String>(
                  initialValue: _locationId,
                  isExpanded: true,
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
            decoration: const InputDecoration(hintText: '22K Antique Temple Necklace'),
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
                  decoration: const InputDecoration(hintText: '15.200', suffixText: 'g'),
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
                  decoration: const InputDecoration(hintText: '14.500', suffixText: 'g'),
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
            decoration: const InputDecoration(prefixText: '₹ ', hintText: '98500.00'),
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
