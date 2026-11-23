/// Thin audio abstraction so the show logic can be tested without a device.
abstract class AudioBackend {
  Future<AudioVoice> load(String path, {Duration initialPosition = Duration.zero});
}

/// One loaded playback. Positions are absolute within the file.
abstract class AudioVoice {
  Future<void> play();
  Future<void> stop();
  Future<void> dispose();
  Future<void> seek(Duration position);

  /// 0.0–1.0
  Future<void> setVolume(double v);

  Duration get position;
  Duration? get duration;
  Stream<Duration> get positionStream;
  Stream<void> get completed;
}
