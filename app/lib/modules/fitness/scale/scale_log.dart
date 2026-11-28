import '../../../core/app_log.dart';

/// Lower-case hex of [bytes], space separated (`01 ff 0a`).
String hex(List<int> bytes) =>
    bytes.map((b) => (b & 0xff).toRadixString(16).padLeft(2, '0')).join(' ');

/// The BLE session's view of [AppLog]: every entry has the source `scale`.
class ScaleLog {
  ScaleLog(this._log);

  final AppLog _log;

  static const source = 'scale';

  void debug(String msg, [Map<String, Object?>? attrs]) =>
      _log.debug(source, msg, attrs);
  void info(String msg, [Map<String, Object?>? attrs]) =>
      _log.info(source, msg, attrs);
  void warn(String msg, [Map<String, Object?>? attrs]) =>
      _log.warn(source, msg, attrs);
}
