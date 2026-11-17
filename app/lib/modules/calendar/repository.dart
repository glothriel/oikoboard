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
import '../../core/family.dart';
import '../../core/mock/mock_store.dart';
import '../../core/platform/browser.dart';
import '../todo/repository.dart' as todo show itemsEntity;
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
  Future<void> updateEvent(
    CalendarEvent event, {
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

  /// The signed-in member's preferred view (follows them across devices).
  Future<CalendarView> preferredView();
  Future<void> setPreferredView(CalendarView view);
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

class ApiCalendarRepository implements CalendarRepository {
  ApiCalendarRepository(this.api, this.sync);
  final ApiClient api;
  final SyncClient sync;

  static const _verifierKey = 'oiko.calendar_pkce';

  @override
  Stream<List<CalendarEvent>> watchRange(DateRange r) => sync
      .watch('calendar.range', {
        'from': toApiTime(r.from),
        'to': toApiTime(r.to),
      })
      .map((v) => _sorted(v.rows(eventsEntity).map(CalendarEvent.fromJson)));

  @override
  Stream<List<FamilyCalendar>> watchCalendars() => sync
      .watch('calendar.calendars', {})
      .map(
        (v) =>
            v.rows(calendarsEntity).map(FamilyCalendar.fromJson).toList()
              ..sort((a, b) => a.name.compareTo(b.name)),
      );

  @override
  Future<void> addEvent(CalendarEvent draft) {
    final body = draft.toJson()
      ..remove('event_id')
      ..remove('original_start')
      ..remove('kind');
    return api.post('/calendar/events', body);
  }

  @override
  Future<void> updateEvent(
    CalendarEvent e, {
    EditScope scope = EditScope.occurrence,
  }) {
    final body = e.toJson()
      ..remove('id')
      ..remove('calendar_id')
      ..remove('event_id')
      ..remove('original_start')
      ..remove('kind');
    // Recurrence belongs to the series; an occurrence can't change it.
    if (e.originalStart != null && scope == EditScope.occurrence) {
      body.remove('recurrence');
    }
    return api.patch('/calendar/events/${e.id}?scope=${scope.param}', body);
  }

  @override
  Future<void> deleteEvent(
    CalendarEvent e, {
    EditScope scope = EditScope.occurrence,
  }) => api.delete('/calendar/events/${e.id}?scope=${scope.param}');

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
  Future<CalendarView> preferredView() async => CalendarView.parse(
    (await api.get('/calendar/preferences') as Map)['view'],
  );

  @override
  Future<void> setPreferredView(CalendarView view) =>
      api.patch('/calendar/preferences', {'view': view.param});
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
              }.contains(c.collection),
            )
            .listen((_) => ctrl.add(current()));
      },
      onCancel: () => sub?.cancel(),
    );
    return ctrl.stream;
  }

  /// What the server's due-task reconciliation would put into the target
  /// calendar: one all-day event per day with open tasks due.
  List<CalendarEvent> _todoDays() {
    final target = store
        .list(calendarsEntity)
        .where((c) => c['todo_target'] == true)
        .firstOrNull;
    if (target == null) return const [];
    final byDay = <DateTime, List<Map<String, dynamic>>>{};
    for (final t in store.list(todo.itemsEntity)) {
      final due = fromApiDate(t['due']);
      if (due == null || t['done'] == true) continue;
      (byDay[due] ??= []).add(t);
    }
    return [
      for (final MapEntry(key: day, value: tasks) in byDay.entries)
        CalendarEvent(
          id: 'todo-day-${toApiDate(day)}',
          calendarId: target['id'] as String,
          title: tasks.length == 1
              ? 'Zadanie: ${tasks.single['title']}'
              : 'Zadania: ${tasks.length}',
          start: day,
          end: DateTime(day.year, day.month, day.day + 1),
          allDay: true,
          memberIds: {
            for (final t in tasks)
              if (t['assignee_id'] != null) t['assignee_id'] as String,
          }.toList(),
          kind: CalendarEvent.todoDayKind,
        ),
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
    CalendarEvent event, {
    EditScope scope = EditScope.occurrence,
  }) => store.put(eventsEntity, event.toJson(), actorId: actorId);

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

  /// Per member, for the app's lifetime.
  static final _views = <String, CalendarView>{};

  @override
  Future<CalendarView> preferredView() async =>
      _views[actorId] ?? CalendarView.month;

  @override
  Future<void> setPreferredView(CalendarView view) async =>
      _views[actorId] = view;
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
    ),
  },
);

final calendarRangeProvider = StreamProvider.autoDispose
    .family<List<CalendarEvent>, DateRange>(
      (ref, range) => ref.watch(calendarRepositoryProvider).watchRange(range),
    );

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

/// The view the calendar opens with; changing it saves the preference.
class CalendarViewPreference extends AsyncNotifier<CalendarView> {
  @override
  Future<CalendarView> build() async {
    try {
      return await ref.watch(calendarRepositoryProvider).preferredView();
    } catch (_) {
      return CalendarView.month;
    }
  }

  Future<void> set(CalendarView view) async {
    state = AsyncData(view);
    await ref.read(calendarRepositoryProvider).setPreferredView(view);
  }
}

final calendarViewProvider =
    AsyncNotifierProvider<CalendarViewPreference, CalendarView>(
      CalendarViewPreference.new,
    );
