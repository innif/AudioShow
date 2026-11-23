import 'dart:async';

import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/playback/show_engine.dart';
import 'package:audioshow/storage/app_settings.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_audio_backend.dart';

var _nextId = 0;

/// Test cue; ids are assigned in creation order starting at 0 per test.
ResolvedCue cue(String name, {CueSettings settings = const CueSettings(), bool missing = false, int? id}) =>
    ResolvedCue(id: id ?? _nextId++, relPath: 'X/$name', absPath: '/root/X/$name', settings: settings, missing: missing);

void main() {
  late FakeAudioBackend backend;
  late ShowEngine engine;

  setUp(() => _nextId = 0);

  void setup(List<ResolvedCue> cues, {AppSettings? settings}) {
    backend = FakeAudioBackend();
    engine = ShowEngine(backend: backend, settings: settings ?? AppSettings());
    engine.setCues(cues);
  }

  /// Runs [body] in fake time and lets pending microtasks settle.
  void run(void Function(FakeAsync a) body) => fakeAsync((a) {
        body(a);
        a.flushMicrotasks();
      });

  void goAndSettle(FakeAsync a) {
    engine.go();
    a.flushMicrotasks();
    a.elapse(ShowEngine.goLockout);
  }

  test('go starts next cue at startAt with volume/100 and advances nextIndex', () => run((a) {
        setup([cue('a.mp3', settings: CueSettings(startAt: const Duration(seconds: 12), volume: 80)), cue('b.mp3')]);
        a.flushMicrotasks();
        engine.go();
        a.flushMicrotasks();
        final v = backend.voiceFor('/root/X/a.mp3');
        expect(backend.initialPositions['/root/X/a.mp3'], const Duration(seconds: 12));
        expect(v.played, isTrue);
        expect(v.volume, closeTo(0.8, 1e-9));
        expect(engine.nextIndex, 1);
        expect(engine.running.single.cue.id, 0);
        expect(engine.played, {0});
      }));

  test('go with fadeIn ramps volume from 0 to target over fadeIn', () => run((a) {
        setup([cue('a.mp3', settings: CueSettings(fadeIn: const Duration(seconds: 2), volume: 50))]);
        a.flushMicrotasks();
        engine.go();
        a.flushMicrotasks();
        final v = backend.voiceFor('/root/X/a.mp3');
        expect(v.volumes.first, 0);
        a.elapse(const Duration(seconds: 1));
        expect(v.volume, closeTo(0.25, 0.02));
        a.elapse(const Duration(seconds: 2));
        expect(v.volume, closeTo(0.5, 1e-9));
      }));

  test("go applies running cue's own goBehavior (keepRunning) instead of global", () => run((a) {
        setup([cue('a.mp3', settings: const CueSettings(goBehavior: GoBehavior.keepRunning)), cue('b.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        goAndSettle(a);
        a.elapse(const Duration(seconds: 5));
        final va = backend.voiceFor('/root/X/a.mp3');
        expect(va.stopped, isFalse);
        expect(va.volume, 1.0);
        expect(engine.running.map((r) => r.cue.id), [0, 1]);
      }));

  test('go with global fadeOut fades running cue over goFade then stops it', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        engine.go();
        a.flushMicrotasks();
        final va = backend.voiceFor('/root/X/a.mp3');
        a.elapse(const Duration(milliseconds: 500));
        expect(va.stopped, isFalse);
        expect(va.volume, lessThan(1.0));
        expect(engine.running.firstWhere((r) => r.cue.id == 0).fadingOut, isTrue);
        a.elapse(const Duration(milliseconds: 600));
        expect(va.stopped, isTrue);
        final fadeVolumes = va.volumes.skip(1).toList();
        for (var i = 1; i < fadeVolumes.length; i++) {
          expect(fadeVolumes[i], lessThanOrEqualTo(fadeVolumes[i - 1]));
        }
        expect(engine.running.map((r) => r.cue.id), [1]);
      }));

  test("go uses running cue's goFade override", () => run((a) {
        setup([cue('a.mp3', settings: const CueSettings(goFade: Duration(seconds: 3))), cue('b.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        engine.go();
        a.flushMicrotasks();
        final va = backend.voiceFor('/root/X/a.mp3');
        a.elapse(const Duration(seconds: 1));
        expect(va.stopped, isFalse);
        a.elapse(const Duration(milliseconds: 2100));
        expect(va.stopped, isTrue);
      }));

  test('go with stop behavior stops running cue immediately', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3')], settings: AppSettings(goBehavior: GoBehavior.stop));
        a.flushMicrotasks();
        goAndSettle(a);
        engine.go();
        a.flushMicrotasks();
        expect(backend.voiceFor('/root/X/a.mp3').stopped, isTrue);
        expect(engine.running.map((r) => r.cue.id), [1]);
      }));

  test('second go within 500ms is ignored', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3')]);
        a.flushMicrotasks();
        engine.go();
        a.flushMicrotasks();
        a.elapse(const Duration(milliseconds: 300));
        engine.go();
        a.flushMicrotasks();
        expect(engine.running, hasLength(1));
        expect(engine.nextIndex, 1);
        a.elapse(const Duration(milliseconds: 300));
        engine.go();
        a.flushMicrotasks();
        expect(engine.nextIndex, isNull);
      }));

  test('go skips missing cues', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3', missing: true), cue('c.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        expect(engine.nextIndex, 2);
        expect(backend.loadedPaths, isNot(contains('/root/X/b.mp3')));
      }));

  test('setCues skips leading missing cues', () => run((a) {
        setup([cue('a.mp3', missing: true), cue('b.mp3')]);
        expect(engine.nextIndex, 1);
      }));

  test('go at end of show does nothing and leaves running cues alone', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3', missing: true)]);
        a.flushMicrotasks();
        goAndSettle(a);
        expect(engine.nextIndex, isNull);
        final loads = backend.voices.length;
        goAndSettle(a);
        a.elapse(const Duration(seconds: 3));
        expect(backend.voices.length, loads);
        expect(backend.voiceFor('/root/X/a.mp3').stopped, isFalse);
        expect(engine.running, hasLength(1));
      }));

  test('select changes next cue without starting it', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3'), cue('c.mp3')]);
        a.flushMicrotasks();
        engine.select(2);
        a.flushMicrotasks();
        expect(engine.nextIndex, 2);
        expect(engine.running, isEmpty);
        goAndSettle(a);
        expect(engine.running.single.cue.id, 2);
        expect(engine.nextIndex, isNull);
      }));

  test('stopAll stops everything immediately and clears running', () => run((a) {
        setup([cue('a.mp3', settings: const CueSettings(goBehavior: GoBehavior.keepRunning)), cue('b.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        goAndSettle(a);
        engine.stopAll();
        a.flushMicrotasks();
        expect(engine.running, isEmpty);
        expect(backend.voiceFor('/root/X/a.mp3').stopped, isTrue);
        expect(backend.voiceFor('/root/X/b.mp3').stopped, isTrue);
      }));

  test('stopAll during a fade cancels the fade', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        engine.fadeAll(const Duration(seconds: 5));
        a.elapse(const Duration(seconds: 1));
        engine.stopAll();
        a.flushMicrotasks();
        final va = backend.voiceFor('/root/X/a.mp3');
        final count = va.volumes.length;
        a.elapse(const Duration(seconds: 5));
        expect(va.volumes.length, count);
      }));

  test('fadeAll(5s) fades all running then stops', () => run((a) {
        setup([cue('a.mp3', settings: const CueSettings(goBehavior: GoBehavior.keepRunning)), cue('b.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        goAndSettle(a);
        engine.fadeAll(const Duration(seconds: 5));
        a.elapse(const Duration(seconds: 4));
        expect(engine.running, hasLength(2));
        a.elapse(const Duration(milliseconds: 1100));
        expect(engine.running, isEmpty);
        expect(backend.voiceFor('/root/X/a.mp3').stopped, isTrue);
      }));

  test('endAt stops the cue when position reaches it', () => run((a) {
        setup([cue('a.mp3', settings: const CueSettings(endAt: Duration(seconds: 30)))]);
        a.flushMicrotasks();
        goAndSettle(a);
        final v = backend.voiceFor('/root/X/a.mp3');
        v.emitPosition(const Duration(seconds: 29));
        expect(v.stopped, isFalse);
        v.emitPosition(const Duration(seconds: 30));
        a.flushMicrotasks();
        expect(v.stopped, isTrue);
        expect(engine.running, isEmpty);
      }));

  test('completed removes cue from running', () => run((a) {
        setup([cue('a.mp3')]);
        a.flushMicrotasks();
        goAndSettle(a);
        backend.voiceFor('/root/X/a.mp3').complete();
        a.flushMicrotasks();
        expect(engine.running, isEmpty);
        expect(backend.voiceFor('/root/X/a.mp3').disposed, isTrue);
      }));

  test('same file twice can run concurrently and is stopped independently', () => run((a) {
        final keep = const CueSettings(goBehavior: GoBehavior.keepRunning);
        setup([cue('a.mp3', settings: keep), cue('a.mp3', settings: keep)]);
        a.flushMicrotasks();
        goAndSettle(a);
        goAndSettle(a);
        final r = engine.running;
        expect(r, hasLength(2));
        expect(r[0].id, isNot(r[1].id));
        engine.seek(r[1], const Duration(seconds: 42));
        a.flushMicrotasks();
        final v0 = backend.voices[0], v1 = backend.voices[1];
        expect(v0.seeks, isEmpty);
        expect(v1.seeks, [const Duration(seconds: 42)]);
      }));

  test('restart seeks to startAt, second restart near startAt seeks to 0', () => run((a) {
        setup([cue('a.mp3', settings: const CueSettings(startAt: Duration(seconds: 10)))]);
        a.flushMicrotasks();
        goAndSettle(a);
        final r = engine.running.single;
        final v = backend.voiceFor('/root/X/a.mp3');
        v.emitPosition(const Duration(seconds: 50));
        engine.restart(r);
        a.flushMicrotasks();
        expect(v.seeks.last, const Duration(seconds: 10));
        engine.restart(r);
        a.flushMicrotasks();
        expect(v.seeks.last, Duration.zero);
      }));

  test('seek does not change cue settings', () => run((a) {
        final s = const CueSettings(startAt: Duration(seconds: 10));
        setup([cue('a.mp3', settings: s)]);
        a.flushMicrotasks();
        goAndSettle(a);
        engine.seek(engine.running.single, const Duration(seconds: 20));
        a.flushMicrotasks();
        expect(engine.cues[0].settings, s);
      }));

  test('next cue is preloaded', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3')]);
        a.flushMicrotasks();
        expect(backend.loadedPaths, ['/root/X/a.mp3']);
        goAndSettle(a);
        expect(backend.loadedPaths, ['/root/X/a.mp3', '/root/X/b.mp3']);
      }));

  test('select disposes the old preload', () => run((a) {
        setup([cue('a.mp3'), cue('b.mp3')]);
        a.flushMicrotasks();
        engine.select(1);
        a.flushMicrotasks();
        expect(backend.voiceFor('/root/X/a.mp3').disposed, isTrue);
        expect(backend.loadedPaths.last, '/root/X/b.mp3');
      }));

  test('stopAll cancels a cue that is still loading', () => run((a) {
        setup([]);
        backend.gate = Completer<void>();
        engine.setCues([cue('a.mp3'), cue('b.mp3')]);
        engine.go();
        a.flushMicrotasks();
        engine.stopAll();
        backend.gate!.complete();
        a.flushMicrotasks();
        final v = backend.voiceFor('/root/X/a.mp3');
        expect(v.played, isFalse);
        expect(v.disposed, isTrue);
        expect(engine.running, isEmpty);
      }));

  test('fadeAll cancels a cue that is still loading', () => run((a) {
        setup([]);
        backend.gate = Completer<void>();
        engine.setCues([cue('a.mp3')]);
        engine.go();
        a.flushMicrotasks();
        engine.fadeAll(const Duration(seconds: 1));
        backend.gate!.complete();
        a.flushMicrotasks();
        expect(backend.voiceFor('/root/X/a.mp3').played, isFalse);
        expect(engine.running, isEmpty);
      }));

  test('next GO applies GO behavior to a cue that is still loading', () => run((a) {
        setup([]);
        backend.gate = Completer<void>();
        engine.setCues([cue('a.mp3'), cue('b.mp3')]);
        engine.go();
        a.flushMicrotasks();
        a.elapse(ShowEngine.goLockout);
        engine.go();
        backend.gate!.complete();
        a.flushMicrotasks();
        expect(backend.voiceFor('/root/X/a.mp3').played, isFalse);
        expect(backend.voiceFor('/root/X/b.mp3').played, isTrue);
        expect(engine.running.map((r) => r.cue.id), [1]);
      }));

  test('endAt at or before startAt is ignored', () => run((a) {
        setup([cue('a.mp3', settings: const CueSettings(startAt: Duration(seconds: 20), endAt: Duration(seconds: 10)))]);
        a.flushMicrotasks();
        goAndSettle(a);
        final v = backend.voiceFor('/root/X/a.mp3');
        v.emitPosition(const Duration(seconds: 20));
        a.flushMicrotasks();
        expect(v.stopped, isFalse);
        expect(engine.running, hasLength(1));
      }));

  test('updateCues keeps next cue when reordered', () => run((a) {
        final ca = cue('a.mp3'), cb = cue('b.mp3'), cc = cue('c.mp3');
        setup([ca, cb, cc]);
        engine.select(1);
        a.flushMicrotasks();
        engine.updateCues([cb, ca, cc]);
        a.flushMicrotasks();
        expect(engine.nextIndex, 0);
        goAndSettle(a);
        expect(engine.running.single.cue.id, cb.id);
        expect(backend.voiceFor('/root/X/b.mp3').played, isTrue);
      }));

  test('updateCues keeps preload when next cue unchanged', () => run((a) {
        final ca = cue('a.mp3'), cb = cue('b.mp3');
        setup([ca, cb]);
        a.flushMicrotasks();
        final loads = backend.voices.length;
        engine.updateCues([cb, ca]);
        a.flushMicrotasks();
        expect(backend.voices.length, loads);
        expect(engine.nextIndex, 1);
      }));

  test('updateCues reloads preload when next cue settings change', () => run((a) {
        final ca = cue('a.mp3');
        setup([ca]);
        a.flushMicrotasks();
        final old = backend.voiceFor('/root/X/a.mp3');
        engine.updateCues([
          ResolvedCue(id: ca.id, relPath: ca.relPath, absPath: ca.absPath,
              settings: const CueSettings(startAt: Duration(seconds: 10))),
        ]);
        a.flushMicrotasks();
        expect(old.disposed, isTrue);
        expect(backend.voices.length, 2);
        goAndSettle(a);
        expect(engine.running.single.voice.position, const Duration(seconds: 10));
      }));

  test('removing next cue makes the entry at its position next', () => run((a) {
        final ca = cue('a.mp3'), cb = cue('b.mp3'), cc = cue('c.mp3');
        setup([ca, cb, cc]);
        engine.select(1);
        engine.updateCues([ca, cc]);
        a.flushMicrotasks();
        expect(engine.nextIndex, 1);
        goAndSettle(a);
        expect(engine.running.single.cue.id, cc.id);
      }));

  test('appending after end of show makes new entry next', () => run((a) {
        final ca = cue('a.mp3');
        setup([ca]);
        a.flushMicrotasks();
        goAndSettle(a);
        expect(engine.nextIndex, isNull);
        engine.updateCues([ca, cue('d.mp3')]);
        a.flushMicrotasks();
        expect(engine.nextIndex, 1);
      }));

  test('appending while a next cue exists keeps it', () => run((a) {
        final ca = cue('a.mp3'), cb = cue('b.mp3');
        setup([ca, cb]);
        a.flushMicrotasks();
        engine.updateCues([ca, cb, cue('d.mp3')]);
        expect(engine.nextIndex, 0);
      }));

  test('removing a running cue keeps it playing', () => run((a) {
        final ca = cue('a.mp3'), cb = cue('b.mp3');
        setup([ca, cb]);
        a.flushMicrotasks();
        goAndSettle(a);
        engine.updateCues([cb]);
        a.flushMicrotasks();
        expect(engine.running.single.cue.id, ca.id);
        expect(backend.voiceFor('/root/X/a.mp3').stopped, isFalse);
        expect(engine.nextIndex, 0);
      }));

  test('duplicate file entries are tracked by id', () => run((a) {
        final a0 = cue('a.mp3'), a1 = cue('a.mp3');
        setup([a0, a1]);
        a.flushMicrotasks();
        goAndSettle(a);
        expect(engine.played, {a0.id});
        engine.updateCues([a1, a0]);
        a.flushMicrotasks();
        expect(engine.nextIndex, 0);
        expect(engine.isPlayed(1), isTrue);
        expect(engine.isPlayed(0), isFalse);
      }));
}
