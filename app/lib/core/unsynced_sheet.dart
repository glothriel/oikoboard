import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'data.dart';
import 'l10n.dart';
import 'sync/outbox.dart';

/// "Change “Milk”" — what a mutation did, for the UI.
String describeMutation(AppLocalizations l, Mutation m) {
  final name = m.label.isEmpty ? l.syncUnnamed : m.label;
  return switch (m.kind) {
    MutationKind.create => l.syncAdd(name),
    MutationKind.patch => l.syncChange(name),
    MutationKind.delete => l.syncDelete(name),
  };
}

Future<void> showUnsyncedSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const UnsyncedSheet(),
);

/// Changes the server rejected (the outbox's dead letter): what each would
/// have changed, why it failed, and retry / discard.
class UnsyncedSheet extends ConsumerWidget {
  const UnsyncedSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final outbox = ref.watch(outboxProvider);
    final failed = ref.watch(outboxStateProvider).value?.failed ?? const [];
    if (outbox == null) return const SizedBox();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(l.syncUnsyncedTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(l.syncUnsyncedHint, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            for (final f in failed.reversed)
              _FailedTile(
                key: ValueKey(f.mutation.id),
                failed: f,
                onRetry: () => outbox.retry(f),
                onDiscard: () => outbox.discard(f),
              ),
          ],
        ),
      ),
    );
  }
}

class _FailedTile extends ConsumerWidget {
  const _FailedTile({
    super.key,
    required this.failed,
    required this.onRetry,
    required this.onDiscard,
  });

  final FailedMutation failed;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  static String _show(Object? v) => switch (v) {
    null => '—',
    String s => s,
    _ => jsonEncode(v),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final m = failed.mutation;
    final current = ref
        .read(syncClientProvider)
        .serverRow(m.entity, m.entityId);
    final fields = switch (m.kind) {
      MutationKind.patch => m.fields,
      MutationKind.create => m.body ?? m.fields,
      MutationKind.delete => const <String, dynamic>{},
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(describeMutation(l, m), style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              l.syncServerSays(failed.status, failed.message),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
            if (fields.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final MapEntry(:key, :value) in fields.entries)
                if (key != 'id')
                  Text(
                    l.syncDiffLine(key, _show(current?[key]), _show(value)),
                    style: theme.textTheme.bodySmall,
                  ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: onDiscard, child: Text(l.syncDiscard)),
                TextButton(onPressed: onRetry, child: Text(l.syncRetry)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
