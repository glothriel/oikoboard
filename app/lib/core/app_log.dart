import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend.dart';
import 'data.dart';

enum LogLevel { debug, info, warn }

/// One structured log record.
class LogEntry {
  LogEntry(this.level, this.source, this.msg, this.attrs, [DateTime? ts])
    : ts = ts ?? DateTime.now().toUtc();

  final DateTime ts;
  final LogLevel level;

  /// The component that logged (e.g. `ble`); sent as the `component` attribute.
  final String source;
  final String msg;
  final Map<String, Object?> attrs;

  /// The wire form of a `log` message record (docs/backend-realtime.md).
  Map<String, dynamic> toJson() => {
    'ts': ts.toIso8601String(),
    'level': level.name,
    'msg': msg,
    'attrs': {...attrs, 'component': source},
  };
}

/// Receives a batch (at most [AppLog.batchSize] entries); returns whether it
/// was taken. A refused batch stays in the buffer.
typedef LogSink = bool Function(List<Map<String, dynamic>> batch);

/// Generic structured app logger. Entries go to [debugPrint] and to a ring
/// buffer; [flush] hands the buffer to [sink] (the server, when connected).
/// With no sink (mock backend) they only stay in the buffer. The buffer holds
/// [capacity] entries, the oldest dropped first.
class AppLog {
  AppLog({this.sink, this.capacity = 500, this.echo = true});

  static const batchSize = 20;

  /// Where batches go; set when the connection is up.
  LogSink? sink;
  final int capacity;

  /// Also print each entry with [debugPrint].
  final bool echo;
  final _buffer = Queue<LogEntry>();

  /// Entries waiting to be sent.
  List<LogEntry> get buffered => List.unmodifiable(_buffer);

  void debug(String source, String msg, [Map<String, Object?>? attrs]) =>
      _add(LogLevel.debug, source, msg, attrs);
  void info(String source, String msg, [Map<String, Object?>? attrs]) =>
      _add(LogLevel.info, source, msg, attrs);
  void warn(String source, String msg, [Map<String, Object?>? attrs]) =>
      _add(LogLevel.warn, source, msg, attrs);

  void _add(
    LogLevel level,
    String source,
    String msg,
    Map<String, Object?>? attrs,
  ) {
    final e = LogEntry(level, source, msg, attrs ?? const {});
    if (echo) debugPrint('[${level.name}] $source: $msg ${e.attrs}');
    _buffer.add(e);
    while (_buffer.length > capacity) {
      _buffer.removeFirst();
    }
    flush();
  }

  /// Sends the buffered entries in batches while the [sink] takes them.
  void flush() {
    final s = sink;
    if (s == null) return;
    while (_buffer.isNotEmpty) {
      final n = _buffer.length < batchSize ? _buffer.length : batchSize;
      final batch = _buffer.take(n).map((e) => e.toJson()).toList();
      if (!s(batch)) return;
      for (var i = 0; i < n; i++) {
        _buffer.removeFirst();
      }
    }
  }
}

/// The app's logger. Mock backend: ring buffer and `debugPrint` only. API
/// mode: batches go to the server over the WebSocket; entries logged while
/// offline wait in the ring buffer and go out when the connection is up.
final appLogProvider = Provider<AppLog>((ref) {
  final log = AppLog();
  if (ref.watch(backendProvider) is! ApiBackend) return log;
  final client = ref.watch(syncClientProvider);
  log.sink = client.sendLogs;
  final status = client.status.listen((up) {
    if (up) log.flush();
  });
  ref.onDispose(status.cancel);
  ref.onDispose(() => log.sink = null);
  return log;
});
