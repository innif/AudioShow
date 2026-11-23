# Eine Show-Ansicht mit Bearbeiten-Schalter – Design (kurz)

Stand: 2026-11-23 · Ergänzt `2026-11-23-audioshow-design.md`

## Warum
Während der Show müssen oft noch Cues hinzugefügt oder umsortiert werden. Getrennte Ansichten (Editor / Show-Modus) sind dafür zu starr. Show aufbauen und fahren wird eine Ansicht; ein **Bearbeiten-Schalter** blendet nur die Bearbeiten-Werkzeuge ein.

## Ziele
- Eine Ansicht pro Show. GO, STOP ALL, Fade-Knöpfe, laufende Playbacks (Suchleiste, „Von Anfang“) und **Cue antippen = als nächsten wählen** sind **immer** da – auch beim Bearbeiten, damit die Show weiterlaufen kann.
- Bearbeiten-Schalter (aus = gesperrt): nur wenn an, sind sichtbar
  - das Archiv (Suche, Vorhören, Import, Hinzufügen),
  - pro Cue ein **Einstellungen-Knopf** und ein **Ziehgriff** zum Umsortieren (plus Entfernen – *eigene Ergänzung*, sonst ließe sich ein falsch hinzugefügter Cue nicht loswerden).
- Beim Bearbeiten dürfen GO & Co. kleiner sein (Archiv braucht Platz).
- Änderungen wirken sofort auf die laufende Show und werden sofort gespeichert; laufende Playbacks laufen ungestört weiter.

## Nicht-Ziele / Anti-Ziele
- Kein Stoppen oder Neuladen der Wiedergabe durch Bearbeiten.
- Umsortieren darf nie dazu führen, dass ein anderer Cue als der markierte als nächster startet.
- Im ausgeschalteten Modus darf eine Fehlberührung nichts an Reihenfolge/Einstellungen ändern.

## Ansätze
- **Gewählt: Engine arbeitet mit festen Eintrags-IDs** statt Listenpositionen. „Nächster“, „gespielt“ und „läuft“ hängen an der ID, die Liste kann sich darunter beliebig ändern (`updateCues`).
- Verworfen: Indizes bei jeder Änderung umrechnen – fehleranfällig bei Verschieben/Entfernen/Duplikaten.
- Verworfen: Show-Modus bei Änderung neu laden – würde laufende Playbacks/Status verlieren.

## Verhalten (Calls)
- Umsortieren: der markierte nächste Cue bleibt derselbe Eintrag. Vorladen folgt ihm.
- Entfernen eines laufenden Cues: spielt zu Ende. Entfernen des nächsten: nächster wird der folgende abspielbare Eintrag an derselben Stelle.
- War die Show zu Ende (kein nächster) und es wird etwas angehängt: der neue Eintrag wird der nächste.
- Änderung von Cue-Einstellungen wirkt ab dem nächsten Start dieses Cues (laufende Instanz bleibt unverändert).
- Ansicht öffnet im Bearbeiten-Modus, wenn noch nichts gespielt wurde *(eigener Call)*; Schalter oben rechts.
- Hochformat/schmal: Archiv als Bottom-Sheet über einen Knopf (nur im Bearbeiten-Modus).
- Wakelock/Vordergrund-Dienst laufen, solange die Ansicht offen ist; Verlassen mit laufender Wiedergabe nur nach Bestätigung (wie bisher).

## Dem Builder überlassen
Genaue Größen der Knöpfe im Bearbeiten-Modus, Breitenaufteilung Archiv/Liste.
