import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/sync_client.dart';
import 'backend.dart';
import 'change.dart';
import 'session.dart';
import 'sync/outbox.dart';
import 'sync/text_store.dart';
import 'sync/view_cache.dart';

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

/// Device storage key prefix of the signed-in member on this server.
String _storeKey(Ref ref, String what) {
  final backend = ref.watch(backendProvider) as ApiBackend;
  final member = ref.watch(sessionProvider)!.memberId;
  return 'oiko.$what.${backend.baseUri}.$member';
}

/// Writes waiting for the server, and the ones it rejected (API mode only;
/// null in mock mode, where writes apply at once).
final outboxProvider = Provider<Outbox?>((ref) {
  if (ref.watch(backendProvider) is! ApiBackend) return null;
  final api = ref.watch(apiClientProvider);
  final outbox = Outbox(
    send: (m) => api.mutate(m.method, m.path, m.body, mutationId: m.id),
    storage: PrefsTextStore(_storeKey(ref, 'outbox')),
  );
  ref.onDispose(outbox.dispose);
  return outbox;
});

/// The outbox's state, for the UI.
final outboxStateProvider =
    StreamProvider<({int pending, List<FailedMutation> failed})>((ref) async* {
      final outbox = ref.watch(outboxProvider);
      if (outbox == null) {
        yield (pending: 0, failed: const []);
        return;
      }
      yield (pending: outbox.pending.length, failed: outbox.failed);
      await for (final _ in outbox.changes) {
        yield (pending: outbox.pending.length, failed: outbox.failed);
      }
    });

/// WebSocket of the signed-in user (API mode only).
final syncClientProvider = Provider<SyncClient>((ref) {
  final backend = ref.watch(backendProvider) as ApiBackend;
  final session = ref.watch(sessionProvider)!;
  final outbox = ref.watch(outboxProvider);
  final base = backend.baseUri;
  final client = SyncClient(
    base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/v1/ws',
    ),
    session.token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).logout(),
    outbox: outbox,
    // key starts with ViewCache.keyPrefix — logout clears it
    cache: ViewCache(PrefsTextStore(_storeKey(ref, 'views'))),
  );
  // Connected again: send what's queued without waiting for the retry timer.
  final status = client.status.listen((up) {
    if (up) outbox?.kick();
  });
  // Back from background/sleep: don't wait for the watchdog or backoff.
  final lifecycle = AppLifecycleListener(onResume: client.checkNow);
  ref.onDispose(lifecycle.dispose);
  ref.onDispose(status.cancel);
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
