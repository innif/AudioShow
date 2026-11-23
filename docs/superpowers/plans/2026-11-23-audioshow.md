# AudioShow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Private Flutter-App für Android-Tablets, die Playbacks aus einem nach Künstler\*innen geordneten Cue-Ordner durchsuchbar macht, pro Abend zu einer Show zusammenstellt und per GO / Stop All / Fade abfährt.

**Architecture:** Reine Dart-Logik (Modelle, Datei-Stores, Suche, `ShowEngine`) ist von Flutter-UI und Audio entkoppelt und wird mit `flutter_test` + `fake_async` gegen temporäre Verzeichnisse und ein Fake-Audio-Backend getestet. Audio läuft über eine schmale `AudioBackend`-Schnittstelle, implementiert mit `just_audio`. Alle Daten (Audio, `cues.json`, Shows) liegen im Cue-Ordner, Zugriff per `dart:io` mit „Zugriff auf alle Dateien“.

**Tech Stack:** Flutter (stable), Dart, `just_audio`, `audio_session`, `permission_handler`, `file_picker`, `shared_preferences`, `wakelock_plus`, `flutter_foreground_task`, `path`, `provider`; Tests: `flutter_test`, `fake_async`.

**Spec:** `docs/superpowers/specs/2026-11-23-audioshow-design.md`

## Global Constraints

- Plattform: Android-Tablets, primär Querformat; Auslieferung als APK per Sideload, kein Play Store.
- Dateizugriff: `MANAGE_EXTERNAL_STORAGE` + `dart:io`-Pfade, kein Storage Access Framework.
- Audio: `just_audio`; Formate mindestens MP3 und WAV, zusätzlich OGG, M4A/AAC, FLAC.
- Standard-Cue-Ordner-Vorschlag: `/storage/emulated/0/Cues`. Künstler\*innen = direkte Unterordner; Ordner, die mit `_` oder `.` beginnen, sind keine Künstler\*innen; `_Shows/` enthält Shows.
- Einstellungen leben ausschließlich in `cues.json` pro Künstler\*innen-Ordner, nie in der Show-Datei. Schreiben ist atomar (temp + rename) und behält unbekannte Felder.
- GO-Standard: laufende Playbacks über 1 s ausblenden; Fade-Knöpfe 1 s und 5 s; alles global einstellbar.
- Pro-Cue-`goBehavior` gilt für den **laufenden** Cue („wenn das nächste GO kommt, mach das mit mir“).
- Springen/Suchleiste/„Von Anfang“ verändern nie die gespeicherten Einstellungen.
- UI: dunkles Design, große Touch-Ziele, Bildschirm bleibt im Show-Modus an, Wiedergabe läuft im Hintergrund weiter.
- Package-Name `audioshow`, Android-Application-ID `de.audioshow.app`.
- Code-Bezeichner Englisch, UI-Texte Deutsch.

## Review Focus

1. **Kaputte oder von Hand editierte `cues.json`** (ungültiges JSON, falsche Typen) → App stürzt nicht ab, die Datei gilt als leer; beim nächsten Speichern wird das Original als `cues.json.corrupt-<timestamp>` gesichert statt still überschrieben. → Test in Task 2.
2. **Müll vom USB-Stick / aus dem Dateimanager**: `._Jonglage.mp3` (macOS), `.DS_Store`, `.txt`, Großschreibung `SONG.MP3`, Umlaute/Leerzeichen in Namen → Nicht-Audio und Punkt-Dateien werden ignoriert, Endungen case-insensitiv erkannt, Namen unverändert angezeigt. → Test in Task 3.
3. **Dieselbe Datei zweimal in der Show / gleichzeitig laufend** → laufende Cues werden über eine eigene Instanz-ID unterschieden, nicht über den Pfad; Stop/Seek trifft nur die gemeinte Instanz. → Test in Task 5.
4. **GO am Ende der Liste oder wenn alle folgenden Dateien fehlen** → GO tut nichts (kein Absturz, laufende Playbacks bleiben unberührt), Anzeige „Ende der Show“. → Test in Task 5.
5. **Cue-Ordner nicht (mehr) vorhanden oder Berechtigung entzogen** → Archiv leer mit klarer Meldung und Weg zu den Einstellungen statt Absturz. → Test in Task 3 (Scanner) und Task 7 (UI-Hinweis).

---

## File Structure

```
lib/
  main.dart                         App-Start, Provider-Setup, Theme
  model/cue_settings.dart           CueSettings, GoBehavior, JSON
  model/show.dart                   Show (Name + Einträge)
  storage/cue_settings_store.dart   cues.json lesen/schreiben (atomar)
  storage/show_store.dart           _Shows/*.json, lastUsed
  storage/import_service.dart       Dateien in Künstler*innen-Ordner kopieren
  storage/app_settings.dart         AppSettings + SharedPreferences-Store
  library/library.dart              Library, Artist, AudioFileRef, LibraryScanner
  library/search.dart               normalizeForSearch, searchLibrary
  playback/audio_backend.dart       AudioBackend / AudioVoice (abstrakt)
  playback/just_audio_backend.dart  just_audio-Implementierung
  playback/show_engine.dart         ShowEngine, ResolvedCue, RunningCue
  ui/home_screen.dart               Shows-Übersicht, Navigation
  ui/settings_screen.dart           globale Einstellungen, Ordnerwahl, Berechtigung
  ui/library_pane.dart              Archiv mit Suche, Vorhören, Import
  ui/cue_settings_dialog.dart       Einstellungen einer Datei bearbeiten
  ui/show_editor_screen.dart        Archiv + Show nebeneinander, Drag & Drop
  ui/show_mode_screen.dart          GO, Stop All, Fades, laufende Cues, Suchleiste
test/
  (je eine *_test.dart pro lib-Datei mit Logik, Pfade gespiegelt)
  fakes/fake_audio_backend.dart
```

---

### Task 1: Flutter-SDK einrichten und Projekt anlegen

**Files:**
- Create: Flutter-Projekt im Repo-Root (`pubspec.yaml`, `lib/main.dart`, `android/…`, `test/widget_test.dart`)
- Modify: `.gitignore` (von `flutter create` erzeugt)

**Interfaces:**
- Produces: lauffähiges leeres Projekt `audioshow`, alle Abhängigkeiten aus dem Tech Stack in `pubspec.yaml`.

- [ ] **Step 1: SDK installieren** – `git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter`; `C:\src\flutter\bin` dauerhaft in den Benutzer-PATH aufnehmen (`[Environment]::SetEnvironmentVariable('Path', …, 'User')`). In VS Code ggf. `dart.flutterSdkPath` setzen, falls die Extension es nicht findet.
- [ ] **Step 2: Toolchain prüfen** – `flutter doctor -v`. Erwartet: Flutter ✓, Android toolchain ✓ (bei fehlenden cmdline-tools diese über den SDK-Manager nachinstallieren; `flutter doctor --android-licenses` akzeptieren). Windows/Chrome/Visual-Studio-Warnungen sind egal. Wenn das Gradle-JDK zu alt ist: `flutter config --jdk-dir` auf ein JDK 17+ setzen (z. B. Android Studio `jbr`).
- [ ] **Step 3: Projekt erzeugen** – im Repo-Root `flutter create --org de.audioshow --project-name audioshow --platforms android .`; Application-ID in `android/app/build.gradle(.kts)` auf `de.audioshow.app` setzen.
- [ ] **Step 4: Abhängigkeiten** – `flutter pub add just_audio audio_session permission_handler file_picker shared_preferences wakelock_plus flutter_foreground_task path provider` und `flutter pub add --dev fake_async`.
- [ ] **Step 5: Verifizieren** – `flutter test` → Default-Widget-Test PASS; `flutter build apk --debug` → `build/app/outputs/flutter-apk/app-debug.apk` existiert.
- [ ] **Step 6: Commit** – `git add -A && git commit -m "chore: scaffold Flutter project"`

---

### Task 2: CueSettings-Modell und `cues.json`-Store

**Files:**
- Create: `lib/model/cue_settings.dart`, `lib/storage/cue_settings_store.dart`
- Test: `test/model/cue_settings_test.dart`, `test/storage/cue_settings_store_test.dart`

**Interfaces:**
- Produces:
  - `enum GoBehavior { fadeOut, stop, keepRunning }` (JSON-Werte `"fadeOut"`, `"stop"`, `"keepRunning"`)
  - `class CueSettings { Duration startAt = 0; Duration? endAt; int volume = 100 /*0–100*/; Duration fadeIn = 0; GoBehavior? goBehavior; Duration? goFade; String note = ''; Map<String, dynamic> extra; }` – `const CueSettings()` = Standard, `copyWith(...)` (mit Möglichkeit, nullable Felder auf null zu setzen), `factory CueSettings.fromJson(Map<String, dynamic>)`, `Map<String, dynamic> toJson()` (nur Nicht-Standardwerte + `extra`), `bool get isDefault`.
  - `cues.json`-Format: `{"version": 1, "files": {"<Dateiname>": {"startAt": 12.5, "endAt": 180.0, "volume": 90, "fadeIn": 2.0, "goBehavior": "keepRunning", "goFade": 3.0, "note": "…"}}}` – Zeiten in Sekunden (double).
  - `class CueSettingsStore { Future<Map<String, CueSettings>> load(Directory artistDir); Future<void> save(Directory artistDir, String fileName, CueSettings settings); }`

- [ ] **Step 1: Failing tests schreiben**
  - `fromJson/toJson roundtrip keeps all fields` – alle Felder gesetzt, Roundtrip gleich.
  - `toJson omits defaults` – `const CueSettings().toJson()` ist `{}`.
  - `unknown keys survive roundtrip` – `{"startAt": 1, "color": "red"}` → `toJson()['color'] == 'red'`.
  - `wrong types fall back to defaults` – `{"startAt": "abc", "volume": "laut"}` → `startAt == Duration.zero`, `volume == 100`, kein Throw.
  - `load returns empty map when cues.json missing`.
  - `save creates cues.json and load returns it`.
  - `save preserves other files' entries and unknown top-level keys` – vorhandenes `{"version":1,"files":{"a.mp3":{"volume":50}},"foo":1}`; `save(dir,'b.mp3',…)` → `a.mp3` unverändert, `foo == 1`.
  - `save with default settings removes the entry`.
  - `corrupt cues.json: load returns empty, save backs it up` – Datei-Inhalt `{nope`; `load` → `{}`; nach `save` existiert genau eine `cues.json.corrupt-*` mit Inhalt `{nope`, und `cues.json` ist gültig.
  - `save leaves no temp file behind`.
- [ ] **Step 2: Tests laufen lassen** – `flutter test test/model test/storage/cue_settings_store_test.dart` → FAIL (nicht definiert).
- [ ] **Step 3: Implementieren** – `save` = lesen (oder bei Korruption sichern), Eintrag ersetzen, in `cues.json.tmp` schreiben, `rename` auf `cues.json`. Ein Schreibvorgang pro Ordner gleichzeitig (einfacher `Future`-Chain-Lock pro Pfad).
- [ ] **Step 4: Tests laufen lassen** → PASS.
- [ ] **Step 5: Commit** – `feat: cue settings model and cues.json store`

---

### Task 3: Library-Scanner und Suche

**Files:**
- Create: `lib/library/library.dart`, `lib/library/search.dart`
- Test: `test/library/library_test.dart`, `test/library/search_test.dart`

**Interfaces:**
- Produces:
  - `const audioExtensions = {'.mp3', '.wav', '.ogg', '.m4a', '.aac', '.flac'};`
  - `class AudioFileRef { final String artist; final String fileName; String get relPath => '$artist/$fileName'; }` (Wertgleichheit über `relPath`)
  - `class Artist { final String name; final List<AudioFileRef> files; }` (Dateien alphabetisch, case-insensitiv)
  - `class Library { final Directory? root; final List<Artist> artists; final String? error; List<AudioFileRef> get allFiles; File fileFor(AudioFileRef ref); Directory artistDir(String artist); static Library empty(String error); }`
  - `class LibraryScanner { Future<Library> scan(Directory root); }`
  - `String normalizeForSearch(String s)` und `List<AudioFileRef> searchLibrary(Library lib, String query)`

- [ ] **Step 1: Failing tests schreiben**
  - `scan lists artist folders and their audio files` – Temp-Root mit `Anna/Jonglage.mp3`, `Trio X/Intro.WAV` → 2 Artists, Dateien korrekt.
  - `scan ignores _Shows, dot-folders, dot-files, non-audio and nested folders` – `_Shows/x.json`, `.trash/a.mp3`, `Anna/._Jonglage.mp3`, `Anna/.DS_Store`, `Anna/notes.txt`, `Anna/sub/deep.mp3` → nur `Anna/Jonglage.mp3`.
  - `scan keeps umlauts and spaces in names` – `Jörg Müller/Fünf Bälle.mp3`.
  - `scan includes artists with no audio files` (leerer Ordner nach Import-Anlage sichtbar).
  - `scan of missing root returns empty library with error` – `error != null`, kein Throw.
  - `normalizeForSearch` – `'Jörg MÜLLER – Fünf'` → `'jorg muller – funf'`; `'ß'` → `'ss'`; `'é'` → `'e'`.
  - `search matches artist and file name, all terms required` – `'trio intro'` findet `Trio X/Intro.wav`, `'trio jonglage'` findet nichts.
  - `search ignores case and diacritics` – `'jorg'` findet `Jörg Müller/…`.
  - `empty query returns all files`.
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren** – Diakritika per fester Ersetzungstabelle (ä/ö/ü/ß/à/á/â/é/è/ê/ë/í/ì/î/ï/ó/ò/ô/õ/ú/ù/û/ñ/ç/å/ø + Großbuchstaben), kein extra Package. Suche: Begriffe an Leerzeichen trennen, jeder muss in `normalize("$artist $fileName")` enthalten sein; Reihenfolge wie `allFiles`.
- [ ] **Step 4: Tests laufen lassen** → PASS.
- [ ] **Step 5: Commit** – `feat: library scanner and search`

---

### Task 4: Shows, Show-Store und Import

**Files:**
- Create: `lib/model/show.dart`, `lib/storage/show_store.dart`, `lib/storage/import_service.dart`
- Test: `test/storage/show_store_test.dart`, `test/storage/import_service_test.dart`

**Interfaces:**
- Consumes: `AudioFileRef` (Task 3).
- Produces:
  - `class Show { final String name; final List<String> entries; /* relPaths */ }` + `copyWith`; JSON `{"version": 1, "entries": ["Anna/Jonglage.mp3", …]}`
  - `class ShowStore { ShowStore(Directory cueRoot); Future<List<String>> listNames(); /* neueste zuerst */ Future<Show> createForDate(DateTime date); Future<Show> load(String name); Future<void> save(Show show); Future<Show> duplicate(String sourceName, DateTime date); Future<void> delete(String name); Future<Map<String, DateTime>> lastUsed(); }`
  - `class ImportService { Future<List<AudioFileRef>> importFiles(Directory cueRoot, String artist, List<File> sources); String sanitizeArtistName(String raw); }`

- [ ] **Step 1: Failing tests schreiben**
  - `createForDate names show yyyy-MM-dd and creates _Shows` – `2026-11-23` → Name `2026-11-23`, Datei `_Shows/2026-11-23.json`.
  - `second show on same day gets -2, third -3`.
  - `save/load roundtrip keeps entry order and duplicates`.
  - `listNames newest first` – `2026-11-21`, `2026-11-23`, `2026-11-23-2` → `[2026-11-23-2, 2026-11-23, 2026-11-21]`.
  - `duplicate copies entries under new date name`.
  - `save is atomic (no .tmp left)`.
  - `load of corrupt show throws FormatException` (UI zeigt Fehler; nichts wird überschrieben).
  - `lastUsed maps relPath to newest show date` – Datum aus Namenspräfix `yyyy-MM-dd`; Shows ohne parsebares Datum werden ignoriert.
  - `import copies files into artist folder, creating it` – Rückgabe-Refs korrekt.
  - `import never overwrites: clash becomes "Name (2).mp3"`.
  - `sanitizeArtistName` – trimmt, ersetzt `/ \ : * ? " < > |` durch `_`, führendes `_`/`.` entfernt, leer → Fehler.
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren** – Schreiben wie in Task 2 (temp + rename).
- [ ] **Step 4: Tests laufen lassen** → PASS.
- [ ] **Step 5: Commit** – `feat: show store and file import`

---

### Task 5: Audio-Schnittstelle und ShowEngine

**Files:**
- Create: `lib/playback/audio_backend.dart`, `lib/playback/show_engine.dart`, `lib/storage/app_settings.dart`
- Test: `test/fakes/fake_audio_backend.dart`, `test/playback/show_engine_test.dart`, `test/storage/app_settings_test.dart`

**Interfaces:**
- Consumes: `CueSettings`, `GoBehavior` (Task 2).
- Produces:
  - ```dart
    abstract class AudioBackend { Future<AudioVoice> load(String path, {Duration initialPosition = Duration.zero}); }
    abstract class AudioVoice {
      Future<void> play(); Future<void> stop(); Future<void> dispose();
      Future<void> seek(Duration position); Future<void> setVolume(double v); // 0.0–1.0
      Duration get position; Duration? get duration;
      Stream<Duration> get positionStream; Stream<void> get completed;
    }
    ```
  - `class AppSettings { String? cueRoot; GoBehavior goBehavior = GoBehavior.fadeOut; Duration goFade = 1s; Duration fadeShort = 1s; Duration fadeLong = 5s; }` + `class AppSettingsStore { Future<AppSettings> load(); Future<void> save(AppSettings s); }` (SharedPreferences).
  - `class ResolvedCue { final String relPath; final String absPath; final CueSettings settings; final bool missing; }`
  - `class RunningCue { final int id; final int showIndex; final ResolvedCue cue; Duration get position; Duration? get duration; bool get fadingOut; }`
  - ```dart
    class ShowEngine extends ChangeNotifier {
      ShowEngine({required AudioBackend backend, required AppSettings settings});
      void setCues(List<ResolvedCue> cues);     // setzt nextIndex auf ersten nicht fehlenden Cue
      List<ResolvedCue> get cues; int? get nextIndex; List<RunningCue> get running;
      void select(int index);                   // macht Cue zum nächsten, startet nicht
      Future<void> go();
      Future<void> stopAll();
      Future<void> fadeAll(Duration d);         // ausblenden, dann stoppen
      Future<void> restart(RunningCue c);       // auf startAt; liegt Position schon < startAt+2s → auf 0
      Future<void> seek(RunningCue c, Duration absolutePosition);
      static const goLockout = Duration(milliseconds: 500);
    }
    ```
  - Positionen sind immer absolut in der Datei (kein Clipping), damit „starte bei 20 s“ der Zeit im Track entspricht.

- [ ] **Step 1: FakeAudioBackend schreiben** – zeichnet Aufrufe auf (`loadedPaths`, pro Voice `played`, `stopped`, `volumes`, `position`), Position und `completed` manuell steuerbar.
- [ ] **Step 2: Failing tests schreiben** (alle mit `fake_async`)
  - `go starts next cue at startAt with volume/100 and advances nextIndex` – `startAt 12s`, `volume 80` → `load(..., initialPosition: 12s)`, Endlautstärke `0.8`, `nextIndex == 1`.
  - `go with fadeIn ramps volume from 0 to target over fadeIn`.
  - `go applies running cue's own goBehavior (keepRunning) instead of global` – Cue A `keepRunning`, global `fadeOut`; GO auf B → A läuft weiter, nicht gestoppt.
  - `go with global fadeOut fades running cue over goFade then stops it` – nach 1 s `stopped == true`, Lautstärke vorher monoton fallend.
  - `go uses running cue's goFade override` – `goFade 3s` → nach 1 s noch nicht gestoppt, nach 3 s gestoppt.
  - `go with stop behavior stops running cue immediately`.
  - `second go within 500ms is ignored`.
  - `go skips missing cues` – `[A, B(missing), C]`: nach GO auf A ist `nextIndex == 2`.
  - `go at end of show does nothing and leaves running cues alone` – `nextIndex == null`, kein Load, laufender Cue unverändert.
  - `select changes next cue without starting it`.
  - `stopAll stops everything immediately and clears running`.
  - `fadeAll(5s) fades all running then stops`.
  - `endAt stops the cue when position reaches it`.
  - `completed removes cue from running`.
  - `same file twice can run concurrently and is stopped independently` – zwei RunningCues mit unterschiedlicher `id`; `seek` auf eine ändert nur deren Voice.
  - `restart seeks to startAt, second restart near startAt seeks to 0`.
  - `seek does not change cue settings` – `cues[i].settings` identisch vor/nach.
  - `next cue is preloaded` – nach `setCues` ist der Pfad des nächsten Cues bereits geladen; `go` lädt nicht erneut.
  - `AppSettingsStore roundtrip` (mit `SharedPreferences.setMockInitialValues({})`).
- [ ] **Step 3: Tests laufen lassen** → FAIL.
- [ ] **Step 4: Implementieren** – Lautstärke einer Voice = `settings.volume / 100 * fadeFactor`; Fades als `Timer.periodic(20ms)` linear; ein laufender Fade wird von `stopAll` abgebrochen. Preload: nach jeder Änderung von `nextIndex` die Voice des nächsten Cues laden (vorherige Preload-Voice verwerfen, wenn sich das Ziel ändert). Laufende Cues bekommen eine fortlaufende `id`.
- [ ] **Step 5: Tests laufen lassen** → PASS.
- [ ] **Step 6: Commit** – `feat: show engine with GO behaviors and fades`

---

### Task 6: just_audio-Backend und Android-Konfiguration

**Files:**
- Create: `lib/playback/just_audio_backend.dart`
- Modify: `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle(.kts)` (minSdk 24)

**Interfaces:**
- Consumes: `AudioBackend`, `AudioVoice` (Task 5).
- Produces: `class JustAudioBackend implements AudioBackend` (eine `AudioPlayer`-Instanz pro Voice, `setFilePath(path, initialPosition:)`); `Future<void> configureAudioSession()` (Kategorie Musik, kein Ducking anderer Apps nötig).

- [ ] **Step 1: Implementieren** – `completed` aus `processingStateStream == completed`; `dispose` gibt den Player frei.
- [ ] **Step 2: Manifest** – Permissions `MANAGE_EXTERNAL_STORAGE`, `READ_EXTERNAL_STORAGE` (maxSdkVersion 32), `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`; Service-Eintrag für `flutter_foreground_task` mit `foregroundServiceType="mediaPlayback"`; `android:requestLegacyExternalStorage="true"`.
- [ ] **Step 3: Verifizieren** – `flutter analyze` ohne Fehler; `flutter test` PASS; `flutter build apk --debug` erfolgreich.
- [ ] **Step 4: Commit** – `feat: just_audio backend and Android permissions`

---

### Task 7: App-Shell, Einstellungen, Berechtigung, Ordnerwahl

**Files:**
- Create: `lib/ui/home_screen.dart`, `lib/ui/settings_screen.dart`
- Modify: `lib/main.dart`
- Test: `test/ui/home_screen_test.dart`

**Interfaces:**
- Consumes: `AppSettingsStore`, `ShowStore`, `LibraryScanner`, `ShowEngine`, `JustAudioBackend`.
- Produces: `class AppState extends ChangeNotifier` in `lib/main.dart` (oder eigene Datei) mit `AppSettings settings`, `Library library`, `Future<void> rescan()`, `Future<void> updateSettings(AppSettings)`, `ShowStore? showStore`; per `ChangeNotifierProvider` bereitgestellt.

- [ ] **Step 1: Failing Widget-Tests**
  - `without cue folder, home shows prompt to choose folder` – Text „Cue-Ordner wählen“ sichtbar.
  - `with library error, home shows error message and settings button` (Review Focus 5).
  - `home lists show names newest first and has "Neue Show"`.
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren**
  - Dunkles `ThemeData` (Material 3, `Brightness.dark`), Mindest-Touch-Ziel 56 dp.
  - Beim Start: Settings laden; fehlt „Zugriff auf alle Dateien“ (`Permission.manageExternalStorage`), Hinweis mit Knopf, der die Systemeinstellung öffnet.
  - Einstellungen: Cue-Ordner (`FilePicker.platform.getDirectoryPath()`, Vorschlag `/storage/emulated/0/Cues`, Ordner bei Bedarf anlegen), GO-Verhalten (3 Optionen) + Ausblendzeit, Dauer Fade kurz/lang.
  - Home: Liste der Shows (öffnen, duplizieren für heute, löschen mit Bestätigung), „Neue Show“ für heute.
- [ ] **Step 4: Tests laufen lassen** → PASS.
- [ ] **Step 5: Commit** – `feat: app shell, settings and permissions`

---

### Task 8: Archiv-Ansicht, Cue-Einstellungen, Import

**Files:**
- Create: `lib/ui/library_pane.dart`, `lib/ui/cue_settings_dialog.dart`
- Test: `test/ui/library_pane_test.dart`

**Interfaces:**
- Consumes: `Library`, `searchLibrary`, `CueSettingsStore`, `ImportService`, `ShowStore.lastUsed`.
- Produces: `class LibraryPane extends StatelessWidget { LibraryPane({required void Function(AudioFileRef) onAdd}); }`; `Future<CueSettings?> showCueSettingsDialog(BuildContext, AudioFileRef, CueSettings current)`.

- [ ] **Step 1: Failing Widget-Tests**
  - `typing in search filters files live` – „trio“ → nur Trio-X-Dateien sichtbar.
  - `without query shows artists collapsed, tap expands`.
  - `sort toggle switches between A–Z and zuletzt verwendet`.
  - `add button calls onAdd with the file ref`.
  - `cue settings dialog returns edited startAt and volume`.
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren**
  - Suchfeld oben, Ergebnisliste flach mit „Künstler\*in – Datei“; ohne Suche aufklappbare Artists. Pro Datei: Dauer (lazy via just_audio, gecacht), gesetzte Startzeit, Vorhören-Knopf (spielt ab `startAt`, erneutes Tippen stoppt), Einstellungen-Knopf, Hinzufügen-Knopf.
  - Einstellungsdialog: Startzeit / Endzeit (Eingabe `m:ss` oder Sekunden), Lautstärke-Slider 0–100 %, Fade-in, GO-Verhalten „Standard / Ausblenden / Stoppen / Weiterlaufen“ + Ausblendzeit, Notiz. Speichern → `CueSettingsStore.save`.
  - Import-Knopf: `FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.audio)`, Ziel-Künstler\*in aus Liste wählen oder neu eingeben, `ImportService.importFiles`, danach `rescan()`.
  - Aktualisieren-Knopf → `rescan()`.
- [ ] **Step 4: Tests laufen lassen** → PASS.
- [ ] **Step 5: Commit** – `feat: library pane with search, cue settings and import`

---

### Task 9: Show-Editor

**Files:**
- Create: `lib/ui/show_editor_screen.dart`
- Test: `test/ui/show_editor_screen_test.dart`

**Interfaces:**
- Consumes: `LibraryPane`, `ShowStore`, `Show`, `Library`, `CueSettingsStore`, `showCueSettingsDialog`.
- Produces: `class ShowEditorScreen extends StatefulWidget { ShowEditorScreen({required String showName}); }`; Knopf „Show starten“ navigiert zu `ShowModeScreen(showName:)` (Task 10).

- [ ] **Step 1: Failing Widget-Tests**
  - `adding from library appends entry and saves show`.
  - `reorder by drag updates order and saves`.
  - `remove entry saves show`.
  - `missing file is shown with warning marker` – Eintrag `Clara/Tuch.mp3` ohne Datei → Warnsymbol + „fehlt“.
  - `entry shows startAt from cues.json`.
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren** – Querformat: `LibraryPane` links (~40 %), `ReorderableListView` der Show rechts; jede Änderung sofort speichern. Eintrag tippen → Cue-Einstellungsdialog (schreibt `cues.json`). Hochformat: Archiv als Bottom-Sheet.
- [ ] **Step 4: Tests laufen lassen** → PASS.
- [ ] **Step 5: Commit** – `feat: show editor`

---

### Task 10: Show-Modus

**Files:**
- Create: `lib/ui/show_mode_screen.dart`
- Test: `test/ui/show_mode_screen_test.dart`

**Interfaces:**
- Consumes: `ShowEngine`, `ResolvedCue` (aus `Show` + `Library` + `CueSettingsStore` aufgelöst), `AppSettings`, `FakeAudioBackend` im Test.
- Produces: `class ShowModeScreen extends StatefulWidget { ShowModeScreen({required String showName}); }`

- [ ] **Step 1: Failing Widget-Tests**
  - `GO button starts next cue and marks following as NÄCHSTER`.
  - `tapping a cue selects it as next without starting`.
  - `STOP ALL stops all running`.
  - `Fade 1s / Fade 5s buttons call fadeAll with configured durations`.
  - `each running cue has its own row with seek bar and Von Anfang` – zwei laufende → zwei Zeilen.
  - `tap on seek bar without drag does not seek; drag does`.
  - `editing is not possible in show mode` – kein Reorder-Handle, kein Einstellungsdialog bei Tippen.
  - `end of show shows "Ende der Show" and GO is disabled`.
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren** – Layout wie Spec-Mockup: oben Zeilen der laufenden Cues (Name, Suchleiste mit absoluter Position/Restzeit, „Von Anfang“), Mitte Cue-Liste (gespielt ✓ / läuft / NÄCHSTER hervorgehoben, Notiz klein darunter, auto-scroll zum nächsten), unten Leiste: `Fade 1s`, `Fade 5s`, `STOP ALL` (rot), `GO` (groß, grün, rechts, ≥ 120 dp hoch). Suchleiste: Seek erst bei `onChangeEnd` nach Ziehen. Beim Betreten: `WakelockPlus.enable()` und Foreground-Service starten (Notification „Show läuft“), beim Verlassen beides beenden und `stopAll` nach Bestätigungsdialog, wenn noch etwas läuft. Zurück-Geste bei laufendem Playback nur nach Bestätigung.
- [ ] **Step 4: Tests laufen lassen** → PASS.
- [ ] **Step 5: Commit** – `feat: show mode`

---

### Task 11: Release-Build und Praxistest auf dem Tablet

**Files:**
- Modify: `android/app/build.gradle(.kts)` (Release mit Debug-Keystore signieren genügt für Sideload), `README.md` (Installation, Ordnerstruktur, Bedienung – kurz)

- [ ] **Step 1: Build** – `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`.
- [ ] **Step 2: Installieren** – Tablet per USB mit Entwickleroptionen/USB-Debugging: `flutter install` oder `adb install -r …apk`.
- [ ] **Step 3: Manuelle Checkliste auf dem Tablet** (Ergebnis im Commit-Text notieren)
  - Zugriff-auf-alle-Dateien erteilen, Cue-Ordner wählen, 3 Künstler\*innen-Ordner mit MP3/WAV werden angezeigt.
  - Import vom USB-Stick in neue\*n Künstler\*in.
  - Suche findet Dateien mit Umlauten.
  - Startzeit setzen → `cues.json` im Ordner enthält sie; nach App-Neustart noch da.
  - Show anlegen, sortieren, starten; GO reagiert ohne hörbare Verzögerung; GO-Ausblenden, Weiterlaufen-Cue, Stop All, Fade 1 s/5 s.
  - Suchleiste springt, „Von Anfang“ funktioniert, gespeicherte Startzeit bleibt unverändert.
  - Bildschirm sperren während Playback → läuft weiter.
- [ ] **Step 4: Commit** – `chore: release build and README`
