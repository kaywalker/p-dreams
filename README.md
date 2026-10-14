# LIFTOFF – ein Flipper für den Gaming-Table

Ein Flipper-Spiel in **Godot 4.7**, inspiriert von *Pinball Dreams* (Digital Illusions, 1992):
Dot-Matrix-Anzeige über dem Tisch, Bonus-Multiplikator über die oberen Rollover-Bahnen,
Rampe, Jackpot-Loch, Drop-Targets und eine Chiptune-Schleife – alles prozedural erzeugt,
ohne externe Grafik- oder Audiodateien.

## Starten

1. Godot 4.7 (Standard-Version, nicht .NET) installieren – <https://godotengine.org/download>
2. Projekt öffnen (`project.godot`) und mit F5 starten.

Das Spiel startet im Vollbild. Kommandozeilen-Optionen (nach `--`):

| Option | Wirkung |
| --- | --- |
| `--windowed` | im Fenster statt im Vollbild starten |
| `--rotation=0/90/180/270` | Ausrichtung des Tisches (sonst gespeicherte Einstellung, Standard 90°) |
| `--no-music` | ohne Musik |
| `--autoplay` | ein Bot spielt (Test/Demo) |
| `--screenshot=datei.png` | nach einigen Frames Screenshot speichern und beenden |

Beispiel: `godot --path . -- --windowed --rotation=0`

## Gaming-Table

* **Ausrichtung:** Der hochkant gebaute Tisch wird gedreht und skaliert, damit er die lange Seite des
  Displays ausfüllt. Im Startbildschirm über *„Ansicht drehen“* (oder Taste **R**) in 90°-Schritten
  drehen, bis der Tisch zur Spielerposition zeigt. Die Einstellung wird gespeichert.
* **Touch:** linke Hälfte des Spielfelds = linker Flipper, rechte Hälfte = rechter Flipper.
  Liegt der Ball im Abschusskanal, spannt Gedrückthalten rechts den Plunger, Loslassen schießt ab.
  Multitouch wird unterstützt (beide Flipper gleichzeitig).
* **Spielerzahl:** 1–4 Spieler über die Touch-Buttons im Startbildschirm, abwechselnd je 3 Bälle.

## Tastatur

| Taste | Funktion |
| --- | --- |
| Linke Shift / A / ← / Y | linker Flipper |
| Rechte Shift / L / → | rechter Flipper |
| Leertaste / ↓ / Enter | Plunger (halten = spannen) bzw. Start im Menü |
| 1–4 | Spiel mit 1–4 Spielern starten |
| N | Rütteln (Nudge) |
| P | Pause |
| R | Ansicht drehen |
| M | Musik an/aus |
| F11 | Vollbild umschalten |
| Esc | Spiel abbrechen / im Menü: beenden |

## Regeln

| Ziel | Punkte / Effekt |
| --- | --- |
| Pop-Bumper | 1.000 |
| Slingshots | 250 |
| Obere STAR-Bahnen (mit den Flippern durchschaltbar) | alle drei: Bonus-Multiplikator +1 (bis 5X) |
| Rampe | 10.000 × Treibstoffstufe; drei Rampen = **Jackpot bereit** |
| Hyperspace-Loch | bei bereitem Jackpot: **LIFTOFF-Jackpot** (100.000, steigt um 50.000) |
| Drop-Targets (alle 3) | 25.000 und **Extra Ball** leuchtet am Hyperspace-Loch |
| Orbit (linke Umlaufbahn) | 5.000, direkt nach einer Rampe 25.000 |
| Ballretter | 10 s nach dem ersten Abschuss wird ein verlorener Ball zurückgegeben |

Am Ende jedes Balls wird der Bonus × Multiplikator gutgeschrieben. Die Top-5-Punktzahlen werden
gespeichert und im Startbildschirm angezeigt.

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `scripts/main.gd` | Spielablauf, Regeln, Eingabe, Drehung/Skalierung, Highscores |
| `scripts/table.gd` | Tisch-Geometrie, eigene Ball-Physik mit 8 Substeps, Zeichnung |
| `scripts/dmd.gd` | 128×32-Dot-Matrix-Anzeige mit 5×7-Pixelschrift |
| `scripts/sfx.gd` | prozedurale Soundeffekte und Musik |

Die Physik ist bewusst selbst geschrieben statt mit `RigidBody2D`: Bei 120 Physik-Ticks × 8 Substeps
bewegt sich der Ball pro Schritt höchstens ~4 Einheiten (Ballradius 14), dadurch tunnelt er auch bei
Höchstgeschwindigkeit nicht durch Flipper oder Wände.

## Testen ohne Bildschirm

```sh
godot --headless --path . --fixed-fps 120 --quit-after 36000 -- --autoplay
```

Der Bot spielt 5 Minuten Spielzeit und gibt am Ende eine Ereignis-Statistik aus. Mit der
Umgebungsvariable `PB_TRACE=1` wird zusätzlich jede halbe Sekunde die Ballposition protokolliert.

## Export für den Tisch

In Godot unter *Projekt → Exportieren* eine Vorlage für das Betriebssystem des Gaming-Tables
(Windows, Linux oder Android) anlegen; dafür werden die Export-Templates für 4.7 benötigt.
