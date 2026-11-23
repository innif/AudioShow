import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../model/cue_settings.dart';
import '../storage/app_settings.dart';
import 'audio_backend.dart';

/// A show entry with its file resolved and settings loaded from `cues.json`.
@immutable
class ResolvedCue {
  final String relPath;
  final String absPath;
  final CueSettings settings;
  final bool missing;
  const ResolvedCue({required this.relPath, required this.absPath, required this.settings, this.missing = false});

  String get artist => relPath.split('/').first;
  String get fileName => relPath.substring(relPath.indexOf('/') + 1);
}

/// One playing instance of a cue. The same cue can run more than once.
class RunningCue {
  final int id;
  final int showIndex;
  final ResolvedCue cue;
  final AudioVoice voice;
  RunningCue._(this.id, this.showIndex, this.cue, this.voice);

  double _fadeFactor = 1;
  bool _fadingOut = false;
  Timer? _fadeTimer;
  final List<StreamSubscription> _subs = [];

  Duration get position => voice.position;
  Duration? get duration => voice.duration;
  bool get fadingOut => _fadingOut;
}

class ShowEngine extends ChangeNotifier {
  ShowEngine({required this.backend, required this.settings});

  final AudioBackend backend;
  AppSettings settings;

  static const goLockout = Duration(milliseconds: 500);
  static const _fadeTick = Duration(milliseconds: 20);
  static const _restartWindow = Duration(seconds: 2);

  List<ResolvedCue> _cues = const [];
  int? _next;
  final List<RunningCue> _running = [];
  final Set<int> _played = {};
  int _nextId = 1;
  bool _locked = false;
  Timer? _lockTimer;
  int? _preloadIndex;
  Future<AudioVoice>? _preload;
  bool _disposed = false;
  String? lastError;

  List<ResolvedCue> get cues => _cues;
  int? get nextIndex => _next;
  List<RunningCue> get running => List.unmodifiable(_running);
  Set<int> get played => Set.unmodifiable(_played);

  void setCues(List<ResolvedCue> cues) {
    _cues = List.unmodifiable(cues);
    _played.clear();
    _discardPreload();
    _setNext(_firstPlayable(0));
    notifyListeners();
  }

  void select(int index) {
    if (index < 0 || index >= _cues.length) return;
    _setNext(index);
    notifyListeners();
  }

  Future<void> go() async {
    if (_locked) return;
    final index = _firstPlayable(_next);
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

    final cue = _cues[index];
    final voiceFuture = _takePreload(index) ?? backend.load(cue.absPath, initialPosition: cue.settings.startAt);
    _played.add(index);
    _setNext(_firstPlayable(index + 1));
    lastError = null;
    notifyListeners();

    final AudioVoice voice;
    try {
      voice = await voiceFuture;
    } catch (e) {
      lastError = 'Konnte ${cue.relPath} nicht laden: $e';
      notifyListeners();
      return;
    }
    if (_disposed) {
      unawaited(voice.dispose());
      return;
    }
    final r = RunningCue._(_nextId++, index, cue, voice);
    _running.add(r);
    final endAt = cue.settings.endAt;
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

  void stopAll() {
    for (final r in List.of(_running)) {
      _stop(r);
    }
  }

  void fadeAll(Duration d) {
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
    _next = index;
    final target = _firstPlayable(index);
    if (target == _preloadIndex) return;
    _discardPreload();
    if (target != null) {
      final cue = _cues[target];
      _preloadIndex = target;
      _preload = backend.load(cue.absPath, initialPosition: cue.settings.startAt);
      _preload!.ignore();
    }
  }

  Future<AudioVoice>? _takePreload(int index) {
    if (_preloadIndex != index) return null;
    final f = _preload;
    _preload = null;
    _preloadIndex = null;
    return f;
  }

  void _discardPreload() {
    final f = _preload;
    _preload = null;
    _preloadIndex = null;
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
