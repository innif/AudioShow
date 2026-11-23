import 'package:audioshow/model/cue_settings.dart';
import 'package:audioshow/storage/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults when nothing stored', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppSettingsStore().load();
    expect(s.cueRoot, isNull);
    expect(s.goBehavior, GoBehavior.fadeOut);
    expect(s.goFade, const Duration(seconds: 1));
    expect(s.fadeShort, const Duration(seconds: 1));
    expect(s.fadeLong, const Duration(seconds: 5));
  });

  test('AppSettingsStore roundtrip', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppSettingsStore();
    await store.save(AppSettings(
      cueRoot: '/storage/emulated/0/Cues',
      goBehavior: GoBehavior.keepRunning,
      goFade: const Duration(milliseconds: 1500),
      fadeShort: const Duration(seconds: 2),
      fadeLong: const Duration(seconds: 8),
    ));
    final s = await store.load();
    expect(s.cueRoot, '/storage/emulated/0/Cues');
    expect(s.goBehavior, GoBehavior.keepRunning);
    expect(s.goFade, const Duration(milliseconds: 1500));
    expect(s.fadeShort, const Duration(seconds: 2));
    expect(s.fadeLong, const Duration(seconds: 8));
  });
}
