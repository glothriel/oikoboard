import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/l10n/app_localizations.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';
import 'package:oikoboard/modules/todo/todo_screen.dart';

Widget _row(TodoItem item) => ProviderScope(
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: TodoItemTile(item: item, onDismissed: () {}),
    ),
  ),
);

void main() {
  late MockStore store;
  late MockTodoRepository repo;
  late TodoList list;

  setUp(() async {
    store = MockStore(latency: Duration.zero);
    repo = MockTodoRepository(store, actorId: 'm1');
    list = await repo.addList('Home', color: 0xFF5C6BC0);
  });

  Future<TodoItem> reload(TodoItem i) async =>
      (await repo.watchListItems(list.id).first).singleWhere(
        (x) => x.id == i.id,
      );

  testWidgets('a row shows only the indicators that apply', (tester) async {
    final base = TodoItem(
      id: 'a',
      listId: 'l',
      title: 'Plain',
      done: false,
      createdAt: DateTime(2026),
    );
    await tester.pumpWidget(_row(base));
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
    expect(find.byIcon(Icons.repeat), findsNothing);

    await tester.pumpWidget(
      _row(
        TodoItem(
          id: 'b',
          listId: 'l',
          title: 'Commented',
          done: false,
          createdAt: DateTime(2026),
          commentCount: 2,
        ),
      ),
    );
    expect(find.byIcon(Icons.forum_outlined), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsNothing);

    await tester.pumpWidget(
      _row(
        TodoItem(
          id: 'c',
          listId: 'l',
          title: 'Recurring',
          done: false,
          createdAt: DateTime(2026),
          occurrenceDate: DateTime(2026, 3, 1),
        ),
      ),
    );
    expect(find.byIcon(Icons.repeat), findsOneWidget);
    expect(find.byIcon(Icons.forum_outlined), findsNothing);
  });

  test('adding and deleting a comment keeps the count (mock)', () async {
    final item = await repo.addItem(list.id, 'Tickets');
    expect((await reload(item)).commentCount, 0);

    await repo.addComment(item.id, 'one');
    await repo.addComment(item.id, 'two');
    expect((await reload(item)).commentCount, 2);

    final comments = await repo.watchComments(item.id).first;
    await repo.deleteComment(comments.first);
    expect((await reload(item)).commentCount, 1);
    await repo.deleteComment(comments.last);
    expect((await reload(item)).commentCount, 0);

    // updateItem keeps the new fields.
    await repo.addComment(item.id, 'three');
    final current = await reload(item);
    await repo.updateItem(current, current.copyWith(title: 'Renamed'));
    expect((await reload(item)).commentCount, 1);
  });

  test('deleting a task with comments, or a comment of a gone task', () async {
    final item = await repo.addItem(list.id, 'Tickets');
    await repo.addComment(item.id, 'one');
    final comment = (await repo.watchComments(item.id).first).single;
    await repo.deleteItem(await reload(item));
    // The comment went with its task; deleting it again must not throw.
    await repo.deleteComment(comment);
    expect(await repo.watchListItems(list.id).first, isEmpty);
  });

  test('TodoItem json round-trip with the indicator fields', () {
    final item = TodoItem(
      id: 'a',
      listId: 'l',
      title: 'T',
      done: false,
      createdAt: DateTime.utc(2026, 3, 1),
      commentCount: 3,
      occurrenceDate: DateTime(2026, 3, 2),
    );
    final back = TodoItem.fromJson(item.toJson());
    expect(back.commentCount, 3);
    expect(back.occurrenceDate, DateTime(2026, 3, 2));
    expect(back.fromRecurring, isTrue);
    expect(back.copyWith(title: 'U').commentCount, 3);
    expect(back.copyWith(title: 'U').fromRecurring, isTrue);

    final json = item.toJson()
      ..remove('comment_count')
      ..remove('occurrence_date');
    final old = TodoItem.fromJson(json);
    expect(old.commentCount, 0);
    expect(old.fromRecurring, isFalse);
  });
}
