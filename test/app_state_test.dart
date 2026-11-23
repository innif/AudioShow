import 'dart:io';

import 'package:audioshow/library/library.dart';
import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/model/show.dart';
import 'package:audioshow/app_state.dart';
import 'package:audioshow/storage/app_settings.dart';

import 'fakes/fake_audio_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('resolve marks missing files and attaches settings', (tester) async {
    final root = makeCueRoot(['Anna/a.mp3']);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path);
    await tester.runAsync(() => state.saveCueSettings(
        const AudioFileRef('Anna', 'a.mp3'), const CueSettings(startAt: Duration(seconds: 12))));
    final cues = (await tester.runAsync(
        () => state.resolve(const Show(name: 's', entries: ['Anna/a.mp3', 'Clara/Tuch.mp3']))))!;
    expect(cues[0].missing, isFalse);
    expect(cues[0].settings.startAt, const Duration(seconds: 12));
    expect(cues[0].absPath, File('${root.path}/Anna/a.mp3').path.replaceAll('/', Platform.pathSeparator));
    expect(cues[1].missing, isTrue);
  });

  testWidgets('init with missing root yields library error', (tester) async {
    final state = await makeState(tester, root: '${Directory.systemTemp.path}/gibtsnicht-xyz');
    expect(state.library.error, isNotNull);
  });

  testWidgets('createShowToday adds a show name', (tester) async {
    final root = makeCueRoot([]);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path);
    final show = (await tester.runAsync(state.createShowToday))!;
    expect(state.showNames, [show.name]);
  });

  testWidgets('init always becomes ready and reports scan errors', (tester) async {
    final state = AppState(
      backend: FakeAudioBackend(),
      checkPermission: () async => throw const FileSystemException('kaputt'),
      initialSettings: const AppSettings(cueRoot: '/x'),
    );
    await tester.runAsync(state.init);
    expect(state.ready, isTrue);
    expect(state.library.error, contains('kaputt'));
  });

  testWidgets('opening show mode stops a running preview', (tester) async {
    final root = makeCueRoot(['Anna/a.mp3']);
    addTearDown(() => root.deleteSync(recursive: true));
    final state = await makeState(tester, root: root.path);
    await tester.runAsync(() => state.togglePreview(const AudioFileRef('Anna', 'a.mp3')));
    final v = (state.backend as FakeAudioBackend).voices.single;
    expect(v.played, isTrue);
    state.stopPreview();
    await tester.pump();
    expect(v.stopped, isTrue);
    expect(state.previewRef, isNull);
  });
}
