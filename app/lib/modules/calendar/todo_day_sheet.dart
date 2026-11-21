import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/family.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/link_text.dart';
import '../../core/widgets.dart';
import '../todo/models.dart';
import '../todo/repository.dart';
import '../todo/todo_screen.dart' show showTodoItemEditor;

/// The tasks due on [day] — opened from the day's due-tasks event.
Future<void> showTodoDaySheet(BuildContext context, DateTime day) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TodoDaySheet(dateOnly(day)),
    );

class _TodoDaySheet extends ConsumerStatefulWidget {
  const _TodoDaySheet(this.day);
  final DateTime day;

  @override
  ConsumerState<_TodoDaySheet> createState() => _TodoDaySheetState();
}

class _TodoDaySheetState extends ConsumerState<_TodoDaySheet> {
  /// Tasks shown so far: ticked ones leave the open tasks but stay here
  /// (ticked), so a mis-tap can be undone.
  final _shown = <String, TodoItem>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = ref.watch(todoOpenItemsProvider).value ?? const <TodoItem>[];
    final allLists = ref.watch(todoListsProvider).value ?? const <TodoList>[];
    final lists = {for (final l in allLists) l.id: l};
    final dueLists = allLists.where((l) => l.dueOn(widget.day)).toList();
    final family = ref.watch(familyProvider);
    final l = context.l10n;
    for (final i in open.where((i) => i.dueOn(widget.day))) {
      _shown[i.id] = i;
    }
    final items = _shown.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.todoDaySheetTitle(
                capitalize(DateFormat('EEEE, d MMMM').format(widget.day)),
              ),
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final dl in dueLists)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ColorDot(Color(dl.color), size: 14),
                ),
                title: Text(dl.name),
                subtitle: Text(l.todoDayListDue),
                trailing: Text(
                  l.todoOpenCount(open.where((i) => i.listId == dl.id).length),
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () {
                  final router = GoRouter.of(context);
                  ref.read(selectedTodoListProvider.notifier).select(dl.id);
                  Navigator.pop(context);
                  router.go('/todo');
                },
              ),
            if (items.isEmpty && dueLists.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  l.todoDayEmpty,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final i in items)
                    // Tapping the row opens the task; only the checkbox
                    // ticks it.
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Checkbox(
                        value: i.done,
                        onChanged: (_) {
                          final next = i.toggled();
                          setState(() => _shown[i.id] = next);
                          ref.read(todoRepositoryProvider).updateItem(i, next);
                        },
                      ),
                      title: LinkText(
                        i.title,
                        style: i.done
                            ? TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: theme.colorScheme.outline,
                              )
                            : null,
                      ),
                      subtitle: lists[i.listId] == null
                          ? null
                          : Row(
                              children: [
                                ColorDot(Color(lists[i.listId]!.color)),
                                const SizedBox(width: 6),
                                Text(lists[i.listId]!.name),
                              ],
                            ),
                      trailing: family.byId(i.assigneeId) == null
                          ? null
                          : MemberAvatar(
                              family.byId(i.assigneeId)!,
                              radius: 14,
                            ),
                      onTap: () => showTodoItemEditor(context, i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lists due on [day] or with tasks due then (color dot + name), e.g.
/// under the day's due-tasks event in the agenda.
class TodoDayLists extends ConsumerWidget {
  const TodoDayLists(this.day, {super.key, this.style});
  final DateTime day;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(todoOpenItemsProvider).value ?? const <TodoItem>[];
    final ids = {for (final i in open.where((i) => i.dueOn(day))) i.listId};
    final lists = (ref.watch(todoListsProvider).value ?? const <TodoList>[])
        .where((l) => ids.contains(l.id) || l.dueOn(day))
        .toList();
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final l in lists)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorDot(Color(l.color), size: 8),
              const SizedBox(width: 4),
              Text(l.name, style: style),
            ],
          ),
      ],
    );
  }
}
