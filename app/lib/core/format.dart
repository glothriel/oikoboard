import 'package:intl/intl.dart';

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// „dziś”, „jutro”, „wczoraj” albo np. „pt, 20 lis”.
String relativeDay(DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  return switch (diff) {
    0 => 'dziś',
    1 => 'jutro',
    -1 => 'wczoraj',
    _ => DateFormat('E, d MMM').format(d),
  };
}

String hm(DateTime d) => DateFormat.Hm().format(d);
