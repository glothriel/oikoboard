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
const commentsEntity = 'todo_comments';

/// The interface the UI uses. The `watch*` methods match the server's views
/// (todo.lists, todo.list, todo.open, todo.comments).
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

  /// A task's comment thread, oldest first.
  Stream<List<TodoComment>> watchComments(String itemId);
  Future<void> addComment(String itemId, String body);

  /// Only the author can delete a comment.
  Future<void> deleteComment(String id);
}

List<TodoComment> _sortComments(Iterable<TodoComment> c) =>
    c.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

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
    {'name': list.name, 'color': list.color, 'due': toApiDate(list.due)},
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

  @override
  Stream<List<TodoComment>> watchComments(String itemId) => sync
      .watch('todo.comments', {'item_id': itemId})
      .map(
        (v) => _sortComments(v.rows(commentsEntity).map(TodoComment.fromJson)),
      );

  @override
  Future<void> addComment(String itemId, String body) => api.post(
    '/todo/comments',
    {'id': uuid.v4(), 'item_id': itemId, 'body': body},
  );

  @override
  Future<void> deleteComment(String id) => api.delete('/todo/comments/$id');
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
  Future<void> deleteItem(String id) async {
    final comments = store
        .list(commentsEntity)
        .where((d) => d['item_id'] == id)
        .map((d) => d['id'] as String)
        .toList();
    for (final c in comments) {
      await store.delete(commentsEntity, c, actorId: actorId);
    }
    await store.delete(itemsEntity, id, actorId: actorId);
  }

  @override
  Stream<List<TodoComment>> watchComments(String itemId) => store
      .watch(commentsEntity)
      .map(
        (docs) => _sortComments(
          docs.map(TodoComment.fromJson).where((c) => c.itemId == itemId),
        ),
      );

  @override
  Future<void> addComment(String itemId, String body) => store.put(
    commentsEntity,
    TodoComment(
      id: uuid.v4(),
      itemId: itemId,
      body: body.trim(),
      createdAt: DateTime.now(),
      authorId: actorId,
    ).toJson(),
    actorId: actorId,
  );

  @override
  Future<void> deleteComment(String id) =>
      store.delete(commentsEntity, id, actorId: actorId);
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

final todoCommentsProvider = StreamProvider.autoDispose
    .family<List<TodoComment>, String>(
      (ref, itemId) => ref.watch(todoRepositoryProvider).watchComments(itemId),
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
