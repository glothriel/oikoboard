import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/mock/mock_store.dart';
import '../../core/module.dart';
import '../../core/family.dart';
import '../../core/widgets.dart';
import 'fitness_hub.dart';
import 'format.dart';
import 'measurements_screen.dart';
import 'profile_screen.dart';
import 'repository.dart';

class FitnessModule extends FamilyModule {
  const FitnessModule();

  @override
  String get id => 'fitness';
  @override
  String title(AppLocalizations l) => l.fitnessModuleTitle;
  @override
  IconData get icon => Icons.monitor_weight_outlined;
  @override
  IconData get selectedIcon => Icons.monitor_weight;

  @override
  Widget buildScreen(BuildContext context) => const FitnessHub();

  @override
  List<RouteBase> get subRoutes => [
    GoRoute(
      path: 'measurements',
      builder: (_, _) => const MeasurementsScreen(),
    ),
    GoRoute(path: 'profile', builder: (_, _) => const ProfileScreen()),
  ];

  @override
  Widget? buildWallTile(BuildContext context) => WallCard(
    title: context.l10n.fitnessWallTitle,
    icon: selectedIcon,
    path: path,
    child: const _FitnessWallTile(),
  );

  @override
  void seedMock(MockStore store) => seedFitnessMock(store);
}

/// The signed-in member's latest weight.
class _FitnessWallTile extends ConsumerWidget {
  const _FitnessWallTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final me = ref.watch(currentMemberProvider);
    final latest = ref
        .watch(measurementsProvider)
        .value
        ?.where((m) => m.memberId == me)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: latest == null
          ? Text(
              l.fitnessWallNone,
              style: TextStyle(color: theme.colorScheme.outline),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  kg(latest.weightKg),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text('kg', style: theme.textTheme.titleMedium),
              ],
            ),
    );
  }
}
