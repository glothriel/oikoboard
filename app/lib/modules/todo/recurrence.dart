import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

enum RepeatUnit { day, week, month, year }

const _dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// The schedules the editor can build: `FREQ` DAILY..YEARLY with `INTERVAL`
/// and, per unit, `BYDAY` (weekly), `BYMONTHDAY` (monthly, yearly; -1 is the
/// last day) and `BYMONTH` (yearly). It is the subset of RFC 5545 the server
/// accepts that the form can round-trip; [parse] returns null for any other
/// rule, which the UI then shows read-only.
class Recurrence {
  const Recurrence({
    required this.unit,
    this.interval = 1,
    this.weekdays = const {},
    this.monthDay,
    this.month,
  });

  final RepeatUnit unit;

  /// Every [interval] days/weeks/months/years; at least 1.
  final int interval;

  /// [DateTime.monday]..[DateTime.sunday]; weekly only. Empty = the start
  /// date's weekday.
  final Set<int> weekdays;

  /// 1..31, or -1 for the last day of the month; monthly and yearly. Null =
  /// the start date's day.
  final int? monthDay;

  /// 1..12; yearly. Null = the start date's month.
  final int? month;

  bool get lastDay => monthDay == -1;

  /// A rule for [unit] anchored on [start]: weekly on its weekday, monthly
  /// on its day, yearly on its date.
  factory Recurrence.starting(RepeatUnit unit, DateTime start) => Recurrence(
    unit: unit,
    weekdays: unit == RepeatUnit.week ? {start.weekday} : const {},
    monthDay: switch (unit) {
      RepeatUnit.month || RepeatUnit.year => start.day,
      _ => null,
    },
    month: unit == RepeatUnit.year ? start.month : null,
  );

  /// The same rule with the defaults that come from [start] filled in.
  Recurrence anchored(DateTime start) {
    final base = Recurrence.starting(unit, start);
    return Recurrence(
      unit: unit,
      interval: interval,
      weekdays: weekdays.isEmpty ? base.weekdays : weekdays,
      monthDay: monthDay ?? base.monthDay,
      month: month ?? base.month,
    );
  }

  Recurrence copyWith({
    RepeatUnit? unit,
    int? interval,
    Set<int>? weekdays,
    int? monthDay,
    int? month,
  }) => Recurrence(
    unit: unit ?? this.unit,
    interval: interval ?? this.interval,
    weekdays: weekdays ?? this.weekdays,
    monthDay: monthDay ?? this.monthDay,
    month: month ?? this.month,
  );

  /// The RRULE string (no DTSTART, COUNT or UNTIL).
  String toRrule() {
    final parts = [
      'FREQ=${switch (unit) {
        RepeatUnit.day => 'DAILY',
        RepeatUnit.week => 'WEEKLY',
        RepeatUnit.month => 'MONTHLY',
        RepeatUnit.year => 'YEARLY',
      }}',
      if (interval > 1) 'INTERVAL=$interval',
      if (unit == RepeatUnit.week && weekdays.isNotEmpty)
        'BYDAY=${(weekdays.toList()..sort()).map((d) => _dayCodes[d - 1]).join(',')}',
      if ((unit == RepeatUnit.month || unit == RepeatUnit.year) &&
          monthDay != null)
        'BYMONTHDAY=$monthDay',
      if (unit == RepeatUnit.year && month != null) 'BYMONTH=$month',
    ];
    return parts.join(';');
  }

  /// Null when [rrule] is outside what the editor can build.
  static Recurrence? parse(String rrule) {
    final kv = <String, String>{};
    for (final part in rrule.split(';')) {
      final i = part.indexOf('=');
      if (i <= 0) return null;
      if (kv.containsKey(part.substring(0, i))) return null;
      kv[part.substring(0, i).toUpperCase()] = part.substring(i + 1);
    }
    final unit = switch (kv['FREQ']) {
      'DAILY' => RepeatUnit.day,
      'WEEKLY' => RepeatUnit.week,
      'MONTHLY' => RepeatUnit.month,
      'YEARLY' => RepeatUnit.year,
      _ => null,
    };
    if (unit == null) return null;
    final allowed = {
      'FREQ',
      'INTERVAL',
      if (unit == RepeatUnit.week) 'BYDAY',
      if (unit == RepeatUnit.month || unit == RepeatUnit.year) 'BYMONTHDAY',
      if (unit == RepeatUnit.year) 'BYMONTH',
    };
    if (!kv.keys.every(allowed.contains)) return null;
    final interval = int.tryParse(kv['INTERVAL'] ?? '1');
    if (interval == null || interval < 1) return null;
    final weekdays = <int>{};
    for (final c in (kv['BYDAY'] ?? '').split(',').where((c) => c.isNotEmpty)) {
      final i = _dayCodes.indexOf(c.toUpperCase());
      if (i < 0) return null;
      weekdays.add(i + 1);
    }
    if (kv.containsKey('BYDAY') && weekdays.isEmpty) return null;
    int? monthDay;
    if (kv['BYMONTHDAY'] case final v?) {
      monthDay = int.tryParse(v);
      if (monthDay == null ||
          monthDay == 0 ||
          monthDay > 31 ||
          (monthDay < 0 && monthDay != -1)) {
        return null;
      }
    }
    int? month;
    if (kv['BYMONTH'] case final v?) {
      month = int.tryParse(v);
      if (month == null || month < 1 || month > 12) return null;
    }
    return Recurrence(
      unit: unit,
      interval: interval,
      weekdays: weekdays,
      monthDay: monthDay,
      month: month,
    );
  }

  bool _matches(DateTime start, DateTime d) {
    final s = DateTime.utc(start.year, start.month, start.day);
    final u = DateTime.utc(d.year, d.month, d.day);
    switch (unit) {
      case RepeatUnit.day:
        return u.difference(s).inDays % interval == 0;
      case RepeatUnit.week:
        final weeks =
            u
                .subtract(Duration(days: u.weekday - 1))
                .difference(s.subtract(Duration(days: s.weekday - 1)))
                .inDays ~/
            7;
        return weeks % interval == 0 &&
            (weekdays.isEmpty ? {start.weekday} : weekdays).contains(d.weekday);
      case RepeatUnit.month:
        return ((d.year - start.year) * 12 + d.month - start.month) %
                    interval ==
                0 &&
            _dayMatches(start, d);
      case RepeatUnit.year:
        return (d.year - start.year) % interval == 0 &&
            d.month == (month ?? start.month) &&
            _dayMatches(start, d);
    }
  }

  bool _dayMatches(DateTime start, DateTime d) {
    final want = monthDay ?? start.day;
    return want == -1
        ? d.day == DateTime(d.year, d.month + 1, 0).day
        : d.day == want;
  }

  /// Up to [count] dates (local midnight) of the series that starts on
  /// [start], from [from] on and not after [end]. Like the server's, for
  /// the mock and tests; looks 10 years ahead at most.
  List<DateTime> occurrences(
    DateTime start, {
    required DateTime from,
    DateTime? end,
    int count = 5,
  }) {
    final first = from.isBefore(start) ? start : from;
    final out = <DateTime>[];
    var d = DateTime(first.year, first.month, first.day);
    final horizon = DateTime(d.year + 10, d.month, d.day);
    while (out.length < count && d.isBefore(horizon)) {
      if (end != null && d.isAfter(end)) break;
      if (_matches(start, d)) out.add(d);
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return out;
  }

  /// “Every 2 weeks on Mon, Fri”, from l10n ICU strings.
  String summary(AppLocalizations l, String locale) {
    final n = interval;
    switch (unit) {
      case RepeatUnit.day:
        return l.recurDaily(n);
      case RepeatUnit.week:
        final days = (weekdays.toList()..sort())
            .map((d) => DateFormat.E(locale).format(DateTime(2024, 1, d)))
            .join(', ');
        return l.recurWeekly(n, days);
      case RepeatUnit.month:
        return lastDay
            ? l.recurMonthlyLast(n)
            : l.recurMonthlyDay(n, monthDay ?? 1);
      case RepeatUnit.year:
        final date = DateFormat.MMMMd(locale)
            .format(DateTime(2024, month ?? 1, lastDay ? 1 : monthDay ?? 1));
        return l.recurYearly(n, date);
    }
  }
}
