import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const audioExtensions = {'.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac'};

bool isAudioFileName(String name) =>
    !name.startsWith('.') && audioExtensions.contains(p.extension(name).toLowerCase());

/// A file in the cue folder, identified by `artist/fileName`.
@immutable
class AudioFileRef {
  final String artist;
  final String fileName;
  const AudioFileRef(this.artist, this.fileName);

  factory AudioFileRef.parse(String relPath) {
    final i = relPath.indexOf('/');
    return AudioFileRef(relPath.substring(0, i), relPath.substring(i + 1));
  }

  String get relPath => '$artist/$fileName';

  @override
  bool operator ==(Object other) => other is AudioFileRef && other.relPath == relPath;
  @override
  int get hashCode => relPath.hashCode;
  @override
  String toString() => relPath;
}

class Artist {
  final String name;
  final List<AudioFileRef> files;
  const Artist(this.name, this.files);
}

int _ci(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

class Library {
  final Directory? root;
  final List<Artist> artists;
  final String? error;

  Library({required this.root, required this.artists, this.error});

  static Library empty(String error) => Library(root: null, artists: const [], error: error);

  late final List<AudioFileRef> allFiles = [for (final a in artists) ...a.files];

  Directory artistDir(String artist) => Directory(p.join(root!.path, artist));
  File fileFor(AudioFileRef ref) => File(p.join(root!.path, ref.artist, ref.fileName));
  bool contains(String relPath) => allFiles.any((f) => f.relPath == relPath);
}

class LibraryScanner {
  Future<Library> scan(Directory root) async {
    try {
      if (!await root.exists()) {
        return Library(root: root, artists: const [], error: 'Cue-Ordner nicht gefunden: ${root.path}');
      }
      final artists = <Artist>[];
      await for (final e in root.list(followLinks: false)) {
        if (e is! Directory) continue;
        final name = p.basename(e.path);
        if (name.startsWith('_') || name.startsWith('.')) continue;
        final files = <AudioFileRef>[];
        await for (final f in e.list(followLinks: false)) {
          if (f is! File) continue;
          final fn = p.basename(f.path);
          if (isAudioFileName(fn)) files.add(AudioFileRef(name, fn));
        }
        files.sort((a, b) => _ci(a.fileName, b.fileName));
        artists.add(Artist(name, files));
      }
      artists.sort((a, b) => _ci(a.name, b.name));
      return Library(root: root, artists: artists);
    } on FileSystemException catch (e) {
      return Library(root: root, artists: const [], error: 'Kein Zugriff auf den Cue-Ordner: ${e.message}');
    }
  }
}
