extends Node2D
## LIFTOFF – der Spieltisch.
##
## Enthält Geometrie, eine eigene Ball-Physik und die komplette Darstellung.
## Die Physik ist bewusst selbst geschrieben (statt RigidBody2D): Mit Substeps
## gibt es kein Durchtunneln schneller Bälle und die Flipper fühlen sich
## berechenbar an – wie bei den Amiga-Klassikern.
##
## Koordinaten: Tisch ist 1000 x 1800 Einheiten groß, y zeigt nach unten
## (zum Spieler). Die Spielregeln liegen in main.gd; der Tisch meldet nur
## Ereignisse über das Signal `table_event`.

signal table_event(kind: String, id: int)

const W := 1000.0
const H := 1800.0
const CENTER_X := 470.0
const BALL_R := 14.0
const GRAVITY := 2300.0
const SUBSTEPS := 8
const MAX_SPEED := 4200.0
const BUMPER_KICK := 1050.0
const SLING_KICK := 900.0
const RAMP_SPEED := 1500.0
const RAMP_MIN_SPEED := 250.0
const SAUCER_POS := Vector2(230, 760)
const SAUCER_HOLD := 1.3
const LANE_X := 930.0
const PLUNGER_Y := 1704.0
const PLUNGER_TRAVEL := 40.0
const DRAIN_Y := 1840.0
const ARC_CENTER := Vector2(500, 480)
const ARC_RADIUS := 460.0

const COL_WALL := Color(0.35, 0.85, 1.0)
const COL_RUBBER := Color(1.0, 0.35, 0.55)
const COL_GOLD := Color(1.0, 0.72, 0.2)
const COL_GREEN := Color(0.3, 1.0, 0.5)
const COL_RED := Color(1.0, 0.25, 0.25)
const COL_BLUE := Color(0.3, 0.6, 1.0)

enum BallMode { NONE, FREE, RAMP, SAUCER }


class Seg:
	var a: Vector2
	var b: Vector2
	var kind: String
	var rest: float
	var thick: float
	var id: int
	var active := true
	var flash := 0.0

	func _init(a_: Vector2, b_: Vector2, kind_ := "wall", rest_ := 0.45, thick_ := 4.0, id_ := 0) -> void:
		a = a_
		b = b_
		kind = kind_
		rest = rest_
		thick = thick_
		id = id_


class Circ:
	var c: Vector2
	var r: float
	var kind: String
	var rest: float
	var id: int
	var flash := 0.0
	var cooldown := 0.0

	func _init(c_: Vector2, r_: float, kind_ := "post", rest_ := 0.55, id_ := 0) -> void:
		c = c_
		r = r_
		kind = kind_
		rest = rest_
		id = id_


class Flipper:
	var pivot: Vector2
	var length := 118.0
	var rb := 17.0
	var rt := 9.0
	var rest_angle: float
	var up_angle: float
	var angle: float
	var omega := 0.0
	var pressed := false

	func _init(pivot_: Vector2, rest_: float, up_: float) -> void:
		pivot = pivot_
		rest_angle = rest_
		up_angle = up_
		angle = rest_

	func tip() -> Vector2:
		return pivot + Vector2.from_angle(angle) * length

	func step(dt: float) -> void:
		var target := up_angle if pressed else rest_angle
		var speed := 26.0 if pressed else 15.0
		var delta := clampf(target - angle, -speed * dt, speed * dt)
		angle += delta
		omega = delta / dt


class Sensor:
	var rect: Rect2
	var id: String
	var inside := false

	func _init(rect_: Rect2, id_: String) -> void:
		rect = rect_
		id = id_


var walls: Array[Seg] = []
var circles: Array[Circ] = []
var flippers: Array[Flipper] = []
var sensors: Array[Sensor] = []
var drops: Array[Seg] = []
var slings: Array[Seg] = []
var gate: Seg
var plunger_floor: Seg
var ramp_points := PackedVector2Array()
var ramp_lengths := PackedFloat32Array()
var ramp_total := 0.0
var arc_points := PackedVector2Array()

var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var ball_mode := BallMode.NONE
var in_lane := false
var ramp_dist := 0.0
var saucer_timer := 0.0
var saucer_block := 0.0
var stuck_timer := 0.0
var plunger_charge := 0.0
var plunger_held := false
var time := 0.0
var trail: Array[Vector2] = []

## Lampenzustände, gesetzt von main.gd: 0 = aus, 1 = an, 2 = blinkt.
var lamps := {}

var font: Font
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	font = ThemeDB.fallback_font
	_build()
	var static_layer := Node2D.new()
	static_layer.show_behind_parent = true
	add_child(static_layer)
	static_layer.draw.connect(_draw_static.bind(static_layer))


# ---------------------------------------------------------------- Geometrie

func _m(v: Vector2) -> Vector2:
	return Vector2(2.0 * CENTER_X - v.x, v.y)


func _wall(a: Vector2, b: Vector2, kind := "wall", rest := 0.45, thick := 4.0, id := 0) -> Seg:
	var s := Seg.new(a, b, kind, rest, thick, id)
	walls.append(s)
	return s


func _circ(c: Vector2, r: float, kind := "post", rest := 0.55, id := 0) -> Circ:
	var o := Circ.new(c, r, kind, rest, id)
	circles.append(o)
	return o


func _mirror_rect(r: Rect2) -> Rect2:
	return Rect2(2.0 * CENTER_X - r.position.x - r.size.x, r.position.y, r.size.x, r.size.y)


func _build() -> void:
	# Kuppel oben, über die ganze Breite inklusive Abschussrinne.
	arc_points.clear()
	var steps := 36
	for i in range(steps + 1):
		var ang := PI + PI * float(i) / steps
		arc_points.append(ARC_CENTER + Vector2(cos(ang), sin(ang)) * ARC_RADIUS)
	for i in range(steps):
		_wall(arc_points[i], arc_points[i + 1], "wall", 0.35)

	# Außenwände und Abschussrinne.
	_wall(Vector2(40, 480), Vector2(40, H + 80))
	_wall(Vector2(960, 480), Vector2(960, H + 80))
	_wall(Vector2(900, 560), Vector2(900, H + 80))
	# Abweiser: Bälle, die an der Außenwand herunterlaufen, landen in den
	# Inlanes statt direkt in den Outlanes.
	_wall(Vector2(40, 1030), Vector2(88, 1200), "wall", 0.4)
	_wall(Vector2(900, 1120), Vector2(856, 1200), "wall", 0.4)
	gate = _wall(Vector2(900, 560), Vector2(958, 500), "gate", 0.3, 3.0)
	gate.active = false
	plunger_floor = _wall(Vector2(902, PLUNGER_Y), Vector2(958, PLUNGER_Y), "plunger", 0.05, 4.0)

	# Out-/Inlane-Führungen und Slingshots (links bauen, rechts spiegeln).
	for side in 2:
		var f := func(v: Vector2) -> Vector2: return v if side == 0 else _m(v)
		_wall(f.call(Vector2(95, 1240)), f.call(Vector2(95, 1440)))
		_wall(f.call(Vector2(95, 1440)), f.call(Vector2(337, 1561)))
		_circ(f.call(Vector2(95, 1240)), 6.0)
		var a: Vector2 = f.call(Vector2(165, 1300))
		var b: Vector2 = f.call(Vector2(165, 1420))
		var c: Vector2 = f.call(Vector2(285, 1490))
		_wall(a, b, "wall", 0.3)
		_wall(b, c, "wall", 0.3)
		slings.append(_wall(c, a, "sling", 0.6, 4.0, side))
		for p in [a, b, c]:
			_circ(p, 8.0, "post", 0.6)

	# Flipper.
	flippers.append(Flipper.new(Vector2(345, 1580), 0.55, -0.45))
	flippers.append(Flipper.new(_m(Vector2(345, 1580)), PI - 0.55, PI + 0.45))

	# Pop-Bumper.
	_circ(Vector2(390, 600), 36.0, "bumper", 0.4, 0)
	_circ(Vector2(550, 600), 36.0, "bumper", 0.4, 1)
	_circ(Vector2(470, 730), 36.0, "bumper", 0.4, 2)

	# Obere Rollover-Bahnen.
	for x in [350.0, 430.0, 510.0, 590.0]:
		_wall(Vector2(x, 330), Vector2(x, 400), "wall", 0.4, 5.0)
	for i in 3:
		var cx := 390.0 + 80.0 * i
		sensors.append(Sensor.new(Rect2(cx - 22, 355, 44, 40), "lane%d" % i))

	# Rampen-Einfahrt (Trichter). Ist der Ball schnell genug, fährt er die Rampe.
	_wall(Vector2(628, 985), Vector2(640, 790))
	_wall(Vector2(732, 985), Vector2(720, 790))
	_wall(Vector2(640, 790), Vector2(720, 790), "wall", 0.25)
	sensors.append(Sensor.new(Rect2(645, 805, 70, 30), "ramp"))

	# Drop-Targets rechts.
	for i in 3:
		var y := 960.0 + 52.0 * i
		var d := _wall(Vector2(868, y), Vector2(868, y + 42), "drop", 0.3, 5.0, i)
		drops.append(d)

	# Sensoren für Orbit, In- und Outlanes.
	sensors.append(Sensor.new(Rect2(42, 420, 80, 60), "orbit"))
	var outlane := Rect2(42, 1380, 50, 30)
	var inlane := Rect2(99, 1335, 60, 30)
	sensors.append(Sensor.new(outlane, "outlane"))
	sensors.append(Sensor.new(_mirror_rect(outlane), "outlane"))
	sensors.append(Sensor.new(inlane, "inlane"))
	sensors.append(Sensor.new(_mirror_rect(inlane), "inlane"))

	# Rampe als Pfad (läuft "über" dem Spielfeld) bis in die linke Inlane.
	ramp_points = PackedVector2Array([
		Vector2(680, 800), Vector2(690, 640), Vector2(660, 540), Vector2(580, 490),
		Vector2(470, 474), Vector2(330, 486), Vector2(210, 540), Vector2(140, 640),
		Vector2(118, 800), Vector2(115, 1000), Vector2(120, 1180), Vector2(128, 1262),
	])
	ramp_lengths.clear()
	ramp_total = 0.0
	ramp_lengths.append(0.0)
	for i in range(1, ramp_points.size()):
		ramp_total += ramp_points[i - 1].distance_to(ramp_points[i])
		ramp_lengths.append(ramp_total)


# ---------------------------------------------------------------- Steuerung

func serve_ball() -> void:
	ball_pos = Vector2(LANE_X, PLUNGER_Y - BALL_R - 6.0)
	ball_vel = Vector2.ZERO
	ball_mode = BallMode.FREE
	in_lane = true
	gate.active = false
	stuck_timer = 0.0
	trail.clear()
	for s in sensors:
		s.inside = false


func remove_ball() -> void:
	ball_mode = BallMode.NONE
	trail.clear()


func reset_drops() -> void:
	for d in drops:
		d.active = true
		d.flash = 0.3


func drops_down() -> int:
	var n := 0
	for d in drops:
		if not d.active:
			n += 1
	return n


func ball_in_plunger() -> bool:
	return ball_mode == BallMode.FREE and in_lane and ball_pos.x > 900.0 and ball_pos.y > 1550.0


func set_flipper(index: int, pressed: bool) -> void:
	flippers[index].pressed = pressed


func set_plunger(held: bool) -> void:
	if plunger_held and not held:
		if ball_in_plunger() and ball_pos.y > PLUNGER_Y - 60.0:
			ball_pos.y = PLUNGER_Y - BALL_R - 6.0
			ball_vel = Vector2(0, -(2200.0 + 1100.0 * plunger_charge))
			table_event.emit("launch", int(plunger_charge * 100.0))
		plunger_charge = 0.0
	plunger_held = held


func nudge(dir: Vector2) -> void:
	if ball_mode == BallMode.FREE and not in_lane:
		ball_vel += dir


# ---------------------------------------------------------------- Physik

func physics_step(delta: float) -> void:
	time += delta
	for c in circles:
		c.flash = maxf(0.0, c.flash - delta)
		c.cooldown = maxf(0.0, c.cooldown - delta)
	for w in walls:
		w.flash = maxf(0.0, w.flash - delta)
	saucer_block = maxf(0.0, saucer_block - delta)

	if plunger_held:
		plunger_charge = minf(1.0, plunger_charge + delta * 1.2)
	var floor_y := PLUNGER_Y + PLUNGER_TRAVEL * plunger_charge
	plunger_floor.a.y = floor_y
	plunger_floor.b.y = floor_y

	match ball_mode:
		BallMode.FREE:
			_step_free(delta)
		BallMode.RAMP:
			_step_flippers(delta)
			_step_ramp(delta)
		BallMode.SAUCER:
			_step_flippers(delta)
			_step_saucer(delta)
		_:
			_step_flippers(delta)

	if ball_mode != BallMode.NONE:
		trail.push_front(ball_pos)
		if trail.size() > 6:
			trail.pop_back()


func _step_flippers(delta: float) -> void:
	for f in flippers:
		f.step(delta)


func _step_free(delta: float) -> void:
	var dt := delta / SUBSTEPS
	for _i in SUBSTEPS:
		for f in flippers:
			f.step(dt)
		ball_vel.y += GRAVITY * dt
		var sp := ball_vel.length()
		if sp > MAX_SPEED:
			ball_vel *= MAX_SPEED / sp
		ball_pos += ball_vel * dt
		_collide()
		_check_sensors()
		if ball_mode != BallMode.FREE:
			return
		if ball_pos.y > DRAIN_Y:
			remove_ball()
			table_event.emit("drain", 0)
			return

	if in_lane and ball_pos.y < 500.0:
		in_lane = false
		gate.active = true

	# Notfall: Ball liegt irgendwo fest -> sanft anstupsen.
	var resting := ball_vel.length() < 8.0
	var held_by_flipper := flippers[0].pressed or flippers[1].pressed
	if resting and not in_lane and not held_by_flipper:
		stuck_timer += delta
		if stuck_timer > 4.0:
			ball_vel += Vector2(_rng.randf_range(-250, 250), -500)
			stuck_timer = 0.0
	else:
		stuck_timer = 0.0


func _resolve(n: Vector2, pen: float, rest: float, surf_vel := Vector2.ZERO) -> float:
	ball_pos += n * pen
	var rel := ball_vel - surf_vel
	var vn := rel.dot(n)
	if vn >= 0.0:
		return 0.0
	var e := rest if -vn > 60.0 else 0.0
	var vt := rel - n * vn
	rel = vt * 0.995 - n * vn * e
	ball_vel = rel + surf_vel
	return -vn


func _collide() -> void:
	for w in walls:
		if not w.active:
			continue
		var ab := w.b - w.a
		var t := clampf((ball_pos - w.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := ball_pos - (w.a + ab * t)
		var rr := BALL_R + w.thick
		var dist2 := d.length_squared()
		if dist2 >= rr * rr or dist2 < 1e-8:
			continue
		var dist := sqrt(dist2)
		var n := d / dist
		var impact := _resolve(n, rr - dist, w.rest)
		if w.kind == "sling" and impact > 60.0 and t > 0.1 and t < 0.9:
			ball_vel += n * SLING_KICK
			w.flash = 0.15
			table_event.emit("sling", w.id)
		elif w.kind == "drop" and impact > 30.0:
			w.active = false
			w.flash = 0.3
			table_event.emit("drop", w.id)

	for c in circles:
		var d := ball_pos - c.c
		var rr := BALL_R + c.r
		var dist2 := d.length_squared()
		if dist2 >= rr * rr or dist2 < 1e-8:
			continue
		var dist := sqrt(dist2)
		var n := d / dist
		_resolve(n, rr - dist, c.rest)
		if c.kind == "bumper" and c.cooldown <= 0.0:
			ball_vel += n * maxf(0.0, BUMPER_KICK - ball_vel.dot(n))
			c.cooldown = 0.06
			c.flash = 0.2
			table_event.emit("bumper", c.id)

	for f in flippers:
		var tip := f.tip()
		var ab := tip - f.pivot
		var t := clampf((ball_pos - f.pivot).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var cp := f.pivot + ab * t
		var rad := lerpf(f.rb, f.rt, t)
		var d := ball_pos - cp
		var rr := BALL_R + rad
		var dist2 := d.length_squared()
		if dist2 >= rr * rr or dist2 < 1e-8:
			continue
		var dist := sqrt(dist2)
		var n := d / dist
		var contact := cp + n * rad - f.pivot
		var surf := Vector2(-contact.y, contact.x) * f.omega
		_resolve(n, rr - dist, 0.3, surf)


func _check_sensors() -> void:
	for s in sensors:
		var inside := s.rect.has_point(ball_pos)
		if inside and not s.inside:
			_on_sensor(s.id)
		s.inside = inside
		if ball_mode != BallMode.FREE:
			return

	if saucer_block <= 0.0 and ball_pos.distance_to(SAUCER_POS) < 14.0 and ball_vel.length() < 1600.0:
		ball_mode = BallMode.SAUCER
		ball_pos = SAUCER_POS
		ball_vel = Vector2.ZERO
		saucer_timer = SAUCER_HOLD
		table_event.emit("saucer", 0)


func _on_sensor(id: String) -> void:
	if id == "ramp":
		if ball_vel.y < -RAMP_MIN_SPEED:
			ball_mode = BallMode.RAMP
			ramp_dist = 0.0
			table_event.emit("ramp", 0)
	elif id.begins_with("lane"):
		table_event.emit("lane", int(id.substr(4)))
	elif id == "orbit":
		if ball_vel.y < 0.0:
			table_event.emit("orbit", 0)
	else:
		table_event.emit(id, 0)


func _step_ramp(delta: float) -> void:
	ramp_dist += RAMP_SPEED * delta
	if ramp_dist >= ramp_total:
		ball_pos = ramp_points[ramp_points.size() - 1]
		ball_vel = Vector2(0, 450)
		ball_mode = BallMode.FREE
		for s in sensors:
			s.inside = false
		table_event.emit("ramp_exit", 0)
		return
	ball_pos = _ramp_point(ramp_dist)


func _ramp_point(dist: float) -> Vector2:
	for i in range(1, ramp_lengths.size()):
		if dist <= ramp_lengths[i]:
			var seg_len := ramp_lengths[i] - ramp_lengths[i - 1]
			var t := (dist - ramp_lengths[i - 1]) / seg_len
			return ramp_points[i - 1].lerp(ramp_points[i], t)
	return ramp_points[ramp_points.size() - 1]


func _step_saucer(delta: float) -> void:
	saucer_timer -= delta
	if saucer_timer <= 0.0:
		ball_mode = BallMode.FREE
		ball_vel = Vector2(_rng.randf_range(380, 520), _rng.randf_range(80, 220))
		saucer_block = 0.5
		table_event.emit("saucer_eject", 0)


# ---------------------------------------------------------------- Zeichnen

func _process(_delta: float) -> void:
	queue_redraw()


func _lamp_state(key: String) -> int:
	return int(lamps.get(key, 0))


func _is_lit(state: int, phase := 0.0) -> bool:
	return state == 1 or (state == 2 and fmod(time + phase, 0.5) < 0.25)


func _text(pos: Vector2, s: String, size: int, col: Color, width := 300.0) -> void:
	draw_string(font, pos - Vector2(width * 0.5, 0), s, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)


func _lamp(pos: Vector2, r: float, col: Color, state: int, label := "") -> void:
	var lit := _is_lit(state)
	if lit:
		draw_circle(pos, r * 1.9, Color(col, 0.16))
		draw_circle(pos, r * 1.35, Color(col, 0.25))
	draw_circle(pos, r, col if lit else col.darkened(0.78))
	draw_arc(pos, r, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 1.5)
	if lit:
		draw_circle(pos - Vector2(r, r) * 0.3, r * 0.3, Color(1, 1, 1, 0.6))
	if label != "":
		_text(pos + Vector2(0, r + 16), label, 14, Color(1, 1, 1, 0.75 if lit else 0.35), 160.0)


func _arrow(pos: Vector2, angle: float, size: float, col: Color, state: int) -> void:
	var lit := _is_lit(state)
	var dir := Vector2.from_angle(angle)
	var side := dir.orthogonal()
	var pts := PackedVector2Array([
		pos + dir * size,
		pos - dir * size * 0.6 + side * size * 0.8,
		pos - dir * size * 0.2,
		pos - dir * size * 0.6 - side * size * 0.8,
	])
	if lit:
		draw_circle(pos, size * 1.6, Color(col, 0.18))
	draw_colored_polygon(pts, col if lit else col.darkened(0.78))


func _glow_line(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	draw_line(a, b, Color(col, 0.15), width + 10.0)
	draw_line(a, b, col, width)


func _draw_static(layer: Node2D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1992
	layer.draw_rect(Rect2(0, 0, W, H), Color(0.03, 0.035, 0.09))
	var field := PackedVector2Array(arc_points)
	field.append(Vector2(960, H))
	field.append(Vector2(40, H))
	layer.draw_colored_polygon(field, Color(0.06, 0.07, 0.17))

	# Nebel und Sterne.
	var nebula := [
		[Vector2(250, 420), 260.0, Color(0.5, 0.15, 0.6, 0.10)],
		[Vector2(700, 1050), 320.0, Color(0.1, 0.35, 0.7, 0.10)],
		[Vector2(330, 1180), 220.0, Color(0.7, 0.2, 0.35, 0.08)],
		[Vector2(520, 300), 200.0, Color(0.2, 0.6, 0.8, 0.07)],
	]
	for nb in nebula:
		for k in 4:
			layer.draw_circle(nb[0], nb[1] * (1.0 - k * 0.2), nb[2])
	for i in 220:
		var p := Vector2(rng.randf_range(45, 955), rng.randf_range(30, H - 40))
		if Geometry2D.is_point_in_polygon(p, field):
			var b := rng.randf_range(0.25, 1.0)
			layer.draw_circle(p, rng.randf_range(0.8, 2.2), Color(0.8, 0.85, 1.0, b))

	# Planet unten links.
	layer.draw_circle(Vector2(250, 1050), 70, Color(0.45, 0.2, 0.55, 0.45))
	layer.draw_arc(Vector2(250, 1050), 105, 0.3, 2.6, 40, Color(0.9, 0.7, 1.0, 0.35), 4.0)
	layer.draw_circle(Vector2(230, 1030), 30, Color(0.7, 0.4, 0.8, 0.25))

	# Rakete in der Mitte.
	var rx := CENTER_X
	var ry := 1000.0
	var body := PackedVector2Array([
		Vector2(rx, ry - 170), Vector2(rx + 34, ry - 110), Vector2(rx + 40, ry + 40),
		Vector2(rx - 40, ry + 40), Vector2(rx - 34, ry - 110),
	])
	layer.draw_colored_polygon(body, Color(0.82, 0.85, 0.95, 0.85))
	layer.draw_colored_polygon(PackedVector2Array([
		Vector2(rx - 40, ry - 10), Vector2(rx - 85, ry + 70), Vector2(rx - 40, ry + 40)]),
		Color(0.95, 0.3, 0.45, 0.9))
	layer.draw_colored_polygon(PackedVector2Array([
		Vector2(rx + 40, ry - 10), Vector2(rx + 85, ry + 70), Vector2(rx + 40, ry + 40)]),
		Color(0.95, 0.3, 0.45, 0.9))
	layer.draw_circle(Vector2(rx, ry - 70), 16, Color(0.2, 0.75, 1.0))
	layer.draw_arc(Vector2(rx, ry - 70), 16, 0, TAU, 24, Color(1, 1, 1, 0.8), 3.0)
	layer.draw_colored_polygon(PackedVector2Array([
		Vector2(rx - 26, ry + 40), Vector2(rx + 26, ry + 40), Vector2(rx, ry + 120)]),
		Color(1.0, 0.65, 0.15, 0.75))
	layer.draw_string(font, Vector2(rx - 200, ry + 190), "LIFTOFF", HORIZONTAL_ALIGNMENT_CENTER,
		400, 58, Color(1.0, 0.75, 0.25, 0.85))
	layer.draw_string(font, Vector2(rx - 200, ry + 222), "a pinball dream", HORIZONTAL_ALIGNMENT_CENTER,
		400, 20, Color(0.7, 0.85, 1.0, 0.6))

	# Abschussrinne.
	layer.draw_rect(Rect2(902, 560, 56, H - 560), Color(0.02, 0.02, 0.06))
	for i in 10:
		var y := 700.0 + i * 95.0
		layer.draw_line(Vector2(915, y), Vector2(930, y - 18), Color(1, 0.7, 0.2, 0.25), 3)
		layer.draw_line(Vector2(945, y), Vector2(930, y - 18), Color(1, 0.7, 0.2, 0.25), 3)

	# Rampenschild.
	layer.draw_string(font, Vector2(600, 1010), "RAMP", HORIZONTAL_ALIGNMENT_CENTER, 160, 18,
		Color(0.6, 0.9, 1.0, 0.7))
	layer.draw_string(font, Vector2(130, 715), "HYPERSPACE", HORIZONTAL_ALIGNMENT_CENTER, 200, 16,
		Color(1.0, 0.6, 0.9, 0.7))


func _draw() -> void:
	# Wände (Bögen, Führungen, Pfosten).
	for w in walls:
		match w.kind:
			"wall":
				_glow_line(w.a, w.b, COL_WALL, w.thick * 2.0)
			"gate":
				if w.active:
					_glow_line(w.a, w.b, COL_GOLD, w.thick * 2.0)
				else:
					draw_line(w.a, w.b, Color(COL_GOLD, 0.3), 2.0)

	# Slingshots.
	for s in slings:
		var a: Vector2 = s.b
		var c: Vector2 = s.a
		var b := Vector2(a.x, a.y + 120)
		var tri := PackedVector2Array([a, b, c])
		draw_colored_polygon(tri, Color(0.2, 0.08, 0.25, 0.8))
		var col := Color.WHITE if s.flash > 0.0 else COL_RUBBER
		draw_line(s.a, s.b, Color(col, 0.25), 18.0)
		draw_line(s.a, s.b, col, 7.0)
		_lamp((a + b + c) / 3.0, 9.0, COL_GOLD, 1 if s.flash > 0.0 else 0)

	# Drop-Targets.
	for d in drops:
		var mid := (d.a + d.b) * 0.5
		if d.active:
			var col := Color.WHITE if d.flash > 0.0 else COL_GOLD
			draw_rect(Rect2(d.a.x - 6, d.a.y, 14, d.b.y - d.a.y), col)
			draw_rect(Rect2(d.a.x - 6, d.a.y, 4, d.b.y - d.a.y), Color(1, 1, 1, 0.5))
		else:
			draw_rect(Rect2(d.a.x - 3, d.a.y + 4, 8, d.b.y - d.a.y - 8), Color(0.25, 0.2, 0.1))
		_lamp(mid + Vector2(-34, 0), 7.0, COL_GOLD, 0 if d.active else 1)

	# Saucer.
	draw_circle(SAUCER_POS, 26, Color(0.4, 0.2, 0.5))
	draw_circle(SAUCER_POS, 19, Color(0.0, 0.0, 0.0))
	draw_arc(SAUCER_POS, 26, 0, TAU, 32, Color(1.0, 0.6, 0.9, 0.8), 3.0)

	# Bumper und Pfosten.
	for c in circles:
		if c.kind == "bumper":
			var lit := c.flash > 0.0
			draw_circle(c.c, c.r + 10, Color(0.2, 0.9, 1.0, 0.35 if lit else 0.12))
			draw_circle(c.c, c.r, Color(0.9, 0.2, 0.4) if not lit else Color(1, 0.8, 0.9))
			draw_circle(c.c, c.r * 0.72, Color(0.15, 0.1, 0.3))
			draw_circle(c.c, c.r * 0.55, Color(1, 1, 0.6) if lit else Color(0.95, 0.75, 0.2))
		else:
			draw_circle(c.c, c.r + 2, COL_RUBBER.darkened(0.3))
			draw_circle(c.c, c.r * 0.6, Color(1, 1, 1, 0.8))

	# Lampen: obere Bahnen.
	for i in 3:
		_lamp(Vector2(390 + 80 * i, 425), 11.0, COL_GREEN, _lamp_state("lane%d" % i))

	# Multiplikator.
	for i in 4:
		var p := Vector2(380 + 60 * i, 1290)
		_lamp(p, 14.0, COL_BLUE, _lamp_state("mult%d" % (i + 2)))
		_text(p + Vector2(0, 6), "%dX" % (i + 2), 15, Color(1, 1, 1, 0.85), 60.0)

	# Treibstoff-Pfeile vor der Rampe.
	for i in 3:
		_arrow(Vector2(680, 1110 - 45 * i), -PI / 2, 16.0, COL_GREEN, _lamp_state("fuel%d" % i))

	# Saucer-Lampen.
	_lamp(Vector2(230, 840), 13.0, COL_RED, _lamp_state("launch"), "JACKPOT")
	_lamp(Vector2(230, 905), 11.0, COL_GOLD, _lamp_state("extra"), "EXTRA BALL")
	_arrow(Vector2(300, 800), -2.4, 14.0, COL_RED, _lamp_state("launch"))

	# Orbit-Pfeil und Ballretter.
	_arrow(Vector2(80, 560), -PI / 2, 14.0, COL_BLUE, _lamp_state("orbit"))
	_lamp(Vector2(CENTER_X, 1700), 14.0, COL_GOLD, _lamp_state("save"), "SHOOT AGAIN")

	# In-/Outlane-Markierungen.
	for side in 2:
		var p_out := Vector2(67, 1440)
		var p_in := Vector2(130, 1395)
		if side == 1:
			p_out = _m(p_out)
			p_in = _m(p_in)
		_lamp(p_out, 8.0, COL_RED, 0)
		_lamp(p_in, 8.0, COL_GREEN, 0)

	# Flipper.
	for f in flippers:
		var tip := f.tip()
		var dir := (tip - f.pivot).normalized()
		var side := dir.orthogonal()
		var poly := PackedVector2Array([
			f.pivot + side * f.rb, tip + side * f.rt, tip - side * f.rt, f.pivot - side * f.rb])
		draw_circle(f.pivot + Vector2(5, 7), f.rb, Color(0, 0, 0, 0.35))
		draw_colored_polygon(poly, Color(0.95, 0.95, 1.0))
		draw_circle(f.pivot, f.rb, Color(0.95, 0.95, 1.0))
		draw_circle(tip, f.rt, Color(0.95, 0.95, 1.0))
		draw_line(f.pivot + side * (f.rb - 3), tip + side * (f.rt - 3), COL_RUBBER, 5.0)
		draw_line(f.pivot - side * (f.rb - 3), tip - side * (f.rt - 3), COL_RUBBER, 5.0)
		draw_circle(f.pivot, 6, Color(0.3, 0.3, 0.4))

	# Plunger.
	var py := PLUNGER_Y + PLUNGER_TRAVEL * plunger_charge
	draw_rect(Rect2(908, py, 44, 10), Color(0.8, 0.8, 0.9))
	var coils := 8
	var bottom := H + 20.0
	for i in coils:
		var y0 := py + 10.0 + (bottom - py - 10.0) * i / coils
		var y1 := py + 10.0 + (bottom - py - 10.0) * (i + 1) / coils
		draw_line(Vector2(912, y0), Vector2(948, y1), Color(0.6, 0.6, 0.7), 3.0)

	# Ball unter der Rampe.
	if ball_mode != BallMode.RAMP:
		_draw_ball(1.0)

	# Rampe (liegt über dem Spielfeld).
	draw_polyline(ramp_points, Color(0.35, 0.8, 1.0, 0.12), 48.0)
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in ramp_points.size():
		var p0 := ramp_points[maxi(i - 1, 0)]
		var p1 := ramp_points[mini(i + 1, ramp_points.size() - 1)]
		var nrm := (p1 - p0).normalized().orthogonal()
		left.append(ramp_points[i] + nrm * 22.0)
		right.append(ramp_points[i] - nrm * 22.0)
	draw_polyline(left, Color(0.75, 0.9, 1.0, 0.8), 4.0)
	draw_polyline(right, Color(0.75, 0.9, 1.0, 0.8), 4.0)
	for i in range(0, ramp_points.size(), 1):
		draw_line(left[i], right[i], Color(0.75, 0.9, 1.0, 0.35), 2.0)

	if ball_mode == BallMode.RAMP:
		_draw_ball(1.25)


func _draw_ball(scale_f: float) -> void:
	if ball_mode == BallMode.NONE:
		return
	var r := BALL_R * scale_f
	for i in range(trail.size() - 1, 0, -1):
		draw_circle(trail[i], r * (1.0 - i * 0.12), Color(0.7, 0.8, 1.0, 0.06))
	draw_circle(ball_pos + Vector2(4, 6) * scale_f, r, Color(0, 0, 0, 0.4))
	draw_circle(ball_pos, r, Color(0.72, 0.74, 0.8))
	draw_circle(ball_pos - Vector2(2, 2), r * 0.8, Color(0.85, 0.87, 0.92))
	draw_circle(ball_pos - Vector2(4, 5) * scale_f, r * 0.35, Color(1, 1, 1, 0.95))
