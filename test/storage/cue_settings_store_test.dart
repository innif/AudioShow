import 'dart:convert';
import 'dart:io';

import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/storage/cue_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  final store = CueSettingsStore();

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('cuestore');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  File cuesFile() => File('${dir.path}/cues.json');

  test('load returns empty map when cues.json missing', () async {
    expect(await store.load(dir), isEmpty);
  });

  test('save creates cues.json and load returns it', () async {
    final s = CueSettings(startAt: const Duration(seconds: 12), volume: 80);
    await store.save(dir, 'Jonglage.mp3', s);
    expect(cuesFile().existsSync(), isTrue);
    final loaded = await store.load(dir);
    expect(loaded['Jonglage.mp3'], s);
  });

  test("save preserves other files' entries and unknown top-level keys", () async {
    await cuesFile().writeAsString(jsonEncode({
      'version': 1,
      'files': {
        'a.mp3': {'volume': 50}
      },
      'foo': 1,
    }));
    await store.save(dir, 'b.mp3', const CueSettings(volume: 70));
    final raw = jsonDecode(await cuesFile().readAsString()) as Map<String, dynamic>;
    expect(raw['foo'], 1);
    expect(raw['files']['a.mp3'], {'volume': 50});
    expect(raw['files']['b.mp3'], {'volume': 70});
  });

  test('save with default settings removes the entry', () async {
    await store.save(dir, 'a.mp3', const CueSettings(volume: 50));
    await store.save(dir, 'a.mp3', const CueSettings());
    expect(await store.load(dir), isEmpty);
  });

  test('corrupt cues.json: load returns empty, save backs it up', () async {
    await cuesFile().writeAsString('{nope');
    expect(await store.load(dir), isEmpty);
    await store.save(dir, 'a.mp3', const CueSettings(volume: 50));
    final backups = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.uri.pathSegments.last.startsWith('cues.json.corrupt-'))
        .toList();
    expect(backups, hasLength(1));
    expect(await backups.single.readAsString(), '{nope');
    expect((await store.load(dir))['a.mp3']!.volume, 50);
  });

  test('save leaves no temp file behind', () async {
    await store.save(dir, 'a.mp3', const CueSettings(volume: 50));
    final names = dir.listSync().map((e) => e.uri.pathSegments.last).toList();
    expect(names, ['cues.json']);
  });

  test('concurrent saves to the same folder all persist', () async {
    await Future.wait([
      store.save(dir, 'a.mp3', const CueSettings(volume: 10)),
      store.save(dir, 'b.mp3', const CueSettings(volume: 20)),
      store.save(dir, 'c.mp3', const CueSettings(volume: 30)),
    ]);
    final loaded = await store.load(dir);
    expect(loaded.keys.toSet(), {'a.mp3', 'b.mp3', 'c.mp3'});
  });
}
