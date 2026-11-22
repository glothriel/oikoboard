import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/pkce.dart';
import '../../core/api/sync_client.dart';
import '../../core/backend.dart';
import '../../core/data.dart';
import '../../core/device_prefs.dart';
import '../../core/family.dart';
import '../../core/mock/mock_store.dart';
import '../../core/platform/browser.dart';
import '../../core/sync/outbox.dart';
import '../../core/undo_delete.dart';
import '../todo/repository.dart' as todo show itemsEntity, listsEntity;
import 'models.dart';

const eventsEntity = 'calendar_events';
const calendarsEntity = 'calendars';

typedef DateRange = ({DateTime from, DateTime to});

/// What a change to an occurrence of a series applies to.
enum EditScope {
  occurrence('this'),
  series('series');

  const EditScope(this.param);
  final String param;
}

abstract interface class CalendarRepository {
  /// Occurrences overlapping [from, to) — the `calendar.range` view.
  Stream<List<CalendarEvent>> watchRange(DateRange range);

  /// Calendars linked to the household — the `calendar.calendars` view.
  Stream<List<FamilyCalendar>> watchCalendars();

  Future<void> addEvent(CalendarEvent draft);

  /// Sends only the fields that differ between [event] and [updated].
  Future<void> updateEvent(
    CalendarEvent event,
    CalendarEvent updated, {
    EditScope scope = EditScope.occurrence,
  });
  Future<void> deleteEvent(
    CalendarEvent event, {
    EditScope scope = EditScope.occurrence,
  });

  /// Whether accounts can be connected (not in the in-memory mock).
  bool get canConnect;
  Future<List<CalendarConnection>> connections();

  /// Starts connecting an account. Completes with the connection id when the
  /// flow finishes in the app; on the web the page navigates away instead
  /// (see [completeConnect]).
  Future<String?> connect();

  /// Finishes a connect flow from the URL the browser came back to.
  Future<String> completeConnect(Uri url);
  Future<List<RemoteCalendar>> remoteCalendars(String connectionId);
  Future<void> link(String connectionId, String remoteId);
  Future<void> unlink(String calendarId);

  /// Due tasks go to this calendar from now on.
  Future<void> setTodoTarget(String calendarId);
  Future<void> disconnect(String connectionId);
  Future<void> syncNow(String calendarId);

  /// Events whose title, description or location contains [query]: a series
  /// once, as its next occurrence; upcoming first. Needs the server
  /// (`GET /calendar/search`).
  Future<List<CalendarEvent>> search(String query);
}

List<CalendarEvent> _sorted(Iterable<CalendarEvent> e) =>
    e.toList()..sort((a, b) => a.start.compareTo(b.start));

/// Web: the app URL the connect flow returns to is marked with this.
const calendarConnectParam = 'calendar_connect';

/// Why connecting a calendar account failed; the calendar screen shows it.
enum CalendarConnectFailure { cancelled, failed }

class CalendarConnectError implements Exception {
  const CalendarConnectError(this.failure);
  final CalendarConnectFailure failure;

  @override
  String toString() => 'CalendarConnectError(${failure.name})';
}

/// Event writes go through the [Outbox] (they work offline); managing
/// calendars and accounts needs the server and goes straight to the API.
class ApiCalendarRepository implements CalendarRepository {
  ApiCalendarRepository(this.api, this.sync, this.outbox);
  final ApiClient api;
  final SyncClient sync;
  final Outbox outbox;

  static const _verifierKey = 'oiko.calendar_pkce';

  @override
  Stream<List<CalendarEvent>> watchRange(DateRange r) => sync
      .watch(
        'calendar.range',
        {'from': toApiTime(r.from), 'to': toApiTime(r.to)},
        (e, row) =>
            e == eventsEntity &&
            CalendarEvent.fromJson(row).overlaps(r.from, r.to),
      )
      .map((v) => _sorted(v.rows(eventsEntity).map(CalendarEvent.fromJson)));

  @override
  Stream<List<FamilyCalendar>> watchCalendars() => sync
      .watch('calendar.calendars', {})
      .map(
        (v) =>
            v.rows(calendarsEntity).map(FamilyCalendar.fromJson).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  static const _eventFields = [
    'title',
    'description',
    'location',
    'starts_at',
    'ends_at',
    'all_day',
    'member_ids',
    'recurrence',
  ];

  @override
  Future<void> addEvent(CalendarEvent draft) async {
    final body = draft.toJson()
      ..remove('event_id')
      ..remove('original_start')
      ..remove('kind');
    // Shown under the id the server will give it, so it can be changed or
    // deleted before the server confirms it.
    final row = draft.toJson()..addAll(mirroredIds(draft));
    outbox.enqueue(
      Mutation.create(
        '/calendar/events',
        eventsEntity,
        row,
        body: body,
        label: draft.title,
      ),
    );
  }

  @override
  Future<void> updateEvent(
    CalendarEvent e,
    CalendarEvent updated, {
    EditScope scope = EditScope.occurrence,
  }) async {
    final fields = changedFields(e.toJson(), updated.toJson(), _eventFields);
    // Recurrence belongs to the series; an occurrence can't change it.
    if (e.originalStart != null && scope == EditScope.occurrence) {
      fields.remove('recurrence');
    }
    if (fields.isEmpty) return;
    outbox.enqueue(
      Mutation.patch(
        '/calendar/events/${e.id}?scope=${scope.param}',
        eventsEntity,
        e.id,
        fields,
        label: updated.title,
      ),
    );
  }

  @override
  Future<void> deleteEvent(
    CalendarEvent e, {
    EditScope scope = EditScope.occurrence,
  }) async => outbox.enqueue(
    Mutation.delete(
      '/calendar/events/${e.id}?scope=${scope.param}',
      eventsEntity,
      e.id,
      label: e.title,
    ),
  );

  @override
  bool get canConnect => true;

  @override
  Future<List<CalendarConnection>> connections() async => [
    for (final j in (await api.get(
      '/calendar/connections',
    ) as List).cast<Map<String, dynamic>>())
      CalendarConnection.fromJson(j),
  ];

  @override
  Future<String?> connect() async {
    final verifier = pkceVerifier();
    final returnTo = kIsWeb
        ? Uri.parse(webAppUrl)
              .replace(queryParameters: {calendarConnectParam: '1'})
              .toString()
        : 'oikoboard://auth';
    final res = await api.post('/calendar/connections', {
      'return': returnTo,
      'challenge': pkceChallenge(verifier),
    }) as Map;
    final url = api.baseUri.resolve(res['url'] as String).toString();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_verifierKey, verifier);
      redirectTo(url);
      return Completer<String?>().future; // the page navigates away
    }
    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: 'oikoboard',
      );
    } catch (_) {
      return null; // closed
    }
    return _complete(Uri.parse(result), verifier);
  }

  @override
  Future<String> completeConnect(Uri url) async {
    final prefs = await SharedPreferences.getInstance();
    final verifier = prefs.getString(_verifierKey) ?? '';
    await prefs.remove(_verifierKey);
    return _complete(url, verifier);
  }

  Future<String> _complete(Uri url, String verifier) async {
    final q = url.queryParameters;
    if (q['error'] != null) {
      throw CalendarConnectError(
        q['error'] == 'access_denied'
            ? CalendarConnectFailure.cancelled
            : CalendarConnectFailure.failed,
      );
    }
    final res = await api.post('/calendar/connections/complete', {
      'code': q['code'],
      'verifier': verifier,
    }) as Map;
    return res['id'] as String;
  }

  @override
  Future<List<RemoteCalendar>> remoteCalendars(String connectionId) async => [
    for (final j in (await api.get(
      '/calendar/connections/$connectionId/calendars',
    ) as List).cast<Map<String, dynamic>>())
      RemoteCalendar.fromJson(j),
  ];

  @override
  Future<void> link(String connectionId, String remoteId) => api.post(
    '/calendars',
    {'connection_id': connectionId, 'remote_id': remoteId},
  );

  @override
  Future<void> unlink(String calendarId) =>
      api.delete('/calendars/$calendarId');

  @override
  Future<void> setTodoTarget(String calendarId) =>
      api.patch('/calendars/$calendarId', {'todo_target': true});

  @override
  Future<void> disconnect(String connectionId) =>
      api.delete('/calendar/connections/$connectionId');

  @override
  Future<void> syncNow(String calendarId) =>
      api.post('/calendars/$calendarId/sync', {});

  @override
  Future<List<CalendarEvent>> search(String query) async {
    final res = await api.get(
      '/calendar/search?q=${Uri.encodeQueryComponent(query)}',
      report: false,
    ) as Map<String, dynamic>;
    return (res['events'] as List)
        .cast<Map<String, dynamic>>()
        .map(CalendarEvent.fromJson)
        .toList();
  }
}

/// What `GET /calendar/search` returns, over [events] held in memory.
List<CalendarEvent> searchEvents(Iterable<CalendarEvent> events, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final now = DateTime.now();
  bool upcoming(CalendarEvent e) => !e.end.isBefore(now);
  // Upcoming soonest first, then past latest first.
  int order(CalendarEvent a, CalendarEvent b) {
    if (upcoming(a) != upcoming(b)) return upcoming(a) ? -1 : 1;
    return upcoming(a)
        ? a.start.compareTo(b.start)
        : b.start.compareTo(a.start);
  }

  final best = <String, CalendarEvent>{};
  for (final e in events) {
    if (e.kind.isNotEmpty) continue;
    if (![
      e.title,
      e.description,
      e.location,
    ].any((s) => s.toLowerCase().contains(q))) {
      continue;
    }
    final key = e.eventId ?? e.id;
    final prev = best[key];
    if (prev == null || order(e, prev) < 0) best[key] = e;
  }
  return best.values.toList()..sort(order);
}

/// Namespace of the server's mirror ids (calendar/mirror.go `idSpace`).
const _idSpace = '6f0c5f5e-3c39-4a0e-9a3b-0b1c2d3e4f50';

/// The ids the server gives a new event created with the client id
/// `draft.id` (calendar/mirror.go): the event is `uuidv5(calendar/remoteId)`,
/// the remote id being the client id without dashes; an occurrence of a
/// series is `uuidv5(event@start)`. Returns `id`, `event_id` and
/// `original_start` of the event's first occurrence.
Map<String, dynamic> mirroredIds(CalendarEvent draft) {
  final remoteId = draft.id.replaceAll('-', '').toLowerCase();
  final eventId = uuid.v5(_idSpace, '${draft.calendarId}/$remoteId');
  if (!draft.recurring) {
    return {'id': eventId, 'event_id': eventId, 'original_start': null};
  }
  final start = draft.allDay
      ? DateTime.utc(draft.start.year, draft.start.month, draft.start.day)
      : draft.start.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final rfc3339 =
      '${start.year.toString().padLeft(4, '0')}-${two(start.month)}-'
      '${two(start.day)}T${two(start.hour)}:${two(start.minute)}:'
      '${two(start.second)}Z';
  return {
    'id': uuid.v5(_idSpace, '$eventId@$rfc3339'),
    'event_id': eventId,
    'original_start': start.toIso8601String(),
  };
}

/// In-memory mock: calendars are fixed, recurring events show only their
/// first occurrence. Due-task days are derived from the mock tasks the way
/// the server derives them.
class MockCalendarRepository implements CalendarRepository {
  MockCalendarRepository(this.store, {required this.actorId});

  final MockStore store;
  final String actorId;

  @override
  Stream<List<CalendarEvent>> watchRange(DateRange r) {
    List<CalendarEvent> current() => _sorted(
      [
        ...store.list(eventsEntity).map(CalendarEvent.fromJson),
        ..._todoDays(),
      ].where((e) => e.overlaps(r.from, r.to)),
    );
    late final StreamController<List<CalendarEvent>> ctrl;
    StreamSubscription<Object>? sub;
    ctrl = StreamController(
      onListen: () {
        ctrl.add(current());
        sub = store.changes
            .where(
              (c) => const {
                eventsEntity,
                calendarsEntity,
                todo.itemsEntity,
                todo.listsEntity,
              }.contains(c.collection),
            )
            .listen((_) => ctrl.add(current()));
      },
      onCancel: () => sub?.cancel(),
    );
    return ctrl.stream;
  }

  /// What the server's due-task reconciliation would put into the target
  /// calendar: one all-day event per day with open tasks (or lists) due, and
  /// a 15-minute event per open task due at a time.
  List<CalendarEvent> _todoDays() {
    final target = store
        .list(calendarsEntity)
        .where((c) => c['todo_target'] == true)
        .firstOrNull;
    if (target == null) return const [];
    final items = store.list(todo.itemsEntity);
    final byDay = <DateTime, List<({String title, String? assignee})>>{};
    for (final l in store.list(todo.listsEntity)) {
      final due = fromApiDate(l['due']);
      final own = items.where((t) => t['list_id'] == l['id']);
      if (due == null ||
          (own.isNotEmpty && own.every((t) => t['done'] == true))) {
        continue;
      }
      (byDay[due] ??= []).add((title: 'Lista: ${l['name']}', assignee: null));
    }
    final timed = <CalendarEvent>[];
    for (final t in items) {
      final due = fromApiDate(t['due']);
      if (due == null || t['done'] == true) continue;
      final time = fromApiClock(t['due_time']);
      if (time != null) {
        final start = due.add(Duration(hours: time.hour, minutes: time.minute));
        timed.add(
          CalendarEvent(
            id: 'todo-task-${t['id']}',
            calendarId: target['id'] as String,
            title: 'Zadanie: ${t['title']}',
            description: t['description'] as String? ?? '',
            start: start,
            end: start.add(const Duration(minutes: 15)),
            allDay: false,
            memberIds: [?t['assignee_id'] as String?],
            kind: CalendarEvent.todoTaskKind,
          ),
        );
        continue;
      }
      (byDay[due] ??= []).add((
        title: 'Zadanie: ${t['title']}',
        assignee: t['assignee_id'] as String?,
      ));
    }
    return [
      for (final MapEntry(key: day, value: entries) in byDay.entries)
        CalendarEvent(
          id: 'todo-day-${toApiDate(day)}',
          calendarId: target['id'] as String,
          title: entries.length == 1
              ? entries.single.title
              : 'Zadania: ${entries.length}',
          start: day,
          end: DateTime(day.year, day.month, day.day + 1),
          allDay: true,
          memberIds: {
            for (final e in entries)
              if (e.assignee != null) e.assignee!,
          }.toList(),
          kind: CalendarEvent.todoDayKind,
        ),
      ...timed,
    ];
  }

  @override
  Stream<List<FamilyCalendar>> watchCalendars() => store
      .watch(calendarsEntity)
      .map((docs) => docs.map(FamilyCalendar.fromJson).toList());

  @override
  Future<void> addEvent(CalendarEvent draft) =>
      store.put(eventsEntity, draft.toJson(), actorId: actorId);

  @override
  Future<void> updateEvent(
    CalendarEvent event,
    CalendarEvent updated, {
    EditScope scope = EditScope.occurrence,
  }) => store.patch(
    eventsEntity,
    event.id,
    changedFields(event.toJson(), updated.toJson(), const [
      'title',
      'description',
      'location',
      'starts_at',
      'ends_at',
      'all_day',
      'member_ids',
      'recurrence',
    ]),
    actorId: actorId,
  );

  @override
  Future<void> deleteEvent(
    CalendarEvent event, {
    EditScope scope = EditScope.occurrence,
  }) => store.delete(eventsEntity, event.id, actorId: actorId);

  @override
  bool get canConnect => false;

  Never _unsupported() =>
      throw UnsupportedError('not available in mock mode without a server');

  @override
  Future<List<CalendarConnection>> connections() async => const [];
  @override
  Future<String?> connect() => _unsupported();
  @override
  Future<String> completeConnect(Uri url) => _unsupported();
  @override
  Future<List<RemoteCalendar>> remoteCalendars(String connectionId) =>
      _unsupported();
  @override
  Future<void> link(String connectionId, String remoteId) => _unsupported();
  @override
  Future<void> unlink(String calendarId) =>
      store.delete(calendarsEntity, calendarId, actorId: actorId);
  @override
  Future<void> setTodoTarget(String calendarId) async {
    for (final c in store.list(calendarsEntity)) {
      final target = c['id'] == calendarId;
      if (c['todo_target'] != target) {
        await store.put(calendarsEntity, {
          ...c,
          'todo_target': target,
        }, actorId: actorId);
      }
    }
  }

  @override
  Future<void> disconnect(String connectionId) => _unsupported();
  @override
  Future<void> syncNow(String calendarId) async {}

  @override
  Future<List<CalendarEvent>> search(String query) async =>
      searchEvents(store.list(eventsEntity).map(CalendarEvent.fromJson), query);
}

final calendarRepositoryProvider = Provider<CalendarRepository>(
  (ref) => switch (ref.watch(backendProvider)) {
    MockBackend(:final store) => MockCalendarRepository(
      store,
      actorId: ref.watch(currentMemberProvider),
    ),
    ApiBackend() => ApiCalendarRepository(
      ref.watch(apiClientProvider),
      ref.watch(syncClientProvider),
      ref.watch(outboxProvider)!,
    ),
  },
);

/// A request to show a day on the calendar screen (e.g. from search). A new
/// object each time, so asking for the same day again is a change too.
class CalendarFocus {
  CalendarFocus(this.day);
  final DateTime day;
}

class CalendarFocusNotifier extends Notifier<CalendarFocus?> {
  @override
  CalendarFocus? build() => null;

  void show(DateTime day) => state = CalendarFocus(day);
}

final calendarFocusProvider =
    NotifierProvider<CalendarFocusNotifier, CalendarFocus?>(
      CalendarFocusNotifier.new,
    );

/// Key for [deleteWithUndo]: an occurrence (or single event) or a whole series.
String calendarEventKey(CalendarEvent e, EditScope scope) =>
    scope == EditScope.series && e.eventId != null
    ? 'calendar_series:${e.eventId}'
    : 'calendar_events:${e.id}';

final _calendarRange = StreamProvider.autoDispose
    .family<List<CalendarEvent>, DateRange>(
      (ref, range) => ref.watch(calendarRepositoryProvider).watchRange(range),
    );

/// The events in a range, without those being deleted with Undo.
final calendarRangeProvider = Provider.autoDispose
    .family<AsyncValue<List<CalendarEvent>>, DateRange>((ref, range) {
      final pending = ref.watch(pendingDeletesProvider);
      return ref
          .watch(_calendarRange(range))
          .whenData(
            (events) => pending.isEmpty
                ? events
                : events
                      .where(
                        (e) =>
                            !pending.contains(
                              calendarEventKey(e, EditScope.occurrence),
                            ) &&
                            !pending.contains(
                              calendarEventKey(e, EditScope.series),
                            ),
                      )
                      .toList(),
          );
    });

final calendarsProvider = StreamProvider.autoDispose<List<FamilyCalendar>>(
  (ref) => ref.watch(calendarRepositoryProvider).watchCalendars(),
);

/// Web: the URL of a finished connect flow, kept until the user is signed in
/// (main.dart) and then completed by the calendar screen.
class PendingCalendarConnect extends Notifier<Uri?> {
  @override
  Uri? build() => null;
  void set(Uri? url) => state = url;
}

final pendingCalendarConnectProvider =
    NotifierProvider<PendingCalendarConnect, Uri?>(PendingCalendarConnect.new);

/// The view the calendar opens with, remembered on this device.
class CalendarViewPreference extends AsyncNotifier<CalendarView> {
  static const key = 'oiko.calendar_view';

  @override
  Future<CalendarView> build() async =>
      CalendarView.parse(await DevicePrefs.get(key));

  Future<void> set(CalendarView view) async {
    state = AsyncData(view);
    await DevicePrefs.set(key, view.param);
  }
}

final calendarViewProvider =
    AsyncNotifierProvider<CalendarViewPreference, CalendarView>(
      CalendarViewPreference.new,
    );
