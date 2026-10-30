import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/rates.dart';
import '../../core/theme.dart';
import '../billing/billing_controller.dart';
import '../billing/billing_screen.dart';
import '../customers/customers_screen.dart';
import '../debug/api_inspector.dart';
import '../finance/accounting_finance_screens.dart';
import '../governance/tax_governance_screens.dart';
import '../home/home_screen.dart';
import '../inventory/inventory_screen.dart';
import '../more/more_screen.dart';
import '../more/old_gold_screen.dart';
import '../more/operations_screens.dart';
import '../more/reports_screen.dart';
import '../more/shift_screen.dart';
import '../supply/supply_production_screens.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<RatesController>().start();
    });
  }

  void _openModule(Widget screen) {
    Navigator.of(context).pop(); // close drawer
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  void _jumpTab(int tabIndex) {
    Navigator.of(context).pop(); // close drawer
    setState(() => _index = tabIndex);
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<BillingController, int>((b) => b.lines.length);
    final pages = <Widget>[
      HomeScreen(
        onJump: (i) => setState(() => _index = i),
        onOpenDrawer: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      InventoryScreen(onJumpToBilling: () => setState(() => _index = 2)),
      const BillingScreen(),
      const CustomersScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      key: _scaffoldKey,
      drawer: _PosSaasDrawer(
        activeTab: _index,
        onJumpTab: _jumpTab,
        onOpenScreen: _openModule,
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Pal.ink,
          border: Border(top: BorderSide(color: Color(0xFF3A2B17), width: 1)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
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
              icon: Icon(Icons.more_horiz_rounded),
              selectedIcon: Icon(Icons.apps_rounded),
              label: 'More',
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile slide-out navigation drawer mirroring the exact `pos.hrpocket.in` SaaS sidebar.
class _PosSaasDrawer extends StatelessWidget {
  const _PosSaasDrawer({
    required this.activeTab,
    required this.onJumpTab,
    required this.onOpenScreen,
  });

  final int activeTab;
  final ValueChanged<int> onJumpTab;
  final ValueChanged<Widget> onOpenScreen;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final initial = (app.tenantName.isNotEmpty ? app.tenantName : app.userName).trim();
    final avatarChar = initial.isEmpty ? 'J' : initial[0].toUpperCase();

    return Drawer(
      backgroundColor: Pal.card,
      surfaceTintColor: Colors.transparent,
      width: 304,
      child: SafeArea(
        child: Column(
          children: [
            // Brand header matching `pos.hrpocket.in` top-left badge
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFE7C664), Color(0xFFB8860B)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.diamond_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Jewellery ERP',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.body(14.5, w: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Pal.goldWash,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: Pal.goldBorder),
                              ),
                              child: Text('SAAS', style: T.caps(8.8, color: Pal.goldDeep)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.tenantName.isEmpty ? 'Enterprise Workspace' : app.tenantName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.body(12, color: Pal.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable SaaS navigation list matching screenshots 677-696
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                children: [
                  _navTile(
                    Icons.space_dashboard_outlined,
                    'Showroom Dashboard',
                    selected: activeTab == 0,
                    onTap: () => onJumpTab(0),
                  ),
                  _navTile(
                    Icons.diamond_outlined,
                    'Vault & Tagged Stock',
                    selected: activeTab == 1,
                    onTap: () => onJumpTab(1),
                  ),
                  _navTile(
                    Icons.point_of_sale_outlined,
                    'POS & Sales Billing',
                    selected: activeTab == 2,
                    onTap: () => onJumpTab(2),
                  ),
                  _navTile(
                    Icons.lock_clock_rounded,
                    'POS Counter Shifts',
                    onTap: () => onOpenScreen(const ShiftScreen()),
                  ),
                  _navTile(
                    Icons.recycling_rounded,
                    'Old Metal Exchange',
                    onTap: () => onOpenScreen(const OldGoldScreen()),
                  ),
                  _navTile(
                    Icons.auto_awesome_outlined,
                    'Custom Orders',
                    onTap: () => onOpenScreen(const CustomOrdersScreen()),
                  ),
                  _navTile(
                    Icons.build_outlined,
                    'Repairs & Custody',
                    onTap: () => onOpenScreen(const RepairsCustodyScreen()),
                  ),

                  _groupHeader('SUPPLY & PRODUCTION'),
                  _navTile(
                    Icons.toll_rounded,
                    'Materials & Bullion Rates',
                    onTap: () => onOpenScreen(const MaterialsRatesScreen()),
                  ),
                  _navTile(
                    Icons.shopping_cart_outlined,
                    'Procurement & Intake',
                    onTap: () => onOpenScreen(const ProcurementScreen()),
                  ),
                  _navTile(
                    Icons.groups_outlined,
                    'Parties & Karigars',
                    selected: activeTab == 3,
                    onTap: () => onJumpTab(3),
                  ),
                  _navTile(
                    Icons.handyman_outlined,
                    'Karigar Job Work',
                    onTap: () => onOpenScreen(const JobWorkScreen()),
                  ),
                  _navTile(
                    Icons.balance_rounded,
                    'Refining & Melting',
                    onTap: () => onOpenScreen(const RefiningMeltingScreen()),
                  ),
                  _navTile(
                    Icons.swap_horiz_rounded,
                    'Inter-Branch Transfers',
                    onTap: () => onOpenScreen(const InterBranchTransfersScreen()),
                  ),
                  _navTile(
                    Icons.handshake_outlined,
                    'Approval & Consignment',
                    onTap: () => onOpenScreen(const ApprovalMemosScreen()),
                  ),
                  _navTile(
                    Icons.domain_rounded,
                    'Inter-Entity Trading',
                    onTap: () => onOpenScreen(const InterEntityTradingScreen()),
                  ),
                  _navTile(
                    Icons.trending_up_rounded,
                    'Wholesale Rate Fixing',
                    onTap: () => onOpenScreen(const RateFixingScreen()),
                  ),

                  _groupHeader('FINANCIALS & GST'),
                  _navTile(
                    Icons.account_balance_outlined,
                    'Double-Entry Accounting',
                    onTap: () => onOpenScreen(const DoubleEntryAccountingScreen()),
                  ),
                  _navTile(
                    Icons.account_balance_wallet_outlined,
                    'Settlements & Cashup',
                    onTap: () => onOpenScreen(const SettlementsCashupScreen()),
                  ),
                  _navTile(
                    Icons.account_balance_rounded,
                    'Banking & Reconciliation',
                    onTap: () => onOpenScreen(const BankingReconciliationScreen()),
                  ),
                  _navTile(
                    Icons.hub_outlined,
                    'Consolidated Chain Analytics',
                    onTap: () => onOpenScreen(const ConsolidatedAnalyticsScreen()),
                  ),
                  _navTile(
                    Icons.insights_rounded,
                    'Valuation & Ledger Reports',
                    onTap: () => onOpenScreen(const ReportsScreen()),
                  ),
                  _navTile(
                    Icons.cloud_sync_outlined,
                    'Provider Integrations',
                    onTap: () => onOpenScreen(const ProviderIntegrationsScreen()),
                  ),
                  _navTile(
                    Icons.verified_user_outlined,
                    'GST Registration & Transport',
                    onTap: () => onOpenScreen(const GstRegistrationTransportScreen()),
                  ),
                  _navTile(
                    Icons.description_outlined,
                    'GST Returns & ITC Review',
                    onTap: () => onOpenScreen(const GstReturnsItcScreen()),
                  ),
                  _navTile(
                    Icons.chat_bubble_outline_rounded,
                    'Customer Messaging',
                    onTap: () => onOpenScreen(const CustomerMessagingScreen()),
                  ),
                  _navTile(
                    Icons.print_outlined,
                    'Company & Invoice Policy',
                    onTap: () => onOpenScreen(const DocumentsPolicyScreen()),
                  ),
                  _navTile(
                    Icons.policy_outlined,
                    'Audit & Compliance',
                    onTap: () => onOpenScreen(const AuditComplianceScreen()),
                  ),
                  _navTile(
                    Icons.apartment_rounded,
                    'Showroom Hierarchy',
                    onTap: () => onOpenScreen(const ShowroomHierarchyScreen()),
                  ),
                  _navTile(
                    Icons.admin_panel_settings_outlined,
                    'Access Control & Roles',
                    onTap: () => onOpenScreen(const AccessControlScreen()),
                  ),
                  _navTile(
                    Icons.monitor_heart_outlined,
                    'API Gateway Diagnostics',
                    onTap: () => onOpenScreen(const ApiInspector()),
                  ),
                ],
              ),
            ),

            // Footer account & sign-out bar
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Pal.goldWash,
                    child: Text(avatarChar, style: T.body(13, color: Pal.goldDeep, w: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.userName.isEmpty ? 'Account' : app.userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.body(12.8, w: FontWeight.w700),
                        ),
                        Text(
                          app.branchName.isEmpty ? app.userEmail : app.branchName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: T.body(11, color: Pal.muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () {
                      Navigator.of(context).pop();
                      app.logout();
                    },
                    icon: const Icon(Icons.logout_rounded, size: 19, color: Pal.danger),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 16, 10, 6),
        child: Text(title, style: T.caps(10, color: Pal.muted, letterSpacing: 1.0)),
      );

  Widget _navTile(
    IconData icon,
    String label, {
    bool selected = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? Pal.goldWash : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Pal.goldBorder),
                  )
                : null,
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? Pal.goldDeep : Pal.muted),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.body(
                      13.2,
                      color: selected ? Pal.goldDeep : Pal.textSoft,
                      w: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
