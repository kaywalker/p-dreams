extends RefCounted
## Gemeinsame Layout-Daten für Spielfeld-Grafik (playfield_art.gd) und
## 3D-Ansicht (table_view.gd): Position, Form und Farbe der Lampen-Einsätze.

const GREEN := Color(0.25, 1.0, 0.45)
const BLUE := Color(0.25, 0.6, 1.0)
const RED := Color(1.0, 0.2, 0.25)
const AMBER := Color(1.0, 0.65, 0.12)
const MAGENTA := Color(1.0, 0.3, 0.85)
const CYAN := Color(0.2, 0.95, 1.0)
const WHITE := Color(1.0, 0.95, 0.85)

## Ausschnitt der 3D-Ansicht in Tischkoordinaten (inkl. Gehäuse).
const VIEW := Rect2(-70, -60, 1140, 1950)

## Die fünf Hauptschüsse mit ihrem Pfeil-Einsatz (RGB, Farbe setzt main.gd).
const SHOTS := {
	"lorb": {"pos": Vector2(75, 965), "name": "ORBIT"},
	"lramp": {"pos": Vector2(206, 1000), "name": "RAMPE L"},
	"scoop": {"pos": Vector2(470, 965), "name": "LAUNCH PAD"},
	"pocket": {"pos": Vector2(575, 880), "name": "STARGATE"},
	"rramp": {"pos": Vector2(680, 1050), "name": "RAMPE R"},
}


## Jeder Einsatz: key, pos, shape ("circle"/"arrow"/"rect"), size, color,
## angle (für Pfeile), text (auf dem Einsatz), label (darunter, auf dem Druck).
static func inserts() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key in SHOTS:
		out.append({"key": "shot_" + key, "pos": SHOTS[key]["pos"], "shape": "arrow", "size": 24.0,
			"color": WHITE, "angle": -PI / 2, "label": SHOTS[key]["name"], "rgb": true})
	for i in 3:
		out.append({"key": "lane%d" % i, "pos": Vector2(390 + 80 * i, 385), "shape": "circle",
			"size": 13.0, "color": GREEN, "text": ["S", "K", "Y"][i]})
	for i in 4:
		out.append({"key": "mult%d" % (i + 2), "pos": Vector2(380 + 60 * i, 1290), "shape": "circle",
			"size": 19.0, "color": BLUE, "text": "%dX" % (i + 2)})
	for i in 3:
		out.append({"key": "fuel%d" % i, "pos": Vector2(420 + 50 * i, 1045), "shape": "circle",
			"size": 13.0, "color": GREEN, "text": "F"})
	out.append({"key": "lock0", "pos": Vector2(440, 1095), "shape": "rect", "size": 18.0,
		"color": AMBER, "text": "L1"})
	out.append({"key": "lock1", "pos": Vector2(500, 1095), "shape": "rect", "size": 18.0,
		"color": AMBER, "text": "L2"})
	out.append({"key": "extra", "pos": Vector2(365, 1012), "shape": "circle", "size": 13.0,
		"color": AMBER, "label": "EXTRA BALL"})
	out.append({"key": "mission_lit", "pos": Vector2(300, 950), "shape": "rect", "size": 15.0,
		"color": MAGENTA, "label": "MISSION"})
	var modes := ["METEOR", "STERNJAGD", "GRAVITY"]
	for i in 3:
		out.append({"key": "mode%d" % i, "pos": Vector2(400 + 70 * i, 1150), "shape": "circle",
			"size": 12.0, "color": MAGENTA, "label": modes[i]})
	for i in 3:
		out.append({"key": "stand%d" % i, "pos": Vector2(535 + 36 * i, 830), "shape": "circle",
			"size": 9.0, "color": CYAN})
	out.append({"key": "kickback", "pos": Vector2(67, 1450), "shape": "circle", "size": 11.0,
		"color": RED, "label": "KICK"})
	out.append({"key": "special", "pos": Vector2(873, 1450), "shape": "circle", "size": 11.0,
		"color": RED})
	out.append({"key": "inlane0", "pos": Vector2(130, 1400), "shape": "circle", "size": 10.0,
		"color": GREEN})
	out.append({"key": "inlane1", "pos": Vector2(810, 1400), "shape": "circle", "size": 10.0,
		"color": GREEN})
	out.append({"key": "upper", "pos": Vector2(780, 1010), "shape": "arrow", "size": 15.0,
		"color": CYAN, "angle": -2.6})
	out.append({"key": "save", "pos": Vector2(470, 1668), "shape": "circle", "size": 15.0,
		"color": AMBER, "label": "SHOOT AGAIN"})
	return out
