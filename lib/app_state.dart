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
    settings = _initialSettings ?? await _settingsStore.load();
    await rescan();
    ready = true;
    notifyListeners();
  }

  Future<void> rescan() async {
    hasPermission = await _checkPermission();
    final root = settings.cueRoot;
    if (root == null) {
      library = Library.empty('Kein Cue-Ordner gewählt');
      showNames = const [];
    } else {
      library = await _scanner.scan(Directory(root));
      showNames = library.error == null ? await showStore!.listNames() : const [];
    }
    notifyListeners();
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

  Future<Map<String, CueSettings>> settingsForArtist(String artist) =>
      cueStore.load(library.artistDir(artist));

  Future<void> saveCueSettings(AudioFileRef ref, CueSettings s) async {
    await cueStore.save(library.artistDir(ref.artist), ref.fileName, s);
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
