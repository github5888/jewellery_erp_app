import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/rates.dart';
import '../billing/billing_controller.dart';
import '../billing/billing_screen.dart';
import '../customers/customers_screen.dart';
import '../home/home_screen.dart';
import '../inventory/inventory_screen.dart';
import '../more/more_screen.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int _index = 0;
  late final RatesController _rates;

  @override
  void initState() {
    super.initState();
    _rates = context.read<RatesController>()..start();
  }

  @override
  void dispose() {
    _rates.stop();
    super.dispose();
  }

  void go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final count = context.select<BillingController, int>((b) => b.lines.length);
    return Scaffold(
      body: IndexedStack(index: _index, children: [
        HomeScreen(onNavigate: go),
        const InventoryScreen(),
        const BillingScreen(),
        const CustomersScreen(),
        const MoreScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: go,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.diamond_outlined), selectedIcon: Icon(Icons.diamond), label: 'Rates'),
          const NavigationDestination(icon: Icon(Icons.qr_code_scanner_rounded), selectedIcon: Icon(Icons.qr_code_scanner_rounded), label: 'Stock'),
          NavigationDestination(
            icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.receipt_long_outlined)),
            selectedIcon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.receipt_long)),
            label: 'Bill',
          ),
          const NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'Customers'),
          const NavigationDestination(icon: Icon(Icons.grid_view_rounded), selectedIcon: Icon(Icons.grid_view_rounded), label: 'More'),
        ],
      ),
    );
  }
}
