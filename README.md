# AudioShow

Private GO-Button-App für Android-Tablets: Playbacks aus einem nach Künstler\*innen sortierten Cue-Ordner suchen, pro Abend zu einer Show zusammenstellen und per **GO / STOP ALL / Fade** abfahren.

Design: [docs/superpowers/specs/2026-11-23-audioshow-design.md](docs/superpowers/specs/2026-11-23-audioshow-design.md)

## Ordnerstruktur auf dem Tablet

```
Cues/
├─ Anna Beispiel/        ← ein Ordner pro Künstler*in
│   ├─ Jonglage.mp3
│   └─ cues.json         ← Startzeit, Lautstärke, Notiz … pro Datei
└─ _Shows/               ← gespeicherte Abende (2026-11-23.json …)
```

Neue Dateien entweder per **Importieren** in der App (Datei wählen → Künstler\*in wählen/neu) oder per Dateimanager in den passenden Ordner kopieren und **Ordner neu einlesen**.

## Bedienung

- **Start:** „Zugriff auf alle Dateien“ erlauben, in den Einstellungen den Cue-Ordner wählen (Vorschlag `/storage/emulated/0/Cues`).
- **Neue Show:** legt die Show für heute an und öffnet sie. Es gibt nur **eine Ansicht** – oben rechts der Schalter **Bearbeiten**:
  - **Bearbeiten an:** links das Archiv mit Suche (Hinzufügen per +), pro Cue Einstellungen (⚙), Entfernen und Ziehgriff zum Umsortieren. GO & Co. sind etwas kleiner, funktionieren aber weiter – die Show kann beim Bearbeiten laufen.
  - **Bearbeiten aus:** nur Liste und große Knöpfe; Reihenfolge und Einstellungen sind gegen Fehlberührung gesperrt.
- **Fahren (in beiden Modi):** GO startet den markierten nächsten Cue. Cue antippen = als nächsten markieren. Laufende Playbacks oben mit Suchleiste (ziehen zum Springen) und „Von Anfang“ (zweimal = auf 0:00). Umsortieren oder Hinzufügen während der Show unterbricht nichts; der markierte nächste Cue bleibt derselbe.
- **GO-Verhalten** (Einstellungen): laufende Playbacks ausblenden (Standard 1 s), stoppen oder weiterlaufen lassen; pro Cue abweichend einstellbar („Bei nächstem GO“).

## Entwicklung

- Flutter-SDK: `D:\dev\flutter` (im Benutzer-PATH), Caches: `GRADLE_USER_HOME=D:\dev\gradle`, `PUB_CACHE=D:\dev\pub-cache`.
- Tests: `flutter test`
- Installieren aufs Tablet (USB-Debugging an): `flutter build apk --release` und `flutter install --release`
