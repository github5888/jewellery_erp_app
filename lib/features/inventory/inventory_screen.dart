import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../billing/billing_controller.dart';
import 'scanner_page.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _code = TextEditingController();
  Article? _found;
  bool _looking = false;
  String? _lookupError;

  List<Article> _stock = [];
  bool _loadingStock = true;
  String? _stockError;

  @override
  void initState() {
    super.initState();
    _loadStock();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _loadStock() async {
    setState(() {
      _loadingStock = true;
      _stockError = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/inventory');
      if (!mounted) return;
      setState(() => _stock = asList(d).map(Article.new).where((a) => a.id.isNotEmpty).toList());
    } on ApiException catch (e) {
      if (mounted) setState(() => _stockError = e.message);
    }
    if (mounted) setState(() => _loadingStock = false);
  }

  Future<void> _lookup(String code) async {
    final c = code.trim();
    if (c.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _looking = true;
      _lookupError = null;
      _found = null;
    });
    try {
      final d = await context.read<ApiClient>().get('/inventory', query: {'barcode': c});
      final a = Article(asMap(d));
      if (!mounted) return;
      if (a.id.isEmpty) {
        setState(() => _lookupError = 'No piece found for $c.');
      } else {
        setState(() => _found = a);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _lookupError = e.message);
    }
    if (mounted) setState(() => _looking = false);
  }

  Future<void> _scan() async {
    final v = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerPage()));
    if (v != null) {
      _code.text = v;
      _lookup(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stock')),
      body: RefreshIndicator(
        color: Pal.ink,
        onRefresh: _loadStock,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  textInputAction: TextInputAction.search,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: _lookup,
                  decoration: InputDecoration(
                    hintText: 'Barcode, e.g. JWL-2026-B001',
                    prefixIcon: const Icon(Icons.search_rounded, color: Pal.muted),
                    suffixIcon: IconButton(
                      onPressed: () => _lookup(_code.text),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                height: 54,
                child: FilledButton(
                  onPressed: _scan,
                  style: FilledButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(54, 54)),
                  child: const Icon(Icons.qr_code_scanner_rounded),
                ),
              ),
            ]),
            if (_looking)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Panel(child: Column(children: [Skeleton(height: 22, width: 220), SizedBox(height: 12), Skeleton(height: 14), SizedBox(height: 8), Skeleton(height: 14, width: 140)])),
              ),
            if (_lookupError != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Panel(
                  color: Pal.dangerWash,
                  child: Row(children: [
                    const Icon(Icons.search_off_rounded, color: Pal.danger),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_lookupError!, style: T.body(14, color: Pal.danger, w: FontWeight.w700))),
                  ]),
                ),
              ),
            if (_found != null) Padding(padding: const EdgeInsets.only(top: 18), child: ArticleCard(article: _found!)),
            SectionLabel('In your showroom', trailing: _loadingStock ? null : Text('${_stock.length} pieces', style: T.body(13, color: Pal.muted))),
            if (_loadingStock)
              for (var i = 0; i < 3; i++)
                const Padding(padding: EdgeInsets.only(bottom: 10), child: Panel(child: Skeleton(height: 44))),
            if (_stockError != null) ErrorBlock(_stockError!, onRetry: _loadStock),
            if (!_loadingStock && _stockError == null && _stock.isEmpty)
              const EmptyBlock(
                icon: Icons.inventory_2_outlined,
                title: 'Scan to look up a piece',
                body: 'The showroom list is empty or not shared with this account. You can still scan any tag above.',
              ),
            for (final a in _stock)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Panel(
                  onTap: () {
                    setState(() => _found = a);
                    _code.text = a.barcode;
                  },
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body(15, w: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text('${a.barcode}  |  ${grams(a.net)} net', style: T.body(13, color: Pal.muted)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(a.status),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ArticleCard extends StatefulWidget {
  const ArticleCard({super.key, required this.article});
  final Article article;
  @override
  State<ArticleCard> createState() => _ArticleCardState();
}

class _ArticleCardState extends State<ArticleCard> {
  bool _adding = false;

  Future<void> _add() async {
    final billing = context.read<BillingController>();
    setState(() => _adding = true);
    try {
      await billing.addArticle(widget.article);
      if (mounted) toast(context, 'Added to bill and reserved for this counter.');
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.article;
    final inBill = context.select<BillingController, bool>((b) => b.lines.any((x) => x.id == a.id));
    return Panel(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(a.name, style: T.display(23))),
          const SizedBox(width: 10),
          StatusPill(a.status),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          Chip2('${a.metal.isEmpty ? 'Metal' : humanize(a.metal)} ${a.purity}'),
          Chip2(a.barcode, icon: Icons.qr_code_2_rounded),
        ]),
        const SizedBox(height: 14),
        const Divider(),
        const SizedBox(height: 6),
        KeyValue('Gross weight', grams(a.gross)),
        KeyValue('Stone weight', grams(a.stone)),
        KeyValue('Net metal weight', grams(a.net), strong: true),
        const Divider(),
        const SizedBox(height: 6),
        KeyValue('Making charge', '${rate(a.makingRate)} ${a.makingType == 'PER_GRAM' ? 'per gram' : statusLabel(a.makingType).toLowerCase()}'),
        if (a.location.isNotEmpty) KeyValue('Location', a.location),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: (_adding || inBill || !a.sellable) ? null : _add,
          icon: _adding
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
              : Icon(inBill ? Icons.check_rounded : Icons.add_rounded),
          label: Text(inBill ? 'On the bill' : (a.sellable ? 'Add to bill' : 'Not available to sell')),
        ),
      ]),
    );
  }
}
