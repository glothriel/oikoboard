import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_client.dart' show uuid;
import '../../core/family.dart';
import '../../core/l10n.dart';
import 'composition.dart';
import 'format.dart';
import 'measurements_screen.dart';
import 'models.dart';
import 'repository.dart';
import 'scale/scale_driver.dart';
import 'scale/scale_session.dart';
import 'suggest.dart';

/// The measurement to store for [reading] weighed by [memberId]: with body
/// composition when the reading has impedance and the member has a [profile].
Measurement measurementFromReading(
  ScaleReading reading,
  String memberId,
  FitnessProfile? profile, {
  required String id,
  required DateTime now,
}) {
  final impedance = reading.impedance;
  final c = impedance == null || profile == null
      ? null
      : computeComposition(
          sex: profile.sex,
          age: ageAt(profile.birthDate, reading.time),
          heightCm: profile.heightCm,
          weightKg: reading.weightKg,
          impedance: impedance.toDouble(),
        );
  return Measurement(
    id: id,
    memberId: memberId,
    measuredAt: reading.time,
    weightKg: double.parse(reading.weightKg.toStringAsFixed(2)),
    impedance: impedance,
    lbmKg: c == null ? null : reading.weightKg * (100 - c.fatPct) / 100,
    fatPct: c?.fatPct,
    waterPct: c?.waterPct,
    proteinPct: c?.proteinPct,
    boneKg: c?.boneKg,
    muscleKg: c?.muscleKg,
    bmrKcal: c?.bmrKcal,
    visceralFat: c?.visceralFat,
    bmi: c?.bmi,
    source: Measurement.sourceScale,
    createdAt: now,
  );
}

class _Pending {
  _Pending(this.reading, this.member);
  final ScaleReading reading;
  String member;
}

class WeighInScreen extends ConsumerStatefulWidget {
  const WeighInScreen({super.key});

  @override
  ConsumerState<WeighInScreen> createState() => _WeighInState();
}

class _WeighInState extends ConsumerState<WeighInScreen> {
  ScaleSession? _session;
  final _subs = <StreamSubscription<Object?>>[];
  var _state = const ScaleState(ScalePhase.idle);
  final _pending = <_Pending>[];

  @override
  void initState() {
    super.initState();
    _scan();
  }

  void _scan() {
    final make = ref.read(scaleSessionProvider);
    if (make == null) return;
    _close();
    final session = _session = make();
    _pending.clear();
    _subs.add(
      session.states.listen((s) {
        if (mounted) setState(() => _state = s);
      }),
    );
    _subs.add(session.readings.listen(_onReading));
    session.start();
  }

  void _onReading(ScaleReading r) {
    if (!mounted) return;
    final me = ref.read(currentMemberProvider);
    final member = suggestMember(
      reading: r,
      all: ref.read(measurementsProvider).value ?? const [],
      now: DateTime.now(),
      fallbackMemberId: me,
    );
    setState(() => _pending.add(_Pending(r, member)));
  }

  void _close() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _session?.dispose();
    _session = null;
  }

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  Future<void> _save(_Pending p) async {
    final profiles = ref.read(fitnessProfilesProvider).value ?? const [];
    final profile = profiles.where((x) => x.id == p.member).firstOrNull;
    await ref
        .read(fitnessRepositoryProvider)
        .addMeasurement(
          measurementFromReading(
            p.reading,
            p.member,
            profile,
            id: uuid.v4(),
            now: DateTime.now(),
          ),
        );
    await _resolve(p);
  }

  Future<void> _resolve(_Pending p) async {
    await _session?.resolve(p.reading);
    if (mounted) setState(() => _pending.remove(p));
  }

  Future<void> _forget() async {
    await _session?.forget();
    _scan();
  }

  Future<void> _discardAll() async {
    for (final p in List.of(_pending)) {
      await _resolve(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final family = ref.watch(familyProvider);
    final fmt = DateFormat.MMMEd().add_Hm();
    final scanning = _state.phase == ScalePhase.scanning;
    final active =
        _state.phase == ScalePhase.waiting ||
        _state.phase == ScalePhase.connected;
    return Scaffold(
      body: Column(
        children: [
          FitnessHeader(
            title: l.fitnessWeighIn,
            back: '/fitness/measurements',
            actions: [
              PopupMenuButton<String>(
                onSelected: (_) => _forget(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'forget',
                    child: Text(l.fitnessWeighInForget),
                  ),
                ],
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _StatusCard(
                  state: _state,
                  onRetry:
                      _state.phase == ScalePhase.idle ||
                          scanning ||
                          active ||
                          _state.phase == ScalePhase.choosing
                      ? null
                      : _scan,
                  onDone: active ? () => _session?.finishNow() : null,
                ),
                const SizedBox(height: 8),
                if (_state.phase == ScalePhase.choosing)
                  Card(
                    child: Column(
                      children: [
                        for (final c in _state.candidates)
                          ListTile(
                            key: ValueKey('scale-${c.id}'),
                            leading: const Icon(Icons.monitor_weight_outlined),
                            title: Text(c.name),
                            onTap: () => _session?.choose(c),
                          ),
                      ],
                    ),
                  ),
                if (_pending.length > 1)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _discardAll,
                      child: Text(l.fitnessWeighInDiscardAll),
                    ),
                  ),
                if (_state.phase == ScalePhase.done && _pending.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text(
                          l.fitnessWeighInNone,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l.fitnessWeighInNoneHint,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: theme.colorScheme.outline),
                        ),
                      ],
                    ),
                  ),
                for (final p in _pending)
                  Card(
                    key: ValueKey(p.reading.time),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '${kg(p.reading.weightKg)} kg',
                                style: theme.textTheme.headlineSmall,
                              ),
                              const SizedBox(width: 12),
                              if (p.reading.impedance != null)
                                Text(
                                  l.fitnessWeighInImpedance(
                                    p.reading.impedance!,
                                  ),
                                  style: TextStyle(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            fmt.format(p.reading.time),
                            style: TextStyle(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 12),
                          Text(l.fitnessWho, style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          Wrap(
                            key: ValueKey('member-${p.reading.time}'),
                            spacing: 8,
                            children: [
                              for (final m in family.members)
                                ChoiceChip(
                                  avatar: MemberAvatar(m, radius: 10),
                                  label: Text(m.name),
                                  selected: m.id == p.member,
                                  onSelected: (_) =>
                                      setState(() => p.member = m.id),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _resolve(p),
                                child: Text(l.fitnessWeighInDiscard),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _save(p),
                                child: Text(l.commonSave),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.state,
    required this.onRetry,
    required this.onDone,
  });
  final ScaleState state;
  final VoidCallback? onRetry;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final name = state.scaleName ?? '';
    final isError = state.phase == ScalePhase.error;
    final text = switch (state.phase) {
      ScalePhase.idle || ScalePhase.scanning => l.fitnessWeighInScanning,
      ScalePhase.choosing => l.fitnessWeighInPick,
      ScalePhase.waiting => l.fitnessWeighInWaiting,
      ScalePhase.connected => l.fitnessWeighInConnected(name),
      ScalePhase.done => l.fitnessWeighInDone(name),
      ScalePhase.error => switch (state.error) {
        ScaleError.bluetoothOff => l.fitnessWeighInBluetoothOff,
        ScaleError.permissionDenied => l.fitnessWeighInPermissionDenied,
        ScaleError.notFound => l.fitnessWeighInNotFound,
        ScaleError.unsupported => l.fitnessWeighInUnsupported,
        _ => l.fitnessWeighInFailed,
      },
    };
    final busy =
        state.phase == ScalePhase.scanning ||
        state.phase == ScalePhase.waiting ||
        state.phase == ScalePhase.connected;
    return Card(
      color: isError ? scheme.errorContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isError ? Icons.bluetooth_disabled : Icons.bluetooth,
                    color: isError
                        ? scheme.onErrorContainer
                        : scheme.onSecondaryContainer,
                  ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
            if (onDone != null)
              TextButton(
                onPressed: onDone,
                child: Text(l.fitnessWeighInDoneButton),
              ),
            if (onRetry != null)
              TextButton(
                onPressed: onRetry,
                child: Text(
                  isError ? l.commonTryAgain : l.fitnessWeighInScanAgain,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
