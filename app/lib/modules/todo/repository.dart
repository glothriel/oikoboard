import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/sync_client.dart';
import '../../core/backend.dart';
import '../../core/data.dart';
import '../../core/family.dart';
import '../../core/mock/mock_store.dart';
import '../../core/sync/outbox.dart';
import '../../core/undo_delete.dart';
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

  Future<TodoList> addList(
    String name, {
    required int color,
    String description = '',
    DateTime? due,
  });

  /// Sends only the fields that differ between [list] and [updated].
  Future<void> updateList(TodoList list, TodoList updated);
  Future<void> deleteList(TodoList list);

  Future<TodoItem> addItem(
    String listId,
    String title, {
    String? assigneeId,
    DateTime? due,
  });

  /// Sends only the fields that differ between [item] and [updated].
  Future<void> updateItem(TodoItem item, TodoItem updated);
  Future<void> deleteItem(TodoItem item);

  /// A task's comment thread, oldest first.
  Stream<List<TodoComment>> watchComments(String itemId);
  Future<void> addComment(String itemId, String body);

  /// Only the author can delete a comment.
  Future<void> deleteComment(TodoComment comment);
}

List<TodoComment> _sortComments(Iterable<TodoComment> c) =>
    c.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

List<TodoList> _sortLists(List<TodoList> l) =>
    l..sort((a, b) => a.createdAt.compareTo(b.createdAt));

// --- API ---

/// Reads come from the WebSocket views, writes go through the [Outbox] and
/// show up in the views at once (docs/backend-realtime.md, "Offline writes").
class ApiTodoRepository implements TodoRepository {
  ApiTodoRepository(this.sync, this.outbox, {required this.actorId});
  final SyncClient sync;
  final Outbox outbox;
  final String actorId;

  static const _listFields = ['name', 'description', 'color', 'due'];
  static const _itemFields = [
    'title',
    'description',
    'done',
    'assignee_id',
    'due',
    'due_time',
  ];

  @override
  Stream<List<TodoList>> watchLists() => sync
      .watch('todo.lists', const {}, (e, _) => e == listsEntity)
      .map(
        (v) => _sortLists(v.rows(listsEntity).map(TodoList.fromJson).toList()),
      );

  @override
  Stream<List<TodoItem>> watchListItems(String listId) => sync
      .watch(
        'todo.list',
        {'list_id': listId},
        (e, r) => switch (e) {
          listsEntity => r['id'] == listId,
          itemsEntity => r['list_id'] == listId,
          _ => false,
        },
      )
      .map((v) => v.rows(itemsEntity).map(TodoItem.fromJson).toList());

  @override
  Stream<List<TodoItem>> watchOpenItems() => sync
      .watch(
        'todo.open',
        const {},
        (e, r) => e == itemsEntity && r['done'] != true,
      )
      .map((v) => v.rows(itemsEntity).map(TodoItem.fromJson).toList());

  @override
  Future<TodoList> addList(
    String name, {
    required int color,
    String description = '',
    DateTime? due,
  }) async {
    final list = TodoList(
      id: uuid.v4(),
      name: name,
      description: description,
      color: color,
      createdAt: DateTime.now(),
      due: due,
    );
    outbox.enqueue(
      Mutation.create(
        '/todo/lists',
        listsEntity,
        list.toJson(),
        body: {
          'id': list.id,
          'name': name,
          'description': description,
          'color': color,
          'due': toApiDate(due),
        },
        label: name,
      ),
    );
    return list;
  }

  @override
  Future<void> updateList(TodoList list, TodoList updated) async {
    final fields = changedFields(list.toJson(), updated.toJson(), _listFields);
    if (fields.isEmpty) return;
    outbox.enqueue(
      Mutation.patch(
        '/todo/lists/${list.id}',
        listsEntity,
        list.id,
        fields,
        label: updated.name,
      ),
    );
  }

  @override
  Future<void> deleteList(TodoList list) async => outbox.enqueue(
    Mutation.delete(
      '/todo/lists/${list.id}',
      listsEntity,
      list.id,
      cascade: const [(itemsEntity, 'list_id')],
      label: list.name,
    ),
  );

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
    outbox.enqueue(
      Mutation.create(
        '/todo/items',
        itemsEntity,
        item.toJson(),
        body: {
          'id': item.id,
          'list_id': listId,
          'title': title,
          'assignee_id': assigneeId,
          'due': toApiDate(due),
        },
        label: title,
      ),
    );
    return item;
  }

  @override
  Future<void> updateItem(TodoItem item, TodoItem updated) async {
    final fields = changedFields(item.toJson(), updated.toJson(), _itemFields);
    if (fields.isEmpty) return;
    outbox.enqueue(
      Mutation.patch(
        '/todo/items/${item.id}',
        itemsEntity,
        item.id,
        fields,
        label: updated.title,
      ),
    );
  }

  @override
  Future<void> deleteItem(TodoItem item) async => outbox.enqueue(
    Mutation.delete(
      '/todo/items/${item.id}',
      itemsEntity,
      item.id,
      cascade: const [(commentsEntity, 'item_id')],
      label: item.title,
    ),
  );

  @override
  Stream<List<TodoComment>> watchComments(String itemId) => sync
      .watch('todo.comments', {
        'item_id': itemId,
      }, (e, r) => e == commentsEntity && r['item_id'] == itemId)
      .map(
        (v) => _sortComments(v.rows(commentsEntity).map(TodoComment.fromJson)),
      );

  @override
  Future<void> addComment(String itemId, String body) async {
    final comment = TodoComment(
      id: uuid.v4(),
      itemId: itemId,
      body: body.trim(),
      createdAt: DateTime.now(),
      authorId: actorId,
    );
    outbox.enqueue(
      Mutation.create(
        '/todo/comments',
        commentsEntity,
        comment.toJson(),
        body: {'id': comment.id, 'item_id': itemId, 'body': comment.body},
        label: comment.body,
      ),
    );
  }

  @override
  Future<void> deleteComment(TodoComment comment) async => outbox.enqueue(
    Mutation.delete(
      '/todo/comments/${comment.id}',
      commentsEntity,
      comment.id,
      label: comment.body,
    ),
  );
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
  Future<TodoList> addList(
    String name, {
    required int color,
    String description = '',
    DateTime? due,
  }) async {
    final list = TodoList(
      id: uuid.v4(),
      name: name,
      description: description,
      color: color,
      createdAt: DateTime.now(),
      due: due,
    );
    await store.put(listsEntity, list.toJson(), actorId: actorId);
    return list;
  }

  @override
  Future<void> updateList(TodoList list, TodoList updated) => store.patch(
    listsEntity,
    list.id,
    changedFields(list.toJson(), updated.toJson(), const [
      'name',
      'description',
      'color',
      'due',
    ]),
    actorId: actorId,
  );

  @override
  Future<void> deleteList(TodoList list) async {
    final items = store
        .list(itemsEntity)
        .where((d) => d['list_id'] == list.id)
        .map(TodoItem.fromJson);
    await Future.wait(items.map(deleteItem));
    await store.delete(listsEntity, list.id, actorId: actorId);
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
  Future<void> updateItem(TodoItem item, TodoItem updated) => store.patch(
    itemsEntity,
    item.id,
    changedFields(item.toJson(), updated.toJson(), const [
      'title',
      'description',
      'done',
      'done_at',
      'assignee_id',
      'due',
      'due_time',
    ]),
    actorId: actorId,
  );

  @override
  Future<void> deleteItem(TodoItem item) async {
    final id = item.id;
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
  Future<void> deleteComment(TodoComment comment) =>
      store.delete(commentsEntity, comment.id, actorId: actorId);
}

// --- providers ---

final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => switch (ref.watch(backendProvider)) {
    MockBackend(:final store) => MockTodoRepository(
      store,
      actorId: ref.watch(currentMemberProvider),
    ),
    ApiBackend() => ApiTodoRepository(
      ref.watch(syncClientProvider),
      ref.watch(outboxProvider)!,
      actorId: ref.watch(currentMemberProvider),
    ),
  },
);

// Keys for [deleteWithUndo]: hidden while its snackbar is up.
String todoListKey(String id) => '$listsEntity:$id';
String todoItemKey(String id) => '$itemsEntity:$id';
String todoCommentKey(String id) => '$commentsEntity:$id';

List<TodoItem> _withoutPending(List<TodoItem> items, Set<String> pending) =>
    pending.isEmpty
    ? items
    : items
          .where(
            (i) =>
                !pending.contains(todoItemKey(i.id)) &&
                !pending.contains(todoListKey(i.listId)),
          )
          .toList();

final _todoLists = StreamProvider<List<TodoList>>(
  (ref) => ref.watch(todoRepositoryProvider).watchLists(),
);

final todoListsProvider = Provider<AsyncValue<List<TodoList>>>((ref) {
  final pending = ref.watch(pendingDeletesProvider);
  return ref
      .watch(_todoLists)
      .whenData(
        (l) => l.where((l) => !pending.contains(todoListKey(l.id))).toList(),
      );
});

final _todoOpenItems = StreamProvider<List<TodoItem>>(
  (ref) => ref.watch(todoRepositoryProvider).watchOpenItems(),
);

final todoOpenItemsProvider = Provider<AsyncValue<List<TodoItem>>>(
  (ref) => ref
      .watch(_todoOpenItems)
      .whenData((i) => _withoutPending(i, ref.watch(pendingDeletesProvider))),
);

final _todoComments = StreamProvider.autoDispose
    .family<List<TodoComment>, String>(
      (ref, itemId) => ref.watch(todoRepositoryProvider).watchComments(itemId),
    );

final todoCommentsProvider = Provider.autoDispose
    .family<AsyncValue<List<TodoComment>>, String>((ref, itemId) {
      final pending = ref.watch(pendingDeletesProvider);
      return ref
          .watch(_todoComments(itemId))
          .whenData(
            (c) => c
                .where((c) => !pending.contains(todoCommentKey(c.id)))
                .toList(),
          );
    });

final _todoListItems = StreamProvider.autoDispose
    .family<List<TodoItem>, String>(
      (ref, listId) => ref.watch(todoRepositoryProvider).watchListItems(listId),
    );

final todoListItemsProvider = Provider.autoDispose
    .family<AsyncValue<List<TodoItem>>, String>(
      (ref, listId) => ref
          .watch(_todoListItems(listId))
          .whenData(
            (i) => _withoutPending(i, ref.watch(pendingDeletesProvider)),
          ),
    );

class SelectedTodoList extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedTodoListProvider = NotifierProvider<SelectedTodoList, String?>(
  SelectedTodoList.new,
);
