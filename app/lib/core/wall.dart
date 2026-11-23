import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../modules/registry.dart';
import 'family.dart';
import 'format.dart';
import 'l10n.dart';
import 'session.dart';

/// Home screen — the “wall” with a tile (or board columns) for each module.
class WallScreen extends ConsumerWidget {
  const WallScreen({super.key});

  String _greeting(AppLocalizations l) {
    final h = DateTime.now().hour;
    if (h < 11) return l.wallGreetingMorning;
    if (h < 18) return l.wallGreetingDay;
    return l.wallGreetingEvening;
  }

  Widget _header(BuildContext context, WidgetRef ref) {
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
            for (final m in modules) ...m.buildWallActions(context),
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
    const pad = 16.0;
    const gap = 12.0;

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
            _header(context, ref),
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
