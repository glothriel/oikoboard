import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/core/markdown.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/modules/todo/repository.dart';

/// Lists and tasks keep a markdown description through create and update.
void main() {
  test('list and task descriptions (mock)', () async {
    final repo = MockTodoRepository(
      MockStore(latency: Duration.zero),
      actorId: 'm1',
    );
    final list = await repo.addList(
      'Trip',
      color: 0xFF5C6BC0,
      description: '**Bring** passports',
    );
    expect(
      (await repo.watchLists().first).single.description,
      '**Bring** passports',
    );
    await repo.updateList(list, list.copyWith(description: '', color: 1));
    final updated = (await repo.watchLists().first).single;
    expect((updated.description, updated.color), ('', 1));

    final item = await repo.addItem(list.id, 'Tickets');
    await repo.updateItem(item, item.copyWith(description: '- seat 12A'));
    expect(
      (await repo.watchListItems(list.id).first).single.description,
      '- seat 12A',
    );
  });

  testWidgets('markdown follows the app theme (dark)', (tester) async {
    final theme = ThemeData(brightness: Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(body: MarkdownText('plain **bold**')),
      ),
    );
    final span = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .first
        .text;
    expect(span.toPlainText(), 'plain bold');
    final colors = <Color?>[];
    span.visitChildren((s) {
      colors.add(s.style?.color);
      return true;
    });
    expect(
      colors.whereType<Color>(),
      everyElement(theme.colorScheme.onSurface),
    );
  });
}
