import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../family.dart';
import '../platform/browser.dart';
import '../session.dart';
import 'api_client.dart';
import 'pkce.dart';

/// Login through the backend (Google OIDC). Flow — docs/auth.md: the app
/// opens /auth/google/start with a return address and a PKCE challenge,
/// comes back with a one-time code and exchanges it (with the verifier)
/// for a session token.
class HttpAuthApi implements AuthApi {
  HttpAuthApi(this.baseUri);
  final Uri baseUri;

  static const _tokenKey = 'oiko.token';
  static const _verifierKey = 'oiko.pkce';
  static const _androidReturn = 'oikoboard://auth';

  ApiClient _client([Session? s]) => ApiClient(baseUri, token: s?.token);

  @override
  Future<AuthOptions> options() async {
    final j = await _client().get('/auth/config') as Map;
    return AuthOptions(
      google: j['google'] == true,
      devLogin: j['dev_login'] == true,
    );
  }

  @override
  Future<Session?> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null) return null;
    try {
      return await _me(token);
    } on ApiException catch (e) {
      if (e.status == 401) await prefs.remove(_tokenKey);
      return null;
    }
  }

  Uri _startUrl(String returnTo, String verifier) => baseUri
      .resolve('/api/v1/auth/google/start')
      .replace(
        queryParameters: {
          'return': returnTo,
          'challenge': pkceChallenge(verifier),
        },
      );

  @override
  Future<Session?> loginWithGoogle() async {
    final verifier = pkceVerifier();
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_verifierKey, verifier);
      redirectTo(_startUrl(webAppUrl, verifier).toString());
      // Strona przechodzi do Google; wynik odbierze completeRedirect.
      return Completer<Session?>().future;
    }
    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(
        url: _startUrl(_androidReturn, verifier).toString(),
        callbackUrlScheme: 'oikoboard',
      );
    } catch (_) {
      return null; // the login window was closed
    }
    return _finish(Uri.parse(result), verifier);
  }

  @override
  Future<Session?> completeRedirect(Uri url) async {
    final q = url.queryParameters;
    if (!q.containsKey('code') && !q.containsKey('error')) return null;
    final prefs = await SharedPreferences.getInstance();
    final verifier = prefs.getString(_verifierKey);
    await prefs.remove(_verifierKey);
    if (verifier == null) {
      throw const LoginError(LoginFailure.staleAttempt);
    }
    return _finish(url, verifier);
  }

  Future<Session> _finish(Uri url, String verifier) async {
    final q = url.queryParameters;
    if (q['error'] != null) {
      throw LoginError(
        q['error'] == 'access_denied'
            ? LoginFailure.cancelled
            : LoginFailure.failed,
      );
    }
    final res = await _client().post('/auth/exchange', {
      'code': q['code'],
      'verifier': verifier,
    }) as Map;
    return _store(res['token'] as String);
  }

  @override
  Future<Session> devLogin(String email) async {
    final res =
        await _client().post('/auth/dev/login', {'email': email}) as Map;
    return _store(res['token'] as String);
  }

  @override
  Future<Session> mockLogin(String memberId) =>
      throw UnsupportedError('mock login is only available in mock mode');

  Future<Session> _store(String token) async {
    final session = await _me(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    return session;
  }

  @override
  Future<Session> reload(Session s) => _me(s.token);

  @override
  Future<Session> createHousehold(
    Session s,
    String name,
    String memberName,
  ) async {
    String? timezone;
    try {
      timezone = (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {} // the server's default then
    await _client(s).post('/households', {
      'name': name,
      'member_name': memberName,
      'timezone': ?timezone,
    });
    return _me(s.token);
  }

  @override
  Future<InvitePreview> previewInvite(Session s, String token) async {
    final j =
        await _client(s).get('/invites/${Uri.encodeComponent(token)}') as Map;
    return InvitePreview(
      householdName: j['household_name'] as String,
      memberName: j['member_name'] as String?,
      invitedBy: j['invited_by'] as String?,
      alreadyMember: j['already_member'] == true,
    );
  }

  @override
  Future<Session> acceptInvite(Session s, String token) async {
    await _client(s).post('/invites/${Uri.encodeComponent(token)}/accept', {});
    return _me(s.token);
  }

  @override
  Future<Session> switchMember(Session s, String memberId) async {
    await _client(s).post('/auth/switch', {'member_id': memberId});
    return _me(s.token);
  }

  @override
  Future<CreatedInvite> createInvite(Session s, {String? memberId}) async {
    final j =
        await _client(s).post('/invites', {'member_id': ?memberId}) as Map;
    final token = j['token'] as String;
    // Link to the web app: on the web, the same address we are on; elsewhere,
    // from the server configuration (OIKO_APP_URL).
    final link = kIsWeb
        ? Uri.parse(webAppUrl)
              .replace(queryParameters: {'invite': token})
              .toString()
        : (j['url'] as String?) ?? token;
    return CreatedInvite(token, link);
  }

  @override
  Future<void> logout(Session s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    try {
      await _client(s).post('/auth/logout', {});
    } catch (_) {}
  }

  Future<Session> _me(String token) async {
    final me = await ApiClient(baseUri, token: token).get('/me') as Map;
    final hh = me['household'] as Map?;
    return Session(
      token: token,
      user: Account.fromJson((me['user'] as Map).cast()),
      memberId: me['member_id'] as String?,
      householdId: hh?['id'] as String?,
      householdName: hh?['name'] as String?,
      members: [
        for (final m in (me['members'] as List).cast<Map<String, dynamic>>())
          Member.fromJson(m),
      ],
      memberships: [
        for (final m
            in (me['memberships'] as List).cast<Map<String, dynamic>>())
          Membership.fromJson(m),
      ],
    );
  }
}
