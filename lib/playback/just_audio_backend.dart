import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_backend.dart';

Future<void> configureAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
}

class JustAudioBackend implements AudioBackend {
  @override
  Future<AudioVoice> load(String path, {Duration initialPosition = Duration.zero}) async {
    // handleInterruptions: false — a phone notification must never pause the show.
    final player = AudioPlayer(handleInterruptions: false, handleAudioSessionActivation: false);
    try {
      await player.setFilePath(path, initialPosition: initialPosition);
    } catch (_) {
      await player.dispose();
      rethrow;
    }
    return _JustAudioVoice(player);
  }
}

class _JustAudioVoice implements AudioVoice {
  final AudioPlayer _p;
  _JustAudioVoice(this._p);

  @override
  Future<void> play() async {
    // play() completes only when playback stops, so don't await it.
    _p.play();
  }

  @override
  Future<void> stop() => _p.stop();
  @override
  Future<void> dispose() => _p.dispose();
  @override
  Future<void> seek(Duration position) => _p.seek(position);
  @override
  Future<void> setVolume(double v) => _p.setVolume(v.clamp(0.0, 1.0));
  @override
  Duration get position => _p.position;
  @override
  Duration? get duration => _p.duration;
  @override
  Stream<Duration> get positionStream => _p.positionStream;
  @override
  Stream<void> get completed =>
      _p.processingStateStream.where((s) => s == ProcessingState.completed).map((_) {});
}
