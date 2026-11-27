import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/family.dart';
import '../../core/l10n.dart';
import 'format.dart';
import 'repository.dart';
import 'trend_chart.dart';

/// The Fitness section's home: one card per feature (cards sit side by side
/// on wide screens).
class FitnessHub extends StatelessWidget {
  const FitnessHub({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [_HubCard(width: 420, child: _MeasurementsCard())],
      ),
    ],
  );
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.width, required this.child});
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).width - 32;
    return SizedBox(width: available < width ? available : width, child: child);
  }
}

class _MeasurementsCard extends ConsumerWidget {
  const _MeasurementsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final me = ref.watch(currentMemberProvider);
    final mine = [
      for (final m in ref.watch(measurementsProvider).value ?? const [])
        if (m.memberId == me) m,
    ];
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/fitness/measurements'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_weight, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l.fitnessMeasurementsTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 8),
              if (mine.isEmpty)
                Text(
                  l.fitnessNoMeasurements,
                  style: TextStyle(color: theme.colorScheme.outline),
                )
              else ...[
                Text(
                  l.fitnessLatest(kg(mine.first.weightKg)),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 72,
                  child: TrendChart(
                    values: [
                      for (final m in mine.take(30).toList().reversed)
                        m.weightKg,
                    ],
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
