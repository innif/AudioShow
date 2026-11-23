import 'dart:async';

import 'package:audioshow/playback/audio_backend.dart';

class FakeVoice implements AudioVoice {
  final String path;
  FakeVoice(this.path, this._position);

  Duration _position;
  @override
  Duration? duration = const Duration(minutes: 3);
  bool played = false;
  bool stopped = false;
  bool disposed = false;
  final List<double> volumes = [];
  final List<Duration> seeks = [];
  double get volume => volumes.isEmpty ? 1.0 : volumes.last;

  final _pos = StreamController<Duration>.broadcast(sync: true);
  final _completed = StreamController<void>.broadcast(sync: true);

  void emitPosition(Duration d) {
    _position = d;
    _pos.add(d);
  }

  void complete() => _completed.add(null);

  @override
  Duration get position => _position;
  @override
  Stream<Duration> get positionStream => _pos.stream;
  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> play() async => played = true;
  @override
  Future<void> stop() async => stopped = true;
  @override
  Future<void> dispose() async => disposed = true;
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    _position = position;
  }

  @override
  Future<void> setVolume(double v) async => volumes.add(v);
}

class FakeAudioBackend implements AudioBackend {
  final List<FakeVoice> voices = [];
  List<String> get loadedPaths => voices.map((v) => v.path).toList();
  FakeVoice voiceFor(String path) => voices.lastWhere((v) => v.path == path);

  final Map<String, Duration> initialPositions = {};

  /// When set, loads wait until it completes (simulates slow file preparation).
  Completer<void>? gate;

  @override
  Future<AudioVoice> load(String path, {Duration initialPosition = Duration.zero}) async {
    if (gate != null) await gate!.future;
    final v = FakeVoice(path, initialPosition);
    initialPositions[path] = initialPosition;
    voices.add(v);
    return v;
  }
}
