import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show TimeOfDay;

import '../../core/api/api_client.dart';
import '../../core/api/sync_client.dart';
import '../../core/backend.dart';
import '../../core/data.dart';
import '../../core/family.dart';
import '../../core/mock/mock_store.dart';
import '../../core/sync/outbox.dart';
import 'recurrence.dart';

const recurringEntity = 'todo_recurring';

const _unset = Object();

/// A template that makes the server create a task on every occurrence of
/// its [rrule] (docs: the recurring tasks capability).
class RecurringTask {
  const RecurringTask({
    required this.id,
    required this.listId,
    required this.title,
    required this.rrule,
    required this.startDate,
    this.description = '',
    this.assigneeId,
    this.endDate,
    this.createTime = const TimeOfDay(hour: 6, minute: 0),
    this.dueOffsetDays,
    this.dueTime,
    this.active = true,
    this.lastRunDate,
  });

  final String id;
  final String listId;
  final String title;
  final String description;
  final String? assigneeId;

  /// RFC 5545 RRULE without DTSTART, COUNT and UNTIL.
  final String rrule;
  final DateTime startDate;

  /// Last day a task can be created (inclusive).
  final DateTime? endDate;

  /// When the task is created, in the household's timezone.
  final TimeOfDay createTime;

  /// Due date = occurrence date + this many days; null = no due date.
  final int? dueOffsetDays;

  /// Time of the due date; null without [dueOffsetDays].
  final TimeOfDay? dueTime;
  final bool active;
  final DateTime? lastRunDate;

  factory RecurringTask.fromJson(Map<String, dynamic> j) => RecurringTask(
    id: j['id'] as String,
    listId: j['list_id'] as String,
    title: j['title'] as String,
    description: j['description'] as String? ?? '',
    assigneeId: j['assignee_id'] as String?,
    rrule: j['rrule'] as String,
    startDate: fromApiDate(j['start_date'])!,
    endDate: fromApiDate(j['end_date']),
    createTime:
        fromApiClock(j['create_time']) ?? const TimeOfDay(hour: 6, minute: 0),
    dueOffsetDays: j['due_offset_days'] as int?,
    dueTime: fromApiClock(j['due_time']),
    active: j['active'] as bool? ?? true,
    lastRunDate: fromApiDate(j['last_run_date']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'list_id': listId,
    'title': title,
    'description': description,
    'assignee_id': assigneeId,
    'rrule': rrule,
    'start_date': toApiDate(startDate),
    'end_date': toApiDate(endDate),
    'create_time': toApiClock(createTime),
    'due_offset_days': dueOffsetDays,
    'due_time': toApiClock(dueOffsetDays == null ? null : dueTime),
    'active': active,
    'last_run_date': toApiDate(lastRunDate),
  };

  /// The nullable fields can be cleared by passing `null` explicitly.
  RecurringTask copyWith({
    String? listId,
    String? title,
    String? description,
    Object? assigneeId = _unset,
    String? rrule,
    DateTime? startDate,
    Object? endDate = _unset,
    TimeOfDay? createTime,
    Object? dueOffsetDays = _unset,
    Object? dueTime = _unset,
    bool? active,
  }) => RecurringTask(
    id: id,
    listId: listId ?? this.listId,
    title: title ?? this.title,
    description: description ?? this.description,
    assigneeId: identical(assigneeId, _unset)
        ? this.assigneeId
        : assigneeId as String?,
    rrule: rrule ?? this.rrule,
    startDate: startDate ?? this.startDate,
    endDate: identical(endDate, _unset) ? this.endDate : endDate as DateTime?,
    createTime: createTime ?? this.createTime,
    dueOffsetDays: identical(dueOffsetDays, _unset)
        ? this.dueOffsetDays
        : dueOffsetDays as int?,
    dueTime: identical(dueTime, _unset) ? this.dueTime : dueTime as TimeOfDay?,
    active: active ?? this.active,
    lastRunDate: lastRunDate,
  );

  /// The first occurrence on or after [from] (null when the series is over
  /// or has none within the search horizon).
  DateTime? nextOccurrence(DateTime from) {
    final r = Recurrence.parse(rrule);
    if (r == null) return null;
    final start = startDate.isAfter(from) ? startDate : from;
    return r
        .occurrences(startDate, from: start, end: endDate, count: 1)
        .firstOrNull;
  }
}

/// The recurring task templates (server: `/todo/recurring`, view
/// `todo.recurring`).
abstract interface class RecurringRepository {
  Stream<List<RecurringTask>> watch();

  Future<void> add(RecurringTask task);

  /// Sends only the fields that differ between [task] and [updated].
  Future<void> update(RecurringTask task, RecurringTask updated);
  Future<void> delete(RecurringTask task);

  /// The next [count] (≤ 20) occurrence dates of [rrule]; computed by the
  /// server, so it throws when offline.
  Future<List<DateTime>> preview({
    required String rrule,
    required DateTime startDate,
    DateTime? endDate,
    int count = 5,
  });
}

const _fields = [
  'list_id',
  'title',
  'description',
  'assignee_id',
  'rrule',
  'start_date',
  'end_date',
  'create_time',
  'due_offset_days',
  'due_time',
  'active',
];

List<RecurringTask> _sorted(Iterable<Map<String, dynamic>> docs) =>
    docs.map(RecurringTask.fromJson).toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

class ApiRecurringRepository implements RecurringRepository {
  ApiRecurringRepository(this.api, this.sync, this.outbox);
  final ApiClient api;
  final SyncClient sync;
  final Outbox outbox;

  @override
  Stream<List<RecurringTask>> watch() => sync
      .watch('todo.recurring', const {}, (e, _) => e == recurringEntity)
      .map((v) => _sorted(v.rows(recurringEntity)));

  @override
  Future<void> add(RecurringTask task) async => outbox.enqueue(
    Mutation.create(
      '/todo/recurring',
      recurringEntity,
      task.toJson(),
      body: {
        for (final e in task.toJson().entries)
          if (e.key != 'last_run_date') e.key: e.value,
      },
      label: task.title,
    ),
  );

  @override
  Future<void> update(RecurringTask task, RecurringTask updated) async {
    final fields = changedFields(task.toJson(), updated.toJson(), _fields);
    if (fields.isEmpty) return;
    outbox.enqueue(
      Mutation.patch(
        '/todo/recurring/${task.id}',
        recurringEntity,
        task.id,
        fields,
        label: updated.title,
      ),
    );
  }

  @override
  Future<void> delete(RecurringTask task) async => outbox.enqueue(
    Mutation.delete(
      '/todo/recurring/${task.id}',
      recurringEntity,
      task.id,
      label: task.title,
    ),
  );

  @override
  Future<List<DateTime>> preview({
    required String rrule,
    required DateTime startDate,
    DateTime? endDate,
    int count = 5,
  }) async {
    final res = await api.post('/todo/recurring/preview', {
      'rrule': rrule,
      'start_date': toApiDate(startDate),
      if (endDate != null) 'end_date': toApiDate(endDate),
      'count': count,
    }) as Map<String, dynamic>;
    return [for (final d in res['dates'] as List) fromApiDate(d)!];
  }
}

/// Stores the templates but never generates tasks (the server does that).
class MockRecurringRepository implements RecurringRepository {
  MockRecurringRepository(this.store, {required this.actorId});
  final MockStore store;
  final String actorId;

  @override
  Stream<List<RecurringTask>> watch() =>
      store.watch(recurringEntity).map(_sorted);

  @override
  Future<void> add(RecurringTask task) async {
    await store.put(recurringEntity, task.toJson(), actorId: actorId);
  }

  @override
  Future<void> update(RecurringTask task, RecurringTask updated) => store.patch(
    recurringEntity,
    task.id,
    changedFields(task.toJson(), updated.toJson(), _fields),
    actorId: actorId,
  );

  @override
  Future<void> delete(RecurringTask task) =>
      store.delete(recurringEntity, task.id, actorId: actorId);

  @override
  Future<List<DateTime>> preview({
    required String rrule,
    required DateTime startDate,
    DateTime? endDate,
    int count = 5,
  }) async =>
      Recurrence.parse(
        rrule,
      )?.occurrences(startDate, from: startDate, end: endDate, count: count) ??
      const [];
}

final recurringRepositoryProvider = Provider<RecurringRepository>(
  (ref) => switch (ref.watch(backendProvider)) {
    MockBackend(:final store) => MockRecurringRepository(
      store,
      actorId: ref.watch(currentMemberProvider),
    ),
    ApiBackend() => ApiRecurringRepository(
      ref.watch(apiClientProvider),
      ref.watch(syncClientProvider),
      ref.watch(outboxProvider)!,
    ),
  },
);

final recurringTasksProvider = StreamProvider<List<RecurringTask>>(
  (ref) => ref.watch(recurringRepositoryProvider).watch(),
);
