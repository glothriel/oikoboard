import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show TimeOfDay;
import 'package:oikoboard/modules/todo/models.dart';

void main() {
  TodoItem item(Map<String, dynamic> extra) => TodoItem.fromJson({
    'id': 'i',
    'list_id': 'l',
    'title': 'Odebrać paczkę',
    'created_at': '2026-11-01T10:00:00Z',
    ...extra,
  });

  test('due time: both wire formats, cleared with the date', () {
    // REST sends "HH:MM", the change feed (to_jsonb) "HH:MM:SS".
    for (final wire in ['17:30', '17:30:00']) {
      final i = item({'due': '2026-11-20', 'due_time': wire});
      expect(i.dueTime, const TimeOfDay(hour: 17, minute: 30));
      expect(i.dueAt, DateTime(2026, 11, 20, 17, 30));
      expect(i.toJson()['due_time'], '17:30');
    }
    final i = item({'due': '2026-11-20', 'due_time': '17:30'});
    expect(i.copyWith(title: 'x').dueTime, isNotNull);
    expect(i.copyWith(due: null).dueTime, isNull);
    expect(i.copyWith(dueTime: null).due, DateTime(2026, 11, 20));
  });

  test('a task due today at a past time is overdue', () {
    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    expect(item({'due': today}).overdue, isFalse);
    if (now.hour > 0 || now.minute > 0) {
      expect(item({'due': today, 'due_time': '00:00'}).overdue, isTrue);
    }
    if (now.hour < 23 || now.minute < 59) {
      expect(item({'due': today, 'due_time': '23:59'}).overdue, isFalse);
    }
  });
}
