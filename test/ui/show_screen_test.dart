import 'dart:io';

import 'package:audioshow/library/library.dart';
import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/storage/show_store.dart';
import 'package:audioshow/ui/show_screen.dart';
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

  Future<List<String>> savedEntries(WidgetTester tester) async =>
      (await tester.runAsync(() => ShowStore(root).load('2026-11-23')))!.entries;

  Future<FakeAudioBackend> open(WidgetTester tester, List<String> entries,
      {Map<String, CueSettings> settings = const {}, bool edit = true}) async {
    await tester.runAsync(() async {
      final store = ShowStore(root);
      final s = await store.createForDate(DateTime(2026, 11, 23));
      await store.save(s.copyWith(entries: entries));
    });
    final state = await makeState(tester, root: root.path);
    for (final e in settings.entries) {
      await tester.runAsync(() => state.saveCueSettings(AudioFileRef.parse(e.key), e.value));
    }
    await pumpApp(tester, state, const ShowScreen(showName: '2026-11-23', keepAwake: false));
    await settle(tester);
    if (!edit) {
      await tester.tap(find.byKey(const Key('editSwitch')));
      await tester.pumpAndSettle();
    }
    return state.backend as FakeAudioBackend;
  }

  Future<void> go(WidgetTester tester) async {
    await tester.tap(find.text('GO'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Confirms the "Cue entfernen?" dialog.
  Future<void> confirmRemove(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Entfernen'));
    await tester.pumpAndSettle();
  }

  Finder nextRow() => find.ancestor(of: find.text('NÄCHSTER'), matching: find.byType(ListTile));

  // --- mode switch ---

  testWidgets('opens in edit mode with archive visible', (tester) async {
    await open(tester, files);
    expect(find.byKey(const Key('librarySearch')), findsOneWidget);
    expect(find.byKey(const ValueKey('handle-0')), findsOneWidget);
    expect(find.byTooltip('Einstellungen'), findsWidgets);
  });

  testWidgets('edit switch off hides archive, handles, settings and remove', (tester) async {
    await open(tester, files, edit: false);
    expect(find.byKey(const Key('librarySearch')), findsNothing);
    expect(find.byIcon(Icons.drag_handle), findsNothing);
    expect(find.byTooltip('Einstellungen'), findsNothing);
    expect(find.byTooltip('Entfernen'), findsNothing);
  });

  testWidgets('controls are smaller in edit mode', (tester) async {
    await open(tester, files);
    final editHeight = tester.getSize(find.byKey(const Key('goButton'))).height;
    await tester.tap(find.byKey(const Key('editSwitch')));
    await tester.pumpAndSettle();
    final showHeight = tester.getSize(find.byKey(const Key('goButton'))).height;
    expect(editHeight, lessThan(showHeight));
  });

  // --- running the show (works in both modes) ---

  testWidgets('GO button starts next cue and marks following as NÄCHSTER', (tester) async {
    final backend = await open(tester, files, edit: false);
    await go(tester);
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).played, isTrue);
    expect(find.descendant(of: nextRow(), matching: find.text('Trio X – Intro.wav')), findsOneWidget);
  });

  testWidgets('GO and select work while editing', (tester) async {
    final backend = await open(tester, files);
    await tester.tap(find.text('Ben – Handstand.wav'));
    await tester.pump();
    expect(find.descendant(of: nextRow(), matching: find.text('Ben – Handstand.wav')), findsOneWidget);
    expect(backend.voices.where((v) => v.played), isEmpty);
    await go(tester);
    expect(backend.voiceFor(abs('Ben/Handstand.wav')).played, isTrue);
  });

  testWidgets('tapping a cue never opens settings', (tester) async {
    await open(tester, files);
    await tester.tap(find.text('Anna – Jonglage.mp3'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern'), findsNothing);
    await tester.tap(find.byKey(const Key('editSwitch')));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Anna – Jonglage.mp3'));
    await tester.pumpAndSettle();
    expect(find.text('Speichern'), findsNothing);
  });

  testWidgets('STOP ALL stops all running', (tester) async {
    final keep = const CueSettings(goBehavior: GoBehavior.keepRunning);
    final backend = await open(tester, files, settings: {'Anna/Jonglage.mp3': keep}, edit: false);
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
    await open(tester, files, settings: {'Anna/Jonglage.mp3': keep}, edit: false);
    await go(tester);
    await go(tester);
    expect(find.byKey(const ValueKey('running-row')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('seekbar')), findsNWidgets(2));
    expect(find.byTooltip('Von Anfang'), findsNWidgets(2));
  });

  testWidgets('tap on seek bar without drag does not seek; drag does', (tester) async {
    final backend = await open(tester, files, edit: false);
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
    expect(v.seeks.single.inSeconds, inInclusiveRange(80, 100));
  });

  testWidgets('Von Anfang seeks to saved start', (tester) async {
    final backend = await open(tester, files,
        settings: {'Anna/Jonglage.mp3': const CueSettings(startAt: Duration(seconds: 10))}, edit: false);
    await go(tester);
    final v = backend.voiceFor(abs('Anna/Jonglage.mp3'));
    v.emitPosition(const Duration(seconds: 60));
    await tester.tap(find.byTooltip('Von Anfang'));
    await tester.pump();
    expect(v.seeks.last, const Duration(seconds: 10));
  });

  testWidgets('end of show shows "Ende der Show" and GO is disabled', (tester) async {
    final backend = await open(tester, ['Anna/Jonglage.mp3'], edit: false);
    await go(tester);
    expect(find.text('Ende der Show'), findsOneWidget);
    final loads = backend.voices.length;
    await go(tester);
    expect(backend.voices.length, loads);
  });

  testWidgets('missing file is marked and skipped', (tester) async {
    final backend = await open(tester, ['Clara/Tuch.mp3', 'Anna/Jonglage.mp3'], edit: false);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(find.textContaining('fehlt'), findsOneWidget);
    await go(tester);
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).played, isTrue);
  });

  // --- editing (with and without playback) ---

  testWidgets('adding from library appends entry and saves show', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3']);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'handstand');
    await tester.pump();
    await tester.tap(find.byTooltip('Zur Show hinzufügen'));
    await settle(tester);
    expect(await savedEntries(tester), ['Anna/Jonglage.mp3', 'Ben/Handstand.wav']);
    expect(find.text('Ben – Handstand.wav'), findsOneWidget);
  });

  testWidgets('adding while playing keeps playback and saves show', (tester) async {
    final backend = await open(tester, ['Anna/Jonglage.mp3']);
    await go(tester);
    expect(find.text('Ende der Show'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'handstand');
    await tester.pump();
    await tester.tap(find.byTooltip('Zur Show hinzufügen'));
    await settle(tester);
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).stopped, isFalse);
    expect(find.byKey(const ValueKey('running-row')), findsOneWidget);
    expect(find.descendant(of: nextRow(), matching: find.text('Ben – Handstand.wav')), findsOneWidget);
    expect(await savedEntries(tester), ['Anna/Jonglage.mp3', 'Ben/Handstand.wav']);
  });

  Future<void> dragHandle(WidgetTester tester, int index, double dy) async {
    final g = await tester.startGesture(tester.getCenter(find.byKey(ValueKey('handle-$index'))));
    await tester.pump(const Duration(milliseconds: 100));
    final steps = (dy.abs() / 15).ceil();
    for (var i = 0; i < steps; i++) {
      await g.moveBy(Offset(0, dy.sign * 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    await settle(tester);
  }

  testWidgets('reorder by drag updates order and saves', (tester) async {
    await open(tester, files);
    await dragHandle(tester, 0, 300);
    expect((await savedEntries(tester)).first, 'Trio X/Intro.wav');
  });

  testWidgets('reorder while playing keeps running cue and next cue', (tester) async {
    final backend = await open(tester, files);
    await go(tester); // Anna runs, Trio X is next
    await dragHandle(tester, 2, -300); // Ben to the top
    expect((await savedEntries(tester)).first, 'Ben/Handstand.wav');
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).stopped, isFalse);
    expect(find.byKey(const ValueKey('running-row')), findsOneWidget);
    expect(find.descendant(of: nextRow(), matching: find.text('Trio X – Intro.wav')), findsOneWidget);
    await go(tester);
    expect(backend.voiceFor(abs('Trio X/Intro.wav')).played, isTrue);
  });

  testWidgets('remove entry saves show', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3', 'Trio X/Intro.wav']);
    await tester.tap(find.byTooltip('Entfernen').first);
    await confirmRemove(tester);
    await settle(tester);
    expect(await savedEntries(tester), ['Trio X/Intro.wav']);
  });

  testWidgets('settings button opens cue settings in edit mode', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3']);
    final row = find.ancestor(of: find.text('Anna – Jonglage.mp3'), matching: find.byType(ListTile));
    await tester.tap(find.descendant(of: row, matching: find.byTooltip('Einstellungen')));
    await tester.pumpAndSettle();
    expect(find.text('Speichern'), findsOneWidget);
  });

  testWidgets('entry shows startAt from cues.json', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3'],
        settings: {'Anna/Jonglage.mp3': const CueSettings(startAt: Duration(seconds: 12))});
    expect(find.textContaining('ab 0:12'), findsWidgets);
  });

  // --- review fixes: list updates immediately, no stale indices ---

  Finder removeIn(String title) => find.descendant(
      of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)).first,
      matching: find.byTooltip('Entfernen'));

  List<String> shownTitles(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((t) => t.title)
      .whereType<Text>()
      .map((t) => t.data ?? '')
      .where((t) => t.contains(' – '))
      .toList();

  testWidgets('reorder shows the new order immediately (no jump back)', (tester) async {
    await open(tester, files, edit: true);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('handle-0'))));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle(); // no real IO has run yet
    expect(shownTitles(tester).first, 'Trio X – Intro.wav');
  });

  testWidgets('two quick removes delete exactly the tapped cues', (tester) async {
    await open(tester, files);
    await tester.tap(removeIn('Anna – Jonglage.mp3'));
    await confirmRemove(tester);
    await tester.tap(removeIn('Ben – Handstand.wav'));
    await confirmRemove(tester);
    expect(shownTitles(tester), ['Trio X – Intro.wav']);
    await settle(tester);
    expect(await savedEntries(tester), ['Trio X/Intro.wav']);
  });

  testWidgets('removing next cue then another quickly keeps "same position" rule', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3', 'Trio X/Intro.wav', 'Ben/Handstand.wav', 'Anna/Jonglage.mp3']);
    await tester.tap(find.text('Ben – Handstand.wav'));
    await tester.pump();
    await tester.tap(removeIn('Ben – Handstand.wav'));
    await confirmRemove(tester);
    await tester.tap(removeIn('Trio X – Intro.wav'));
    await confirmRemove(tester);
    // the entry that took Ben's place (the second Anna) is next
    expect(shownTitles(tester), ['Anna – Jonglage.mp3', 'Anna – Jonglage.mp3']);
    final rows = tester.widgetList<ListTile>(find.byType(ListTile)).where((t) => t.title is Text && (t.title as Text).data!.contains(' – ')).toList();
    expect(rows[1].selected, isTrue);
    expect(rows[0].selected, isFalse);
  });

  testWidgets('narrow layout: Archiv button sits in the app bar', (tester) async {
    await open(tester, files);
    tester.view.physicalSize = const Size(800, 1200);
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Archiv')), findsOneWidget);
    await tester.tap(find.byKey(const Key('editSwitch')));
    await tester.pumpAndSettle();
    expect(find.text('Archiv'), findsNothing);
  });

  testWidgets('remove asks for confirmation; cancel keeps the cue', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3', 'Trio X/Intro.wav']);
    await tester.tap(removeIn('Anna – Jonglage.mp3'));
    await tester.pumpAndSettle();
    expect(find.text('Cue entfernen?'), findsOneWidget);
    expect(find.textContaining('Anna – Jonglage.mp3 wird aus der Show entfernt'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(shownTitles(tester), ['Anna – Jonglage.mp3', 'Trio X – Intro.wav']);
    await settle(tester);
    expect(await savedEntries(tester), ['Anna/Jonglage.mp3', 'Trio X/Intro.wav']);
  });

  testWidgets('removing a running cue says it keeps playing', (tester) async {
    final backend = await open(tester, ['Anna/Jonglage.mp3', 'Trio X/Intro.wav']);
    await go(tester);
    await tester.tap(removeIn('Anna – Jonglage.mp3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('spielt noch zu Ende'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Entfernen'));
    await tester.pumpAndSettle();
    expect(backend.voiceFor(abs('Anna/Jonglage.mp3')).stopped, isFalse);
    expect(shownTitles(tester), ['Trio X – Intro.wav']);
  });

  testWidgets('seek bar spans the full width of the show pane', (tester) async {
    await open(tester, files, edit: false);
    await go(tester);
    final bar = tester.getSize(find.byKey(const ValueKey('seekbar'))).width;
    final row = tester.getSize(find.byKey(const ValueKey('running-row'))).width;
    expect(bar, greaterThan(row * 0.9));
  });

  testWidgets('+10 s and -10 s buttons jump in the running cue', (tester) async {
    final backend = await open(tester, files, edit: false);
    await go(tester);
    final v = backend.voiceFor(abs('Anna/Jonglage.mp3'));
    v.emitPosition(const Duration(seconds: 30));
    await tester.pump();
    await tester.tap(find.byTooltip('10 s vor'));
    await tester.pump();
    expect(v.seeks.last, const Duration(seconds: 40));
    await tester.tap(find.byTooltip('10 s zurück'));
    await tester.pump();
    expect(v.seeks.last, const Duration(seconds: 30));
  });
}
