import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart' show toApiDate;
import '../../core/change.dart';
import '../../core/family.dart';
import '../../core/l10n.dart';
import '../../core/mock/mock_store.dart';
import '../../core/module.dart';
import '../../core/widgets.dart';
import 'models.dart';
import 'repository.dart';
import 'todo_screen.dart';
import 'wall_filter.dart';

class TodoModule extends FamilyModule {
  const TodoModule();

  @override
  String get id => 'todo';
  @override
  String title(AppLocalizations l) => l.todoModuleTitle;
  @override
  IconData get icon => Icons.checklist_outlined;
  @override
  IconData get selectedIcon => Icons.checklist;

  @override
  Widget buildScreen(BuildContext context) => const TodoScreen();

  @override
  Widget? buildWallTile(BuildContext context) => WallCard(
    title: title(context.l10n),
    icon: selectedIcon,
    path: path,
    child: const _TodoWallTile(),
  );

  @override
  List<Widget> buildWallActions(BuildContext context) => const [
    WallTodoFilterButton(),
  ];

  /// A column per list with its open tasks (after the wall filter).
  @override
  List<Widget> buildWallColumns(BuildContext context, WidgetRef ref) {
    final (:lists, :items) = ref.watch(_wallTodosProvider);
    return [
      for (final l in lists)
        _KanbanColumn(
          key: ValueKey(l.id),
          list: l,
          items: items.where((i) => i.listId == l.id).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        ),
    ];
  }

  @override
  String? describeChange(AppLocalizations l, Change change) {
    if (change.collection == listsEntity) {
      final name = '${change.data['name']}';
      return switch (change.op) {
        ChangeOp.created => l.changeListCreated(name),
        ChangeOp.updated => l.changeListUpdated(name),
        ChangeOp.deleted => l.changeListDeleted(name),
      };
    }
    if (change.collection == commentsEntity) {
      return change.op == ChangeOp.created
          ? l.changeCommentAdded('${change.data['body']}')
          : null;
    }
    if (change.collection != itemsEntity) return null;
    final t = '${change.data['title']}';
    return switch (change.op) {
      ChangeOp.created => l.changeTaskAdded(t),
      ChangeOp.updated =>
        change.data['done'] == true
            ? l.changeTaskChecked(t)
            : l.changeTaskChanged(t),
      ChangeOp.deleted => l.changeTaskDeleted(t),
    };
  }

  @override
  void seedMock(MockStore store) {
    final now = DateTime.now();
    var n = 0;
    String ts() => now.subtract(Duration(minutes: 500 - n++)).toIso8601String();

    void list(String id, String name, int color, {int? dueInDays}) =>
        store.seed(listsEntity, {
          'id': id,
          'name': name,
          'color': color,
          'created_at': ts(),
          'due': toApiDate(
            dueInDays == null
                ? null
                : DateTime(now.year, now.month, now.day + dueInDays),
          ),
        });

    void item(
      String listId,
      String title, {
      bool done = false,
      String? who,
      int? dueInDays,
    }) => store.seed(itemsEntity, {
      'id': 'seed-${n + 1}',
      'list_id': listId,
      'title': title,
      'done': done,
      'created_at': ts(),
      'assignee_id': who,
      'due': toApiDate(
        dueInDays == null
            ? null
            : DateTime(now.year, now.month, now.day + dueInDays),
      ),
      'done_at': done ? now.toIso8601String() : null,
    });

    list('zakupy', 'Zakupy', 0xFF26A69A);
    list('dom', 'Dom', 0xFF5C6BC0);
    list('wakacje', 'Wakacje', 0xFFFFA726, dueInDays: 9);

    item('zakupy', 'Mleko');
    item('zakupy', 'Chleb');
    item('zakupy', 'Jajka (10 szt.)');
    item('zakupy', 'Pomidory', done: true);
    item('zakupy', 'Płyn do naczyń', who: 'tata');

    item('dom', 'Wymienić żarówkę w łazience', who: 'tata');
    item('dom', 'Odkurzyć pokój', who: 'kuba', dueInDays: 0);
    item('dom', 'Zapłacić za prąd', who: 'mama', dueInDays: 2);
    item('dom', 'Podlać kwiatki', who: 'ola', dueInDays: -1);
    item('dom', 'Wynieść śmieci', done: true, who: 'kuba');

    item('wakacje', 'Zarezerwować nocleg', who: 'mama');
    item('wakacje', 'Paszport dla Oli', dueInDays: 14);
    item('wakacje', 'Kupić krem z filtrem');
  }

  static const _shoppingPool = [
    'Masło',
    'Banany',
    'Ser żółty',
    'Kawa',
    'Jogurty',
    'Makaron',
    'Papier toaletowy',
    'Ogórki',
    'Herbata',
    'Ryż',
  ];

  @override
  Future<void> simulate(MockStore store, Random random, String actorId) async {
    final repo = MockTodoRepository(store, actorId: actorId);
    final items = store.list(itemsEntity).map(TodoItem.fromJson).toList();
    if (items.isNotEmpty && random.nextBool()) {
      final item = items[random.nextInt(items.length)];
      await repo.updateItem(item, item.toggled());
      return;
    }
    final lists = store.list(listsEntity);
    if (lists.isEmpty) return;
    final shopping = lists.firstWhere(
      (l) => l['name'] == 'Zakupy',
      orElse: () => lists.first,
    );
    await repo.addItem(
      shopping['id'] as String,
      _shoppingPool[random.nextInt(_shoppingPool.length)],
      assigneeId: random.nextInt(3) == 0 ? actorId : null,
    );
  }
}

/// The lists and open tasks the wall shows, after its filter.
final _wallTodosProvider =
    Provider<({List<TodoList> lists, List<TodoItem> items})>((ref) {
      final filter =
          ref.watch(wallTodoFilterProvider).value ?? const WallTodoFilter();
      return filter.apply(
        ref.watch(todoListsProvider).value ?? const <TodoList>[],
        ref.watch(todoOpenItemsProvider).value ?? const <TodoItem>[],
        ref.watch(currentMemberProvider),
      );
    });

class _TodoWallTile extends ConsumerWidget {
  const _TodoWallTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final (:lists, :items) = ref.watch(_wallTodosProvider);
    final me = ref.watch(currentMemberProvider);
    final l10n = context.l10n;
    if (lists.isEmpty &&
        (ref.watch(wallTodoFilterProvider).value?.isActive ?? false)) {
      return Text(
        l10n.todoWallFilterEmpty,
        style: TextStyle(color: theme.colorScheme.outline),
      );
    }

    final open = items.where((i) => !i.done).toList();
    // Overdue first, all of them, oldest first.
    final overdue = open.where((i) => i.overdue).toList()
      ..sort((a, b) => a.due!.compareTo(b.due!));
    final rest = open.where((i) => !i.overdue).toList()
      ..sort((a, b) {
        // Mine first, then by due date (tasks without one last).
        final mine = (a.assigneeId == me ? 0 : 1).compareTo(
          b.assigneeId == me ? 0 : 1,
        );
        if (mine != 0) return mine;
        if (a.due == null || b.due == null) {
          return (a.due == null ? 1 : 0).compareTo(b.due == null ? 1 : 0);
        }
        return a.due!.compareTo(b.due!);
      });

    Widget tile(TodoItem i) => WallTaskTile(i);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final l in lists)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                ColorDot(Color(l.color)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (l.due != null)
                        DueLabel(
                          l.due!,
                          overdue: l.overdue,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                Text(
                  l10n.todoOpenCount(
                    open.where((i) => i.listId == l.id).length,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        if (overdue.isNotEmpty) ...[
          const Divider(height: 20),
          Text(
            l10n.todoOverdueSection(overdue.length),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          for (final i in overdue) tile(i),
        ],
        if (rest.isNotEmpty) const Divider(height: 20),
        for (final i in rest.take(5)) tile(i),
      ],
    );
  }
}

/// An open task on the wall: the checkbox ticks it, tapping the row opens
/// the editor (a tap anywhere must not finish the task).
class WallTaskTile extends ConsumerWidget {
  const WallTaskTile(this.item, {super.key});
  final TodoItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final i = item;
    final assignee = ref.watch(familyProvider).byId(i.assigneeId);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: i.done,
        onChanged: (_) => toggleTodoDone(context, ref, i),
      ),
      title: Text(
        i.title,
        style: TextStyle(color: i.overdue ? theme.colorScheme.error : null),
      ),
      subtitle: i.due == null ? null : DueLabel(i.due!, overdue: i.overdue),
      trailing: assignee == null ? null : MemberAvatar(assignee, radius: 12),
      onTap: () => showTodoItemEditor(context, i),
    );
  }
}

class _KanbanColumn extends ConsumerStatefulWidget {
  const _KanbanColumn({super.key, required this.list, required this.items});
  final TodoList list;
  final List<TodoItem> items;

  @override
  ConsumerState<_KanbanColumn> createState() => _KanbanColumnState();
}

class _KanbanColumnState extends ConsumerState<_KanbanColumn> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String text) {
    final title = text.trim();
    if (title.isEmpty) return;
    _controller.clear();
    // With "only my tasks" a new task is mine, or it would vanish at once.
    final mine =
        ref.read(wallTodoFilterProvider).value?.scope == WallTodoScope.myTasks;
    ref
        .read(todoRepositoryProvider)
        .addItem(
          widget.list.id,
          title,
          assigneeId: mine ? ref.read(currentMemberProvider) : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final list = widget.list;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () {
                ref.read(selectedTodoListProvider.notifier).select(list.id);
                context.go(const TodoModule().path);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    ColorDot(Color(list.color), size: 12),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        list.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${widget.items.length}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (list.due != null)
              DueLabel(
                list.due!,
                overdue: list.overdue && widget.items.isNotEmpty,
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 4),
            if (widget.items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  l.todoAllDone,
                  style: TextStyle(color: theme.colorScheme.outline),
                ),
              ),
            for (final i in widget.items) WallTaskTile(i, key: ValueKey(i.id)),
            // Laid out like a [WallTaskTile]: the + sits where the checkboxes
            // are and the text starts where the task titles do.
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const SizedBox(
                width: kMinInteractiveDimension,
                child: Center(child: Icon(Icons.add, size: 20)),
              ),
              title: TextField(
                controller: _controller,
                onSubmitted: _add,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: l.todoAddTo(list.name),
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
