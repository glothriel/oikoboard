import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';

/// Records the updates [moveTodoItem] makes.
class _Repo implements TodoRepository {
  final updates = <String, double>{};

  @override
  Future<void> updateItem(TodoItem item, TodoItem updated) async =>
      updates[item.id] = updated.position;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TodoItem item(String id, double position) => TodoItem(
    id: id,
    listId: 'l',
    title: id,
    done: false,
    createdAt: DateTime(2026),
    position: position,
  );

  List<String> order(List<TodoItem> items, Map<String, double> updates) => ([
    for (final i in items) i.copyWith(position: updates[i.id]),
  ]..sort(TodoItem.byPosition)).map((i) => i.id).toList();

  test('moving a task sets a position between its new neighbours', () {
    final items = [item('a', 1), item('b', 2), item('c', 3)];
    for (final (from, to, want) in [
      (2, 0, 'cab'),
      (0, 2, 'bca'),
      (0, 1, 'bac'),
      (1, 0, 'bac'),
    ]) {
      final repo = _Repo();
      moveTodoItem(repo, items, from, to);
      expect(repo.updates, hasLength(1));
      expect(order(items, repo.updates).join(), want);
    }
  });

  test('without room between neighbours the tasks are renumbered', () {
    const p = 1.8e9;
    final next = p + 2.4e-7; // the next double after p
    final items = [item('a', p), item('b', next), item('c', next + 1)];
    final repo = _Repo();
    moveTodoItem(repo, items, 2, 1);
    expect(repo.updates, hasLength(3));
    expect(order(items, repo.updates).join(), 'acb');
  });

  test('lists follow the saved order, new ones at the end', () {
    TodoList list(String id) =>
        TodoList(id: id, name: id, color: 0, createdAt: DateTime(2026));
    final lists = [list('a'), list('b'), list('c'), list('d')];
    expect(
      orderLists(lists, ['c', 'gone', 'a']).map((l) => l.id).join(),
      'cabd',
    );
    expect(orderLists(lists, const []).map((l) => l.id).join(), 'abcd');
  });
}
