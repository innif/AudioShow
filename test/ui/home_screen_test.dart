import 'package:audioshow/storage/show_store.dart';
import 'package:audioshow/ui/home_screen.dart';
import 'package:audioshow/app_state.dart';
import 'package:audioshow/storage/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_audio_backend.dart';

import '../support.dart';

void main() {
  testWidgets('without cue folder, home shows prompt to choose folder', (tester) async {
    final state = await makeState(tester);
    await pumpApp(tester, state, const HomeScreen());
    expect(find.text('Cue-Ordner wählen'), findsOneWidget);
  });

  testWidgets('with library error, home shows error message and settings button', (tester) async {
    final state = await makeState(tester, root: '/gibts/nicht');
    await pumpApp(tester, state, const HomeScreen());
    expect(find.textContaining('Cue-Ordner nicht gefunden'), findsOneWidget);
    expect(find.text('Einstellungen öffnen'), findsOneWidget);
  });

  testWidgets('without storage permission, home asks for it', (tester) async {
    final root = makeCueRoot([]);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path, permission: false);
    await pumpApp(tester, state, const HomeScreen());
    expect(find.text('Zugriff erlauben'), findsOneWidget);
  });

  testWidgets('home lists show names newest first and has "Neue Show"', (tester) async {
    final root = makeCueRoot([]);
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.runAsync(() async {
      final store = ShowStore(root);
      await store.createForDate(DateTime(2026, 11, 21));
      await store.createForDate(DateTime(2026, 11, 23));
    });
    final state = await makeState(tester, root: root.path);
    await pumpApp(tester, state, const HomeScreen());
    expect(find.text('Neue Show'), findsOneWidget);
    final a = tester.getTopLeft(find.text('2026-11-23'));
    final b = tester.getTopLeft(find.text('2026-11-21'));
    expect(a.dy, lessThan(b.dy));
  });

  Future<AppState> stateWithLastShow(WidgetTester tester, String root, String? lastShow) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
      backend: FakeAudioBackend(),
      checkPermission: () async => true,
      initialSettings: AppSettings(cueRoot: root, lastShow: lastShow),
    );
    await tester.runAsync(state.init);
    return state;
  }

  Future<void> pumpWithRoutes(WidgetTester tester, AppState state) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: const HomeScreen(),
        onGenerateRoute: (s) => MaterialPageRoute(
          settings: s,
          builder: (_) => Scaffold(appBar: AppBar(), body: Text('SHOW ${s.arguments}')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('opens the last opened show on start', (tester) async {
    final root = makeCueRoot([]);
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.runAsync(() => ShowStore(root).createForDate(DateTime(2026, 11, 21)));
    await tester.runAsync(() => ShowStore(root).createForDate(DateTime(2026, 11, 23)));
    final state = await stateWithLastShow(tester, root.path, '2026-11-21');
    await pumpWithRoutes(tester, state);
    expect(find.text('SHOW 2026-11-21'), findsOneWidget);
    // back leads to the list and it does not reopen
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('2026-11-23'), findsOneWidget);
    expect(find.text('SHOW 2026-11-21'), findsNothing);
  });

  testWidgets('stays on the list when the last show no longer exists', (tester) async {
    final root = makeCueRoot([]);
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.runAsync(() => ShowStore(root).createForDate(DateTime(2026, 11, 23)));
    final state = await stateWithLastShow(tester, root.path, '2026-01-01');
    await pumpWithRoutes(tester, state);
    expect(find.textContaining('SHOW'), findsNothing);
    expect(find.text('2026-11-23'), findsOneWidget);
  });

  testWidgets('opening a show remembers it', (tester) async {
    final root = makeCueRoot([]);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await stateWithLastShow(tester, root.path, null);
    await tester.runAsync(() => state.rememberShow('2026-11-23'));
    expect(state.settings.lastShow, '2026-11-23');
    expect((await tester.runAsync(() => AppSettingsStore().load()))!.lastShow, '2026-11-23');
  });
}
