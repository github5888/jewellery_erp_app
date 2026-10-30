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
  bool _showTransformForm = false;
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
    final reservedCount = _articles.where((a) => a.status.toUpperCase() == 'RESERVED').length;
    final soldCount = _articles.where((a) => a.status.toUpperCase() == 'SOLD').length;
    final q = _search.text.trim().toLowerCase();
    final fLots = _lots.where((l) {
      if (q.isEmpty) return true;
      return '${l.lotCode} ${l.metal} ${l.purityLabel} ${l.locationName}'.toLowerCase().contains(q);
    }).toList();
    final fLocs = _locations.where((loc) {
      if (q.isEmpty) return true;
      return '${loc.code} ${loc.name} ${loc.type}'.toLowerCase().contains(q);
    }).toList();

    return LuxuryModuleScaffold(
      title: 'Vault & Tagged Stock',
      icon: Icons.diamond_outlined,
      searchController: _search,
      searchHint: 'Search by Tag, Ornament, Purity or Vault...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        IconButton(
          tooltip: 'Scan Tag',
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded, color: Pal.goldSoft),
        ),
        IconButton(
          tooltip: 'Refresh Vault',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        selected: _tab,
        onChanged: (v) => setState(() {
          _tab = v;
          if (v != 'TRANSFORM') _showTransformForm = false;
        }),
        items: [
          ('ARTICLES', 'Tagged (${_articles.length})', Icons.diamond_outlined),
          ('LOTS', 'Bullion (${_lots.length})', Icons.layers_outlined),
          ('VAULTS', 'Vaults (${_locations.length})', Icons.account_balance_outlined),
          ('TRANSFORM', 'Transform (${_transformations.length})', Icons.merge_type_rounded),
        ],
      ),
      secondaryFilterBar: _tab == 'ARTICLES'
          ? LuxurySubChips<String>(
              value: _statusFilter,
              onChanged: (v) => setState(() => _statusFilter = v),
              items: [
                ('ALL', 'All (${_articles.length})'),
                ('AVAILABLE', 'Available ($availableCount)'),
                ('RESERVED', 'Reserved ($reservedCount)'),
                ('SOLD', 'Sold ($soldCount)'),
              ],
            )
          : null,
      floatingActionButton: GoldAddFab(
        icon: (_tab == 'TRANSFORM' && _showTransformForm) ? Icons.close_rounded : Icons.add_rounded,
        onPressed: _tab == 'LOTS'
            ? _receiveLotSheet
            : _tab == 'VAULTS'
                ? _createLocationSheet
                : _tab == 'TRANSFORM'
                    ? () => setState(() => _showTransformForm = !_showTransformForm)
                    : _receiveSheet,
        tooltip: _tab == 'LOTS'
            ? 'Receive Bullion Lot'
            : _tab == 'VAULTS'
                ? 'New Stock Location'
                : _tab == 'TRANSFORM'
                    ? 'New Material Transformation'
                    : 'Receive Tagged Piece',
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 92),
          children: [
            SaasKpiGrid(
              items: [
                (label: 'AVAILABLE PIECES', value: '$availableCount / ${_articles.length}'),
                (label: 'BULLION LOTS', value: '${_lots.length} active'),
                (label: 'PURE 999 WT', value: fineGrams(_totalFineGrams.toString())),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              for (var i = 0; i < 4; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 82)))
            else if (_error != null)
              ErrorBlock(_error!, onRetry: _load)
            else if (_tab == 'ARTICLES') ...[
              if (filtered.isEmpty)
                const SaasEmptyBox(
                  'No matching tagged ornaments in showroom custody. Tap + to receive a tagged piece or scan a tag.',
                )
              else
                for (final a in filtered)
                  _ArticleCard(article: a, onTap: () => _showArticleSheet(a)),
            ] else if (_tab == 'LOTS') ...[
              if (fLots.isEmpty)
                const SaasEmptyBox(
                  'No fungible bullion lots in custody. Tap + to receive a bullion bar, granule, or scrap lot.',
                )
              else
                for (final l in fLots)
                  LuxuryRecordCard(
                    icon: Icons.layers_outlined,
                    code: l.lotCode,
                    status: l.form.isEmpty ? 'AVAILABLE' : l.form,
                    lines: [
                      ('Metal & Purity', '${l.metal} ${l.purityLabel}'),
                      ('Vault Location', l.locationName.isEmpty ? '-' : l.locationName),
                      ('Gross Weight', grams(l.quantityGrams)),
                    ],
                    amountLabel: 'Pure 999 Content',
                    amountValue: fineGrams(l.fineGrams),
                  ),
            ] else if (_tab == 'TRANSFORM') ...[
              _MaterialTransformationView(
                transformations: _transformations,
                showForm: _showTransformForm,
                onCloseForm: () => setState(() => _showTransformForm = false),
                onTransformed: () {
                  setState(() => _showTransformForm = false);
                  _load();
                },
              ),
            ] else ...[
              if (fLocs.isEmpty)
                const SaasEmptyBox(
                  'No showroom vaults or display trays configured yet. Tap + to create a stock location.',
                )
              else
                for (final loc in fLocs)
                  LuxuryRecordCard(
                    icon: loc.type == 'VAULT' ? Icons.lock_outline_rounded : Icons.storefront_outlined,
                    code: loc.name,
                    status: loc.type,
                    lines: [
                      ('Location Code', loc.code),
                      ('Custody Type', statusLabel(loc.type)),
                    ],
                    amountLabel: 'Tagged Stock',
                    amountValue: '${_articles.where((a) => a.locationId == loc.id).length} pcs',
                  ),
              if (_reservations.isNotEmpty) ...[
                SectionLabel('Active Custody Reservations (${_reservations.length})'),
                for (final r in _reservations)
                  LuxuryRecordCard(
                    icon: Icons.timer_outlined,
                    code: r.articleTag.isEmpty ? shortId(r.id) : r.articleTag,
                    status: r.state,
                    lines: [
                      ('Reference', r.referenceType),
                      if (r.expiresAt.isNotEmpty) ('Hold Expires', formatDateTime(r.expiresAt)),
                    ],
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

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
                KeyValue('Est. Live Metal Value', inr(estMetal.toStringAsFixed(2)), strong: true, valueColor: Pal.goldDeep),
              if (a.makingCharges.isNotEmpty && decOrZero(a.makingCharges) > Decimal.zero)
                KeyValue('Making Charges', inr(a.makingCharges), mono: true),
            ]),
          ),
          const SizedBox(height: 16),
          RoyalGoldButton(
            label: 'Add Ornament to POS Bill',
            icon: Icons.add_shopping_cart_rounded,
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
    return LuxuryRecordCard(
      icon: Icons.diamond_outlined,
      code: a.name.isEmpty ? a.barcode : '${a.barcode} · ${a.name}',
      status: a.status.isEmpty ? 'AVAILABLE' : a.status,
      onTap: onTap,
      lines: [
        ('Purity & Vault', '${a.metal} ${a.karatLabel}${a.locationName.isEmpty ? '' : ' · ${a.locationName}'}'),
        ('Weights', 'Gross ${grams(a.grossWeight)} · Net ${grams(a.effectiveNetWeight)}'),
      ],
      amountLabel: a.carryingCost.isNotEmpty && decOrZero(a.carryingCost) > Decimal.zero
          ? 'Carrying Cost'
          : 'Net Metal',
      amountValue: a.carryingCost.isNotEmpty && decOrZero(a.carryingCost) > Decimal.zero
          ? inr(a.carryingCost)
          : grams(a.effectiveNetWeight),
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
          GoldButton(
            label: 'Receive Into Showroom Custody',
            busy: _busy,
            onPressed: _submit,
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
    required this.showForm,
    required this.onCloseForm,
    required this.onTransformed,
  });

  final List<Map<String, dynamic>> transformations;
  final bool showForm;
  final VoidCallback onCloseForm;
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
        if (widget.showForm) ...[
          SaasFormCard(
            title: 'Material transformation',
            subtitle: 'Fine-metal and historical cost are conserved across immutable lot genealogy.',
            icon: Icons.merge_type_rounded,
            trailing: TextButton(
              onPressed: widget.onCloseForm,
              child: const Text('Close'),
            ),
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
                GoldButton(
                  label: _busy ? 'Posting…' : 'Post Transformation',
                  busy: _busy,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (widget.transformations.isEmpty)
          const SaasEmptyBox('No material transformations posted yet. Tap + to transform a material lot.')
        else
          for (final item in widget.transformations)
            LuxuryRecordCard(
              icon: Icons.merge_type_rounded,
              code: 'Genealogy · ${fmtDate('${item['businessDate'] ?? ''}')}',
              status: 'POSTED',
              lines: [
                ('In → Out Fine', '${grams(item['inputFineWeightGrams'])} → ${grams(item['outputFineWeightGrams'])}'),
                ('Approved Loss', grams(item['approvedLossFineWeightGrams'])),
              ],
              amountLabel: 'Carrying Cost',
              amountValue: inr(item['totalCarryingCost']),
            ),
      ],
    );
  }
}
