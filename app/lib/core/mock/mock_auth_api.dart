import 'package:material_ui/material_ui.dart';

import '../family.dart';
import '../session.dart';

/// Rodzina z mocka (id czytelne, nie UUID — mockowi to nie przeszkadza).
const mockFamily = [
  Member('mama', 'Mama', Color(0xFFE57373)),
  Member('tata', 'Tata', Color(0xFF5C6BC0)),
  Member('ola', 'Ola', Color(0xFFAB47BC)),
  Member('kuba', 'Kuba', Color(0xFF26A69A)),
];

/// Tryb bez serwera: „kim jesteś?” spośród [mockFamily].
class MockAuthApi implements AuthApi {
  @override
  Future<AuthOptions> options() async => const AuthOptions(mock: true);

  @override
  Future<Session> mockLogin(String memberId) async {
    final m = mockFamily.firstWhere((m) => m.id == memberId);
    return Session(
      token: 'mock',
      user: Account(id: m.id, email: '${m.id}@mock', name: m.name),
      memberId: m.id,
      householdId: 'mock',
      householdName: 'Rodzina (mock)',
      members: mockFamily,
      memberships: const [],
    );
  }

  @override
  Future<Session> switchMember(Session s, String memberId) =>
      mockLogin(memberId);

  @override
  Future<Session> reload(Session s) async => s;

  @override
  Future<Session?> restore() async => null;

  @override
  Future<Session?> completeRedirect(Uri url) async => null;

  @override
  Future<void> logout(Session s) async {}

  Never _unsupported() => throw UnsupportedError('niedostępne w trybie mock');

  @override
  Future<Session?> loginWithGoogle() => _unsupported();
  @override
  Future<Session> devLogin(String email) => _unsupported();
  @override
  Future<Session> createHousehold(Session s, String name, String memberName) =>
      _unsupported();
  @override
  Future<InvitePreview> previewInvite(Session s, String token) =>
      _unsupported();
  @override
  Future<Session> acceptInvite(Session s, String token) => _unsupported();
  @override
  Future<CreatedInvite> createInvite(Session s, {String? memberId}) =>
      _unsupported();
}
