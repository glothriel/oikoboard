import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/modules/fitness/composition.dart';

BodyComposition _c(Sex sex, int age, double h, double w, double z) =>
    computeComposition(
      sex: sex,
      age: age,
      heightCm: h,
      weightKg: w,
      impedance: z,
    );

Matcher _near(double v) => closeTo(v, 0.001);

void main() {
  group('computeComposition', () {
    test('male, 30 y, 180 cm, 80 kg, 500 ohm', () {
      final r = _c(Sex.male, 30, 180, 80, 500);
      expect(r.bmi, _near(24.6914));
      expect(r.fatPct, _near(22.3151));
      expect(r.waterPct, _near(56.7100));
      expect(r.proteinPct, _near(15.1486));
      expect(r.boneKg, _near(3.1254));
      expect(r.muscleKg, _near(59.0225));
      expect(r.bmrKcal, _near(1790.86));
      expect(r.visceralFat, _near(10.7998));
    });

    test('female, 30 y, 165 cm, 60 kg, 520 ohm', () {
      final r = _c(Sex.female, 30, 165, 60, 520);
      expect(r.bmi, _near(22.0386));
      expect(r.fatPct, _near(28.7058));
      expect(r.waterPct, _near(52.0447));
      expect(r.proteinPct, _near(13.9024));
      expect(r.boneKg, _near(1.8607));
      expect(r.muscleKg, _near(40.9158));
      expect(r.bmrKcal, _near(1333.16));
      expect(r.visceralFat, _near(4.845));
    });

    test('Schofield brackets for men', () {
      const cases = [
        (2, 59.512, -30.4),
        (5, 22.706, 504.3),
        (15, 17.686, 658.2),
        (25, 15.057, 692.2),
        (40, 11.472, 873.1),
        (70, 11.711, 587.7),
      ];
      for (final (age, slope, constant) in cases) {
        final r = _c(Sex.male, age, 170, 60, 500);
        expect(r.bmrKcal, _near(slope * 60 + constant), reason: 'age $age');
      }
    });

    test('Schofield brackets for women', () {
      const cases = [
        (2, 58.317, -31.1),
        (5, 20.315, 485.9),
        (15, 13.384, 692.6),
        (25, 14.818, 486.6),
        (40, 8.126, 845.6),
        (70, 9.082, 658.5),
      ];
      for (final (age, slope, constant) in cases) {
        final r = _c(Sex.female, age, 160, 60, 500);
        expect(r.bmrKcal, _near(slope * 60 + constant), reason: 'age $age');
      }
    });

    test('bracket edges belong to the older bracket', () {
      expect(_c(Sex.male, 2, 170, 60, 500).bmrKcal, _near(59.512 * 60 - 30.4));
      expect(_c(Sex.male, 3, 170, 60, 500).bmrKcal, _near(22.706 * 60 + 504.3));
      expect(
        _c(Sex.male, 59, 170, 60, 500).bmrKcal,
        _near(11.472 * 60 + 873.1),
      );
      expect(
        _c(Sex.male, 60, 170, 60, 500).bmrKcal,
        _near(11.711 * 60 + 587.7),
      );
    });

    test('male visceral fat, both branches', () {
      // H < 1.6 W + 63
      expect(_c(Sex.male, 30, 180, 80, 500).visceralFat, _near(10.7998));
      // H >= 1.6 W + 63
      expect(_c(Sex.male, 70, 180, 70, 500).visceralFat, _near(14.41));
      expect(_c(Sex.male, 15, 170, 60, 500).visceralFat, _near(3.54));
    });

    test('female visceral fat, both branches', () {
      // W <= H/2 - 13
      expect(_c(Sex.female, 30, 165, 60, 520).visceralFat, _near(4.845));
      expect(_c(Sex.female, 15, 160, 50, 500).visceralFat, _near(1.58));
      // W > H/2 - 13
      expect(_c(Sex.female, 40, 165, 80, 520).visceralFat, _near(9.0253));
      expect(_c(Sex.female, 70, 160, 60, 500).visceralFat, _near(8.5));
    });

    test('visceral fat is clamped to 1..50', () {
      expect(_c(Sex.male, 40, 180, 50, 500).visceralFat, 1); // raw 0.01
      expect(_c(Sex.female, 5, 110, 18, 600).visceralFat, 1);
      expect(_c(Sex.male, 30, 20, 80, 1).visceralFat, 50);
    });

    test('LBM is capped at 98% of weight', () {
      // Uncapped LBM would be 78.4+: capped at 0.98 * 80 = 78.4
      final r = _c(Sex.male, 30, 180, 80, -100000);
      expect(r.fatPct, 5); // (W - LBM) / W = 2 %, clamped up to 5
      expect(r.proteinPct, _near(19.5 * 0.98));
      expect(r.waterPct, _near(0.73 * 95));
    });

    test('fat floor is 5 for men and 10 for women', () {
      expect(_c(Sex.male, 5, 110, 18, 600).fatPct, 5);
      expect(_c(Sex.female, 5, 110, 18, 600).fatPct, 10);
      expect(_c(Sex.female, 5, 110, 18, 600).waterPct, _near(65.7));
    });

    test('high impedance raises fat and clamps water at 35', () {
      final mid = _c(Sex.male, 30, 180, 80, 3000);
      expect(mid.fatPct, _near(43.5651));
      expect(mid.waterPct, _near(41.1975));
      final low = _c(Sex.female, 30, 165, 60, 3000);
      expect(low.fatPct, _near(52.3154));
      expect(low.waterPct, 35);
    });

    test('bone and muscle lower clamps', () {
      final r = _c(Sex.male, 2, 80, 10, 600);
      expect(r.boneKg, 0.5);
      expect(r.muscleKg, 10);
    });

    test('bone gets +0.1 above 2.2 kg and -0.1 otherwise', () {
      expect(_c(Sex.male, 30, 180, 80, 500).boneKg, _near(3.1254));
      expect(_c(Sex.female, 30, 165, 60, 520).boneKg, _near(1.8607));
    });

    test('BMR is clamped to at least 500', () {
      expect(_c(Sex.male, 2, 80, 5, 600).bmrKcal, 500);
    });
  });

  group('ageAt', () {
    final birth = DateTime(1990, 6, 15);
    test('the day before the birthday', () {
      expect(ageAt(birth, DateTime(2020, 6, 14)), 29);
    });
    test('on the birthday', () {
      expect(ageAt(birth, DateTime(2020, 6, 15)), 30);
    });
    test('after the birthday and in an earlier month', () {
      expect(ageAt(birth, DateTime(2020, 6, 16)), 30);
      expect(ageAt(birth, DateTime(2020, 1, 1)), 29);
      expect(ageAt(birth, DateTime(2020, 12, 31)), 30);
    });
    test('ignores the time of day', () {
      expect(ageAt(birth, DateTime(2020, 6, 15, 0, 1)), 30);
    });
  });
}
