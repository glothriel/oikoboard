// The online dot on MemberAvatar follows the (mock) presence set.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/core/backend.dart';
import 'package:oikoboard/core/family.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/l10n/app_localizations.dart';

const _ola = Member('ola', 'Ola', Color(0xFFAB47BC));
const _kuba = Member('kuba', 'Kuba', Color(0xFF26A69A));
const _kid = Member('kid', 'Kid', Color(0xFF26A69A), hasAccount: false);

void main() {
  testWidgets('dot shows for online members and follows the store', (
    tester,
  ) async {
    final store = MockStore(latency: Duration.zero); // seeds `ola` online
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          backendProvider.overrideWithValue(MockBackend(store)),
          currentMemberProvider.overrideWithValue('mama'),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Row(
              children: [
                MemberAvatar(_ola),
                MemberAvatar(_kuba),
                MemberAvatar(_kid),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final dot = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Online',
    );
    expect(dot, findsOneWidget);
    expect(
      find.descendant(of: find.byType(MemberAvatar).first, matching: dot),
      findsOneWidget,
    );

    store.setOnline('kuba', true);
    store.setOnline('kid', true); // no account: never shown
    await tester.pump();
    await tester.pump();
    expect(dot, findsNWidgets(2));

    store.setOnline('ola', false);
    await tester.pump();
    await tester.pump();
    expect(dot, findsOneWidget);
  });
}
