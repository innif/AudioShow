import 'package:flutter/foundation.dart';

/// What happens to a *running* cue when the next GO comes.
enum GoBehavior { fadeOut, stop, keepRunning }

GoBehavior? goBehaviorFromName(Object? name) {
  for (final b in GoBehavior.values) {
    if (b.name == name) return b;
  }
  return null;
}

/// Per-file settings, stored in the artist folder's `cues.json`.
@immutable
class CueSettings {
  final Duration startAt;
  final Duration? endAt;

  /// 0–100 %.
  final int volume;
  final Duration fadeIn;

  /// Override of the global GO behavior, applied to this cue while it runs.
  final GoBehavior? goBehavior;
  final Duration? goFade;
  final String note;

  /// Unknown keys from `cues.json`, preserved on write.
  final Map<String, dynamic> extra;

  const CueSettings({
    this.startAt = Duration.zero,
    this.endAt,
    this.volume = 100,
    this.fadeIn = Duration.zero,
    this.goBehavior,
    this.goFade,
    this.note = '',
    this.extra = const {},
  });

  static const _known = {
    'startAt',
    'endAt',
    'volume',
    'fadeIn',
    'goBehavior',
    'goFade',
    'note',
  };

  static Duration? _dur(Object? v) {
    if (v is num && v.isFinite && v >= 0) {
      return Duration(microseconds: (v * 1000000).round());
    }
    return null;
  }

  static double _secs(Duration d) => d.inMicroseconds / 1000000;

  factory CueSettings.fromJson(Map<String, dynamic> json) {
    final vol = json['volume'];
    final note = json['note'];
    return CueSettings(
      startAt: _dur(json['startAt']) ?? Duration.zero,
      endAt: _dur(json['endAt']),
      volume: vol is num ? vol.round().clamp(0, 100) : 100,
      fadeIn: _dur(json['fadeIn']) ?? Duration.zero,
      goBehavior: goBehaviorFromName(json['goBehavior']),
      goFade: _dur(json['goFade']),
      note: note is String ? note : '',
      extra: Map.unmodifiable({
        for (final e in json.entries)
          if (!_known.contains(e.key)) e.key: e.value,
      }),
    );
  }

  Map<String, dynamic> toJson() => {
        ...extra,
        if (startAt != Duration.zero) 'startAt': _secs(startAt),
        if (endAt != null) 'endAt': _secs(endAt!),
        if (volume != 100) 'volume': volume,
        if (fadeIn != Duration.zero) 'fadeIn': _secs(fadeIn),
        if (goBehavior != null) 'goBehavior': goBehavior!.name,
        if (goFade != null) 'goFade': _secs(goFade!),
        if (note.isNotEmpty) 'note': note,
      };

  bool get isDefault => toJson().isEmpty;

  CueSettings copyWith({
    Duration? startAt,
    Duration? endAt,
    bool clearEndAt = false,
    int? volume,
    Duration? fadeIn,
    GoBehavior? goBehavior,
    bool clearGoBehavior = false,
    Duration? goFade,
    bool clearGoFade = false,
    String? note,
  }) =>
      CueSettings(
        startAt: startAt ?? this.startAt,
        endAt: clearEndAt ? null : (endAt ?? this.endAt),
        volume: volume ?? this.volume,
        fadeIn: fadeIn ?? this.fadeIn,
        goBehavior: clearGoBehavior ? null : (goBehavior ?? this.goBehavior),
        goFade: clearGoFade ? null : (goFade ?? this.goFade),
        note: note ?? this.note,
        extra: extra,
      );

  @override
  bool operator ==(Object other) =>
      other is CueSettings &&
      other.startAt == startAt &&
      other.endAt == endAt &&
      other.volume == volume &&
      other.fadeIn == fadeIn &&
      other.goBehavior == goBehavior &&
      other.goFade == goFade &&
      other.note == note &&
      mapEquals(other.extra, extra);

  @override
  int get hashCode =>
      Object.hash(startAt, endAt, volume, fadeIn, goBehavior, goFade, note);
}
