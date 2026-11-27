import 'package:flutter_test/flutter_test.dart';
import 'package:oikoboard/core/mock/mock_store.dart';
import 'package:oikoboard/modules/todo/models.dart';
import 'package:oikoboard/modules/todo/repository.dart';

void main() {
  TodoItem item(Map<String, dynamic> extra) => TodoItem.fromJson({
    'id': 'i',
    'list_id': 'l',
    'title': 'Task',
    'created_at': '2026-11-01T10:00:00Z',
    ...extra,
  });

  test('keepForever: JSON round trip and copyWith', () {
    expect(item({}).keepForever, isFalse);
    final i = item({'keep_forever': true});
    expect(i.keepForever, isTrue);
    expect(i.toJson()['keep_forever'], isTrue);
    expect(TodoItem.fromJson(i.toJson()).keepForever, isTrue);
    expect(i.copyWith(title: 'x').keepForever, isTrue);
    expect(i.copyWith(keepForever: false).keepForever, isFalse);
    expect(item({}).copyWith(keepForever: true).keepForever, isTrue);
  });

  test('MockTodoRepository stores keepForever on add and update', () async {
    final store = MockStore(latency: Duration.zero);
    final repo = MockTodoRepository(store, actorId: 'tata');
    final added = await repo.addItem('l', 'Keep me', keepForever: true);
    TodoItem stored() => store
        .list(itemsEntity)
        .map(TodoItem.fromJson)
        .singleWhere((i) => i.id == added.id);
    expect(stored().keepForever, isTrue);

    await repo.updateItem(added, added.copyWith(keepForever: false));
    expect(stored().keepForever, isFalse);
    final off = await repo.addItem('l', 'Plain');
    expect(off.keepForever, isFalse);
  });
}
