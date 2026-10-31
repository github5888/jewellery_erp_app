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

/// Full-screen `More` directory mirroring the exact `_PosSaasDrawer` ("side wala")
/// and `pos.hrpocket.in` sidebar, with Search Module + Tenant & Showroom context.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key, this.onJump});
  final ValueChanged<int>? onJump;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  final _searchCtrl = TextEditingController();

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

    final initialSource =
        (app.tenantName.trim().isNotEmpty ? app.tenantName : app.userName).trim();
    final avatarChar = initialSource.isEmpty ? 'J' : initialSource[0].toUpperCase();

    final showroomContext = [
      if (app.tenantName.trim().isNotEmpty) app.tenantName.trim(),
      if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
      if (app.branchCode.trim().isNotEmpty) '(${app.branchCode.trim()})',
    ].join(' · ');

    // Exact option groups & items from `_PosSaasDrawer` ("side wala") + `pos.hrpocket.in` sidebar
    final groups = <({String? header, List<_NavEntry> items})>[
      (
        header: null,
        items: [
          _NavEntry(
            Icons.space_dashboard_outlined,
            'Showroom Dashboard',
            onTap: () => widget.onJump?.call(0),
          ),
          _NavEntry(
            Icons.diamond_outlined,
            'Vault & Tagged Stock',
            onTap: () => widget.onJump?.call(1),
          ),
          _NavEntry(
            Icons.point_of_sale_outlined,
            'POS & Sales Billing',
            onTap: () => widget.onJump?.call(2),
          ),
          _NavEntry(
            Icons.lock_clock_rounded,
            'POS Counter Shifts',
            onTap: () => _open(context, const ShiftScreen()),
          ),
          _NavEntry(
            Icons.recycling_rounded,
            'Old Metal Exchange',
            onTap: () => _open(context, const OldGoldScreen()),
          ),
          _NavEntry(
            Icons.auto_awesome_outlined,
            'Custom Orders',
            onTap: () => _open(context, const CustomOrdersScreen()),
          ),
          _NavEntry(
            Icons.build_outlined,
            'Repairs & Custody',
            onTap: () => _open(context, const RepairsCustodyScreen()),
          ),
        ],
      ),
      (
        header: 'SUPPLY & PRODUCTION',
        items: [
          _NavEntry(
            Icons.toll_rounded,
            'Materials & Bullion Rates',
            onTap: () => _open(context, const MaterialsRatesScreen()),
          ),
          _NavEntry(
            Icons.shopping_cart_outlined,
            'Procurement & Intake',
            onTap: () => _open(context, const ProcurementScreen()),
          ),
          _NavEntry(
            Icons.groups_outlined,
            'Parties & Karigars',
            onTap: () => _jumpOrOpen(context, 3, const CustomersScreen()),
          ),
          _NavEntry(
            Icons.handyman_outlined,
            'Karigar Job Work',
            onTap: () => _open(context, const JobWorkScreen()),
          ),
          _NavEntry(
            Icons.balance_rounded,
            'Refining & Melting',
            onTap: () => _open(context, const RefiningMeltingScreen()),
          ),
          _NavEntry(
            Icons.swap_horiz_rounded,
            'Inter-Branch Transfers',
            onTap: () => _open(context, const InterBranchTransfersScreen()),
          ),
          _NavEntry(
            Icons.handshake_outlined,
            'Approval & Consignment',
            onTap: () => _open(context, const ApprovalMemosScreen()),
          ),
          _NavEntry(
            Icons.domain_rounded,
            'Inter-Entity Trading',
            onTap: () => _open(context, const InterEntityTradingScreen()),
          ),
          _NavEntry(
            Icons.trending_up_rounded,
            'Wholesale Rate Fixing',
            onTap: () => _open(context, const RateFixingScreen()),
          ),
        ],
      ),
      (
        header: 'FINANCIALS & GST',
        items: [
          _NavEntry(
            Icons.account_balance_outlined,
            'Double-Entry Accounting',
            onTap: () => _open(context, const DoubleEntryAccountingScreen()),
          ),
          _NavEntry(
            Icons.account_balance_wallet_outlined,
            'Settlements & Cashup',
            onTap: () => _open(context, const SettlementsCashupScreen()),
          ),
          _NavEntry(
            Icons.account_balance_rounded,
            'Banking & Reconciliation',
            onTap: () => _open(context, const BankingReconciliationScreen()),
          ),
          _NavEntry(
            Icons.hub_outlined,
            'Consolidated Chain Analytics',
            onTap: () => _open(context, const ConsolidatedAnalyticsScreen()),
          ),
          _NavEntry(
            Icons.insights_rounded,
            'Valuation & Ledger Reports',
            onTap: () => _open(context, const ReportsScreen()),
          ),
          _NavEntry(
            Icons.cloud_sync_outlined,
            'Provider Integrations',
            onTap: () => _open(context, const ProviderIntegrationsScreen()),
          ),
          _NavEntry(
            Icons.verified_user_outlined,
            'GST Registration & Transport',
            onTap: () => _open(context, const GstRegistrationTransportScreen()),
          ),
          _NavEntry(
            Icons.description_outlined,
            'GST Returns & ITC Review',
            onTap: () => _open(context, const GstReturnsItcScreen()),
          ),
          _NavEntry(
            Icons.chat_bubble_outline_rounded,
            'Customer Messaging',
            onTap: () => _open(context, const CustomerMessagingScreen()),
          ),
          _NavEntry(
            Icons.receipt_long_outlined,
            'GST E-Invoices & Bills',
            onTap: () => _open(
              context,
              const GstRegistrationTransportScreen(submissionsFocus: true),
            ),
          ),
          _NavEntry(
            Icons.print_outlined,
            'Company & Invoice Policy',
            onTap: () => _open(context, const DocumentsPolicyScreen()),
          ),
          _NavEntry(
            Icons.policy_outlined,
            'Audit & Compliance',
            onTap: () => _open(context, const AuditComplianceScreen()),
          ),
          _NavEntry(
            Icons.apartment_rounded,
            'Showroom Hierarchy',
            onTap: () => _open(context, const ShowroomHierarchyScreen()),
          ),
          _NavEntry(
            Icons.admin_panel_settings_outlined,
            'Access Control & Roles',
            onTap: () => _open(context, const AccessControlScreen()),
          ),
          _NavEntry(
            Icons.monitor_heart_outlined,
            'API Gateway Diagnostics',
            onTap: () => _open(context, const ApiInspector()),
          ),
          if (!app.mfaEnrolled)
            _NavEntry(
              Icons.shield_outlined,
              'Enroll Authenticator 2FA',
              onTap: () => _showMfaEnrollment(context),
            ),
          if (app.branchCount > 1)
            _NavEntry(
              Icons.storefront_outlined,
              'Switch Showroom Context',
              onTap: app.switchShowroom,
            ),
        ],
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFFFAF6EE),
        body: Column(
          children: [
            // 1. Exact `_PosSaasDrawer` Dark Espresso-Bronze & Radiant Gold Header
            //    with Website Logo + Tenant/Showroom (`Kalyan Jewellers · Headquarters Showroom`) + Search Module Bar
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 12,
                16,
                16,
              ),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF150F09), Color(0xFF281C0E), Color(0xFF3A2812)],
                ),
                border: Border(bottom: BorderSide(color: Color(0xFF4C3618))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const GemMark(size: 40, darkSurface: true),
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
                                    style: T.display(18, color: Colors.white, w: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Pal.goldBright.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: Pal.goldBright.withValues(alpha: 0.45),
                                    ),
                                  ),
                                  child: Text('SAAS', style: T.caps(8.8, color: Pal.goldSoft)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            InkWell(
                              onTap: app.branchCount > 1 ? app.switchShowroom : null,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.storefront_outlined,
                                    size: 13.5,
                                    color: Pal.goldSoft,
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      showroomContext.isEmpty
                                          ? 'Enterprise Workspace'
                                          : showroomContext,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: T.body(
                                        12.2,
                                        color: Colors.white.withValues(alpha: 0.85),
                                        w: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      StatusPill(app.mfaEnrolled ? '2FA ON' : 'ACTIVE'),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Search Module Option
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF6EE),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Pal.goldBright.withValues(alpha: 0.45),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.20),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      style: T.body(13.5, color: Pal.text, w: FontWeight.w600),
                      decoration: InputDecoration(
                        filled: false,
                        hintText: 'Search module (GST, Refining, Accounting, Bank...)',
                        hintStyle: T.body(13, color: Pal.muted),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Pal.muted,
                          size: 20,
                        ),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Pal.muted,
                                ),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. Scrollable SaaS Navigation List — identical to `_PosSaasDrawer` ("side wala")
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  for (final grp in groups)
                    Builder(builder: (_) {
                      final visible = q.isEmpty
                          ? grp.items
                          : grp.items
                              .where((it) =>
                                  it.label.toLowerCase().contains(q) ||
                                  (grp.header?.toLowerCase().contains(q) ?? false))
                              .toList();
                      if (visible.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (grp.header != null) _groupHeader(grp.header!),
                          for (final it in visible)
                            _navTile(
                              it.icon,
                              it.label,
                              onTap: it.onTap,
                            ),
                        ],
                      );
                    }),
                ],
              ),
            ),

            // 3. Exact `_PosSaasDrawer` Footer Account, Showroom & Sign-Out Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Pal.line)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: Pal.goldWash,
                    child: Text(
                      avatarChar,
                      style: T.body(13.5, color: Pal.goldDeep, w: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: InkWell(
                      onTap: !app.mfaEnrolled ? () => _showMfaEnrollment(context) : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.tenantName.trim().isNotEmpty
                                ? app.tenantName.trim()
                                : (app.userName.isEmpty ? 'Account' : app.userName),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body(13.2, w: FontWeight.w800, color: Pal.ink),
                          ),
                          Text(
                            [
                              if (app.branchName.trim().isNotEmpty) app.branchName.trim(),
                              if (app.userName.trim().isNotEmpty) app.userName.trim()
                              else if (app.userEmail.trim().isNotEmpty) app.userEmail.trim(),
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: T.body(11.4, color: Pal.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (app.branchCount > 1)
                    IconButton(
                      tooltip: 'Switch Showroom',
                      onPressed: app.switchShowroom,
                      icon: const Icon(Icons.swap_horiz_rounded, size: 20, color: Pal.goldDeep),
                    ),
                  IconButton(
                    tooltip: 'Sign out',
                    onPressed: () async {
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
                    icon: const Icon(Icons.logout_rounded, size: 20, color: Pal.danger),
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
        child: Text(title, style: T.caps(10.2, color: Pal.muted, letterSpacing: 1.0)),
      );

  Widget _navTile(
    IconData icon,
    String label, {
    bool selected = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? Pal.goldWash : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11.5),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Pal.goldBorder),
                  )
                : null,
            child: Row(
              children: [
                Icon(icon, size: 19, color: selected ? Pal.goldDeep : Pal.goldDeep.withValues(alpha: 0.82)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.body(
                      13.8,
                      color: selected ? Pal.goldDeep : Pal.ink,
                      w: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: Pal.muted),
              ],
            ),
          ),
        ),
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

class _NavEntry {
  const _NavEntry(this.icon, this.label, {required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
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
