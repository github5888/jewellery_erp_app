import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../billing/billing_controller.dart';
import '../supply/supply_production_screens.dart';
import 'scanner_page.dart';

/// Tagged Stock & Lots (`pos.hrpocket.in/inventory` — `image-6.png`, `image-7.png`, `image-8.png`)
/// formatted cleanly for mobile phones and wired 1:1 to live `/inventory` & `/materials` APIs:
/// - `Stock and custody` header + `+ Stock location` (`POST /inventory/locations`)
/// - `Receive tagged article` (`POST /inventory/articles/receive`) + `Operation authorization` + Controlled Actions
/// - `Receive fungible material lot` (`POST /inventory/material-lots/receive`) + Lot register & Transform action
/// - Multi-input / multi-output `Material transformation` (`POST /inventory/material-lots/transform`) + `Recent genealogy`
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, this.onJumpToBilling});
  final VoidCallback? onJumpToBilling;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _TransformInputDraft {
  _TransformInputDraft({String balanceId = '', String qtyGrams = '', this.expectedVersion = 1})
      : balanceIdCtrl = TextEditingController(text: balanceId),
        grossGramsCtrl = TextEditingController(text: qtyGrams);

  final TextEditingController balanceIdCtrl;
  final TextEditingController grossGramsCtrl;
  int expectedVersion;

  void dispose() {
    balanceIdCtrl.dispose();
    grossGramsCtrl.dispose();
  }
}

class _TransformOutputDraft {
  _TransformOutputDraft({String defaultLocationId = '', String defaultUnitId = ''})
      : lotCodeCtrl = TextEditingController(),
        descCtrl = TextEditingController(),
        locationIdCtrl = TextEditingController(text: defaultLocationId),
        purityIdCtrl = TextEditingController(),
        unitIdCtrl = TextEditingController(text: defaultUnitId),
        qtyCtrl = TextEditingController();

  final TextEditingController lotCodeCtrl;
  final TextEditingController descCtrl;
  final TextEditingController locationIdCtrl;
  final TextEditingController purityIdCtrl;
  final TextEditingController unitIdCtrl;
  final TextEditingController qtyCtrl;

  void dispose() {
    lotCodeCtrl.dispose();
    descCtrl.dispose();
    locationIdCtrl.dispose();
    purityIdCtrl.dispose();
    unitIdCtrl.dispose();
    qtyCtrl.dispose();
  }
}

class _InventoryScreenState extends State<InventoryScreen> {
  static const _uuid = Uuid();

  final _search = TextEditingController();
  // 'ARTICLES' | 'LOTS' | 'TRANSFORM' | 'LOCATIONS'
  String _tab = 'ARTICLES';
  String _statusFilter = 'ALL';

  bool _showReceiveArticleForm = true;
  bool _showAuthBox = false;
  bool _showReceiveLotForm = true;
  bool _showTransformForm = true;
  bool _formsInitialized = false;

  List<Article> _articles = [];
  List<MaterialLotItem> _lots = [];
  List<StockLocationItem> _locations = [];
  List<ReservationItem> _reservations = [];
  List<Map<String, dynamic>> _transformations = [];
  WorkspaceLookup _lk = WorkspaceLookup();

  bool _loading = true;
  bool _busy = false;
  String? _error;

  // Shared Operation Authorization (`image-6.png` right card)
  final _opAuthReason = TextEditingController();

  // 1. Receive Tagged Article (`image-6.png` left card)
  final _artLocationId = TextEditingController();
  final _artDate = TextEditingController(text: todayIso());
  final _artTag = TextEditingController();
  final _artDesc = TextEditingController();
  final _artGrossWt = TextEditingController();
  final _artCost = TextEditingController();
  final _artMetalId = TextEditingController();
  final _artPurityId = TextEditingController();
  final _artMetalWt = TextEditingController();
  final _artReason = TextEditingController();

  // 2. Receive Fungible Material Lot (`image-7.png` left card)
  final _lotLocationId = TextEditingController();
  final _lotCode = TextEditingController();
  final _lotDesc = TextEditingController();
  final _lotDate = TextEditingController(text: todayIso());
  final _lotMetalId = TextEditingController();
  final _lotPurityId = TextEditingController();
  final _lotUnitId = TextEditingController();
  final _lotQty = TextEditingController();
  final _lotCost = TextEditingController();
  final _lotReason = TextEditingController();

  // 3. Material Transformation (`image-8.png` left card)
  final _txDate = TextEditingController(text: todayIso());
  final List<_TransformInputDraft> _txInputs = [_TransformInputDraft()];
  final List<_TransformOutputDraft> _txOutputs = [_TransformOutputDraft()];
  final _txLossGrams = TextEditingController(text: '0');
  final _txLossReason = TextEditingController();
  final _txReason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final i in _txInputs) {
      i.dispose();
    }
    for (final o in _txOutputs) {
      o.dispose();
    }
    for (final c in [
      _search,
      _opAuthReason,
      _artLocationId,
      _artDate,
      _artTag,
      _artDesc,
      _artGrossWt,
      _artCost,
      _artMetalId,
      _artPurityId,
      _artMetalWt,
      _artReason,
      _lotLocationId,
      _lotCode,
      _lotDesc,
      _lotDate,
      _lotMetalId,
      _lotPurityId,
      _lotUnitId,
      _lotQty,
      _lotCost,
      _lotReason,
      _txDate,
      _txLossGrams,
      _txLossReason,
      _txReason,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = context.read<ApiClient>();
    try {
      final results = await Future.wait<dynamic>([
        api.get('/inventory'),
        WorkspaceLookup.load(
          api,
          includeParties: false,
          includeInventory: true,
          includeMaterials: true,
        ),
      ]);
      if (!mounted) return;
      final d = results[0];
      final lk = results[1] as WorkspaceLookup;

      List<Article> articles;
      var lots = <MaterialLotItem>[];
      var locations = <StockLocationItem>[];
      var reservations = <ReservationItem>[];
      var transformations = <Map<String, dynamic>>[];

      if (d is Map &&
          (d.containsKey('articles') ||
              d.containsKey('materialLots') ||
              d.containsKey('locations'))) {
        articles = asList(d, keys: const ['articles']).map(Article.fromJson).toList();
        lots = asList(d, keys: const ['materialLots']).map(MaterialLotItem.fromJson).toList();
        locations =
            asList(d, keys: const ['locations']).map(StockLocationItem.fromJson).toList();
        reservations =
            asList(d, keys: const ['reservations']).map(ReservationItem.fromJson).toList();
        transformations = asList(
          d,
          keys: const ['materialTransformations', 'transformations', 'genealogy'],
        );
      } else {
        articles = asList(d).map(Article.fromJson).toList();
      }

      // Populate convenient master-data defaults (locations, metals, units)
      if (_artLocationId.text.isEmpty && lk.locations.isNotEmpty) {
        _artLocationId.text = lk.locations.first.id;
      }
      if (_lotLocationId.text.isEmpty && lk.locations.isNotEmpty) {
        _lotLocationId.text = lk.locations.first.id;
      }
      if (_artMetalId.text.isEmpty && lk.metals.isNotEmpty) {
        _artMetalId.text = lk.metals.first.id;
        final pur = lk.puritiesForMetal(_artMetalId.text);
        if (pur.isNotEmpty) _artPurityId.text = pur.first.id;
      }
      if (_lotMetalId.text.isEmpty && lk.metals.isNotEmpty) {
        _lotMetalId.text = lk.metals.first.id;
        final pur = lk.puritiesForMetal(_lotMetalId.text);
        if (pur.isNotEmpty) _lotPurityId.text = pur.first.id;
      }
      if (_lotUnitId.text.isEmpty && lk.units.isNotEmpty) {
        _lotUnitId.text = lk.units.first.id;
      }
      for (final out in _txOutputs) {
        if (out.locationIdCtrl.text.isEmpty && lk.locations.isNotEmpty) {
          out.locationIdCtrl.text = lk.locations.first.id;
        }
        if (out.unitIdCtrl.text.isEmpty && lk.units.isNotEmpty) {
          out.unitIdCtrl.text = lk.units.first.id;
        }
      }

      if (!_formsInitialized) {
        _showReceiveArticleForm = articles.isEmpty;
        _showReceiveLotForm = lots.isEmpty;
        _showTransformForm = transformations.isEmpty;
        _formsInitialized = true;
      }

      setState(() {
        _articles = articles;
        _lots = lots;
        _locations = locations;
        _reservations = reservations;
        _transformations = transformations;
        _lk = lk;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
    final exact =
        _articles.where((a) => a.barcode.toUpperCase() == code.toUpperCase()).toList();
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

  Future<void> _createLocationSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CreateLocationSheet(),
    );
    if (created == true) await _load();
  }

  // ---------------------------------------------------------------------------
  // API MUTATIONS (`image-6.png`, `image-7.png`, `image-8.png`)
  // ---------------------------------------------------------------------------

  Future<void> _submitReceiveArticle() async {
    if (_artLocationId.text.trim().isEmpty) {
      setState(() => _error = 'Select a Receiving location (or tap + Stock location first).');
      return;
    }
    if (_artTag.text.trim().isEmpty) {
      setState(() => _error = 'Enter a Unique tag for the ornament.');
      return;
    }
    if (_artDesc.text.trim().length < 3) {
      setState(() => _error = 'Enter a Description (min 3 characters).');
      return;
    }
    if (_artMetalId.text.trim().isEmpty || _artPurityId.text.trim().isEmpty) {
      setState(() => _error = 'Select both Metal and Purity.');
      return;
    }
    if (!isValidWeight(_artGrossWt.text) ||
        !isValidWeight(_artMetalWt.text) ||
        !isValidAmount(_artCost.text)) {
      setState(
        () => _error =
            'Enter valid Gross weight g, Metal weight g, and Carrying cost INR.',
      );
      return;
    }
    if (decOrZero(_artMetalWt.text) > decOrZero(_artGrossWt.text)) {
      setState(() => _error = 'Metal weight g cannot exceed Gross weight g.');
      return;
    }
    final reason = _artReason.text.trim().isNotEmpty
        ? _artReason.text.trim()
        : _opAuthReason.text.trim();
    if (reason.length < 5) {
      setState(
        () => _error = 'Enter Receipt reason and source evidence (min 5 characters).',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/inventory/articles/receive',
        idempotencyKey: _uuid.v4(),
        body: {
          'locationId': _artLocationId.text.trim(),
          'tag': _artTag.text.trim().toUpperCase(),
          'description': _artDesc.text.trim(),
          'grossWeightGrams': normWeight6(_artGrossWt.text),
          'ownershipKind': 'ENTITY',
          'sourceType': 'OPENING_STOCK',
          'sourceId': _uuid.v4(),
          'businessDate': _artDate.text.trim().isEmpty ? todayIso() : _artDate.text.trim(),
          'reason': reason,
          'carryingCost': normAmount(_artCost.text),
          'currency': 'INR',
          'components': [
            {
              'metalId': _artMetalId.text.trim(),
              'purityGradeId': _artPurityId.text.trim(),
              'weightGrams': normWeight6(_artMetalWt.text),
            },
          ],
        },
      );
      final receivedTag = _artTag.text.trim().toUpperCase();
      _artTag.clear();
      _artDesc.clear();
      _artGrossWt.clear();
      _artMetalWt.clear();
      _artCost.clear();
      _artReason.clear();
      if (!mounted) return;
      setState(() => _showReceiveArticleForm = false);
      toast(context, 'Article $receivedTag received into custody.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.code == 'MFA_REQUIRED'
              ? 'Two-factor authentication (2FA) is required to receive vault stock. Enroll 2FA in More → Account & Password.'
              : e.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitReceiveLot() async {
    if (_lotLocationId.text.trim().isEmpty ||
        _lotCode.text.trim().isEmpty ||
        _lotDesc.text.trim().length < 3 ||
        _lotMetalId.text.trim().isEmpty ||
        _lotPurityId.text.trim().isEmpty ||
        _lotUnitId.text.trim().isEmpty ||
        !isValidWeight(_lotQty.text) ||
        !isValidAmount(_lotCost.text)) {
      setState(
        () => _error =
            'Complete Location, Lot code, Description, Metal, Purity, Mass unit, Quantity, and Carrying cost INR.',
      );
      return;
    }
    final reason = _lotReason.text.trim().isNotEmpty
        ? _lotReason.text.trim()
        : _opAuthReason.text.trim();
    if (reason.length < 5) {
      setState(() => _error = 'Enter Receipt reason (min 5 characters).');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/inventory/material-lots/receive',
        idempotencyKey: _uuid.v4(),
        body: {
          'locationId': _lotLocationId.text.trim(),
          'lotCode': _lotCode.text.trim().toUpperCase(),
          'description': _lotDesc.text.trim(),
          'metalId': _lotMetalId.text.trim(),
          'purityGradeId': _lotPurityId.text.trim(),
          'unitId': _lotUnitId.text.trim(),
          'quantity': normWeight6(_lotQty.text),
          'ownershipKind': 'ENTITY',
          'sourceType': 'OPENING_STOCK',
          'sourceId': _uuid.v4(),
          'businessDate': _lotDate.text.trim().isEmpty ? todayIso() : _lotDate.text.trim(),
          'reason': reason,
          'carryingCost': normAmount(_lotCost.text),
          'currency': 'INR',
          'costMethod': 'FIFO',
        },
      );
      final createdCode = _lotCode.text.trim().toUpperCase();
      _lotCode.clear();
      _lotDesc.clear();
      _lotQty.clear();
      _lotCost.clear();
      _lotReason.clear();
      if (!mounted) return;
      setState(() => _showReceiveLotForm = false);
      toast(context, 'Material lot $createdCode received.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitTransformation() async {
    for (final inp in _txInputs) {
      if (inp.balanceIdCtrl.text.trim().isEmpty || !isValidWeight(inp.grossGramsCtrl.text)) {
        setState(
          () => _error = 'Select source lot and custody and enter valid Gross g for every input row.',
        );
        return;
      }
    }
    for (final out in _txOutputs) {
      if (out.lotCodeCtrl.text.trim().isEmpty ||
          out.descCtrl.text.trim().length < 3 ||
          out.locationIdCtrl.text.trim().isEmpty ||
          out.purityIdCtrl.text.trim().isEmpty ||
          out.unitIdCtrl.text.trim().isEmpty ||
          !isValidWeight(out.qtyCtrl.text)) {
        setState(
          () => _error =
              'Complete Output lot code, Description, Output location, Output purity, Unit, and Qty for every output row.',
        );
        return;
      }
    }
    final reason = _txReason.text.trim().isNotEmpty
        ? _txReason.text.trim()
        : _opAuthReason.text.trim();
    if (reason.length < 5) {
      setState(
        () => _error = 'Enter transformation authorization reason (min 5 characters).',
      );
      return;
    }

    final lossRaw = _txLossGrams.text.trim().isEmpty ? '0' : _txLossGrams.text.trim();
    if (decOrZero(lossRaw) > Decimal.zero && _txLossReason.text.trim().length < 5) {
      setState(
        () => _error = 'Enter a Loss approval reason when approved fine loss is greater than 0.',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<ApiClient>().post(
        '/inventory/material-lots/transform',
        idempotencyKey: _uuid.v4(),
        body: {
          'inputs': [
            for (final inp in _txInputs)
              {
                'balanceId': inp.balanceIdCtrl.text.trim(),
                'expectedBalanceVersion': inp.expectedVersion,
                'quantityGrams': normWeight6(inp.grossGramsCtrl.text),
              },
          ],
          'outputs': [
            for (final out in _txOutputs)
              {
                'locationId': out.locationIdCtrl.text.trim(),
                'lotCode': out.lotCodeCtrl.text.trim().toUpperCase(),
                'description': out.descCtrl.text.trim(),
                'purityGradeId': out.purityIdCtrl.text.trim(),
                'unitId': out.unitIdCtrl.text.trim(),
                'quantity': normWeight6(out.qtyCtrl.text),
              },
          ],
          'approvedLossFineWeightGrams': lossRaw,
          if (decOrZero(lossRaw) > Decimal.zero && _txLossReason.text.trim().isNotEmpty)
            'lossApprovalReason': _txLossReason.text.trim(),
          'sourceType': 'MATERIAL_TRANSFORMATION',
          'sourceId': _uuid.v4(),
          'businessDate': _txDate.text.trim().isEmpty ? todayIso() : _txDate.text.trim(),
          'reason': reason,
        },
      );

      for (var i = _txOutputs.length - 1; i >= 1; i--) {
        _txOutputs[i].dispose();
        _txOutputs.removeAt(i);
      }
      _txOutputs.first.lotCodeCtrl.clear();
      _txOutputs.first.descCtrl.clear();
      _txOutputs.first.qtyCtrl.clear();
      _txReason.clear();
      _txLossGrams.text = '0';
      _txLossReason.clear();

      if (!mounted) return;
      setState(() => _showTransformForm = false);
      toast(context, 'Material transformation posted to immutable genealogy.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _prefillTransformFromLot(MaterialLotItem lot) {
    final matchingBalance = _lk.lotBalances
        .where((b) =>
            '${b.raw['lotId'] ?? ''}' == lot.id ||
            '${b.raw['lotCode'] ?? ''}' == lot.lotCode)
        .firstOrNull;

    setState(() {
      _tab = 'TRANSFORM';
      _showTransformForm = true;
      if (matchingBalance != null) {
        _txInputs.first.balanceIdCtrl.text = matchingBalance.id;
        _txInputs.first.grossGramsCtrl.text =
            '${matchingBalance.raw['quantityGrams'] ?? lot.quantityGrams}';
        _txInputs.first.expectedVersion = asInt(
          matchingBalance.raw['balanceVersion'] ?? matchingBalance.raw['version'],
          fallback: 1,
        );
      }
    });
  }

  Future<void> _releaseReservation(ReservationItem r) async {
    final reason = _opAuthReason.text.trim().length >= 5
        ? _opAuthReason.text.trim()
        : 'Authorized release of reservation hold from mobile Tagged Stock & Lots.';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final matchingArt = _articles.where((a) => a.id == r.articleId).firstOrNull;
      await context.read<ApiClient>().post(
        '/inventory/reservations/${r.id}/release',
        idempotencyKey: _uuid.v4(),
        body: {
          'expectedReservationVersion': r.version,
          'expectedBalanceVersion': matchingArt?.balanceVersion ?? 1,
          'reason': reason,
        },
      );
      if (!mounted) return;
      toast(context, 'Reservation released.');
      await _load();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final rates = context.watch<RatesController>();
    final gold999 = rates.find('GOLD', '999');
    final bullionActive = gold999 != null && decOrZero(gold999.sell) > Decimal.zero;
    final showroomContext = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
    ].join(' · ');

    final filtered = _filteredArticles;
    final availableCount = _articles.where((a) => a.isAvailable).length;
    final reservedCount =
        _articles.where((a) => a.status.toUpperCase() == 'RESERVED').length;
    final soldCount = _articles.where((a) => a.status.toUpperCase() == 'SOLD').length;

    final q = _search.text.trim().toLowerCase();
    final fLots = _lots.where((l) {
      if (q.isEmpty) return true;
      return '${l.lotCode} ${l.description} ${l.metal} ${l.purityLabel} ${l.locationName}'
          .toLowerCase()
          .contains(q);
    }).toList();
    final fLocs = _locations.where((loc) {
      if (q.isEmpty) return true;
      return '${loc.code} ${loc.name} ${loc.type}'.toLowerCase().contains(q);
    }).toList();

    final isFormOpenOnCurrentTab = (_tab == 'ARTICLES' && _showReceiveArticleForm) ||
        (_tab == 'LOTS' && _showReceiveLotForm) ||
        (_tab == 'TRANSFORM' && _showTransformForm);

    return LuxuryModuleScaffold(
      title: 'Tagged Stock & Lots',
      icon: Icons.inventory_2_outlined,
      searchController: _search,
      searchHint: 'Search tag, lot code, metal, purity or location...',
      onSearchChanged: (_) => setState(() {}),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _createLocationSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Pal.goldBright.withValues(alpha: 0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 15, color: Pal.goldSoft),
                  const SizedBox(width: 3),
                  Text(
                    'Stock location',
                    style: T.body(11.5, color: Pal.goldSoft, w: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Scan Tag',
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded, color: Pal.goldSoft),
        ),
        IconButton(
          tooltip: 'Refresh Stock & Custody',
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, color: Pal.goldSoft),
        ),
      ],
      topFilterBar: PillTabs<String>(
        selected: _tab,
        onChanged: (v) => setState(() => _tab = v),
        items: [
          ('ARTICLES', 'Tagged Stock (${_articles.length})', Icons.diamond_outlined),
          ('LOTS', 'Material Lots (${_lots.length})', Icons.layers_outlined),
          (
            'TRANSFORM',
            'Transformation (${_transformations.length})',
            Icons.merge_type_rounded,
          ),
          ('LOCATIONS', 'Locations (${_locations.length})', Icons.warehouse_outlined),
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
        icon: isFormOpenOnCurrentTab ? Icons.close_rounded : Icons.add_rounded,
        tooltip: _tab == 'LOTS'
            ? 'Receive fungible material lot'
            : _tab == 'TRANSFORM'
                ? 'Material transformation'
                : _tab == 'LOCATIONS'
                    ? 'New stock location'
                    : 'Receive tagged article',
        onPressed: () {
          if (_tab == 'LOCATIONS') {
            _createLocationSheet();
            return;
          }
          setState(() {
            if (_tab == 'ARTICLES') {
              _showReceiveArticleForm = !_showReceiveArticleForm;
            } else if (_tab == 'LOTS') {
              _showReceiveLotForm = !_showReceiveLotForm;
            } else if (_tab == 'TRANSFORM') {
              _showTransformForm = !_showTransformForm;
            }
          });
        },
      ),
      body: RefreshIndicator(
        color: Pal.gold,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 92),
          children: [
            // Website Sub-Header (`Stock and custody` + `+ Stock location` + `Bullion 24K` from `image-6.png`)
            Panel(
              radius: 16,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBF3DC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE7CF8B)),
                        ),
                        child: const Icon(
                          Icons.widgets_outlined,
                          size: 19,
                          color: Pal.goldDeep,
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stock and custody',
                              style: T.body(16, color: Pal.ink, w: FontWeight.w800),
                            ),
                            if (showroomContext.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              Text(
                                showroomContext,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.body(11.8, color: Pal.muted, w: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        onPressed: _createLocationSheet,
                        icon: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('Stock location'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Append-only article movements with separate ownership, custody, availability and historical cost.',
                    style: T.body(12.2, color: Pal.muted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(99),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const MaterialsRatesScreen(),
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: bullionActive
                                ? const Color(0xFFFBF3DC)
                                : Pal.warnWash,
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: bullionActive
                                  ? const Color(0xFFE5CC82)
                                  : Pal.warn.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.toll_rounded,
                                size: 13.5,
                                color: bullionActive ? Pal.goldDeep : Pal.warn,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                bullionActive
                                    ? 'Bullion 24K: Fine 999 Board Active'
                                    : 'Bullion 24K: Configure Rate Board',
                                style: T.body(
                                  11.2,
                                  color: bullionActive ? Pal.goldDeep : Pal.warn,
                                  w: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Chip2('Available: $availableCount / ${_articles.length}'),
                      Chip2('Pure 999: ${fineGrams(_totalFineGrams.toString())}', gold: true),
                    ],
                  ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              ErrorBanner(_error!, onRetry: _load),
            ],

            const SizedBox(height: 12),

            if (_loading && _articles.isEmpty && _lots.isEmpty && _locations.isEmpty)
              for (var i = 0; i < 3; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Panel(child: Skeleton(height: 110)),
                )
            else if (_tab == 'ARTICLES')
              _buildTaggedArticlesTab(filtered)
            else if (_tab == 'LOTS')
              _buildMaterialLotsTab(fLots)
            else if (_tab == 'TRANSFORM')
              _buildTransformationTab()
            else
              _buildLocationsTab(fLocs),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: TAGGED ARTICLES (`image-6.png`)
  // ---------------------------------------------------------------------------

  Widget _buildTaggedArticlesTab(List<Article> filtered) {
    final purities = _lk.puritiesForMetal(_artMetalId.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Action toggles: Receive tagged article + Operation authorization
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: Icon(
                _showReceiveArticleForm ? Icons.expand_less_rounded : Icons.add_rounded,
                size: 16,
                color: Pal.goldDeep,
              ),
              label: Text(
                'Receive tagged article',
                style: T.body(12.2, color: Pal.goldDeep, w: FontWeight.w700),
              ),
              backgroundColor: _showReceiveArticleForm ? Pal.goldWash : Pal.card,
              side: BorderSide(color: Pal.gold.withValues(alpha: 0.45)),
              onPressed: () =>
                  setState(() => _showReceiveArticleForm = !_showReceiveArticleForm),
            ),
            ActionChip(
              avatar: Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: _opAuthReason.text.trim().isNotEmpty ? Pal.ok : Pal.muted,
              ),
              label: Text(
                'Operation authorization',
                style: T.body(12.2, color: Pal.ink, w: FontWeight.w700),
              ),
              backgroundColor: _showAuthBox ? Pal.goldWash : Pal.card,
              side: const BorderSide(color: Pal.line),
              onPressed: () => setState(() => _showAuthBox = !_showAuthBox),
            ),
          ],
        ),

        // Operation authorization card (`image-6.png` right card)
        if (_showAuthBox) ...[
          const SizedBox(height: 10),
          SaasFormCard(
            title: 'Operation authorization',
            subtitle:
                'Shared authorization reason & source evidence applied to controlled custody actions.',
            trailing: TextButton(
              onPressed: () => setState(() => _showAuthBox = false),
              child: const Text('Hide'),
            ),
            child: SaasField(
              label: 'Authorization reason',
              controller: _opAuthReason,
              hint: 'Enter manager / custodian reason & voucher reference',
              maxLines: 3,
            ),
          ),
        ],

        // Receive tagged article form (`image-6.png` left card)
        if (_showReceiveArticleForm) ...[
          const SizedBox(height: 10),
          SaasFormCard(
            title: 'Receive tagged article',
            trailing: _articles.isNotEmpty
                ? TextButton(
                    onPressed: () => setState(() => _showReceiveArticleForm = false),
                    child: const Text('Hide'),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LookupField(
                  label: 'Receiving location',
                  controller: _artLocationId,
                  options: _lk.locations,
                  hint: _lk.locations.isEmpty
                      ? 'No stock location yet — tap + Stock location'
                      : 'Receiving location',
                ),
                const SizedBox(height: 10),
                DatePickField(label: 'Business date', controller: _artDate),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SaasField(
                        label: 'Unique tag',
                        controller: _artTag,
                        hint: 'Unique tag',
                        mono: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SaasField(
                        label: 'Description',
                        controller: _artDesc,
                        hint: 'Description',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const FieldLabel('Gross weight g'),
                          TextField(
                            controller: _artGrossWt,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            style: T.mono(13.5),
                            decoration: const InputDecoration(
                              hintText: 'Gross weight g',
                            ),
                            onChanged: (v) {
                              if (_artMetalWt.text.trim().isEmpty) {
                                _artMetalWt.text = v;
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SaasField(
                        label: 'Carrying cost INR',
                        controller: _artCost,
                        hint: '0.00',
                        mono: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LookupField(
                        label: 'Metal',
                        controller: _artMetalId,
                        options: _lk.metals,
                        hint: 'Metal',
                        onSelected: (opt) {
                          setState(() {
                            _artPurityId.clear();
                            if (opt != null) {
                              final p = _lk.puritiesForMetal(opt.id);
                              if (p.isNotEmpty) _artPurityId.text = p.first.id;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LookupField(
                        label: 'Purity',
                        controller: _artPurityId,
                        options: purities.isNotEmpty ? purities : _lk.purityGrades,
                        hint: 'Purity',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Metal weight g',
                  controller: _artMetalWt,
                  hint: '0.000',
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Receipt reason and source evidence',
                  controller: _artReason,
                  hint: 'Receipt reason and source evidence',
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  busy: _busy,
                  label: 'Receive article',
                  onPressed: _busy ? null : _submitReceiveArticle,
                ),
              ],
            ),
          ),
        ],

        const SectionLabel('Tagged Articles Register'),
        if (filtered.isEmpty)
          const SaasEmptyBox(
            'No tagged articles in custody yet. Complete Receive tagged article above or scan a tag.',
          )
        else
          for (final a in filtered)
            _TaggedArticleMobileCard(
              article: a,
              onTap: () => _showArticleSheet(a),
              onControlledAction: () => _showControlledActionSheet(a),
              onAddToPos: a.isAvailable
                  ? () async {
                      final billing = context.read<BillingController>();
                      final added = await billing.addArticle(a);
                      if (!mounted) return;
                      if (added) {
                        toast(context, '${a.barcode} added to POS Quick Bill.');
                        widget.onJumpToBilling?.call();
                      } else if (billing.error != null) {
                        toast(context, billing.error!, error: true);
                      }
                    }
                  : null,
            ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: FUNGIBLE MATERIAL LOTS (`image-7.png`)
  // ---------------------------------------------------------------------------

  Widget _buildMaterialLotsTab(List<MaterialLotItem> fLots) {
    final purities = _lk.puritiesForMetal(_lotMetalId.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: Icon(
              _showReceiveLotForm ? Icons.expand_less_rounded : Icons.add_rounded,
              size: 16,
              color: Pal.goldDeep,
            ),
            label: Text(
              'Receive fungible material lot',
              style: T.body(12.2, color: Pal.goldDeep, w: FontWeight.w700),
            ),
            backgroundColor: _showReceiveLotForm ? Pal.goldWash : Pal.card,
            side: BorderSide(color: Pal.gold.withValues(alpha: 0.45)),
            onPressed: () =>
                setState(() => _showReceiveLotForm = !_showReceiveLotForm),
          ),
        ),

        if (_showReceiveLotForm) ...[
          const SizedBox(height: 10),
          SaasFormCard(
            title: 'Receive fungible material lot',
            trailing: _lots.isNotEmpty
                ? TextButton(
                    onPressed: () => setState(() => _showReceiveLotForm = false),
                    child: const Text('Hide'),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: LookupField(
                        label: 'Location',
                        controller: _lotLocationId,
                        options: _lk.locations,
                        hint: 'Location',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SaasField(
                        label: 'Lot code',
                        controller: _lotCode,
                        hint: 'Lot code',
                        mono: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SaasField(
                        label: 'Description',
                        controller: _lotDesc,
                        hint: 'Description',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DatePickField(label: 'Business date', controller: _lotDate),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LookupField(
                        label: 'Metal',
                        controller: _lotMetalId,
                        options: _lk.metals,
                        hint: 'Metal',
                        onSelected: (opt) {
                          setState(() {
                            _lotPurityId.clear();
                            if (opt != null) {
                              final p = _lk.puritiesForMetal(opt.id);
                              if (p.isNotEmpty) _lotPurityId.text = p.first.id;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: LookupField(
                        label: 'Purity',
                        controller: _lotPurityId,
                        options: purities.isNotEmpty ? purities : _lk.purityGrades,
                        hint: 'Purity',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LookupField(
                        label: 'Mass unit',
                        controller: _lotUnitId,
                        options: _lk.units,
                        hint: 'Mass unit',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SaasField(
                        label: 'Quantity',
                        controller: _lotQty,
                        hint: 'Quantity',
                        mono: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Carrying cost INR',
                  controller: _lotCost,
                  hint: 'Carrying cost INR',
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Receipt reason',
                  controller: _lotReason,
                  hint: 'Receipt reason',
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  busy: _busy,
                  label: 'Receive lot',
                  onPressed: _busy ? null : _submitReceiveLot,
                ),
              ],
            ),
          ),
        ],

        const SectionLabel('Fungible Material Lots (Lot · Balance · Cost · Action)'),
        if (fLots.isEmpty)
          const SaasEmptyBox(
            'No fungible material lots in custody yet. Complete Receive fungible material lot above.',
          )
        else
          for (final l in fLots)
            LuxuryRecordCard(
              icon: Icons.layers_outlined,
              code: l.description.isEmpty ? l.lotCode : '${l.lotCode} · ${l.description}',
              status: l.form.isEmpty ? 'FIFO LOT' : l.form,
              lines: [
                ('Material', '${l.metal} ${l.purityLabel}'),
                ('Custody Location', l.locationName.isEmpty ? 'Showroom Vault' : l.locationName),
                ('Balance (Gross / Fine)', '${grams(l.quantityGrams)} · ${fineGrams(l.fineGrams)}'),
              ],
              amountLabel: l.remainingCost.isNotEmpty ? 'Carrying Cost' : 'Pure 999 Wt',
              amountValue: l.remainingCost.isNotEmpty
                  ? inr(l.remainingCost)
                  : fineGrams(l.fineGrams),
              actions: [
                GoldButton(
                  label: 'Transform Lot',
                  compact: true,
                  onPressed: () => _prefillTransformFromLot(l),
                ),
              ],
            ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: MATERIAL TRANSFORMATION & RECENT GENEALOGY (`image-8.png`)
  // ---------------------------------------------------------------------------

  Widget _buildTransformationTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ActionChip(
            avatar: Icon(
              _showTransformForm ? Icons.expand_less_rounded : Icons.add_rounded,
              size: 16,
              color: Pal.goldDeep,
            ),
            label: Text(
              'Material transformation',
              style: T.body(12.2, color: Pal.goldDeep, w: FontWeight.w700),
            ),
            backgroundColor: _showTransformForm ? Pal.goldWash : Pal.card,
            side: BorderSide(color: Pal.gold.withValues(alpha: 0.45)),
            onPressed: () => setState(() => _showTransformForm = !_showTransformForm),
          ),
        ),

        if (_showTransformForm) ...[
          const SizedBox(height: 10),
          SaasFormCard(
            title: 'Material transformation',
            subtitle:
                'Fine-metal and historical cost are conserved across immutable lot genealogy.',
            icon: Icons.merge_type_rounded,
            trailing: _transformations.isNotEmpty
                ? TextButton(
                    onPressed: () => setState(() => _showTransformForm = false),
                    child: const Text('Hide'),
                  )
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DatePickField(label: 'Business date', controller: _txDate),
                const SizedBox(height: 14),

                // Input balances (`+ Add input`)
                Text('Input balances', style: T.body(13.2, w: FontWeight.w800)),
                const SizedBox(height: 8),
                for (var i = 0; i < _txInputs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Input #${i + 1}',
                              style: T.body(12, color: Pal.goldDeep, w: FontWeight.w700),
                            ),
                            const Spacer(),
                            if (_txInputs.length > 1)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() {
                                  _txInputs[i].dispose();
                                  _txInputs.removeAt(i);
                                }),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Pal.danger,
                                ),
                              ),
                          ],
                        ),
                        LookupField(
                          label: 'Source lot and custody',
                          controller: _txInputs[i].balanceIdCtrl,
                          options: _lk.lotBalances,
                          hint: 'Select source lot and custody',
                          onSelected: (opt) {
                            if (opt != null) {
                              setState(() {
                                _txInputs[i].expectedVersion = asInt(
                                  opt.raw['balanceVersion'] ?? opt.raw['version'],
                                  fallback: 1,
                                );
                                _txInputs[i].grossGramsCtrl.text =
                                    '${opt.raw['quantityGrams'] ?? ''}';
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        SaasField(
                          label: 'Gross g',
                          controller: _txInputs[i].grossGramsCtrl,
                          hint: 'Gross g',
                          mono: true,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ],
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _txInputs.add(_TransformInputDraft())),
                    icon: const Icon(Icons.add_rounded, size: 17, color: Pal.goldDeep),
                    label: Text(
                      'Add input',
                      style: T.body(12.5, color: Pal.goldDeep, w: FontWeight.w700),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Output lots (`+ Add output`)
                Text('Output lots', style: T.body(13.2, w: FontWeight.w800)),
                const SizedBox(height: 8),
                for (var i = 0; i < _txOutputs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  SaasSubBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Output #${i + 1}',
                              style: T.body(12, color: Pal.goldDeep, w: FontWeight.w700),
                            ),
                            const Spacer(),
                            if (_txOutputs.length > 1)
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() {
                                  _txOutputs[i].dispose();
                                  _txOutputs.removeAt(i);
                                }),
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Pal.danger,
                                ),
                              ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: SaasField(
                                label: 'Output lot code',
                                controller: _txOutputs[i].lotCodeCtrl,
                                hint: 'Output lot code',
                                mono: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'Description',
                                controller: _txOutputs[i].descCtrl,
                                hint: 'Description',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: LookupField(
                                label: 'Output location',
                                controller: _txOutputs[i].locationIdCtrl,
                                options: _lk.locations,
                                hint: 'Output location',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: LookupField(
                                label: 'Output purity',
                                controller: _txOutputs[i].purityIdCtrl,
                                options: _lk.purityGrades,
                                hint: 'Output purity',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: LookupField(
                                label: 'Unit',
                                controller: _txOutputs[i].unitIdCtrl,
                                options: _lk.units,
                                hint: 'Unit',
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SaasField(
                                label: 'Qty',
                                controller: _txOutputs[i].qtyCtrl,
                                hint: 'Qty',
                                mono: true,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(
                      () => _txOutputs.add(
                        _TransformOutputDraft(
                          defaultLocationId:
                              _lk.locations.isNotEmpty ? _lk.locations.first.id : '',
                          defaultUnitId: _lk.units.isNotEmpty ? _lk.units.first.id : '',
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 17, color: Pal.goldDeep),
                    label: Text(
                      'Add output',
                      style: T.body(12.5, color: Pal.goldDeep, w: FontWeight.w700),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SaasField(
                        label: 'Approved fine loss g',
                        controller: _txLossGrams,
                        hint: '0',
                        mono: true,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SaasField(
                        label: 'Loss approval reason',
                        controller: _txLossReason,
                        hint: 'Loss approval reason',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SaasField(
                  label: 'Transformation reason & batch evidence',
                  controller: _txReason,
                  hint: 'Enter batch transformation narration & assay reference',
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                RoyalGoldButton(
                  busy: _busy,
                  label: 'Post transformation',
                  onPressed: _busy ? null : _submitTransformation,
                ),
              ],
            ),
          ),
        ],

        // Recent genealogy (`image-8.png` right card)
        const SizedBox(height: 16),
        Panel(
          radius: 16,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent genealogy',
                style: T.body(15.5, color: Pal.ink, w: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                'Posted batches are immutable and traceable in both directions.',
                style: T.body(12, color: Pal.muted),
              ),
              const SizedBox(height: 12),
              if (_transformations.isEmpty)
                const SaasEmptyBox('No material transformation batches posted yet.')
              else
                for (final item in _transformations)
                  _GenealogyBatchCard(item: item),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: STOCK LOCATIONS & ACTIVE RESERVATIONS
  // ---------------------------------------------------------------------------

  Widget _buildLocationsTab(List<StockLocationItem> fLocs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fLocs.isEmpty)
          Panel(
            radius: 18,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
            child: Column(
              children: [
                const Icon(Icons.warehouse_outlined, size: 34, color: Pal.goldDeep),
                const SizedBox(height: 10),
                Text('No Stock Locations Configured', style: T.body(16, w: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  'Create at least one Vault or Counter display tray before receiving tagged articles or bullion lots.',
                  textAlign: TextAlign.center,
                  style: T.body(12.5, color: Pal.muted),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: 210,
                  child: RoyalGoldButton(
                    icon: Icons.add_rounded,
                    label: 'Stock location',
                    onPressed: _createLocationSheet,
                  ),
                ),
              ],
            ),
          )
        else
          for (final loc in fLocs)
            LuxuryRecordCard(
              icon: loc.type == 'VAULT'
                  ? Icons.lock_outline_rounded
                  : Icons.storefront_outlined,
              code: loc.name,
              status: loc.type,
              lines: [
                ('Location Code', loc.code),
                ('Custody Type', statusLabel(loc.type)),
              ],
              amountLabel: 'Tagged Stock',
              amountValue:
                  '${_articles.where((a) => a.locationId == loc.id).length} pcs',
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
                if (r.expiresAt.isNotEmpty)
                  ('Hold Expires', formatDateTime(r.expiresAt)),
              ],
              actions: [
                if (r.state.toUpperCase() == 'ACTIVE')
                  GoldButton(
                    label: 'Release Hold',
                    compact: true,
                    busy: _busy,
                    onPressed: () => _releaseReservation(r),
                  ),
              ],
            ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ARTICLE DETAIL & CONTROLLED ACTION SHEETS (`image-6.png`)
  // ---------------------------------------------------------------------------

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    a.name.isEmpty ? a.barcode : a.name,
                    style: T.display(22),
                  ),
                ),
                if (a.status.isNotEmpty) StatusPill(a.status),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                MonoTag(a.barcode),
                Chip2('${a.metal} ${a.karatLabel}', gold: true),
                if (a.locationName.isNotEmpty) Chip2(a.locationName),
              ],
            ),
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
              child: Column(
                children: [
                  KeyValue('Gross Weight', grams(a.grossWeight), mono: true),
                  KeyValue('Metal Weight', grams(a.effectiveNetWeight), mono: true),
                  if (decOrZero(a.stoneWeight) > Decimal.zero)
                    KeyValue('Stone / Kundan Wt', grams(a.stoneWeight), mono: true),
                  if (a.fineWeight.isNotEmpty && decOrZero(a.fineWeight) > Decimal.zero)
                    KeyValue(
                      'Pure Fine 999 Wt',
                      fineGrams(a.fineWeight),
                      mono: true,
                      strong: true,
                    ),
                  if (a.carryingCost.isNotEmpty &&
                      decOrZero(a.carryingCost) > Decimal.zero)
                    KeyValue('Carrying Cost', inr(a.carryingCost), mono: true),
                  if (estMetal > Decimal.zero)
                    KeyValue(
                      'Est. Live Metal Value',
                      inr(estMetal.toStringAsFixed(2)),
                      strong: true,
                      valueColor: Pal.goldDeep,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showControlledActionSheet(a);
                    },
                    icon: const Icon(Icons.admin_panel_settings_outlined, size: 17),
                    label: const Text('Controlled Action'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RoyalGoldButton(
                    label: 'Add to POS Bill',
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
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showControlledActionSheet(Article a) async {
    final targetLocCtrl = TextEditingController(
      text: _lk.locations.where((l) => l.id != a.locationId).firstOrNull?.id ??
          (_lk.locations.isNotEmpty ? _lk.locations.first.id : ''),
    );
    final reasonCtrl = TextEditingController(text: _opAuthReason.text.trim());
    String actionType = a.status.toUpperCase() == 'RESERVED' ? 'RELEASE' : 'MOVE';
    bool sheetBusy = false;
    String? sheetErr;

    final activeRes = _reservations
        .where((r) =>
            (r.articleId == a.id || r.articleTag == a.barcode) &&
            r.state.toUpperCase() == 'ACTIVE')
        .firstOrNull;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Controlled Action · ${a.barcode}', style: T.display(20)),
              const SizedBox(height: 4),
              Text(
                'Append-only custody movement or reservation hold with operation authorization.',
                style: T.body(12.2, color: Pal.muted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Move Custody'),
                    selected: actionType == 'MOVE',
                    showCheckmark: false,
                    selectedColor: Pal.goldWash,
                    onSelected: (_) => setLocal(() => actionType = 'MOVE'),
                  ),
                  if (a.isAvailable)
                    ChoiceChip(
                      label: const Text('Reserve Hold (4h)'),
                      selected: actionType == 'RESERVE',
                      showCheckmark: false,
                      selectedColor: Pal.goldWash,
                      onSelected: (_) => setLocal(() => actionType = 'RESERVE'),
                    ),
                  if (activeRes != null)
                    ChoiceChip(
                      label: const Text('Release Hold'),
                      selected: actionType == 'RELEASE',
                      showCheckmark: false,
                      selectedColor: Pal.goldWash,
                      onSelected: (_) => setLocal(() => actionType = 'RELEASE'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              if (actionType == 'MOVE') ...[
                LookupField(
                  label: 'Destination Custody Location',
                  controller: targetLocCtrl,
                  options: _lk.locations,
                ),
                const SizedBox(height: 10),
              ],
              SaasField(
                label: 'Operation authorization reason (min 5 chars)',
                controller: reasonCtrl,
                hint: 'Enter authorization reason & source evidence',
                maxLines: 2,
              ),
              if (sheetErr != null) ...[
                const SizedBox(height: 10),
                Text(sheetErr!, style: T.body(12.5, color: Pal.danger, w: FontWeight.w700)),
              ],
              const SizedBox(height: 14),
              RoyalGoldButton(
                busy: sheetBusy,
                label: actionType == 'MOVE'
                    ? 'Authorize Custody Move'
                    : actionType == 'RESERVE'
                        ? 'Authorize Reservation Hold'
                        : 'Release Reservation Hold',
                onPressed: sheetBusy
                    ? null
                    : () async {
                        if (reasonCtrl.text.trim().length < 5) {
                          setLocal(
                            () => sheetErr =
                                'Enter an Operation authorization reason (min 5 characters).',
                          );
                          return;
                        }
                        setLocal(() {
                          sheetBusy = true;
                          sheetErr = null;
                        });
                        _opAuthReason.text = reasonCtrl.text.trim();
                        final api = context.read<ApiClient>();
                        try {
                          if (actionType == 'RESERVE') {
                            await api.post(
                              '/inventory/articles/${a.id}/reserve',
                              idempotencyKey: _uuid.v4(),
                              body: {
                                'expectedBalanceVersion': a.balanceVersion,
                                'referenceType': 'SHOWROOM_HOLD',
                                'referenceId': _uuid.v4(),
                                'expiresAt': DateTime.now()
                                    .toUtc()
                                    .add(const Duration(hours: 4))
                                    .toIso8601String(),
                                'reason': reasonCtrl.text.trim(),
                              },
                            );
                          } else if (actionType == 'RELEASE' && activeRes != null) {
                            await api.post(
                              '/inventory/reservations/${activeRes.id}/release',
                              idempotencyKey: _uuid.v4(),
                              body: {
                                'expectedReservationVersion': activeRes.version,
                                'expectedBalanceVersion': a.balanceVersion,
                                'reason': reasonCtrl.text.trim(),
                              },
                            );
                          } else {
                            if (targetLocCtrl.text.trim().isEmpty) {
                              setLocal(
                                () => sheetErr = 'Select a destination custody location.',
                              );
                              setLocal(() => sheetBusy = false);
                              return;
                            }
                            try {
                              await api.post(
                                '/inventory/articles/${a.id}/move',
                                idempotencyKey: _uuid.v4(),
                                body: {
                                  'toLocationId': targetLocCtrl.text.trim(),
                                  'locationId': targetLocCtrl.text.trim(),
                                  'expectedBalanceVersion': a.balanceVersion,
                                  'businessDate': todayIso(),
                                  'reason': reasonCtrl.text.trim(),
                                },
                              );
                            } on ApiException catch (e) {
                              if (e.status == 404 || e.code == 'HTTP_ERROR') {
                                await api.post(
                                  '/inventory/articles/${a.id}/transfer',
                                  idempotencyKey: _uuid.v4(),
                                  body: {
                                    'toLocationId': targetLocCtrl.text.trim(),
                                    'expectedBalanceVersion': a.balanceVersion,
                                    'businessDate': todayIso(),
                                    'reason': reasonCtrl.text.trim(),
                                  },
                                );
                              } else {
                                rethrow;
                              }
                            }
                          }
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                          if (!mounted) return;
                          toast(context, 'Controlled custody action completed.');
                          await _load();
                        } on ApiException catch (e) {
                          setLocal(() => sheetErr = e.message);
                        } finally {
                          if (ctx.mounted) setLocal(() => sheetBusy = false);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
    targetLocCtrl.dispose();
    reasonCtrl.dispose();
  }
}

/// Mobile-formatted Tagged Article card showing all 5 column groups from `image-6.png`:
/// `Tag / article`, `Material`, `Ownership / custody`, `Cost`, and `Controlled action`.
class _TaggedArticleMobileCard extends StatelessWidget {
  const _TaggedArticleMobileCard({
    required this.article,
    required this.onTap,
    required this.onControlledAction,
    this.onAddToPos,
  });

  final Article article;
  final VoidCallback onTap;
  final VoidCallback onControlledAction;
  final VoidCallback? onAddToPos;

  @override
  Widget build(BuildContext context) {
    final a = article;
    final ownership = '${a.raw['ownershipKind'] ?? 'ENTITY'}';
    final costVal =
        a.carryingCost.isNotEmpty && decOrZero(a.carryingCost) > Decimal.zero
            ? inr(a.carryingCost)
            : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Pal.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Pal.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A1A140E),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Tag / article + status
              Row(
                children: [
                  MonoTag(a.barcode),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.body(14, color: Pal.ink, w: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(a.status.isEmpty ? 'AVAILABLE' : a.status),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Material + Ownership / custody + Cost grid
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Pal.surfaceAlt,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: Pal.line),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _col(
                            'MATERIAL',
                            '${a.metal} ${a.karatLabel} · ${grams(a.effectiveNetWeight)}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _col('CARRYING COST', costVal, mono: true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _col(
                            'OWNERSHIP / CUSTODY',
                            '$ownership · ${a.locationName.isEmpty ? 'Showroom Vault' : a.locationName}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _col(
                            'GROSS / FINE 999',
                            '${grams(a.grossWeight)} / ${fineGrams(a.fineWeight)}',
                            mono: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // 3. Controlled action buttons
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 35),
                    ),
                    onPressed: onControlledAction,
                    icon: const Icon(Icons.admin_panel_settings_outlined, size: 15),
                    label: const Text('Controlled action'),
                  ),
                  if (onAddToPos != null)
                    GoldButton(
                      label: '+ POS Bill',
                      compact: true,
                      onPressed: onAddToPos,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _col(String k, String v, {bool mono = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: T.caps(8.8, color: Pal.muted)),
        const SizedBox(height: 2),
        Text(
          v,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mono
              ? T.mono(12, color: Pal.ink, w: FontWeight.w700)
              : T.body(12.2, color: Pal.ink, w: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Mobile Genealogy card matching `Recent genealogy` (`Date`, `Lineage`, `Reconciliation`, `Cost`) in `image-8.png`.
class _GenealogyBatchCard extends StatelessWidget {
  const _GenealogyBatchCard({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final date = fmtDate('${item['businessDate'] ?? item['createdAt'] ?? ''}');
    final inLots = asList(item['inputs'])
        .map((x) => '${asMap(x['lot'])['lotCode'] ?? x['lotCode'] ?? shortId('${x['balanceId'] ?? ''}')}')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final outLots = asList(item['outputs'])
        .map((x) => '${asMap(x['lot'])['lotCode'] ?? x['lotCode'] ?? ''}')
        .where((s) => s.isNotEmpty)
        .join(', ');
    final lineage = (inLots.isNotEmpty || outLots.isNotEmpty)
        ? '${inLots.isEmpty ? 'Source' : inLots} → ${outLots.isEmpty ? 'Output' : outLots}'
        : 'Batch ${shortId('${item['id'] ?? ''}')}';

    final inFine = grams(item['inputFineWeightGrams'] ?? '0');
    final outFine = grams(item['outputFineWeightGrams'] ?? '0');
    final lossFine = grams(item['approvedLossFineWeightGrams'] ?? '0');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Pal.surfaceAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Pal.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.merge_type_rounded, size: 16, color: Pal.goldDeep),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lineage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.mono(12.5, color: Pal.ink, w: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 8),
              Text(date, style: T.body(11.5, color: Pal.muted)),
            ],
          ),
          const SizedBox(height: 8),
          KVRow('Reconciliation (Fine)', '$inFine → $outFine (Loss: $lossFine)'),
          KVRow(
            'Conserved Cost',
            inr(item['totalCarryingCost'] ?? item['carryingCost'] ?? '0.00'),
            bold: true,
          ),
        ],
      ),
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
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New Stock Location', style: T.display(20)),
          const SizedBox(height: 12),
          SaasField(
            label: 'Code (e.g. VAULT_MAIN)',
            controller: _code,
            hint: 'VAULT_MAIN',
            mono: true,
          ),
          const SizedBox(height: 10),
          SaasField(
            label: 'Location name',
            controller: _name,
            hint: 'Main Showroom Safe Vault',
          ),
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
          RoyalGoldButton(
            label: 'Create Stock Location',
            busy: _busy,
            onPressed: _busy ? null : _submit,
          ),
        ],
      ),
    );
  }
}
