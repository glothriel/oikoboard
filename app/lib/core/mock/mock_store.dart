import 'dart:async';

import '../change.dart';

/// Fake backend: documents in memory + a stream of changes.
///
/// Behaves like the server: a write has a slight delay and every change goes
/// to [changes] (the WebSocket's counterpart). The modules' mock repositories
/// build their typed API on it.
class MockStore {
  MockStore({this.latency = const Duration(milliseconds: 120)});

  final Duration latency;
  final _data = <String, Map<String, Map<String, dynamic>>>{};
  final _changes = StreamController<Change>.broadcast();
  int _seq = 0;
  int _idSeq = 0;

  Stream<Change> get changes => _changes.stream;

  final _online = <String>{'ola'};
  final _onlineCtrl = StreamController<Set<String>>.broadcast();

  /// Members online besides the signed-in one (mock presence).
  Set<String> get online => Set.of(_online);

  /// [online] after each change.
  Stream<Set<String>> get onlineChanges => _onlineCtrl.stream;

  void setOnline(String memberId, bool on) {
    if (on ? !_online.add(memberId) : !_online.remove(memberId)) return;
    _onlineCtrl.add(online);
  }

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idSeq++).toRadixString(36)}';

  List<Map<String, dynamic>> list(String collection) =>
      _data[collection]?.values.map(Map<String, dynamic>.of).toList() ?? [];

  /// The collection's current state, then the new one after each change.
  Stream<List<Map<String, dynamic>>> watch(String collection) {
    late final StreamController<List<Map<String, dynamic>>> ctrl;
    StreamSubscription<Change>? sub;
    ctrl = StreamController(
      onListen: () {
        ctrl.add(list(collection));
        sub = changes
            .where((c) => c.collection == collection)
            .listen((_) => ctrl.add(list(collection)));
      },
      onCancel: () => sub?.cancel(),
    );
    return ctrl.stream;
  }

  /// Initial data — no delay, no change events.
  void seed(String collection, Map<String, dynamic> doc) {
    (_data[collection] ??= {})[doc['id'] as String] = Map.of(doc);
  }

  Future<Map<String, dynamic>> put(
    String collection,
    Map<String, dynamic> doc, {
    required String actorId,
  }) async {
    await Future<void>.delayed(latency);
    final id = doc['id'] as String? ?? newId();
    final docs = _data[collection] ??= {};
    final existed = docs.containsKey(id);
    final stored = {...doc, 'id': id};
    docs[id] = stored;
    _emit(
      collection,
      id,
      existed ? ChangeOp.updated : ChangeOp.created,
      stored,
      actorId,
    );
    return Map.of(stored);
  }

  /// Changes only [fields] of an existing document (like a PATCH).
  Future<void> patch(
    String collection,
    String id,
    Map<String, dynamic> fields, {
    required String actorId,
  }) async {
    if (fields.isEmpty) return;
    await Future<void>.delayed(latency);
    final doc = _data[collection]?[id];
    if (doc == null) return;
    doc.addAll(fields);
    _emit(collection, id, ChangeOp.updated, doc, actorId);
  }

  Future<void> delete(
    String collection,
    String id, {
    required String actorId,
  }) async {
    await Future<void>.delayed(latency);
    final removed = _data[collection]?.remove(id);
    if (removed != null) {
      _emit(collection, id, ChangeOp.deleted, removed, actorId);
    }
  }

  void _emit(
    String collection,
    String id,
    ChangeOp op,
    Map<String, dynamic> data,
    String actorId,
  ) {
    _changes.add(
      Change(
        seq: ++_seq,
        collection: collection,
        entityId: id,
        op: op,
        data: Map.of(data),
        actorId: actorId,
        at: DateTime.now(),
      ),
    );
  }
}
