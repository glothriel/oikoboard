// SyncClient reconnect behaviour against a fake in-process WebSocket server.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/core/api/sync_client.dart';

import 'support/fake_ws_server.dart';

void main() {
  late FakeServer server;
  setUp(() async => server = await FakeServer.start());
  tearDown(() => server.close());

  test('a silent connection is dropped and replaced', () async {
    // First connection says ready, sends one heartbeat and then goes quiet
    // without closing (half-open socket).
    server.behave = (n, ws) => readyThen(ws, () => ws.add('{"t":"ping"}'));
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

  test('a server without heartbeats (older version) is not dropped', () async {
    server.behave = (n, ws) => readyThen(ws);
    final client = SyncClient(
      server.uri,
      't',
      silenceTimeout: const Duration(seconds: 1),
    );
    addTearDown(client.dispose);

    await client.status.firstWhere((c) => c);
    await Future<void>.delayed(const Duration(seconds: 3));
    client.checkNow(); // e.g. the app resumed
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(server.connections, 1);
    expect(client.connected, isTrue);
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

  test('family.members: a snapshot, then an upsert and a remove', () async {
    Map<String, dynamic> row(String id, String name) => {
      'id': id,
      'name': name,
      'color': 0xFF1565C0,
      'has_account': true,
    };
    server.behave = (n, ws) => ws.listen((raw) {
      final msg = jsonDecode(raw as String) as Map;
      switch (msg['t']) {
        case 'auth':
          ws.add(jsonEncode({'t': 'ready'}));
        case 'sub':
          final sub = msg['id'];
          ws.add(
            jsonEncode({
              't': 'snapshot',
              'sub': sub,
              'seq': 1,
              'data': {
                'members': [row('a', 'Anna')],
              },
            }),
          );
          ws.add(
            jsonEncode({
              't': 'upsert',
              'sub': sub,
              'op': 'insert',
              'seq': 2,
              'entity': 'members',
              'id': 'b',
              'row': row('b', 'Bob'),
            }),
          );
          ws.add(
            jsonEncode({
              't': 'remove',
              'sub': sub,
              'op': 'delete',
              'seq': 3,
              'entity': 'members',
              'id': 'a',
              'row': row('a', 'Anna'),
            }),
          );
      }
    });
    final client = SyncClient(server.uri, 't');
    addTearDown(client.dispose);

    final names = <String>[];
    final sub = client
        .watch('family.members', const {}, (e, _) => e == 'members')
        .listen(
          (v) => names.add(v.rows('members').map((r) => r['name']).join(',')),
        );
    addTearDown(sub.cancel);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(names.last, 'Bob');
    expect(names, contains('Anna,Bob'));
  });
}
