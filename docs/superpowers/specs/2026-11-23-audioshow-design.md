# AudioShow – Design

Stand: 2026-11-23

## Worum es geht

Eine private Flutter-App für Android-Tablets, mit der Playbacks in einer Show per GO-Button abgefahren werden – eine Alternative zu *Audio Cues* (Radial Theater Project).

**Kontext:** Einsatz in einem Open-Stage-Varieté. Jeden Abend treten wechselnde Künstler\*innen auf, jede\*r bringt eigene Playbacks mit. Vor der Show werden die Playbacks in eine Reihenfolge gebracht, während der Show der Reihe nach abgefahren. Neue Dateien kommen per USB aufs Tablet; häufig sind sie aber schon vorhanden, weil die Person früher schon einmal da war.

**Warum nicht einfach Audio Cues:** Funktional ist Audio Cues fast perfekt. Das Problem ist das Datei-Management: Es gibt nur eine lange Liste ohne Suche, durch die man scrollen muss. Diese App löst genau das – Suche, Ordnung nach Künstler\*in, und Cue-Einstellungen (z. B. Startzeit), die an der Datei hängen bleiben und beim nächsten Besuch wieder da sind.

## Ziele

1. **Schnell einen Abend zusammenstellen:** Playbacks aus einem Archiv per Suche finden und in eine Show-Liste übernehmen.
2. **Einstellungen bleiben an der Datei:** Startzeit, Lautstärke usw. werden in einer Config-Datei im Künstler\*innen-Ordner gespeichert und gelten bei jeder künftigen Verwendung.
3. **Zuverlässiges Abfahren:** GO startet den nächsten Cue sofort; Stop All ist immer erreichbar.
4. **Eingreifen während der Show:** Zu einem beliebigen Cue springen; im laufenden Playback per Suchleiste an eine Stelle springen oder von vorn beginnen.

## Nicht-Ziele (v1)

- Fernsteuerung (Bluetooth-Remote, MIDI, OSC, Flic)
- Cloud-Import (Google Drive o. ä.) – Dateien kommen nur lokal (Tablet, USB)
- Bezahlmodell, Play-Store-Veröffentlichung, iOS
- Eigene Cue-Typen wie Fade-/Goto-/Pause-Cues; Fades passieren meist am Tonpult
- Auto-Follow-Ketten (Cue startet automatisch nach dem vorigen), Loops, Mehrkanal-/Output-Routing

## Anti-Ziele (wäre ein Fehlschlag, auch wenn es technisch läuft)

- GO reagiert spürbar verzögert oder löst versehentlich doppelt aus.
- Eine Fehlberührung während der Show verändert Einstellungen oder die Reihenfolge.
- Cue-Einstellungen gehen verloren oder werden durch ein Springen/„ab 20 s starten“ dauerhaft überschrieben.
- Das Archiv wird wieder zu einer langen Liste, durch die man scrollen muss.

## Rahmenbedingungen

- **Plattform:** Flutter, Android-Tablets (primär Querformat). Installation per APK/Sideload, nur für den Eigengebrauch.
- **Flutter-SDK** ist auf dem Entwicklungsrechner (Windows) noch nicht installiert.
- Audioformate: mindestens MP3 und WAV; zusätzlich was der Player unterstützt (OGG, M4A/AAC, FLAC).

## Ansätze (entschieden)

### Dateizugriff
- **Gewählt: Voller Dateizugriff (`MANAGE_EXTERNAL_STORAGE`, „Zugriff auf alle Dateien“) mit normalen Dateipfaden (`dart:io`).** Einfach und schnell: Ordner scannen, suchen, Config-Dateien schreiben, von USB kopieren.
- Verworfen: Storage Access Framework (Ordnerauswahl über Content-URIs). Play-Store-konform, aber umständlich (keine echten Pfade, langsameres Listing großer Ordner, mehr Fehlerquellen) – ohne Nutzen für eine private App.

### Audio-Wiedergabe
- **Gewählt: `just_audio` (ExoPlayer).** Bewährt; Seek, Clip (Start/Ende), Lautstärke, mehrere gleichzeitige Player. Der nächste Cue wird vorgeladen, damit GO ohne Verzögerung startet. Fades werden selbst über Lautstärke-Rampen umgesetzt.
- Verworfen: `flutter_soloud` – niedrigere Latenz und eingebaute Fades, aber jünger/weniger erprobt; der Präzisionsgewinn spielt bei Playbacks auf Knopfdruck kaum eine Rolle.

## Das Design

### Dateisystem

Ein **Cue-Ordner** wird einmalig in den Einstellungen gewählt (Standardvorschlag: `/storage/emulated/0/Cues`). Darin:

```
Cues/
├─ Anna Beispiel/            ← ein Ordner pro Künstler*in
│   ├─ Jonglage.mp3
│   └─ cues.json             ← Einstellungen der Playbacks in diesem Ordner
├─ Trio X/
│   ├─ Intro.wav
│   ├─ Hauptnummer.mp3
│   └─ cues.json
└─ _Shows/                   ← gespeicherte Show-Listen (Abende)
    ├─ 2026-11-21.json
    └─ 2026-11-23.json
```

- Künstler\*innen-Ordner = direkte Unterordner des Cue-Ordners (außer `_Shows` und andere mit `_` beginnende). Audiodateien direkt darin; tiefere Unterordner werden in v1 ignoriert *(Builder-Call, siehe unten)*.
- Alles (Audio, Einstellungen, Shows) liegt im Cue-Ordner → übersteht Neuinstallation der App und lässt sich als Ganzes kopieren/sichern.
- Dateien, die per Dateimanager in den Ordner gelegt werden, erscheinen nach erneutem Scan (beim App-Start, beim Öffnen des Archivs, per Aktualisieren).

### `cues.json` (pro Künstler\*innen-Ordner)

Einträge pro Dateiname. Fehlende Datei/fehlender Eintrag = Standardwerte. Felder:

- `startAt` – Startposition (Standard 0)
- `endAt` – optionales Ende
- `volume` – 0–100 % (Standard 100 %)
- `fadeIn` – optionale Einblendzeit
- `goBehavior` – optionale Abweichung vom globalen GO-Verhalten (siehe unten), inkl. Fade-Dauer
- `note` – Freitext-Notiz (z. B. „wartet auf Zeichen“)

Die App behält beim Schreiben unbekannte Felder bei und schreibt atomar (temporäre Datei + Umbenennen), damit nichts verloren geht. Wird eine Datei umbenannt/gelöscht, bleibt ihr Eintrag einfach ungenutzt.

### Archiv-Ansicht (Bibliothek)

- **Suchfeld** oben, durchsucht Künstler\*innen-Namen und Dateinamen gleichzeitig (Teilstring, Groß/Klein und Umlaute/Akzente egal), Ergebnisse live.
- Ohne Suche: Liste der Künstler\*innen (aufklappbar zu ihren Dateien). Sortierung alphabetisch oder „zuletzt verwendet“ *(„zuletzt verwendet“ wird aus den Show-Dateien abgeleitet)*.
- Pro Datei: Dauer, gesetzte Startzeit, Vorhören (kurz anspielen, über dieselbe Ausgabe).
- Antippen/Hinzufügen-Knopf → Datei wird ans Ende der aktuellen Show angehängt.
- **Importieren:** Dateien wählen (z. B. vom USB-Stick), Ziel-Künstler\*in wählen oder neu anlegen → Dateien werden in deren Ordner kopiert.
- Einstellungen einer Datei bearbeiten (schreibt `cues.json`).

### Show (ein Abend)

- Neue Show = neue Datei in `_Shows/` mit Datum als Namen (bei mehreren pro Tag Zusatz `-2` usw.). Frühere Shows lassen sich öffnen und als Vorlage duplizieren.
- Die Show ist eine geordnete Liste von Verweisen (relativer Pfad `Künstler*in/Datei`). Dieselbe Datei darf mehrfach vorkommen.
- **Die Einstellungen kommen immer aus `cues.json`**, nicht aus der Show. Wird im Show-Editor eine Einstellung geändert, wird sie in `cues.json` geschrieben und gilt künftig überall.
- Bearbeiten: Reihenfolge per Drag & Drop, Entfernen, Hinzufügen aus dem Archiv (Archiv und Show nebeneinander im Querformat).
- Fehlende Dateien (gelöscht/umbenannt) werden in der Liste deutlich markiert und beim GO übersprungen.

```
┌ Archiv ────────────────┐  ┌ Show 23.11. ─────────────────────┐
│ 🔍 such…               │  │ 1  Anna – Jonglage      ab 0:12  │
│ ▸ Anna Beispiel        │  │ 2  Trio X – Intro                │
│ ▸ Ben                  │→ │ 3  Ben – Handstand               │
│ ▾ Trio X               │  │ 4  ⚠ Clara – Tuch.mp3 (fehlt)    │
│    Intro.wav     2:31  │  │                                  │
│    Hauptnummer   4:05  │  │                                  │
└────────────────────────┘  └──────────────────────────────────┘
```

### Show-Modus (während der Vorstellung)

```
┌──────────────────────────────────────────────────────────────┐
│  ▶ 2 Trio X – Intro  ━━━━━━●━━━━━━  1:12 / 2:31  [⟲ Anfang]  │
│ ─────────────────────────────────────────────────────────────│
│    1 Anna – Jonglage                         ✓               │
│  ▷ 2 Trio X – Intro                          läuft            │
│  ● 3 Ben – Handstand                         NÄCHSTER         │
│    4 Clara – Tuch                                             │
│                                                              │
│ [Fade 1s] [Fade 5s]   [ STOP ALL ]        [     GO     ]     │
└──────────────────────────────────────────────────────────────┘
```

- **GO** (groß, unten rechts, mit dem Daumen erreichbar): startet den markierten nächsten Cue mit seinen Einstellungen; danach rückt die Markierung auf den folgenden Cue. Schutz gegen versehentliches Doppel-Auslösen (kurze Sperrzeit nach GO, genaue Dauer Builder-Call).
- **Stop All:** stoppt sofort alle laufenden Playbacks.
- **Fade 1 s / Fade 5 s:** blendet alle laufenden Playbacks über die Zeit aus und stoppt sie dann.
- **Springen:** Antippen eines Cues macht ihn zum nächsten (startet ihn nicht).
- **Laufende Cues:** Jedes laufende Playback bekommt oben eine eigene Zeile (meist nur eine) mit Position/Restzeit und einer **Suchleiste wie in Audio Cues**: Ziehen springt im laufenden Playback an die gewählte Stelle (z. B. „starte mal bei 20 s“). Dazu ein Knopf „Von Anfang“ (springt auf die gespeicherte Startzeit, bzw. auf 0 – siehe Builder-Calls). Diese Sprünge ändern **nicht** die gespeicherten Einstellungen. Eine Startzeit für einen noch nicht laufenden Cue einmalig festzulegen, ist **nicht** vorgesehen.
- Im Show-Modus sind Bearbeiten (Reihenfolge, Einstellungen) gesperrt; Wechsel zurück in den Editor über eine bewusste Aktion.
- Bildschirm bleibt an (Wakelock), dunkles Design.
- Wiedergabe läuft weiter, wenn die App in den Hintergrund geht oder der Bildschirm gesperrt wird.

### GO-Verhalten bei laufendem Playback

Globale Einstellung, pro Cue in `cues.json` überschreibbar. **Die Abweichung gehört zum laufenden Cue**: Sie bedeutet „wenn das nächste GO kommt, mach das mit *mir*“ (z. B. ein Intro mit „Weiterlaufen“ läuft unter der nächsten Nummer weiter). Bei einem GO wird also jedes laufende Playback nach seiner eigenen Einstellung behandelt (bzw. der globalen, wenn es keine hat).

- **Ausblenden** (Standard): laufende Playbacks werden über *X* s ausgeblendet (Standard 1 s) und gestoppt, der neue Cue startet sofort.
- **Stoppen:** laufende Playbacks stoppen sofort.
- **Weiterlaufen:** laufende Playbacks laufen parallel weiter.

### Einstellungen (global)

- Cue-Ordner
- GO-Verhalten + Ausblendzeit
- Dauer der Fade-Knöpfe (Standard 1 s und 5 s)

## Dem Builder überlassen

- Paketwahl jenseits von `just_audio` (State-Management, Dateiauswahl, Wakelock usw.), Projektstruktur, Mindest-Android-Version.
- Genaue Darstellung, Farben, Schriftgrößen – Hauptsache gut lesbar im Dunkeln und große Touch-Ziele.
- Format der Zeitfelder in `cues.json`.
- Schutz der Suchleiste vor versehentlichem Berühren (z. B. erst beim Ziehen, nicht beim bloßen Antippen springen).
- Umgang mit Unterordnern innerhalb eines Künstler\*innen-Ordners (v1: ignorieren).
- Ob „Von Anfang“ auf 0 oder auf `startAt` springt (Vorschlag: `startAt`, mit zweitem Tipp auf 0).
- Teststrategie.
