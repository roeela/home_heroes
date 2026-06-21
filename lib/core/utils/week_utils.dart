/// Returns the Monday (start of week) for the given date (or today).
DateTime getWeekStart([DateTime? now]) {
  final date = (now ?? DateTime.now()).toLocal();
  final daysFromMonday = date.weekday - 1; // Monday = weekday 1
  return DateTime(date.year, date.month, date.day - daysFromMonday);
}

/// Human-readable label for a week, e.g. "2/6 - 8/6".
String weekLabel(DateTime weekStart) {
  final end = weekStart.add(const Duration(days: 6));
  return '${weekStart.day}/${weekStart.month} - ${end.day}/${end.month}';
}

/// A stable string key for a week start date, e.g. "2024-06-03".
String weekStartId(DateTime weekStart) =>
    '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
