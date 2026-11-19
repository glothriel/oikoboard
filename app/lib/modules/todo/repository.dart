import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/sync_client.dart';
import '../../core/backend.dart';
import '../../core/data.dart';
import '../../core/family.dart';
import '../../core/mentions.dart';
import '../../core/mock/mock_store.dart';
import '../../core/sync/outbox.dart';
import '../../core/undo_delete.dart';
import 'models.dart';

const listsEntity = 'todo_lists';
const itemsEntity = 'todo_items';
const commentsEntity = 'todo_comments';
const inboxEntity = 'todo_inbox';

/// The interface the UI uses. The `watch*` methods match the server's views
/// (todo.lists, todo.list, todo.open, todo.comments, todo.inbox).
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

  /// The signed-in member's inbox, newest first.
  Stream<List<InboxEntry>> watchInbox();

  /// Marks the unread ones of [entries] read.
  Future<void> markRead(Iterable<InboxEntry> entries);
}

List<InboxEntry> _sortInbox(Iterable<InboxEntry> e) =>
    e.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

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

  @override
  Stream<List<InboxEntry>> watchInbox() => sync
      .watch('todo.inbox', {
        'member_id': actorId,
      }, (e, r) => e == inboxEntity && r['member_id'] == actorId)
      .map((v) => _sortInbox(v.rows(inboxEntity).map(InboxEntry.fromJson)));

  @override
  Future<void> markRead(Iterable<InboxEntry> entries) async {
    final now = toApiTime(DateTime.now());
    for (final e in entries.where((e) => e.unread)) {
      outbox.enqueue(
        Mutation.patch('/todo/inbox/${e.id}', inboxEntity, e.id, {
          'read_at': now,
        }, label: e.title),
      );
    }
  }
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
    await _notify(
      _Notices()..mentions(description),
      listId: list.id,
      title: name,
    );
    return list;
  }

  @override
  Future<void> updateList(TodoList list, TodoList updated) async {
    await store.patch(
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
    await _notify(
      _Notices()..mentions(updated.description, list.description),
      listId: list.id,
      title: updated.name,
    );
  }

  @override
  Future<void> deleteList(TodoList list) async {
    final items = store
        .list(itemsEntity)
        .where((d) => d['list_id'] == list.id)
        .map(TodoItem.fromJson);
    await Future.wait(items.map(deleteItem));
    await _deleteInbox((e) => e['list_id'] == list.id);
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
    if (assigneeId != null) {
      await _notify(
        _Notices()..add(assigneeId, InboxKind.assigned),
        listId: listId,
        itemId: item.id,
        title: title,
      );
    }
    return item;
  }

  @override
  Future<void> updateItem(TodoItem item, TodoItem updated) async {
    await store.patch(
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
    final n = _Notices()..mentions(updated.description, item.description);
    if (updated.assigneeId case final a? when a != item.assigneeId) {
      n.add(a, InboxKind.assigned);
    }
    await _notify(
      n,
      listId: item.listId,
      itemId: item.id,
      title: updated.title,
    );
  }

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
    await _deleteInbox((e) => e['item_id'] == id);
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
  Future<void> addComment(String itemId, String body) async {
    final comment = TodoComment(
      id: uuid.v4(),
      itemId: itemId,
      body: body.trim(),
      createdAt: DateTime.now(),
      authorId: actorId,
    );
    await store.put(commentsEntity, comment.toJson(), actorId: actorId);
    final item = store
        .list(itemsEntity)
        .map(TodoItem.fromJson)
        .where((i) => i.id == itemId)
        .firstOrNull;
    if (item == null) return;
    final n = _Notices()..mentions(comment.body);
    // everyone in the thread: the assignee, commenters, earlier recipients
    for (final id in [
      ?item.assigneeId,
      for (final c in store.list(commentsEntity))
        if (c['item_id'] == itemId) ?c['author_id'] as String?,
      for (final e in store.list(inboxEntity))
        if (e['item_id'] == itemId) e['member_id'] as String,
    ]) {
      n.add(id, InboxKind.reply);
    }
    await _notify(
      n,
      listId: item.listId,
      itemId: itemId,
      commentId: comment.id,
      title: item.title,
      excerpt: comment.body,
    );
  }

  @override
  Future<void> deleteComment(TodoComment comment) async {
    await _deleteInbox((e) => e['comment_id'] == comment.id);
    await store.delete(commentsEntity, comment.id, actorId: actorId);
  }

  /// The server's ON DELETE CASCADE of inbox entries.
  Future<void> _deleteInbox(bool Function(Map<String, dynamic>) where) async {
    for (final e in store.list(inboxEntity).where(where)) {
      await store.delete(inboxEntity, e['id'] as String, actorId: actorId);
    }
  }

  @override
  Stream<List<InboxEntry>> watchInbox() => store
      .watch(inboxEntity)
      .map(
        (docs) => _sortInbox(
          docs.where((d) => d['member_id'] == actorId).map(InboxEntry.fromJson),
        ),
      );

  @override
  Future<void> markRead(Iterable<InboxEntry> entries) async {
    final now = toApiTime(DateTime.now());
    for (final e in entries.where((e) => e.unread)) {
      await store.patch(inboxEntity, e.id, {'read_at': now}, actorId: actorId);
    }
  }

  /// What the server does on a write: inbox entries for everyone in [n]
  /// but the actor.
  Future<void> _notify(
    _Notices n, {
    required String listId,
    String? itemId,
    String? commentId,
    required String title,
    String excerpt = '',
  }) async {
    for (final MapEntry(key: member, value: kind) in n.kinds.entries) {
      if (member == actorId) continue;
      await store.put(inboxEntity, {
        'id': uuid.v4(),
        'member_id': member,
        'kind': kind.name,
        'list_id': listId,
        'item_id': itemId,
        'comment_id': commentId,
        'actor_id': actorId,
        'title': title,
        'excerpt': excerpt,
        'read_at': null,
        'created_at': toApiTime(DateTime.now()),
      }, actorId: actorId);
    }
  }
}

/// Who gets an inbox entry about one write: one per member, the most
/// specific kind wins (as on the server).
class _Notices {
  final kinds = <String, InboxKind>{};

  static const _rank = {
    InboxKind.reply: 1,
    InboxKind.mention: 2,
    InboxKind.assigned: 3,
  };

  void add(String member, InboxKind kind) {
    final prev = kinds[member];
    if (prev == null || _rank[kind]! > _rank[prev]!) kinds[member] = kind;
  }

  /// Members newly mentioned in [text] (not already in [before]).
  void mentions(String text, [String before = '']) {
    final old = mentionedIds(before);
    for (final id in mentionedIds(text)) {
      if (!old.contains(id)) add(id, InboxKind.mention);
    }
  }
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

final todoInboxProvider = StreamProvider<List<InboxEntry>>(
  (ref) => ref.watch(todoRepositoryProvider).watchInbox(),
);

final todoUnreadCountProvider = Provider<int>(
  (ref) =>
      ref.watch(todoInboxProvider).value?.where((e) => e.unread).length ?? 0,
);

class SelectedTodoList extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedTodoListProvider = NotifierProvider<SelectedTodoList, String?>(
  SelectedTodoList.new,
);
