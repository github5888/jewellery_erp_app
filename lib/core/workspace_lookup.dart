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
/// present clean dropdowns AND allow optional exact UUID entry.
class WorkspaceLookup {
  List<LookupOption> parties = const [];
  List<LookupOption> locations = const [];
  List<LookupOption> articles = const [];
  List<LookupOption> materialLots = const [];
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
  List<LookupOption> estimates = const [];
  List<LookupOption> taxProfiles = const [];
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
                  label: code.isNotEmpty ? '$code · $name' : name,
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
                final kind = '${l['type'] ?? l['kind'] ?? ''}'.trim();
                return LookupOption(
                  id: id,
                  label: [
                    if (code.isNotEmpty) code,
                    '· $name',
                    if (kind.isNotEmpty) '($kind)',
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
                final tag = '${a['tag'] ?? a['tagNumber'] ?? a['barcode'] ?? ''}'.trim();
                final desc = '${a['description'] ?? a['name'] ?? 'Tagged Article'}'.trim();
                final wt = '${a['grossWeightGrams'] ?? ''}'.trim();
                final avail = '${asMap(a['balance'])['availability'] ?? ''}'.trim();
                return LookupOption(
                  id: id,
                  label: [
                    if (tag.isNotEmpty) tag,
                    desc,
                    if (wt.isNotEmpty) grams(wt),
                    if (avail.isNotEmpty) '[$avail]',
                  ].join(' · '),
                  raw: a,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();

          final lots = asList(
            d['materialLots'] ?? d['materialLotBalances'] ?? d['lotBalances'] ?? d,
            keys: const ['materialLots', 'materialLotBalances', 'lotBalances'],
          );
          final parsedLots = <LookupOption>[];
          final parsedBalances = <LookupOption>[];
          for (final l in lots) {
            final lid = '${l['id'] ?? ''}';
            final lCode = '${l['lotCode'] ?? l['code'] ?? 'Lot'}';
            final lDesc = '${l['description'] ?? ''}'.trim();
            final mCode = '${asMap(l['metal'])['code'] ?? ''}'.trim();
            final pCode = '${asMap(l['purityGrade'])['code'] ?? ''}'.trim();
            if (lid.isNotEmpty) {
              parsedLots.add(LookupOption(
                id: lid,
                label: [lCode, if (mCode.isNotEmpty) '$mCode $pCode', if (lDesc.isNotEmpty) lDesc].join(' · '),
                raw: l,
              ));
            }
            final nested = l['balances'];
            if (nested is List && nested.isNotEmpty) {
              for (final b in nested.whereType<Map>()) {
                final bm = Map<String, dynamic>.from(b);
                final bid = '${bm['id'] ?? ''}';
                if (bid.isEmpty) continue;
                final qty = '${bm['quantityGrams'] ?? l['acquiredWeightGrams'] ?? '0'}';
                final fine = '${bm['fineWeightGrams'] ?? l['acquiredFineWeightGrams'] ?? '0'}';
                final locCode = '${asMap(bm['location'])['code'] ?? ''}'.trim();
                parsedBalances.add(LookupOption(
                  id: bid,
                  label: [
                    lCode,
                    if (mCode.isNotEmpty) '$mCode $pCode',
                    '${grams(qty)}',
                    if (locCode.isNotEmpty) locCode,
                  ].join(' · '),
                  raw: {
                    ...l,
                    ...bm,
                    'lotId': lid,
                    'lotCode': lCode,
                    'quantityGrams': qty,
                    'fineWeightGrams': fine,
                    'balanceVersion': bm['version'] ?? 1,
                  },
                ));
              }
            } else {
              final id = '${l['balanceId'] ?? l['id'] ?? ''}';
              if (id.isEmpty) continue;
              final qty = '${l['quantityGrams'] ?? l['availableGrams'] ?? '0'}';
              parsedBalances.add(LookupOption(
                id: id,
                label: '$lCode · ${grams(qty)}',
                raw: l,
              ));
            }
          }
          w.materialLots = parsedLots;
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
          final seriesMap = <String, LookupOption>{};
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
                label: '${p['code'] ?? ''} · ${p['name'] ?? 'Period'} (${p['state'] ?? ''})',
                raw: p,
              ));
            }
            for (final s in asList(fy['series'])) {
              final sid = '${s['id'] ?? ''}';
              if (sid.isEmpty) continue;
              seriesMap[sid] = LookupOption(
                id: sid,
                label: '${s['prefix'] ?? s['seriesKey'] ?? 'SER'} · ${s['documentType'] ?? ''}',
                raw: s,
              );
            }
          }
          for (final s in asList(d['series'])) {
            final sid = '${s['id'] ?? ''}';
            if (sid.isEmpty) continue;
            seriesMap[sid] = LookupOption(
              id: sid,
              label: '${s['prefix'] ?? s['seriesKey'] ?? 'SER'} · ${s['documentType'] ?? ''}',
              raw: s,
            );
          }
          w.financialYears = fyOut;
          w.periods = periodOut;
          w.series = seriesMap.values.toList();

          final accts = asList(d['accounts'] ?? d, keys: const ['accounts']);
          w.accounts = accts
              .map((a) {
                final id = '${a['id'] ?? ''}';
                final ctrl = '${a['controlType'] ?? 'NONE'}';
                return LookupOption(
                  id: id,
                  label: '${a['code'] ?? ''} · ${a['name'] ?? 'Account'} (${ctrl != 'NONE' ? ctrl : a['group'] ?? ''})',
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
                label: '$mCode · $karat · $fine‰',
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
                    label: '${u['code'] ?? u['name'] ?? 'Unit'} (${u['symbol'] ?? u['code'] ?? ''})',
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
          final d = asMap(await api.get('/sales'));
          final invs = asList(d['invoices'] ?? d, keys: const ['invoices', 'salesInvoices']);
          w.invoices = invs
              .map((inv) {
                final id = '${inv['id'] ?? ''}';
                final num = '${inv['documentNumber'] ?? inv['invoiceNumber'] ?? shortId(id)}';
                final amt = '${inv['totalAmount'] ?? '0.00'}';
                return LookupOption(
                  id: id,
                  label: '$num · ${inr(amt)} (${inv['state'] ?? 'DRAFT'})',
                  raw: inv,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();
          final ests = asList(d['estimates']);
          w.estimates = ests
              .map((est) {
                final id = '${est['id'] ?? ''}';
                return LookupOption(
                  id: id,
                  label: '${est['quoteNumber'] ?? shortId(id)} · ${inr(est['totalAmount'])} (${est['state'] ?? ''})',
                  raw: est,
                );
              })
              .where((o) => o.id.isNotEmpty)
              .toList();
          final tps = asList(d['taxProfiles']);
          w.taxProfiles = tps
              .map((tp) {
                final id = '${tp['id'] ?? ''}';
                return LookupOption(
                  id: id,
                  label: '${tp['code'] ?? ''} · ${tp['name'] ?? ''} (${tp['ratePercent'] ?? '0'}%)',
                  raw: tp,
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
                final st = '${c['state'] ?? c['status'] ?? ''}';
                return LookupOption(
                  id: id,
                  label: [name, if (cap.isNotEmpty) cap, if (st.isNotEmpty) st].join(' · '),
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

  List<LookupOption> locationsByType(List<String> types) {
    if (types.isEmpty) return locations;
    final matches = locations.where((l) {
      final t = '${l.raw['type'] ?? l.raw['kind'] ?? ''}'.toUpperCase();
      return types.any((want) => t == want.toUpperCase());
    }).toList();
    return matches.isNotEmpty ? matches : locations;
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
      final docType = '${s.raw['documentType'] ?? ''} ${s.raw['seriesKey'] ?? ''} ${s.label}'.toUpperCase();
      return keywords.any((k) => docType.contains(k.toUpperCase()));
    }).toList();
    return filtered.isNotEmpty ? filtered : series;
  }

  List<LookupOption> accountsByControl(List<String> controls) {
    if (controls.isEmpty) return accounts;
    final matches = accounts.where((a) {
      final c = '${a.raw['controlType'] ?? ''}'.toUpperCase();
      final g = '${a.raw['group'] ?? ''}'.toUpperCase();
      return controls.any((k) => c == k.toUpperCase() || g == k.toUpperCase());
    }).toList();
    return matches.isNotEmpty ? matches : accounts;
  }

  List<LookupOption> puritiesForMetal(String? metalId) {
    if (metalId == null || metalId.isEmpty) return purityGrades;
    final matches = purityGrades.where((p) => '${p.raw['metalId'] ?? ''}' == metalId).toList();
    return matches.isNotEmpty ? matches : purityGrades;
  }
}

/// SDK-agnostic, overflow-proof luxury dropdown using `InputDecorator` + `DropdownButton`.
class GoldDropdown<T> extends StatelessWidget {
  const GoldDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.hintText,
    this.labelText,
    this.isDense = false,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;
  final String? hintText;
  final String? labelText;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    final validValue = items.any((it) => it.value == value) ? value : null;
    final effectiveHint = hint ?? hintText;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: labelText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 3),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: validValue,
          isExpanded: true,
          isDense: isDense,
          dropdownColor: Pal.card,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Pal.goldDeep),
          hint: effectiveHint != null
              ? Text(
                  effectiveHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body(13.2, color: Pal.muted.withValues(alpha: 0.78)),
                )
              : null,
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Mobile-first selector showing live workspace options (`Select...`) with a
/// 1-tap toggle to paste or edit a raw UUID directly (matching `pos.hrpocket.in`).
class LookupField extends StatefulWidget {
  const LookupField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    this.hint = 'Select...',
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
          widget.optional && !widget.label.contains('(optional)')
              ? '${widget.label} (optional)'
              : widget.label,
          trailing: hasOptions
              ? GestureDetector(
                  onTap: () => setState(() => _manualMode = !_manualMode),
                  child: Text(
                    _manualMode ? 'Select from list' : 'UUID',
                    style: T.body(11, color: Pal.goldDeep, w: FontWeight.w700),
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
                  child: Text('None', style: T.body(13.2, color: Pal.muted)),
                ),
              for (final opt in widget.options)
                DropdownMenuItem<String>(
                  value: opt.id,
                  child: Text(
                    opt.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.body(13.2, w: FontWeight.w600),
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
            style: T.mono(12.8),
            decoration: InputDecoration(hintText: widget.hint),
          ),
      ],
    );
  }
}

/// Clean labeled text input matching `pos.hrpocket.in` form fields.
class SaasField extends StatelessWidget {
  const SaasField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.mono = false,
    this.maxLines = 1,
    this.trailing,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final bool mono;
  final int maxLines;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(label, trailing: trailing),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: mono ? T.mono(13) : T.body(13.5, w: FontWeight.w500),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }
}

/// Clean labeled dropdown matching `pos.hrpocket.in` select inputs.
class SaasDropdown extends StatelessWidget {
  const SaasDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(label),
        GoldDropdown<String>(
          value: options.containsKey(value) ? value : options.keys.first,
          items: options.entries
              .map((e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.body(13.2, w: FontWeight.w600),
                    ),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

/// Clean mobile calendar date field (`YYYY-MM-DD`) that never overflows.
class DatePickField extends StatefulWidget {
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

  @override
  State<DatePickField> createState() => _DatePickFieldState();
}

class _DatePickFieldState extends State<DatePickField> {
  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(widget.controller.text.trim()) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2036),
    );
    if (picked != null) {
      final iso =
          '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      widget.controller.text = iso;
      widget.onChanged?.call(iso);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(
          widget.optional && !widget.label.contains('(optional)')
              ? '${widget.label} (optional)'
              : widget.label,
        ),
        TextField(
          controller: widget.controller,
          readOnly: true,
          onTap: () => _pick(context),
          style: T.mono(13),
          decoration: InputDecoration(
            hintText: widget.optional ? 'dd-mm-yyyy' : todayIso(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.optional && widget.controller.text.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.clear_rounded, size: 16),
                    onPressed: () {
                      widget.controller.clear();
                      widget.onChanged?.call('');
                      setState(() {});
                    },
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.calendar_today_outlined, size: 16, color: Pal.goldDeep),
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
              style: T.body(11.2, color: fg, w: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean SaaS page heading matching `pos.hrpocket.in` screenshots (`677`–`696`):
/// Gold module icon + crisp dark heading + muted 1-line subtitle + Bullion 24K badge.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const BullionHeaderBadge(),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 21, color: Pal.goldDeep),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: T.body(18.5, w: FontWeight.w800, color: Pal.ink)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: T.body(12.5, color: Pal.muted)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Crisp white bordered form card matching `pos.hrpocket.in` forms (`New work order`,
/// `New melt batch`, `New transfer request`, `New approval memo`, etc.).
class SaasFormCard extends StatelessWidget {
  const SaasFormCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Pal.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Pal.border),
        boxShadow: const [
          BoxShadow(color: Color(0x0A1A140B), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: 17, color: Pal.goldDeep),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: T.body(14.8, w: FontWeight.w800, color: Pal.ink)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: T.body(11.8, color: Pal.muted)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Tinted nested sub-box inside a form card (`pos.hrpocket.in` multi-line builder box).
class SaasSubBox extends StatelessWidget {
  const SaasSubBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Pal.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.border),
      ),
      child: child,
    );
  }
}

/// Dashed/soft empty-state container matching `No work orders yet.`, `No refining batches yet.`, etc.
class SaasEmptyBox extends StatelessWidget {
  const SaasEmptyBox(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: Pal.card.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Pal.borderStrong),
      ),
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: T.body(13, color: Pal.muted, w: FontWeight.w500),
      ),
    );
  }
}

/// Responsive 2-column KPI grid matching `pos.hrpocket.in` summary metric cards.
class SaasKpiGrid extends StatelessWidget {
  const SaasKpiGrid({super.key, required this.items});
  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 560 ? items.length.clamp(2, 4) : 2;
        final w = (constraints.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final it in items)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                  decoration: BoxDecoration(
                    color: Pal.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Pal.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        it.label.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.body(10, w: FontWeight.w700, color: Pal.muted, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        it.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.mono(16.5, w: FontWeight.w800, color: Pal.ink),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Clean checkbox row matching `pos.hrpocket.in` (`Enable e-invoice registration`, etc.).
class SaasCheckRow extends StatelessWidget {
  const SaasCheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                activeColor: Pal.goldDeep,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: T.body(13.2, color: Pal.ink, w: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}
