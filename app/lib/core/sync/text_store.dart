import 'package:shared_preferences/shared_preferences.dart';

/// One piece of text kept on the device between app starts.
abstract interface class TextStore {
  Future<String?> load();
  Future<void> save(String data);
}

class MemoryTextStore implements TextStore {
  MemoryTextStore([this.data]);
  String? data;

  @override
  Future<String?> load() async => data;

  @override
  Future<void> save(String data) async => this.data = data;
}

/// Shared preferences (localStorage on the web). Failures (no storage) are
/// ignored: the data then lives only as long as the app.
class PrefsTextStore implements TextStore {
  PrefsTextStore(this.key);
  final String key;

  @override
  Future<String?> load() async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String data) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, data);
    } catch (_) {}
  }
}
