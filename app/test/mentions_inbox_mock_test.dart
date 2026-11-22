import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/app.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:oikoboard/core/mock/mock_auth_api.dart';
import 'package:oikoboard/core/session.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oikoboard/core/family.dart';
import 'package:oikoboard/core/markdown.dart';
import 'package:oikoboard/core/mentions.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';

const _family = Family([
  Member('ola', 'Ola', Color(0xFFAB47BC)),
  Member('olak', 'Ola K', Color(0xFF26A69A)),
  Member('mama', 'Mama', Color(0xFFE57373)),
]);

void main() {
  group('mentions', () {
    test('encode: names to links, longest first, not inside words', () {
      expect(
        encodeMentions('hi @ola and @Ola K, mail a@Mama.pl, @Olaf', _family),
        'hi [@Ola](member:ola) and [@Ola K](member:olak), mail a@Mama.pl, @Olaf',
      );
    });

    test('decode uses the current name and round-trips', () {
      const md = 'see [@Old name](member:mama) and [@Gone](member:x)';
      expect(decodeMentions(md, _family), 'see @Mama and @Gone');
      final again = encodeMentions(decodeMentions(md, _family), _family);
      expect(again, 'see [@Mama](member:mama) and @Gone');
    });

    test('active @query before the cursor', () {
      TextEditingValue at(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      expect(activeMention(at('hey @Ol')), (start: 4, query: 'Ol'));
      expect(activeMention(at('@')), (start: 0, query: ''));
      expect(activeMention(at('a@Ol')), isNull);
      expect(activeMention(at('@Ola ')), isNull);
    });
  });

  test('inbox: mentions, replies and assignments (mock)', () async {
    final store = MockStore(latency: Duration.zero);
    MockTodoRepository as(String id) => MockTodoRepository(store, actorId: id);
    Future<List<InboxEntry>> inbox(String id) => as(id).watchInbox().first;

    final list = await as('mama').addList('Trip', color: 1);
    final item = await as('mama')
        .addItem(list.id, 'Passport', assigneeId: 'ola');
    expect((await inbox('ola')).single.kind, InboxKind.assigned);

    // A comment mentioning Kuba: a mention for him, a reply for Ola.
    await as('mama').addComment(item.id, 'ask [@Kuba](member:kuba)');
    expect((await inbox('kuba')).single.kind, InboxKind.mention);
    final ola = await inbox('ola');
    expect(ola.map((e) => e.kind), [InboxKind.reply, InboxKind.assigned]);
    expect(await inbox('mama'), isEmpty);

    // Kuba answers: Mama (commented) and Ola get a reply.
    await as('kuba').addComment(item.id, 'ok');
    expect((await inbox('mama')).single.excerpt, 'ok');
    expect(await inbox('ola'), hasLength(3));

    // Description mentions notify once.
    final current = (await as('mama').watchListItems(list.id).first).single;
    final described = current.copyWith(description: '[@Tata](member:tata)');
    await as('mama').updateItem(current, described);
    await as('mama').updateItem(
      described,
      described.copyWith(description: '${described.description} again'),
    );
    expect(await inbox('tata'), hasLength(1));

    await as('ola').markRead(await inbox('ola'));
    expect((await inbox('ola')).where((e) => e.unread), isEmpty);

    // Deleting the task takes its entries with it.
    await as('mama').deleteItem(described);
    expect(await inbox('ola'), isEmpty);
  });

  testWidgets('a mention renders as the member’s current name', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [familyProvider.overrideWithValue(_family)],
        child: const MaterialApp(
          home: Scaffold(
            body: MarkdownText('hi [@Old](member:mama), **bold**'),
          ),
        ),
      ),
    );
    expect(find.textContaining('@Mama', findRichText: true), findsOneWidget);
    expect(find.textContaining('@Old', findRichText: true), findsNothing);
  });

  testWidgets('inbox in the app bar opens the thread (mock)', (tester) async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('en'),
    ];
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('en');
    Intl.defaultLocale = 'en';
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final store = MockStore(latency: Duration.zero);
    for (final m in modules) {
      m.seedMock(store);
    }
    final container = ProviderContainer(
      overrides: [backendProvider.overrideWithValue(MockBackend(store))],
    );
    addTearDown(container.dispose);
    container
        .read(sessionProvider.notifier)
        .set(await MockAuthApi().mockLogin('tata'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OikoboardApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Seeded: Mama mentioned Tata, then Ola replied in the thread.
    await tester.tap(find.byTooltip('Inbox: 2 unread'));
    await tester.pumpAndSettle();
    expect(find.text('Ola replied in “Paszport dla Oli”'), findsOneWidget);
    expect(
      find.text('Mama mentioned you in “Paszport dla Oli”'),
      findsOneWidget,
    );
    // The excerpt shows the mention as a name, not the link.
    expect(find.textContaining('@Tata'), findsOneWidget);

    await tester.tap(find.text('Ola replied in “Paszport dla Oli”'));
    await tester.pumpAndSettle();
    // The mock store answers the task lookup partly outside the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100)); // the task loads
    await tester.pumpAndSettle();
    expect(find.text('Comments: Paszport dla Oli'), findsOneWidget);
    expect(find.textContaining('@Tata', findRichText: true), findsOneWidget);
    // Opening the thread read both entries about it.
    expect(find.byTooltip('Inbox'), findsOneWidget);

    // Under the thread: the task's editor, over the task's list.
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Comments: Paszport dla Oli'), findsNothing);
    expect(find.widgetWithText(TextField, 'Paszport dla Oli'), findsOneWidget);
    expect(find.text('Kupić krem z filtrem'), findsOneWidget);
  });
}
