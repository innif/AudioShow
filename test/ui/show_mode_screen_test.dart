import 'dart:io';

import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/library/library.dart';
import 'package:audioshow/storage/show_store.dart';
import 'package:audioshow/ui/show_mode_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../fakes/fake_audio_backend.dart';
import '../support.dart';

void main() {
  const files = ['Anna/Jonglage.mp3', 'Trio X/Intro.wav', 'Ben/Handstand.wav'];
  late Directory root;

  setUp(() => root = makeCueRoot(files));
  tearDown(() => root.deleteSync(recursive: true));

  String abs(String rel) => File('${root.path}/$rel').path.replaceAll('/', Platform.pathSeparator);

  Future<FakeAudioBackend> open(WidgetTester tester, List<String> entries,
      {Map<String, CueSettings> settings = const {}}) async {
    await tester.runAsync(() async {
      final store = ShowStore(root);
      final s = await store.createForDate(DateTime(2026, 11, 23));
      await store.save(s.copyWith(entries: entries));
    });
    final state = await makeState(tester, root: root.path);
    for (final e in settings.entries) {
      await tester.runAsync(() => state.saveCueSettings(AudioFileRef.parse(e.key), e.value));
    }
    await pumpApp(tester, state, const ShowModeScreen(showName: '2026-11-23', keepAwake: false));
    await settle(tester);
    return state.backend as FakeAudioBackend;
  }

  Future<void> go(WidgetTester tester) async {
    await tester.tap(find.text('GO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('GO button starts next cue and marks following as NÄCHSTER', (tester) async {
    final backend = await open(tester, files);
    await go(tester);
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).played, isTrue);
    final next = find.ancestor(of: find.text('NÄCHSTER'), matching: find.byType(ListTile));
    expect(find.descendant(of: next, matching: find.text('Trio X – Intro.wav')), findsOneWidget);
  });

  testWidgets('tapping a cue selects it as next without starting', (tester) async {
    final backend = await open(tester, files);
    await tester.tap(find.text('Ben – Handstand.wav'));
    await tester.pump();
    expect(backend.voices.where((v) => v.played), isEmpty);
    await go(tester);
    expect(backend.voiceFor(abs('Ben/Handstand.wav')).played, isTrue);
  });

  testWidgets('STOP ALL stops all running', (tester) async {
    final keep = const CueSettings(goBehavior: GoBehavior.keepRunning);
    final backend = await open(tester, files, settings: {'Anna/Jonglage.mp3': keep});
    await go(tester);
    await go(tester);
    expect(find.byKey(const ValueKey('running-row')), findsNWidgets(2));
    await tester.tap(find.text('STOP ALL'));
    await tester.pump();
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).stopped, isTrue);
    expect(backend.voiceFor(abs('Trio X/Intro.wav')).stopped, isTrue);
    expect(find.byKey(const ValueKey('running-row')), findsNothing);
  });

  testWidgets('Fade 1 s / Fade 5 s buttons fade out over configured durations', (tester) async {
    final backend = await open(tester, files);
    await go(tester);
    final v = backend.voiceFor(abs('Anna/Jonglage.mp3'));
    await tester.tap(find.text('Fade 5 s'));
    await tester.pump(const Duration(seconds: 4));
    expect(v.stopped, isFalse);
    await tester.pump(const Duration(milliseconds: 1200));
    expect(v.stopped, isTrue);

    await go(tester);
    final v2 = backend.voiceFor(abs('Trio X/Intro.wav'));
    await tester.tap(find.text('Fade 1 s'));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(v2.stopped, isTrue);
  });

  testWidgets('each running cue has its own row with seek bar and Von Anfang', (tester) async {
    final keep = const CueSettings(goBehavior: GoBehavior.keepRunning);
    await open(tester, files, settings: {'Anna/Jonglage.mp3': keep});
    await go(tester);
    await go(tester);
    expect(find.byKey(const ValueKey('running-row')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('seekbar')), findsNWidgets(2));
    expect(find.byTooltip('Von Anfang'), findsNWidgets(2));
  });

  testWidgets('tap on seek bar without drag does not seek; drag does', (tester) async {
    final backend = await open(tester, files);
    await go(tester);
    final v = backend.voiceFor(abs('Anna/Jonglage.mp3'));
    final bar = find.byKey(const ValueKey('seekbar'));
    await tester.tap(bar);
    await tester.pump();
    expect(v.seeks, isEmpty);
    final rect = tester.getRect(bar);
    await tester.dragFrom(rect.centerLeft + const Offset(5, 0), Offset(rect.width / 2, 0));
    await tester.pump();
    expect(v.seeks, hasLength(1));
    // dragged to about the middle of a 3:00 file
    expect(v.seeks.single.inSeconds, inInclusiveRange(80, 100));
  });

  testWidgets('Von Anfang seeks to saved start', (tester) async {
    final backend = await open(tester, files,
        settings: {'Anna/Jonglage.mp3': const CueSettings(startAt: Duration(seconds: 10))});
    await go(tester);
    final v = backend.voiceFor(abs('Anna/Jonglage.mp3'));
    v.emitPosition(const Duration(seconds: 60));
    await tester.tap(find.byTooltip('Von Anfang'));
    await tester.pump();
    expect(v.seeks.last, const Duration(seconds: 10));
  });

  testWidgets('editing is not possible in show mode', (tester) async {
    await open(tester, files);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byTooltip('Entfernen'), findsNothing);
    await tester.longPress(find.text('Anna – Jonglage.mp3'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern'), findsNothing);
  });

  testWidgets('end of show shows "Ende der Show" and GO is disabled', (tester) async {
    final backend = await open(tester, ['Anna/Jonglage.mp3']);
    await go(tester);
    expect(find.text('Ende der Show'), findsOneWidget);
    final loads = backend.voices.length;
    await go(tester);
    expect(backend.voices.length, loads);
  });

  testWidgets('missing file is marked and skipped', (tester) async {
    final backend = await open(tester, ['Clara/Tuch.mp3', 'Anna/Jonglage.mp3']);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    await go(tester);
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).played, isTrue);
  });
}
