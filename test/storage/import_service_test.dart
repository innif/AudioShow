import 'dart:io';

import 'package:audioshow/library/library.dart';
import 'package:audioshow/storage/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory usb;
  final svc = ImportService();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('root');
    usb = await Directory.systemTemp.createTemp('usb');
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await usb.delete(recursive: true);
  });

  File src(String name, [String content = 'audio']) =>
      File('${usb.path}/$name')..writeAsStringSync(content);

  test('import copies files into artist folder, creating it', () async {
    final refs = await svc.importFiles(root, 'Neue Künstlerin', [src('Act.mp3'), src('Outro.wav')]);
    expect(refs, const [AudioFileRef('Neue Künstlerin', 'Act.mp3'), AudioFileRef('Neue Künstlerin', 'Outro.wav')]);
    expect(File('${root.path}/Neue Künstlerin/Act.mp3').readAsStringSync(), 'audio');
    expect(File('${usb.path}/Act.mp3').existsSync(), isTrue, reason: 'source stays');
  });

  test('import never overwrites: clash becomes "Name (2).mp3"', () async {
    await svc.importFiles(root, 'A', [src('Act.mp3', 'old')]);
    final refs = await svc.importFiles(root, 'A', [src('Act.mp3', 'new')]);
    expect(refs.single.fileName, 'Act (2).mp3');
    expect(File('${root.path}/A/Act.mp3').readAsStringSync(), 'old');
    expect(File('${root.path}/A/Act (2).mp3').readAsStringSync(), 'new');
  });

  test('sanitizeArtistName', () {
    expect(svc.sanitizeArtistName('  Trio X  '), 'Trio X');
    expect(svc.sanitizeArtistName('A/B\\C:D*E?F"G<H>I|J'), 'A_B_C_D_E_F_G_H_I_J');
    expect(svc.sanitizeArtistName('_Shows'), 'Shows');
    expect(svc.sanitizeArtistName('..geheim'), 'geheim');
    expect(() => svc.sanitizeArtistName('  '), throwsArgumentError);
    expect(() => svc.sanitizeArtistName('__'), throwsArgumentError);
  });
}
