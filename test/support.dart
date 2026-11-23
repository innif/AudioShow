import 'dart:io';

import 'package:audioshow/app_state.dart';
import 'package:audioshow/storage/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_audio_backend.dart';

/// Creates a temp cue root with the given relative files.
Directory makeCueRoot(List<String> files) {
  final root = Directory.systemTemp.createTempSync('cueroot');
  for (final rel in files) {
    final f = File('${root.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('x');
  }
  return root;
}

Future<AppState> makeState(WidgetTester tester, {String? root, bool permission = true}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(
    backend: FakeAudioBackend(),
    checkPermission: () async => permission,
    initialSettings: AppSettings(cueRoot: root),
  );
  await tester.runAsync(state.init);
  return state;
}

Future<void> pumpApp(WidgetTester tester, AppState state, Widget child) async {
  tester.view.physicalSize = const Size(2000, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: state,
    child: MaterialApp(theme: ThemeData.dark(), home: child),
  ));
  await tester.pump();
}

/// Lets real file IO started by the widget finish, then rebuilds.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
}
