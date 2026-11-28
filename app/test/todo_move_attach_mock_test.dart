import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/app.dart';
import 'package:oikoboard/core/attachments.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:oikoboard/core/files.dart';
import 'package:oikoboard/core/mock/mock_auth_api.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/core/session.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MockStore store;
  late ProviderContainer container;

  Future<void> start(WidgetTester tester) async {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('en'),
    ];
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('en');
    Intl.defaultLocale = 'en';
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    store = MockStore(latency: Duration.zero);
    for (final m in modules) {
      m.seedMock(store);
    }
    container = ProviderContainer(
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
    await tester.tap(find.byIcon(Icons.checklist_outlined));
    await tester.pumpAndSettle();
  }

  TodoItem itemNamed(String title) => store
      .list(itemsEntity)
      .map(TodoItem.fromJson)
      .singleWhere((i) => i.title == title);

  testWidgets('a task moves to another list from its editor (mock)', (
    tester,
  ) async {
    await start(tester);
    await tester.tap(find.text('Mleko'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dom').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(itemNamed('Mleko').listId, 'dom');
    expect(find.text('Moved to “Dom”'), findsOneWidget);
    expect(find.text('Mleko'), findsNothing); // gone from Zakupy
  });

  testWidgets('files on a task and on a comment (mock)', (tester) async {
    await start(tester);
    final files = container.read(fileStoreProvider);
    final repo = container.read(todoRepositoryProvider);
    final item = itemNamed('Chleb');

    late StoredFile photo, pdf;
    await tester.runAsync(() async {
      photo = await files.upload(Uint8List(100), 'receipt.jpg');
      pdf = await files.upload(Uint8List(2048), 'warranty.pdf');
      expect((await files.usage()).used, 2148);
      await repo.attach(item.id, [photo]);
      await repo.addComment(item.id, '', attachments: [pdf]);
    });
    expect(photo.isImage, isTrue);
    expect(pdf.mime, 'application/pdf');
    final rows = store.list(attachmentsEntity).map(TodoAttachment.fromJson);
    expect(rows.map((a) => (a.file.name, a.commentId == null)), {
      ('receipt.jpg', true),
      ('warranty.pdf', false),
    });

    // The editor shows the task's own files; removing one deletes it on save.
    await tester.tap(find.text('Chleb'));
    await tester.pumpAndSettle();
    expect(find.byType(FileImageView), findsOneWidget);
    expect(find.text('warranty.pdf'), findsNothing); // the comment's
    await tester.tap(find.byTooltip('Remove'));
    await tester.pump();
    expect(find.byType(FileImageView), findsNothing);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.list(attachmentsEntity).map((a) => a['name']), [
      'warranty.pdf',
    ]);

    // Deleting the comment takes its file along.
    final comment = store
        .list(commentsEntity)
        .map(TodoComment.fromJson)
        .singleWhere((c) => c.itemId == item.id);
    await tester.runAsync(() => repo.deleteComment(comment));
    expect(store.list(attachmentsEntity), isEmpty);
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(25 << 20), '25 MB');
    expect(formatBytes(1 << 30), '1 GB');
  });
}
