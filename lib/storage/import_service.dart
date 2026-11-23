import 'dart:io';

import 'package:path/path.dart' as p;

import '../library/library.dart';

/// Copies audio files (e.g. from a USB stick) into an artist folder.
class ImportService {
  String sanitizeArtistName(String raw) {
    var s = raw.trim().replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    s = s.replaceFirst(RegExp(r'^[_.]+'), '').trim();
    if (s.isEmpty) throw ArgumentError.value(raw, 'artist', 'Name ist leer');
    return s;
  }

  Future<List<AudioFileRef>> importFiles(Directory cueRoot, String artist, List<File> sources) async {
    final name = sanitizeArtistName(artist);
    final dir = Directory(p.join(cueRoot.path, name));
    await dir.create(recursive: true);
    final refs = <AudioFileRef>[];
    for (final src in sources) {
      final target = await _freeTarget(dir, p.basename(src.path));
      await src.copy(target.path);
      refs.add(AudioFileRef(name, p.basename(target.path)));
    }
    return refs;
  }

  Future<File> _freeTarget(Directory dir, String fileName) async {
    var f = File(p.join(dir.path, fileName));
    if (!await f.exists()) return f;
    final stem = p.basenameWithoutExtension(fileName), ext = p.extension(fileName);
    for (var i = 2;; i++) {
      f = File(p.join(dir.path, '$stem ($i)$ext'));
      if (!await f.exists()) return f;
    }
  }
}
