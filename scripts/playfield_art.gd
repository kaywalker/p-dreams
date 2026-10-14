extends Node2D
## Spielfeld-Druck: wird einmal in eine SubViewport-Textur gerendert und in
## der 3D-Ansicht auf Spielfeld und Apron gelegt (UV = Tischkoordinaten).

const Layout := preload("res://scripts/layout.gd")
const Phys := preload("res://scripts/physics.gd")

const W := 1000.0
const H := 1800.0

var font: Font
var bold: FontVariation


func _ready() -> void:
	font = ThemeDB.fallback_font
	bold = FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.9


func _text(pos: Vector2, s: String, size: int, col: Color, width := 400.0, f: Font = null) -> void:
	draw_string(f if f else bold, pos - Vector2(width * 0.5, 0), s, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)


func _gradient_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bottom, bottom]))


func _glow_circle(c: Vector2, r: float, col: Color, layers := 10) -> void:
	for i in layers:
		var f := 1.0 - float(i) / layers
		draw_circle(c, r * f, Color(col, col.a / layers * 0.8))


func _band(points: PackedVector2Array, col: Color, width: float) -> void:
	draw_polyline(points, Color(col, 0.10), width * 2.2, true)
	draw_polyline(points, Color(col, 0.22), width, true)
	draw_polyline(points, Color(col, 0.55), width * 0.18, true)


func _curve(a: Vector2, ctrl: Vector2, b: Vector2, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1992

	# Grund: tiefer Weltraum mit Farbverlauf.
	_gradient_rect(Rect2(0, 0, W, H * 0.5), Color(0.09, 0.03, 0.2), Color(0.03, 0.05, 0.16))
	_gradient_rect(Rect2(0, H * 0.5, W, H * 0.5), Color(0.03, 0.05, 0.16), Color(0.01, 0.06, 0.12))

	# Nebel.
	_glow_circle(Vector2(240, 420), 330, Color(0.75, 0.15, 0.85, 0.55), 16)
	_glow_circle(Vector2(720, 1060), 380, Color(0.1, 0.45, 1.0, 0.5), 16)
	_glow_circle(Vector2(330, 1220), 260, Color(1.0, 0.2, 0.45, 0.4), 14)
	_glow_circle(Vector2(560, 260), 260, Color(0.15, 0.8, 1.0, 0.35), 14)
	_glow_circle(Vector2(800, 520), 200, Color(1.0, 0.45, 0.1, 0.25), 12)

	# Sterne mit Glanz.
	for i in 420:
		var p := Vector2(rng.randf_range(0, W), rng.randf_range(0, H))
		var b := rng.randf_range(0.2, 1.0)
		var r := rng.randf_range(0.6, 2.0)
		draw_circle(p, r, Color(0.85, 0.9, 1.0, b))
		if b > 0.93:
			draw_line(p - Vector2(9, 0), p + Vector2(9, 0), Color(1, 1, 1, 0.5), 1.2)
			draw_line(p - Vector2(0, 9), p + Vector2(0, 9), Color(1, 1, 1, 0.5), 1.2)
			_glow_circle(p, 8, Color(0.7, 0.85, 1.0, 0.5), 5)

	# Synthwave-Gitter über den Flippern.
	var horizon := 1500.0
	for i in 15:
		var x := -300.0 + i * 110.0
		draw_line(Vector2(470 + (x - 470) * 0.15, horizon), Vector2(x, 1700), Color(1.0, 0.2, 0.8, 0.25), 2.0)
	for i in 8:
		var t := pow(float(i) / 7.0, 1.8)
		var y := lerpf(horizon, 1700, t)
		draw_line(Vector2(0, y), Vector2(W, y), Color(1.0, 0.2, 0.8, 0.12 + 0.2 * t), 2.0)
	_gradient_rect(Rect2(0, horizon - 40, W, 40), Color(1.0, 0.3, 0.7, 0.0), Color(1.0, 0.3, 0.7, 0.18))

	# Planet mit Ring.
	var pc := Vector2(250, 1150)
	_glow_circle(pc, 120, Color(0.9, 0.4, 1.0, 0.4), 10)
	draw_circle(pc, 78, Color(0.42, 0.18, 0.6))
	draw_circle(pc + Vector2(-14, -16), 62, Color(0.6, 0.3, 0.78))
	draw_circle(pc + Vector2(-28, -30), 30, Color(0.78, 0.5, 0.92, 0.6))
	for k in 3:
		draw_arc(pc, 108 + k * 8, 0.25, PI - 0.25, 48, Color(1.0, 0.75, 1.0, 0.45 - k * 0.1), 4.0, true)

	# Mond oben rechts.
	draw_circle(Vector2(790, 330), 42, Color(0.75, 0.78, 0.85))
	draw_circle(Vector2(775, 318), 12, Color(0.6, 0.62, 0.7))
	draw_circle(Vector2(805, 345), 8, Color(0.62, 0.64, 0.72))

	# Schusslinien (leuchtende Bahnen) von den Flippern zu den Schüssen.
	_band(_curve(Vector2(430, 1520), Vector2(560, 1250), Vector2(680, 1000)), Color(0.2, 1.0, 0.5), 30)
	_band(_curve(Vector2(510, 1520), Vector2(300, 1250), Vector2(206, 960)), Color(1.0, 0.3, 0.85), 30)
	_band(_curve(Vector2(500, 1520), Vector2(140, 1250), Vector2(76, 930)), Color(0.2, 0.9, 1.0), 26)
	_band(_curve(Vector2(470, 1520), Vector2(470, 1200), Vector2(470, 930)), Color(1.0, 0.75, 0.2), 26)
	_band(_curve(Vector2(780, 960), Vector2(600, 860), Vector2(420, 870)), Color(0.2, 0.95, 1.0), 18)

	# Launch-Pad-Gasse: Startrampe mit Warnstreifen.
	draw_rect(Rect2(434, 800, 72, 105), Color(0.08, 0.08, 0.12))
	for i in 7:
		var y := 830.0 + i * 12.0
		draw_line(Vector2(438, y), Vector2(502, y + 10), Color(1.0, 0.75, 0.1, 0.55), 5.0)
	var sp := Phys.SCOOP_POS
	draw_circle(sp, 22, Color(0.25, 0.25, 0.3))
	draw_circle(sp, 18, Color(0.0, 0.0, 0.0))

	# Stargate-Tasche hinter den Standups.
	_glow_circle(Vector2(575, 860), 70, Color(0.2, 0.95, 1.0, 0.45), 8)
	for k in 4:
		draw_arc(Vector2(575, 860), 20.0 + k * 13.0, 0, TAU, 40, Color(0.3, 0.95, 1.0, 0.5 - k * 0.1), 3.0, true)

	# Logo.
	_text(Vector2(472, 1252), "LIFTOFF", 56, Color(1.0, 0.25, 0.75, 0.5), 600)
	_text(Vector2(470, 1249), "LIFTOFF", 56, Color(1.0, 0.85, 0.3), 600)

	# Beschriftungen.
	_text(Vector2(470, 286), "SKY LANES", 20, Color(0.5, 1.0, 0.6, 0.9))
	_text(Vector2(75, 730), "SPIN", 13, Color(0.4, 0.95, 1.0, 0.8), 100)
	_text(Vector2(470, 1338), "BONUS MULTIPLIER", 13, Color(0.6, 0.8, 1.0, 0.8))
	_text(Vector2(470, 1075), "TREIBSTOFF", 12, Color(0.5, 1.0, 0.6, 0.8))
	_text(Vector2(470, 1130), "LOCK", 12, Color(1.0, 0.75, 0.3, 0.8))
	_text(Vector2(385, 905), "TARGETS", 13, Color(1.0, 0.8, 0.3, 0.8))

	# Fassungen der Einsätze.
	for ins in Layout.inserts():
		var p: Vector2 = ins["pos"]
		var s: float = ins["size"]
		var col: Color = ins["color"]
		_glow_circle(p, s * 2.4, Color(col, 0.35), 6)
		draw_circle(p, s + 4, Color(0.75, 0.78, 0.85))
		draw_circle(p, s + 2, Color(0.05, 0.05, 0.08))
		if ins.has("label"):
			_text(p + Vector2(0, s + 20), ins["label"], 13, Color(1, 1, 1, 0.85), 200)

	# Abschussrinne.
	draw_rect(Rect2(900, 500, 60, H - 500), Color(0.02, 0.02, 0.05))
	for i in 11:
		var y := 640.0 + i * 95.0
		draw_polyline(PackedVector2Array([Vector2(914, y), Vector2(930, y - 18), Vector2(946, y)]),
			Color(1.0, 0.65, 0.2, 0.5), 3.0)

	# Apron mit Regelkarten (liegt unter y = 1690).
	_gradient_rect(Rect2(0, 1688, W, H - 1688), Color(0.1, 0.1, 0.14), Color(0.05, 0.05, 0.08))
	draw_line(Vector2(0, 1690), Vector2(W, 1690), Color(0.8, 0.82, 0.9), 4.0)
	_card(Rect2(60, 1708, 320, 80), ["3 RAMPEN = LOCK AM LAUNCH PAD", "2 LOCKS = MULTIBALL",
		"ROTE PFEILE = JACKPOT"])
	_card(Rect2(560, 1708, 320, 80), ["DROP TARGETS = MISSION", "STARGATE = JACKPOT +100K",
		"LINKE RAMPE > OBERER FLIPPER"])


func _card(r: Rect2, lines: Array) -> void:
	draw_rect(r, Color(0.95, 0.92, 0.85))
	draw_rect(r.grow(-4), Color(0.12, 0.05, 0.22), false, 2.0)
	for i in lines.size():
		_text(Vector2(r.get_center().x, r.position.y + 24 + i * 22), lines[i], 13, Color(0.12, 0.05, 0.22),
			r.size.x)
