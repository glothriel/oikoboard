import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/app.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:oikoboard/core/mock/mock_auth_api.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/core/session.dart';

/// The AI screen in mock mode: lists connected apps and disconnects one.
void main() {
  // The UI tests assert the Polish texts: the device locale is Polish here.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('pl'),
    ];
  });
  testWidgets('connected AI apps in mock mode', (tester) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('CupertinoLocalizations')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        backendProvider.overrideWithValue(
          MockBackend(MockStore(latency: Duration.zero)),
        ),
      ],
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

    await tester.tap(find.byTooltip('mama@mock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Czat AI (MCP)'));
    await tester.pumpAndSettle();
    expect(find.text('ChatGPT'), findsOneWidget);

    await tester.tap(find.text('Odłącz'));
    await tester.pumpAndSettle();
    expect(find.text('ChatGPT'), findsNothing);
    expect(find.text('Nic nie jest podłączone.'), findsOneWidget);
  });
}
