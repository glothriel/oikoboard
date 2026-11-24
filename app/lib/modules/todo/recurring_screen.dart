import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart' show uuid;
import '../../core/family.dart';
import '../../core/l10n.dart';
import '../../core/widgets.dart';
import 'models.dart';
import 'recurrence.dart';
import 'recurring.dart';
import 'todo_screen.dart' show dueText, pickDueDate, pickDueTime;

/// The drawer with the recurring task templates of [list]: a row each, a
/// pause switch and an add button; a row opens the form.
Future<void> showRecurringDrawer(BuildContext context, TodoList list) =>
    showSideSheet<void>(context, builder: (_) => _RecurringDrawer(list: list));

String _day(BuildContext context, DateTime d) =>
    DateFormat.MMMEd(Localizations.localeOf(context).toString()).format(d);

class _RecurringDrawer extends ConsumerWidget {
  const _RecurringDrawer({required this.list});
  final TodoList list;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final templates = [
      for (final t
          in ref.watch(recurringTasksProvider).value ?? const <RecurringTask>[])
        if (t.listId == list.id) t,
    ];
    return SideSheetScaffold(
      title: l.recurringTitle,
      actions: [
        IconButton(
          tooltip: l.recurringNew,
          icon: const Icon(Icons.add),
          onPressed: () => showRecurringForm(context, list: list),
        ),
      ],
      children: [
        if (templates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              l.recurringEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.outline),
            ),
          ),
        for (final t in templates)
          Builder(
            builder: (context) {
              final rule = Recurrence.parse(t.rrule);
              final summary =
                  rule?.anchored(t.startDate).summary(l, locale) ??
                  l.recurCustomRule(t.rrule);
              final next = t.active ? t.nextOccurrence(DateTime.now()) : null;
              return ListTile(
                key: ValueKey(t.id),
                contentPadding: EdgeInsets.zero,
                title: Text(t.title),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary),
                    Text(
                      !t.active
                          ? l.recurringPaused
                          : next == null
                          ? l.recurringNoNext
                          : l.recurringNext(_day(context, next)),
                    ),
                  ],
                ),
                onTap: () => showRecurringForm(context, list: list, task: t),
                trailing: Switch(
                  value: t.active,
                  onChanged: (v) => ref
                      .read(recurringRepositoryProvider)
                      .update(t, t.copyWith(active: v)),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// The template form (a side sheet over the drawer); [task] null = a new one.
Future<void> showRecurringForm(
  BuildContext context, {
  required TodoList list,
  RecurringTask? task,
}) => showSideSheet<void>(
  context,
  builder: (_) => _RecurringForm(list: list, task: task),
);

enum _DueMode { none, sameDay, after }

class _RecurringForm extends ConsumerStatefulWidget {
  const _RecurringForm({required this.list, this.task});
  final TodoList list;
  final RecurringTask? task;

  @override
  ConsumerState<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<_RecurringForm> {
  late final _title = TextEditingController(text: widget.task?.title);
  late final _description = TextEditingController(
    text: widget.task?.description,
  );
  late final _interval = TextEditingController(text: '1');
  late final _dueDays = TextEditingController(text: '2');

  late String? _assignee = widget.task?.assigneeId;
  late DateTime _start =
      widget.task?.startDate ??
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  late DateTime? _end = widget.task?.endDate;
  late TimeOfDay _createTime =
      widget.task?.createTime ?? const TimeOfDay(hour: 6, minute: 0);
  late TimeOfDay? _dueTime = widget.task?.dueTime;
  late _DueMode _dueMode = switch (widget.task?.dueOffsetDays) {
    null => _DueMode.none,
    0 => _DueMode.sameDay,
    _ => _DueMode.after,
  };

  /// The schedule; [_raw] holds a stored rule the form can't edit.
  late RepeatUnit _unit = RepeatUnit.week;
  late Set<int> _weekdays = {_start.weekday};
  bool _lastDay = false;
  String? _raw;

  Timer? _debounce;
  int _previewSeq = 0;
  List<DateTime>? _dates;
  bool _previewFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(now: true));
    final t = widget.task;
    if (t == null) return;
    final due = t.dueOffsetDays;
    if (due != null && due > 0) _dueDays.text = '$due';
    final r = Recurrence.parse(t.rrule);
    if (r == null) {
      _raw = t.rrule;
    } else {
      final a = r.anchored(t.startDate);
      _unit = a.unit;
      _weekdays = {...a.weekdays};
      _lastDay = a.lastDay;
      _interval.text = '${a.interval}';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _title.dispose();
    _description.dispose();
    _interval.dispose();
    _dueDays.dispose();
    super.dispose();
  }

  int get _n => (int.tryParse(_interval.text) ?? 1).clamp(1, 999);

  int? get _offset => switch (_dueMode) {
    _DueMode.none => null,
    _DueMode.sameDay => 0,
    _DueMode.after => (int.tryParse(_dueDays.text) ?? 1).clamp(1, 366),
  };

  String get _rrule {
    if (_raw != null) return _raw!;
    return Recurrence(
      unit: _unit,
      interval: _n,
      weekdays: _unit == RepeatUnit.week
          ? (_weekdays.isEmpty ? {_start.weekday} : _weekdays)
          : const {},
      monthDay: switch (_unit) {
        RepeatUnit.month => _lastDay ? -1 : _start.day,
        RepeatUnit.year => _start.day,
        _ => null,
      },
      month: _unit == RepeatUnit.year ? _start.month : null,
    ).toRrule();
  }

  /// Recomputes the preview, after a pause in the edits.
  void _refresh({bool now = false}) {
    _debounce?.cancel();
    void run() async {
      final seq = ++_previewSeq;
      try {
        final dates = await ref
            .read(recurringRepositoryProvider)
            .preview(rrule: _rrule, startDate: _start, endDate: _end);
        if (!mounted || seq != _previewSeq) return;
        setState(() {
          _dates = dates;
          _previewFailed = false;
        });
      } catch (_) {
        if (!mounted || seq != _previewSeq) return;
        setState(() {
          _dates = null;
          _previewFailed = true;
        });
      }
    }

    now ? run() : _debounce = Timer(const Duration(milliseconds: 400), run);
  }

  void _edit(VoidCallback change) {
    setState(change);
    _refresh();
  }

  Future<void> _pickStart() async {
    final d = await pickDueDate(context, _start);
    if (d == null) return;
    _edit(() {
      _start = d;
      if (_end != null && _end!.isBefore(d)) _end = d;
    });
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end ?? _start,
      firstDate: _start,
      lastDate: DateTime(_start.year + 20),
    );
    if (d != null) _edit(() => _end = d);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    final repo = ref.read(recurringRepositoryProvider);
    final old = widget.task;
    final offset = _offset;
    final draft =
        (old ??
                RecurringTask(
                  id: uuid.v4(),
                  listId: widget.list.id,
                  title: title,
                  rrule: _rrule,
                  startDate: _start,
                ))
            .copyWith(
              title: title,
              description: _description.text.trim(),
              assigneeId: _assignee,
              rrule: _rrule,
              startDate: _start,
              endDate: _end,
              createTime: _createTime,
              dueOffsetDays: offset,
              dueTime: offset == null ? null : _dueTime,
            );
    old == null ? repo.add(draft) : repo.update(old, draft);
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final t = widget.task!;
    final ok = await confirmDelete(
      context,
      title: l.recurDeleteTitle(t.title),
      message: l.recurDeleteMessage,
    );
    if (!ok || !mounted) return;
    ref.read(recurringRepositoryProvider).delete(t);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final members = ref.watch(familyProvider).members;
    final unitLabel = switch (_unit) {
      RepeatUnit.day => l.recurUnitDay(_n),
      RepeatUnit.week => l.recurUnitWeek(_n),
      RepeatUnit.month => l.recurUnitMonth(_n),
      RepeatUnit.year => l.recurUnitYear(_n),
    };
    final first = _dates?.firstOrNull;
    final offset = _offset;

    return SideSheetScaffold(
      title: widget.task == null ? l.recurringNew : l.recurringEdit,
      actions: [
        if (widget.task != null)
          IconButton(
            tooltip: l.commonDelete,
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
      ],
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerRight,
            child: ListenableBuilder(
              listenable: _title,
              builder: (context, _) => FilledButton(
                onPressed: _title.text.trim().isEmpty ? null : _save,
                child: Text(l.commonSave),
              ),
            ),
          ),
        ),
      ),
      children: [
        TextField(
          controller: _title,
          autofocus: widget.task == null,
          decoration: InputDecoration(labelText: l.todoTask),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _description,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(labelText: l.todoDescription),
        ),
        const SizedBox(height: 20),
        Text(l.todoWhoDoesIt, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l.commonNobody),
              selected: _assignee == null,
              onSelected: (_) => setState(() => _assignee = null),
            ),
            for (final m in members)
              ChoiceChip(
                avatar: MemberAvatar(m, radius: 10),
                label: Text(m.name),
                selected: _assignee == m.id,
                showCheckmark: false,
                onSelected: (_) => setState(() => _assignee = m.id),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text(l.recurringRepeat, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (_raw != null)
          Text(l.recurCustomRule(_raw!))
        else ...[
          Wrap(
            spacing: 8,
            children: [
              for (final (u, label) in [
                (RepeatUnit.day, l.recurDailyChip),
                (RepeatUnit.week, l.recurWeeklyChip),
                (RepeatUnit.month, l.recurMonthlyChip),
                (RepeatUnit.year, l.recurYearlyChip),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _unit == u,
                  onSelected: (_) => _edit(() {
                    _unit = u;
                    if (u == RepeatUnit.week && _weekdays.isEmpty) {
                      _weekdays = {_start.weekday};
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(l.recurEvery),
              const SizedBox(width: 12),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _interval,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onChanged: (_) => _edit(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Text(unitLabel),
            ],
          ),
          if (_unit == RepeatUnit.week) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(
                      DateFormat.E(locale).format(DateTime(2024, 1, d)),
                    ),
                    selected: _weekdays.contains(d),
                    onSelected: (on) => _edit(() {
                      on ? _weekdays.add(d) : _weekdays.remove(d);
                      if (_weekdays.isEmpty) _weekdays.add(d);
                    }),
                  ),
              ],
            ),
          ],
          if (_unit == RepeatUnit.month) ...[
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l.recurOnDay(_start.day)),
                ),
                ButtonSegment(value: true, label: Text(l.recurLastDay)),
              ],
              selected: {_lastDay},
              onSelectionChanged: (s) => _edit(() => _lastDay = s.first),
            ),
          ],
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text(l.recurStartsOn(_day(context, _start))),
                onPressed: _pickStart,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_busy),
                label: Text(
                  _end == null
                      ? l.recurEndsNever
                      : l.recurEndsOn(_day(context, _end!)),
                ),
                onPressed: _pickEnd,
              ),
            ),
            if (_end != null)
              IconButton(
                tooltip: l.recurNoEnd,
                icon: const Icon(Icons.close),
                onPressed: () => _edit(() => _end = null),
              ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.schedule),
          label: Text(l.recurCreatesAtTime(_createTime.format(context))),
          onPressed: () async {
            final t = await showTimePicker(
              context: context,
              initialTime: _createTime,
            );
            if (t != null) setState(() => _createTime = t);
          },
        ),
        const SizedBox(height: 20),
        Text(l.recurDue, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final (m, label) in [
              (_DueMode.none, l.recurDueNone),
              (_DueMode.sameDay, l.recurDueSameDay),
              (_DueMode.after, l.recurDueAfter),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _dueMode == m,
                onSelected: (_) => setState(() => _dueMode = m),
              ),
          ],
        ),
        if (_dueMode == _DueMode.after) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _dueDays,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.recurDueDaysField),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
        if (_dueMode != _DueMode.none) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.access_time),
                label: Text(
                  _dueTime == null ? l.todoSetTime : _dueTime!.format(context),
                ),
                onPressed: () async {
                  final t = await pickDueTime(context, _dueTime);
                  if (t != null) setState(() => _dueTime = t);
                },
              ),
              if (_dueTime != null)
                IconButton(
                  tooltip: l.todoRemoveTime,
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _dueTime = null),
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Text(l.recurNextOccurrences, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        if (_previewFailed)
          Text(
            l.recurPreviewFailed,
            style: TextStyle(color: theme.colorScheme.error),
          )
        else if (_dates == null)
          const LinearProgressIndicator()
        else if (_dates!.isEmpty)
          Text(l.recurNoOccurrences)
        else ...[
          for (final d in _dates!.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(_day(context, d)),
            ),
          if (first != null && offset != null) ...[
            const SizedBox(height: 8),
            Text(
              l.recurFirstDue(
                dueText(
                  context,
                  DateTime(first.year, first.month, first.day + offset),
                  _dueTime,
                ),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ],
    );
  }
}
