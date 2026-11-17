import 'package:intl/intl.dart';

import 'l10n.dart';

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// “Today”, “tomorrow”, “yesterday” or e.g. “Fri, 20 Nov”.
String relativeDay(AppLocalizations l, DateTime d) {
  final today = dateOnly(DateTime.now());
  final diff = dateOnly(d).difference(today).inDays;
  return switch (diff) {
    0 => l.dateToday,
    1 => l.dateTomorrow,
    -1 => l.dateYesterday,
    _ => DateFormat('E, d MMM').format(d),
  };
}

String hm(DateTime d) => DateFormat.Hm().format(d);
