import 'package:material_ui/material_ui.dart' show TimeOfDay;

import '../../core/api/api_client.dart'
    show
        fromApiClock,
        fromApiDate,
        fromApiTime,
        toApiClock,
        toApiDate,
        toApiTime;
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
  TodoItem({
    required this.id,
    required this.listId,
    required this.title,
    required this.done,
    required this.createdAt,
    this.description = '',
    this.assigneeId,
    this.due,
    this.dueTime,
    this.doneAt,
    double? position,
  }) : position = position ?? createdAt.microsecondsSinceEpoch / 1e6;

  final String id;
  final String listId;
  final String title;

  /// Markdown; empty when there is none.
  final String description;
  final bool done;
  final DateTime createdAt;
  final String? assigneeId;

  /// Due date (local midnight).
  final DateTime? due;

  /// Optional time of [due]; null without a [due].
  final TimeOfDay? dueTime;
  final DateTime? doneAt;

  /// Manual order within the list, ascending; seconds since the epoch at
  /// creation, so new tasks go last.
  final double position;

  /// [due] at [dueTime] (or midnight): for sorting.
  DateTime? get dueAt => due == null || dueTime == null
      ? due
      : due!.add(Duration(hours: dueTime!.hour, minutes: dueTime!.minute));

  /// Open and due before today, or today at a time already past.
  bool get overdue {
    if (done || due == null) return false;
    final now = DateTime.now();
    return dueTime == null
        ? due!.isBefore(dateOnly(now))
        : dueAt!.isBefore(now);
  }

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
    dueTime: fromApiClock(j['due_time']),
    doneAt: fromApiTime(j['done_at']),
    position: (j['position'] as num?)?.toDouble(),
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
    'due_time': toApiClock(dueTime),
    'done_at': toApiTime(doneAt),
    'position': position,
  };

  /// Nullable fields can be cleared by passing `null` explicitly; clearing
  /// [due] clears [dueTime] too.
  TodoItem copyWith({
    String? title,
    String? description,
    bool? done,
    Object? assigneeId = _unset,
    Object? due = _unset,
    Object? dueTime = _unset,
    Object? doneAt = _unset,
    double? position,
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
    dueTime: !identical(due, _unset) && due == null
        ? null
        : identical(dueTime, _unset)
        ? this.dueTime
        : dueTime as TimeOfDay?,
    doneAt: identical(doneAt, _unset) ? this.doneAt : doneAt as DateTime?,
    position: position ?? this.position,
  );

  /// Manual order: by [position], then by creation.
  static int byPosition(TodoItem a, TodoItem b) {
    final c = a.position.compareTo(b.position);
    return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
  }

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

enum InboxKind { mention, reply, assigned }

/// One thing in the signed-in member's inbox (the server's `todo_inbox`).
class InboxEntry {
  const InboxEntry({
    required this.id,
    required this.kind,
    required this.listId,
    required this.title,
    required this.createdAt,
    this.itemId,
    this.commentId,
    this.actorId,
    this.excerpt = '',
    this.readAt,
  });

  final String id;
  final InboxKind kind;
  final String listId;

  /// Null: a mention in the list's description.
  final String? itemId;

  /// Null: about a description or an assignment.
  final String? commentId;
  final String? actorId;

  /// The task's (or list's) title and the comment's text when it happened.
  final String title;
  final String excerpt;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get unread => readAt == null;

  factory InboxEntry.fromJson(Map<String, dynamic> j) => InboxEntry(
    id: j['id'] as String,
    kind: InboxKind.values.byName(j['kind'] as String),
    listId: j['list_id'] as String,
    itemId: j['item_id'] as String?,
    commentId: j['comment_id'] as String?,
    actorId: j['actor_id'] as String?,
    title: j['title'] as String,
    excerpt: (j['excerpt'] as String?) ?? '',
    createdAt: fromApiTime(j['created_at'])!,
    readAt: fromApiTime(j['read_at']),
  );
}
