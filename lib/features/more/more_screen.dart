import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../core/workspace_lookup.dart';
import '../customers/customers_screen.dart';
import '../finance/accounting_finance_screens.dart';
import '../governance/tax_governance_screens.dart';
import '../supply/supply_production_screens.dart';
import 'old_gold_screen.dart';
import 'operations_screens.dart';
import 'reports_screen.dart';
import 'shift_screen.dart';

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
    final initial = app.userName.trim().isEmpty ? 'J' : app.userName.trim()[0].toUpperCase();
    final q = _searchCtrl.text.trim().toLowerCase();

    // Exact 1:1 navigation directory from `pos.hrpocket.in` sidebar (`Screenshots 677–696`)
    final sections = <({String title, List<_Item> items})>[
      (
        title: 'Showroom & Retail',
        items: [
          _Item(
            Icons.space_dashboard_outlined,
            'Showroom Dashboard',
            'Executive metrics, live bullion & showroom overview',
            () => widget.onJump?.call(0),
          ),
          _Item(
            Icons.diamond_outlined,
            'Vault & Tagged Stock',
            'Barcoded HUID jewellery, fine-metal lots & reservations',
            () => widget.onJump?.call(1),
          ),
          _Item(
            Icons.point_of_sale_outlined,
            'POS & Sales Billing',
            'Counter POS cart, estimates, GST invoices, credit notes & tax profiles',
            () => widget.onJump?.call(2),
          ),
          _Item(
            Icons.lock_clock_rounded,
            'POS Counter Shifts',
            'Open cash float, reconcile & close showroom shift',
            () => _open(context, const ShiftScreen()),
          ),
          _Item(
            Icons.recycling_rounded,
            'Old Metal Exchange',
            'Assay purity, melt loss & customer exchange vouchers',
            () => _open(context, const OldGoldScreen()),
          ),
          _Item(
            Icons.auto_awesome_outlined,
            'Custom Orders',
            'Customer design orders, target weight & promised delivery',
            () => _open(context, const CustomOrdersScreen()),
          ),
          _Item(
            Icons.build_outlined,
            'Repairs & Custody',
            'Customer ornament repair intake & custody register',
            () => _open(context, const RepairsCustodyScreen()),
          ),
          _Item(
            Icons.insights_rounded,
            'MIS & Statutory Reports',
            'Stock valuation, gross margin, trial balance, GL & AR/AP ageing',
            () => _open(context, const ReportsScreen()),
          ),
        ],
      ),
      (
        title: 'Supply & Production',
        items: [
          _Item(
            Icons.toll_rounded,
            'Materials & Bullion Rates',
            'Precious metals, purity grades, rate books & price check',
            () => _open(context, const MaterialsRatesScreen()),
          ),
          _Item(
            Icons.shopping_cart_outlined,
            'Procurement & Intake',
            'Purchase orders, goods receipts, supplier bills & returns / debits',
            () => _open(context, const ProcurementScreen()),
          ),
          _Item(
            Icons.groups_outlined,
            'Parties & Karigars',
            'Customers, suppliers, karigars & refiners — KYC & credit policy',
            () => _jumpOrOpen(context, 3, const CustomersScreen()),
          ),
          _Item(
            Icons.handyman_outlined,
            'Karigar Job Work',
            'Fine-metal controlled work orders, issue, receipt & loss recovery',
            () => _open(context, const JobWorkScreen()),
          ),
          _Item(
            Icons.balance_rounded,
            'Refining & Melting',
            'Controlled melt batches, assay recovery & FIFO fine allocation',
            () => _open(context, const RefiningMeltingScreen()),
          ),
          _Item(
            Icons.swap_horiz_rounded,
            'Inter-Branch Transfers',
            'Transit custody stock transfers across authorized showrooms',
            () => _open(context, const InterBranchTransfersScreen()),
          ),
          _Item(
            Icons.handshake_outlined,
            'Approval & Consignment',
            'Outbound customer approval & inbound supplier consignment memos',
            () => _open(context, const ApprovalMemosScreen()),
          ),
          _Item(
            Icons.domain_rounded,
            'Inter-Entity Trading',
            'Arm\'s-length related-entity trades, IGST & new destination tags',
            () => _open(context, const InterEntityTradingScreen()),
          ),
          _Item(
            Icons.trending_up_rounded,
            'Wholesale Rate Fixing',
            'Metal-denominated contracts, unfixed exposure & fixing allocations',
            () => _open(context, const RateFixingScreen()),
          ),
        ],
      ),
      (
        title: 'Financials & GST',
        items: [
          _Item(
            Icons.menu_book_rounded,
            'Double-Entry Accounting',
            'Manual journals, P&L / BS, period control & annual close',
            () => _open(context, const DoubleEntryAccountingScreen()),
          ),
          _Item(
            Icons.account_balance_wallet_outlined,
            'Settlements & Cashup',
            'Open items, receipts, disbursements, refunds & provider clearings',
            () => _open(context, const SettlementsCashupScreen()),
          ),
          _Item(
            Icons.account_balance_rounded,
            'Banking & Reconciliation',
            'Import normalized bank CSV statements & reconcile ledger lines',
            () => _open(context, const BankingReconciliationScreen()),
          ),
          _Item(
            Icons.hub_outlined,
            'Consolidated Chain Analytics',
            'Authorized entities, intercompany reconciliation & eliminations',
            () => _open(context, const ConsolidatedAnalyticsScreen()),
          ),
          _Item(
            Icons.cloud_sync_outlined,
            'Provider Integrations',
            'Payment, GST, messaging & export connections, queue & webhooks',
            () => _open(context, const ProviderIntegrationsScreen()),
          ),
          _Item(
            Icons.verified_user_outlined,
            'GST Registration & Transport',
            'Effective GSTIN profiles, reporting window & threshold controls',
            () => _open(context, const GstRegistrationTransportScreen()),
          ),
          _Item(
            Icons.receipt_long_outlined,
            'GST E-Invoices & Bills',
            'Prepare IRN e-invoice & E-way bill provider submissions',
            () => _open(
              context,
              const GstRegistrationTransportScreen(submissionsFocus: true),
            ),
          ),
          _Item(
            Icons.description_outlined,
            'GST Returns & ITC Review',
            'Import & reconcile GSTR-2B, prepare GSTR working papers & exports',
            () => _open(context, const GstReturnsItcScreen()),
          ),
          _Item(
            Icons.chat_bubble_outline_rounded,
            'Customer Messaging',
            'Consent-verified WhatsApp, SMS & Email customer notifications',
            () => _open(context, const CustomerMessagingScreen()),
          ),
          _Item(
            Icons.policy_outlined,
            'Audit & Compliance',
            'Tenant support access grants, review & revoke controls',
            () => _open(context, const AuditComplianceScreen()),
          ),
          _Item(
            Icons.apartment_rounded,
            'Showroom Hierarchy',
            'Legal entities, functional currencies & showroom branches',
            () => _open(context, const ShowroomHierarchyScreen()),
          ),
          _Item(
            Icons.admin_panel_settings_outlined,
            'Access Control & Roles',
            'Tenant RBAC roles, permission keys & branch memberships',
            () => _open(context, const AccessControlScreen()),
          ),
          _Item(
            Icons.print_outlined,
            'Company & Invoice Policy',
            'Official A4 & thermal invoice print templates & document preview',
            () => _open(context, const DocumentsPolicyScreen()),
          ),
        ],
      ),
      (
        title: 'Account & Session',
        items: [
          _Item(
            Icons.manage_accounts_outlined,
            'Account & Password',
            app.userEmail.isEmpty ? 'Workspace profile & password security' : app.userEmail,
            () => _showAccountPasswordSheet(context),
          ),
          if (!app.mfaEnrolled)
            _Item(
              Icons.shield_outlined,
              'Enroll Authenticator 2FA',
              'Required for high-assurance vault & ledger actions',
              () => _showMfaEnrollment(context),
            ),
          if (app.branchCount > 1)
            _Item(
              Icons.swap_horiz_rounded,
              'Switch Showroom',
              app.branchName.isEmpty ? 'Select showroom' : 'Active: ${app.branchName}',
              app.switchShowroom,
            ),
          _Item(
            Icons.logout_rounded,
            'Sign out',
            'Close active workspace session on this device',
            () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: Pal.card,
                  title: Text('Sign out of workspace?', style: T.display(20)),
                  content: Text(
                    'Your session will be closed safely on this device.',
                    style: T.body(13.5, color: Pal.muted),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
            danger: true,
          ),
        ],
      ),
    ];

    return LuxuryModuleScaffold(
      title: 'More · All Modules',
      icon: Icons.grid_view_rounded,
      searchController: _searchCtrl,
      searchHint: 'Search module (Procurement, GST, Accounting, Refining...)',
      onSearchChanged: (_) => setState(() {}),
      topFilterBar: PillTabs<String>(
        value: _cat,
        onChanged: (v) => setState(() => _cat = v),
        tabs: const [
          ('ALL', 'All Modules'),
          ('Showroom & Retail', 'Showroom'),
          ('Supply & Production', 'Supply & Prod'),
          ('Financials & GST', 'Financials & GST'),
          ('Account & Session', 'Account'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          LuxuryHeroCard(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                WebsiteBrandLockup(
                  badgeSize: 38,
                  fontSize: 17.5,
                  subtitle: app.tenantName.isEmpty ? 'Enterprise Workspace' : app.tenantName,
                  darkSurface: true,
                ),
              ]),
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.14), height: 1),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Pal.goldBright.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Pal.goldBright.withValues(alpha: 0.45)),
                  ),
                  child: Text(initial, style: T.display(18, color: Pal.goldSoft)),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      app.userName.isEmpty ? 'Workspace User' : app.userName,
                      style: T.body(14.5, color: Colors.white, w: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (app.branchName.isNotEmpty)
                      Text(
                        '${app.branchName}${app.branchCode.isNotEmpty ? ' · ${app.branchCode}' : ''}',
                        style: T.body(12, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ]),
                ),
                StatusPill(app.mfaEnrolled ? '2FA ON' : 'ACTIVE'),
              ]),
            ]),
          ),
          for (final sec in sections) ...[
            if (_cat == 'ALL' || _cat == sec.title)
              Builder(builder: (_) {
                final filtered = q.isEmpty
                    ? sec.items
                    : sec.items
                        .where((i) =>
                            i.title.toLowerCase().contains(q) ||
                            i.sub.toLowerCase().contains(q) ||
                            sec.title.toLowerCase().contains(q))
                        .toList();
                if (filtered.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionLabel(sec.title),
                    _group(filtered),
                  ],
                );
              }),
          ],
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

  Widget _group(List<_Item> items) => Panel(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(indent: 62),
            InkWell(
              onTap: items[i].onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: items[i].danger ? Pal.dangerWash : Pal.goldWash,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: items[i].danger
                            ? Pal.danger.withValues(alpha: 0.22)
                            : Pal.goldBorder,
                      ),
                    ),
                    child: Icon(
                      items[i].icon,
                      size: 19,
                      color: items[i].danger ? Pal.danger : Pal.goldDeep,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        items[i].title,
                        style: T.body(
                          14.2,
                          w: FontWeight.w700,
                          color: items[i].danger ? Pal.danger : Pal.text,
                        ),
                      ),
                      if (items[i].sub.isNotEmpty)
                        Text(items[i].sub, style: T.body(12, color: Pal.muted)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 19, color: Pal.muted),
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
                KVRow('Name', app.userName.isEmpty ? 'Workspace User' : app.userName, bold: true),
                KVRow('Email', app.userEmail),
                KVRow('Tenant', app.tenantName),
                KVRow('Legal Entity', app.entityName),
                KVRow('Showroom', '${app.branchName} (${app.branchCode})'),
                KVRow('2FA Security', app.mfaEnrolled ? 'Enrolled (TOTP)' : 'Not enrolled'),
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
          SaasField(label: 'Current password', controller: _current, obscureText: true),
          const SizedBox(height: 10),
          SaasField(label: 'New password (min 12 chars)', controller: _next, obscureText: true),
          const SizedBox(height: 10),
          SaasField(label: 'Confirm new password', controller: _confirm, obscureText: true),
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Two-Factor Authentication (TOTP)', style: T.display(22)),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
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
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            style: T.mono(22, w: FontWeight.w700),
            decoration: const InputDecoration(hintText: '000000'),
          ),
          if (_err != null)
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: T.body(13, color: Pal.danger, w: FontWeight.w700))),
          const SizedBox(height: 16),
          RoyalGoldButton(
            label: 'Verify & Activate 2FA',
            busy: _verifying,
            onPressed: _verifying ? null : _verify,
          ),
        ],
      ]),
    );
  }
}
