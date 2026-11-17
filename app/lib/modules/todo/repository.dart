import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/sync_client.dart';
import '../../core/backend.dart';
import '../../core/data.dart';
import '../../core/family.dart';
import '../../core/mock/mock_store.dart';
import 'models.dart';

const listsEntity = 'todo_lists';
const itemsEntity = 'todo_items';

/// Interfejs, którego używa UI. Metody `watch*` odpowiadają widokom
/// serwera (todo.lists, todo.list, todo.open).
abstract interface class TodoRepository {
  Stream<List<TodoList>> watchLists();
  Stream<List<TodoItem>> watchListItems(String listId);
  Stream<List<TodoItem>> watchOpenItems();

  Future<TodoList> addList(String name, {required int color});
  Future<void> updateList(TodoList list);
  Future<void> deleteList(String id);

  Future<TodoItem> addItem(
    String listId,
    String title, {
    String? assigneeId,
    DateTime? due,
  });
  Future<void> updateItem(TodoItem item);
  Future<void> deleteItem(String id);
}

List<TodoList> _sortLists(List<TodoList> l) =>
    l..sort((a, b) => a.createdAt.compareTo(b.createdAt));

// --- API ---

class ApiTodoRepository implements TodoRepository {
  ApiTodoRepository(this.api, this.sync);
  final ApiClient api;
  final SyncClient sync;

  @override
  Stream<List<TodoList>> watchLists() => sync
      .watch('todo.lists')
      .map(
        (v) => _sortLists(v.rows(listsEntity).map(TodoList.fromJson).toList()),
      );

  @override
  Stream<List<TodoItem>> watchListItems(String listId) => sync
      .watch('todo.list', {'list_id': listId})
      .map((v) => v.rows(itemsEntity).map(TodoItem.fromJson).toList());

  @override
  Stream<List<TodoItem>> watchOpenItems() => sync
      .watch('todo.open')
      .map((v) => v.rows(itemsEntity).map(TodoItem.fromJson).toList());

  @override
  Future<TodoList> addList(String name, {required int color}) async =>
      TodoList.fromJson(
        await api.post('/todo/lists', {
          'id': uuid.v4(),
          'name': name,
          'color': color,
        }),
      );

  @override
  Future<void> updateList(TodoList list) => api.patch(
    '/todo/lists/${list.id}',
    {'name': list.name, 'color': list.color},
  );

  @override
  Future<void> deleteList(String id) => api.delete('/todo/lists/$id');

  @override
  Future<TodoItem> addItem(
    String listId,
    String title, {
    String? assigneeId,
    DateTime? due,
  }) async => TodoItem.fromJson(
    await api.post('/todo/items', {
      'id': uuid.v4(),
      'list_id': listId,
      'title': title,
      'assignee_id': assigneeId,
      'due': toApiDate(due),
    }),
  );

  @override
  Future<void> updateItem(TodoItem item) =>
      api.patch('/todo/items/${item.id}', {
        'title': item.title,
        'done': item.done,
        'assignee_id': item.assigneeId,
        'due': toApiDate(item.due),
      });

  @override
  Future<void> deleteItem(String id) => api.delete('/todo/items/$id');
}

// --- mock ---

class MockTodoRepository implements TodoRepository {
  MockTodoRepository(this.store, {required this.actorId});

  final MockStore store;
  final String actorId;

  Stream<List<TodoItem>> _items(bool Function(TodoItem) where) => store
      .watch(itemsEntity)
      .map((docs) => docs.map(TodoItem.fromJson).where(where).toList());

  @override
  Stream<List<TodoList>> watchLists() => store
      .watch(listsEntity)
      .map((docs) => _sortLists(docs.map(TodoList.fromJson).toList()));

  @override
  Stream<List<TodoItem>> watchListItems(String listId) =>
      _items((i) => i.listId == listId);

  @override
  Stream<List<TodoItem>> watchOpenItems() => _items((i) => !i.done);

  @override
  Future<TodoList> addList(String name, {required int color}) async {
    final list = TodoList(
      id: uuid.v4(),
      name: name,
      color: color,
      createdAt: DateTime.now(),
    );
    await store.put(listsEntity, list.toJson(), actorId: actorId);
    return list;
  }

  @override
  Future<void> updateList(TodoList list) =>
      store.put(listsEntity, list.toJson(), actorId: actorId);

  @override
  Future<void> deleteList(String id) async {
    final items = store
        .list(itemsEntity)
        .where((d) => d['list_id'] == id)
        .map((d) => d['id'] as String);
    await Future.wait(items.map(deleteItem));
    await store.delete(listsEntity, id, actorId: actorId);
  }

  @override
  Future<TodoItem> addItem(
    String listId,
    String title, {
    String? assigneeId,
    DateTime? due,
  }) async {
    final item = TodoItem(
      id: uuid.v4(),
      listId: listId,
      title: title,
      done: false,
      createdAt: DateTime.now(),
      assigneeId: assigneeId,
      due: due,
    );
    await store.put(itemsEntity, item.toJson(), actorId: actorId);
    return item;
  }

  @override
  Future<void> updateItem(TodoItem item) =>
      store.put(itemsEntity, item.toJson(), actorId: actorId);

  @override
  Future<void> deleteItem(String id) =>
      store.delete(itemsEntity, id, actorId: actorId);
}

// --- providers ---

final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => switch (ref.watch(backendProvider)) {
    MockBackend(:final store) => MockTodoRepository(
      store,
      actorId: ref.watch(currentMemberProvider),
    ),
    ApiBackend() => ApiTodoRepository(
      ref.watch(apiClientProvider),
      ref.watch(syncClientProvider),
    ),
  },
);

final todoListsProvider = StreamProvider<List<TodoList>>(
  (ref) => ref.watch(todoRepositoryProvider).watchLists(),
);

final todoOpenItemsProvider = StreamProvider<List<TodoItem>>(
  (ref) => ref.watch(todoRepositoryProvider).watchOpenItems(),
);

final todoListItemsProvider = StreamProvider.autoDispose
    .family<List<TodoItem>, String>(
      (ref, listId) => ref.watch(todoRepositoryProvider).watchListItems(listId),
    );

class SelectedTodoList extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedTodoListProvider = NotifierProvider<SelectedTodoList, String?>(
  SelectedTodoList.new,
);
