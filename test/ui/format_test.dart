import 'package:audioshow/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatTime', () {
    expect(formatTime(const Duration(seconds: 65)), '1:05');
    expect(formatTime(const Duration(hours: 1, seconds: 5)), '1:00:05');
    expect(formatTime(const Duration(seconds: -3)), '-0:03');
  });

  test('formatSeconds', () {
    expect(formatSeconds(const Duration(milliseconds: 500)), '0,5 s');
    expect(formatSeconds(const Duration(seconds: 2)), '2 s');
  });

  test('parseTime accepts m:ss, seconds and comma decimals', () {
    expect(parseTime('1:05'), const Duration(seconds: 65));
    expect(parseTime('20'), const Duration(seconds: 20));
    expect(parseTime('12,5'), const Duration(milliseconds: 12500));
    expect(parseTime('1:00:05'), const Duration(seconds: 3605));
    expect(parseTime(''), isNull);
    expect(parseTime('abc'), isNull);
    expect(parseTime('-3'), isNull);
  });
}
