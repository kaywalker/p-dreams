# LIFTOFF – ein Flipper für den Gaming-Table

Ein moderner 3D-Flipper in **Godot 4.7**, ursprünglich inspiriert von *Pinball Dreams* (1992), im Aufbau
aber an aktuellen Tischen orientiert: zwei Rampen mit Drahtbahn-Rückläufen, ein dritter (oberer) Flipper,
Orbit mit Spinner, Scoop mit Up-Kicker und Raketen-Toy, Drop- und Standup-Targets, RGB-Pfeile vor jedem
Schuss, Multiball mit Jackpots, Missionen, Combos und ein animiertes Farb-Display. Grafik, Sound und Musik
werden komplett im Code erzeugt – es gibt keine externen Asset-Dateien.

## Starten

1. Godot 4.7 (Standard-Version, nicht .NET) installieren – <https://godotengine.org/download>
2. Projekt öffnen (`project.godot`) und mit F5 starten.

Das Spiel startet im Vollbild. Kommandozeilen-Optionen (nach `--`):

| Option | Wirkung |
| --- | --- |
| `--windowed` | im Fenster statt im Vollbild starten |
| `--rotation=0/90/180/270` | Ausrichtung des Tisches (sonst gespeicherte Einstellung, Standard 90°) |
| `--no-music` | ohne Musik |
| `--low` | geringere Grafikqualität für schwache Hardware |
| `--autoplay` | ein Bot spielt (Test/Demo) |
| `--screenshot=datei.png` | nach einigen Frames Screenshot speichern und beenden |

Beispiel: `godot --path . -- --windowed --rotation=0`

## Gaming-Table

* **Ausrichtung:** Der hochkant gebaute Tisch wird gedreht und skaliert, damit er die lange Seite des
  Displays ausfüllt. Im Startbildschirm über *„Ansicht drehen“* (oder Taste **R**) in 90°-Schritten
  drehen, bis der Tisch zur Spielerposition zeigt. Die Einstellung wird gespeichert.
* **Touch:** linke Hälfte des Spielfelds = linker Flipper, rechte Hälfte = rechter und oberer Flipper.
  Liegt der Ball im Abschusskanal, spannt Gedrückthalten rechts den Plunger, Loslassen schießt ab.
  Multitouch wird unterstützt (beide Flipper gleichzeitig).
* **Spielerzahl:** 1–4 Spieler über die Touch-Buttons im Startbildschirm, abwechselnd je 3 Bälle.

## Tastatur

| Taste | Funktion |
| --- | --- |
| Linke Shift / A / ← / Y | linker Flipper |
| Rechte Shift / L / → | rechter und oberer Flipper |
| Leertaste / ↓ / Enter | Plunger (halten = spannen) bzw. Start im Menü |
| 1–4 | Spiel mit 1–4 Spielern starten |
| N / ↑ | Rütteln (Nudge, Vorsicht: Tilt) |
| P | Pause |
| R | Ansicht drehen |
| M | Musik an/aus |
| F11 | Vollbild umschalten |
| Esc | Spiel abbrechen / im Menü: beenden |

## Das Spielfeld

| Schuss | Was passiert |
| --- | --- |
| **Linker Orbit** (mit Spinner) | Ball läuft über die Kuppel und kommt rechts zurück |
| **Linke Rampe** | Kunststofframpe, Drahtbahn bringt den Ball auf den **oberen Flipper** |
| **Drop-Targets** (schräge 3er-Bank) | alle drei = Mission leuchtet |
| **Launch Pad** (Scoop unter der Rakete) | Lock, Multiball-Start, Super Jackpot, Missionen, Extra Ball; der Up-Kicker schießt den Ball über eine Drahtbahn zurück in die Sky Lanes |
| **Stargate** (Standup-Tasche) | alle drei Standups = Jackpot-Wert +100.000, beim zweiten Mal Extra Ball |
| **Rechte Rampe** | Drahtbahn-Rücklauf in die linke Inlane |
| **Sky Lanes** (oben, 3 Stück) | per Flipper durchschaltbar, alle drei = Bonus-Multiplikator +1 und Kickback |
| **Pop-Bumper** | 1.000 (in der Mission „Meteor Storm“ 10.000) |

Die farbigen Pfeile vor den Hauptschüssen zeigen, was gerade lohnt (grün = Treibstoff, orange = Lock,
rot = Jackpot, lila = Mission, cyan = Combo).

## Regeln

* **Treibstoff & Multiball:** Drei Rampenschüsse lassen den Lock am Launch Pad leuchten. Zwei Locks starten
  einen **3-Ball-Multiball**: Jeder rote Pfeil ist ein Jackpot; sind alle fünf eingesammelt, gibt es am
  Launch Pad den **Super Jackpot** (4 × Jackpot-Wert).
* **Missionen** (30 s, Start am Launch Pad, nachdem die Drop-Targets komplett sind):
  *Meteor Storm* (Bumper 10.000), *Sternjagd* (lila Pfeile 50.000, wandern weiter), *Gravity* (Targets 25.000).
* **Combos:** zwei verschiedene Hauptschüsse innerhalb von 3 s, je Combo mehr Punkte. Linke Rampe →
  oberer Flipper → Launch Pad ist der **Upper Combo** (50.000).
* **Skill Shot:** Beim Abschuss blinkt eine Sky Lane; wer sie trifft, bekommt 75.000.
* **Kickback** in der linken Outlane, **Ballretter** 10 s nach dem Abschuss (15 s im Multiball).
* **Tilt:** Rütteln (Taste N) ist erlaubt, aber nach „DANGER“ folgt der Tilt – Flipper aus, kein Bonus.

Am Ende jedes Balls wird der Bonus × Multiplikator gutgeschrieben. Die Top-5-Punktzahlen werden
gespeichert und im Startbildschirm angezeigt.

## Aufbau

| Datei | Inhalt |
| --- | --- |
| `scripts/main.gd` | Spielablauf, Regeln, Eingabe, Drehung/Skalierung, Highscores |
| `scripts/physics.gd` | Tisch-Geometrie, eigene Ball-Physik (8 Substeps, Multiball), Rampen-/Drahtbahnen |
| `scripts/table_view.gd` | 3D-Darstellung: Gehäuse, Rampen, Bumper, Rakete, Licht, Lampen-Einsätze |
| `scripts/playfield_art.gd` | Spielfelddruck (wird einmal in eine Textur gerendert) |
| `scripts/layout.gd` | Positionen und Farben der Lampen-Einsätze |
| `scripts/display.gd` | animiertes Farb-Display |
| `scripts/sfx.gd` | prozedurale Soundeffekte und Musik |

Die Physik ist bewusst selbst geschrieben statt mit `RigidBody2D`: Bei 120 Physik-Ticks × 8 Substeps
bewegt sich der Ball pro Schritt höchstens ~4 Einheiten (Ballradius 14), dadurch tunnelt er auch bei
Höchstgeschwindigkeit nicht durch Flipper oder Wände. Die 3D-Ansicht liest den Physik-Zustand nur aus;
die Kamera schaut senkrecht von oben, so wie man auf einen Gaming-Table blickt.

Für schwächere Hardware gibt es `--low` (ohne MSAA, geringere 3D-Auflösung).

## Testen ohne Bildschirm

```sh
godot --headless --path . --fixed-fps 120 --quit-after 36000 -- --autoplay
```

Der Bot spielt 5 Minuten Spielzeit und gibt am Ende eine Ereignis-Statistik aus. Mit der
Umgebungsvariable `PB_TRACE=1` wird zusätzlich jede halbe Sekunde die Ballposition protokolliert.

## Export für den Tisch

In Godot unter *Projekt → Exportieren* eine Vorlage für das Betriebssystem des Gaming-Tables
(Windows, Linux oder Android) anlegen; dafür werden die Export-Templates für 4.7 benötigt.
