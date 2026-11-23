import 'dart:io';

import 'package:audioshow/model/show.dart';
import 'package:audioshow/storage/show_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ShowStore store;
  final d23 = DateTime(2026, 11, 23, 20, 15);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('shows');
    store = ShowStore(root);
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('createForDate names show yyyy-MM-dd and creates _Shows', () async {
    final s = await store.createForDate(d23);
    expect(s.name, '2026-11-23');
    expect(s.entries, isEmpty);
    expect(File('${root.path}/_Shows/2026-11-23.json').existsSync(), isTrue);
  });

  test('second show on same day gets -2, third -3', () async {
    await store.createForDate(d23);
    expect((await store.createForDate(d23)).name, '2026-11-23-2');
    expect((await store.createForDate(d23)).name, '2026-11-23-3');
  });

  test('save/load roundtrip keeps entry order and duplicates', () async {
    final s = await store.createForDate(d23);
    final e = ['B/b.mp3', 'A/a.mp3', 'B/b.mp3'];
    await store.save(s.copyWith(entries: e));
    expect((await store.load(s.name)).entries, e);
  });

  test('listNames newest first', () async {
    await store.createForDate(DateTime(2026, 11, 21));
    await store.createForDate(d23);
    await store.createForDate(d23);
    expect(await store.listNames(), ['2026-11-23-2', '2026-11-23', '2026-11-21']);
  });

  test('listNames on empty root is empty', () async {
    expect(await store.listNames(), isEmpty);
  });

  test('duplicate copies entries under new date name', () async {
    final s = await store.createForDate(DateTime(2026, 11, 21));
    await store.save(s.copyWith(entries: ['A/a.mp3']));
    final d = await store.duplicate(s.name, d23);
    expect(d.name, '2026-11-23');
    expect((await store.load(d.name)).entries, ['A/a.mp3']);
  });

  test('delete removes the show', () async {
    final s = await store.createForDate(d23);
    await store.delete(s.name);
    expect(await store.listNames(), isEmpty);
  });

  test('save is atomic (no .tmp left)', () async {
    final s = await store.createForDate(d23);
    await store.save(s.copyWith(entries: ['A/a.mp3']));
    final names = Directory('${root.path}/_Shows').listSync().map((e) => e.uri.pathSegments.last);
    expect(names, ['2026-11-23.json']);
  });

  test('load of corrupt show throws FormatException', () async {
    Directory('${root.path}/_Shows').createSync();
    File('${root.path}/_Shows/kaputt.json').writeAsStringSync('{nope');
    expect(() => store.load('kaputt'), throwsFormatException);
  });

  test('lastUsed maps relPath to newest show date', () async {
    final a = await store.createForDate(DateTime(2026, 11, 1));
    await store.save(a.copyWith(entries: ['A/a.mp3', 'B/b.mp3']));
    final b = await store.createForDate(DateTime(2026, 11, 20));
    await store.save(b.copyWith(entries: ['A/a.mp3']));
    await store.save(const Show(name: 'Probe', entries: ['C/c.mp3']));
    final used = await store.lastUsed();
    expect(used['A/a.mp3'], DateTime(2026, 11, 20));
    expect(used['B/b.mp3'], DateTime(2026, 11, 1));
    expect(used.containsKey('C/c.mp3'), isFalse);
  });
}
