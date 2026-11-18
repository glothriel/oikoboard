import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'change.dart';
import 'l10n.dart';
import 'mock/mock_store.dart';

/// Contract of an app module (a “view”). A new feature = a new implementation
/// of this class + registering it in `modules/registry.dart`. Navigation, the
/// wall, change notices and the simulator are built from the module list.
abstract class FamilyModule {
  const FamilyModule();

  String get id;

  /// Localized name, shown in navigation and on the wall.
  String title(AppLocalizations l);
  IconData get icon;
  IconData get selectedIcon;
  String get path => '/$id';

  /// The module's main screen.
  Widget buildScreen(BuildContext context);

  /// Extra screens under [path] (e.g. details).
  List<RouteBase> get subRoutes => const [];

  /// Optional tile on the home screen (the “wall”).
  Widget? buildWallTile(BuildContext context) => null;

  /// Columns for the wall's board (kanban) layout; by default the wall tile.
  /// [ref] belongs to the wall, which rebuilds when watched data changes.
  List<Widget> buildWallColumns(BuildContext context, WidgetRef ref) => [
    ?buildWallTile(context),
  ];

  /// Description of a change made by another member (for a notice), or null
  /// if the change doesn't concern this module.
  String? describeChange(AppLocalizations l, Change change) => null;

  // --- mock only ---

  /// Sample data.
  void seedMock(MockStore store) {}

  /// One random action of “another family member” (for testing realtime).
  Future<void> simulate(MockStore store, Random random, String actorId) async {}
}
