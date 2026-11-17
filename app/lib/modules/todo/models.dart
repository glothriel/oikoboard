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
  });

  final String id;
  final String name;
  final int color;
  final DateTime createdAt;

  factory TodoList.fromJson(Map<String, dynamic> j) => TodoList(
    id: j['id'] as String,
    name: j['name'] as String,
    color: j['color'] as int,
    createdAt: fromApiTime(j['created_at'])!,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'created_at': toApiTime(createdAt),
  };

  TodoList copyWith({String? name, int? color}) => TodoList(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    createdAt: createdAt,
  );
}

class TodoItem {
  const TodoItem({
    required this.id,
    required this.listId,
    required this.title,
    required this.done,
    required this.createdAt,
    this.assigneeId,
    this.due,
    this.doneAt,
  });

  final String id;
  final String listId;
  final String title;
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
    'done': done,
    'created_at': toApiTime(createdAt),
    'assignee_id': assigneeId,
    'due': toApiDate(due),
    'done_at': toApiTime(doneAt),
  };

  /// Pola nullowalne można wyczyścić przekazując jawnie `null`.
  TodoItem copyWith({
    String? title,
    bool? done,
    Object? assigneeId = _unset,
    Object? due = _unset,
    Object? doneAt = _unset,
  }) => TodoItem(
    id: id,
    listId: listId,
    title: title ?? this.title,
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
