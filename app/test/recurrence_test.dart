import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:oikoboard/l10n/app_localizations.dart';
import 'package:oikoboard/modules/todo/recurrence.dart';

String _d(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('pl');
  });

  group('toRrule / parse', () {
    test('presets', () {
      final mon = DateTime(2026, 11, 23); // a Monday
      expect(Recurrence.starting(RepeatUnit.day, mon).toRrule(), 'FREQ=DAILY');
      expect(
        Recurrence.starting(RepeatUnit.week, mon).toRrule(),
        'FREQ=WEEKLY;BYDAY=MO',
      );
      expect(
        const Recurrence(
          unit: RepeatUnit.week,
          interval: 2,
          weekdays: {5, 1},
        ).toRrule(),
        'FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR',
      );
      expect(
        Recurrence.starting(RepeatUnit.month, mon).toRrule(),
        'FREQ=MONTHLY;BYMONTHDAY=23',
      );
      expect(
        const Recurrence(unit: RepeatUnit.month, monthDay: -1).toRrule(),
        'FREQ=MONTHLY;BYMONTHDAY=-1',
      );
      expect(
        Recurrence.starting(RepeatUnit.year, mon).toRrule(),
        'FREQ=YEARLY;BYMONTHDAY=23;BYMONTH=11',
      );
    });

    test('round trips', () {
      for (final r in [
        'FREQ=DAILY;INTERVAL=3',
        'FREQ=WEEKLY;BYDAY=MO,FR',
        'FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=-1',
        'FREQ=YEARLY;BYMONTHDAY=1;BYMONTH=5',
      ]) {
        expect(Recurrence.parse(r)!.toRrule(), r);
      }
    });

    test('rejects what the editor cannot build', () {
      for (final r in [
        '',
        'FREQ=HOURLY',
        'FREQ=DAILY;COUNT=3',
        'FREQ=MONTHLY;BYDAY=1MO',
        'FREQ=MONTHLY;BYSETPOS=1;BYDAY=MO',
        'FREQ=WEEKLY;BYDAY=XX',
        'FREQ=DAILY;INTERVAL=0',
        'FREQ=MONTHLY;BYMONTHDAY=-2',
        'FREQ=MONTHLY;BYMONTHDAY=32',
        'FREQ=DAILY;FREQ=DAILY',
      ]) {
        expect(Recurrence.parse(r), isNull, reason: r);
      }
    });
  });

  group('occurrences', () {
    List<String> run(
      String rrule,
      DateTime start, {
      DateTime? from,
      DateTime? end,
      int count = 5,
    }) =>
        Recurrence.parse(rrule)!
            .occurrences(start, from: from ?? start, end: end, count: count)
            .map(_d)
            .toList();

    test('weekly Monday and Friday', () {
      expect(run('FREQ=WEEKLY;BYDAY=MO,FR', DateTime(2026, 11, 23)), [
        '2026-11-23',
        '2026-11-27',
        '2026-11-30',
        '2026-12-04',
        '2026-12-07',
      ]);
    });

    test('every 2 weeks counts weeks from the start week', () {
      expect(run('FREQ=WEEKLY;INTERVAL=2;BYDAY=WE', DateTime(2026, 11, 25)), [
        '2026-11-25',
        '2026-12-09',
        '2026-12-23',
        '2027-01-06',
        '2027-01-20',
      ]);
    });

    test('daily every 3 days, from later than the start', () {
      expect(
        run(
          'FREQ=DAILY;INTERVAL=3',
          DateTime(2026, 11, 1),
          from: DateTime(2026, 11, 10),
          count: 2,
        ),
        ['2026-11-10', '2026-11-13'],
      );
    });

    test('last day of month, over a leap year', () {
      expect(
        run('FREQ=MONTHLY;BYMONTHDAY=-1', DateTime(2027, 12, 31), count: 4),
        ['2027-12-31', '2028-01-31', '2028-02-29', '2028-03-31'],
      );
    });

    test('day 31 skips shorter months', () {
      expect(
        run('FREQ=MONTHLY;BYMONTHDAY=31', DateTime(2026, 11, 1), count: 3),
        ['2026-12-31', '2027-01-31', '2027-03-31'],
      );
    });

    test('yearly and end date', () {
      expect(
        run('FREQ=YEARLY;BYMONTHDAY=5;BYMONTH=3', DateTime(2026, 11, 23)),
        ['2027-03-05', '2028-03-05', '2029-03-05', '2030-03-05', '2031-03-05'],
      );
      expect(
        run('FREQ=DAILY', DateTime(2026, 11, 23), end: DateTime(2026, 11, 24)),
        ['2026-11-23', '2026-11-24'],
      );
    });

    test('defaults come from the start date', () {
      expect(run('FREQ=WEEKLY', DateTime(2026, 11, 25), count: 2), [
        '2026-11-25',
        '2026-12-02',
      ]);
      expect(run('FREQ=MONTHLY', DateTime(2026, 11, 15), count: 2), [
        '2026-11-15',
        '2026-12-15',
      ]);
    });
  });

  group('summary', () {
    String sum(String rrule, String locale) {
      final r = Recurrence.parse(rrule)!.anchored(DateTime(2026, 11, 23));
      return r.summary(lookupAppLocalizations(Locale(locale)), locale);
    }

    test('english', () {
      expect(sum('FREQ=DAILY', 'en'), 'Every day');
      expect(sum('FREQ=DAILY;INTERVAL=3', 'en'), 'Every 3 days');
      expect(sum('FREQ=WEEKLY;BYDAY=MO,FR', 'en'), 'Every week on Mon, Fri');
      expect(
        sum('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO', 'en'),
        'Every 2 weeks on Mon',
      );
      expect(sum('FREQ=MONTHLY;BYMONTHDAY=15', 'en'), 'Every month on day 15');
      expect(
        sum('FREQ=MONTHLY;BYMONTHDAY=-1', 'en'),
        'Every month on the last day',
      );
      expect(
        sum('FREQ=YEARLY;BYMONTHDAY=5;BYMONTH=3', 'en'),
        'Every year on March 5',
      );
    });

    test('polish plurals', () {
      expect(sum('FREQ=DAILY', 'pl'), 'Codziennie');
      expect(sum('FREQ=DAILY;INTERVAL=3', 'pl'), 'Co 3 dni');
      expect(
        sum('FREQ=WEEKLY;INTERVAL=2;BYDAY=MO', 'pl'),
        contains('Co 2 tygodnie'),
      );
      expect(
        sum('FREQ=WEEKLY;INTERVAL=5;BYDAY=MO', 'pl'),
        contains('Co 5 tygodni'),
      );
    });
  });
}
