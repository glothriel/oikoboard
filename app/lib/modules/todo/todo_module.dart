import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart' show toApiDate;
import '../../core/change.dart';
import '../../core/family.dart';
import '../../core/format.dart';
import '../../core/mock/mock_store.dart';
import '../../core/module.dart';
import '../../core/widgets.dart';
import 'models.dart';
import 'repository.dart';
import 'todo_screen.dart';

class TodoModule extends FamilyModule {
  const TodoModule();

  @override
  String get id => 'todo';
  @override
  String get title => 'Listy';
  @override
  IconData get icon => Icons.checklist_outlined;
  @override
  IconData get selectedIcon => Icons.checklist;

  @override
  Widget buildScreen(BuildContext context) => const TodoScreen();

  @override
  Widget? buildWallTile(BuildContext context) => WallCard(
    title: title,
    icon: selectedIcon,
    path: path,
    child: const _TodoWallTile(),
  );

  @override
  String? describeChange(Change change) {
    if (change.collection == listsEntity) {
      final name = change.data['name'];
      return switch (change.op) {
        ChangeOp.created => 'nowa lista „$name”',
        ChangeOp.updated => 'zmieniona lista „$name”',
        ChangeOp.deleted => 'usunięta lista „$name”',
      };
    }
    if (change.collection != itemsEntity) return null;
    final t = change.data['title'];
    return switch (change.op) {
      ChangeOp.created => 'dodano „$t”',
      ChangeOp.updated =>
        change.data['done'] == true ? 'odhaczono „$t” ✓' : 'zmieniono „$t”',
      ChangeOp.deleted => 'usunięto „$t”',
    };
  }

  @override
  void seedMock(MockStore store) {
    final now = DateTime.now();
    var n = 0;
    String ts() => now.subtract(Duration(minutes: 500 - n++)).toIso8601String();

    void list(String id, String name, int color) => store.seed(listsEntity, {
      'id': id,
      'name': name,
      'color': color,
      'created_at': ts(),
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
    list('wakacje', 'Wakacje', 0xFFFFA726);

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
      await repo.updateItem(items[random.nextInt(items.length)].toggled());
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

class _TodoWallTile extends ConsumerWidget {
  const _TodoWallTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final lists = ref.watch(todoListsProvider).value ?? const <TodoList>[];
    final items = ref.watch(todoOpenItemsProvider).value ?? const <TodoItem>[];
    final family = ref.watch(familyProvider);
    final me = ref.watch(currentMemberProvider);

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

    Widget tile(TodoItem i) => CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: i.done,
      title: Text(
        i.title,
        style: TextStyle(color: i.overdue ? theme.colorScheme.error : null),
      ),
      subtitle: i.due == null
          ? null
          : Text(
              'termin: ${relativeDay(i.due!)}',
              style: TextStyle(
                color: i.overdue ? theme.colorScheme.error : null,
              ),
            ),
      secondary: family.byId(i.assigneeId) == null
          ? null
          : MemberAvatar(family.byId(i.assigneeId)!, radius: 12),
      onChanged: (_) =>
          ref.read(todoRepositoryProvider).updateItem(i.toggled()),
    );

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
                Expanded(child: Text(l.name)),
                Text(
                  '${open.where((i) => i.listId == l.id).length} do zrobienia',
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
            'Zaległe (${overdue.length})',
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
