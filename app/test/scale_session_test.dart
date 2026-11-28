import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oikoboard/modules/fitness/scale/scale_driver.dart';
import 'package:oikoboard/modules/fitness/scale/scale_session.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late StreamController<ScaleSignal> signals;
  late int flushes;
  late List<FinishReason> finished;
  late ScaleFinisher finisher;

  void build() {
    signals = StreamController<ScaleSignal>.broadcast();
    flushes = 0;
    finished = [];
    finisher = ScaleFinisher(
      signals: signals.stream,
      flush: () => flushes++,
      onFinish: finished.add,
    );
  }

  test('silence expires after 60 s, flushing once', () {
    fakeAsync((async) {
      build();
      async.elapse(const Duration(seconds: 59));
      expect(finished, isEmpty);
      async.elapse(const Duration(seconds: 1));
      expect(finished, [FinishReason.idle]);
      expect(flushes, 1);
    });
  });

  test('any signal resets the silence timer', () {
    fakeAsync((async) {
      build();
      for (var i = 0; i < 5; i++) {
        async.elapse(const Duration(seconds: 50));
        signals.add(ScaleSignal.activity);
        async.flushMicrotasks();
      }
      expect(finished, isEmpty);
      async.elapse(const Duration(seconds: 60));
      expect(finished, [FinishReason.idle]);
    });
  });

  test('history complete + 2 s quiet finishes; activity extends the quiet', () {
    fakeAsync((async) {
      build();
      signals.add(ScaleSignal.historyComplete);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      signals.add(ScaleSignal.activity);
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1500));
      expect(finished, isEmpty);
      async.elapse(const Duration(milliseconds: 500));
      expect(finished, [FinishReason.history]);
      expect(flushes, 1);
    });
  });

  test('user and disconnect finish once; later events are ignored', () {
    fakeAsync((async) {
      build();
      finisher.finish(FinishReason.user);
      finisher.finish(FinishReason.disconnect);
      async.elapse(const Duration(minutes: 5));
      expect(finished, [FinishReason.user]);
      expect(flushes, 1);
    });
  });

  test(
    'fake session emits waiting, then many samples, and can be finished',
    () async {
      final session = FakeScaleSession(
        samples: [
          for (var i = 1; i <= 12; i++)
            ScaleReading(
              time: DateTime.now().subtract(Duration(hours: i)),
              weightKg: 60.0 + i,
            ),
        ],
      );
      final phases = <ScalePhase>[];
      final readings = <ScaleReading>[];
      session.states.listen((s) => phases.add(s.phase));
      session.readings.listen(readings.add);
      await session.start();
      await Future<void>.delayed(Duration.zero);
      expect(phases, contains(ScalePhase.waiting));
      expect(phases.last, ScalePhase.done);
      expect(readings, hasLength(12));
      await session.dispose();
    },
  );
}
