import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../change.dart';

/// State of one view: entity → id → row.
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

/// One WebSocket connection per app, many view subscriptions.
///
/// Protocol (docs/backend-realtime.md): auth → sub → snapshot, then
/// upsert/remove. After a disconnect it reconnects with a short backoff and
/// re-subscribes every open view — each gets a fresh snapshot.
///
/// The server sends `{"t":"ping"}` every 5 s, so silence longer than
/// [silenceTimeout] means a half-open socket (sleep, Wi-Fi ↔ LTE): it is
/// dropped and replaced.
class SyncClient {
  SyncClient(
    this.wsUri,
    this.token, {
    this.onUnauthorized,
    this.silenceTimeout = const Duration(seconds: 12),
    this.readyTimeout = const Duration(seconds: 10),
    this.maxBackoff = const Duration(seconds: 3),
  }) {
    _connect();
  }

  final Uri wsUri;
  final String token;
  final void Function()? onUnauthorized;
  final Duration silenceTimeout;
  final Duration readyTimeout;
  final Duration maxBackoff;

  static const _minBackoff = Duration(milliseconds: 500);

  final _subs = <String, _Sub>{};
  var _nextId = 0;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;
  // Incremented on every connect; callbacks of older channels are ignored.
  var _gen = 0;
  Timer? _retry;
  Timer? _watchdog;
  DateTime _lastMessage = DateTime.now();
  var _backoff = _minBackoff;
  var _disposed = false;
  final _random = Random();

  final _status = StreamController<bool>.broadcast();
  final _changes = StreamController<Change>.broadcast();
  final _seenSeqs = <int>{}; // LinkedHashSet — keeps insertion order
  var connected = false;

  /// true = connected and authenticated.
  Stream<bool> get status => _status.stream;

  /// Changes from all subscriptions (deduplicated) — for notifications.
  Stream<Change> get changes => _changes.stream;

  /// Subscribes to a view. Cancelling the stream sends `unsub`.
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

  /// Call when the app comes back to the foreground or the network changes:
  /// a connection that is down or has been silent for a while is replaced
  /// right away instead of waiting for the backoff or the watchdog.
  void checkNow() {
    if (_disposed) return;
    final quiet = DateTime.now().difference(_lastMessage);
    final fresh = connected
        ? const Duration(seconds: 7) // a heartbeat came recently
        : const Duration(seconds: 3); // a connect is already under way
    if (_channel != null && quiet < fresh) return;
    _backoff = _minBackoff;
    _reconnect(immediately: true);
  }

  void _connect() {
    if (_disposed) return;
    final gen = ++_gen;
    _retry?.cancel();
    _lastMessage = DateTime.now();
    final WebSocketChannel channel;
    try {
      channel = WebSocketChannel.connect(wsUri);
    } catch (_) {
      _reconnect();
      return;
    }
    _channel = channel;
    channel.ready.then((_) {}, onError: (_) => _onClosed(gen, channel));
    _channelSub = channel.stream.listen(
      (raw) {
        if (gen == _gen) _onMessage(raw);
      },
      onDone: () => _onClosed(gen, channel),
      onError: (_) {},
      cancelOnError: false,
    );
    _send({'t': 'auth', 'token': token});
    for (final id in _subs.keys) {
      _sendSub(id);
    }
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (gen != _gen) return;
      final quiet = DateTime.now().difference(_lastMessage);
      if (quiet > (connected ? silenceTimeout : readyTimeout)) {
        _reconnect(immediately: true);
      }
    });
  }

  void _onClosed(int gen, WebSocketChannel channel) {
    if (_disposed || gen != _gen) return;
    if (channel.closeCode == 4001) {
      _drop();
      onUnauthorized?.call();
      return;
    }
    _reconnect();
  }

  /// Tears the current channel down; its late callbacks are ignored.
  void _drop() {
    _gen++;
    _watchdog?.cancel();
    _channelSub?.cancel();
    _channelSub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setConnected(false);
  }

  void _reconnect({bool immediately = false}) {
    if (_disposed) return;
    _drop();
    _retry?.cancel();
    if (immediately) {
      _connect();
      return;
    }
    final jitter = Duration(milliseconds: _random.nextInt(300));
    _retry = Timer(_backoff + jitter, _connect);
    _backoff = Duration(
      milliseconds: min(_backoff.inMilliseconds * 2, maxBackoff.inMilliseconds),
    );
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
      // connection is gone — the reconnect re-sends the subscriptions
    }
  }

  void _sendSub(String id) {
    final s = _subs[id];
    if (s == null) return;
    _send({'t': 'sub', 'id': id, 'view': s.view, 'params': s.params});
  }

  void _onMessage(dynamic raw) {
    _lastMessage = DateTime.now();
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final type = msg['t'] as String;
    if (type == 'ping') return;
    if (type == 'ready') {
      _backoff = _minBackoff;
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
    if (!_seenSeqs.add(seq)) return; // same change via another subscription
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
    _watchdog?.cancel();
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
