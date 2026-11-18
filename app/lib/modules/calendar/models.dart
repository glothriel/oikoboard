import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart' show fromApiTime, toApiTime;

/// How the calendar screen shows time.
enum CalendarView {
  day('day', 1),
  threeDays('3days', 3),
  week('week', 7),
  month('month', 0);

  const CalendarView(this.param, this.days);

  /// Stored name (device preferences).
  final String param;

  /// Days shown side by side; 0 for the month grid.
  final int days;

  static CalendarView parse(Object? s) =>
      values.where((v) => v.param == s).firstOrNull ?? month;
}

/// One occurrence: a single event, or one instance of a recurring series.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.memberIds,
    this.eventId,
    this.description = '',
    this.location = '',
    this.recurrence = const [],
    this.originalStart,
    this.kind = '',
  });

  /// [kind] of the event the server keeps for a day's due tasks.
  static const todoDayKind = 'todo-day';

  final String id;
  final String calendarId;

  /// The series (or the single event) this occurrence belongs to.
  final String? eventId;
  final String title;
  final String description;
  final String location;
  final DateTime start;

  /// Exclusive end. All-day events: local midnight after the last day.
  final DateTime end;
  final bool allDay;
  final List<String> memberIds;

  /// RRULE/EXDATE lines of the series; empty for single events.
  final List<String> recurrence;

  /// Set for occurrences of a series.
  final DateTime? originalStart;

  /// Events managed by Oikoboard itself (e.g. [todoDayKind]); empty for
  /// ordinary ones. They can't be edited as events.
  final String kind;

  bool get recurring => recurrence.isNotEmpty;
  bool get isTodoDay => kind == todoDayKind;

  bool occursOn(DateTime day) => overlaps(
    DateTime(day.year, day.month, day.day),
    DateTime(day.year, day.month, day.day + 1),
  );

  /// Same rule as the server's `calendar.range` view.
  bool overlaps(DateTime from, DateTime to) =>
      start.isBefore(to) && (end.isAfter(from) || start == from);

  /// All-day dates travel as UTC midnight and are shown as local dates.
  static DateTime _date(Object? s) {
    final u = DateTime.parse(s as String).toUtc();
    return DateTime(u.year, u.month, u.day);
  }

  static String _dateToApi(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day).toIso8601String();

  factory CalendarEvent.fromJson(Map<String, dynamic> j) {
    final allDay = j['all_day'] as bool? ?? false;
    return CalendarEvent(
      id: j['id'] as String,
      calendarId: j['calendar_id'] as String? ?? '',
      eventId: j['event_id'] as String?,
      title: j['title'] as String,
      description: j['description'] as String? ?? '',
      location: j['location'] as String? ?? '',
      start: allDay ? _date(j['starts_at']) : fromApiTime(j['starts_at'])!,
      end: allDay ? _date(j['ends_at']) : fromApiTime(j['ends_at'])!,
      allDay: allDay,
      memberIds: (j['member_ids'] as List?)?.cast<String>() ?? const [],
      recurrence: (j['recurrence'] as List?)?.cast<String>() ?? const [],
      originalStart: fromApiTime(j['original_start']),
      kind: j['kind'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'calendar_id': calendarId,
    'event_id': eventId,
    'title': title,
    'description': description,
    'location': location,
    'starts_at': allDay ? _dateToApi(start) : toApiTime(start),
    'ends_at': allDay ? _dateToApi(end) : toApiTime(end),
    'all_day': allDay,
    'member_ids': memberIds,
    'recurrence': recurrence,
    'original_start': toApiTime(originalStart),
    'kind': kind,
  };

  CalendarEvent copyWith({
    String? calendarId,
    String? title,
    String? description,
    String? location,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    List<String>? memberIds,
    List<String>? recurrence,
  }) => CalendarEvent(
    id: id,
    calendarId: calendarId ?? this.calendarId,
    eventId: eventId,
    title: title ?? this.title,
    description: description ?? this.description,
    location: location ?? this.location,
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    memberIds: memberIds ?? this.memberIds,
    recurrence: recurrence ?? this.recurrence,
    originalStart: originalStart,
    kind: kind,
  );
}

/// An external calendar linked to the household.
class FamilyCalendar {
  const FamilyCalendar({
    required this.id,
    required this.name,
    required this.color,
    required this.writable,
    this.connectionId = '',
    this.remoteId = '',
    this.account = '',
    this.syncError = '',
    this.todoTarget = false,
  });

  final String id;
  final String name;
  final Color color;
  final bool writable;

  /// Due tasks are shown in this calendar (one per family).
  final bool todoTarget;
  final String connectionId;
  final String remoteId;
  final String account;
  final String syncError;

  factory FamilyCalendar.fromJson(Map<String, dynamic> j) => FamilyCalendar(
    id: j['id'] as String,
    name: j['name'] as String,
    color: Color(j['color'] as int),
    writable: j['writable'] as bool? ?? true,
    connectionId: j['connection_id'] as String? ?? '',
    remoteId: j['remote_id'] as String? ?? '',
    account: j['account'] as String? ?? '',
    syncError: j['sync_error'] as String? ?? '',
    todoTarget: j['todo_target'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
    'writable': writable,
    'connection_id': connectionId,
    'remote_id': remoteId,
    'account': account,
    'sync_error': syncError,
    'todo_target': todoTarget,
  };
}

/// A connected provider account (e.g. a Google account) of the signed-in user.
class CalendarConnection {
  const CalendarConnection(this.id, this.provider, this.account, this.status);
  final String id;
  final String provider;
  final String account;
  final String status;

  bool get revoked => status == 'revoked';

  factory CalendarConnection.fromJson(Map<String, dynamic> j) =>
      CalendarConnection(
        j['id'] as String,
        j['provider'] as String,
        j['account'] as String? ?? '',
        j['status'] as String? ?? 'ok',
      );
}

/// A calendar available in a connected account.
class RemoteCalendar {
  const RemoteCalendar(
    this.remoteId,
    this.name,
    this.color,
    this.writable,
    this.linked,
  );
  final String remoteId;
  final String name;
  final Color color;
  final bool writable;
  final bool linked;

  factory RemoteCalendar.fromJson(Map<String, dynamic> j) => RemoteCalendar(
    j['remote_id'] as String,
    j['name'] as String,
    Color(j['color'] as int),
    j['writable'] as bool? ?? true,
    j['linked'] as bool? ?? false,
  );
}

/// Simple repeat choices offered in the editor (anything else is kept as-is).
enum Repeat {
  none(null),
  daily('RRULE:FREQ=DAILY'),
  weekdays('RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR'),
  weekly('RRULE:FREQ=WEEKLY'),
  monthly('RRULE:FREQ=MONTHLY'),
  yearly('RRULE:FREQ=YEARLY'),
  custom(null);

  const Repeat(this.rule);
  final String? rule;

  static Repeat of(List<String> recurrence) {
    if (recurrence.isEmpty) return Repeat.none;
    if (recurrence.length == 1) {
      for (final r in values) {
        if (r.rule == recurrence.first) return r;
      }
    }
    return Repeat.custom;
  }
}
