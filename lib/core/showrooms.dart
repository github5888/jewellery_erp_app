/// One selectable showroom context (Tenant > Legal Entity > Showroom Branch).
class ShowroomOption {
  ShowroomOption({
    required this.tenantId,
    required this.tenantName,
    required this.tenantSlug,
    required this.entityId,
    required this.entityName,
    required this.currency,
    required this.timezone,
    required this.branchId,
    required this.branchName,
    required this.branchCode,
  });

  final String tenantId;
  final String tenantName;
  final String tenantSlug;
  final String entityId;
  final String entityName;
  final String currency;
  final String timezone;
  final String branchId;
  final String branchName;
  final String branchCode;

  String get tenantLabel =>
      tenantName.isNotEmpty ? tenantName : (tenantId.isNotEmpty ? tenantId : 'Enterprise Store');

  String get branchLabel =>
      branchName.isNotEmpty ? branchName : (branchCode.isNotEmpty ? branchCode : branchId);
}

String _s(dynamic v) => v == null ? '' : '$v';

String _first(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty && v is! Map && v is! List) return '$v';
  }
  return '';
}

/// Parses GET /session memberships across both:
/// 1) Production `@jewellery-erp/contracts` shape:
///    `memberships: [{ id, tenant: { id, slug, name }, scopes: [{ legalEntity: { id, name, currency, timezone }, branch: { id, code, name } }] }]`
/// 2) Handoff doc shape:
///    `memberships: [{ tenantId, tenantName, legalEntities: [{ id, name, branches: [{ id, code, name }] }] }]`
List<ShowroomOption> parseShowrooms(Map<String, dynamic> session) {
  final out = <ShowroomOption>[];
  final seen = <String>{};

  void emit(Map b, Map<String, String> c, {required bool strict}) {
    final bid = _first(b, ['branchId', 'id']);
    final name = _first(b, ['branchName', 'name', 'displayName', 'title']);
    if (bid.isEmpty) return;
    if (strict && name.isEmpty) return;
    final tid = _first(b, ['tenantId']).isNotEmpty ? _first(b, ['tenantId']) : (c['t'] ?? '');
    final eid = _first(b, ['legalEntityId']).isNotEmpty ? _first(b, ['legalEntityId']) : (c['e'] ?? '');
    if (!seen.add('$tid|$eid|$bid')) return;
    out.add(ShowroomOption(
      tenantId: tid,
      tenantName: c['tn'] ?? '',
      tenantSlug: c['ts'] ?? '',
      entityId: eid,
      entityName: c['en'] ?? '',
      currency: c['cur'] ?? 'INR',
      timezone: c['tz'] ?? 'Asia/Kolkata',
      branchId: bid,
      branchName: name,
      branchCode: _first(b, ['code', 'branchCode']),
    ));
  }

  void walk(dynamic node, Map<String, String> c, String parentKey) {
    if (node is List) {
      for (final x in node) {
        walk(x, c, parentKey);
      }
      return;
    }
    if (node is! Map) return;
    final m = node;
    final cc = Map<String, String>.from(c);

    if (m['tenant'] is Map) {
      final t = m['tenant'] as Map;
      cc['t'] = _first(t, ['id', 'tenantId']);
      cc['tn'] = _first(t, ['name', 'tenantName', 'displayName']);
      cc['ts'] = _first(t, ['slug']);
    }
    if (m['tenantId'] != null) cc['t'] = _s(m['tenantId']);
    if (m['tenantName'] != null) cc['tn'] = _s(m['tenantName']);
    if (parentKey == 'tenants') {
      cc['t'] = _first(m, ['id', 'tenantId']);
      cc['tn'] = _first(m, ['name', 'tenantName']);
      cc['ts'] = _first(m, ['slug']);
    }

    if (m['legalEntity'] is Map) {
      final e = m['legalEntity'] as Map;
      cc['e'] = _first(e, ['id', 'legalEntityId']);
      cc['en'] = _first(e, ['name', 'legalName', 'legalEntityName']);
      final cur = _first(e, ['currency', 'functionalCurrency']);
      final tz = _first(e, ['timezone']);
      if (cur.isNotEmpty) cc['cur'] = cur;
      if (tz.isNotEmpty) cc['tz'] = tz;
    }
    if (m['legalEntityId'] != null) cc['e'] = _s(m['legalEntityId']);
    if (m['legalEntityName'] != null) cc['en'] = _s(m['legalEntityName']);
    if (parentKey == 'legalEntities') {
      cc['e'] = _first(m, ['id', 'legalEntityId']);
      cc['en'] = _first(m, ['name', 'legalName', 'legalEntityName']);
      final cur = _first(m, ['currency', 'functionalCurrency']);
      final tz = _first(m, ['timezone']);
      if (cur.isNotEmpty) cc['cur'] = cur;
      if (tz.isNotEmpty) cc['tz'] = tz;
    }

    if (m['branch'] is Map) {
      emit(m['branch'] as Map, cc, strict: false);
    } else if (parentKey == 'branches') {
      emit(m, cc, strict: false);
    } else if (m['branchId'] != null) {
      emit(m, cc, strict: true);
    }

    m.forEach((k, v) {
      if (k == 'user' || k == 'selectedContext' || k == 'mfa') return;
      if (v is Map || v is List) walk(v, cc, '$k');
    });
  }

  walk(session, <String, String>{}, '');
  return out;
}
