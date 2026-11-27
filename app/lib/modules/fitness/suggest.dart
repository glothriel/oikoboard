import 'dart:math' as math;

import 'models.dart';
import 'scale/scale_driver.dart';

const _recent = Duration(days: 30);

double _distance(ScaleReading reading, Measurement m) {
  final dw = (reading.weightKg - m.weightKg).abs();
  final di = reading.impedance != null && m.impedance != null
      ? (reading.impedance! - m.impedance!).abs() / 100
      : 0;
  return dw + di;
}

/// The member who most likely just stepped on the scale: the one whose last
/// two measurements (both from the last 30 days, else only the last one) are
/// closest to [reading] by |Δweight kg| + |Δimpedance|/100. With no data at
/// all, [fallbackMemberId] (the signed-in member).
String suggestMember({
  required ScaleReading reading,
  required Iterable<Measurement> all,
  required DateTime now,
  required String fallbackMemberId,
}) {
  final byMember = <String, List<Measurement>>{};
  for (final m in all) {
    (byMember[m.memberId] ??= []).add(m);
  }
  String? best;
  var bestScore = double.infinity;
  for (final MapEntry(:key, :value) in byMember.entries) {
    value.sort((a, b) => b.measuredAt.compareTo(a.measuredAt));
    var used = value.take(2).toList();
    if (used.length == 2 &&
        !used.every((m) => now.difference(m.measuredAt) <= _recent)) {
      used = [used.first];
    }
    final score = used.map((m) => _distance(reading, m)).reduce(math.min);
    if (score < bestScore) {
      bestScore = score;
      best = key;
    }
  }
  return best ?? fallbackMemberId;
}
