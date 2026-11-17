import 'dart:math';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'change.dart';
import 'mock/mock_store.dart';

/// Kontrakt modułu („widoku”) aplikacji. Nowa funkcja = nowa implementacja
/// tej klasy + dopisanie jej do `modules/registry.dart`. Nawigacja, ściana,
/// powiadomienia o zmianach i symulator budują się z listy modułów.
abstract class FamilyModule {
  const FamilyModule();

  String get id;
  String get title;
  IconData get icon;
  IconData get selectedIcon;
  String get path => '/$id';

  /// Główny ekran modułu.
  Widget buildScreen(BuildContext context);

  /// Dodatkowe ekrany pod [path] (np. szczegóły).
  List<RouteBase> get subRoutes => const [];

  /// Kafelek na ekranie głównym („ścianie”), opcjonalny.
  Widget? buildWallTile(BuildContext context) => null;

  /// Opis zmiany od innej osoby (do powiadomienia), albo null jeśli
  /// zmiana nie dotyczy tego modułu.
  String? describeChange(Change change) => null;

  // --- tylko na czas mocka ---

  /// Dane przykładowe.
  void seedMock(MockStore store) {}

  /// Jedna losowa akcja „innego członka rodziny” (do testowania realtime).
  Future<void> simulate(MockStore store, Random random, String actorId) async {}
}
