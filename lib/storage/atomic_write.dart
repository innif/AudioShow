import 'dart:io';

/// Writes [content] to [file] via a temp file + rename, so a crash never
/// leaves a half-written file behind.
Future<void> writeAtomic(File file, String content) async {
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsString(content, flush: true);
  await tmp.rename(file.path);
}

final Map<String, Future<void>> _locks = {};

/// Serializes async operations per [key] (e.g. a file path).
Future<T> withLock<T>(String key, Future<T> Function() action) {
  final previous = _locks[key] ?? Future.value();
  final result = previous.then((_) => action());
  final done = result.then((_) {}, onError: (_) {});
  _locks[key] = done;
  done.then((_) {
    if (identical(_locks[key], done)) _locks.remove(key);
  });
  return result;
}
