import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../customers/customers_screen.dart';
import '../debug/api_inspector.dart';
import '../finance/accounting_finance_screens.dart';
import '../governance/tax_governance_screens.dart';
import '../supply/supply_production_screens.dart';
import 'old_gold_screen.dart';
import 'operations_screens.dart';
import 'reports_screen.dart';
import 'shift_screen.dart';

/// Mobile-formatted `More` hub (`Enterprise SaaS Suite`) mirroring the exact
/// `pos.hrpocket.in` sidebar (`image-3.png` & `Screenshot 696`) with:
/// - `Enterprise SaaS Suite` top header + Search Module bar + Category filter pills
/// - Active Tenant & Showroom card (`Kalyan Jewellers · Headquarters Showroom (MAIN)`)
/// - Exact `OPERATIONS`, `SUPPLY & PRODUCTION`, `FINANCIALS & GST`, and `Account & Password` items
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key, this.onJump});
  final ValueChanged<int>? onJump;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _searchCtrl = TextEditingController();
  String _cat = 'ALL';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _open(BuildContext c, Widget w) =>
      Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));

  void _jumpOrOpen(BuildContext c, int tabIndex, Widget fallback) {
    if (widget.onJump != null) {
      widget.onJump!(tabIndex);
    } else {
      _open(c, fallback);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final q = _searchCtrl.text.trim().toLowerCase();

    final tenantTitle = app.tenantName.trim().isNotEmpty
        ? app.tenantName.trim()
        : (app.userName.trim().isNotEmpty ? app.userName.trim() : 'Enterprise Workspace');
    final initial = tenantTitle[0].toUpperCase();
    final showroomLine = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
      if (app.branchCode.trim().isNotEmpty) '(${app.branchCode.trim()})',
    ].join(' · ');

    // Exact section names, item titles & order from `image-3.png` + `Screenshot (696).png`
    final sections = <({String key, String title, List<_SidebarItem> items})>[
      (
        key: 'OPERATIONS',
        title: 'OPERATIONS',
        items: [
          _SidebarItem(
            Icons.speed_rounded,
            'Dashboard',
            () => widget.onJump?.call(0),
            highlighted: true,
          ),
          _SidebarItem(
            Icons.receipt_long_outlined,
            'Sales & POS Billing',
            () => widget.onJump?.call(2),
          ),
          _SidebarItem(
            Icons.payments_outlined,
            'Counter POS Shifts',
            () => _open(context, const ShiftScreen()),
          ),
          _SidebarItem(
            Icons.inventory_2_outlined,
            'Tagged Stock & Lots',
            () => widget.onJump?.call(1),
          ),
          _SidebarItem(
            Icons.recycling_rounded,
            'Old Gold Exchange',
            () => _open(context, const OldGoldScreen()),
          ),
          _SidebarItem(
            Icons.diamond_outlined,
            'Custom Orders',
            () => _open(context, const CustomOrdersScreen()),
          ),
          _SidebarItem(
            Icons.build_outlined,
            'Repairs & Custody',
            () => _open(context, const RepairsCustodyScreen()),
          ),
        ],
      ),
      (
        key: 'SUPPLY',
        title: 'SUPPLY & PRODUCTION',
        items: [
          _SidebarItem(
            Icons.toll_rounded,
            'Materials & Bullion Rates',
            () => _open(context, const MaterialsRatesScreen()),
          ),
          _SidebarItem(
            Icons.shopping_cart_outlined,
            'Procurement & Intake',
            () => _open(context, const ProcurementScreen()),
          ),
          _SidebarItem(
            Icons.groups_outlined,
            'Parties & Karigars',
            () => _jumpOrOpen(context, 3, const CustomersScreen()),
          ),
          _SidebarItem(
            Icons.handyman_outlined,
            'Karigar Job Work',
            () => _open(context, const JobWorkScreen()),
          ),
          _SidebarItem(
            Icons.balance_rounded,
            'Refining & Melting',
            () => _open(context, const RefiningMeltingScreen()),
          ),
          _SidebarItem(
            Icons.swap_horiz_rounded,
            'Inter-Branch Transfers',
            () => _open(context, const InterBranchTransfersScreen()),
          ),
          _SidebarItem(
            Icons.handshake_outlined,
            'Approval & Consignment',
            () => _open(context, const ApprovalMemosScreen()),
          ),
          _SidebarItem(
            Icons.domain_rounded,
            'Inter-Entity Trading',
            () => _open(context, const InterEntityTradingScreen()),
          ),
          _SidebarItem(
            Icons.trending_up_rounded,
            'Wholesale Rate Fixing',
            () => _open(context, const RateFixingScreen()),
          ),
        ],
      ),
      (
        key: 'FINANCIALS',
        title: 'FINANCIALS & GST',
        items: [
          _SidebarItem(
            Icons.account_balance_outlined,
            'Double-Entry Accounting',
            () => _open(context, const DoubleEntryAccountingScreen()),
          ),
          _SidebarItem(
            Icons.account_balance_wallet_outlined,
            'Settlements & Cashup',
            () => _open(context, const SettlementsCashupScreen()),
          ),
          _SidebarItem(
            Icons.account_balance_rounded,
            'Banking & Reconciliation',
            () => _open(context, const BankingReconciliationScreen()),
          ),
          _SidebarItem(
            Icons.bar_chart_rounded,
            'Consolidated Chain Analytics',
            () => _open(context, const ConsolidatedAnalyticsScreen()),
          ),
          _SidebarItem(
            Icons.insights_rounded,
            'Valuation & Ledger Reports',
            () => _open(context, const ReportsScreen()),
          ),
          _SidebarItem(
            Icons.cloud_sync_outlined,
            'Provider Integrations',
            () => _open(context, const ProviderIntegrationsScreen()),
          ),
          _SidebarItem(
            Icons.verified_user_outlined,
            'GST Registration & Transport',
            () => _open(context, const GstRegistrationTransportScreen()),
          ),
          _SidebarItem(
            Icons.analytics_outlined,
            'GST Returns & ITC Review',
            () => _open(context, const GstReturnsItcScreen()),
          ),
          _SidebarItem(
            Icons.chat_bubble_outline_rounded,
            'Customer Messaging',
            () => _open(context, const CustomerMessagingScreen()),
          ),
          _SidebarItem(
            Icons.print_outlined,
            'GST E-Invoices & Bills',
            () => _open(
              context,
              const GstRegistrationTransportScreen(submissionsFocus: true),
            ),
          ),
          _SidebarItem(
            Icons.fact_check_outlined,
            'Audit & Compliance',
            () => _open(context, const AuditComplianceScreen()),
          ),
          _SidebarItem(
            Icons.apartment_rounded,
            'Showroom Hierarchy',
            () => _open(context, const ShowroomHierarchyScreen()),
          ),
          _SidebarItem(
            Icons.shield_outlined,
            'Access Control & Roles',
            () => _open(context, const AccessControlScreen()),
          ),
          _SidebarItem(
            Icons.request_quote_outlined,
            'Company & Invoice Policy',
            () => _open(context, const DocumentsPolicyScreen()),
          ),
          _SidebarItem(
            Icons.monitor_heart_outlined,
            'API Gateway Diagnostics',
            () => _open(context, const ApiInspector()),
          ),
        ],
      ),
    ];

    return LuxuryModuleScaffold(
      title: 'Enterprise SaaS Suite',
      icon: Icons.grid_view_rounded,
      searchController: _searchCtrl,
      searchHint: 'Search SaaS module (POS, GST, Refining, Accounting...)',
      onSearchChanged: (_) => setState(() {}),
      topFilterBar: PillTabs<String>(
        value: _cat,
        onChanged: (v) => setState(() => _cat = v),
        tabs: const [
          ('ALL', 'All Suite'),
          ('OPERATIONS', 'Operations'),
          ('SUPPLY', 'Supply & Prod'),
          ('FINANCIALS', 'Financials & GST'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          // Top Brand + Headquarters Showroom Context Card (`Jewellery ERP SAAS` + `Kalyan Jewellers · Headquarters Showroom`)
          LuxuryHeroCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const GemMark(size: 42, darkSurface: true),
                    const SizedBox(width: 12),
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
                                  style: T.body(
                                    18,
                                    color: Colors.white,
                                    w: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFBF3DC),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFFE5CC82)),
                                ),
                                child: Text(
                                  'SAAS',
                                  style: T.caps(
                                    9,
                                    color: Pal.goldDeep,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tenantTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body(
                              13,
                              color: Pal.goldSoft,
                              w: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusPill(app.mfaEnrolled ? '2FA ON' : 'ACTIVE'),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: app.branchCount > 1 ? app.switchShowroom : null,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.storefront_outlined,
                        size: 16,
                        color: Pal.goldSoft,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          showroomLine.isEmpty
                              ? 'Active Showroom Workspace'
                              : showroomLine,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: T.body(
                            12.8,
                            color: Colors.white,
                            w: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (app.branchCount > 1) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Switch',
                          style: T.body(11.8, color: Pal.goldSoft, w: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Sidebar Sections (`OPERATIONS`, `SUPPLY & PRODUCTION`, `FINANCIALS & GST`) formatted cleanly for mobile
          for (final sec in sections)
            if (_cat == 'ALL' || _cat == sec.key)
              Builder(builder: (_) {
                final filtered = q.isEmpty
                    ? sec.items
                    : sec.items
                        .where((i) =>
                            i.title.toLowerCase().contains(q) ||
                            sec.title.toLowerCase().contains(q))
                        .toList();
                if (filtered.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(sec.title),
                    Panel(
                      radius: 16,
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            if (i > 0) const SizedBox(height: 3),
                            _MobileSidebarTile(item: filtered[i]),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              }),

          // Bottom `Account & Password` Card matching the bottom of `image-3.png`
          const SectionLabel('ACCOUNT & SESSION'),
          Panel(
            radius: 16,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                InkWell(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  onTap: () => _showAccountPasswordSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F5F8),
                            shape: BoxShape.circle,
                            border: Border.all(color: Pal.line),
                          ),
                          child: Text(
                            initial,
                            style: T.body(14.5, color: Pal.ink, w: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tenantTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: T.body(14, color: Pal.ink, w: FontWeight.w800),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Account & Password',
                                style: T.body(12, color: Pal.muted),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 20, color: Pal.muted),
                      ],
                    ),
                  ),
                ),
                if (!app.mfaEnrolled) ...[
                  const Divider(height: 1, indent: 64),
                  InkWell(
                    onTap: () => _showMfaEnrollment(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Pal.goldWash,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Pal.goldBorder),
                            ),
                            child: const Icon(
                              Icons.shield_outlined,
                              size: 18,
                              color: Pal.goldDeep,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Enroll Authenticator 2FA',
                              style: T.body(13.8, w: FontWeight.w700, color: Pal.ink),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 19, color: Pal.muted),
                        ],
                      ),
                    ),
                  ),
                ],
                if (app.branchCount > 1) ...[
                  const Divider(height: 1, indent: 64),
                  InkWell(
                    onTap: app.switchShowroom,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Pal.goldWash,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Pal.goldBorder),
                            ),
                            child: const Icon(
                              Icons.swap_horiz_rounded,
                              size: 18,
                              color: Pal.goldDeep,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Switch Showroom Context',
                              style: T.body(13.8, w: FontWeight.w700, color: Pal.ink),
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, size: 19, color: Pal.muted),
                        ],
                      ),
                    ),
                  ),
                ],
                const Divider(height: 1, indent: 64),
                InkWell(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: Pal.card,
                        title: Text('Sign out of workspace?', style: T.display(20)),
                        content: Text(
                          'Your session will be closed safely. Unsubmitted cart items on this device will be cleared.',
                          style: T.body(13.5, color: Pal.muted),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Pal.danger,
                              minimumSize: const Size(110, 42),
                            ),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Sign out'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) app.logout();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Pal.dangerWash,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Pal.danger.withValues(alpha: 0.22)),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            size: 18,
                            color: Pal.danger,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Sign out',
                            style: T.body(13.8, w: FontWeight.w700, color: Pal.danger),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, size: 19, color: Pal.muted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAccountPasswordSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AccountPasswordSheet(
        onEnrollMfa: () {
          Navigator.pop(context);
          _showMfaEnrollment(context);
        },
      ),
    );
  }

  Future<void> _showMfaEnrollment(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _MfaEnrollSheet(),
    );
  }
}

class _SidebarItem {
  const _SidebarItem(
    this.icon,
    this.title,
    this.onTap, {
    this.highlighted = false,
  });
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool highlighted;
}

class _MobileSidebarTile extends StatelessWidget {
  const _MobileSidebarTile({required this.item});
  final _SidebarItem item;

  @override
  Widget build(BuildContext context) {
    // Matches the warm cream pill row & slate/gold icon styling in `image-3.png`
    final bg = item.highlighted ? const Color(0xFFF6EFDB) : Colors.transparent;
    final fg = item.highlighted ? Pal.goldDeep : const Color(0xFF334155);
    final iconColor = item.highlighted ? Pal.goldDeep : const Color(0xFF64748B);

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11.5),
          child: Row(
            children: [
              Icon(item.icon, size: 19.5, color: iconColor),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(
                    14.2,
                    color: fg,
                    w: item.highlighted ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: item.highlighted ? Pal.goldDeep : Pal.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountPasswordSheet extends StatefulWidget {
  const _AccountPasswordSheet({required this.onEnrollMfa});
  final VoidCallback onEnrollMfa;

  @override
  State<_AccountPasswordSheet> createState() => _AccountPasswordSheetState();
}

class _AccountPasswordSheetState extends State<_AccountPasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hideCurrent = true;
  bool _hideNext = true;
  String? _err;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_current.text.isEmpty || _next.text.length < 12) {
      setState(() => _err = 'Enter your current password and a new password (min 12 characters).');
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _err = 'New password and confirmation do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final api = context.read<ApiClient>();
    try {
      try {
        await api.post('/auth/password/change', body: {
          'currentPassword': _current.text,
          'newPassword': _next.text,
        });
      } on ApiException catch (e) {
        if (e.status == 404) {
          await api.post('/auth/password', body: {
            'currentPassword': _current.text,
            'newPassword': _next.text,
          });
        } else {
          rethrow;
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'Password updated successfully.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Account & Password', style: T.display(21)),
          const SizedBox(height: 10),
          Panel(
            color: Pal.surfaceAlt,
            child: Column(
              children: [
                KVRow('User', app.userName.isEmpty ? 'Workspace User' : app.userName, bold: true),
                KVRow('Email', app.userEmail),
                KVRow('Tenant', app.tenantName),
                KVRow('Showroom', '${app.branchName} (${app.branchCode})'),
                KVRow('2FA Security', app.mfaEnrolled ? 'Active (TOTP)' : 'Not enrolled'),
              ],
            ),
          ),
          if (!app.mfaEnrolled) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.onEnrollMfa,
              icon: const Icon(Icons.shield_outlined, size: 17),
              label: const Text('Enroll Two-Factor Authentication (2FA)'),
            ),
          ],
          const SizedBox(height: 14),
          const FieldLabel('Current password'),
          TextField(
            controller: _current,
            obscureText: _hideCurrent,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: Icon(_hideCurrent ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hideCurrent = !_hideCurrent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const FieldLabel('New password (min 12 chars)'),
          TextField(
            controller: _next,
            obscureText: _hideNext,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: Icon(_hideNext ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hideNext = !_hideNext),
              ),
            ),
          ),
          const SizedBox(height: 10),
          const FieldLabel('Confirm new password'),
          TextField(
            controller: _confirm,
            obscureText: _hideNext,
          ),
          if (_err != null) ...[
            const SizedBox(height: 10),
            Text(_err!, style: T.body(12.8, color: Pal.danger, w: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          RoyalGoldButton(
            label: _busy ? 'Updating…' : 'Update Password',
            busy: _busy,
            onPressed: _changePassword,
          ),
        ],
      ),
    );
  }
}

class _MfaEnrollSheet extends StatefulWidget {
  const _MfaEnrollSheet();
  @override
  State<_MfaEnrollSheet> createState() => _MfaEnrollSheetState();
}

class _MfaEnrollSheetState extends State<_MfaEnrollSheet> {
  String? _secret;
  List<String>? _recoveryCodes;
  final _code = TextEditingController();
  bool _loading = true;
  bool _verifying = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final d = asMap(await context.read<ApiClient>().post('/auth/mfa/enrollment'));
      if (mounted) {
        setState(() {
          _secret = '${d['secret'] ?? ''}';
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _err = e.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _verify() async {
    if (_code.text.trim().length != 6) {
      setState(() => _err = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _verifying = true;
      _err = null;
    });
    try {
      final api = context.read<ApiClient>();
      final app = context.read<AppState>();
      final d = asMap(await api.post(
        '/auth/mfa/enrollment/verify',
        body: {'code': _code.text.trim()},
      ));
      final codes = (d['recoveryCodes'] is List)
          ? (d['recoveryCodes'] as List).map((e) => '$e').toList()
          : <String>[];
      await app.refreshSession();
      if (mounted) setState(() => _recoveryCodes = codes);
    } on ApiException catch (e) {
      if (mounted) setState(() => _err = e.message);
    }
    if (mounted) setState(() => _verifying = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Two-Factor Authentication (TOTP)', style: T.display(22)),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_recoveryCodes != null) ...[
            Text(
              '2FA is now active! Store these recovery codes safely — each can be used once if you lose your phone:',
              style: T.body(13.5, color: Pal.ok, w: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Panel(
              color: Pal.surfaceAlt,
              child: SelectableText(_recoveryCodes!.join('\n'), style: T.mono(13)),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          ] else ...[
            Text(
              'Add this secret key in Google Authenticator, Authy, or 1Password, then enter the 6-digit code:',
              style: T.body(13, color: Pal.muted),
            ),
            if (_secret != null && _secret!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Panel(
                color: Pal.surfaceAlt,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _secret!));
                  toast(context, 'TOTP secret copied.');
                },
                child: Row(children: [
                  Expanded(child: SelectableText(_secret!, style: T.mono(13.5, w: FontWeight.w700))),
                  const Icon(Icons.copy_rounded, size: 17, color: Pal.goldDeep),
                ]),
              ),
            ],
            const SizedBox(height: 14),
            const FieldLabel('6-Digit Verification Code'),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: T.mono(22, w: FontWeight.w700),
              decoration: const InputDecoration(hintText: '000000'),
            ),
            if (_err != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_err!, style: T.body(13, color: Pal.danger, w: FontWeight.w700)),
              ),
            const SizedBox(height: 16),
            RoyalGoldButton(
              label: 'Verify & Activate 2FA',
              busy: _verifying,
              onPressed: _verifying ? null : _verify,
            ),
          ],
        ],
      ),
    );
  }
}
