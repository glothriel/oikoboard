import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/modules/fitness/models.dart';
import 'package:oikoboard/modules/fitness/scale/scale_driver.dart';
import 'package:oikoboard/modules/fitness/suggest.dart';

final now = DateTime(2026, 6, 30, 8);

Measurement m(String member, int daysAgo, double kg, [int? imp]) => Measurement(
  id: '$member$daysAgo',
  memberId: member,
  measuredAt: now.subtract(Duration(days: daysAgo)),
  weightKg: kg,
  impedance: imp,
  source: 'scale',
  createdAt: now,
);

String suggest(double kg, int? imp, List<Measurement> all) => suggestMember(
  reading: ScaleReading(time: now, weightKg: kg, impedance: imp),
  all: all,
  now: now,
  fallbackMemberId: 'me',
);

void main() {
  test('no data falls back to the signed-in member', () {
    expect(suggest(70, 500, const []), 'me');
  });

  test('closest weight wins', () {
    expect(suggest(61, null, [m('a', 2, 85), m('b', 2, 60)]), 'b');
  });

  test('two recent measurements: either can match', () {
    final all = [m('a', 1, 70), m('a', 5, 80), m('b', 2, 75)];
    expect(suggest(80.2, null, all), 'a');
  });

  test('an old second measurement is ignored, only the last one counts', () {
    final all = [m('a', 1, 70), m('a', 60, 80), m('b', 2, 75)];
    // 80 would match "a" if its old measurement counted.
    expect(suggest(80, null, all), 'b');
  });

  test('impedance breaks a weight tie', () {
    final all = [m('a', 1, 70, 400), m('b', 1, 70, 520)];
    expect(suggest(70, 510, all), 'b');
  });
}
