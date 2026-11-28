// The family follows its member source, and a dangling member id shows a
// placeholder instead of crashing (mock backend widgets).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:oikoboard/core/family.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/l10n/app_localizations.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/todo_screen.dart';

final _members = StateProvider<List<Member>>(
  (_) => const [Member('a', 'Anna', Color(0xFF1565C0))],
);

Widget _app(Widget body) => ProviderScope(
  overrides: [
    backendProvider.overrideWithValue(
      MockBackend(MockStore(latency: Duration.zero)),
    ),
    membersProvider.overrideWith((ref) => ref.watch(_members)),
  ],
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => FamilyScope(child: child!),
    home: Scaffold(body: body),
  ),
);

TodoItem _item(String? assignee) => TodoItem(
  id: 'i',
  listId: 'l',
  title: 'Task',
  done: false,
  createdAt: DateTime(2026),
  assigneeId: assignee,
);

void main() {
  testWidgets('a member that appears later is shown and selectable', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(TodoItemTile(item: _item('b'), onDismissed: () {})),
    );
    // unknown for now: placeholder, no exception
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
    expect(tester.takeException(), isNull);

    ProviderScope.containerOf(tester.element(find.byType(TodoItemTile)))
        .read(_members.notifier)
        .state = const [
      Member('a', 'Anna', Color(0xFF1565C0)),
      Member('b', 'Bob', Color(0xFF2E7D32)),
    ];
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsNothing);

    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, 'Bob'), findsOneWidget);
  });

  testWidgets('familyOf rebuilds its widget when the family changes', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (c) => Text(familyOf(c).members.map((m) => m.name).join()),
        ),
      ),
    );
    expect(find.text('Anna'), findsOneWidget);
    ProviderScope.containerOf(tester.element(find.byType(Builder).first))
        .read(_members.notifier)
        .state = const [
      Member('b', 'Bob', Color(0xFF2E7D32)),
    ];
    await tester.pump();
    expect(find.text('Bob'), findsOneWidget);
  });

  test('byIdOrRemoved gives a placeholder only for an unknown id', () {
    const family = Family([Member('a', 'Anna', Color(0xFF1565C0))]);
    expect(family.byIdOrRemoved('a')!.removed, isFalse);
    expect(family.byIdOrRemoved('x')!.removed, isTrue);
    expect(family.byIdOrRemoved(null), isNull);
  });
}
