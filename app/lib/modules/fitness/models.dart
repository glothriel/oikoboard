import '../../core/api/api_client.dart'
    show fromApiDate, fromApiTime, toApiDate, toApiTime;
import 'composition.dart';

const _unset = Object();

double? _num(Object? v) => (v as num?)?.toDouble();

/// One weigh-in. The composition fields are null for a weight-only reading.
class Measurement {
  const Measurement({
    required this.id,
    required this.memberId,
    required this.measuredAt,
    required this.weightKg,
    required this.source,
    required this.createdAt,
    this.impedance,
    this.lbmKg,
    this.fatPct,
    this.waterPct,
    this.proteinPct,
    this.boneKg,
    this.muscleKg,
    this.bmrKcal,
    this.visceralFat,
    this.bmi,
  });

  static const sourceScale = 'scale';
  static const sourceManual = 'manual';

  final String id;
  final String memberId;
  final DateTime measuredAt;
  final double weightKg;

  /// Ω; null when not measured.
  final int? impedance;
  final double? lbmKg;
  final double? fatPct;
  final double? waterPct;
  final double? proteinPct;
  final double? boneKg;
  final double? muscleKg;
  final double? bmrKcal;
  final double? visceralFat;
  final double? bmi;

  /// `scale` or `manual`.
  final String source;
  final DateTime createdAt;

  bool get hasComposition => fatPct != null;

  factory Measurement.fromJson(Map<String, dynamic> j) => Measurement(
    id: j['id'] as String,
    memberId: j['member_id'] as String,
    measuredAt: fromApiTime(j['measured_at'])!,
    weightKg: _num(j['weight_kg'])!,
    impedance: (j['impedance'] as num?)?.toInt(),
    lbmKg: _num(j['lbm_kg']),
    fatPct: _num(j['fat_pct']),
    waterPct: _num(j['water_pct']),
    proteinPct: _num(j['protein_pct']),
    boneKg: _num(j['bone_kg']),
    muscleKg: _num(j['muscle_kg']),
    bmrKcal: _num(j['bmr_kcal']),
    visceralFat: _num(j['visceral_fat']),
    bmi: _num(j['bmi']),
    source: j['source'] as String? ?? sourceManual,
    createdAt: fromApiTime(j['created_at']) ?? DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'member_id': memberId,
    'measured_at': toApiTime(measuredAt),
    'weight_kg': weightKg,
    'impedance': impedance,
    'lbm_kg': lbmKg,
    'fat_pct': fatPct,
    'water_pct': waterPct,
    'protein_pct': proteinPct,
    'bone_kg': boneKg,
    'muscle_kg': muscleKg,
    'bmr_kcal': bmrKcal,
    'visceral_fat': visceralFat,
    'bmi': bmi,
    'source': source,
    'created_at': toApiTime(createdAt),
  };

  /// The POST body: the row without server-owned fields.
  Map<String, dynamic> toBody() => toJson()..remove('created_at');

  /// Nullable fields can be cleared by passing `null` explicitly.
  Measurement copyWith({
    DateTime? measuredAt,
    double? weightKg,
    Object? impedance = _unset,
    Object? lbmKg = _unset,
    Object? fatPct = _unset,
    Object? waterPct = _unset,
    Object? proteinPct = _unset,
    Object? boneKg = _unset,
    Object? muscleKg = _unset,
    Object? bmrKcal = _unset,
    Object? visceralFat = _unset,
    Object? bmi = _unset,
  }) => Measurement(
    id: id,
    memberId: memberId,
    measuredAt: measuredAt ?? this.measuredAt,
    weightKg: weightKg ?? this.weightKg,
    impedance: identical(impedance, _unset)
        ? this.impedance
        : impedance as int?,
    lbmKg: identical(lbmKg, _unset) ? this.lbmKg : lbmKg as double?,
    fatPct: identical(fatPct, _unset) ? this.fatPct : fatPct as double?,
    waterPct: identical(waterPct, _unset) ? this.waterPct : waterPct as double?,
    proteinPct: identical(proteinPct, _unset)
        ? this.proteinPct
        : proteinPct as double?,
    boneKg: identical(boneKg, _unset) ? this.boneKg : boneKg as double?,
    muscleKg: identical(muscleKg, _unset) ? this.muscleKg : muscleKg as double?,
    bmrKcal: identical(bmrKcal, _unset) ? this.bmrKcal : bmrKcal as double?,
    visceralFat: identical(visceralFat, _unset)
        ? this.visceralFat
        : visceralFat as double?,
    bmi: identical(bmi, _unset) ? this.bmi : bmi as double?,
    source: source,
    createdAt: createdAt,
  );
}

/// A member's data for the composition formulas; [id] is the member id.
class FitnessProfile {
  const FitnessProfile({
    required this.id,
    required this.sex,
    required this.birthDate,
    required this.heightCm,
  });

  final String id;
  final Sex sex;
  final DateTime birthDate;
  final double heightCm;

  /// Whole years on [today].
  int ageOn(DateTime today) {
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  factory FitnessProfile.fromJson(Map<String, dynamic> j) => FitnessProfile(
    id: j['id'] as String,
    sex: Sex.values.byName(j['sex'] as String),
    birthDate: fromApiDate(j['birth_date'])!,
    heightCm: _num(j['height_cm'])!,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'sex': sex.name,
    'birth_date': toApiDate(birthDate),
    'height_cm': heightCm,
  };

  FitnessProfile copyWith({Sex? sex, DateTime? birthDate, double? heightCm}) =>
      FitnessProfile(
        id: id,
        sex: sex ?? this.sex,
        birthDate: birthDate ?? this.birthDate,
        heightCm: heightCm ?? this.heightCm,
      );
}
