import 'dart:io';

import 'package:audioshow/library/library.dart';
import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/model/show.dart';
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
}
