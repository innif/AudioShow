import 'package:flutter/foundation.dart';

/// One evening: an ordered list of `artist/fileName` references.
@immutable
class Show {
  final String name;
  final List<String> entries;
  const Show({required this.name, this.entries = const []});

  Show copyWith({List<String>? entries}) => Show(name: name, entries: entries ?? this.entries);

  Map<String, dynamic> toJson() => {'version': 1, 'entries': entries};

  factory Show.fromJson(String name, Map<String, dynamic> json) {
    final e = json['entries'];
    if (e is! List) throw const FormatException('Show without entries');
    return Show(name: name, entries: List.unmodifiable(e.whereType<String>()));
  }
}
