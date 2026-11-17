import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'core/api/api_client.dart';
import 'core/backend.dart';
import 'core/mock/mock_store.dart';
import 'core/platform/browser.dart';
import 'core/session.dart';
import 'modules/calendar/repository.dart';
import 'modules/registry.dart';

/// Server address:
///   flutter run -d chrome                                  → http://(page host):8090 (debug)
///   flutter run -d chrome --dart-define=OIKO_API=mock      → in-memory data
///   flutter run --dart-define=OIKO_API=http://192.168.1.10:8090
/// Without OIKO_API: a release web build talks to its own origin (the server
/// serves the app); Android/desktop ask for the server on first start.
const _apiArg = String.fromEnvironment('OIKO_API');

/// A fixed backend, or null when the user chooses the server.
Backend? _fixedBackend() {
  if (_apiArg == 'mock') {
    final store = MockStore();
    for (final m in modules) {
      m.seedMock(store);
    }
    return MockBackend(store);
  }
  if (_apiArg.isNotEmpty) return ApiBackend(Uri.parse(_apiArg));
  if (kIsWeb) {
    return ApiBackend(
      kReleaseMode
          ? Uri.parse(Uri.base.origin)
          : Uri.parse('http://${Uri.base.host}:8090'),
    );
  }
  return null;
}

/// Web: link z zaproszeniem (?invite=) i powrót z logowania (?code=,
/// ?error=). Zapamiętuje/obsługuje je i czyści pasek adresu.
Future<void> _handleStartUrl(ProviderContainer c) async {
  final invites = c.read(pendingInviteProvider.notifier);
  await invites.set(await PendingInvite.load());
  if (!kIsWeb) return;
  final url = Uri.base;
  final q = url.queryParameters;
  if (q['invite'] case final token?) await invites.set(token);
  if (q.containsKey(calendarConnectParam)) {
    // Back from connecting a calendar account — finished by the calendar
    // screen once signed in.
    c.read(pendingCalendarConnectProvider.notifier).set(url);
  } else if (q.containsKey('code') || q.containsKey('error')) {
    try {
      final s = await c.read(authApiProvider).completeRedirect(url);
      c.read(sessionProvider.notifier).set(s);
    } catch (e) {
      c
          .read(loginMessageProvider.notifier)
          .set(e is ApiException ? e.message : '$e');
    }
  }
  const handled = {'invite', 'code', 'error', calendarConnectParam};
  if (q.keys.any(handled.contains)) {
    final rest = Uri(
      queryParameters: {...q}..removeWhere((k, _) => handled.contains(k)),
    ).query;
    replaceUrl(
      '${url.origin}${url.path}${rest.isEmpty ? '' : '?$rest'}'
      '${url.hasFragment ? '#${url.fragment}' : ''}',
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pl');
  Intl.defaultLocale = 'pl';

  final fixed = _fixedBackend();
  final container = ProviderContainer(
    overrides: [
      if (fixed != null)
        backendProvider.overrideWithValue(fixed)
      else
        serverChoiceProvider.overrideWithValue(true),
    ],
  );
  if (fixed == null) {
    await container
        .read(serverUrlProvider.notifier)
        .set(await ServerUrl.load());
  }
  try {
    if (container.read(serverChoiceProvider) &&
        container.read(serverUrlProvider) == null) {
      throw StateError('no server yet'); // the server screen comes first
    }
    await _handleStartUrl(container);
    // Zalogowany wcześniej? (token zapisany lokalnie)
    if (container.read(sessionProvider) == null) {
      container
          .read(sessionProvider.notifier)
          .set(await container.read(authApiProvider).restore());
    }
  } catch (_) {
    // serwer niedostępny — pokażemy ekran logowania z komunikatem
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const OikoboardApp(),
    ),
  );
}
