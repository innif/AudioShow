import 'dart:io';

import 'package:audioshow/library/library.dart';
import 'package:audioshow/library/search.dart';
import 'package:flutter_test/flutter_test.dart';

Library _lib() => Library(
      root: Directory('/x'),
      artists: [
        Artist('Anna', const [AudioFileRef('Anna', 'Jonglage.mp3')]),
        Artist('Jörg Müller', const [AudioFileRef('Jörg Müller', 'Fünf Bälle.mp3')]),
        Artist('Trio X', const [
          AudioFileRef('Trio X', 'Intro.wav'),
          AudioFileRef('Trio X', 'Hauptnummer.mp3'),
        ]),
      ],
    );

void main() {
  test('normalizeForSearch', () {
    expect(normalizeForSearch('Jörg MÜLLER – Fünf'), 'jorg muller – funf');
    expect(normalizeForSearch('ß'), 'ss');
    expect(normalizeForSearch('é'), 'e');
    expect(normalizeForSearch('Ñandú Çà'), 'nandu ca');
  });

  test('search matches artist and file name, all terms required', () {
    expect(searchLibrary(_lib(), 'trio intro').map((f) => f.relPath), ['Trio X/Intro.wav']);
    expect(searchLibrary(_lib(), 'trio jonglage'), isEmpty);
  });

  test('search ignores case and diacritics', () {
    expect(searchLibrary(_lib(), 'jorg').map((f) => f.relPath), ['Jörg Müller/Fünf Bälle.mp3']);
    expect(searchLibrary(_lib(), 'BÄLLE').length, 1);
  });

  test('empty query returns all files', () {
    expect(searchLibrary(_lib(), '  ').length, 4);
  });
}
