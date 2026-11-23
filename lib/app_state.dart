import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'library/library.dart';
import 'model/cue_settings.dart';
import 'model/show.dart';
import 'playback/audio_backend.dart';
import 'playback/show_engine.dart';
import 'storage/app_settings.dart';
import 'storage/cue_settings_store.dart';
import 'storage/import_service.dart';
import 'storage/show_store.dart';

Future<bool> _defaultCheckPermission() async {
  if (!Platform.isAndroid) return true;
  return await Permission.manageExternalStorage.isGranted || await Permission.storage.isGranted;
}

/// App-wide state: settings, library scan, show list and file stores.
class AppState extends ChangeNotifier {
  AppState({
    required this.backend,
    AppSettingsStore? settingsStore,
    Future<bool> Function()? checkPermission,
    AppSettings? initialSettings,
  })  : _settingsStore = settingsStore ?? AppSettingsStore(),
        _checkPermission = checkPermission ?? _defaultCheckPermission,
        _initialSettings = initialSettings;

  final AudioBackend backend;
  final AppSettingsStore _settingsStore;
  final Future<bool> Function() _checkPermission;
  final AppSettings? _initialSettings;

  final CueSettingsStore cueStore = CueSettingsStore();
  final ImportService importer = ImportService();
  final LibraryScanner _scanner = LibraryScanner();

  AppSettings settings = const AppSettings();
  Library library = Library.empty('Kein Cue-Ordner gewählt');
  List<String> showNames = const [];
  bool hasPermission = true;
  bool ready = false;

  ShowStore? get showStore => settings.cueRoot == null ? null : ShowStore(Directory(settings.cueRoot!));

  Future<void> init() async {
    try {
      settings = _initialSettings ?? await _settingsStore.load();
    } catch (_) {
      settings = const AppSettings();
    }
    await rescan();
    ready = true;
    notifyListeners();
  }

  /// Never throws: any failure ends up in [library.error].
  Future<void> rescan() async {
    try {
      await _rescan();
    } catch (e) {
      library = Library.empty('Fehler beim Einlesen des Cue-Ordners: $e');
      showNames = const [];
      lastUsed = const {};
      _cueSettings.clear();
      notifyListeners();
    }
  }

  Future<void> _rescan() async {
    hasPermission = await _checkPermission();
    final root = settings.cueRoot;
    if (root == null) {
      library = Library.empty('Kein Cue-Ordner gewählt');
      showNames = const [];
    } else {
      library = await _scanner.scan(Directory(root));
      showNames = library.error == null ? await showStore!.listNames() : const [];
    }
    lastUsed = library.error == null && showStore != null ? await showStore!.lastUsed() : const {};
    _cueSettings.clear();
    for (final a in library.artists) {
      final map = await settingsForArtist(a.name);
      for (final e in map.entries) {
        _cueSettings[AudioFileRef(a.name, e.key).relPath] = e.value;
      }
    }
    notifyListeners();
  }

  final Map<String, CueSettings> _cueSettings = {};

  /// Cached settings from the last scan (kept current by [saveCueSettings]).
  CueSettings settingsOf(AudioFileRef ref) => _cueSettings[ref.relPath] ?? const CueSettings();

  /// relPath -> date of the newest show using it; refreshed by [rescan].
  Map<String, DateTime> lastUsed = const {};

  Future<void> addArtistFolder(String name) async {
    final n = importer.sanitizeArtistName(name);
    await library.artistDir(n).create(recursive: true);
    await rescan();
  }

  Future<List<AudioFileRef>> importFiles(String artist, List<File> files) async {
    final refs = await importer.importFiles(library.root!, artist, files);
    await rescan();
    return refs;
  }

  Future<void> requestPermission() async {
    if (Platform.isAndroid) {
      final s = await Permission.manageExternalStorage.request();
      if (!s.isGranted) await Permission.storage.request();
    }
    await rescan();
  }

  Future<void> updateSettings(AppSettings s) async {
    final rootChanged = s.cueRoot != settings.cueRoot;
    settings = s;
    await _settingsStore.save(s);
    if (rootChanged) {
      await rescan();
    } else {
      notifyListeners();
    }
  }

  Future<Show> createShowToday() async {
    final show = await showStore!.createForDate(DateTime.now());
    await rescan();
    return show;
  }

  Future<Show> duplicateForToday(String name) async {
    final show = await showStore!.duplicate(name, DateTime.now());
    await rescan();
    return show;
  }

  Future<void> deleteShow(String name) async {
    await showStore!.delete(name);
    await rescan();
  }

  AudioVoice? _preview;
  AudioFileRef? previewRef;
  StreamSubscription<void>? _previewDone;

  /// Starts (or, for the same file, stops) listening to a file outside the show.
  Future<void> togglePreview(AudioFileRef ref) async {
    final same = ref == previewRef;
    stopPreview();
    if (same) return;
    previewRef = ref;
    notifyListeners();
    final s = settingsOf(ref);
    final AudioVoice v;
    try {
      v = await backend.load(library.fileFor(ref).path, initialPosition: s.startAt);
    } catch (_) {
      if (previewRef == ref) {
        previewRef = null;
        notifyListeners();
      }
      rethrow;
    }
    if (previewRef != ref) {
      unawaited(v.dispose());
      return;
    }
    _preview = v;
    await v.setVolume(s.volume / 100);
    await v.play();
    _previewDone = v.completed.listen((_) {
      if (previewRef == ref) stopPreview();
    });
  }

  void stopPreview() {
    final v = _preview;
    _previewDone?.cancel();
    _previewDone = null;
    _preview = null;
    if (previewRef != null) {
      previewRef = null;
      notifyListeners();
    }
    if (v != null) unawaited(v.stop().whenComplete(v.dispose));
  }

  Future<Map<String, CueSettings>> settingsForArtist(String artist) =>
      cueStore.load(library.artistDir(artist));

  Future<void> saveCueSettings(AudioFileRef ref, CueSettings s) async {
    await cueStore.save(library.artistDir(ref.artist), ref.fileName, s);
    _cueSettings[ref.relPath] = s;
    notifyListeners();
  }

  /// Resolves show entries to files and their current settings.
  Future<List<ResolvedCue>> resolve(Show show) async {
    final byArtist = <String, Map<String, CueSettings>>{};
    final result = <ResolvedCue>[];
    for (final rel in show.entries) {
      final ref = AudioFileRef.parse(rel);
      final file = library.fileFor(ref);
      final settings = byArtist[ref.artist] ??= await settingsForArtist(ref.artist);
      result.add(ResolvedCue(
        relPath: rel,
        absPath: file.path,
        settings: settings[ref.fileName] ?? const CueSettings(),
        missing: !await file.exists(),
      ));
    }
    return result;
  }
}
