import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636, S256) for flows finished by the app: the one-time code
/// from a redirect is useless without the verifier kept here.
String pkceVerifier() {
  final r = Random.secure();
  return base64UrlEncode(List.generate(32, (_) => r.nextInt(256)))
      .replaceAll('=', '');
}

String pkceChallenge(String verifier) =>
    base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
        .replaceAll('=', '');

/// Address of the web app (without query and fragment).
String get webAppUrl => '${Uri.base.origin}${Uri.base.path}';
