import 'package:shared_preferences/shared_preferences.dart';

import '../model/cue_settings.dart';

class AppSettings {
  final String? cueRoot;
  final GoBehavior goBehavior;
  final Duration goFade;
  final Duration fadeShort;
  final Duration fadeLong;

  /// Name of the show opened last; reopened on app start.
  final String? lastShow;

  const AppSettings({
    this.cueRoot,
    this.goBehavior = GoBehavior.fadeOut,
    this.goFade = const Duration(seconds: 1),
    this.fadeShort = const Duration(seconds: 1),
    this.fadeLong = const Duration(seconds: 5),
    this.lastShow,
  });

  static const suggestedCueRoot = '/storage/emulated/0/Cues';

  AppSettings copyWith({
    String? cueRoot,
    GoBehavior? goBehavior,
    Duration? goFade,
    Duration? fadeShort,
    Duration? fadeLong,
    String? lastShow,
  }) =>
      AppSettings(
        cueRoot: cueRoot ?? this.cueRoot,
        goBehavior: goBehavior ?? this.goBehavior,
        goFade: goFade ?? this.goFade,
        fadeShort: fadeShort ?? this.fadeShort,
        fadeLong: fadeLong ?? this.fadeLong,
        lastShow: lastShow ?? this.lastShow,
      );
}

class AppSettingsStore {
  static const _root = 'cueRoot',
      _go = 'goBehavior',
      _goFade = 'goFadeMs',
      _short = 'fadeShortMs',
      _long = 'fadeLongMs',
      _lastShow = 'lastShow';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    const d = AppSettings();
    Duration ms(String k, Duration def) {
      final v = p.getInt(k);
      return v == null ? def : Duration(milliseconds: v);
    }

    return AppSettings(
      cueRoot: p.getString(_root),
      goBehavior: goBehaviorFromName(p.getString(_go)) ?? d.goBehavior,
      goFade: ms(_goFade, d.goFade),
      fadeShort: ms(_short, d.fadeShort),
      fadeLong: ms(_long, d.fadeLong),
      lastShow: p.getString(_lastShow),
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    if (s.cueRoot == null) {
      await p.remove(_root);
    } else {
      await p.setString(_root, s.cueRoot!);
    }
    await p.setString(_go, s.goBehavior.name);
    await p.setInt(_goFade, s.goFade.inMilliseconds);
    await p.setInt(_short, s.fadeShort.inMilliseconds);
    await p.setInt(_long, s.fadeLong.inMilliseconds);
    if (s.lastShow == null) {
      await p.remove(_lastShow);
    } else {
      await p.setString(_lastShow, s.lastShow!);
    }
  }
}
