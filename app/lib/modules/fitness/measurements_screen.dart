import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart' show uuid;
import '../../core/family.dart';
import '../../core/l10n.dart';
import '../../core/undo_delete.dart';
import '../../core/widgets.dart';
import 'format.dart';
import 'models.dart';
import 'repository.dart';
import 'trend_chart.dart';

/// Header of a Fitness sub-screen: back arrow and title.
class FitnessHeader extends StatelessWidget {
  const FitnessHeader({
    super.key,
    required this.title,
    this.actions = const [],
  });
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
    child: Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/fitness'),
        ),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ...actions,
      ],
    ),
  );
}

/// The household's measurements without those being deleted with Undo.
final _visibleMeasurementsProvider = Provider<AsyncValue<List<Measurement>>>((
  ref,
) {
  final pending = ref.watch(pendingDeletesProvider);
  return ref
      .watch(measurementsProvider)
      .whenData(
        (all) => pending.isEmpty
            ? all
            : [
                for (final m in all)
                  if (!pending.contains('measurement:${m.id}')) m,
              ],
      );
});

class MeasurementsScreen extends ConsumerStatefulWidget {
  const MeasurementsScreen({super.key});

  @override
  ConsumerState<MeasurementsScreen> createState() => _State();
}

class _State extends ConsumerState<MeasurementsScreen> {
  String? _member;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final family = ref.watch(familyProvider);
    final me = _member ?? ref.watch(currentMemberProvider);
    final async = ref.watch(_visibleMeasurementsProvider);
    final all = async.value ?? const <Measurement>[];
    final mine = [
      for (final m in all)
        if (m.memberId == me) m,
    ];
    final fmt = DateFormat.MMMEd().add_Hm();
    return Scaffold(
      body: Column(
        children: [
          FitnessHeader(title: l.fitnessMeasurementsTitle),
          Expanded(
            child: async.isLoading && !async.hasValue
                ? const Center(child: CircularProgressIndicator())
                : all.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.monitor_weight_outlined,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l.fitnessNoMeasurements,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l.fitnessNoMeasurementsHint,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in family.members)
                            ChoiceChip(
                              avatar: MemberAvatar(m, radius: 10),
                              label: Text(m.name),
                              selected: m.id == me,
                              onSelected: (_) => setState(() => _member = m.id),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
                          child: SizedBox(
                            height: 150,
                            child: TrendChart(
                              values: [
                                for (final m in mine.take(60).toList().reversed)
                                  m.weightKg,
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final m in all) _row(context, m, family, fmt),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l.fitnessAddMeasurement,
        onPressed: () => showAddMeasurement(context, member: me),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _row(
    BuildContext context,
    Measurement m,
    Family family,
    DateFormat fmt,
  ) {
    final l = context.l10n;
    final member = family.byId(m.memberId);
    final extra = [
      if (m.bmi != null) l.fitnessBmi(kg(m.bmi!)),
      if (m.fatPct != null) l.fitnessFatPct(kg(m.fatPct!)),
      if (m.waterPct != null) l.fitnessWaterPct(kg(m.waterPct!)),
      if (m.muscleKg != null) l.fitnessMusclePct(kg(m.muscleKg!)),
    ];
    final weight = '${kg(m.weightKg)} kg';
    return ListTile(
      key: ValueKey(m.id),
      contentPadding: EdgeInsets.zero,
      leading: member == null ? null : MemberAvatar(member),
      title: Text(weight),
      subtitle: Text(
        [
          fmt.format(m.measuredAt),
          if (extra.isNotEmpty) extra.join(' · '),
        ].join('\n'),
      ),
      isThreeLine: extra.isNotEmpty,
      trailing: IconButton(
        tooltip: l.commonDelete,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => deleteWithUndo(
          context,
          key: 'measurement:${m.id}',
          message: l.commonDeleted(weight),
          commit: () =>
              ref.read(fitnessRepositoryProvider).deleteMeasurement(m),
        ),
      ),
    );
  }
}

Future<void> showAddMeasurement(BuildContext context, {String? member}) =>
    showEditorSheet<void>(
      context,
      builder: (context) => _AddSheet(member: member),
    );

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet({this.member});
  final String? member;

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final _weight = TextEditingController();
  late String _member;
  DateTime _when = DateTime.now();
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _member = widget.member ?? ref.read(currentMemberProvider);
  }

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when),
    );
    if (time == null || !mounted) return;
    setState(
      () => _when = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _save() {
    final kgValue = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    if (kgValue == null || kgValue < 10 || kgValue > 500) {
      setState(() => _invalid = true);
      return;
    }
    ref
        .read(fitnessRepositoryProvider)
        .addMeasurement(
          Measurement(
            id: uuid.v4(),
            memberId: _member,
            measuredAt: _when,
            weightKg: double.parse(kgValue.toStringAsFixed(2)),
            source: Measurement.sourceManual,
            createdAt: DateTime.now(),
          ),
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final family = ref.watch(familyProvider);
    return EditorSheet(
      title: l.fitnessAddMeasurement,
      primary: FilledButton(onPressed: _save, child: Text(l.commonSave)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
      ],
      children: [
        TextField(
          controller: _weight,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l.fitnessWeight,
            errorText: _invalid ? l.fitnessWeightInvalid : null,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_invalid) setState(() => _invalid = false);
          },
        ),
        const SizedBox(height: 16),
        Text(l.fitnessWho, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final m in family.members)
              ChoiceChip(
                avatar: MemberAvatar(m, radius: 10),
                label: Text(m.name),
                selected: m.id == _member,
                onSelected: (_) => setState(() => _member = m.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickWhen,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: l.fitnessWhen,
              border: const OutlineInputBorder(),
            ),
            child: Text(DateFormat.MMMEd().add_Hm().format(_when)),
          ),
        ),
      ],
    );
  }
}
