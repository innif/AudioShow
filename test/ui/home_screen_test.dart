import 'package:audioshow/storage/show_store.dart';
import 'package:audioshow/ui/home_screen.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
