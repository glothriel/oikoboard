// Data-layer test against a live server with dev login:
//   OIKO_DEV_LOGIN=1 go run ./cmd/oikoboard
//   flutter test test/live_server_test.dart
// Skipped if the server doesn't answer or has no dev login.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/core/api/api_client.dart';
import 'package:oikoboard/core/api/sync_client.dart';
import 'package:oikoboard/core/sync/outbox.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';

final base = Uri.parse(
  const String.fromEnvironment(
    'OIKO_API',
    defaultValue: 'http://localhost:8090',
  ),
);

Future<String> devLogin(String email) async {
  final res =
      await ApiClient(base).post('/auth/dev/login', {'email': email}) as Map;
  return res['token'] as String;
}

ApiTodoRepository repoFor(String token) {
  final api = ApiClient(base, token: token);
  final outbox = Outbox(
    send: (m) => api.mutate(m.method, m.path, m.body, mutationId: m.id),
  );
  return ApiTodoRepository(
    SyncClient(
      base.replace(scheme: 'ws', path: '/api/v1/ws'),
      token,
      outbox: outbox,
    ),
    outbox,
    actorId: '',
  );
}

Future<T> firstWhere<T>(Stream<T> s, bool Function(T) test) =>
    s.firstWhere(test).timeout(const Duration(seconds: 5));

void main() {
  var up = true;
  setUpAll(() async {
    try {
      final cfg = await ApiClient(base).get('/auth/config') as Map;
      up = cfg['dev_login'] == true;
    } catch (_) {
      up = false;
    }
  });

  test("Dad's change reaches Ola live, only in the right views", () async {
    if (!up) {
      markTestSkipped('server unreachable or without OIKO_DEV_LOGIN=1');
      return;
    }
    // Dad creates a new family and invites Ola with a link.
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tataToken = await devLogin('tata-$ts@example.test');
    final tataApi = ApiClient(base, token: tataToken);
    await tataApi.post('/households', {
      'name': 'Test $ts',
      'member_name': 'Tata',
    });
    final invite = await tataApi.post('/invites', {}) as Map;
    final olaToken = await devLogin('ola-$ts@example.test');
    await ApiClient(
      base,
      token: olaToken,
    ).post('/invites/${invite['token']}/accept', {'name': 'Ola'});

    final tata = repoFor(tataToken);
    final ola = repoFor(olaToken);
    await tata.addList('Zakupy', color: 0xFF4CAF50);

    final lists = await firstWhere<List<TodoList>>(
      ola.watchLists(),
      (l) => l.any((l) => l.name == 'Zakupy'),
    );
    final zakupy = lists.firstWhere((l) => l.name == 'Zakupy');

    // Ola has open: the shopping list and “not done”.
    final olaList = ola.watchListItems(zakupy.id).asBroadcastStream();
    final olaOpen = ola.watchOpenItems().asBroadcastStream();
    await olaList.first; // snapshots
    await olaOpen.first;

    final title = 'Test ${DateTime.now().millisecondsSinceEpoch}';
    final listSeen = firstWhere<List<TodoItem>>(
      olaList,
      (l) => l.any((i) => i.title == title),
    );
    final openSeen = firstWhere<List<TodoItem>>(
      olaOpen,
      (l) => l.any((i) => i.title == title),
    );
    final item = await tata.addItem(zakupy.id, title);
    await listSeen;
    await openSeen;

    // Checking off: it stays in the list as done and disappears from “not done”.
    final doneSeen = firstWhere<List<TodoItem>>(
      olaList,
      (l) => l.any((i) => i.id == item.id && i.done),
    );
    final goneFromOpen = firstWhere<List<TodoItem>>(
      olaOpen,
      (l) => l.every((i) => i.id != item.id),
    );
    await tata.updateItem(item, item.toggled());
    await doneSeen;
    await goneFromOpen;

    final deleted = firstWhere<List<TodoItem>>(
      olaList,
      (l) => l.every((i) => i.id != item.id),
    );
    await tata.deleteItem(item);
    await deleted;

    // Dad's own write leaves the overlay when its change comes back over
    // the WebSocket — well before the outbox's fallback timeout.
    final tataLists = tata.watchLists().asBroadcastStream();
    await tataLists.first;
    await tata.updateList(zakupy, zakupy.copyWith(name: 'Sklep'));
    await firstWhere<List<TodoList>>(
      tataLists,
      (l) => l.any((l) => l.name == 'Sklep'),
    );
    final sw = Stopwatch()..start();
    // (earlier writes had no open view to come back through — they wait
    // for the timeout, so look at the rename only)
    while (tata.outbox.overlay.any((m) => m.fields['name'] == 'Sklep')) {
      expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
}
