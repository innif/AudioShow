import 'dart:convert';
import 'dart:io';

import '../model/cue_settings.dart';
import 'atomic_write.dart';

/// Reads and writes `cues.json` in an artist folder.
///
/// Format: `{"version": 1, "files": {"<file name>": {...CueSettings}}}`.
class CueSettingsStore {
  static const fileName = 'cues.json';

  File _file(Directory dir) => File('${dir.path}${Platform.pathSeparator}$fileName');

  /// Returns the raw document, or null if missing. Throws [FormatException]
  /// if the file exists but is not a valid JSON object.
  Future<Map<String, dynamic>?> _readRaw(File f) async {
    if (!await f.exists()) return null;
    final decoded = jsonDecode(await f.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('cues.json is not an object');
    }
    return decoded;
  }

  Future<Map<String, CueSettings>> load(Directory artistDir) async {
    try {
      final raw = await _readRaw(_file(artistDir));
      final files = raw?['files'];
      if (files is! Map<String, dynamic>) return {};
      return {
        for (final e in files.entries)
          if (e.value is Map<String, dynamic>)
            e.key: CueSettings.fromJson(e.value as Map<String, dynamic>),
      };
    } on FormatException {
      return {};
    } on FileSystemException {
      // e.g. not UTF-8 (edited with an old Windows editor) or unreadable
      return {};
    }
  }

  Future<void> save(Directory artistDir, String fileName, CueSettings settings) {
    final f = _file(artistDir);
    return withLock(f.path, () async {
      Map<String, dynamic> raw;
      try {
        raw = await _readRaw(f) ?? {};
      } on Exception {
        // FormatException (bad JSON) or FileSystemException (not UTF-8)
        final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        await f.rename('${f.path}.corrupt-$stamp');
        raw = {};
      }
      final files = raw['files'] is Map<String, dynamic>
          ? Map<String, dynamic>.of(raw['files'] as Map<String, dynamic>)
          : <String, dynamic>{};
      if (settings.isDefault) {
        files.remove(fileName);
      } else {
        files[fileName] = settings.toJson();
      }
      raw['version'] = raw['version'] ?? 1;
      raw['files'] = files;
      await writeAtomic(f, const JsonEncoder.withIndent('  ').convert(raw));
    });
  }
}
