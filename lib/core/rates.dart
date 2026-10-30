import 'dart:async';
import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

/// Live bullion board. Polls every 60 s while the shell is mounted.
class RatesController extends ChangeNotifier {
  RatesController(this.api);
  final ApiClient api;

  List<MetalRate> rates = [];
  bool loading = false;
  String? error;
  DateTime? updatedAt;
  Timer? _timer;

  void start() {
    load();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => load(silent: true));
  }

  void stop() => _timer?.cancel();

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final d = await api.get('/rates');
      final list = d is Map ? d['metals'] : d;
      rates = asList(list).map(MetalRate.fromJson).toList();
      updatedAt = DateTime.now();
      error = null;
    } on ApiException catch (e) {
      // Keep the last good board on a silent refresh failure.
      if (!silent || rates.isEmpty) error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  MetalRate? find(String metal, String purity) {
    for (final r in rates) {
      if (r.metal == metal && r.purity == purity) return r;
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
