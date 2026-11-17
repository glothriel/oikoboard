import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'family.dart';

/// Zalogowane konto (osoba z e-mailem). Członek rodziny to osobna rzecz.
class Account {
  const Account({required this.id, required this.email, required this.name});
  final String id;
  final String email;
  final String name;

  factory Account.fromJson(Map<String, dynamic> j) => Account(
    id: j['id'] as String,
    email: j['email'] as String,
    name: (j['name'] as String?) ?? '',
  );
}

/// Rodzina, do której należy konto.
class Membership {
  const Membership(this.memberId, this.householdId, this.householdName);
  final String memberId;
  final String householdId;
  final String householdName;

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
    j['member_id'] as String,
    j['household_id'] as String,
    j['household_name'] as String,
  );
}

class Session {
  const Session({
    required this.token,
    required this.user,
    required this.memberId,
    required this.householdId,
    required this.householdName,
    required this.members,
    required this.memberships,
  });

  final String token;
  final Account user;

  /// null = konto jeszcze bez rodziny (ekran „załóż / dołącz”).
  final String? memberId;
  final String? householdId;
  final String? householdName;
  final List<Member> members;
  final List<Membership> memberships;

  bool get hasHousehold => memberId != null;
  Member get me => members.firstWhere((m) => m.id == memberId);
}

class AuthOptions {
  const AuthOptions({
    this.google = false,
    this.devLogin = false,
    this.mock = false,
  });
  final bool google;

  /// Logowanie samym e-mailem — tylko lokalnie (OIKO_DEV_LOGIN=1).
  final bool devLogin;

  /// Tryb bez serwera: wybór członka rodziny z mocka.
  final bool mock;
}

class InvitePreview {
  const InvitePreview({
    required this.householdName,
    this.memberName,
    this.invitedBy,
    this.alreadyMember = false,
  });
  final String householdName;

  /// Zaproszenie dla konkretnego członka (np. „Kuba”), albo null = nowa osoba.
  final String? memberName;
  final String? invitedBy;
  final bool alreadyMember;
}

class CreatedInvite {
  const CreatedInvite(this.token, this.link);
  final String token;
  final String link;
}

/// Logowanie i konto. Implementacje: HTTP (Google) i mock.
abstract interface class AuthApi {
  Future<AuthOptions> options();

  /// Przywraca zapisaną sesję (np. po odświeżeniu strony), albo null.
  Future<Session?> restore();

  /// Web: przekierowuje całą stronę do Google (wynik odbiera
  /// [completeRedirect] po powrocie). Android: zwraca sesję.
  Future<Session?> loginWithGoogle();

  /// Web: dokończenie logowania, gdy adres zawiera `?code=` / `?error=`.
  Future<Session?> completeRedirect(Uri url);

  Future<Session> devLogin(String email);

  /// Mock: zalogowanie jako członek rodziny z mocka.
  Future<Session> mockLogin(String memberId);

  Future<Session> reload(Session s);
  Future<Session> createHousehold(Session s, String name, String memberName);
  Future<InvitePreview> previewInvite(Session s, String token);
  Future<Session> acceptInvite(Session s, String token);
  Future<Session> switchMember(Session s, String memberId);
  Future<CreatedInvite> createInvite(Session s, {String? memberId});
  Future<void> logout(Session s);
}

class LoginError implements Exception {
  const LoginError(this.message);
  final String message;
  @override
  String toString() => message;
}

final authApiProvider = Provider<AuthApi>(
  (ref) => ref.watch(backendProvider).authApi(),
);

class SessionNotifier extends Notifier<Session?> {
  @override
  Session? build() => null;

  void set(Session? s) => state = s;

  Future<void> logout() async {
    final s = state;
    state = null;
    if (s != null) await ref.read(authApiProvider).logout(s);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

/// Token z linku zaproszenia, czekający na zalogowanie / decyzję.
/// Trzymany też w pamięci przeglądarki — przeżywa przekierowanie do Google.
class PendingInvite extends Notifier<String?> {
  static const _key = 'oiko.invite';

  @override
  String? build() => null;

  static Future<String?> load() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  Future<void> set(String? token) async {
    state = token;
    final prefs = await SharedPreferences.getInstance();
    token == null
        ? await prefs.remove(_key)
        : await prefs.setString(_key, token);
  }
}

final pendingInviteProvider = NotifierProvider<PendingInvite, String?>(
  PendingInvite.new,
);

/// Token zaproszenia z wklejonego linku (`...?invite=XYZ`) albo gołego tokena.
String? parseInvite(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final uri = Uri.tryParse(t);
  final fromLink = uri?.queryParameters['invite'];
  if (fromLink != null && fromLink.isNotEmpty) return fromLink;
  return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(t) ? t : null;
}

/// Błąd logowania do pokazania na ekranie logowania (np. po powrocie z Google).
class LoginMessage extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? m) => state = m;
}

final loginMessageProvider = NotifierProvider<LoginMessage, String?>(
  LoginMessage.new,
);
