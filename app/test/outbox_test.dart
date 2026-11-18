// Outbox delivery rules and the optimistic overlay in SyncClient views.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/core/api/api_client.dart';
import 'package:oikoboard/core/api/sync_client.dart';
import 'package:oikoboard/core/sync/outbox.dart';
import 'package:oikoboard/core/sync/text_store.dart';
import 'package:oikoboard/core/sync/view_cache.dart';
import 'package:oikoboard/modules/calendar/models.dart';
import 'package:oikoboard/modules/calendar/repository.dart';

import 'support/fake_ws_server.dart';

/// The REST side of a server the test controls.
class FakeSender {
  final sent = <Mutation>[];

  /// What the next request does: null = succeed, an exception = throw it.
  Object? Function(Mutation m) behave = (_) => null;

  Future<void> call(Mutation m) async {
    sent.add(m);
    await Future<void>.delayed(Duration.zero);
    if (behave(m) case final Object e) throw e;
  }
}

Mutation patch(String id, Map<String, dynamic> fields) =>
    Mutation.patch('/todo/items/$id', 'todo_items', id, fields);

Future<void> settle([int ms = 50]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  group('Outbox', () {
    test('offline: queued in order, sent when the server is back', () async {
      final server = FakeSender()
        ..behave = (_) => const SocketException('offline');
      final outbox = Outbox(
        send: server.call,
        maxBackoff: const Duration(milliseconds: 100),
      );
      addTearDown(outbox.dispose);

      outbox.enqueue(patch('a', {'title': '1'}));
      outbox.enqueue(patch('a', {'title': '2'}));
      await settle(200);
      expect(outbox.pending, hasLength(2));
      expect(server.sent.every((m) => m.fields['title'] == '1'), isTrue);

      server.sent.clear();
      server.behave = (_) => null;
      outbox.kick();
      await settle();
      expect(outbox.pending, isEmpty);
      expect(server.sent.map((m) => m.fields['title']), ['1', '2']);
    });

    test('a 4xx goes to the dead letter, the queue moves on', () async {
      final server = FakeSender()
        ..behave = (m) =>
            m.entityId == 'gone' ? ApiException(404, 'not found') : null;
      final outbox = Outbox(send: server.call);
      addTearDown(outbox.dispose);
      final failures = <FailedMutation>[];
      outbox.failures.listen(failures.add);

      outbox.enqueue(patch('gone', {'title': 'x'}));
      outbox.enqueue(patch('b', {'title': 'y'}));
      await settle();
      expect(outbox.pending, isEmpty);
      expect(outbox.failed.single.status, 404);
      expect(failures.single.mutation.entityId, 'gone');
      expect(server.sent.map((m) => m.entityId), ['gone', 'b']);
      // rolled back: not in the overlay
      expect(outbox.overlay.map((m) => m.entityId), ['b']);

      server.behave = (_) => null;
      outbox.retry(outbox.failed.single);
      await settle();
      expect(outbox.failed, isEmpty);
    });

    test('5xx is retried; a delete that is already gone succeeds', () async {
      var calls = 0;
      final server = FakeSender()
        ..behave = (m) {
          if (m.kind == MutationKind.delete) return ApiException(404, '');
          return ++calls < 3 ? ApiException(502, 'bad gateway') : null;
        };
      final outbox = Outbox(
        send: server.call,
        maxBackoff: const Duration(milliseconds: 50),
      );
      addTearDown(outbox.dispose);

      outbox.enqueue(patch('a', {'title': 'x'}));
      outbox.enqueue(Mutation.delete('/todo/items/b', 'todo_items', 'b'));
      await settle(500);
      expect(calls, 3);
      expect(outbox.pending, isEmpty);
      expect(outbox.failed, isEmpty);
    });

    test('survives a restart', () async {
      final storage = MemoryTextStore();
      final first = Outbox(
        send: (_) async => throw const SocketException('offline'),
        storage: storage,
      );
      first.enqueue(patch('a', {'done': true}));
      await settle();
      first.dispose();

      final server = FakeSender();
      final second = Outbox(send: server.call, storage: storage);
      addTearDown(second.dispose);
      await settle();
      expect(server.sent.single.fields, {'done': true});
      expect(second.pending, isEmpty);
    });

    test('a sent mutation stays in the overlay until its echo', () async {
      final outbox = Outbox(
        send: FakeSender().call,
        echoTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(outbox.dispose);
      final a = patch('a', {'title': 'x'});
      final b = patch('b', {'title': 'y'});
      outbox.enqueue(a);
      outbox.enqueue(b);
      await settle();
      expect(outbox.overlay, hasLength(2));
      outbox.confirm(a.id);
      expect(outbox.overlay.single.id, b.id);
      await settle(400); // no echo for b: dropped after the timeout
      expect(outbox.overlay, isEmpty);
    });
  });

  test('changedFields keeps only what differs', () {
    expect(
      changedFields(
        {
          'title': 'a',
          'done': false,
          'ids': ['x'],
        },
        {
          'title': 'a',
          'done': true,
          'ids': ['x'],
        },
        ['title', 'done', 'ids'],
      ),
      {'done': true},
    );
  });

  test('mirroredIds matches the server (calendar/mirror.go)', () {
    // Reference values computed by the Go mirrorID/occurrenceID.
    CalendarEvent draft({bool recurring = false, bool allDay = false}) =>
        CalendarEvent(
          id: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
          calendarId: '11111111-2222-3333-4444-555555555555',
          title: 't',
          start: allDay
              ? DateTime(2026, 11, 18)
              : DateTime.utc(2026, 11, 18, 9, 30).toLocal(),
          end: allDay
              ? DateTime(2026, 11, 19)
              : DateTime.utc(2026, 11, 18, 10, 30).toLocal(),
          allDay: allDay,
          memberIds: const [],
          recurrence: recurring ? const ['RRULE:FREQ=DAILY'] : const [],
        );
    const event = '73379acb-f5d4-5b5a-bcd1-2c47a82c8f09';
    expect(mirroredIds(draft())['id'], event);
    expect(
      mirroredIds(draft(recurring: true))['id'],
      'd0341873-3689-5ea3-8baf-60553a2def6d',
    );
    expect(
      mirroredIds(draft(recurring: true, allDay: true))['id'],
      'a9a11999-9cba-5f88-8b11-a7e531233e75',
    );
    expect(mirroredIds(draft(recurring: true))['event_id'], event);
  });

  group('overlay', () {
    late FakeServer server;
    late FakeSender sender;
    late Outbox outbox;
    late SyncClient client;
    final item = {'id': 'i1', 'list_id': 'L', 'title': 'Milk', 'done': false};

    setUp(() async {
      server = await FakeServer.start();
      server.behave = (n, ws) => ws.listen((raw) {
        final msg = jsonDecode(raw as String) as Map;
        switch (msg['t']) {
          case 'auth':
            ws.add(jsonEncode({'t': 'ready'}));
          case 'sub':
            final open = msg['view'] == 'todo.open';
            ws.add(
              jsonEncode({
                't': 'snapshot',
                'sub': msg['id'],
                'seq': 1,
                'data': {
                  'todo_items': [item],
                  if (!open)
                    'todo_comments': [
                      {'id': 'c1', 'item_id': 'i1', 'body': 'hi'},
                    ],
                },
              }),
            );
        }
      });
      sender = FakeSender()..behave = (_) => const SocketException('offline');
      outbox = Outbox(send: sender.call);
      client = SyncClient(server.uri, 't', outbox: outbox);
    });

    tearDown(() async {
      client.dispose();
      outbox.dispose();
      await server.close();
    });

    Stream<ViewData> open() => client.watch(
      'todo.open',
      const {},
      (e, r) => e == 'todo_items' && r['done'] != true,
    );

    test('pending changes show at once and follow the view filter', () async {
      final views = <ViewData>[];
      open().listen(views.add);
      await settle(200);
      expect(views.last.rows('todo_items').single['title'], 'Milk');

      outbox.enqueue(patch('i1', {'title': 'Oat milk'}));
      await settle();
      expect(views.last.rows('todo_items').single['title'], 'Oat milk');

      final bread = {'id': 'i2', 'list_id': 'L', 'title': 'Bread'};
      outbox.enqueue(Mutation.create('/todo/items', 'todo_items', bread));
      await settle();
      expect(views.last.rows('todo_items'), hasLength(2));

      // checked off → no longer matches todo.open
      outbox.enqueue(patch('i1', {'done': true}));
      await settle();
      expect(views.last.rows('todo_items').map((r) => r['id']), ['i2']);
    });

    test('a delete removes cascaded rows too', () async {
      final views = <ViewData>[];
      client.watch('todo.list', const {'list_id': 'L'}).listen(views.add);
      await settle(200);
      expect(views.last.rows('todo_comments'), hasLength(1));
      outbox.enqueue(
        Mutation.delete(
          '/todo/items/i1',
          'todo_items',
          'i1',
          cascade: const [('todo_comments', 'item_id')],
        ),
      );
      await settle();
      expect(views.last.rows('todo_items'), isEmpty);
      expect(views.last.rows('todo_comments'), isEmpty);
    });

    test('the echo replaces the overlay', () async {
      final views = <ViewData>[];
      open().listen(views.add);
      await settle(200);
      sender.behave = (_) => null;
      final m = patch('i1', {'title': 'Oat milk'});
      outbox.enqueue(m);
      await settle();
      expect(outbox.overlay, hasLength(1)); // sent, waiting for the echo

      server.sockets.last.add(
        jsonEncode({
          't': 'upsert',
          'sub': 's0',
          'op': 'update',
          'seq': 2,
          'entity': 'todo_items',
          'id': 'i1',
          'row': {...item, 'title': 'Oat milk'},
          'mutation': m.id,
        }),
      );
      await settle();
      expect(outbox.overlay, isEmpty);
      expect(views.last.rows('todo_items').single['title'], 'Oat milk');
    });

    test('a rejected change rolls back', () async {
      final views = <ViewData>[];
      open().listen(views.add);
      await settle(200);
      sender.behave = (_) => ApiException(409, 'conflict');
      outbox.enqueue(patch('i1', {'title': 'Oat milk'}));
      await settle();
      expect(views.last.rows('todo_items').single['title'], 'Milk');
      expect(outbox.failed, hasLength(1));
    });
  });

  test('the last snapshot is shown when started offline', () async {
    final storage = MemoryTextStore(
      jsonEncode({
        viewCacheKey('todo.open', const {}): {
          'todo_items': {
            'i1': {'id': 'i1', 'title': 'Milk'},
          },
        },
      }),
    );
    // nothing listens on this port
    final client = SyncClient(
      Uri.parse('ws://127.0.0.1:9/'),
      't',
      cache: ViewCache(storage),
    );
    addTearDown(client.dispose);
    final first = await client
        .watch('todo.open')
        .first
        .timeout(const Duration(seconds: 2));
    expect(first.rows('todo_items').single['title'], 'Milk');
  });
}
