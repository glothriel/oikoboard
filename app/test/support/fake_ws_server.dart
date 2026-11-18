// Fake in-process WebSocket server for SyncClient tests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Fake server: counts connections; [behave] decides what each one does.
class FakeServer {
  FakeServer._(this._http);

  final HttpServer _http;
  var connections = 0;
  final sockets = <WebSocket>[];
  final _connected = StreamController<int>.broadcast();

  /// Called with the connection number (1-based) and its socket.
  late void Function(int n, WebSocket ws) behave;

  static Future<FakeServer> start() async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final s = FakeServer._(http);
    http.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      final n = ++s.connections;
      s.sockets.add(ws);
      s._connected.add(n);
      s.behave(n, ws);
    });
    return s;
  }

  Uri get uri => Uri.parse('ws://127.0.0.1:${_http.port}/');

  Future<void> waitFor(int n) => _connected.stream
      .firstWhere((c) => c >= n)
      .timeout(const Duration(seconds: 10));

  Future<void> close() async {
    for (final ws in sockets) {
      await ws.close();
    }
    await _http.close(force: true);
  }
}

/// Replies `ready` to auth, then does whatever [after] says.
void readyThen(WebSocket ws, [void Function()? after]) {
  ws.listen((raw) {
    final msg = jsonDecode(raw as String) as Map;
    if (msg['t'] == 'auth') {
      ws.add(jsonEncode({'t': 'ready', 'member_id': 'm', 'household_id': 'h'}));
      after?.call();
    }
  });
}
