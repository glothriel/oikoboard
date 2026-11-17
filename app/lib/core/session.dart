import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backend.dart';
import 'family.dart';

/// The signed-in account (a person with an email). A family member is a separate thing.
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

/// The family the account belongs to.
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

  /// null = the account has no family yet (the “create / join” screen).
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

  /// Email-only login — local only (OIKO_DEV_LOGIN=1).
  final bool devLogin;

  /// No-server mode: picking a family member from the mock.
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

  /// An invitation for a specific member (e.g. “Kuba”), or null = a new person.
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

  /// Restores the saved session (e.g. after a page reload), or null.
  Future<Session?> restore();

  /// Web: redirects the whole page to Google (the result is picked up by
  /// [completeRedirect] after returning). Android: returns the session.
  Future<Session?> loginWithGoogle();

  /// Web: finishes the login when the address contains `?code=` / `?error=`.
  Future<Session?> completeRedirect(Uri url);

  Future<Session> devLogin(String email);

  /// Mock: logs in as a family member from the mock.
  Future<Session> mockLogin(String memberId);

  Future<Session> reload(Session s);
  Future<Session> createHousehold(Session s, String name, String memberName);
  Future<InvitePreview> previewInvite(Session s, String token);
  Future<Session> acceptInvite(Session s, String token);
  Future<Session> switchMember(Session s, String memberId);
  Future<CreatedInvite> createInvite(Session s, {String? memberId});
  Future<void> logout(Session s);
}

/// Why a login failed; the login screen shows the matching message.
enum LoginFailure { staleAttempt, cancelled, failed }

class LoginError implements Exception {
  const LoginError(this.failure);
  final LoginFailure failure;
  @override
  String toString() => 'LoginError(${failure.name})';
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

/// Token from an invitation link, waiting for login / a decision.
/// Also kept in browser storage — survives the redirect to Google.
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

/// Invitation token from a pasted link (`...?invite=XYZ`) or a bare token.
String? parseInvite(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  final uri = Uri.tryParse(t);
  final fromLink = uri?.queryParameters['invite'];
  if (fromLink != null && fromLink.isNotEmpty) return fromLink;
  return RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(t) ? t : null;
}

/// Login error to show on the login screen (e.g. after returning from
/// Google): a [LoginError], an [ApiException] or any other error.
class LoginMessage extends Notifier<Object?> {
  @override
  Object? build() => null;
  void set(Object? error) => state = error;
}

final loginMessageProvider = NotifierProvider<LoginMessage, Object?>(
  LoginMessage.new,
);
