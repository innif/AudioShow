import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/show.dart';
import 'atomic_write.dart';

/// Shows live in `<cueRoot>/_Shows/<name>.json`.
class ShowStore {
  final Directory cueRoot;
  ShowStore(this.cueRoot);

  static final _datePrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:-(\d+))?$');

  Directory get _dir => Directory(p.join(cueRoot.path, '_Shows'));
  File _file(String name) => File(p.join(_dir.path, '$name.json'));

  static String _dateName(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime? _dateOf(String name) {
    final m = _datePrefix.firstMatch(name);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  /// Sort key: date desc, then same-day suffix desc; undated shows last.
  static int _compareNewestFirst(String a, String b) {
    final ma = _datePrefix.firstMatch(a), mb = _datePrefix.firstMatch(b);
    if (ma == null || mb == null) {
      if (ma == null && mb == null) return a.compareTo(b);
      return ma == null ? 1 : -1;
    }
    final byDate = '${mb[1]}${mb[2]}${mb[3]}'.compareTo('${ma[1]}${ma[2]}${ma[3]}');
    if (byDate != 0) return byDate;
    return int.parse(mb[4] ?? '1').compareTo(int.parse(ma[4] ?? '1'));
  }

  Future<List<String>> listNames() async {
    if (!await _dir.exists()) return [];
    final names = <String>[];
    await for (final e in _dir.list()) {
      if (e is File && e.path.endsWith('.json')) {
        names.add(p.basenameWithoutExtension(e.path));
      }
    }
    names.sort(_compareNewestFirst);
    return names;
  }

  Future<String> _freeName(DateTime date) async {
    final base = _dateName(date);
    if (!await _file(base).exists()) return base;
    for (var i = 2;; i++) {
      final n = '$base-$i';
      if (!await _file(n).exists()) return n;
    }
  }

  Future<Show> createForDate(DateTime date, {List<String> entries = const []}) async {
    await _dir.create(recursive: true);
    final show = Show(name: await _freeName(date), entries: entries);
    await save(show);
    return show;
  }

  Future<Show> load(String name) async {
    final decoded = jsonDecode(await _file(name).readAsString());
    if (decoded is! Map<String, dynamic>) throw const FormatException('Show is not an object');
    return Show.fromJson(name, decoded);
  }

  Future<void> save(Show show) async {
    await _dir.create(recursive: true);
    final f = _file(show.name);
    await withLock(f.path, () => writeAtomic(f, const JsonEncoder.withIndent('  ').convert(show.toJson())));
  }

  Future<Show> duplicate(String sourceName, DateTime date) async {
    final src = await load(sourceName);
    return createForDate(date, entries: src.entries);
  }

  Future<void> delete(String name) async {
    final f = _file(name);
    if (await f.exists()) await f.delete();
  }

  /// relPath -> date of the newest dated show containing it.
  Future<Map<String, DateTime>> lastUsed() async {
    final result = <String, DateTime>{};
    for (final name in await listNames()) {
      final date = _dateOf(name);
      if (date == null) continue;
      Show show;
      try {
        show = await load(name);
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
      for (final e in show.entries) {
        final prev = result[e];
        if (prev == null || date.isAfter(prev)) result[e] = date;
      }
    }
    return result;
  }
}
