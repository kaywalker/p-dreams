extends Node2D
## Spielfeld-Druck: wird einmal in eine SubViewport-Textur gerendert und in
## der 3D-Ansicht auf Spielfeld und Apron gelegt (UV = Tischkoordinaten).
##
## Motiv: Weltraum-Startplatz. Prozeduraler Nebel (Rauschtextur), Spiral-
## galaxie, Komet, Ringplanet, Asteroiden, Startrampe mit Rauch, Planeten-
## horizont über den Flippern und leuchtende Chevron-Bahnen zu den Schüssen.

const Layout := preload("res://scripts/layout.gd")
const Phys := preload("res://scripts/physics.gd")

const W := 1000.0
const H := 1800.0

var font: Font
var bold: FontVariation
var _nebula: ImageTexture
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	font = ThemeDB.fallback_font
	bold = FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.9
	_nebula = _make_nebula()


# ---------------------------------------------------------------- Helfer

func _text(pos: Vector2, s: String, size: int, col: Color, width := 400.0, f: Font = null) -> void:
	draw_string(f if f else bold, pos - Vector2(width * 0.5, 0), s, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)


func _label(pos: Vector2, s: String, size: int, col: Color) -> void:
	# Beschriftung mit dunkler Pille dahinter – auf buntem Grund gut lesbar.
	var w := bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + 14.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.0, 0.0, 0.05, 0.65)
	box.set_corner_radius_all(int(size * 0.7))
	draw_style_box(box, Rect2(pos.x - w * 0.5, pos.y - size * 0.95, w, size * 1.35))
	_text(pos, s, size, col, w + 20.0)


func _gradient_rect(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)]), PackedColorArray([top, top, bottom, bottom]))


func _glow_circle(c: Vector2, r: float, col: Color, layers := 10) -> void:
	for i in layers:
		var f := 1.0 - float(i) / layers
		draw_circle(c, r * f, Color(col, col.a / layers * 0.8))


func _curve(a: Vector2, ctrl: Vector2, b: Vector2, n := 32) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	return pts


func _ellipse(c: Vector2, rx: float, ry: float, rot: float, a0 := 0.0, a1 := TAU, n := 64) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


## Prozeduraler Nebel als Textur (Rauschen mit Domain Warping).
func _make_nebula() -> ImageTexture:
	var w := 250
	var h := 450
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n1 := FastNoiseLite.new()
	n1.seed = 7
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 0.011
	n1.fractal_type = FastNoiseLite.FRACTAL_FBM
	n1.fractal_octaves = 5
	n1.domain_warp_enabled = true
	n1.domain_warp_amplitude = 40.0
	n1.domain_warp_frequency = 0.008
	var n2 := FastNoiseLite.new()
	n2.seed = 99
	n2.frequency = 0.02
	n2.fractal_octaves = 4
	for y in h:
		var fy := float(y) / h
		var base := Color(0.025, 0.015, 0.09).lerp(Color(0.005, 0.03, 0.08), fy)
		for x in w:
			var fx := float(x) / w
			# Band wie die Milchstraße: von oben links nach unten rechts.
			var band := exp(-pow(fx - fy * 0.75 - 0.05, 2.0) / 0.06) * 0.85 + 0.25
			var a := n1.get_noise_2d(x, y) * 0.5 + 0.5
			var b := n2.get_noise_2d(x, y) * 0.5 + 0.5
			var neb := pow(clampf((a - 0.3) / 0.55, 0.0, 1.0), 1.5) * band
			var col := base
			col += Color(0.6, 0.12, 0.8) * neb * 0.75
			col += Color(0.08, 0.45, 0.95) * pow(b, 3.0) * 0.55 * band
			col += Color(1.0, 0.35, 0.45) * pow(neb * b, 2.0) * 1.1
			col += Color(1.0, 0.75, 0.4) * pow(neb, 6.0) * 0.6
			col.a = 1.0
			img.set_pixel(x, y, Color(minf(col.r, 1.0), minf(col.g, 1.0), minf(col.b, 1.0)))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- Motive

func _stars() -> void:
	for i in 650:
		var p := Vector2(_rng.randf_range(0, W), _rng.randf_range(0, H))
		var b := _rng.randf_range(0.15, 1.0)
		var tint: Color = [Color(0.8, 0.88, 1.0), Color(1.0, 0.9, 0.75), Color(0.85, 0.75, 1.0)][i % 3]
		draw_circle(p, _rng.randf_range(0.5, 1.8), Color(tint, b))
		if b > 0.95:
			_glow_circle(p, 10, Color(tint, 0.6), 5)
			draw_line(p - Vector2(14, 0), p + Vector2(14, 0), Color(1, 1, 1, 0.55), 1.2)
			draw_line(p - Vector2(0, 14), p + Vector2(0, 14), Color(1, 1, 1, 0.55), 1.2)


func _galaxy(c: Vector2, r: float, rot: float) -> void:
	_glow_circle(c, r * 1.3, Color(0.6, 0.5, 1.0, 0.35), 12)
	var g := RandomNumberGenerator.new()
	g.seed = 3
	for arm in 2:
		for i in 260:
			var t := float(i) / 260.0
			var ang := rot + arm * PI + t * 4.2
			var rad := r * t
			var jitter := Vector2(g.randf_range(-1, 1), g.randf_range(-1, 1)) * (4.0 + 10.0 * t)
			var p := c + Vector2(cos(ang), sin(ang) * 0.55).rotated(0.4) * rad + jitter
			var col := Color(0.75, 0.85, 1.0).lerp(Color(1.0, 0.55, 0.85), t)
			draw_circle(p, g.randf_range(0.8, 2.4) * (1.2 - t * 0.6), Color(col, 0.75 - 0.5 * t))
	_glow_circle(c, r * 0.35, Color(1.0, 0.92, 0.75, 0.9), 10)
	draw_circle(c, 5, Color(1, 1, 0.95))


func _comet(head: Vector2, dir: Vector2, length: float) -> void:
	var side := dir.orthogonal()
	for i in 24:
		var t := float(i) / 24.0
		var p := head - dir * length * t
		var w := lerpf(4.0, 26.0, t)
		draw_colored_polygon(PackedVector2Array([p + side * w, p - side * w,
			p - dir * length / 24.0 - side * w * 1.05, p - dir * length / 24.0 + side * w * 1.05]),
			Color(0.6, 0.9, 1.0, 0.2 * (1.0 - t)))
	draw_polyline(PackedVector2Array([head, head - dir * length * 0.8 + side * 18.0]),
		Color(1.0, 0.8, 0.6, 0.25), 3.0, true)
	_glow_circle(head, 22, Color(0.7, 0.95, 1.0, 0.9), 8)
	draw_circle(head, 4, Color.WHITE)


func _ringed_planet(c: Vector2, r: float) -> void:
	_glow_circle(c, r * 1.45, Color(0.95, 0.45, 1.0, 0.5), 12)
	# Hintere Ringhälfte.
	for k in 4:
		draw_polyline(_ellipse(c, r * (1.55 + k * 0.1), r * (0.42 + k * 0.03), -0.35, PI, TAU),
			Color(1.0, 0.8, 0.95, 0.45 - k * 0.08), 5.0, true)
	draw_circle(c, r, Color(0.38, 0.14, 0.55))
	# Wolkenbänder.
	var bands := [Color(0.55, 0.25, 0.7), Color(0.7, 0.35, 0.75), Color(0.48, 0.2, 0.62),
		Color(0.85, 0.5, 0.8), Color(0.5, 0.22, 0.66), Color(0.65, 0.3, 0.72)]
	for i in 26:
		var y := -r + (i + 0.5) * (2.0 * r / 26.0)
		var half := sqrt(maxf(0.0, r * r - y * y))
		var col: Color = bands[(i * 7 / 5) % bands.size()]
		var p := Vector2(0, y).rotated(-0.35)
		var d := Vector2(half, 0).rotated(-0.35)
		draw_line(c + p - d, c + p + d, col, 2.0 * r / 26.0 + 1.0)
	# Schatten (Tag-Nacht-Grenze) und Lichtkante.
	for i in 10:
		draw_arc(c + Vector2(r * 0.25, r * 0.2), r * (0.95 - i * 0.02), -0.6, 2.3, 32,
			Color(0.05, 0.0, 0.12, 0.08), r * 0.25)
	draw_arc(c, r - 2, PI + 0.6, TAU - 0.2, 40, Color(1.0, 0.85, 1.0, 0.7), 3.0, true)
	# Vordere Ringhälfte.
	for k in 4:
		draw_polyline(_ellipse(c, r * (1.55 + k * 0.1), r * (0.42 + k * 0.03), -0.35, 0.0, PI),
			Color(1.0, 0.85, 0.95, 0.7 - k * 0.12), 5.0, true)


func _asteroid(c: Vector2, r: float, seed_: int) -> void:
	var g := RandomNumberGenerator.new()
	g.seed = seed_
	var pts := PackedVector2Array()
	for i in 11:
		pts.append(c + Vector2.from_angle(TAU * i / 11.0) * r * g.randf_range(0.7, 1.15))
	draw_colored_polygon(pts, Color(0.32, 0.27, 0.36))
	var light := PackedVector2Array()
	for p in pts:
		light.append(c + (p - c) * 0.8 + Vector2(-r * 0.12, -r * 0.15))
	draw_colored_polygon(light, Color(0.5, 0.44, 0.52))
	for i in 3:
		var cp := c + Vector2(g.randf_range(-0.4, 0.4), g.randf_range(-0.4, 0.4)) * r
		draw_circle(cp, r * g.randf_range(0.12, 0.22), Color(0.28, 0.23, 0.32))
	pts.append(pts[0])
	draw_polyline(pts, Color(1.0, 0.7, 0.5, 0.35), 1.5, true)


func _chevrons(path: PackedVector2Array, col: Color, every := 46.0, size := 13.0) -> void:
	# Leuchtende Bahn mit Pfeilen in Schussrichtung.
	draw_polyline(path, Color(col, 0.07), size * 5.0, true)
	draw_polyline(path, Color(col, 0.12), size * 2.6, true)
	var dist := 0.0
	var next := every * 0.5
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var seg := a.distance_to(b)
		while next <= dist + seg:
			var p := a.lerp(b, (next - dist) / seg)
			var d := (b - a).normalized()
			var s := d.orthogonal()
			var fade := 0.35 + 0.65 * (next / 900.0)
			var chev := PackedVector2Array([p - d * size * 0.6 + s * size, p + d * size * 0.4,
				p - d * size * 0.6 - s * size])
			draw_polyline(chev, Color(col, 0.25 * fade), 9.0, true)
			draw_polyline(chev, Color(col.lightened(0.4), 0.9 * fade), 3.5, true)
			next += every
		dist += seg


func _horizon() -> void:
	# Planetenoberfläche über den Flippern mit Atmosphäre, Bergen und Kratern.
	var c := Vector2(470, 2650)
	var r := 1200.0
	_glow_circle(c, r + 90.0, Color(1.0, 0.35, 0.65, 0.35), 18)
	draw_circle(c, r + 8.0, Color(1.0, 0.55, 0.4, 0.85))
	draw_circle(c, r, Color(0.16, 0.05, 0.22))
	# Berge auf der Horizontlinie.
	var g := RandomNumberGenerator.new()
	g.seed = 11
	var ridge := PackedVector2Array()
	for i in 41:
		var ang := deg_to_rad(-90.0 + (i - 20) * 1.35)
		var rr := r + (g.randf_range(6, 34) if i % 2 == 0 else g.randf_range(-4, 8))
		ridge.append(c + Vector2.from_angle(ang) * rr)
	for i in range(40, -1, -1):
		ridge.append(c + Vector2.from_angle(deg_to_rad(-90.0 + (i - 20) * 1.35)) * (r - 20.0))
	draw_colored_polygon(ridge, Color(0.1, 0.03, 0.16))
	# Perspektivisches Gitter auf der Oberfläche.
	for i in 17:
		var x := -500.0 + i * 125.0
		var top := c + Vector2.from_angle(deg_to_rad(-90.0 + (x - 470.0) / 30.0)) * r
		draw_line(top, Vector2(x, 1720), Color(1.0, 0.25, 0.8, 0.22), 2.0)
	for i in 7:
		var t := pow(float(i + 1) / 7.0, 1.7)
		draw_arc(c, r - t * 230.0, deg_to_rad(-120), deg_to_rad(-60), 64, Color(1.0, 0.25, 0.8, 0.1 + 0.18 * t), 2.0)
	# Krater.
	for pos in [Vector2(250, 1570), Vector2(690, 1585), Vector2(560, 1660), Vector2(360, 1650)]:
		draw_polyline(_ellipse(pos, 34, 10, 0.0), Color(0.45, 0.2, 0.5, 0.6), 2.0, true)
		draw_colored_polygon(_ellipse(pos + Vector2(0, 2), 30, 8, 0.0), Color(0.08, 0.02, 0.12, 0.6))


func _launch_pad() -> void:
	# Gasse des Scoops: Startrampe mit Warnstreifen, Rauch und Countdown.
	_glow_circle(Vector2(470, 930), 150, Color(1.0, 0.55, 0.15, 0.45), 12)
	for i in 14:
		var g := Vector2(470 + sin(i * 1.7) * 75.0, 935 + cos(i * 2.3) * 22.0)
		_glow_circle(g, 34 + (i % 4) * 8, Color(0.85, 0.8, 0.9, 0.45), 6)
	draw_rect(Rect2(434, 805, 72, 100), Color(0.08, 0.07, 0.1))
	for i in 8:
		var y := 822.0 + i * 11.0
		draw_line(Vector2(438, y), Vector2(502, y + 9), Color(1.0, 0.75, 0.1, 0.6), 4.5)
	var sp := Phys.SCOOP_POS
	draw_circle(sp, 22, Color(0.25, 0.25, 0.3))
	draw_circle(sp, 18, Color(0.0, 0.0, 0.0))
	# Countdown links neben der Gasse.
	var digits := ["3", "2", "1"]
	for i in 3:
		_text(Vector2(410 - i * 4, 960 + i * 26), digits[i], 22 - i * 2, Color(1.0, 0.8, 0.3, 0.75 - i * 0.15), 40)


func _panel(r: Rect2, title: String, col: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.02, 0.08, 0.55)
	box.border_color = Color(col, 0.75)
	box.set_border_width_all(3)
	box.set_corner_radius_all(18)
	box.shadow_color = Color(col, 0.25)
	box.shadow_size = 10
	draw_style_box(box, r)
	if title != "":
		_label(Vector2(r.get_center().x, r.position.y + 6), title, 12, col.lightened(0.3))


func _lane_art() -> void:
	# In- und Outlanes: farbige Bahnen mit Pfeilen Richtung Flipper bzw. Abfluss.
	for side in 2:
		var mx := func(x: float) -> float: return x if side == 0 else 940.0 - x
		for i in 4:
			var y := 1280.0 + i * 40.0
			var cx: float = mx.call(130.0)
			draw_polyline(PackedVector2Array([Vector2(cx - 12, y), Vector2(cx, y + 10), Vector2(cx + 12, y)]),
				Color(0.3, 1.0, 0.5, 0.55), 3.0, true)
			var ox: float = mx.call(67.0)
			draw_polyline(PackedVector2Array([Vector2(ox - 10, y + 150), Vector2(ox, y + 160), Vector2(ox + 10, y + 150)]),
				Color(1.0, 0.3, 0.3, 0.45), 3.0, true)
	# Sky Lanes: leuchtende Streifen in jeder Bahn.
	for i in 3:
		var x := 390.0 + 80.0 * i
		_gradient_rect(Rect2(x - 22, 300, 44, 70), Color(0.3, 1.0, 0.5, 0.0), Color(0.3, 1.0, 0.5, 0.22))


# ---------------------------------------------------------------- Zeichnen

func _draw() -> void:
	_rng.seed = 1992
	draw_texture_rect(_nebula, Rect2(0, 0, W, H), false)
	_stars()

	_galaxy(Vector2(700, 235), 85, 0.3)
	_comet(Vector2(205, 330), Vector2(-0.55, 0.83).normalized() * -1.0, 230)
	draw_circle(Vector2(800, 430), 30, Color(0.72, 0.75, 0.82))
	draw_circle(Vector2(791, 421), 8, Color(0.58, 0.6, 0.68))
	draw_circle(Vector2(809, 440), 5, Color(0.6, 0.62, 0.7))
	draw_arc(Vector2(800, 430), 30, 2.0, 4.6, 24, Color(0.1, 0.1, 0.2, 0.6), 12)
	_ringed_planet(Vector2(240, 1150), 80)
	for a in [[Vector2(320, 640), 16, 1], [Vector2(612, 700), 12, 2], [Vector2(770, 1090), 18, 3],
			[Vector2(560, 1395), 11, 4], [Vector2(380, 1410), 14, 5], [Vector2(150, 960), 10, 6]]:
		_asteroid(a[0], a[1], a[2])

	_horizon()
	_lane_art()

	# Schussbahnen mit Chevrons.
	_chevrons(_curve(Vector2(430, 1500), Vector2(570, 1250), Vector2(680, 1010)), Color(0.25, 1.0, 0.45))
	_chevrons(_curve(Vector2(510, 1500), Vector2(300, 1250), Vector2(206, 1020)), Color(1.0, 0.3, 0.85))
	_chevrons(_curve(Vector2(500, 1500), Vector2(120, 1300), Vector2(76, 990)), Color(0.2, 0.9, 1.0))
	_chevrons(_curve(Vector2(470, 1500), Vector2(470, 1200), Vector2(470, 990)), Color(1.0, 0.75, 0.2))
	_chevrons(_curve(Vector2(780, 975), Vector2(640, 900), Vector2(575, 900)), Color(0.2, 0.95, 1.0), 40, 10)

	_launch_pad()

	# Stargate-Tasche.
	var sg := Vector2(570, 870)
	_glow_circle(sg, 75, Color(0.2, 0.95, 1.0, 0.5), 10)
	for k in 5:
		draw_arc(sg, 18.0 + k * 12.0, k * 0.6, k * 0.6 + TAU * 0.8, 40, Color(0.35, 0.95, 1.0, 0.6 - k * 0.1), 3.0, true)

	# Instrumententafeln um die Lampengruppen.
	_panel(Rect2(372, 1022, 196, 150), "MISSION CONTROL", Color(1.0, 0.4, 0.9))
	_panel(Rect2(344, 1262, 252, 70), "", Color(0.3, 0.6, 1.0))

	# Logo mit Chrom-Effekt.
	var logo_pos := Vector2(470, 1238)
	_text(logo_pos + Vector2(4, 5), "LIFTOFF", 66, Color(0, 0, 0, 0.6), 700)
	draw_string_outline(bold, logo_pos - Vector2(350, 0), "LIFTOFF", HORIZONTAL_ALIGNMENT_CENTER, 700, 66, 10,
		Color(1.0, 0.2, 0.7, 0.8))
	_text(logo_pos, "LIFTOFF", 66, Color(1.0, 0.72, 0.2), 700)
	_text(logo_pos - Vector2(0, 3), "LIFTOFF", 66, Color(1.0, 0.95, 0.7, 0.45), 700)

	# Beschriftungen.
	_label(Vector2(470, 290), "SKY LANES", 18, Color(0.5, 1.0, 0.6))
	_label(Vector2(75, 735), "SPIN", 12, Color(0.4, 0.95, 1.0))
	_label(Vector2(470, 1350), "BONUS MULTIPLIER", 12, Color(0.6, 0.8, 1.0))
	_label(Vector2(470, 1070), "TREIBSTOFF", 11, Color(0.5, 1.0, 0.6))
	_label(Vector2(470, 1124), "LOCK", 11, Color(1.0, 0.75, 0.3))
	_label(Vector2(385, 908), "TARGETS", 12, Color(1.0, 0.8, 0.3))

	# Fassungen der Einsätze (Chromringe mit Lichthof).
	for ins in Layout.inserts():
		var p: Vector2 = ins["pos"]
		var s: float = ins["size"]
		var col: Color = ins["color"]
		_glow_circle(p, s * 2.6, Color(col, 0.4), 6)
		draw_circle(p, s + 5, Color(0.55, 0.58, 0.66))
		draw_circle(p, s + 3.5, Color(0.88, 0.9, 0.95))
		draw_circle(p, s + 2, Color(0.04, 0.04, 0.07))
		if ins.has("label"):
			_label(p + Vector2(0, s + 21), ins["label"], 12, Color(1, 1, 1, 0.92))

	# Abschussrinne.
	draw_rect(Rect2(900, 500, 60, H - 500), Color(0.02, 0.02, 0.05))
	for i in 11:
		var y := 640.0 + i * 95.0
		draw_polyline(PackedVector2Array([Vector2(914, y), Vector2(930, y - 18), Vector2(946, y)]),
			Color(1.0, 0.65, 0.2, 0.55), 3.0)

	# Apron mit Regelkarten (liegt unter y = 1690).
	_gradient_rect(Rect2(0, 1688, W, H - 1688), Color(0.12, 0.1, 0.16), Color(0.05, 0.04, 0.08))
	for i in 40:
		var x := i * 26.0
		draw_line(Vector2(x, 1800), Vector2(x + 60, 1690), Color(1, 1, 1, 0.03), 8.0)
	draw_line(Vector2(0, 1690), Vector2(W, 1690), Color(0.8, 0.82, 0.9), 4.0)
	_card(Rect2(60, 1708, 320, 80), ["3 RAMPEN = LOCK AM LAUNCH PAD", "2 LOCKS = MULTIBALL",
		"ROTE PFEILE = JACKPOT"])
	_card(Rect2(560, 1708, 320, 80), ["DROP TARGETS = MISSION", "STARGATE = JACKPOT +100K",
		"LINKE RAMPE > OBERER FLIPPER"])


func _card(r: Rect2, lines: Array) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.95, 0.92, 0.85)
	box.border_color = Color(0.12, 0.05, 0.22)
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	draw_style_box(box, r)
	for i in lines.size():
		_text(Vector2(r.get_center().x, r.position.y + 24 + i * 22), lines[i], 13, Color(0.12, 0.05, 0.22),
			r.size.x)
