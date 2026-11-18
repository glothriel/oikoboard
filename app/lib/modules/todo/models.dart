import '../../core/api/api_client.dart'
    show fromApiDate, fromApiTime, toApiDate, toApiTime;
import '../../core/format.dart';

const _unset = Object();

class TodoList {
  const TodoList({
    required this.id,
    required this.name,
    required this.color,
    required this.createdAt,
    this.description = '',
    this.due,
  });

  final String id;
  final String name;

  /// Markdown; empty when there is none.
  final String description;
  final int color;
  final DateTime createdAt;

  /// Due date of the whole list (e.g. a packing list for a trip).
  final DateTime? due;

  /// Due before today.
  bool get overdue => due != null && due!.isBefore(dateOnly(DateTime.now()));

  bool dueOn(DateTime day) => due != null && isSameDay(due!, day);

  factory TodoList.fromJson(Map<String, dynamic> j) => TodoList(
    id: j['id'] as String,
    name: j['name'] as String,
    description: j['description'] as String? ?? '',
    color: j['color'] as int,
    createdAt: fromApiTime(j['created_at'])!,
    due: fromApiDate(j['due']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'color': color,
    'created_at': toApiTime(createdAt),
    'due': toApiDate(due),
  };

  /// [due] can be cleared by passing `null` explicitly.
  TodoList copyWith({
    String? name,
    String? description,
    int? color,
    Object? due = _unset,
  }) => TodoList(
    id: id,
    name: name ?? this.name,
    description: description ?? this.description,
    color: color ?? this.color,
    createdAt: createdAt,
    due: identical(due, _unset) ? this.due : due as DateTime?,
  );
}

class TodoItem {
  const TodoItem({
    required this.id,
    required this.listId,
    required this.title,
    required this.done,
    required this.createdAt,
    this.description = '',
    this.assigneeId,
    this.due,
    this.doneAt,
  });

  final String id;
  final String listId;
  final String title;

  /// Markdown; empty when there is none.
  final String description;
  final bool done;
  final DateTime createdAt;
  final String? assigneeId;

  /// Due date (local midnight; no time of day).
  final DateTime? due;
  final DateTime? doneAt;

  /// Open and due before today.
  bool get overdue =>
      !done && due != null && due!.isBefore(dateOnly(DateTime.now()));

  /// Open and due on [day].
  bool dueOn(DateTime day) => !done && due != null && isSameDay(due!, day);

  factory TodoItem.fromJson(Map<String, dynamic> j) => TodoItem(
    id: j['id'] as String,
    listId: j['list_id'] as String,
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    done: j['done'] as bool? ?? false,
    createdAt: fromApiTime(j['created_at'])!,
    assigneeId: j['assignee_id'] as String?,
    due: fromApiDate(j['due']),
    doneAt: fromApiTime(j['done_at']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'list_id': listId,
    'title': title,
    'description': description,
    'done': done,
    'created_at': toApiTime(createdAt),
    'assignee_id': assigneeId,
    'due': toApiDate(due),
    'done_at': toApiTime(doneAt),
  };

  /// Nullable fields can be cleared by passing `null` explicitly.
  TodoItem copyWith({
    String? title,
    String? description,
    bool? done,
    Object? assigneeId = _unset,
    Object? due = _unset,
    Object? doneAt = _unset,
  }) => TodoItem(
    id: id,
    listId: listId,
    title: title ?? this.title,
    description: description ?? this.description,
    done: done ?? this.done,
    createdAt: createdAt,
    assigneeId: identical(assigneeId, _unset)
        ? this.assigneeId
        : assigneeId as String?,
    due: identical(due, _unset) ? this.due : due as DateTime?,
    doneAt: identical(doneAt, _unset) ? this.doneAt : doneAt as DateTime?,
  );

  TodoItem toggled() =>
      copyWith(done: !done, doneAt: done ? null : DateTime.now());
}

/// One message in a task's comment thread.
class TodoComment {
  const TodoComment({
    required this.id,
    required this.itemId,
    required this.body,
    required this.createdAt,
    this.authorId,
  });

  final String id;
  final String itemId;
  final String body;
  final DateTime createdAt;

  /// Null when the author is no longer a member.
  final String? authorId;

  factory TodoComment.fromJson(Map<String, dynamic> j) => TodoComment(
    id: j['id'] as String,
    itemId: j['item_id'] as String,
    body: j['body'] as String,
    createdAt: fromApiTime(j['created_at'])!,
    authorId: j['author_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'item_id': itemId,
    'body': body,
    'created_at': toApiTime(createdAt),
    'author_id': authorId,
  };
}
