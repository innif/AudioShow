# Unified Show View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Editor und Show-Modus zu einer Ansicht mit Bearbeiten-Schalter zusammenführen; die Show bleibt beim Bearbeiten fahrbar.

**Architecture:** `ShowEngine` adressiert Einträge über stabile IDs (`ResolvedCue.id`) und bekommt `updateCues()`, das Status (nächster, gespielt, laufend, Vorladen) über Listenänderungen hinweg erhält. Eine neue `ShowScreen` ersetzt `ShowEditorScreen` und `ShowModeScreen`.

**Tech Stack:** wie bisher (Flutter 3.50 / `material_ui`, `just_audio`, `provider`, `fake_async`).

**Spec:** `docs/superpowers/specs/2026-11-23-unified-show-view-design.md` (ergänzt `2026-11-23-audioshow-design.md`)

## Global Constraints
- GO, STOP ALL, Fade, laufende Playbacks und „Cue antippen = nächster“ sind in beiden Modi vorhanden.
- Archiv, Einstellungen-Knopf, Ziehgriff, Entfernen nur im Bearbeiten-Modus.
- Bearbeiten stoppt oder lädt keine laufende Wiedergabe neu; jede Änderung wird sofort gespeichert.
- Ansicht öffnet im Bearbeiten-Modus.

## Review Focus
1. Umsortieren, während der nächste Cue vorgeladen ist → GO startet genau den markierten Eintrag. → Task 1
2. Dieselbe Datei zweimal in der Liste, eine davon wird verschoben/entfernt → Status hängt am richtigen Eintrag. → Task 1
3. Nächsten Cue entfernen → der Eintrag, der an seine Stelle rückt, wird nächster. → Task 1
4. Einstellungen des vorgeladenen nächsten Cues ändern (z. B. Startzeit) → GO nutzt die neue Startzeit. → Task 1
5. Hinzufügen während etwas läuft → läuft ungestört weiter. → Task 2

---

### Task 1: ShowEngine mit stabilen Eintrags-IDs und `updateCues`

**Files:** Modify `lib/playback/show_engine.dart`, `lib/app_state.dart` (`resolve`), `test/playback/show_engine_test.dart`, `test/app_state_test.dart`

**Interfaces:**
- `ResolvedCue` bekommt `final int id` (Konstruktor-Parameter `id`, Standard 0) und Wertgleichheit (`==`/`hashCode` über id, relPath, absPath, settings, missing).
- `RunningCue.showIndex` entfällt; stattdessen `RunningCue.cue.id`.
- `ShowEngine.played` → `Set<int>` von **IDs**.
- Neu: `void updateCues(List<ResolvedCue> cues)`; `int? get nextIndex` bleibt (aus nächster ID abgeleitet); `select(int index)` bleibt.
- `AppState.resolve(Show show, {List<int>? ids})` → setzt `ResolvedCue.id = ids[i]` (ohne `ids`: Index).

- [ ] **Step 1: Bestehende Engine-Tests auf IDs umstellen** (`r.showIndex` → `r.cue.id`; Test-Helfer `cue()` vergibt fortlaufende IDs ab 0 pro Test) und neue failing Tests:
  - `updateCues keeps next cue when reordered` – `[a,b,c]`, next=b(id1); update `[b,a,c]` → `nextIndex == 0`; GO startet b.
  - `updateCues keeps preload when next cue unchanged` – kein zusätzlicher Load nach Reorder.
  - `updateCues reloads preload when next cue settings change` – startAt 0→10 s → neuer Load mit `initialPosition 10s`, alter Preload disposed.
  - `removing next cue makes the entry at its position next` – `[a,b,c]` next=b; update `[a,c]` → `nextIndex == 1` (c).
  - `appending after end of show makes new entry next` – nach GO auf einzigen Cue `nextIndex == null`; update `[a, d]` → `nextIndex == 1`.
  - `removing a running cue keeps it playing` – update ohne den laufenden Eintrag → `running` unverändert, Voice nicht gestoppt.
  - `duplicate file entries are tracked by id` – `[a(id0), a(id1)]`, GO → played `{0}`; update `[a(id1), a(id0)]` → `nextIndex == 0` (id1).
  - `resolve assigns given ids` (AppState).
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren** – Engine speichert `_nextId` statt `_next`, Preload als `(_preloadId, _preloadCue)`; `_setNext` vergleicht Ziel-ID **und** `ResolvedCue`-Gleichheit, sonst Preload verwerfen/neu laden. `updateCues`: gespielte IDs auf vorhandene beschränken; nächster: alte ID vorhanden → behalten; sonst alte Position (geclamped) → erster abspielbarer ab dort; war `null` → erster abspielbarer Eintrag, dessen ID neu ist.
- [ ] **Step 4: Tests** → `flutter test test/playback test/app_state_test.dart` PASS.
- [ ] **Step 5: Commit** – `refactor: show engine tracks entries by stable id`

### Task 2: Eine ShowScreen mit Bearbeiten-Schalter

**Files:** Create `lib/ui/show_screen.dart`, `test/ui/show_screen_test.dart`; Delete `lib/ui/show_editor_screen.dart`, `lib/ui/show_mode_screen.dart`, deren Tests; Modify `lib/main.dart` (nur Route `/show` → `ShowScreen`), `lib/ui/home_screen.dart` falls nötig.

**Interfaces:** `class ShowScreen extends StatefulWidget { ShowScreen({required String showName, bool keepAwake = true}); }`. Schalter: `Switch` mit Key `editSwitch`, Label „Bearbeiten“. Pro Zeile im Bearbeiten-Modus: Tooltip „Einstellungen“, „Entfernen“, Ziehgriff Key `handle-<index>`.

- [ ] **Step 1: Failing Widget-Tests** (alle bisherigen Show-Modus- und Editor-Tests übernehmen, angepasst) plus:
  - `opens in edit mode with archive visible` – `librarySearch` sichtbar, Ziehgriffe sichtbar.
  - `edit switch off hides archive, handles, settings and remove`.
  - `GO and select work while editing` – im Bearbeiten-Modus Cue antippen → NÄCHSTER; GO startet ihn.
  - `tapping a cue never opens settings` – in beiden Modi.
  - `settings button opens cue settings in edit mode`.
  - `reorder while playing keeps running cue and next cue` – GO auf 1, dann Eintrag 3 nach oben ziehen → laufende Zeile bleibt, NÄCHSTER weiterhin derselbe Eintrag, Voice nicht gestoppt.
  - `adding while playing keeps playback and saves show`.
  - `controls are smaller in edit mode` – Höhe der GO-Schaltfläche im Bearbeiten-Modus < als ohne.
- [ ] **Step 2: Tests laufen lassen** → FAIL.
- [ ] **Step 3: Implementieren** – Zustand: `Show _show`, `List<int> _ids` parallel zu `entries` (neue IDs fortlaufend), eine `ShowEngine` für die Lebensdauer der Ansicht; jede Änderung: speichern → `resolve(show, ids:)` → `engine.updateCues`. Laden: `setCues`. Änderungen an Cue-Einstellungen (AppState notify) → neu auflösen + `updateCues`. Layout: AppBar mit Schalter; Bearbeiten an & breit: Archiv links (flex 2) | rechts laufende Zeilen + Liste + Steuerleiste (flex 3); schmal: Archiv als Bottom-Sheet-Knopf. Bearbeiten aus: volle Breite. Steuerleiste Höhe 120 (aus) / 72 (an). Vorschau stoppen beim Ausschalten des Bearbeiten-Modus und bei GO (`AppState.stopPreview`). Wakelock/Dienst/Verlassen-Bestätigung aus dem bisherigen Show-Modus übernehmen.
- [ ] **Step 4: Tests** → `flutter test` (gesamt) PASS, `flutter analyze` ohne Fehler.
- [ ] **Step 5: Commit** – `feat: single show view with edit switch`

### Task 3: Build und Installation
- [ ] `flutter build apk --release`, `flutter install -d <tablet> --release`; App startet ohne Fehler (logcat). README-Bedienung anpassen. Commit `docs: update README for unified show view`.
