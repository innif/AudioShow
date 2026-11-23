import 'dart:io';

import 'package:audioshow/library/library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  final scanner = LibraryScanner();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lib');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  void touch(String rel) {
    final f = File('${root.path}/$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync('x');
  }

  List<String> rels(Library lib) => lib.allFiles.map((f) => f.relPath).toList();

  test('scan lists artist folders and their audio files', () async {
    touch('Anna/Jonglage.mp3');
    touch('Trio X/Intro.WAV');
    touch('Trio X/hauptnummer.mp3');
    final lib = await scanner.scan(root);
    expect(lib.error, isNull);
    expect(lib.artists.map((a) => a.name), ['Anna', 'Trio X']);
    expect(rels(lib), ['Anna/Jonglage.mp3', 'Trio X/hauptnummer.mp3', 'Trio X/Intro.WAV']);
  });

  test('scan ignores _Shows, dot-folders, dot-files, non-audio and nested folders', () async {
    touch('_Shows/x.json');
    touch('.trash/a.mp3');
    touch('Anna/._Jonglage.mp3');
    touch('Anna/.DS_Store');
    touch('Anna/notes.txt');
    touch('Anna/cues.json');
    touch('Anna/sub/deep.mp3');
    touch('Anna/Jonglage.mp3');
    final lib = await scanner.scan(root);
    expect(lib.artists.map((a) => a.name), ['Anna']);
    expect(rels(lib), ['Anna/Jonglage.mp3']);
  });

  test('scan keeps umlauts and spaces in names', () async {
    touch('Jörg Müller/Fünf Bälle.mp3');
    final lib = await scanner.scan(root);
    expect(rels(lib), ['Jörg Müller/Fünf Bälle.mp3']);
  });

  test('scan includes artists with no audio files', () async {
    Directory('${root.path}/Neu').createSync();
    final lib = await scanner.scan(root);
    expect(lib.artists.single.name, 'Neu');
    expect(lib.artists.single.files, isEmpty);
  });

  test('scan of missing root returns empty library with error', () async {
    final lib = await scanner.scan(Directory('${root.path}/gibtsnicht'));
    expect(lib.error, isNotNull);
    expect(lib.artists, isEmpty);
  });

  test('fileFor and artistDir resolve paths under root', () async {
    touch('Anna/Jonglage.mp3');
    final lib = await scanner.scan(root);
    final ref = lib.allFiles.single;
    expect(lib.fileFor(ref).existsSync(), isTrue);
    expect(lib.artistDir('Anna').existsSync(), isTrue);
  });

  test('AudioFileRef equality by relPath', () {
    expect(const AudioFileRef('A', 'b.mp3'), const AudioFileRef('A', 'b.mp3'));
    expect(AudioFileRef.parse('A/b.mp3'), const AudioFileRef('A', 'b.mp3'));
  });
}
