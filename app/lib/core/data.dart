import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/sync_client.dart';
import 'backend.dart';
import 'change.dart';
import 'session.dart';

/// REST client of the signed-in user (API mode only).
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

/// WebSocket of the signed-in user (API mode only).
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
  // Back from background/sleep: don't wait for the watchdog or backoff.
  final lifecycle = AppLifecycleListener(onResume: client.checkNow);
  ref.onDispose(lifecycle.dispose);
  ref.onDispose(client.dispose);
  return client;
});

/// Changes made by others (for notifications), regardless of backend.
final changeEventsProvider = StreamProvider<Change>((ref) {
  return switch (ref.watch(backendProvider)) {
    MockBackend(:final store) => store.changes,
    ApiBackend() => ref.watch(syncClientProvider).changes,
  };
});

/// Whether we are connected to the server (mock: always).
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
