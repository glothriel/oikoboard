/// Body composition from weight, impedance and a member's profile
/// (Siri, Pace & Rathbun, Wang, Schofield and Janssen equations).
library;

enum Sex { male, female }

class BodyComposition {
  const BodyComposition({
    required this.bmi,
    required this.fatPct,
    required this.waterPct,
    required this.proteinPct,
    required this.boneKg,
    required this.muscleKg,
    required this.bmrKcal,
    required this.visceralFat,
  });

  final double bmi;
  final double fatPct;
  final double waterPct;
  final double proteinPct;
  final double boneKg;
  final double muscleKg;
  final double bmrKcal;
  final double visceralFat;
}

/// Schofield (slope, constant) per age bracket: <3, <10, <18, <30, <60, 60+.
const _schofieldMale = [
  (59.512, -30.4),
  (22.706, 504.3),
  (17.686, 658.2),
  (15.057, 692.2),
  (11.472, 873.1),
  (11.711, 587.7),
];
const _schofieldFemale = [
  (58.317, -31.1),
  (20.315, 485.9),
  (13.384, 692.6),
  (14.818, 486.6),
  (8.126, 845.6),
  (9.082, 658.5),
];
const _schofieldAgeLimits = [3, 10, 18, 30, 60];

/// Computes the composition. Callers skip it without impedance or a profile.
BodyComposition computeComposition({
  required Sex sex,
  required int age,
  required double heightCm,
  required double weightKg,
  required double impedance,
}) {
  final h = heightCm;
  final w = weightKg;
  final male = sex == Sex.male;

  final lc =
      0.09058 * h * h / 100 +
      0.32 * w +
      12.226 -
      0.0068 * impedance -
      0.0542 * age;
  var lbm = male ? lc : lc * 0.84;
  if (lbm > 0.98 * w) lbm = 0.98 * w;

  final fat = ((w - lbm) / w * 100).clamp(male ? 5.0 : 10.0, 75.0);
  final water = (0.73 * (100 - fat)).clamp(35.0, 73.0);
  final protein = (19.5 * lbm / w).clamp(5.0, 32.0);

  final b = male ? 0.18016894 : 0.245691014;
  var bone = -(b - 0.05158 * lbm);
  bone += bone > 2.2 ? 0.1 : -0.1;
  bone = bone.clamp(0.5, 8.0);

  final muscle = (w - fat * w / 100 - bone).clamp(10.0, 120.0);

  var bracket = _schofieldAgeLimits.indexWhere((limit) => age < limit);
  if (bracket < 0) bracket = _schofieldAgeLimits.length;
  final (slope, constant) = (male ? _schofieldMale : _schofieldFemale)[bracket];
  final bmr = (slope * w + constant).clamp(500.0, 5000.0);

  final double visceral;
  if (male) {
    visceral = h < 1.6 * w + 63
        ? 0.15 * age + 305 * w / (0.0826 * h * h - 0.4 * h + 48) - 2.9
        : 0.15 * age + w * (0.765 - 0.0015 * h) - 0.143 * h - 5;
  } else {
    visceral = w <= h / 2 - 13
        ? 0.07 * age + w * (0.691 - 0.0024 * h) - 0.027 * h - 10.5
        : 0.07 * age + 500 * w / (1.45 * h + 0.1158 * h * h - 120) - 6;
  }

  return BodyComposition(
    bmi: w / ((h / 100) * (h / 100)),
    fatPct: fat,
    waterPct: water,
    proteinPct: protein,
    boneKg: bone,
    muscleKg: muscle,
    bmrKcal: bmr,
    visceralFat: visceral.clamp(1.0, 50.0),
  );
}

/// Whole years between [birth] and [at] (calendar dates, time ignored).
int ageAt(DateTime birth, DateTime at) {
  var years = at.year - birth.year;
  if (at.month < birth.month ||
      (at.month == birth.month && at.day < birth.day)) {
    years--;
  }
  return years;
}
