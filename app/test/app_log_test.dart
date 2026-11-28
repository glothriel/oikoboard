import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/core/app_log.dart';

void main() {
  test('the ring buffer keeps the newest 500 entries', () {
    final log = AppLog(echo: false);
    for (var i = 0; i < 510; i++) {
      log.info('ble', 'm$i');
    }
    expect(log.buffered.length, 500);
    expect(log.buffered.first.msg, 'm10');
    expect(log.buffered.last.msg, 'm509');
  });

  test('entries wait while the sink refuses and flush on reconnect in 20s', () {
    final log = AppLog(echo: false);
    final batches = <List<Map<String, dynamic>>>[];
    var up = false;
    log.sink = (b) {
      if (!up) return false;
      batches.add(b);
      return true;
    };
    for (var i = 0; i < 45; i++) {
      log.debug('ble', 'm$i', {'n': i});
    }
    expect(batches, isEmpty);
    up = true;
    log.flush();
    expect(batches.map((b) => b.length), [20, 20, 5]);
    expect(log.buffered, isEmpty);
    expect(batches.first.first['msg'], 'm0');
    expect(batches.first.first['level'], 'debug');
    expect(batches.first.first['attrs'], {'n': 0, 'component': 'ble'});
  });

  test('connected: entries go out at once', () {
    final log = AppLog(echo: false);
    final sent = <Map<String, dynamic>>[];
    log.sink = (b) {
      sent.addAll(b);
      return true;
    };
    log.warn('ble', 'x');
    expect(sent.single['level'], 'warn');
    expect(log.buffered, isEmpty);
  });
}
