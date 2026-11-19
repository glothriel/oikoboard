import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/mock/mock_store.dart';
import '../../core/module.dart';
import '../../core/widgets.dart';
import 'calendar_screen.dart';
import 'models.dart';
import 'repository.dart';

class CalendarModule extends FamilyModule {
  const CalendarModule();

  @override
  String get id => 'calendar';
  @override
  String title(AppLocalizations l) => l.calendarModuleTitle;
  @override
  IconData get icon => Icons.calendar_month_outlined;
  @override
  IconData get selectedIcon => Icons.calendar_month;

  @override
  Widget buildScreen(BuildContext context) => const CalendarScreen();

  @override
  Widget? buildWallTile(BuildContext context) => WallCard(
    title: title(context.l10n),
    icon: selectedIcon,
    path: path,
    child: const _CalendarWallTile(),
  );

  @override
  void seedMock(MockStore store) {
    for (final c in const [
      FamilyCalendar(
        id: 'cal-family',
        name: 'Rodzina',
        color: Color(0xFF5C6BC0),
        writable: true,
        account: 'mock',
        todoTarget: true,
      ),
      FamilyCalendar(
        id: 'cal-school',
        name: 'Szkoła',
        color: Color(0xFF26A69A),
        writable: true,
        account: 'mock',
      ),
    ]) {
      store.seed(calendarsEntity, c.toJson());
    }
    final now = DateTime.now();
    var n = 0;
    void ev(
      String title,
      int day,
      List<String> who, {
      int? from,
      int fromMin = 0,
      int? to,
      int toMin = 0,
      int days = 1,
    }) {
      final allDay = from == null;
      final start = allDay
          ? DateTime(now.year, now.month, now.day + day)
          : DateTime(now.year, now.month, now.day + day, from, fromMin);
      final end = allDay
          ? DateTime(now.year, now.month, now.day + day + days)
          : DateTime(now.year, now.month, now.day + day, to!, toMin);
      store.seed(
        eventsEntity,
        CalendarEvent(
          id: 'seed-ev-${n++}',
          calendarId: title.contains('szk') ? 'cal-school' : 'cal-family',
          title: title,
          start: start,
          end: end,
          allDay: allDay,
          memberIds: who,
        ).toJson(),
      );
    }

    ev('Przegląd auta', -5, ['tata'], from: 9, to: 10);
    ev('Basen', -2, ['ola'], from: 17, to: 18);
    ev('Odwieźć Kubę do szkoły', 0, ['tata'], from: 7, fromMin: 30, to: 8);
    ev('Basen', 0, ['ola'], from: 17, to: 18);
    ev(
      'Dentysta — Kuba',
      1,
      ['mama', 'kuba'],
      from: 16,
      fromMin: 30,
      to: 17,
      toMin: 30,
    );
    ev('Kolacja u sąsiadów', 1, ['mama', 'tata'], from: 19, to: 22);
    ev('Zebranie w szkole', 2, ['mama'], from: 18, to: 19, toMin: 30);
    ev('Urodziny babci', 3, ['mama', 'tata', 'ola', 'kuba']);
    ev('Piłka nożna', 5, ['kuba', 'tata'], from: 10, to: 12);
    ev('Basen', 7, ['ola'], from: 17, to: 18);
    ev('Wyjazd w góry', 9, ['mama', 'tata', 'ola', 'kuba'], days: 3);
    ev('Basen', 14, ['ola'], from: 17, to: 18);
  }

  static const _pool = [
    'Trening',
    'Kino',
    'Zakupy w Ikei',
    'Wizyta u lekarza',
    'Spotkanie z klasą',
    'Fryzjer',
    'Odebrać paczkę',
  ];

  @override
  Future<void> simulate(MockStore store, Random random, String actorId) async {
    final repo = MockCalendarRepository(store, actorId: actorId);
    final now = DateTime.now();
    final future = store
        .list(eventsEntity)
        .map(CalendarEvent.fromJson)
        .where((e) => !e.allDay && e.start.isAfter(now))
        .toList();
    if (future.isNotEmpty && random.nextInt(3) == 0) {
      final e = future[random.nextInt(future.length)];
      const shift = Duration(hours: 1);
      await repo.updateEvent(
        e,
        e.copyWith(start: e.start.add(shift), end: e.end.add(shift)),
      );
      return;
    }
    final start = DateTime(
      now.year,
      now.month,
      now.day + random.nextInt(7),
      8 + random.nextInt(11),
    );
    await repo.addEvent(
      CalendarEvent(
        id: store.newId(),
        calendarId: 'cal-family',
        title: _pool[random.nextInt(_pool.length)],
        start: start,
        end: start.add(const Duration(hours: 1)),
        allDay: false,
        memberIds: [actorId],
      ),
    );
  }
}

class _CalendarWallTile extends ConsumerWidget {
  const _CalendarWallTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = dateOnly(DateTime.now());
    final events =
        ref
            .watch(
              calendarRangeProvider((
                from: today,
                to: today.add(const Duration(days: 8)),
              )),
            )
            .value ??
        const <CalendarEvent>[];
    final tomorrow = today.add(const Duration(days: 1));
    final l = context.l10n;
    final soon = events
        .where(
          (e) =>
              !dateOnly(e.start).isBefore(today.add(const Duration(days: 2))) &&
              e.start.isBefore(today.add(const Duration(days: 8))),
        )
        .take(4)
        .toList();

    Widget section(
      String label,
      List<CalendarEvent> list, {
      bool showDay = false,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        if (list.isEmpty)
          Text('—', style: TextStyle(color: theme.colorScheme.outline)),
        for (final e in list)
          InkWell(
            onTap: () => showEventEditor(context, event: e),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  ColorDot(eventColor(e, context)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    [
                      if (showDay) relativeDay(l, e.start),
                      if (!e.allDay) hm(e.start),
                    ].join(' '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section(l.dateToday, eventsOn(events, today)),
        section(l.dateTomorrow, eventsOn(events, tomorrow)),
        if (soon.isNotEmpty) section(l.calendarSoon, soon, showDay: true),
      ],
    );
  }
}
