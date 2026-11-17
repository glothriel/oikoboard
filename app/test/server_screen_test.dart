import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/app.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // The UI tests assert the Polish texts: the device locale is Polish here.
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .platformDispatcher
        .localesTestValue = const [
      Locale('pl'),
    ];
  });
  test('server addresses are normalized', () {
    expect(
      parseServerUrl('oiko.example.com/app')?.toString(),
      'https://oiko.example.com',
    );
    expect(
      parseServerUrl('192.168.1.10:8090')?.toString(),
      'http://192.168.1.10:8090',
    );
    expect(
      parseServerUrl('http://localhost:8090')?.toString(),
      'http://localhost:8090',
    );
    expect(parseServerUrl(''), isNull);
    expect(parseServerUrl('ftp://x'), isNull);
  });

  testWidgets('first start asks for the server', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final onError = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('CupertinoLocalizations')) onError?.call(d);
    };
    addTearDown(() => FlutterError.onError = onError);

    final container = ProviderContainer(
      overrides: [serverChoiceProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const OikoboardApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Serwer rodziny'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'nie-oiko.example.com');
        await tester.tap(find.text('Połącz'));
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('nie odpowiada'), findsOneWidget);
        expect(container.read(serverUrlProvider), isNull);

        await tester.enterText(find.byType(TextField), 'oiko.example.com');
        await tester.tap(find.text('Połącz'));
        await tester.runAsync(
          () => Future.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(
          container.read(serverUrlProvider).toString(),
          'https://oiko.example.com',
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('oiko.server'), 'https://oiko.example.com');
      },
      () => MockClient(
        (req) async => req.url.host == 'oiko.example.com'
            ? http.Response(jsonEncode({'ok': true}), 200)
            : http.Response('nope', 404),
      ),
    );
  });
}
