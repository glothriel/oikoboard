import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/family.dart';
import '../../core/l10n.dart';
import 'composition.dart';
import 'measurements_screen.dart' show FitnessHeader;
import 'repository.dart';

/// The signed-in member's sex, birth date and height: what body composition
/// needs besides the scale's reading.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _height = TextEditingController();
  Sex _sex = Sex.male;
  DateTime? _birthDate;
  bool _loaded = false;
  bool _birthDateMissing = false;
  String? _heightError;

  @override
  void dispose() {
    _height.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    setState(() {
      _birthDate = date;
      _birthDateMissing = false;
    });
  }

  Future<void> _save() async {
    final l = context.l10n;
    final height = double.tryParse(_height.text.trim().replaceAll(',', '.'));
    final today = DateTime.now();
    final birth = _birthDate;
    final heightOk = height != null && height >= 50 && height <= 250;
    final birthOk =
        birth != null &&
        birth.isBefore(DateTime(today.year, today.month, today.day));
    setState(() {
      _heightError = heightOk ? null : l.fitnessHeightInvalid;
      _birthDateMissing = !birthOk;
    });
    if (!heightOk || !birthOk) return;
    await ref
        .read(fitnessRepositoryProvider)
        .saveProfile(sex: _sex, birthDate: birth, heightCm: height);
    if (mounted) context.go('/fitness');
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final me = ref.watch(currentMemberProvider);
    final async = ref.watch(fitnessProfilesProvider);
    final mine = async.value?.where((p) => p.id == me).firstOrNull;
    // Fill the form once from the stored profile; later edits stay put.
    if (!_loaded && (mine != null || async.hasValue)) {
      _loaded = true;
      if (mine != null) {
        _sex = mine.sex;
        _birthDate = mine.birthDate;
        _height.text = mine.heightCm.toStringAsFixed(
          mine.heightCm % 1 == 0 ? 0 : 1,
        );
      }
    }
    final birth = _birthDate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FitnessHeader(title: l.fitnessProfileTitle),
        Expanded(
          child: !_loaded
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(l.fitnessSex, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    SegmentedButton<Sex>(
                      segments: [
                        ButtonSegment(
                          value: Sex.male,
                          label: Text(l.fitnessSexMale),
                        ),
                        ButtonSegment(
                          value: Sex.female,
                          label: Text(l.fitnessSexFemale),
                        ),
                      ],
                      selected: {_sex},
                      onSelectionChanged: (s) => setState(() => _sex = s.first),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      key: const Key('fitness-birth-date'),
                      onTap: _pickBirthDate,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: l.fitnessBirthDate,
                          border: const OutlineInputBorder(),
                          suffixIcon: const Icon(Icons.calendar_today_outlined),
                          errorText: _birthDateMissing
                              ? l.fitnessBirthDateInvalid
                              : null,
                        ),
                        child: Text(
                          birth == null
                              ? ''
                              : DateFormat.yMMMMd(
                                  Localizations.localeOf(context).toString(),
                                ).format(birth),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      key: const Key('fitness-height'),
                      controller: _height,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l.fitnessHeight,
                        border: const OutlineInputBorder(),
                        errorText: _heightError,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _save,
                        child: Text(l.commonSave),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
