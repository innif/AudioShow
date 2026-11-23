/// "1:05" style; hours only when needed.
String formatTime(Duration d) {
  final neg = d.isNegative;
  d = d.abs();
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final body = h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
  return neg ? '-$body' : body;
}

/// "0,5 s", "2 s"
String formatSeconds(Duration d) {
  final s = d.inMilliseconds / 1000;
  final text = s == s.roundToDouble() ? s.round().toString() : s.toString().replaceAll('.', ',');
  return '$text s';
}

/// Parses "1:05", "1:05.5", "65", "65,5" into a Duration; null if invalid.
Duration? parseTime(String input) {
  final t = input.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length > 3) return null;
  double total = 0;
  for (final p in parts) {
    final v = double.tryParse(p);
    if (v == null || v < 0) return null;
    total = total * 60 + v;
  }
  return Duration(milliseconds: (total * 1000).round());
}
