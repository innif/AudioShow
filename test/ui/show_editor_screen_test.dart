import 'dart:io';

import 'package:audioshow/library/library.dart';
import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/storage/show_store.dart';
import 'package:audioshow/ui/show_editor_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support.dart';

void main() {
  const files = ['Anna/Jonglage.mp3', 'Trio X/Intro.wav', 'Ben/Handstand.wav'];
  late Directory root;

  setUp(() => root = makeCueRoot(files));
  tearDown(() => root.deleteSync(recursive: true));

  Future<List<String>> savedEntries(WidgetTester tester) async =>
      (await tester.runAsync(() => ShowStore(root).load('2026-11-23')))!.entries;

  Future<void> open(WidgetTester tester, List<String> entries) async {
    await tester.runAsync(() async {
      final store = ShowStore(root);
      final s = await store.createForDate(DateTime(2026, 11, 23));
      await store.save(s.copyWith(entries: entries));
    });
  }

  testWidgets('adding from library appends entry and saves show', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3']);
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, const ShowEditorScreen(showName: '2026-11-23'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'handstand');
    await tester.pump();
    await tester.tap(find.byTooltip('Zur Show hinzufügen'));
    await settle(tester);
    expect(await savedEntries(tester), ['Anna/Jonglage.mp3', 'Ben/Handstand.wav']);
    expect(find.text('2  Ben – Handstand.wav'), findsOneWidget);
  });

  testWidgets('reorder by drag updates order and saves', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3', 'Trio X/Intro.wav', 'Ben/Handstand.wav']);
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, const ShowEditorScreen(showName: '2026-11-23'));
    await settle(tester);
    final handle = find.byKey(const ValueKey('handle-0'));
    final g = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    await settle(tester);
    expect((await savedEntries(tester)).first, 'Trio X/Intro.wav');
  });

  testWidgets('remove entry saves show', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3', 'Trio X/Intro.wav']);
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, const ShowEditorScreen(showName: '2026-11-23'));
    await settle(tester);
    await tester.tap(find.byTooltip('Entfernen').first);
    await settle(tester);
    expect(await savedEntries(tester), ['Trio X/Intro.wav']);
  });

  testWidgets('missing file is shown with warning marker', (tester) async {
    await open(tester, ['Clara/Tuch.mp3']);
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, const ShowEditorScreen(showName: '2026-11-23'));
    await settle(tester);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
    expect(find.textContaining('fehlt'), findsOneWidget);
  });

  testWidgets('entry shows startAt from cues.json', (tester) async {
    await open(tester, ['Anna/Jonglage.mp3']);
    final state = await makeState(tester, root: root.path);
    await tester.runAsync(() => state.saveCueSettings(
        const AudioFileRef('Anna', 'Jonglage.mp3'), const CueSettings(startAt: Duration(seconds: 12))));
    await pumpApp(tester, state, const ShowEditorScreen(showName: '2026-11-23'));
    await settle(tester);
    expect(find.textContaining('ab 0:12'), findsWidgets);
  });
}
