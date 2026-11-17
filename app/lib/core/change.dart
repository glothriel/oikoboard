/// Jedna zmiana w danych — to samo, co docelowo serwer będzie wysyłał
/// przez WebSocket (wiersz z tabeli `changes`).
enum ChangeOp { created, updated, deleted }

class Change {
  const Change({
    required this.seq,
    required this.collection,
    required this.entityId,
    required this.op,
    required this.data,
    required this.actorId,
    required this.at,
  });

  /// Rosnący numer zmiany — klient pamięta ostatni i po reconnect dociąga resztę.
  final int seq;

  /// Np. `todo_items`, `calendar_events`.
  final String collection;
  final String entityId;
  final ChangeOp op;

  /// Stan encji po zmianie (przy usunięciu — ostatni znany stan).
  final Map<String, dynamic> data;

  /// Kto zrobił zmianę (id członka rodziny).
  final String actorId;
  final DateTime at;
}
