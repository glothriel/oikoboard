// SyncClient reconnect behaviour against a fake in-process WebSocket server.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/core/api/sync_client.dart';

import 'support/fake_ws_server.dart';

void main() {
  late FakeServer server;
  setUp(() async => server = await FakeServer.start());
  tearDown(() => server.close());

  test('a silent connection is dropped and replaced', () async {
    // First connection says ready and then goes quiet without closing
    // (half-open socket); the second one behaves.
    server.behave = (n, ws) => readyThen(ws);
    final client = SyncClient(
      server.uri,
      't',
      silenceTimeout: const Duration(seconds: 2),
    );
    addTearDown(client.dispose);

    await server.waitFor(1);
    await client.status.firstWhere((c) => c);
    await server.waitFor(2);
    expect(server.connections, 2);
  });

  test('heartbeats keep the connection alive', () async {
    server.behave = (n, ws) {
      Timer? t;
      readyThen(ws, () {
        t = Timer.periodic(
          const Duration(milliseconds: 500),
          (_) => ws.add('{"t":"ping"}'),
        );
      });
      ws.done.then((_) => t?.cancel());
    };
    final client = SyncClient(
      server.uri,
      't',
      silenceTimeout: const Duration(seconds: 2),
    );
    addTearDown(client.dispose);

    await client.status.firstWhere((c) => c);
    await Future<void>.delayed(const Duration(seconds: 4));
    expect(server.connections, 1);
    expect(client.connected, isTrue);
  });

  test('a connect that never gets ready is retried', () async {
    // First connection never answers auth.
    server.behave = (n, ws) => n == 1 ? ws.listen((_) {}) : readyThen(ws);
    final client = SyncClient(
      server.uri,
      't',
      readyTimeout: const Duration(seconds: 2),
    );
    addTearDown(client.dispose);

    await client.status
        .firstWhere((c) => c)
        .timeout(const Duration(seconds: 8));
    expect(server.connections, 2);
  });

  test('closed connections are retried with a capped backoff', () async {
    // Five connections get closed right away, the sixth stays.
    server.behave = (n, ws) => n <= 5 ? ws.close() : readyThen(ws);
    final client = SyncClient(
      server.uri,
      't',
      maxBackoff: const Duration(seconds: 1),
    );
    addTearDown(client.dispose);

    final sw = Stopwatch()..start();
    await client.status
        .firstWhere((c) => c)
        .timeout(const Duration(seconds: 10));
    // 0.5 + 1 + 1 + 1 + 1 s plus jitter; uncapped it would be 15.5 s.
    expect(sw.elapsed, lessThan(const Duration(seconds: 7)));
    expect(server.connections, 6);
  });

  test('checkNow leaves a fresh connection alone', () async {
    server.behave = (n, ws) => readyThen(ws);
    final client = SyncClient(server.uri, 't');
    addTearDown(client.dispose);

    await client.status.firstWhere((c) => c);
    client.checkNow();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.connections, 1);
  });
}
