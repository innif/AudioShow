import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../model/cue_settings.dart';
import '../storage/app_settings.dart';
import 'audio_backend.dart';

/// A show entry with its file resolved and settings loaded from `cues.json`.
@immutable
class ResolvedCue {
  /// Stable id of the show entry (survives reordering; differs for duplicates).
  final int id;
  final String relPath;
  final String absPath;
  final CueSettings settings;
  final bool missing;
  const ResolvedCue({
    this.id = 0,
    required this.relPath,
    required this.absPath,
    required this.settings,
    this.missing = false,
  });

  @override
  bool operator ==(Object other) =>
      other is ResolvedCue &&
      other.id == id &&
      other.relPath == relPath &&
      other.absPath == absPath &&
      other.settings == settings &&
      other.missing == missing;

  @override
  int get hashCode => Object.hash(id, relPath, absPath, settings, missing);

  String get artist => relPath.split('/').first;
  String get fileName => relPath.substring(relPath.indexOf('/') + 1);
}

/// One playing instance of a cue. The same cue can run more than once.
class RunningCue {
  final int id;
  final ResolvedCue cue;
  final AudioVoice voice;
  RunningCue._(this.id, this.cue, this.voice);

  double _fadeFactor = 1;
  bool _fadingOut = false;
  Timer? _fadeTimer;
  final List<StreamSubscription> _subs = [];

  Duration get position => voice.position;
  Duration? get duration => voice.duration;
  bool get fadingOut => _fadingOut;
}

/// A GO whose file is still loading; can be cancelled before it sounds.
class _PendingStart {
  _PendingStart(this.cue);
  final ResolvedCue cue;
  bool cancelled = false;
}

class ShowEngine extends ChangeNotifier {
  ShowEngine({required this.backend, required this.settings});

  final AudioBackend backend;
  AppSettings settings;

  static const goLockout = Duration(milliseconds: 500);
  static const _fadeTick = Duration(milliseconds: 20);
  static const _restartWindow = Duration(seconds: 2);

  List<ResolvedCue> _cues = const [];
  int? _nextEntry; // entry id of the next cue
  final List<RunningCue> _running = [];
  final List<_PendingStart> _pending = [];
  final Set<int> _played = {};
  int _nextRunId = 1;
  bool _locked = false;
  Timer? _lockTimer;
  ResolvedCue? _preloadCue;
  Future<AudioVoice>? _preload;
  bool _disposed = false;
  String? lastError;

  List<ResolvedCue> get cues => _cues;
  int? get nextIndex {
    final id = _nextEntry;
    if (id == null) return null;
    final i = _indexOfId(id);
    return i < 0 ? null : i;
  }

  List<RunningCue> get running => List.unmodifiable(_running);

  /// Entry ids that have been started.
  Set<int> get played => Set.unmodifiable(_played);
  bool isPlayed(int index) => _played.contains(_cues[index].id);
  bool isRunning(int index) => _running.any((r) => r.cue.id == _cues[index].id);

  int _indexOfId(int id) => _cues.indexWhere((c) => c.id == id);

  void setCues(List<ResolvedCue> cues) {
    _cues = List.unmodifiable(cues);
    _played.clear();
    _discardPreload();
    _setNext(_firstPlayable(0));
    notifyListeners();
  }

  /// Replaces the list (reorder/add/remove/settings change) while keeping
  /// running cues, played marks and the next cue (by entry id).
  void updateCues(List<ResolvedCue> cues) {
    final oldIds = {for (final c in _cues) c.id};
    final oldNextIndex = nextIndex;
    final oldNext = _nextEntry;
    _cues = List.unmodifiable(cues);
    _played.retainWhere((id) => _indexOfId(id) >= 0);
    int? index;
    if (oldNext != null) {
      final i = _indexOfId(oldNext);
      index = i >= 0 ? i : _firstPlayable(min(oldNextIndex ?? 0, _cues.length));
    } else {
      final i = _cues.indexWhere((c) => !oldIds.contains(c.id) && !c.missing);
      index = i >= 0 ? i : null;
    }
    _setNext(index);
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _cues.length) return;
    _setNext(index);
    notifyListeners();
  }

  Future<void> go() async {
    if (_locked) return;
    final index = _firstPlayable(nextIndex);
    if (index == null) return;
    _locked = true;
    _lockTimer = Timer(goLockout, () => _locked = false);

    for (final r in List.of(_running)) {
      switch (r.cue.settings.goBehavior ?? settings.goBehavior) {
        case GoBehavior.keepRunning:
          break;
        case GoBehavior.stop:
          _stop(r);
        case GoBehavior.fadeOut:
          _fadeOut(r, r.cue.settings.goFade ?? settings.goFade);
      }
    }
    // A previous cue that has not started yet: never let it sound late.
    for (final p in _pending) {
      if ((p.cue.settings.goBehavior ?? settings.goBehavior) != GoBehavior.keepRunning) p.cancelled = true;
    }

    final cue = _cues[index];
    final voiceFuture = _takePreload(index) ?? backend.load(cue.absPath, initialPosition: cue.settings.startAt);
    _played.add(cue.id);
    _setNext(_firstPlayable(index + 1));
    lastError = null;
    notifyListeners();

    final pending = _PendingStart(cue);
    _pending.add(pending);
    final AudioVoice voice;
    try {
      voice = await voiceFuture;
    } catch (e) {
      _pending.remove(pending);
      if (_disposed) return;
      lastError = 'Konnte ${cue.relPath} nicht laden: $e';
      notifyListeners();
      return;
    }
    _pending.remove(pending);
    if (_disposed || pending.cancelled) {
      unawaited(voice.dispose());
      return;
    }
    final r = RunningCue._(_nextRunId++, cue, voice);
    _running.add(r);
    // An end at or before the start would stop the cue instantly; ignore it.
    final endAt = cue.settings.endAt != null && cue.settings.endAt! > cue.settings.startAt ? cue.settings.endAt : null;
    r._subs.add(voice.positionStream.listen((pos) {
      if (endAt != null && pos >= endAt) _stop(r);
    }));
    r._subs.add(voice.completed.listen((_) => _stop(r)));
    final fadeIn = cue.settings.fadeIn;
    r._fadeFactor = fadeIn > Duration.zero ? 0 : 1;
    _applyVolume(r);
    await voice.play();
    if (fadeIn > Duration.zero) _ramp(r, 0, 1, fadeIn);
    notifyListeners();
  }

  void _cancelPending() {
    for (final p in _pending) {
      p.cancelled = true;
    }
  }

  void stopAll() {
    _cancelPending();
    for (final r in List.of(_running)) {
      _stop(r);
    }
  }

  void fadeAll(Duration d) {
    _cancelPending();
    for (final r in List.of(_running)) {
      _fadeOut(r, d);
    }
    notifyListeners();
  }

  /// Jumps to the saved start; if already near it, jumps to 0.
  Future<void> restart(RunningCue r) {
    final start = r.cue.settings.startAt;
    final near = (r.position - start).abs() < _restartWindow;
    return r.voice.seek(near ? Duration.zero : start);
  }

  Future<void> seek(RunningCue r, Duration absolutePosition) => r.voice.seek(absolutePosition);

  // --- internals ---

  int? _firstPlayable(int? from) {
    if (from == null) return null;
    for (var i = max(0, from); i < _cues.length; i++) {
      if (!_cues[i].missing) return i;
    }
    return null;
  }

  void _setNext(int? index) {
    _nextEntry = index == null || index >= _cues.length ? null : _cues[index].id;
    final target = _firstPlayable(index);
    final cue = target == null ? null : _cues[target];
    if (cue != null && cue == _preloadCue) return;
    _discardPreload();
    if (cue != null) {
      _preloadCue = cue;
      _preload = backend.load(cue.absPath, initialPosition: cue.settings.startAt);
      _preload!.ignore();
    }
  }

  Future<AudioVoice>? _takePreload(int index) {
    if (_preloadCue != _cues[index]) return null;
    final f = _preload;
    _preload = null;
    _preloadCue = null;
    return f;
  }

  void _discardPreload() {
    final f = _preload;
    _preload = null;
    _preloadCue = null;
    f?.then((v) => v.dispose(), onError: (_) {});
  }

  void _applyVolume(RunningCue r) {
    unawaited(r.voice.setVolume(r.cue.settings.volume / 100 * r._fadeFactor));
  }

  void _ramp(RunningCue r, double from, double to, Duration d, {VoidCallback? onDone}) {
    r._fadeTimer?.cancel();
    final steps = max(1, (d.inMicroseconds / _fadeTick.inMicroseconds).ceil());
    var k = 0;
    r._fadeFactor = from;
    _applyVolume(r);
    if (d <= Duration.zero) {
      r._fadeFactor = to;
      _applyVolume(r);
      onDone?.call();
      return;
    }
    r._fadeTimer = Timer.periodic(_fadeTick, (t) {
      k++;
      r._fadeFactor = from + (to - from) * k / steps;
      _applyVolume(r);
      if (k >= steps) {
        t.cancel();
        r._fadeTimer = null;
        onDone?.call();
      }
    });
  }

  void _fadeOut(RunningCue r, Duration d) {
    r._fadingOut = true;
    _ramp(r, r._fadeFactor, 0, d, onDone: () => _stop(r));
  }

  void _stop(RunningCue r) {
    if (!_running.remove(r)) return;
    r._fadeTimer?.cancel();
    for (final s in r._subs) {
      s.cancel();
    }
    unawaited(r.voice.stop().whenComplete(r.voice.dispose));
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stopAll();
    _discardPreload();
    _lockTimer?.cancel();
    super.dispose();
  }
}
