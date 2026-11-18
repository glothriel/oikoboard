import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../modules/registry.dart';
import 'device_prefs.dart';
import 'family.dart';
import 'format.dart';
import 'l10n.dart';
import 'session.dart';

/// How the wall shows the modules: today's overview (cards) or a board with
/// a column per list.
enum WallLayout { today, kanban }

/// The wall layout, remembered per member on this device.
class WallLayoutPreference extends AsyncNotifier<WallLayout> {
  String get _key => 'oiko.wall_layout.${ref.read(currentMemberProvider)}';

  @override
  Future<WallLayout> build() async {
    ref.watch(currentMemberProvider);
    final v = await DevicePrefs.get(_key);
    return WallLayout.values.where((l) => l.name == v).firstOrNull ??
        WallLayout.today;
  }

  Future<void> set(WallLayout layout) async {
    state = AsyncData(layout);
    await DevicePrefs.set(_key, layout.name);
  }
}

final wallLayoutProvider =
    AsyncNotifierProvider<WallLayoutPreference, WallLayout>(
      WallLayoutPreference.new,
    );

/// Home screen — the “wall” with a tile (or board columns) for each module.
class WallScreen extends ConsumerWidget {
  const WallScreen({super.key});

  String _greeting(AppLocalizations l) {
    final h = DateTime.now().hour;
    if (h < 11) return l.wallGreetingMorning;
    if (h < 18) return l.wallGreetingDay;
    return l.wallGreetingEvening;
  }

  Widget _header(BuildContext context, WidgetRef ref, WallLayout layout) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider)!;
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.wallGreeting(_greeting(l), session.me.name),
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    capitalize(
                      DateFormat('EEEE, d MMMM y').format(DateTime.now()),
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            SegmentedButton<WallLayout>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: WallLayout.today,
                  icon: const Icon(Icons.dashboard_outlined),
                  tooltip: l.wallLayoutToday,
                ),
                ButtonSegment(
                  value: WallLayout.kanban,
                  icon: const Icon(Icons.view_kanban_outlined),
                  tooltip: l.wallLayoutKanban,
                ),
              ],
              selected: {layout},
              onSelectionChanged: (s) =>
                  ref.read(wallLayoutProvider.notifier).set(s.single),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final m in session.members)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(message: m.name, child: MemberAvatar(m)),
              ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(wallLayoutProvider).value ?? WallLayout.today;
    const pad = 16.0;
    const gap = 12.0;

    if (layout == WallLayout.kanban) {
      final columns = [
        for (final m in modules) ...m.buildWallColumns(context, ref),
      ];
      return Padding(
        padding: const EdgeInsets.fromLTRB(pad, pad, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: pad),
              child: _header(context, ref, layout),
            ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: pad, bottom: pad),
                itemCount: columns.length,
                separatorBuilder: (_, _) => const SizedBox(width: gap),
                itemBuilder: (_, i) => SizedBox(
                  width: 300,
                  child: SingleChildScrollView(child: columns[i]),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final tiles = [for (final m in modules) ?m.buildWallTile(context)];
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final width =
            (constraints.maxWidth - pad * 2 - gap * (cols - 1)) / cols;

        return ListView(
          padding: const EdgeInsets.all(pad),
          children: [
            _header(context, ref, layout),
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final t in tiles) SizedBox(width: width, child: t),
              ],
            ),
          ],
        );
      },
    );
  }
}
