import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../sync/outbox.dart';
import '../sync/view_cache.dart';

/// State of one view: entity → id → row.
class ViewData {
  ViewData(this.entities);
  final Map<String, Map<String, Map<String, dynamic>>> entities;

  List<Map<String, dynamic>> rows(String entity) =>
      entities[entity]?.values.toList() ?? const [];
}

/// Whether a row belongs to a view — the client's copy of the server's
/// `View.Matches`, used to place pending changes into views.
typedef ViewFilter = bool Function(String entity, Map<String, dynamic> row);

class _Sub {
  _Sub(this.view, this.params, this.controller, this.accept);
  final String view;
  final Map<String, dynamic> params;
  final StreamController<ViewData> controller;
  final ViewFilter? accept;

  /// The server's state (snapshot + changes), without the overlay.
  Entities state = {};

  /// Has a snapshot, live or cached.
  var hasData = false;

  String get cacheKey => viewCacheKey(view, params);
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
///
/// With an [Outbox], views show its pending mutations on top of the server's
/// state, and changes coming back with a mutation id confirm them. With a
/// [ViewCache], the last state of each view is kept on the device and shown
/// until the snapshot arrives (e.g. when started offline).
class SyncClient {
  SyncClient(
    this.wsUri,
    this.token, {
    this.onUnauthorized,
    this.silenceTimeout = const Duration(seconds: 12),
    this.readyTimeout = const Duration(seconds: 10),
    this.maxBackoff = const Duration(seconds: 3),
    this.outbox,
    this.cache,
  }) {
    _outboxSub = outbox?.changes.listen((_) => _emitAll());
    cache?.loaded.then((_) {
      for (final s in _subs.values) {
        _fromCache(s);
      }
    });
    _connect();
  }

  final Outbox? outbox;
  final ViewCache? cache;
  StreamSubscription<void>? _outboxSub;

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
  // This connection gets heartbeats: silence then means it's dead. A server
  // without them (older version) is only judged by the socket closing.
  var _heartbeats = false;
  var _backoff = _minBackoff;
  var _disposed = false;
  final _random = Random();

  final _status = StreamController<bool>.broadcast();
  var connected = false;

  /// true = connected and authenticated.
  Stream<bool> get status => _status.stream;

  /// Subscribes to a view. Cancelling the stream sends `unsub`.
  ///
  /// [accept] lets pending mutations add rows to the view (creates, or
  /// changes that move a row into it) and drop rows that no longer match;
  /// without it they only change or remove rows already in it.
  Stream<ViewData> watch(
    String view, [
    Map<String, dynamic> params = const {},
    ViewFilter? accept,
  ]) {
    late final StreamController<ViewData> ctrl;
    final id = 's${_nextId++}';
    ctrl = StreamController<ViewData>(
      onListen: () {
        final sub = _subs[id] = _Sub(view, params, ctrl, accept);
        _fromCache(sub);
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
    if (connected && !_heartbeats) return; // can't tell; trust the socket
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
    _heartbeats = false;
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
      if (connected && !_heartbeats) return;
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
    if (type == 'ping') {
      _heartbeats = true;
      return;
    }
    if (type == 'ready') {
      _backoff = _minBackoff;
      _setConnected(true);
      return;
    }
    final sub = _subs[msg['sub']];
    if (sub == null) return;
    // Our own write came back: it leaves the overlay shortly.
    if (msg['mutation'] case final String m) outbox?.confirm(m);

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
      case 'remove':
        sub.state[msg['entity'] as String]?.remove(msg['id']);
      case 'error':
        sub.controller.addError(Exception('${msg['code']}: ${msg['msg']}'));
        return;
      default:
        return;
    }
    sub.hasData = true;
    cache?.put(sub.cacheKey, sub.state);
    _emit(sub);
  }

  void _fromCache(_Sub sub) {
    if (sub.hasData) return;
    final cached = cache?.get(sub.cacheKey);
    if (cached == null) return;
    sub.state = cached;
    sub.hasData = true;
    _emit(sub);
  }

  void _emitAll() {
    for (final s in _subs.values) {
      _emit(s);
    }
  }

  void _emit(_Sub sub) {
    if (!sub.hasData || sub.controller.isClosed) return;
    sub.controller.add(ViewData(_withOverlay(sub)));
  }

  /// The server's state of [sub] with the pending mutations applied in order.
  Entities _withOverlay(_Sub sub) {
    final out = {for (final e in sub.state.entries) e.key: Map.of(e.value)};
    final accept = sub.accept;
    for (final m in outbox?.overlay ?? const <Mutation>[]) {
      switch (m.kind) {
        case MutationKind.create:
          if (accept != null && accept(m.entity, m.fields)) {
            (out[m.entity] ??= {})[m.entityId] = m.fields;
          }
        case MutationKind.patch:
          final current =
              out[m.entity]?[m.entityId] ?? _knownRow(m.entity, m.entityId);
          if (current == null) continue;
          final row = {...current, ...m.fields};
          if (accept == null) {
            if (out[m.entity]?.containsKey(m.entityId) ?? false) {
              out[m.entity]![m.entityId] = row;
            }
          } else if (accept(m.entity, row)) {
            (out[m.entity] ??= {})[m.entityId] = row;
          } else {
            out[m.entity]?.remove(m.entityId);
          }
        case MutationKind.delete:
          out[m.entity]?.remove(m.entityId);
          for (final (entity, field) in m.cascade) {
            out[entity]?.removeWhere((_, r) => r[field] == m.entityId);
          }
      }
    }
    return out;
  }

  /// A row as any open view (or a pending create) knows it.
  Map<String, dynamic>? _knownRow(String entity, String id) {
    for (final s in _subs.values) {
      if (s.state[entity]?[id] case final row?) return row;
    }
    for (final m in outbox?.overlay ?? const <Mutation>[]) {
      if (m.kind == MutationKind.create &&
          m.entity == entity &&
          m.entityId == id) {
        return m.fields;
      }
    }
    return null;
  }

  /// The server's state of a row, if an open view has it (for showing what a
  /// failed change would have changed).
  Map<String, dynamic>? serverRow(String entity, String id) {
    for (final s in _subs.values) {
      if (s.state[entity]?[id] case final row?) return row;
    }
    return null;
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _watchdog?.cancel();
    _outboxSub?.cancel();
    cache?.close();
    _channelSub?.cancel();
    _channel?.sink.close();
    for (final s in _subs.values) {
      s.controller.close();
    }
    _subs.clear();
    _status.close();
  }
}
