import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart' show TimeOfDay;
import 'package:uuid/uuid.dart';

const uuid = Uuid();

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => 'ApiException($status): $message';
}

/// The server didn't answer at all.
class ConnectionException implements Exception {
  const ConnectionException();

  @override
  String toString() => 'ConnectionException';
}

/// Thin layer over the REST API (writes). Reads go through [SyncClient].
class ApiClient {
  ApiClient(this.baseUri, {this.token, this.onUnauthorized});

  final Uri baseUri;
  final String? token;
  final void Function()? onUnauthorized;
  final _http = http.Client();

  /// Failed writes to show in the UI (a snackbar in the shell).
  static final errors = StreamController<Exception>.broadcast();

  /// [report]: false for reads whose failure the caller shows itself.
  Future<dynamic> get(String path, {bool report = true}) =>
      _send('GET', path, report: report);
  Future<dynamic> post(String path, Object body) =>
      _send('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) =>
      _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// A queued write (the outbox): with its own mutation id, so a retry is
  /// the same operation, and without reporting failures to [errors] — the
  /// outbox decides what to do with them.
  Future<dynamic> mutate(
    String method,
    String path,
    Object? body, {
    required String mutationId,
  }) => _send(method, path, body: body, mutationId: mutationId, report: false);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    String? mutationId,
    bool report = true,
  }) async {
    final req = http.Request(method, baseUri.resolve('/api/v1$path'));
    req.headers['Content-Type'] = 'application/json';
    // Operation id — comes back in the change over the WebSocket (confirmation).
    req.headers['X-Mutation-Id'] = mutationId ?? uuid.v4();
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);

    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req));
    } catch (e) {
      if (report) errors.add(const ConnectionException());
      rethrow;
    }
    if (res.statusCode == 401) onUnauthorized?.call();
    if (res.statusCode >= 400) {
      var msg = res.reasonPhrase ?? '';
      try {
        msg =
            (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['message']
                as String;
      } catch (_) {}
      final error = ApiException(res.statusCode, msg);
      if (report) errors.add(error);
      throw error;
    }
    if (res.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  void close() => _http.close();
}

/// Times go to the API in UTC (with an offset) and come back as local time.
String? toApiTime(DateTime? d) => d?.toUtc().toIso8601String();
DateTime? fromApiTime(Object? s) =>
    s == null ? null : DateTime.parse(s as String).toLocal();

/// Calendar dates (no time of day) travel as "YYYY-MM-DD"; in the app they
/// are local midnight.
String? toApiDate(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
DateTime? fromApiDate(Object? s) {
  if (s == null) return null;
  final d = DateTime.parse((s as String).substring(0, 10));
  return DateTime(d.year, d.month, d.day);
}

/// Wall-clock times (no date) travel as "HH:MM" ("HH:MM:SS" from the change
/// feed).
String? toApiClock(TimeOfDay? t) => t == null
    ? null
    : '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
TimeOfDay? fromApiClock(Object? s) {
  if (s == null) return null;
  final p = (s as String).split(':');
  return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
}
