import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../modules/registry.dart';
import '../backend.dart';
import '../family.dart';

/// Tylko w trybie mock: udaje innych członków rodziny klikających w swoich
/// telefonach. Z prawdziwym serwerem wystarczy otworzyć drugą kartę
/// przeglądarki i zalogować się jako ktoś inny.
class FamilySimulator extends Notifier<bool> {
  Timer? _timer;
  final _random = Random();

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void toggle() {
    _timer?.cancel();
    _timer = null;
    state = !state;
    if (state) {
      _tick();
      _timer = Timer.periodic(const Duration(seconds: 4), (_) => _tick());
    }
  }

  void _tick() {
    final backend = ref.read(backendProvider);
    if (backend is! MockBackend) return;
    final me = ref.read(currentMemberProvider);
    final others = ref
        .read(familyProvider)
        .members
        .where((m) => m.id != me)
        .toList();
    if (others.isEmpty) return;
    final actor = others[_random.nextInt(others.length)];
    final module = modules[_random.nextInt(modules.length)];
    module.simulate(backend.store, _random, actor.id);
  }
}

final simulatorProvider = NotifierProvider<FamilySimulator, bool>(
  FamilySimulator.new,
);
