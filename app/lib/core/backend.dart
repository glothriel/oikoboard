import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/http_auth_api.dart';
import 'mock/mock_auth_api.dart';
import 'mock/mock_store.dart';
import 'session.dart';

/// Skąd aplikacja bierze dane: z prawdziwego serwera albo z mocka w pamięci.
/// Wybierane w main.dart (`--dart-define=OIKO_API=...`).
sealed class Backend {
  const Backend();
  AuthApi authApi();
}

class MockBackend extends Backend {
  const MockBackend(this.store);
  final MockStore store;

  @override
  AuthApi authApi() => MockAuthApi();
}

class ApiBackend extends Backend {
  const ApiBackend(this.baseUri);
  final Uri baseUri;

  @override
  AuthApi authApi() => HttpAuthApi(baseUri);
}

/// The server the app talks to when the user picks it (Android/desktop: each
/// family runs its own). Saved on the device. main.dart overrides
/// [backendProvider] instead when the server is fixed (web, --dart-define).
class ServerUrl extends Notifier<Uri?> {
  ServerUrl([this._initial]);
  final Uri? _initial;
  static const _key = 'oiko.server';

  @override
  Uri? build() => _initial;

  static Future<Uri?> load() async {
    final s = (await SharedPreferences.getInstance()).getString(_key);
    return s == null ? null : Uri.parse(s);
  }

  Future<void> set(Uri? url) async {
    final prefs = await SharedPreferences.getInstance();
    url == null
        ? await prefs.remove(_key)
        : await prefs.setString(_key, '$url');
    state = url;
  }
}

final serverUrlProvider = NotifierProvider<ServerUrl, Uri?>(ServerUrl.new);

/// Whether the user chooses the server (main.dart turns it on when the
/// server isn't fixed).
final serverChoiceProvider = Provider<bool>((ref) => false);

final backendProvider = Provider<Backend>((ref) {
  final url = ref.watch(serverUrlProvider);
  if (url == null) throw StateError('no server chosen');
  return ApiBackend(url);
});

/// Normalizes what the user typed: adds https:// (http:// for local
/// addresses), drops paths. Null when it isn't an address.
Uri? parseServerUrl(String text) {
  var t = text.trim();
  if (t.isEmpty) return null;
  if (!t.contains('://')) {
    final local = RegExp(
      r'^(localhost|127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)',
    ).hasMatch(t);
    t = '${local ? 'http' : 'https'}://$t';
  }
  final u = Uri.tryParse(t);
  if (u == null ||
      u.host.isEmpty ||
      !(u.scheme == 'http' || u.scheme == 'https')) {
    return null;
  }
  return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null);
}
