import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/rates.dart';
import '../../core/theme.dart';
import '../billing/billing_controller.dart';
import '../billing/billing_screen.dart';
import '../customers/customers_screen.dart';
import '../home/home_screen.dart';
import '../inventory/inventory_screen.dart';
import '../more/more_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RatesController>().start();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<BillingController, int>((b) => b.lines.length);
    final pages = <Widget>[
      HomeScreen(onJump: (i) => setState(() => _index = i)),
      InventoryScreen(onJumpToBilling: () => setState(() => _index = 2)),
      const BillingScreen(),
      const CustomersScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Pal.line)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.space_dashboard_outlined),
              selectedIcon: Icon(Icons.space_dashboard_rounded),
              label: 'Showroom',
            ),
            const NavigationDestination(
              icon: Icon(Icons.diamond_outlined),
              selectedIcon: Icon(Icons.diamond_rounded),
              label: 'Vault',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: cartCount > 0,
                backgroundColor: Pal.goldBright,
                textColor: Pal.obsidian,
                label: Text('$cartCount'),
                child: const Icon(Icons.point_of_sale_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: cartCount > 0,
                backgroundColor: Pal.goldBright,
                textColor: Pal.obsidian,
                label: Text('$cartCount'),
                child: const Icon(Icons.point_of_sale_rounded),
              ),
              label: 'POS Bill',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Parties',
            ),
            const NavigationDestination(
              icon: Icon(Icons.apps_outlined),
              selectedIcon: Icon(Icons.apps_rounded),
              label: 'SaaS Suite',
            ),
          ],
        ),
      ),
    );
  }
}
