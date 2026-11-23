import 'package:audioshow/library/library.dart';
import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/storage/show_store.dart';
import 'package:audioshow/ui/cue_settings_dialog.dart';
import 'package:audioshow/ui/library_pane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../support.dart';

void main() {
  const files = ['Anna/Jonglage.mp3', 'Trio X/Intro.wav', 'Trio X/Hauptnummer.mp3', 'Zora/Seil.mp3'];

  testWidgets('typing in search filters files live', (tester) async {
    final root = makeCueRoot(files);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, Scaffold(body: LibraryPane(onAdd: (_) {})));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'trio');
    await tester.pump();
    expect(find.text('Intro.wav'), findsOneWidget);
    expect(find.text('Hauptnummer.mp3'), findsOneWidget);
    expect(find.text('Jonglage.mp3'), findsNothing);
  });

  testWidgets('without query shows artists collapsed, tap expands', (tester) async {
    final root = makeCueRoot(files);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, Scaffold(body: LibraryPane(onAdd: (_) {})));
    await settle(tester);
    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Jonglage.mp3'), findsNothing);
    await tester.tap(find.text('Anna'));
    await tester.pumpAndSettle();
    expect(find.text('Jonglage.mp3'), findsOneWidget);
  });

  testWidgets('sort toggle switches between A–Z and zuletzt verwendet', (tester) async {
    final root = makeCueRoot(files);
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.runAsync(() async {
      final store = ShowStore(root);
      final s = await store.createForDate(DateTime(2026, 11, 20));
      await store.save(s.copyWith(entries: ['Zora/Seil.mp3']));
    });
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, Scaffold(body: LibraryPane(onAdd: (_) {})));
    await settle(tester);
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Anna'), lessThan(y('Zora')));
    await tester.tap(find.text('Zuletzt'));
    await settle(tester);
    expect(y('Zora'), lessThan(y('Anna')));
  });

  testWidgets('add button calls onAdd with the file ref', (tester) async {
    final root = makeCueRoot(files);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path);
    AudioFileRef? added;
    await pumpApp(tester, state, Scaffold(body: LibraryPane(onAdd: (r) => added = r)));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'jonglage');
    await tester.pump();
    await tester.tap(find.byTooltip('Zur Show hinzufügen'));
    expect(added, const AudioFileRef('Anna', 'Jonglage.mp3'));
  });

  testWidgets('file shows saved start time', (tester) async {
    final root = makeCueRoot(files);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path);
    await tester.runAsync(() => state.saveCueSettings(
        const AudioFileRef('Anna', 'Jonglage.mp3'), const CueSettings(startAt: Duration(seconds: 12))));
    await pumpApp(tester, state, Scaffold(body: LibraryPane(onAdd: (_) {})));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'jonglage');
    await tester.pump();
    expect(find.textContaining('ab 0:12'), findsOneWidget);
  });

  testWidgets('cue settings dialog returns edited startAt and volume', (tester) async {
    final state = await makeState(tester);
    CueSettings? result;
    await pumpApp(
      tester,
      state,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showCueSettingsDialog(
                context, const AudioFileRef('Anna', 'Jonglage.mp3'), const CueSettings(note: 'alt')),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('startAt')), '0:12');
    await tester.drag(find.byKey(const Key('volume')), const Offset(-3000, 0));
    await tester.pump();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(result!.startAt, const Duration(seconds: 12));
    expect(result!.volume, 0);
    expect(result!.note, 'alt');
  });

  testWidgets('cue settings dialog rejects invalid time', (tester) async {
    final state = await makeState(tester);
    await pumpApp(
      tester,
      state,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showCueSettingsDialog(context, const AudioFileRef('A', 'a.mp3'), const CueSettings()),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('startAt')), 'abc');
    await tester.pump();
    expect(find.text('Ungültige Zeit'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern'));
    expect(save.onPressed, isNull);
  });
}
