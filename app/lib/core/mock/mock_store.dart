import 'dart:async';

import '../change.dart';

/// Udawany backend: dokumenty w pamięci + strumień zmian.
///
/// Zachowuje się jak przyszły serwer: zapis ma lekkie opóźnienie, a każda
/// zmiana trafia do [changes] (odpowiednik WebSocketu). Repozytoria modułów
/// budują na nim swoje typowane API; później podmienimy je na wersje HTTP.
class MockStore {
  MockStore({this.latency = const Duration(milliseconds: 120)});

  final Duration latency;
  final _data = <String, Map<String, Map<String, dynamic>>>{};
  final _changes = StreamController<Change>.broadcast();
  int _seq = 0;
  int _idSeq = 0;

  Stream<Change> get changes => _changes.stream;

  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(_idSeq++).toRadixString(36)}';

  List<Map<String, dynamic>> list(String collection) =>
      _data[collection]?.values.map(Map<String, dynamic>.of).toList() ?? [];

  /// Aktualny stan kolekcji, a potem nowy po każdej zmianie w niej.
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

  /// Dane startowe — bez opóźnienia i bez emitowania zmian.
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
