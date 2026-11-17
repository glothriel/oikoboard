import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../change.dart';

/// Stan jednego widoku: encja → id → wiersz.
class ViewData {
  ViewData(this.entities);
  final Map<String, Map<String, Map<String, dynamic>>> entities;

  List<Map<String, dynamic>> rows(String entity) =>
      entities[entity]?.values.toList() ?? const [];
}

class _Sub {
  _Sub(this.view, this.params, this.controller);
  final String view;
  final Map<String, dynamic> params;
  final StreamController<ViewData> controller;
  Map<String, Map<String, Map<String, dynamic>>> state = {};
}

/// Jedno połączenie WebSocket na aplikację, wiele subskrypcji widoków.
///
/// Protokół (docs/backend-realtime.md): auth → sub → snapshot, potem
/// upsert/remove. Po zerwaniu: reconnect z backoffem i ponowna subskrypcja
/// wszystkich otwartych widoków — każdy dostaje świeży snapshot.
class SyncClient {
  SyncClient(this.wsUri, this.token, {this.onUnauthorized}) {
    _connect();
  }

  final Uri wsUri;
  final String token;
  final void Function()? onUnauthorized;

  final _subs = <String, _Sub>{};
  var _nextId = 0;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  Timer? _retry;
  var _backoff = const Duration(milliseconds: 500);
  var _disposed = false;
  final _random = Random();

  final _status = StreamController<bool>.broadcast();
  final _changes = StreamController<Change>.broadcast();
  final _seenSeqs = <int>{}; // LinkedHashSet — pamięta kolejność
  var connected = false;

  /// true = połączony i zalogowany.
  Stream<bool> get status => _status.stream;

  /// Zmiany ze wszystkich subskrypcji (bez duplikatów) — do powiadomień.
  Stream<Change> get changes => _changes.stream;

  /// Subskrypcja widoku. Anulowanie streamu = `unsub`.
  Stream<ViewData> watch(
    String view, [
    Map<String, dynamic> params = const {},
  ]) {
    late final StreamController<ViewData> ctrl;
    final id = 's${_nextId++}';
    ctrl = StreamController<ViewData>(
      onListen: () {
        _subs[id] = _Sub(view, params, ctrl);
        _sendSub(id);
      },
      onCancel: () {
        _subs.remove(id);
        _send({'t': 'unsub', 'id': id});
      },
    );
    return ctrl.stream;
  }

  void _connect() {
    if (_disposed) return;
    final channel = WebSocketChannel.connect(wsUri);
    _channel = channel;
    // błąd połączenia obsługuje onDone niżej
    channel.ready.then((_) {}, onError: (_) {});
    _channelSub = channel.stream.listen(
      _onMessage,
      onDone: () => _onClosed(channel),
      onError: (_) {},
      cancelOnError: false,
    );
    _send({'t': 'auth', 'token': token});
    for (final id in _subs.keys) {
      _sendSub(id);
    }
  }

  void _onClosed(WebSocketChannel channel) {
    if (_disposed || channel != _channel) return;
    _setConnected(false);
    if (channel.closeCode == 4001) {
      onUnauthorized?.call();
      return;
    }
    final jitter = Duration(milliseconds: _random.nextInt(300));
    _retry = Timer(_backoff + jitter, _connect);
    _backoff = Duration(milliseconds: min(_backoff.inMilliseconds * 2, 30000));
  }

  void _setConnected(bool v) {
    if (connected == v) return;
    connected = v;
    _status.add(v);
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _channel?.sink.add(jsonEncode(msg));
    } catch (_) {
      // połączenie padło — reconnect wyśle subskrypcje od nowa
    }
  }

  void _sendSub(String id) {
    final s = _subs[id];
    if (s == null) return;
    _send({'t': 'sub', 'id': id, 'view': s.view, 'params': s.params});
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = msg['t'] as String;
    if (type == 'ready') {
      _backoff = const Duration(milliseconds: 500);
      _setConnected(true);
      return;
    }
    final sub = _subs[msg['sub']];
    if (sub == null) return;

    switch (type) {
      case 'snapshot':
        final data = (msg['data'] as Map).cast<String, dynamic>();
        sub.state = {
          for (final e in data.entries)
            e.key: {
              for (final r in (e.value as List).cast<Map<String, dynamic>>())
                r['id'] as String: r,
            },
        };
      case 'upsert':
        final row = (msg['row'] as Map).cast<String, dynamic>();
        (sub.state[msg['entity'] as String] ??= {})[msg['id'] as String] = row;
        _notify(msg);
      case 'remove':
        sub.state[msg['entity'] as String]?.remove(msg['id']);
        _notify(msg);
      case 'error':
        sub.controller.addError(Exception('${msg['code']}: ${msg['msg']}'));
        return;
      default:
        return;
    }
    sub.controller.add(
      ViewData({for (final e in sub.state.entries) e.key: Map.of(e.value)}),
    );
  }

  void _notify(Map<String, dynamic> msg) {
    final seq = msg['seq'] as int;
    if (!_seenSeqs.add(seq)) return; // ta sama zmiana z innej subskrypcji
    if (_seenSeqs.length > 500) _seenSeqs.remove(_seenSeqs.first);
    final actor = msg['actor'] as String?;
    if (actor == null) return;
    _changes.add(
      Change(
        seq: seq,
        collection: msg['entity'] as String,
        entityId: msg['id'] as String,
        op: switch (msg['op']) {
          'insert' => ChangeOp.created,
          'delete' => ChangeOp.deleted,
          _ => ChangeOp.updated,
        },
        data: (msg['row'] as Map?)?.cast<String, dynamic>() ?? const {},
        actorId: actor,
        at: DateTime.now(),
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _channelSub?.cancel();
    _channel?.sink.close();
    for (final s in _subs.values) {
      s.controller.close();
    }
    _subs.clear();
    _status.close();
    _changes.close();
  }
}
