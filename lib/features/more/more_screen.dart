import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../debug/api_inspector.dart';
import 'old_gold_screen.dart';
import 'records_screen.dart';
import 'shift_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 32), children: [
        Panel(
          child: Row(children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Pal.ink, shape: BoxShape.circle),
              child: Text(app.userName.isEmpty ? '?' : app.userName.trim()[0].toUpperCase(), style: T.display(21, color: Pal.goldSoft)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(app.userName, style: T.body(16, w: FontWeight.w800)),
                Text('${app.user['email'] ?? ''}', style: T.body(13, color: Pal.muted)),
              ]),
            ),
          ]),
        ),
        const SectionLabel('Counter'),
        _group(context, [
          _Item(Icons.point_of_sale_rounded, 'Counter shift', 'Open and close the cash drawer', () => _open(context, const ShiftScreen())),
          _Item(Icons.recycling_rounded, 'Buy old metal', 'Value and exchange old gold or silver', () => _open(context, const OldGoldScreen())),
          _Item(Icons.lock_clock_rounded, 'Rate fixing', 'Locked rates with advance booked', () => _open(context, const RecordsScreen(title: 'Rate fixing', path: '/rate-fixing', emptyTitle: 'No locked rates'))),
          _Item(Icons.handshake_outlined, 'Approval memos', 'Jangad given on approval', () => _open(context, const RecordsScreen(title: 'Approval memos', path: '/approval-memos', emptyTitle: 'No memos out on approval'))),
        ]),
        const SectionLabel('Back office'),
        _group(context, [
          _Item(Icons.local_shipping_outlined, 'Procurement inward', 'Supplier metal and consignment intake', () => _open(context, const RecordsScreen(title: 'Procurement inward', path: '/procurement', emptyTitle: 'No inward entries'))),
          _Item(Icons.handyman_outlined, 'Karigar job work', 'Metal issued to artisans and receipts', () => _open(context, const RecordsScreen(title: 'Karigar job work', path: '/job-work', emptyTitle: 'No job work open'))),
        ]),
        const SectionLabel('Reports'),
        _group(context, [
          _Item(Icons.bar_chart_rounded, 'Daily sales', 'Today at a glance', () => _open(context, const RecordsScreen(title: 'Daily sales', path: '/reports/sales-daily', emptyTitle: 'No sales yet today'))),
          _Item(Icons.inventory_2_outlined, 'Stock summary', 'Weights and pieces by metal', () => _open(context, const RecordsScreen(title: 'Stock summary', path: '/reports/inventory-summary', emptyTitle: 'No stock summary'))),
        ]),
        const SectionLabel('Account'),
        _group(context, [
          _Item(Icons.monitor_heart_outlined, 'API check', 'See what the server returns', () => _open(context, const ApiInspector())),
          if (app.branchCount > 1) _Item(Icons.swap_horiz_rounded, 'Switch showroom', app.branchName, app.switchShowroom),
          _Item(Icons.logout_rounded, 'Sign out', 'End this session on this phone', () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: Pal.pearl,
                title: Text('Sign out?', style: T.display(20)),
                content: Text('Any bill you have not issued will be cleared.', style: T.body(14, color: Pal.muted)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay signed in')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                ],
              ),
            );
            if (ok == true) app.logout();
          }, danger: true),
        ]),
      ]),
    );
  }

  Widget _group(BuildContext context, List<_Item> items) => Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 60),
            InkWell(
              onTap: items[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Icon(items[i].icon, size: 22, color: items[i].danger ? Pal.danger : Pal.ink),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(items[i].title, style: T.body(15, w: FontWeight.w800, color: items[i].danger ? Pal.danger : Pal.text)),
                      if (items[i].sub.isNotEmpty) Text(items[i].sub, style: T.body(12.5, color: Pal.muted)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Pal.muted),
                ]),
              ),
            ),
          ],
        ]),
      );
}

class _Item {
  const _Item(this.icon, this.title, this.sub, this.onTap, {this.danger = false});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool danger;
}
