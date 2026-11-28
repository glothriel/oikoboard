import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/modules/fitness/scale/registry.dart';
import 'package:oikoboard/modules/fitness/scale/saved_scale.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('nothing saved by default', () async {
    expect(await SavedScale.load(), isNull);
  });

  test('save, load and forget round-trip', () async {
    await const SavedScale(
      remoteId: 'AA:BB:CC:DD:EE:FF',
      driverId: 'mi_scale2',
      name: 'MIBFS',
    ).save();
    final s = await SavedScale.load();
    expect(s?.remoteId, 'AA:BB:CC:DD:EE:FF');
    expect(s?.driverId, 'mi_scale2');
    expect(s?.name, 'MIBFS');
    await SavedScale.clear();
    expect(await SavedScale.load(), isNull);
  });

  test('an unreadable value counts as nothing saved', () async {
    SharedPreferences.setMockInitialValues({'fitness.scale.paired': '{oops'});
    expect(await SavedScale.load(), isNull);
    SharedPreferences.setMockInitialValues({'fitness.scale.paired': '[1]'});
    expect(await SavedScale.load(), isNull);
  });

  test('driverById finds a driver or null', () {
    final id = scaleDrivers.first.id;
    expect(driverById(id), same(scaleDrivers.first));
    expect(driverById('nope'), isNull);
  });
}
