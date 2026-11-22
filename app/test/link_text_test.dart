import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/core/link_text.dart';
import 'package:oikoboard/l10n/app_localizations.dart';

void main() {
  late int tileTaps;
  late List<Uri> opened;
  late int reorders;

  /// A task row like the list screen's: reorderable, dismissible, tappable.
  Future<void> pumpRow(WidgetTester tester) async {
    tileTaps = 0;
    reorders = 0;
    opened = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverReorderableList(
                itemCount: 2,
                onReorderItem: (_, _) => reorders++,
                itemBuilder: (context, i) =>
                    ReorderableDelayedDragStartListener(
                      key: ValueKey(i),
                      index: i,
                      child: Dismissible(
                        key: ValueKey('d$i'),
                        direction: DismissDirection.endToStart,
                        child: Material(
                          child: ListTile(
                            title: LinkText(
                              'see https://example.com/x, then',
                              onOpen: opened.add,
                            ),
                            onTap: () => tileTaps++,
                          ),
                        ),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Offset linkCenter(WidgetTester tester) {
    final range = find.textRange.ofSubstring('example.com').evaluate().first;
    final p = range.renderObject;
    final box = p
        .getBoxesForSelection(
          TextSelection(
            baseOffset: range.textRange.start,
            extentOffset: range.textRange.end,
          ),
        )
        .first
        .toRect();
    return p.localToGlobal(box.center);
  }

  final link = Uri.parse('https://example.com/x');

  testWidgets('a plain tap on a link goes to the row', (tester) async {
    await pumpRow(tester);
    await tester.tapAt(linkCenter(tester));
    await tester.pumpAndSettle();
    expect(tileTaps, 1);
    expect(opened, <Uri>[]);
  });

  testWidgets('a long press on a link opens its menu, not a drag', (
    tester,
  ) async {
    await pumpRow(tester);
    final g = await tester.startGesture(linkCenter(tester));
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Open link'), findsOneWidget);
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();
    expect(tileTaps, 0);
    expect(opened, [link]);
  });

  testWidgets('a right click on a link opens its menu', (tester) async {
    await pumpRow(tester);
    await tester.tapAt(
      linkCenter(tester),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();
    expect(tileTaps, 0);
    expect(opened, [link]);
  });

  testWidgets('Ctrl+click opens a link', (tester) async {
    await pumpRow(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(linkCenter(tester), kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(tileTaps, 0);
    expect(opened, [link]);
  });

  testWidgets('a long press outside the link still reorders', (tester) async {
    await pumpRow(tester);
    final row = find.byType(ListTile).first;
    final g = await tester.startGesture(
      tester.getTopRight(row) - const Offset(20, -20),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveBy(const Offset(0, 120));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(reorders, 1);
    expect(find.text('Open link'), findsNothing);
  });
}
