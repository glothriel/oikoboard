import 'dart:async';
import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format.dart';
import 'calendar_screen.dart';
import 'models.dart';

/// Days side by side on a 24-hour axis (the day, 3-day and week views).
///
/// Columns share the available width; with [minColumnWidth] they don't get
/// narrower than that and the days scroll horizontally instead.
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.days,
    required this.events,
    this.minColumnWidth,
    this.onDayTap,
    this.onSlotTap,
  });

  final List<DateTime> days;
  final List<CalendarEvent> events;
  final double? minColumnWidth;
  final ValueChanged<DateTime>? onDayTap;

  /// An empty spot was tapped; gets its time rounded down to half an hour.
  final ValueChanged<DateTime>? onSlotTap;

  static const hourHeight = 52.0;
  static const gutter = 48.0;

  @override
  State<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<TimeGrid> {
  late final ScrollController _vertical;
  final _headScroll = ScrollController();
  final _bodyScroll = ScrollController();
  late final Timer _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Start at 7:00, or an hour before now when today is shown.
    final showsToday = widget.days.any((d) => isSameDay(d, _now));
    final hour = showsToday ? math.max(_now.hour - 1, 0) : 7;
    _vertical = ScrollController(
      initialScrollOffset: hour * TimeGrid.hourHeight,
    );
    // The day headers scroll horizontally together with the grid.
    _headScroll.addListener(() => _follow(_headScroll, _bodyScroll));
    _bodyScroll.addListener(() => _follow(_bodyScroll, _headScroll));
    _clock = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  void _follow(ScrollController from, ScrollController to) {
    if (to.hasClients && to.offset != from.offset) to.jumpTo(from.offset);
  }

  @override
  void dispose() {
    _clock.cancel();
    _vertical.dispose();
    _headScroll.dispose();
    _bodyScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = widget.days;
    return LayoutBuilder(
      builder: (context, c) {
        final available = c.maxWidth - TimeGrid.gutter;
        final column = math.max(
          available / days.length,
          widget.minColumnWidth ?? 0,
        );
        final width = column * days.length;
        final scrolls = width > available + 0.5;

        Widget horizontal(ScrollController controller, Widget child) => scrolls
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: controller,
                child: SizedBox(width: width, child: child),
              )
            : child;

        final allDay = [
          for (final d in days)
            eventsOn(widget.events, d).where((e) => e.allDay).toList(),
        ];
        final allDayRows = allDay.map((l) => l.length).fold(0, math.max);

        final head = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final d in days)
                  SizedBox(
                    width: column,
                    child: _DayHeader(
                      day: d,
                      isToday: isSameDay(d, _now),
                      onTap: widget.onDayTap == null
                          ? null
                          : () => widget.onDayTap!(d),
                    ),
                  ),
              ],
            ),
            if (allDayRows > 0)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in allDay)
                    SizedBox(width: column, child: _AllDayCell(l, max: 3)),
                ],
              ),
          ],
        );

        final body = SizedBox(
          height: 24 * TimeGrid.hourHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: TimeGrid.gutter,
                child: _HourLabels(theme: theme),
              ),
              Expanded(
                child: horizontal(
                  _bodyScroll,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final d in days)
                        SizedBox(
                          width: column,
                          child: _DayColumn(
                            day: d,
                            events: widget.events,
                            now: isSameDay(d, _now) ? _now : null,
                            onSlotTap: widget.onSlotTap,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(width: TimeGrid.gutter),
                Expanded(child: horizontal(_headScroll, head)),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(controller: _vertical, child: body),
            ),
          ],
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday, this.onTap});

  final DateTime day;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Text(
              DateFormat('EEE').format(day),
              style: theme.textTheme.labelMedium?.copyWith(
                color: isToday ? scheme.primary : scheme.outline,
              ),
            ),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
                  : null,
              child: Text(
                '${day.day}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isToday ? scheme.onPrimary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllDayCell extends StatelessWidget {
  const _AllDayCell(this.events, {required this.max});

  final List<CalendarEvent> events;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = events.length > max ? max - 1 : events.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in events.take(shown))
            _Tile(event: e, allDay: true, height: 20),
          if (events.length > shown)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                '+${events.length - shown}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _HourLabels extends StatelessWidget {
  const _HourLabels({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      for (var h = 1; h < 24; h++)
        Positioned(
          top: h * TimeGrid.hourHeight - 8,
          right: 6,
          child: Text(
            '$h:00',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
    ],
  );
}

/// A timed event placed in a day: minutes from midnight and its lane.
class _Placed {
  _Placed(this.event, this.top, this.bottom);
  final CalendarEvent event;
  final int top;
  final int bottom;
  int lane = 0;
  int lanes = 1;
}

int _minuteOf(DateTime t, DateTime day) {
  if (!t.isAfter(day)) return 0;
  if (!isSameDay(t, day)) return 24 * 60;
  return t.hour * 60 + t.minute;
}

/// Overlapping events share the width: each cluster of overlapping events
/// is split into lanes, an event takes the first lane free at its start.
List<_Placed> _layout(List<CalendarEvent> events, DateTime day) {
  const minMinutes = 25; // shortest an event is drawn
  final placed = [
    for (final e in eventsOn(events, day).where((e) => !e.allDay))
      _Placed(e, _minuteOf(e.start, day), _minuteOf(e.end, day)),
  ]..sort((a, b) => a.top != b.top ? a.top - b.top : b.bottom - a.bottom);

  final cluster = <_Placed>[];
  final laneEnds = <int>[];
  var clusterEnd = -1;
  void close() {
    for (final p in cluster) {
      p.lanes = laneEnds.length;
    }
    cluster.clear();
    laneEnds.clear();
  }

  for (final p in placed) {
    if (p.top >= clusterEnd) close();
    final end = math.max(p.bottom, p.top + minMinutes);
    var lane = laneEnds.indexWhere((e) => e <= p.top);
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(end);
    } else {
      laneEnds[lane] = end;
    }
    p.lane = lane;
    cluster.add(p);
    clusterEnd = math.max(clusterEnd, end);
  }
  close();
  return placed;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.events,
    this.now,
    this.onSlotTap,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final DateTime? now;
  final ValueChanged<DateTime>? onSlotTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const hh = TimeGrid.hourHeight;
    final line = scheme.outlineVariant.withValues(alpha: 0.5);

    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth - 4;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onSlotTap == null
              ? null
              : (d) {
                  final half = (d.localPosition.dy / (hh / 2)).floor();
                  onSlotTap!(
                    DateTime(day.year, day.month, day.day, 0, half * 30),
                  );
                },
          child: Container(
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: line)),
            ),
            child: Stack(
              children: [
                for (var h = 1; h < 24; h++)
                  Positioned(
                    top: h * hh,
                    left: 0,
                    right: 0,
                    child: Container(height: 1, color: line),
                  ),
                for (final p in _layout(events, day))
                  Positioned(
                    top: p.top * hh / 60,
                    height: math.max((p.bottom - p.top) * hh / 60 - 1, 20),
                    left: 2 + p.lane * width / p.lanes,
                    width: width / p.lanes - 1,
                    child: _Tile(event: p.event),
                  ),
                if (now != null)
                  Positioned(
                    top: (now!.hour * 60 + now!.minute) * hh / 60 - 4,
                    left: 0,
                    right: 0,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: scheme.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Container(height: 2, color: scheme.error),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.event, this.allDay = false, this.height});

  final CalendarEvent event;
  final bool allDay;
  final double? height;

  @override
  Widget build(BuildContext context) {
    if (event.isTodoDay) {
      return TodoDayChip(
        event,
        height: height,
        onTap: () => showEventEditor(context, event: event),
      );
    }
    final theme = Theme.of(context);
    final color = eventColor(event, context);
    final text = theme.textTheme.labelSmall?.copyWith(
      color: allDay ? Colors.white : null,
    );
    return Container(
      height: height,
      margin: allDay ? const EdgeInsets.only(top: 2) : null,
      child: Material(
        color: allDay
            ? color.withValues(alpha: 0.85)
            : Color.alphaBlend(
                color.withValues(alpha: 0.22),
                theme.colorScheme.surface,
              ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: allDay
              ? BorderSide.none
              : BorderSide(color: color.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showEventEditor(context, event: event),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: LayoutBuilder(
              // Short events show what fits, the rest is clipped.
              builder: (context, c) => ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  maxHeight: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        maxLines: c.maxHeight > 50 ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: text?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (!allDay && c.maxHeight > 30)
                        Text(
                          '${hm(event.start)} – ${hm(event.end)}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: text,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
