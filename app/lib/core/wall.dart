import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../modules/registry.dart';
import 'family.dart';
import 'format.dart';
import 'session.dart';

/// Ekran główny — „ściana” z kafelkami wszystkich modułów.
class WallScreen extends ConsumerWidget {
  const WallScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Dzień dobry';
    if (h < 18) return 'Cześć';
    return 'Dobry wieczór';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider)!;
    final me = session.me;
    final tiles = [for (final m in modules) ?m.buildWallTile(context)];

    return LayoutBuilder(
      builder: (context, constraints) {
        const pad = 16.0;
        const gap = 12.0;
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
            Text(
              '${_greeting()}, ${me.name}!',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 2),
            Text(
              capitalize(DateFormat('EEEE, d MMMM y').format(DateTime.now())),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
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
