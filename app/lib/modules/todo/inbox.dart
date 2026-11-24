import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/family.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/mentions.dart';
import '../../core/widgets.dart';
import 'models.dart';
import 'repository.dart';
import 'todo_module.dart';

/// The inbox button in the app bar, with the number of unread entries.
class TodoInboxButton extends ConsumerWidget {
  const TodoInboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(todoUnreadCountProvider);
    final l = context.l10n;
    return IconButton(
      tooltip: unread == 0 ? l.todoInbox : l.todoInboxUnread(unread),
      icon: Badge.count(
        count: unread,
        isLabelVisible: unread > 0,
        child: Icon(unread > 0 ? Icons.inbox : Icons.inbox_outlined),
      ),
      onPressed: () => showSideSheet<void>(
        context,
        builder: (_) => _InboxSheet(onOpen: (e) => _open(context, ref, e)),
      ),
    );
  }

  /// Opens what [entry] is about: the task's list with the task's editor
  /// (and, for a comment, its thread over it), or just the list. [context]
  /// is the button's, which outlives the sheet.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    InboxEntry entry,
  ) async {
    final repo = ref.read(todoRepositoryProvider);
    final inbox = ref.read(todoInboxProvider).value ?? const <InboxEntry>[];
    // Opening a thread reads everything about it.
    repo.markRead(
      inbox.where(
        (e) =>
            entry.itemId == null ? e.id == entry.id : e.itemId == entry.itemId,
      ),
    );
    final itemId = entry.itemId;
    if (itemId == null) {
      showTodoList(context, ref, entry.listId);
      return;
    }
    final item = (await repo.watchListItems(entry.listId).first)
        .where((i) => i.id == itemId)
        .firstOrNull;
    if (!context.mounted) return;
    if (item == null) {
      showTodoList(context, ref, entry.listId);
      return;
    }
    await showTodoItem(context, ref, item, comments: entry.commentId != null);
  }
}

class _InboxSheet extends ConsumerWidget {
  const _InboxSheet({required this.onOpen});
  final void Function(InboxEntry) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final entries = ref.watch(todoInboxProvider).value ?? const <InboxEntry>[];
    final unread = entries.where((e) => e.unread).toList();
    return SideSheetScaffold(
      title: l.todoInbox,
      actions: [
        IconButton(
          tooltip: l.todoInboxMarkAllRead,
          icon: const Icon(Icons.done_all),
          onPressed: unread.isEmpty
              ? null
              : () => ref.read(todoRepositoryProvider).markRead(unread),
        ),
      ],
      children: [
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              l.todoInboxEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
        for (final e in entries)
          _InboxTile(
            key: ValueKey(e.id),
            entry: e,
            onTap: () {
              Navigator.pop(context);
              onOpen(e);
            },
          ),
      ],
    );
  }
}

class _InboxTile extends ConsumerWidget {
  const _InboxTile({super.key, required this.entry, required this.onTap});
  final InboxEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final family = ref.watch(familyProvider);
    final actor = family.byId(entry.actorId);
    final name = actor?.name ?? l.todoCommentFormerMember;
    final text = entry.recurring
        ? l.todoInboxRecurring(entry.title)
        : switch (entry.kind) {
            InboxKind.mention => l.todoInboxMention(name, entry.title),
            InboxKind.reply => l.todoInboxReply(name, entry.title),
            InboxKind.assigned => l.todoInboxAssigned(name, entry.title),
          };
    final local = entry.createdAt.toLocal();
    final when = isSameDay(local, DateTime.now())
        ? hm(local)
        : '${relativeDay(l, local)} ${hm(local)}';
    final muted = theme.colorScheme.outline;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor: entry.unread ? theme.colorScheme.secondaryContainer : null,
      leading: Badge(
        isLabelVisible: entry.unread,
        smallSize: 10,
        child: actor == null
            ? const CircleAvatar(
                radius: 16,
                child: Icon(Icons.person_outline, size: 18),
              )
            : MemberAvatar(actor, radius: 16),
      ),
      title: Text(
        text,
        style: TextStyle(
          fontWeight: entry.unread ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry.excerpt.isNotEmpty)
            Text(
              decodeMentions(entry.excerpt, family),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          Text(when, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        ],
      ),
      onTap: onTap,
    );
  }
}
