/// One selectable showroom (tenant > legal entity > branch).
class ShowroomOption {
  ShowroomOption({
    required this.tenantId,
    required this.tenantName,
    required this.entityId,
    required this.entityName,
    required this.branchId,
    required this.branchName,
    required this.branchCode,
  });
  final String tenantId, tenantName, entityId, entityName, branchId, branchName, branchCode;

  String get tenantLabel =>
      tenantName.isNotEmpty ? tenantName : (tenantId.isNotEmpty ? tenantId : 'Your business');
  String get branchLabel => branchName.isNotEmpty ? branchName : (branchCode.isNotEmpty ? branchCode : branchId);
}

String _s(dynamic v) => v == null ? '' : '$v';

String _first(Map m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty && v is! Map && v is! List) return '$v';
  }
  return '';
}

/// Reads the showroom list out of GET /session without assuming one exact
/// shape: handles tenants > legalEntities > branches (as in the guide),
/// membership objects with nested tenant/legalEntity/branch, and flat rows
/// that carry tenantId / legalEntityId / branchId directly.
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
      entityId: eid,
      entityName: c['en'] ?? '',
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
    }
    if (m['tenantId'] != null) cc['t'] = _s(m['tenantId']);
    if (m['tenantName'] != null) cc['tn'] = _s(m['tenantName']);
    if (parentKey == 'tenants') {
      cc['t'] = _first(m, ['id', 'tenantId']);
      cc['tn'] = _first(m, ['name', 'tenantName']);
    }

    if (m['legalEntity'] is Map) {
      final e = m['legalEntity'] as Map;
      cc['e'] = _first(e, ['id', 'legalEntityId']);
      cc['en'] = _first(e, ['name', 'legalName', 'legalEntityName']);
    }
    if (m['legalEntityId'] != null) cc['e'] = _s(m['legalEntityId']);
    if (m['legalEntityName'] != null) cc['en'] = _s(m['legalEntityName']);
    if (parentKey == 'legalEntities') {
      cc['e'] = _first(m, ['id', 'legalEntityId']);
      cc['en'] = _first(m, ['name', 'legalName', 'legalEntityName']);
    }

    if (m['branch'] is Map) {
      emit(m['branch'] as Map, cc, strict: false);
    } else if (parentKey == 'branches') {
      emit(m, cc, strict: false);
    } else if (m['branchId'] != null) {
      emit(m, cc, strict: true);
    }

    m.forEach((k, v) {
      if (k == 'user' || k == 'selectedContext') return;
      if (v is Map || v is List) walk(v, cc, '$k');
    });
  }

  walk(session, <String, String>{}, '');
  return out;
}
