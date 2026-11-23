import 'package:audioshow/model/cue_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fromJson/toJson roundtrip keeps all fields', () {
    final s = CueSettings(
      startAt: const Duration(milliseconds: 12500),
      endAt: const Duration(seconds: 180),
      volume: 90,
      fadeIn: const Duration(seconds: 2),
      goBehavior: GoBehavior.keepRunning,
      goFade: const Duration(seconds: 3),
      note: 'wartet auf Zeichen',
    );
    final json = s.toJson();
    expect(json['startAt'], 12.5);
    expect(json['goBehavior'], 'keepRunning');
    final back = CueSettings.fromJson(json);
    expect(back, s);
  });

  test('toJson omits defaults', () {
    expect(const CueSettings().toJson(), isEmpty);
    expect(const CueSettings().isDefault, isTrue);
  });

  test('unknown keys survive roundtrip', () {
    final s = CueSettings.fromJson({'startAt': 1, 'color': 'red'});
    expect(s.startAt, const Duration(seconds: 1));
    expect(s.toJson()['color'], 'red');
    expect(s.isDefault, isFalse);
  });

  test('wrong types fall back to defaults', () {
    final s = CueSettings.fromJson(
        {'startAt': 'abc', 'volume': 'laut', 'goBehavior': 'quatsch', 'endAt': true});
    expect(s.startAt, Duration.zero);
    expect(s.volume, 100);
    expect(s.goBehavior, isNull);
    expect(s.endAt, isNull);
  });

  test('copyWith can clear nullable fields', () {
    final s = CueSettings(endAt: const Duration(seconds: 5), goBehavior: GoBehavior.stop);
    final c = s.copyWith(clearEndAt: true, clearGoBehavior: true);
    expect(c.endAt, isNull);
    expect(c.goBehavior, isNull);
  });
}
