import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../api/api_client.dart';
import 'text_store.dart';

enum MutationKind { create, patch, delete }

/// One queued write: the REST call plus what it does to the data, so views
/// can show it before the server confirms it (the optimistic overlay).
class Mutation {
  Mutation({
    String? id,
    required this.kind,
    required this.method,
    required this.path,
    this.body,
    required this.entity,
    required this.entityId,
    this.fields = const {},
    this.cascade = const [],
    this.label = '',
    DateTime? createdAt,
  }) : id = id ?? uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  /// Sent as `X-Mutation-Id`; comes back with every change it causes.
  final String id;
  final MutationKind kind;
  final String method;
  final String path;
  final Map<String, dynamic>? body;

  /// The row it affects, as the views know it.
  final String entity;
  final String entityId;

  /// create: the whole row; patch: the changed fields.
  final Map<String, dynamic> fields;

  /// delete: rows of other entities that go with it, as (entity, field)
  /// pairs — e.g. `('todo_items', 'list_id')` for a list.
  final List<(String, String)> cascade;

  /// A human-readable name of the row (a title), for the UI.
  final String label;
  final DateTime createdAt;

  factory Mutation.create(
    String path,
    String entity,
    Map<String, dynamic> row, {
    Map<String, dynamic>? body,
    String label = '',
  }) => Mutation(
    kind: MutationKind.create,
    method: 'POST',
    path: path,
    body: body ?? row,
    entity: entity,
    entityId: row['id'] as String,
    fields: row,
    label: label,
  );

  factory Mutation.patch(
    String path,
    String entity,
    String id,
    Map<String, dynamic> fields, {
    String label = '',
  }) => Mutation(
    kind: MutationKind.patch,
    method: 'PATCH',
    path: path,
    body: fields,
    entity: entity,
    entityId: id,
    fields: fields,
    label: label,
  );

  factory Mutation.delete(
    String path,
    String entity,
    String id, {
    List<(String, String)> cascade = const [],
    String label = '',
  }) => Mutation(
    kind: MutationKind.delete,
    method: 'DELETE',
    path: path,
    entity: entity,
    entityId: id,
    cascade: cascade,
    label: label,
  );

  factory Mutation.fromJson(Map<String, dynamic> j) => Mutation(
    id: j['id'] as String,
    kind: MutationKind.values.byName(j['kind'] as String),
    method: j['method'] as String,
    path: j['path'] as String,
    body: (j['body'] as Map?)?.cast<String, dynamic>(),
    entity: j['entity'] as String,
    entityId: j['entity_id'] as String,
    fields: (j['fields'] as Map?)?.cast<String, dynamic>() ?? const {},
    cascade: [
      for (final c in (j['cascade'] as List?) ?? const [])
        ((c as List)[0] as String, c[1] as String),
    ],
    label: j['label'] as String? ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'method': method,
    'path': path,
    'body': body,
    'entity': entity,
    'entity_id': entityId,
    'fields': fields,
    'cascade': [
      for (final (e, f) in cascade) [e, f],
    ],
    'label': label,
    'created_at': createdAt.toIso8601String(),
  };
}

/// A mutation the server rejected (the dead letter).
class FailedMutation {
  FailedMutation(this.mutation, this.status, this.message, DateTime? at)
    : at = at ?? DateTime.now();
  final Mutation mutation;
  final int status;
  final String message;
  final DateTime at;

  factory FailedMutation.fromJson(Map<String, dynamic> j) => FailedMutation(
    Mutation.fromJson((j['mutation'] as Map).cast<String, dynamic>()),
    j['status'] as int,
    j['message'] as String,
    DateTime.parse(j['at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'mutation': mutation.toJson(),
    'status': status,
    'message': message,
    'at': at.toIso8601String(),
  };
}

/// Sends one mutation; throws [ApiException] when the server rejects it and
/// anything else when it can't be reached.
typedef MutationSender = Future<void> Function(Mutation m);

/// Persistent queue of writes (docs/backend-realtime.md, "Offline writes").
///
/// Mutations are sent one at a time, in order. Network errors, 5xx, 408 and
/// 429 are retried; any other 4xx moves the mutation to [failed]. A sent
/// mutation stays in the overlay until its change comes back over the
/// WebSocket ([confirm]) or, failing that, for [echoTimeout].
class Outbox {
  Outbox({
    required this.send,
    TextStore? storage,
    this.maxBackoff = const Duration(seconds: 3),
    this.echoTimeout = const Duration(seconds: 10),
  }) : storage = storage ?? MemoryTextStore() {
    _ready = _load();
  }

  final MutationSender send;
  final TextStore storage;
  final Duration maxBackoff;
  final Duration echoTimeout;

  final _pending = <Mutation>[];
  final _failed = <FailedMutation>[];
  // Sent, waiting for the change to come back (in memory only — after a
  // restart the snapshot already contains them).
  final _sent = <String, Mutation>{};
  final _echoed = <String>{};
  late final Future<void> _ready;
  var _busy = false;
  var _disposed = false;
  Timer? _retry;
  late var _backoff = _firstBackoff;

  Duration get _firstBackoff => maxBackoff < const Duration(milliseconds: 500)
      ? maxBackoff
      : const Duration(milliseconds: 500);

  final _changes = StreamController<void>.broadcast();
  final _failures = StreamController<FailedMutation>.broadcast();

  /// Fires whenever [pending], [failed] or the overlay change.
  Stream<void> get changes => _changes.stream;

  /// Mutations the server has just rejected.
  Stream<FailedMutation> get failures => _failures.stream;

  /// Not yet accepted by the server, oldest first.
  List<Mutation> get pending => List.unmodifiable(_pending);
  List<FailedMutation> get failed => List.unmodifiable(_failed);

  /// What views should show on top of the server's state, in order.
  Iterable<Mutation> get overlay =>
      [..._sent.values, ..._pending].where((m) => !_echoed.contains(m.id));

  /// Loaded from storage (tests).
  Future<void> get ready => _ready;

  Future<void> _load() async {
    try {
      final raw = await storage.load();
      if (raw != null) {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        _pending.insertAll(0, [
          for (final m in (j['pending'] as List).cast<Map<String, dynamic>>())
            Mutation.fromJson(m),
        ]);
        _failed.insertAll(0, [
          for (final f in (j['failed'] as List).cast<Map<String, dynamic>>())
            FailedMutation.fromJson(f),
        ]);
      }
    } catch (_) {
      // unreadable — start empty
    }
    _notify();
    unawaited(_pump());
  }

  void _save() {
    unawaited(
      storage
          .save(
            jsonEncode({
              'pending': [for (final m in _pending) m.toJson()],
              'failed': [for (final f in _failed) f.toJson()],
            }),
          )
          .catchError((_) {}),
    );
  }

  void _notify() {
    if (!_disposed) _changes.add(null);
  }

  void enqueue(Mutation m) {
    if (_disposed) return;
    _pending.add(m);
    _save();
    _notify();
    unawaited(_pump());
  }

  /// A change with this mutation id came back over the WebSocket: the
  /// server's state now contains it.
  void confirm(String mutationId) {
    if (_sent.remove(mutationId) != null) {
      _notify();
      return;
    }
    if (_pending.any((m) => m.id == mutationId) && _echoed.add(mutationId)) {
      _notify(); // in flight; dropped when the response arrives
    }
  }

  /// Try sending now (e.g. the connection is back).
  void kick() {
    _retry?.cancel();
    _retry = null;
    _backoff = _firstBackoff;
    unawaited(_pump());
  }

  /// Puts a failed mutation back at the end of the queue.
  void retry(FailedMutation f) {
    if (!_failed.remove(f)) return;
    _pending.add(f.mutation);
    _save();
    _notify();
    unawaited(_pump());
  }

  void discard(FailedMutation f) {
    if (!_failed.remove(f)) return;
    _save();
    _notify();
  }

  Future<void> _pump() async {
    await _ready;
    if (_busy || _disposed) return;
    _busy = true;
    try {
      while (_pending.isNotEmpty && !_disposed && _retry == null) {
        final m = _pending.first;
        final outcome = await _attempt(m);
        if (_disposed) return;
        if (outcome == null) {
          _scheduleRetry();
          return;
        }
        _pending.removeAt(0);
        if (outcome case final FailedMutation f) {
          _echoed.remove(m.id);
          _failed.add(f);
          _failures.add(f);
        } else if (!_echoed.remove(m.id)) {
          _sent[m.id] = m;
          Timer(echoTimeout, () {
            if (_sent.remove(m.id) != null) _notify();
          });
        }
        _backoff = _firstBackoff;
        _save();
        _notify();
      }
    } finally {
      _busy = false;
    }
  }

  /// true = accepted, a [FailedMutation] = rejected, null = try again later.
  Future<Object?> _attempt(Mutation m) async {
    try {
      await send(m);
      return true;
    } on ApiException catch (e) {
      // Already gone (e.g. a retried delete whose response was lost).
      if (m.kind == MutationKind.delete && e.status == 404) return true;
      if (e.status >= 500 ||
          e.status == 401 ||
          e.status == 408 ||
          e.status == 429) {
        return null;
      }
      return FailedMutation(m, e.status, e.message, null);
    } catch (_) {
      return null;
    }
  }

  void _scheduleRetry() {
    final jitter = Duration(milliseconds: Random().nextInt(300));
    _retry = Timer(_backoff + jitter, () {
      _retry = null;
      unawaited(_pump());
    });
    _backoff = Duration(
      milliseconds: min(_backoff.inMilliseconds * 2, maxBackoff.inMilliseconds),
    );
  }

  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _changes.close();
    _failures.close();
  }
}

/// The fields of [after] that differ from [before], limited to [fields].
Map<String, dynamic> changedFields(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
  Iterable<String> fields,
) => {
  for (final f in fields)
    if (jsonEncode(before[f]) != jsonEncode(after[f])) f: after[f],
};
