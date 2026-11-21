import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart';
import '../../core/family.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/undo_delete.dart';
import 'calendars_sheet.dart';
import 'models.dart';
import 'repository.dart';
import 'time_grid.dart';
import 'todo_day_sheet.dart';

extension CalendarViewLabel on CalendarView {
  String label(AppLocalizations l) => switch (this) {
    CalendarView.day => l.calendarViewDay,
    CalendarView.threeDays => l.calendarViewThreeDays,
    CalendarView.week => l.calendarViewWeek,
    CalendarView.month => l.calendarViewMonth,
  };
}

extension RepeatLabel on Repeat {
  String label(AppLocalizations l) => switch (this) {
    Repeat.none => l.repeatNone,
    Repeat.daily => l.repeatDaily,
    Repeat.weekdays => l.repeatWeekdays,
    Repeat.weekly => l.repeatWeekly,
    Repeat.monthly => l.repeatMonthly,
    Repeat.yearly => l.repeatYearly,
    Repeat.custom => l.repeatCustom,
  };
}

/// Linked calendars where there's no `ref` (doesn't subscribe).
List<FamilyCalendar> calendarsOf(BuildContext context) =>
    ProviderScope.containerOf(
      context,
      listen: false,
    ).read(calendarsProvider).value ??
    const [];

FamilyCalendar? calendarOf(BuildContext context, String id) =>
    calendarsOf(context).where((c) => c.id == id).firstOrNull;

/// The first member's color, else the calendar's.
Color eventColor(CalendarEvent e, BuildContext context) =>
    familyOf(context).byId(e.memberIds.firstOrNull)?.color ??
    calendarOf(context, e.calendarId)?.color ??
    Theme.of(context).colorScheme.primary;

String eventTimeLabel(AppLocalizations l, CalendarEvent e) {
  if (e.allDay) {
    final days = e.end.difference(e.start).inDays;
    return days > 1 ? l.calendarAllDaySpan(days) : l.calendarAllDay;
  }
  if (isSameDay(e.start, e.end)) return '${hm(e.start)} – ${hm(e.end)}';
  final f = DateFormat('d MMM HH:mm');
  return '${f.format(e.start)} – ${f.format(e.end)}';
}

List<CalendarEvent> eventsOn(List<CalendarEvent> all, DateTime day) =>
    all.where((e) => e.occursOn(day)).toList()..sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.start.compareTo(b.start);
    });

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = dateOnly(DateTime.now());
  List<CalendarEvent> _lastEvents = const [];

  void _select(DateTime day) => setState(() {
    _selected = day;
    _month = DateTime(day.year, day.month);
  });

  /// Previous/next page of the view: a month, or as many days as it shows.
  void _shift(CalendarView view, int delta) {
    if (view == CalendarView.month) {
      setState(() => _month = DateTime(_month.year, _month.month + delta));
    } else {
      final d = _selected;
      _select(DateTime(d.year, d.month, d.day + delta * view.days));
    }
  }

  void _setView(CalendarView view) =>
      ref.read(calendarViewProvider.notifier).set(view);

  /// First day shown by a day-columns view (weeks start on Monday).
  DateTime _firstDay(CalendarView view) => view == CalendarView.week
      ? DateTime(
          _selected.year,
          _selected.month,
          _selected.day - _selected.weekday + 1,
        )
      : _selected;

  List<DateTime> _days(CalendarView view) {
    final first = _firstDay(view);
    return [
      for (var i = 0; i < view.days; i++)
        DateTime(first.year, first.month, first.day + i),
    ];
  }

  DateRange _range(CalendarView view) {
    if (view == CalendarView.month) return monthGridRange(_month);
    final days = _days(view);
    final last = days.last;
    return (
      from: days.first,
      to: DateTime(last.year, last.month, last.day + 1),
    );
  }

  String _title(CalendarView view) {
    if (view == CalendarView.month) {
      return capitalize(DateFormat('LLLL y').format(_month));
    }
    if (view == CalendarView.day) {
      return capitalize(DateFormat('EEE, d MMMM').format(_selected));
    }
    final days = _days(view);
    final (a, b) = (days.first, days.last);
    if (a.month == b.month) return capitalize(DateFormat('LLLL y').format(a));
    final from = DateFormat(a.year == b.year ? 'LLL' : 'LLL y').format(a);
    return capitalize('$from – ${DateFormat('LLL y').format(b)}');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _finishConnect());
  }

  /// Web: back from connecting an account — finish and show its calendars.
  Future<void> _finishConnect() async {
    final url = ref.read(pendingCalendarConnectProvider);
    if (url == null) return;
    ref.read(pendingCalendarConnectProvider.notifier).set(null);
    try {
      final id = await ref
          .read(calendarRepositoryProvider)
          .completeConnect(url);
      if (mounted) await showCalendarsSheet(context, openAccount: id);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } on CalendarConnectError catch (e) {
      if (mounted) {
        final l = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(switch (e.failure) {
              CalendarConnectFailure.cancelled => l.calendarConnectCancelled,
              CalendarConnectFailure.failed => l.calendarConnectFailed,
            }),
          ),
        );
      }
    }
  }

  Widget _header(CalendarView view, {required bool wide}) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final (previous, next) = switch (view) {
      CalendarView.day => (l.calendarPrevDay, l.calendarNextDay),
      CalendarView.month => (l.calendarPrevMonth, l.calendarNextMonth),
      _ => (l.calendarPrevPeriod, l.calendarNextPeriod),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _title(view),
              style: theme.textTheme.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<CalendarView>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  for (final v in CalendarView.values)
                    ButtonSegment(value: v, label: Text(v.label(l))),
                ],
                selected: {view},
                onSelectionChanged: (s) => _setView(s.single),
              ),
            )
          else
            PopupMenuButton<CalendarView>(
              tooltip: l.calendarViewTooltip,
              initialValue: view,
              onSelected: _setView,
              icon: Icon(_viewIcon(view)),
              itemBuilder: (_) => [
                for (final v in CalendarView.values)
                  PopupMenuItem(
                    value: v,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(_viewIcon(v)),
                      title: Text(v.label(l)),
                    ),
                  ),
              ],
            ),
          TextButton(
            onPressed: () => _select(dateOnly(DateTime.now())),
            child: Text(l.dateToday),
          ),
          IconButton(
            tooltip: l.calendarsTooltip,
            onPressed: () => showCalendarsSheet(context),
            icon: const Icon(Icons.tune),
          ),
          IconButton(
            tooltip: previous,
            onPressed: () => _shift(view, -1),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: next,
            onPressed: () => _shift(view, 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  static IconData _viewIcon(CalendarView v) => switch (v) {
    CalendarView.day => Icons.calendar_view_day,
    CalendarView.threeDays => Icons.view_column,
    CalendarView.week => Icons.view_week,
    CalendarView.month => Icons.calendar_view_month,
  };

  @override
  Widget build(BuildContext context) {
    final viewPref = ref.watch(calendarViewProvider);
    if (!viewPref.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    final view = viewPref.value!;
    final l = context.l10n;
    // Subscribes the calendar.range view to what's on screen. While a new
    // range loads, the previous events stay.
    final events =
        ref.watch(calendarRangeProvider(_range(view))).value ?? _lastEvents;
    _lastEvents = events;
    final calendars = ref.watch(calendarsProvider);
    final noCalendars = calendars.hasValue && calendars.value!.isEmpty;
    final canAdd = calendars.value?.any((c) => c.writable) ?? false;

    return Scaffold(
      floatingActionButton: canAdd
          ? FloatingActionButton(
              tooltip: l.calendarNewEvent,
              onPressed: () => showEventEditor(context, day: _selected),
              child: const Icon(Icons.add),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final header = _header(view, wide: constraints.maxWidth >= 720);
          if (view != CalendarView.month) {
            return Column(
              children: [
                header,
                Expanded(
                  child: noCalendars
                      ? const _ConnectPrompt()
                      : _SwipeDays(
                          // the week scrolls sideways itself
                          enabled: view != CalendarView.week,
                          onSwipe: (delta) => _shift(view, delta),
                          child: TimeGrid(
                            days: _days(view),
                            events: events,
                            // The week keeps readable columns and scrolls
                            // sideways; fewer days always fit the width.
                            minColumnWidth: view == CalendarView.week
                                ? 120
                                : null,
                            onDayTap: (d) {
                              _select(d);
                              _setView(CalendarView.day);
                            },
                            onSlotTap: canAdd
                                ? (t) => showEventEditor(context, start: t)
                                : null,
                          ),
                        ),
                ),
              ],
            );
          }
          final Widget agenda = noCalendars
              ? const _ConnectPrompt()
              : DayAgenda(day: _selected, events: eventsOn(events, _selected));
          if (constraints.maxWidth >= 840) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      header,
                      Expanded(
                        child: MonthGrid(
                          month: _month,
                          selected: _selected,
                          events: events,
                          onSelect: _select,
                          expand: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(width: 360, child: agenda),
              ],
            );
          }
          return Column(
            children: [
              header,
              MonthGrid(
                month: _month,
                selected: _selected,
                events: events,
                onSelect: _select,
                expand: false,
              ),
              const Divider(height: 1),
              Expanded(child: agenda),
            ],
          );
        },
      ),
    );
  }
}

/// Shown while the family has no calendar linked.
/// A horizontal swipe moves a day-columns view by a page: left = next.
class _SwipeDays extends StatelessWidget {
  const _SwipeDays({
    required this.enabled,
    required this.onSwipe,
    required this.child,
  });
  final bool enabled;
  final ValueChanged<int> onSwipe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() > 300) onSwipe(v < 0 ? 1 : -1);
      },
      child: child,
    );
  }
}

class _ConnectPrompt extends StatelessWidget {
  const _ConnectPrompt();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(context.l10n.calendarConnectPrompt, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => showCalendarsSheet(context),
            icon: const Icon(Icons.add_link),
            label: Text(context.l10n.calendarConnectAction),
          ),
        ],
      ),
    ),
  );
}

/// Days shown by the month grid (from Monday, 6 weeks).
DateRange monthGridRange(DateTime month) {
  final offset = DateTime(month.year, month.month, 1).weekday - 1;
  return (
    from: DateTime(month.year, month.month, 1 - offset),
    to: DateTime(month.year, month.month, 1 - offset + 42),
  );
}

class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.month,
    required this.selected,
    required this.events,
    required this.onSelect,
    required this.expand,
  });

  final DateTime month;
  final DateTime selected;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onSelect;

  /// true: the grid fills the available space and shows event titles.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final weekdays = [
      l.calendarWeekdayMon,
      l.calendarWeekdayTue,
      l.calendarWeekdayWed,
      l.calendarWeekdayThu,
      l.calendarWeekdayFri,
      l.calendarWeekdaySat,
      l.calendarWeekdaySun,
    ];
    final offset = DateTime(month.year, month.month, 1).weekday - 1;
    var days = List.generate(
      42,
      (i) => DateTime(month.year, month.month, 1 - offset + i),
    );
    if (days[35].month != month.month) days = days.sublist(0, 35);
    final today = DateTime.now();

    Widget row(int r) => Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var c = 0; c < 7; c++)
          Expanded(
            child: _DayCell(
              day: days[r * 7 + c],
              inMonth: days[r * 7 + c].month == month.month,
              isToday: isSameDay(days[r * 7 + c], today),
              isSelected: isSameDay(days[r * 7 + c], selected),
              events: eventsOn(events, days[r * 7 + c]),
              showTitles: expand,
              onTap: () => onSelect(days[r * 7 + c]),
            ),
          ),
      ],
    );

    final rows = days.length ~/ 7;
    final weekHeader = Row(
      children: [
        for (final w in weekdays)
          Expanded(
            child: Center(
              child: Text(
                w,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: expand
          ? Column(
              children: [
                weekHeader,
                const SizedBox(height: 4),
                for (var r = 0; r < rows; r++) Expanded(child: row(r)),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                weekHeader,
                const SizedBox(height: 4),
                for (var r = 0; r < rows; r++)
                  SizedBox(height: 48, child: row(r)),
              ],
            ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.events,
    required this.showTitles,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final List<CalendarEvent> events;
  final bool showTitles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final number = Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
          : null,
      child: Text(
        '${day.day}',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isToday
              ? scheme.onPrimary
              : inMonth
              ? scheme.onSurface
              : scheme.outline.withValues(alpha: 0.6),
          fontWeight: isToday || isSelected ? FontWeight.w700 : null,
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: isSelected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: showTitles
                ? LayoutBuilder(
                    builder: (context, c) {
                      final fit = ((c.maxHeight - 28) / 20).floor().clamp(
                        0,
                        99,
                      );
                      final shown = events.length > fit
                          ? (fit - 1).clamp(0, 99)
                          : events.length;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          number,
                          for (final e in events.take(shown)) _EventChip(e),
                          if (events.length > shown && fit > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, top: 2),
                              child: Text(
                                '+${events.length - shown}',
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                        ],
                      );
                    },
                  )
                : Column(
                    children: [
                      number,
                      const SizedBox(height: 3),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (final e in events.take(3))
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              decoration: BoxDecoration(
                                color: eventColor(e, context),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _EventChip extends StatelessWidget {
  const _EventChip(this.event);
  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    if (event.isTodo) return TodoDayChip(event, height: 18);
    final color = eventColor(event, context);
    return Container(
      height: 18,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: color.withValues(alpha: event.allDay ? 0.85 : 0.18),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        event.allDay ? event.title : '${hm(event.start)} ${event.title}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: event.allDay ? Colors.white : null),
      ),
    );
  }
}

/// A day's due tasks (or a task due at a time): outlined, with a checklist
/// icon — it stands for the tasks, not for an event. Tapping it opens them
/// (if [onTap] is set).
class TodoDayChip extends StatelessWidget {
  const TodoDayChip(this.event, {super.key, this.height, this.onTap});
  final CalendarEvent event;
  final double? height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = eventColor(event, context);
    final chip = Container(
      height: height,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          color.withValues(alpha: 0.12),
          theme.colorScheme.surface,
        ),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(Icons.checklist, size: 12, color: color),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              event.isTodoTask
                  ? '${hm(event.start)} ${event.title}'
                  : event.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: chip,
    );
  }
}

class DayAgenda extends StatelessWidget {
  const DayAgenda({super.key, required this.day, required this.events});

  final DateTime day;
  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Text(
          capitalize(DateFormat('EEEE, d MMMM').format(day)),
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              context.l10n.calendarNoEvents,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
        for (final e in events)
          EventCard(
            event: e,
            onTap: () => showEventEditor(context, event: e),
          ),
      ],
    );
  }
}

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.onTap});

  final CalendarEvent event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, color: eventColor(event, context)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              event.title,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          if (event.recurring)
                            Icon(
                              Icons.repeat,
                              size: 16,
                              color: theme.colorScheme.outline,
                            ),
                          if (event.isTodo)
                            Icon(
                              Icons.checklist,
                              size: 16,
                              color: theme.colorScheme.outline,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (event.isTodoDay)
                        TodoDayLists(
                          event.start,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        )
                      else
                        Text(
                          [
                            eventTimeLabel(context.l10n, event),
                            if (event.location.isNotEmpty) event.location,
                            ?calendarOf(context, event.calendarId)?.name,
                          ].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      if (event.memberIds.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (final m
                                in event.memberIds
                                    .map(familyOf(context).byId)
                                    .nonNulls)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: MemberAvatar(m, radius: 10),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens an event — a due-tasks day opens its tasks instead.
Future<void> showEventEditor(
  BuildContext context, {
  CalendarEvent? event,
  DateTime? day,
  DateTime? start,
}) {
  if (event != null && event.isTodo) {
    return showTodoDaySheet(context, dateOnly(event.start));
  }
  return showDialog<void>(
    context: context,
    builder: (_) => _EventEditor(event: event, day: day ?? start, start: start),
  );
}

/// For an occurrence of a series: change just it or the whole series?
Future<EditScope?> _askScope(BuildContext context, {required String title}) =>
    showDialog<EditScope>(
      context: context,
      builder: (context) {
        final l = context.l10n;
        return SimpleDialog(
          title: Text(title),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, EditScope.occurrence),
              child: Text(l.calendarRecurringThisOnly),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, EditScope.series),
              child: Text(l.calendarRecurringSeries),
            ),
          ],
        );
      },
    );

class _EventEditor extends ConsumerStatefulWidget {
  const _EventEditor({this.event, this.day, this.start});
  final CalendarEvent? event;
  final DateTime? day;

  /// New event: its start time (otherwise 9:00).
  final DateTime? start;

  @override
  ConsumerState<_EventEditor> createState() => _EventEditorState();
}

class _EventEditorState extends ConsumerState<_EventEditor> {
  late final _title = TextEditingController(text: widget.event?.title);
  late final _location = TextEditingController(text: widget.event?.location);
  late final _description = TextEditingController(
    text: widget.event?.description,
  );
  late bool _allDay = widget.event?.allDay ?? false;
  late DateTime _date = dateOnly(
    widget.event?.start ?? widget.day ?? DateTime.now(),
  );
  late TimeOfDay _startTime = TimeOfDay.fromDateTime(
    widget.event?.start ?? widget.start ?? _date.add(const Duration(hours: 9)),
  );
  late TimeOfDay _endTime = widget.event != null
      ? TimeOfDay.fromDateTime(widget.event!.end)
      : TimeOfDay(hour: (_startTime.hour + 1) % 24, minute: _startTime.minute);
  late Repeat _repeat = Repeat.of(widget.event?.recurrence ?? const []);
  String? _calendarId;

  /// Length of an all-day event in days (kept when editing).
  late final int _spanDays = widget.event?.allDay == true
      ? widget.event!.end.difference(widget.event!.start).inDays.clamp(1, 365)
      : 1;
  late final Set<String> _members = widget.event == null
      ? {ref.read(currentMemberProvider)}
      : {...widget.event!.memberIds};

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 2),
      lastDate: DateTime(_date.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        final duration = _at(_endTime).difference(_at(_startTime));
        _startTime = picked;
        _endTime = TimeOfDay.fromDateTime(_at(picked).add(duration));
      } else {
        _endTime = picked;
      }
    });
  }

  List<String> get _recurrence => switch (_repeat) {
    Repeat.custom => widget.event?.recurrence ?? const [],
    final r => [?r.rule],
  };

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty || _calendarId == null) return;
    final repo = ref.read(calendarRepositoryProvider);
    final DateTime start;
    DateTime end;
    if (_allDay) {
      start = _date;
      end = DateTime(_date.year, _date.month, _date.day + _spanDays);
    } else {
      start = _at(_startTime);
      end = _at(_endTime);
      if (!end.isAfter(start)) end = start.add(const Duration(hours: 1));
    }
    final members = ref
        .read(familyProvider)
        .members
        .map((m) => m.id)
        .where(_members.contains)
        .toList();
    final old = widget.event;
    if (old == null) {
      Navigator.pop(context);
      await repo.addEvent(
        CalendarEvent(
          id: uuid.v4(),
          calendarId: _calendarId!,
          title: title,
          description: _description.text.trim(),
          location: _location.text.trim(),
          start: start,
          end: end,
          allDay: _allDay,
          memberIds: members,
          recurrence: _recurrence,
        ),
      );
      return;
    }
    var scope = EditScope.series;
    if (old.originalStart != null) {
      // Changing the repeat rule always applies to the whole series.
      final picked = _repeat != Repeat.of(old.recurrence)
          ? EditScope.series
          : await _askScope(
              context,
              title: context.l10n.calendarRecurringChange,
            );
      if (picked == null || !mounted) return;
      scope = picked;
    }
    Navigator.pop(context);
    await repo.updateEvent(
      old,
      old.copyWith(
        title: title,
        description: _description.text.trim(),
        location: _location.text.trim(),
        start: start,
        end: end,
        allDay: _allDay,
        memberIds: members,
        recurrence: _recurrence,
      ),
      scope: scope,
    );
  }

  Future<void> _delete() async {
    final event = widget.event!;
    var scope = EditScope.series;
    if (event.originalStart != null) {
      final picked = await _askScope(
        context,
        title: context.l10n.calendarRecurringDelete,
      );
      if (picked == null || !mounted) return;
      scope = picked;
    }
    final repo = ref.read(calendarRepositoryProvider);
    deleteWithUndo(
      context,
      key: calendarEventKey(event, scope),
      message: context.l10n.commonDeleted(event.title),
      commit: () => repo.deleteEvent(event, scope: scope),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final calendars = ref.watch(calendarsProvider).value ?? const [];
    final current = widget.event == null
        ? null
        : calendars.where((c) => c.id == widget.event!.calendarId).firstOrNull;
    final readOnly = current != null && !current.writable;
    final writable = calendars.where((c) => c.writable).toList();
    _calendarId ??= widget.event?.calendarId ?? writable.firstOrNull?.id;
    final existing = widget.event != null;
    final l = context.l10n;

    return AlertDialog(
      title: Text(existing ? l.calendarEvent : l.calendarNewEvent),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (readOnly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    l.calendarReadOnlyNotice(current.name),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              TextField(
                controller: _title,
                enabled: !readOnly,
                autofocus: !existing,
                decoration: InputDecoration(labelText: l.calendarTitleField),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 8),
              if (existing)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.circle,
                    size: 14,
                    color: current?.color ?? theme.colorScheme.outline,
                  ),
                  title: Text(current?.name ?? l.calendarLabel),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _calendarId,
                  decoration: InputDecoration(labelText: l.calendarLabel),
                  items: [
                    for (final c in writable)
                      DropdownMenuItem(
                        value: c.id,
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 12, color: c.color),
                            const SizedBox(width: 8),
                            Text(c.name),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _calendarId = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.calendarAllDay),
                value: _allDay,
                onChanged: readOnly ? null : (v) => setState(() => _allDay = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(
                  capitalize(DateFormat('EEEE, d MMMM y').format(_date)),
                ),
                onTap: readOnly ? null : _pickDate,
              ),
              if (!_allDay)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(_startTime.format(context)),
                        onPressed: readOnly ? null : () => _pickTime(true),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('–'),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: readOnly ? null : () => _pickTime(false),
                        child: Text(_endTime.format(context)),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              DropdownButtonFormField<Repeat>(
                initialValue: _repeat,
                decoration: InputDecoration(
                  labelText: l.calendarRepeatField,
                  prefixIcon: const Icon(Icons.repeat),
                ),
                items: [
                  for (final r in Repeat.values)
                    if (r != Repeat.custom || _repeat == Repeat.custom)
                      DropdownMenuItem(value: r, child: Text(r.label(l))),
                ],
                onChanged: readOnly
                    ? null
                    : (v) => setState(() => _repeat = v ?? Repeat.none),
              ),
              TextField(
                controller: _location,
                enabled: !readOnly,
                decoration: InputDecoration(
                  labelText: l.calendarPlaceField,
                  prefixIcon: const Icon(Icons.place_outlined),
                ),
              ),
              TextField(
                controller: _description,
                enabled: !readOnly,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l.calendarDescriptionField,
                  prefixIcon: const Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 16),
              Text(l.calendarWhoField, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in ref.watch(familyProvider).members)
                    FilterChip(
                      avatar: MemberAvatar(m, radius: 10),
                      label: Text(m.name),
                      showCheckmark: false,
                      selected: _members.contains(m.id),
                      onSelected: readOnly
                          ? null
                          : (v) => setState(
                              () => v
                                  ? _members.add(m.id)
                                  : _members.remove(m.id),
                            ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (existing && !readOnly)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: Text(l.commonDelete),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(readOnly ? l.commonClose : l.commonCancel),
        ),
        if (!readOnly)
          FilledButton(onPressed: _save, child: Text(l.commonSave)),
      ],
    );
  }
}
