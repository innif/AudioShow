<div align="center">

# 🎭 AudioShow

**Die GO-Button-App für Varieté, Kleinkunst und offene Bühnen.**

Playbacks suchen, pro Abend zu einer Show zusammenstellen und mit einem großen **GO** abfahren – direkt vom Android-Tablet.

![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.14-0175C2?logo=dart&logoColor=white)
![Android](https://img.shields.io/badge/Android-7.0%2B-3DDC84?logo=android&logoColor=white)

</div>

---

## Worum geht's?

Bei Shows mit vielen wechselnden Künstler\*innen sammeln sich schnell Hunderte Playbacks an. AudioShow hält sie in einer einfachen Ordnerstruktur auf dem Tablet, findet jede Datei in Sekunden und macht aus ihnen eine Ablaufliste, die sich auch im dunklen Technikplatz sicher bedienen lässt.

- 🔍 **Schnelle Suche** über Künstler\*in und Dateiname – tolerant gegenüber Umlauten und Akzenten („jorg“ findet „Jörg“)
- 📋 **Show pro Abend** – Cues hinzufügen, per Drag & Drop umsortieren, automatisch gespeichert
- ▶️ **GO / STOP ALL / Fade** – große Knöpfe, gemacht für den Live-Betrieb
- 🎚️ **Einstellungen pro Datei** – Startzeit, Endzeit, Lautstärke, Fade-in, Notiz und eigenes GO-Verhalten
- 🔀 **Bearbeiten während der Show** – Umsortieren oder Hinzufügen unterbricht nichts, der nächste Cue bleibt markiert
- 🔒 **Schutz vor Fehlberührung** – außerhalb des Bearbeiten-Modus sind Reihenfolge und Einstellungen gesperrt
- 🔋 **Läuft zuverlässig weiter** – Bildschirm bleibt an, Wiedergabe läuft als Vordergrunddienst
- 💾 **Offene Dateiformate** – alles liegt als einfache Ordner und JSON-Dateien vor, ohne Datenbank und ohne Cloud

## Ordnerstruktur

Alles, was AudioShow braucht, liegt in einem frei wählbaren Cue-Ordner:

```
Cues/
├─ Anna Beispiel/        ← ein Ordner pro Künstler*in
│   ├─ Jonglage.mp3
│   ├─ Zugabe.wav
│   └─ cues.json         ← Einstellungen pro Datei
├─ Ben Muster/
│   └─ …
└─ _Shows/               ← gespeicherte Abende
    └─ 2026-11-23.json
```

Unterstützte Formate: `mp3`, `wav`, `ogg`, `m4a`, `aac`, `flac`.

Neue Dateien kommen entweder über **Importieren** in der App (Datei wählen → Künstler\*in wählen oder neu anlegen) in den Ordner oder werden per Dateimanager hineinkopiert. Danach **Ordner neu einlesen**.

<details>
<summary><b>Beispiel: <code>cues.json</code></b></summary>

```json
{
  "version": 1,
  "files": {
    "Jonglage.mp3": {
      "startAt": 2.5,
      "volume": 80,
      "fadeIn": 1.0,
      "goBehavior": "keepRunning",
      "note": "Erst starten, wenn das Licht aus ist"
    }
  }
}
```

Zeiten in Sekunden, Lautstärke in Prozent. Nicht gesetzte Werte verwenden die Standardeinstellungen. Unbekannte Felder bleiben beim Speichern erhalten.

</details>

## Bedienung

### Erster Start

1. Den Zugriff auf **alle Dateien** erlauben.
2. In den **Einstellungen** den Cue-Ordner wählen (Vorschlag: `/storage/emulated/0/Cues`).

### Show zusammenstellen

**Neue Show** legt die Show für den heutigen Tag an und öffnet sie. Beim nächsten Start der App wird die zuletzt geöffnete Show automatisch wieder geladen.

Es gibt nur **eine Ansicht**, oben rechts mit dem Schalter **Bearbeiten**:

| Modus | Was du siehst |
|---|---|
| **Bearbeiten an** | Links das Archiv mit Suche (Hinzufügen per **+**). Pro Cue: Einstellungen (⚙), Entfernen und ein Ziehgriff zum Umsortieren. Die Transportknöpfe sind etwas kleiner, funktionieren aber weiter: Die Show kann während des Bearbeitens laufen. |
| **Bearbeiten aus** | Nur die Ablaufliste und große Knöpfe. Reihenfolge und Einstellungen sind gesperrt. |

### Show fahren

- **GO** startet den markierten nächsten Cue.
- **Cue antippen** markiert ihn als nächsten.
- **Laufende Playbacks** erscheinen oben mit Fortschrittsleiste: Ziehen springt an eine Stelle, **Von Anfang** springt zum Startpunkt (zweimal tippen = auf 0:00).
- **STOP ALL** beendet sofort alles. Die beiden **Fade**-Knöpfe blenden alles aus, kurz oder lang (Standard 1 s und 5 s, in den Einstellungen änderbar).

### GO-Verhalten

Was mit laufenden Playbacks passiert, wenn GO gedrückt wird, ist in den Einstellungen festgelegt:

- **Ausblenden** (Standard, 1 s)
- **Stoppen**
- **Weiterlaufen lassen**

In den Cue-Einstellungen („Bei nächstem GO“) lässt sich das für jeden Cue einzeln anders einstellen, zum Beispiel für eine Hintergrundmusik, die unter dem nächsten Einspieler weiterlaufen soll.

## Installation

AudioShow wird aktuell aus dem Quellcode gebaut. Voraussetzungen:

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart ≥ 3.14)
- Android SDK und ein Android-Gerät ab Android 7.0 mit aktiviertem USB-Debugging

```bash
git clone https://github.com/innif/AudioShow.git
cd AudioShow
flutter pub get

# auf das angeschlossene Tablet installieren
flutter build apk --release
flutter install --release
```

## Entwicklung

```bash
flutter test      # alle Tests ausführen
flutter analyze   # statische Analyse
flutter run       # Debug-Build auf dem Gerät starten
```

### Projektstruktur

```
lib/
├─ library/    Cue-Ordner einlesen und durchsuchen
├─ model/      Show und Cue-Einstellungen
├─ playback/   Show-Engine, Audio-Backend, Vordergrunddienst
├─ storage/    Shows, cues.json, App-Einstellungen, Import
└─ ui/         Bildschirme und Widgets
test/          Unit- und Widget-Tests (inkl. Fake-Audio-Backend)
```

Die Wiedergabe läuft über eine austauschbare `AudioBackend`-Schnittstelle (produktiv mit [`just_audio`](https://pub.dev/packages/just_audio)). Dadurch lässt sich die komplette Show-Logik ohne echtes Audio testen. Dateien werden atomar geschrieben, damit eine Show auch bei einem Absturz mitten im Speichern nicht beschädigt wird.

## Mitmachen

Issues und Pull Requests sind willkommen. Vor einem PR bitte sicherstellen, dass `flutter analyze` und `flutter test` ohne Fehler durchlaufen.
