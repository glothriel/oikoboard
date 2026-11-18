import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/app.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:oikoboard/core/mock/mock_auth_api.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/core/session.dart';
import 'package:oikoboard/modules/registry.dart';
import 'package:oikoboard/modules/todo/repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Due tasks show in the calendar as one chip per day; the chip opens the
/// day's tasks, and ticking the last one removes the chip.
void main() {
  // The UI tests assert the Polish texts: the device locale is Polish here.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('pl'),
    ];
  });
  testWidgets('due tasks in the calendar (mock)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('pl');
    Intl.defaultLocale = 'pl';
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('CupertinoLocalizations')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(1400, 1000);
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
        .set(await MockAuthApi().mockLogin('mama'));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const OikoboardApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The wall lists overdue tasks separately.
    expect(find.text('Zaległe (1)'), findsOneWidget);

    await tester.tap(find.text('Kalendarz').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miesiąc').first);
    await tester.pumpAndSettle();

    const chip = 'Zadanie: Odkurzyć pokój'; // due today
    expect(find.text(chip), findsWidgets); // month grid + today's agenda
    await tester.tap(find.text(chip).last); // the agenda card opens it
    await tester.pumpAndSettle();
    expect(find.widgetWithText(CheckboxListTile, 'Odkurzyć pokój'), findsOne);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Odkurzyć pokój'));
    await tester.pumpAndSettle();
    final item = store
        .list(itemsEntity)
        .singleWhere((i) => i['title'] == 'Odkurzyć pokój');
    expect(item['done'], true);
    // Still in the sheet (ticked), gone from the calendar.
    expect(find.widgetWithText(CheckboxListTile, 'Odkurzyć pokój'), findsOne);
    await tester.tapAt(const Offset(10, 10)); // close the sheet
    await tester.pumpAndSettle();
    expect(find.text(chip), findsNothing);
  });
}
