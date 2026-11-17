import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/sync_client.dart';
import 'backend.dart';
import 'change.dart';
import 'session.dart';

/// Klient REST zalogowanego użytkownika (tylko tryb API).
final apiClientProvider = Provider<ApiClient>((ref) {
  final backend = ref.watch(backendProvider) as ApiBackend;
  final session = ref.watch(sessionProvider)!;
  final client = ApiClient(
    backend.baseUri,
    token: session.token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).logout(),
  );
  ref.onDispose(client.close);
  return client;
});

/// WebSocket zalogowanego użytkownika (tylko tryb API).
final syncClientProvider = Provider<SyncClient>((ref) {
  final backend = ref.watch(backendProvider) as ApiBackend;
  final session = ref.watch(sessionProvider)!;
  final base = backend.baseUri;
  final client = SyncClient(
    base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/v1/ws',
    ),
    session.token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).logout(),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Zmiany robione przez innych (do powiadomień), niezależnie od backendu.
final changeEventsProvider = StreamProvider<Change>((ref) {
  return switch (ref.watch(backendProvider)) {
    MockBackend(:final store) => store.changes,
    ApiBackend() => ref.watch(syncClientProvider).changes,
  };
});

/// Czy jesteśmy połączeni z serwerem (mock: zawsze).
final onlineProvider = StreamProvider<bool>((ref) async* {
  switch (ref.watch(backendProvider)) {
    case MockBackend():
      yield true;
    case ApiBackend():
      final sync = ref.watch(syncClientProvider);
      yield sync.connected;
      yield* sync.status;
  }
});
