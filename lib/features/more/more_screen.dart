import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../debug/api_inspector.dart';
import 'old_gold_screen.dart';
import 'operations_screens.dart';
import 'reports_screen.dart';
import 'shift_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _open(BuildContext c, Widget w) =>
      Navigator.push(c, MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final initial = app.userName.trim().isEmpty ? 'J' : app.userName.trim()[0].toUpperCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Enterprise Operations')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
        children: [
          LuxuryHeroCard(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Pal.goldBright.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Pal.goldBright.withValues(alpha: 0.45)),
                  ),
                  child: Text(initial, style: T.display(21, color: Pal.goldSoft)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      app.userName.isEmpty ? 'Workspace User' : app.userName,
                      style: T.display(19, color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.userEmail,
                      style: T.body(12.5, color: Colors.white70),
                    ),
                  ]),
                ),
                StatusPill(app.mfaEnrolled ? '2FA ON' : 'ACTIVE'),
              ]),
              const SizedBox(height: 14),
              Divider(color: Colors.white.withValues(alpha: 0.14)),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.storefront_outlined, size: 15, color: Pal.goldSoft),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    [
                      if (app.tenantName.isNotEmpty) app.tenantName,
                      if (app.branchName.isNotEmpty) app.branchName,
                      if (app.branchCode.isNotEmpty) '(${app.branchCode})',
                    ].join(' · '),
                    style: T.body(12.5, color: Colors.white, w: FontWeight.w600),
                  ),
                ),
              ]),
            ]),
          ),
          const SectionLabel('Counter & Patron Desk'),
          _group([
            _Item(
              Icons.point_of_sale_rounded,
              'POS Counter Shifts',
              'Open cash float, reconcile & close drawer',
              () => _open(context, const ShiftScreen()),
            ),
            _Item(
              Icons.recycling_rounded,
              'Old Metal Exchange',
              'Assay purity, melt loss & purchase vouchers',
              () => _open(context, const OldGoldScreen()),
            ),
            _Item(
              Icons.lock_clock_rounded,
              'Rate Fixing & Advances',
              'Lock bullion rate against customer advance',
              () => _open(context, const RateFixingScreen()),
            ),
            _Item(
              Icons.handshake_outlined,
              'Approval Memos (Jangad)',
              'VIP trial handover & vault return register',
              () => _open(context, const ApprovalMemosScreen()),
            ),
          ]),
          const SectionLabel('Bullion & Artisan Custody'),
          _group([
            _Item(
              Icons.local_shipping_outlined,
              'Procurement & Inward',
              'Purchase orders, GRN QC, supplier bills & returns',
              () => _open(context, const ProcurementScreen()),
            ),
            _Item(
              Icons.handyman_outlined,
              'Karigar Job Work',
              'Fine 999 artisan issues, wastage & ornament receipts',
              () => _open(context, const JobWorkScreen()),
            ),
          ]),
          const SectionLabel('Reports & Double-Entry Ledgers'),
          _group([
            _Item(
              Icons.diamond_outlined,
              'Vault Stock Valuation',
              'Pure 999 fine weight & FIFO inventory cost',
              () => _open(context, const ReportsScreen(initialTab: 'STOCK')),
            ),
            _Item(
              Icons.trending_up_rounded,
              'Sales & Gross Margin',
              'Invoice revenue, COGS & gross profitability',
              () => _open(context, const ReportsScreen(initialTab: 'MARGIN')),
            ),
            _Item(
              Icons.balance_rounded,
              'Trial Balance & AR/AP Ageing',
              'Double-entry ledger balances & overdue buckets',
              () => _open(context, const ReportsScreen(initialTab: 'TRIAL')),
            ),
            _Item(
              Icons.account_balance_wallet_outlined,
              'Settlements & Clearings',
              'Receipts, disbursements & UPI/Card clearings',
              () => _open(context, const ReportsScreen(initialTab: 'PAYMENTS')),
            ),
          ]),
          const SectionLabel('Security & Session'),
          _group([
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
                'Switch Showroom Context',
                app.branchName.isEmpty ? 'Select branch' : 'Active: ${app.branchName}',
                app.switchShowroom,
              ),
            _Item(
              Icons.monitor_heart_outlined,
              'API Gateway Diagnostics',
              Uri.tryParse(app.api.baseUrl)?.host ?? app.api.baseUrl,
              () => _open(context, const ApiInspector()),
            ),
            _Item(
              Icons.logout_rounded,
              'Sign Out of Workspace',
              'Revoke active session cookie on this device',
              () async {
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
          ]),
        ],
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
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13.5),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: items[i].danger ? Pal.dangerWash : Pal.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      items[i].icon,
                      size: 19,
                      color: items[i].danger ? Pal.danger : Pal.ink,
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
                const Icon(Icons.copy_rounded, size: 17, color: Pal.teal),
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
          FilledButton(
            onPressed: _verifying ? null : _verify,
            style: FilledButton.styleFrom(backgroundColor: Pal.teal),
            child: _verifying
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                : const Text('Verify & Activate 2FA'),
          ),
        ],
      ]),
    );
  }
}
