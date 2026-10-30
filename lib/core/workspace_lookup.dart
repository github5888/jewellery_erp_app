import 'package:flutter/material.dart';

import 'api.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

class LookupOption {
  const LookupOption({
    required this.id,
    required this.label,
    this.subtitle,
    this.raw = const {},
  });

  final String id;
  final String label;
  final String? subtitle;
  final Map<String, dynamic> raw;
}

/// Fetches live master-data options from `pos.hrpocket.in` so mobile forms
/// present clean dropdowns instead of forcing users to copy-paste raw UUIDs.
class WorkspaceLookup {
  List<LookupOption> parties = const [];
  List<LookupOption> locations = const [];
  List<LookupOption> articles = const [];
  List<LookupOption> lotBalances = const [];
  List<LookupOption> financialYears = const [];
  List<LookupOption> periods = const [];
  List<LookupOption> series = const [];
  List<LookupOption> accounts = const [];
  List<LookupOption> metals = const [];
  List<LookupOption> purityGrades = const [];
  List<LookupOption> units = const [];
  List<LookupOption> legalEntities = const [];
  List<LookupOption> branches = const [];
  List<LookupOption> invoices = const [];
  List<LookupOption> connections = const [];

  static Future<WorkspaceLookup> load(
    ApiClient api, {
    bool includeParties = true,
    bool includeInventory = false,
    bool includeAccounting = false,
    bool includeMaterials = false,
    bool includeOrganization = false,
    bool includeSales = false,
    bool includeIntegrations = false,
  }) async {
    final w = WorkspaceLookup();
    final tasks = <Future<void>>[];

    if (includeParties) {
      tasks.add(() async {
        try {
          final d = await api.get('/parties');
          final list = asList(d, keys: const ['parties', 'items', 'rows']);
          w.parties = list
              .map((p) {
                final id = '${p['id'] ?? ''}';
                final code = '${p['code'] ?? ''}'.trim();
                final name = '${p['displayName'] ?? p['legalName'] ?? p['name'] ?? 'Party'}'.trim();
                return LookupOption(
                  id: id,
                  label: code.isNotEmpty ? '$name ($code)' : name,
                  raw: p,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();
        } catch (_) {}
      }());
    }

    if (includeInventory) {
      tasks.add(() async {
        try {
          final d = asMap(await api.get('/inventory'));
          final locs = asList(d['locations'] ?? d, keys: const ['locations']);
          w.locations = locs
              .map((l) {
                final id = '${l['id'] ?? ''}';
                final code = '${l['code'] ?? ''}'.trim();
                final name = '${l['name'] ?? 'Custody Location'}'.trim();
                final kind = '${l['kind'] ?? l['type'] ?? ''}'.trim();
                return LookupOption(
                  id: id,
                  label: [
                    if (code.isNotEmpty) code,
                    name,
                    if (kind.isNotEmpty) '· $kind',
                  ].join(' '),
                  raw: l,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();

          final arts = asList(d['articles'] ?? d, keys: const ['articles']);
          w.articles = arts
              .map((a) {
                final id = '${a['id'] ?? a['articleId'] ?? ''}';
                final tag = '${a['tagNumber'] ?? a['tag'] ?? a['barcode'] ?? ''}'.trim();
                final desc = '${a['description'] ?? a['name'] ?? 'Tagged Article'}'.trim();
                final wt = '${a['grossWeightGrams'] ?? ''}'.trim();
                return LookupOption(
                  id: id,
                  label: [
                    if (tag.isNotEmpty) tag,
                    desc,
                    if (wt.isNotEmpty) '(${grams(wt)})',
                  ].join(' · '),
                  raw: a,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();

          final lots = asList(
            d['materialLotBalances'] ?? d['lotBalances'] ?? d['materialLots'] ?? d,
            keys: const ['materialLotBalances', 'lotBalances', 'materialLots'],
          );
          final parsedBalances = <LookupOption>[];
          for (final l in lots) {
            final nested = l['balances'];
            if (nested is List && nested.isNotEmpty) {
              for (final b in nested.whereType<Map>()) {
                final bm = Map<String, dynamic>.from(b);
                final bid = '${bm['id'] ?? ''}';
                if (bid.isEmpty) continue;
                final code = '${l['lotCode'] ?? l['code'] ?? 'Lot'}';
                final qty = '${bm['quantityGrams'] ?? l['quantityGrams'] ?? '0'}';
                parsedBalances.add(LookupOption(
                  id: bid,
                  label: '$code · ${grams(qty)}',
                  raw: {...l, ...bm},
                ));
              }
            } else {
              final id = '${l['balanceId'] ?? l['id'] ?? ''}';
              if (id.isEmpty) continue;
              final code = '${l['lotCode'] ?? l['code'] ?? 'Bullion Lot'}';
              final qty = '${l['quantityGrams'] ?? l['availableGrams'] ?? '0'}';
              parsedBalances.add(LookupOption(
                id: id,
                label: '$code · ${grams(qty)}',
                raw: l,
              ));
            }
          }
          w.lotBalances = parsedBalances;
        } catch (_) {}
      }());
    }

    if (includeAccounting) {
      tasks.add(() async {
        try {
          final d = asMap(await api.get('/accounting/workspace'));
          final fys = asList(d['financialYears'] ?? d, keys: const ['financialYears']);
          final fyOut = <LookupOption>[];
          final periodOut = <LookupOption>[];
          final seriesOut = <LookupOption>[];
          for (final fy in fys) {
            final fyId = '${fy['id'] ?? ''}';
            final fyLabel = '${fy['label'] ?? fy['code'] ?? 'FY'}';
            if (fyId.isNotEmpty) {
              fyOut.add(LookupOption(id: fyId, label: '$fyLabel (${fy['state'] ?? 'OPEN'})', raw: fy));
            }
            for (final p in asList(fy['periods'])) {
              final pid = '${p['id'] ?? ''}';
              if (pid.isEmpty) continue;
              periodOut.add(LookupOption(
                id: pid,
                label: '${p['name'] ?? p['code'] ?? 'Period'} · ${p['state'] ?? ''}',
                raw: p,
              ));
            }
            for (final s in asList(fy['series'])) {
              final sid = '${s['id'] ?? ''}';
              if (sid.isEmpty) continue;
              seriesOut.add(LookupOption(
                id: sid,
                label: '${s['prefix'] ?? s['seriesKey'] ?? 'SER'} · ${s['documentType'] ?? ''}',
                raw: s,
              ));
            }
          }
          w.financialYears = fyOut;
          w.periods = periodOut;
          w.series = seriesOut;

          final accts = asList(d['accounts'] ?? d, keys: const ['accounts']);
          w.accounts = accts
              .map((a) {
                final id = '${a['id'] ?? ''}';
                return LookupOption(
                  id: id,
                  label: '${a['code'] ?? ''} · ${a['name'] ?? 'Account'} (${a['group'] ?? ''})',
                  raw: a,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();
        } catch (_) {}
      }());
    }

    if (includeMaterials) {
      tasks.add(() async {
        try {
          final d = asMap(await api.get('/materials'));
          final ms = asList(d['metals'] ?? d, keys: const ['metals']);
          final metalOut = <LookupOption>[];
          final purityOut = <LookupOption>[];
          for (final m in ms) {
            final mid = '${m['id'] ?? ''}';
            final mName = '${m['name'] ?? m['code'] ?? 'Metal'}';
            final mCode = '${m['code'] ?? ''}';
            if (mid.isNotEmpty) {
              metalOut.add(LookupOption(id: mid, label: '$mName ($mCode)', raw: m));
            }
            for (final pg in asList(m['purityGrades'])) {
              final pid = '${pg['id'] ?? ''}';
              if (pid.isEmpty) continue;
              final karat = '${pg['displayKarat'] ?? pg['code'] ?? ''}';
              final fine = '${pg['finenessPerThousand'] ?? ''}';
              purityOut.add(LookupOption(
                id: pid,
                label: '$mCode $karat (${fine}‰)',
                raw: {...pg, 'metalId': mid, 'metalCode': mCode},
              ));
            }
          }
          w.metals = metalOut;
          w.purityGrades = purityOut;

          final us = asList(d['units'] ?? d, keys: const ['units']);
          w.units = us
              .map((u) => LookupOption(
                    id: '${u['id'] ?? ''}',
                    label: '${u['name'] ?? u['code'] ?? 'Unit'} (${u['symbol'] ?? u['code'] ?? ''})',
                    raw: u,
                  ))
              .where((o) => o.id.isNotEmpty)
              .toList();
        } catch (_) {}
      }());
    }

    if (includeOrganization) {
      tasks.add(() async {
        try {
          final d = await api.get('/organization');
          final ents = asList(d, keys: const ['legalEntities', 'entities']);
          final entOut = <LookupOption>[];
          final brOut = <LookupOption>[];
          for (final e in ents) {
            final eid = '${e['id'] ?? ''}';
            final eName = '${e['legalName'] ?? e['name'] ?? 'Entity'}';
            if (eid.isNotEmpty) {
              entOut.add(LookupOption(id: eid, label: eName, raw: e));
            }
            for (final b in asList(e['branches'])) {
              final bid = '${b['id'] ?? ''}';
              if (bid.isEmpty) continue;
              brOut.add(LookupOption(
                id: bid,
                label: '${b['code'] ?? ''} · ${b['name'] ?? 'Branch'} ($eName)',
                raw: {...b, 'legalEntityId': eid, 'legalEntityName': eName},
              ));
            }
          }
          w.legalEntities = entOut;
          w.branches = brOut;
        } catch (_) {}
      }());
    }

    if (includeSales) {
      tasks.add(() async {
        try {
          final d = await api.get('/sales');
          final invs = asList(d, keys: const ['invoices', 'salesInvoices']);
          w.invoices = invs
              .map((inv) {
                final id = '${inv['id'] ?? ''}';
                final num = '${inv['documentNumber'] ?? inv['invoiceNumber'] ?? id}';
                final amt = '${inv['totalAmount'] ?? '0.00'}';
                return LookupOption(
                  id: id,
                  label: '$num · ${inr(amt)} (${inv['state'] ?? 'DRAFT'})',
                  raw: inv,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();
        } catch (_) {}
      }());
    }

    if (includeIntegrations) {
      tasks.add(() async {
        try {
          final d = await api.get('/integrations');
          final conns = asList(d, keys: const ['connections', 'providers', 'items']);
          w.connections = conns
              .map((c) {
                final id = '${c['id'] ?? ''}';
                final name = '${c['displayName'] ?? c['providerKey'] ?? 'Provider'}';
                final cap = '${c['capability'] ?? ''}';
                return LookupOption(
                  id: id,
                  label: cap.isNotEmpty ? '$name ($cap)' : name,
                  raw: c,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();
        } catch (_) {}
      }());
    }

    await Future.wait(tasks);
    return w;
  }

  List<LookupOption> partiesByRole(String role) {
    final matches = parties.where((p) {
      final roles = p.raw['roles'];
      if (roles is List) {
        return roles.any((r) =>
            (r is Map ? '${r['role']}' : '$r').toUpperCase() == role.toUpperCase());
      }
      return false;
    }).toList();
    return matches.isNotEmpty ? matches : parties;
  }

  List<LookupOption> openPeriods() {
    final open = periods
        .where((p) => '${p.raw['state'] ?? ''}'.toUpperCase() == 'OPEN')
        .toList();
    return open.isNotEmpty ? open : periods;
  }

  List<LookupOption> seriesFor(List<String> keywords) {
    if (keywords.isEmpty) return series;
    final filtered = series.where((s) {
      final docType = '${s.raw['documentType'] ?? s.label}'.toUpperCase();
      return keywords.any((k) => docType.contains(k.toUpperCase()));
    }).toList();
    return filtered.isNotEmpty ? filtered : series;
  }
}

/// SDK-agnostic, overflow-proof luxury dropdown using `InputDecorator` + `DropdownButton`.
/// Works identically across all Flutter 3.x releases with zero deprecation lints.
class GoldDropdown<T> extends StatelessWidget {
  const GoldDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.labelText,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;
  final String? labelText;

  @override
  Widget build(BuildContext context) {
    final validValue = items.any((it) => it.value == value) ? value : null;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: labelText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: validValue,
          isExpanded: true,
          dropdownColor: Pal.card,
          borderRadius: BorderRadius.circular(13),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Pal.goldDeep),
          hint: hint != null
              ? Text(
                  hint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(13.5, color: Pal.muted.withValues(alpha: 0.78)),
                )
              : null,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Mobile-first selector that shows a live dropdown when workspace options exist,
/// with a 1-tap toggle to enter or edit an exact UUID when needed.
class LookupField extends StatefulWidget {
  const LookupField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    this.hint = 'Select or enter ID',
    this.optional = false,
    this.onSelected,
  });

  final String label;
  final TextEditingController controller;
  final List<LookupOption> options;
  final String hint;
  final bool optional;
  final ValueChanged<LookupOption?>? onSelected;

  @override
  State<LookupField> createState() => _LookupFieldState();
}

class _LookupFieldState extends State<LookupField> {
  bool _manualMode = false;

  @override
  Widget build(BuildContext context) {
    final hasOptions = widget.options.isNotEmpty;
    final current = widget.controller.text.trim();
    final matched = widget.options.any((o) => o.id == current);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(
          widget.optional ? '${widget.label} (optional)' : widget.label,
          trailing: hasOptions
              ? GestureDetector(
                  onTap: () => setState(() => _manualMode = !_manualMode),
                  child: Text(
                    _manualMode ? 'Use list' : 'Enter ID',
                    style: T.body(11.5, color: Pal.goldDeep, w: FontWeight.w700),
                  ),
                )
              : null,
        ),
        if (hasOptions && !_manualMode)
          GoldDropdown<String>(
            value: matched ? current : null,
            hint: widget.hint,
            items: [
              if (widget.optional)
                DropdownMenuItem<String>(
                  value: '',
                  child: Text('None', style: T.body(13.5, color: Pal.muted)),
                ),
              for (final opt in widget.options)
                DropdownMenuItem<String>(
                  value: opt.id,
                  child: Text(
                    opt.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.body(13.5, w: FontWeight.w600),
                  ),
                ),
            ],
            onChanged: (v) {
              final next = v ?? '';
              widget.controller.text = next;
              final found = widget.options.where((o) => o.id == next).firstOrNull;
              widget.onSelected?.call(found);
              setState(() {});
            },
          )
        else
          TextField(
            controller: widget.controller,
            style: T.mono(13),
            decoration: InputDecoration(hintText: widget.hint),
          ),
      ],
    );
  }
}

/// Clean mobile calendar date field (`YYYY-MM-DD`) that never overflows.
class DatePickField extends StatelessWidget {
  const DatePickField({
    super.key,
    required this.label,
    required this.controller,
    this.optional = false,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool optional;
  final ValueChanged<String>? onChanged;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(controller.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2036),
    );
    if (picked != null) {
      final iso =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      controller.text = iso;
      onChanged?.call(iso);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(optional ? '$label (optional)' : label),
        TextField(
          controller: controller,
          readOnly: true,
          onTap: () => _pick(context),
          style: T.mono(13.2),
          decoration: InputDecoration(
            hintText: optional ? 'YYYY-MM-DD' : todayIso(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (optional && controller.text.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () {
                      controller.clear();
                      onChanged?.call('');
                    },
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.calendar_today_outlined, size: 17, color: Pal.goldDeep),
                  onPressed: () => _pick(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Signature gold status pill shown in the `pos.hrpocket.in` header bar:
/// `Bullion 24K: Fine 999 Board Active`
class BullionHeaderBadge extends StatelessWidget {
  const BullionHeaderBadge({super.key, this.dark = false});
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? Pal.goldBright.withValues(alpha: 0.14) : Pal.goldWash;
    final border = dark ? Pal.goldBright.withValues(alpha: 0.42) : Pal.goldBorder;
    final fg = dark ? Pal.goldSoft : Pal.goldDeep;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.toll_rounded, size: 13, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Bullion 24K: Fine 999 Board Active',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: T.body(11.5, color: fg, w: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean SaaS module header card matching `pos.hrpocket.in` page headers on mobile.
class SaasModuleHeader extends StatelessWidget {
  const SaasModuleHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge = 'Enterprise Control',
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return LuxuryHeroCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: EnterpriseBadge(badge, icon: icon),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(title, style: T.display(21, color: Colors.white)),
          const SizedBox(height: 4),
          Text(subtitle, style: T.body(12.5, color: Colors.white70)),
        ],
      ),
    );
  }
}
