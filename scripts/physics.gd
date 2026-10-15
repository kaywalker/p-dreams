extends Node
## LIFTOFF – Tischgeometrie und Ball-Physik (ohne Darstellung).
##
## Eigene 2D-Physik statt RigidBody2D: Mit 8 Substeps pro Tick bewegt sich ein
## Ball höchstens ~4 Einheiten pro Schritt und tunnelt nie durch Flipper oder
## Wände. Unterstützt mehrere Bälle (Multiball) inklusive Ball-Ball-Stößen.
## Rampen, Drahtbahnen und der Up-Kicker sind 3D-Pfade (`Track`), auf denen der
## Ball geführt fährt.
##
## Layout (von links nach rechts): linker Orbit mit Spinner, linke Rampe
## (führt auf den oberen Flipper), schräge Drop-Target-Bank, Scoop "Launch Pad"
## mit Up-Kicker, Standup-Tasche, rechte Rampe (führt in die linke Inlane),
## rechte Rücklaufbahn mit oberem Flipper. Oben: drei Lanes und drei Bumper.
##
## Koordinaten: Tisch 1000 x 1800 Einheiten, y zeigt zum Spieler. Die
## Darstellung (table_view.gd) liest den Zustand nur aus; Spielregeln liegen
## in main.gd und reagieren auf `table_event`.

signal table_event(kind: String, id: int, ball_id: int)

const W := 1000.0
const H := 1800.0
const CENTER_X := 470.0
const BALL_R := 14.0
const GRAVITY := 2300.0
const SUBSTEPS := 8
const MAX_SPEED := 4200.0
## Geringer Rollwiderstand: ~3 % Geschwindigkeitsverlust pro Sekunde, egal ob
## die Kugel frei rollt oder an einer Wand, einem Flipper oder einer Führung.
const ROLL_DAMPING_STEP := 0.99996
const BUMPER_KICK := 1050.0
const SLING_KICK := 900.0
const TRACK_SPEED := 1500.0
const RAMP_MIN_SPEED := 250.0
const SCOOP_POS := Vector2(470, 818)
const SCOOP_HOLD := 1.0
const LANE_X := 930.0
const PLUNGER_Y := 1704.0
const PLUNGER_TRAVEL := 40.0
const DRAIN_Y := 1840.0
const ARC_CENTER := Vector2(500, 480)
const ARC_RADIUS := 460.0
const SPINNER_Y := 760.0
const SPINNER_X0 := 44.0
const SPINNER_X1 := 106.0
const UPPER_FLIPPER := 2

enum Mode { FREE, TRACK, SCOOP }


class Seg:
	var a: Vector2
	var b: Vector2
	var kind: String
	var rest: float
	var thick: float
	var id: int
	var style := "metal"
	var active := true
	var flash := 0.0

	func _init(a_: Vector2, b_: Vector2, kind_: String, rest_: float, thick_: float, id_: int) -> void:
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

	func _init(c_: Vector2, r_: float, kind_: String, rest_: float, id_: int) -> void:
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
	var enabled := true

	func _init(pivot_: Vector2, rest_: float, up_: float, length_ := 118.0, rb_ := 17.0, rt_ := 9.0) -> void:
		pivot = pivot_
		rest_angle = rest_
		up_angle = up_
		angle = rest_
		length = length_
		rb = rb_
		rt = rt_

	func tip() -> Vector2:
		return pivot + Vector2.from_angle(angle) * length

	func step(dt: float) -> void:
		var up := pressed and enabled
		var target := up_angle if up else rest_angle
		var speed := 26.0 if up else 15.0
		var delta := clampf(target - angle, -speed * dt, speed * dt)
		angle += delta
		omega = delta / dt


class Sensor:
	var rect: Rect2
	var id: String
	var num: int

	func _init(rect_: Rect2, id_: String, num_: int) -> void:
		rect = rect_
		id = id_
		num = num_


## Geführte 3D-Bahn: Punkte (x, y, Höhe) in Tischeinheiten.
class Track:
	var name: String
	var points: PackedVector3Array
	var lengths := PackedFloat32Array()
	var total := 0.0
	var exit_vel: Vector2
	## Bis zu dieser Strecke Kunststofframpe, danach Drahtbahn.
	var plastic_end := 0.0

	## `ctrl` sind Stützpunkte; die Bahn wird als Catmull-Rom-Spline fein
	## abgetastet, damit Kurven rund statt eckig sind.
	func _init(name_: String, ctrl: PackedVector3Array, exit_vel_: Vector2, plastic_until: int) -> void:
		name = name_
		exit_vel = exit_vel_
		points = PackedVector3Array()
		var plastic_index := 0
		for i in ctrl.size() - 1:
			var p0 := ctrl[maxi(i - 1, 0)]
			var p1 := ctrl[i]
			var p2 := ctrl[i + 1]
			var p3 := ctrl[mini(i + 2, ctrl.size() - 1)]
			var n := maxi(2, int(p1.distance_to(p2) / 10.0))
			if i == plastic_until:
				plastic_index = points.size()
			for k in n:
				var t := float(k) / n
				points.append(_catmull(p0, p1, p2, p3, t))
		points.append(ctrl[ctrl.size() - 1])
		if plastic_until >= ctrl.size() - 1:
			plastic_index = points.size() - 1
		lengths.append(0.0)
		for i in range(1, points.size()):
			total += points[i - 1].distance_to(points[i])
			lengths.append(total)
		plastic_end = lengths[plastic_index]

	static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
		var t2 := t * t
		var t3 := t2 * t
		return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

	func point(dist: float) -> Vector3:
		for i in range(1, lengths.size()):
			if dist <= lengths[i]:
				var seg_len := lengths[i] - lengths[i - 1]
				var t := 0.0 if seg_len <= 0.0 else (dist - lengths[i - 1]) / seg_len
				return points[i - 1].lerp(points[i], t)
		return points[points.size() - 1]


class Ball:
	var id: int
	var pos: Vector2
	var vel := Vector2.ZERO
	var height := 0.0
	var mode := Mode.FREE
	var track: Track
	var track_dist := 0.0
	var hold := 0.0
	var stuck := 0.0
	var inside := PackedByteArray()
	## Drehung der Kugel für die Darstellung (rollt mit).
	var roll := Basis.IDENTITY

	func _init(id_: int, pos_: Vector2, sensor_count: int) -> void:
		id = id_
		pos = pos_
		inside.resize(sensor_count)


var walls: Array[Seg] = []
var circles: Array[Circ] = []
var flippers: Array[Flipper] = []
var sensors: Array[Sensor] = []
var drops: Array[Seg] = []
var standups: Array[Seg] = []
var slings: Array[Seg] = []
var balls: Array[Ball] = []
var tracks := {}
var gate: Seg
var plunger_floor: Seg
var arc_points := PackedVector2Array()

var plunger_charge := 0.0
var plunger_held := false
var spinner_angle := 0.0
var spinner_speed := 0.0
var kickback_lit := false
## Liegt ein Ball zu lange still, wird er angestupst (für Tests abschaltbar).
var auto_unstick := true
var time := 0.0

var _gate_side := 1.0
var _next_ball_id := 1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- Geometrie

func _m(v: Vector2) -> Vector2:
	return Vector2(2.0 * CENTER_X - v.x, v.y)


func _wall(a: Vector2, b: Vector2, style := "metal", kind := "wall", rest := 0.45, thick := 4.0, id := 0) -> Seg:
	var s := Seg.new(a, b, kind, rest, thick, id)
	s.style = style
	walls.append(s)
	return s


func _circ(c: Vector2, r: float, kind := "post", rest := 0.55, id := 0) -> Circ:
	var o := Circ.new(c, r, kind, rest, id)
	circles.append(o)
	return o


## Kreisbogen aus kurzen Wandstücken (Winkel in Bogenmaß, Bildschirmkoordinaten).
func _arc(center: Vector2, r: float, a0: float, a1: float, style := "metal", rest := 0.4) -> void:
	# Gerade Anzahl: am Scheitel liegt eine Spitze statt eines waagerechten Stücks.
	var steps := maxi(4, int(absf(a1 - a0) * r / 12.0))
	steps += steps % 2
	var prev := center + Vector2.from_angle(a0) * r
	for i in range(1, steps + 1):
		var p := center + Vector2.from_angle(lerpf(a0, a1, float(i) / steps)) * r
		_wall(prev, p, style, "wall", rest)
		prev = p


func _sensor(r: Rect2, id: String, num := 0) -> void:
	sensors.append(Sensor.new(r, id, num))


func _mirror_rect(r: Rect2) -> Rect2:
	return Rect2(2.0 * CENTER_X - r.position.x - r.size.x, r.position.y, r.size.x, r.size.y)


func _build() -> void:
	# Kuppel oben, über die ganze Breite inklusive Abschussrinne.
	var steps := 36
	for i in range(steps + 1):
		var ang := PI + PI * float(i) / steps
		arc_points.append(ARC_CENTER + Vector2(cos(ang), sin(ang)) * ARC_RADIUS)
	for i in range(steps):
		_wall(arc_points[i], arc_points[i + 1], "metal", "wall", 0.35)

	# Außenwände und Abschussrinne mit Einweg-Gate.
	_wall(Vector2(40, 480), Vector2(40, H + 80), "wood")
	_wall(Vector2(960, 480), Vector2(960, H + 80), "wood")
	_wall(Vector2(900, 560), Vector2(900, H + 80), "metal")
	_circ(Vector2(900, 560), 5.0, "pin", 0.4)
	gate = _wall(Vector2(902, 556), Vector2(958, 500), "gate", "gate", 0.3, 3.0)
	_gate_side = signf((gate.b - gate.a).cross(Vector2(800, 400) - gate.a))
	plunger_floor = _wall(Vector2(902, PLUNGER_Y), Vector2(958, PLUNGER_Y), "none", "plunger", 0.05, 4.0)

	# Abweiser über den Outlanes.
	_wall(Vector2(40, 1030), Vector2(88, 1200), "metal", "wall", 0.4)
	_wall(Vector2(900, 1120), Vector2(856, 1200), "metal", "wall", 0.4)

	# Linker Orbit mit Spinner, rechte Rücklaufbahn.
	_wall(Vector2(110, 560), Vector2(110, 900), "metal")
	_circ(Vector2(110, 560), 7.0, "post", 0.5)
	_circ(Vector2(110, 900), 7.0, "post", 0.5)
	_wall(Vector2(840, 560), Vector2(840, 880), "metal")
	_circ(Vector2(840, 560), 7.0, "post", 0.5)
	_circ(Vector2(840, 880), 7.0, "post", 0.5)
	_sensor(Rect2(42, 420, 66, 60), "orbit", 0)
	_sensor(Rect2(842, 420, 56, 60), "orbit", 1)

	# Out-/Inlane-Führungen und Slingshots (links bauen, rechts spiegeln).
	for side in 2:
		var f := func(v: Vector2) -> Vector2: return v if side == 0 else _m(v)
		# Outlane-Wand und Inlane-Führung mit gerundetem Übergang.
		_wall(f.call(Vector2(95, 1240)), f.call(Vector2(95, 1415)), "metal")
		var fc: Vector2 = f.call(Vector2(135, 1415.3))
		if side == 0:
			_arc(fc, 40.0, PI, deg_to_rad(116.6))
		else:
			_arc(fc, 40.0, 0.0, deg_to_rad(63.4))
		_wall(f.call(Vector2(117.1, 1451.1)), f.call(Vector2(337, 1561)), "metal")
		_circ(f.call(Vector2(95, 1240)), 6.0, "post")
		var a: Vector2 = f.call(Vector2(165, 1300))
		var b: Vector2 = f.call(Vector2(165, 1420))
		var c: Vector2 = f.call(Vector2(285, 1490))
		_wall(a, b, "none", "wall", 0.3)
		_wall(b, c, "none", "wall", 0.3)
		slings.append(_wall(c, a, "none", "sling", 0.6, 4.0, side))
		for p in [a, b, c]:
			_circ(p, 8.0, "post", 0.6)
	var outlane := Rect2(42, 1380, 50, 30)
	var inlane := Rect2(99, 1335, 60, 30)
	_sensor(outlane, "outlane", 0)
	_sensor(_mirror_rect(outlane), "outlane", 1)
	_sensor(inlane, "inlane", 0)
	_sensor(_mirror_rect(inlane), "inlane", 1)

	# Flipper: links, rechts und der obere rechte Flipper.
	flippers.append(Flipper.new(Vector2(345, 1580), 0.55, -0.45))
	flippers.append(Flipper.new(_m(Vector2(345, 1580)), PI - 0.55, PI + 0.45))
	flippers.append(Flipper.new(Vector2(836, 912), PI - 0.5, PI + 0.4, 70.0, 15.0, 8.0))

	# Pop-Bumper.
	_circ(Vector2(395, 500), 36.0, "bumper", 0.4, 0)
	_circ(Vector2(545, 500), 36.0, "bumper", 0.4, 1)
	_circ(Vector2(470, 612), 36.0, "bumper", 0.4, 2)

	# Obere Rollover-Lanes.
	for x in [350.0, 430.0, 510.0, 590.0]:
		_wall(Vector2(x, 300), Vector2(x, 362), "plastic", "wall", 0.4, 5.0)
	for i in 3:
		_sensor(Rect2(368 + 80 * i, 315, 44, 40), "lane", i)

	# Linke Rampe (Trichter), führt auf den oberen Flipper.
	_wall(Vector2(160, 945), Vector2(172, 775), "ramp")
	_wall(Vector2(252, 945), Vector2(242, 775), "ramp")
	_arc(Vector2(207, 775), 35.0, PI, TAU, "ramp", 0.25)
	_sensor(Rect2(180, 790, 56, 30), "ramp", 0)

	# Rechte Rampe (Trichter), führt in die linke Inlane.
	_wall(Vector2(628, 985), Vector2(640, 800), "ramp")
	_wall(Vector2(732, 985), Vector2(720, 800), "ramp")
	_arc(Vector2(680, 800), 40.0, PI, TAU, "ramp", 0.25)
	_sensor(Rect2(645, 812, 70, 30), "ramp", 1)

	# Schräge Drop-Target-Bank zwischen linker Rampe und Scoop.
	var p0 := Vector2(295, 892)
	var dir := (Vector2(400, 830) - p0).normalized()
	for i in 3:
		var a := p0 + dir * (i * 46.0)
		drops.append(_wall(a, a + dir * 38.0, "drop", "drop", 0.3, 5.0, i))

	# Scoop "Launch Pad" mit Gasse.
	_wall(Vector2(428, 905), Vector2(434, 805), "metal")
	_wall(Vector2(512, 905), Vector2(506, 805), "metal")
	_arc(Vector2(470, 805), 36.0, PI, TAU, "metal", 0.2)
	_circ(Vector2(428, 905), 6.0, "post")
	_circ(Vector2(512, 905), 6.0, "post")

	# Standup-Tasche zwischen Scoop und rechter Rampe.
	# Schräg gestellt und direkt am Scoop-Bogen angesetzt, damit kein Ball oben
	# liegen bleibt; rechts offen.
	var s0 := Vector2(470, 805) + Vector2.from_angle(deg_to_rad(-50.0)) * 36.0
	var sdir := (Vector2(594, 816) - s0).normalized()
	_wall(s0, s0 + sdir * 20.0, "metal", "wall", 0.3)
	for i in 3:
		var a := s0 + sdir * (22.0 + 30.0 * i)
		standups.append(_wall(a, a + sdir * 26.0, "standup", "standup", 0.35, 5.0, i))

	# Geführte Bahnen.
	tracks["ramp_left"] = Track.new("ramp_left", PackedVector3Array([
		Vector3(205, 775, 0), Vector3(200, 620, 80), Vector3(230, 470, 150), Vector3(330, 395, 175),
		Vector3(470, 385, 175), Vector3(620, 410, 170), Vector3(740, 480, 160), Vector3(800, 600, 135),
		Vector3(810, 720, 100), Vector3(807, 820, 45), Vector3(804, 895, 0),
	]), Vector2(-176, 96), 4)
	tracks["ramp_right"] = Track.new("ramp_right", PackedVector3Array([
		Vector3(680, 810, 0), Vector3(690, 640, 60), Vector3(660, 540, 100), Vector3(580, 490, 115),
		Vector3(470, 474, 115), Vector3(330, 486, 115), Vector3(210, 540, 110), Vector3(150, 640, 100),
		Vector3(138, 800, 80), Vector3(132, 1000, 55), Vector3(128, 1150, 25), Vector3(128, 1262, 0),
	]), Vector2(0, 450), 4)
	tracks["vuk"] = Track.new("vuk", PackedVector3Array([
		Vector3(470, 818, -14), Vector3(470, 818, 150), Vector3(470, 700, 175), Vector3(450, 520, 180),
		Vector3(420, 400, 160), Vector3(400, 320, 70), Vector3(392, 290, 0),
	]), Vector2(0, 150), 1)


# ---------------------------------------------------------------- Steuerung

func clear_balls() -> void:
	balls.clear()


func find_ball(id: int) -> Ball:
	for b in balls:
		if b.id == id:
			return b
	return null


func lane_occupied() -> bool:
	for b in balls:
		if b.pos.x > 900.0 and b.pos.y > 1300.0:
			return true
	return false


## Legt einen neuen Ball auf den Plunger. Liefert die Ball-ID.
func serve_ball() -> int:
	var b := Ball.new(_next_ball_id, Vector2(LANE_X, PLUNGER_Y - BALL_R - 6.0), sensors.size())
	_next_ball_id += 1
	balls.append(b)
	return b.id


func ball_in_plunger() -> bool:
	for b in balls:
		if _on_plunger(b):
			return true
	return false


func _on_plunger(b: Ball) -> bool:
	return b.mode == Mode.FREE and b.pos.x > 900.0 and b.pos.y > PLUNGER_Y - 70.0


## Schießt alle Bälle auf dem Plunger mit Stärke 0..1 ab.
func launch(power: float) -> void:
	for b in balls:
		if _on_plunger(b):
			b.pos.y = PLUNGER_Y - BALL_R - 6.0
			b.vel = Vector2(0, -(2200.0 + 1100.0 * power))
			table_event.emit("launch", int(power * 100.0), b.id)


func set_flipper(index: int, pressed: bool) -> void:
	flippers[index].pressed = pressed
	if index == 1:
		flippers[UPPER_FLIPPER].pressed = pressed


func set_flippers_enabled(on: bool) -> void:
	for f in flippers:
		f.enabled = on


func set_plunger(held: bool) -> void:
	if plunger_held and not held:
		launch(plunger_charge)
		plunger_charge = 0.0
	plunger_held = held


func set_scoop_hold(ball_id: int, seconds: float) -> void:
	var b := find_ball(ball_id)
	if b and b.mode == Mode.SCOOP:
		b.hold = seconds


func nudge(dir: Vector2) -> void:
	for b in balls:
		if b.mode == Mode.FREE and not _on_plunger(b):
			b.vel += dir


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


# ---------------------------------------------------------------- Physik

func physics_step(delta: float) -> void:
	time += delta
	for c in circles:
		c.flash = maxf(0.0, c.flash - delta)
		c.cooldown = maxf(0.0, c.cooldown - delta)
	for w in walls:
		w.flash = maxf(0.0, w.flash - delta)

	if plunger_held:
		plunger_charge = minf(1.0, plunger_charge + delta * 1.2)
	var floor_y := PLUNGER_Y + PLUNGER_TRAVEL * plunger_charge
	plunger_floor.a.y = floor_y
	plunger_floor.b.y = floor_y

	# Spinner dreht aus und meldet jede halbe Umdrehung.
	var before := int(spinner_angle / PI)
	spinner_angle += spinner_speed * delta
	spinner_speed *= exp(-1.6 * delta)
	if spinner_speed < 0.6:
		spinner_speed = 0.0
		spinner_angle = lerpf(spinner_angle, roundf(spinner_angle / PI) * PI, 0.1)
	if int(spinner_angle / PI) != before:
		table_event.emit("spinner", 0, 0)

	var dt := delta / SUBSTEPS
	var drained: Array[Ball] = []
	for _i in SUBSTEPS:
		for f in flippers:
			f.step(dt)
		for b in balls:
			if b.mode != Mode.FREE or drained.has(b):
				continue
			var prev := b.pos
			b.vel.y += GRAVITY * dt
			b.vel *= ROLL_DAMPING_STEP
			var sp := b.vel.length()
			if sp > MAX_SPEED:
				b.vel *= MAX_SPEED / sp
			b.pos += b.vel * dt
			_collide(b)
			_check_spinner(b, prev)
			_check_sensors(b)
			if b.pos.y > DRAIN_Y:
				drained.append(b)
		_collide_balls()

	for b in balls:
		match b.mode:
			Mode.TRACK:
				_step_track(b, delta)
			Mode.SCOOP:
				_step_scoop(b, delta)
			Mode.FREE:
				_check_stuck(b, delta)
				b.height = 0.0
		_update_roll(b, delta)

	for b in drained:
		balls.erase(b)
		table_event.emit("drain", 0, b.id)


func _update_roll(b: Ball, delta: float) -> void:
	var v := b.vel if b.mode == Mode.FREE else Vector2.ZERO
	if b.mode == Mode.TRACK:
		var ahead: Vector3 = b.track.point(b.track_dist + 5.0)
		v = (Vector2(ahead.x, ahead.y) - b.pos).normalized() * TRACK_SPEED
	var speed := v.length()
	if speed < 1.0:
		return
	# Rollachse liegt waagerecht, senkrecht zur Bewegung (3D: x, z = Tisch x, y).
	var axis := Vector3(v.y, 0.0, -v.x).normalized()
	b.roll = (Basis(axis, speed * delta / BALL_R) * b.roll).orthonormalized()


func _check_stuck(b: Ball, delta: float) -> void:
	var cradled := false
	for f in flippers:
		if f.pressed and b.pos.distance_to(f.pivot) < f.length + 30.0:
			cradled = true
	if auto_unstick and b.vel.length() < 8.0 and not _on_plunger(b) and not cradled:
		b.stuck += delta
		if b.stuck > 3.0:
			b.vel += Vector2(_rng.randf_range(-250, 250), -500)
			b.stuck = 0.0
	else:
		b.stuck = 0.0


func _resolve(b: Ball, n: Vector2, pen: float, rest: float, surf_vel := Vector2.ZERO) -> float:
	b.pos += n * pen
	var rel := b.vel - surf_vel
	var vn := rel.dot(n)
	if vn >= 0.0:
		return 0.0
	# Echter Stoß: Rückprall und etwas Reibung. Rollender Kontakt (kleine
	# Normalgeschwindigkeit, passiert in jedem Substep): keine Reibung, sonst
	# bremst jede Wand die Kugel auf eine künstliche Endgeschwindigkeit ab.
	var impact := -vn > 60.0
	var e := rest if impact else 0.0
	var vt := rel - n * vn
	rel = vt * (0.97 if impact else 1.0) - n * vn * e
	b.vel = rel + surf_vel
	return -vn


func _collide(b: Ball) -> void:
	for w in walls:
		if not w.active:
			continue
		if w == gate and signf((gate.b - gate.a).cross(b.pos - gate.a)) != _gate_side:
			continue
		var ab := w.b - w.a
		var t := clampf((b.pos - w.a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := b.pos - (w.a + ab * t)
		var rr := BALL_R + w.thick
		var dist2 := d.length_squared()
		if dist2 >= rr * rr or dist2 < 1e-8:
			continue
		var dist := sqrt(dist2)
		var n := d / dist
		var impact := _resolve(b, n, rr - dist, w.rest)
		match w.kind:
			"sling":
				if impact > 60.0 and t > 0.1 and t < 0.9:
					b.vel += n * SLING_KICK
					w.flash = 0.15
					table_event.emit("sling", w.id, b.id)
			"drop":
				if impact > 30.0:
					w.active = false
					w.flash = 0.3
					table_event.emit("drop", w.id, b.id)
			"standup":
				if impact > 40.0 and w.flash <= 0.0:
					w.flash = 0.25
					table_event.emit("standup", w.id, b.id)

	for c in circles:
		var d := b.pos - c.c
		var rr := BALL_R + c.r
		var dist2 := d.length_squared()
		if dist2 >= rr * rr or dist2 < 1e-8:
			continue
		var dist := sqrt(dist2)
		var n := d / dist
		var impact := _resolve(b, n, rr - dist, c.rest)
		if c.kind == "bumper" and c.cooldown <= 0.0:
			b.vel += n * maxf(0.0, BUMPER_KICK - b.vel.dot(n))
			c.cooldown = 0.06
			c.flash = 0.18
			table_event.emit("bumper", c.id, b.id)
		elif c.kind == "post" and impact > 400.0:
			c.flash = 0.1

	for f in flippers:
		var tip := f.tip()
		var ab := tip - f.pivot
		var t := clampf((b.pos - f.pivot).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var cp := f.pivot + ab * t
		var rad := lerpf(f.rb, f.rt, t)
		var d := b.pos - cp
		var rr := BALL_R + rad
		var dist2 := d.length_squared()
		if dist2 >= rr * rr or dist2 < 1e-8:
			continue
		var dist := sqrt(dist2)
		var n := d / dist
		var contact := cp + n * rad - f.pivot
		var surf := Vector2(-contact.y, contact.x) * f.omega
		_resolve(b, n, rr - dist, 0.3, surf)


func _collide_balls() -> void:
	for i in balls.size():
		var a := balls[i]
		if a.mode != Mode.FREE:
			continue
		for j in range(i + 1, balls.size()):
			var b := balls[j]
			if b.mode != Mode.FREE:
				continue
			var d := b.pos - a.pos
			var dist2 := d.length_squared()
			var rr := BALL_R * 2.0
			if dist2 >= rr * rr or dist2 < 1e-8:
				continue
			var dist := sqrt(dist2)
			var n := d / dist
			var pen := (rr - dist) * 0.5
			a.pos -= n * pen
			b.pos += n * pen
			var rel := (b.vel - a.vel).dot(n)
			if rel < 0.0:
				var imp := -1.9 * rel * 0.5
				a.vel -= n * imp
				b.vel += n * imp


func _check_spinner(b: Ball, prev: Vector2) -> void:
	if b.pos.x < SPINNER_X0 or b.pos.x > SPINNER_X1:
		return
	if (prev.y - SPINNER_Y) * (b.pos.y - SPINNER_Y) <= 0.0 and prev.y != b.pos.y:
		spinner_speed = clampf(absf(b.vel.y) / 60.0, 6.0, 45.0)


func _check_sensors(b: Ball) -> void:
	for i in sensors.size():
		var s := sensors[i]
		var inside := s.rect.has_point(b.pos)
		if inside and b.inside[i] == 0:
			_on_sensor(b, s)
		b.inside[i] = 1 if inside else 0
		if b.mode != Mode.FREE:
			return

	if b.pos.distance_to(SCOOP_POS) < 18.0 and b.vel.length() < 3000.0:
		for other in balls:
			if other != b and other.mode == Mode.SCOOP:
				return
		b.mode = Mode.SCOOP
		b.pos = SCOOP_POS
		b.vel = Vector2.ZERO
		b.height = -14.0
		b.hold = SCOOP_HOLD
		table_event.emit("scoop", 0, b.id)


func _start_track(b: Ball, name: String) -> void:
	b.mode = Mode.TRACK
	b.track = tracks[name]
	b.track_dist = 0.0


func _on_sensor(b: Ball, s: Sensor) -> void:
	match s.id:
		"ramp":
			if b.vel.y < -RAMP_MIN_SPEED:
				_start_track(b, "ramp_left" if s.num == 0 else "ramp_right")
				table_event.emit("ramp", s.num, b.id)
		"orbit":
			if b.vel.y < 0.0:
				table_event.emit("orbit", s.num, b.id)
		"outlane":
			if s.num == 0 and kickback_lit:
				kickback_lit = false
				b.vel = Vector2(_rng.randf_range(10, 40), -2900)
				table_event.emit("kickback", 0, b.id)
			else:
				table_event.emit("outlane", s.num, b.id)
		_:
			table_event.emit(s.id, s.num, b.id)


func _step_track(b: Ball, delta: float) -> void:
	b.track_dist += TRACK_SPEED * delta
	var tr := b.track
	if b.track_dist >= tr.total:
		var end := tr.points[tr.points.size() - 1]
		b.pos = Vector2(end.x, end.y)
		b.height = 0.0
		b.vel = tr.exit_vel
		b.mode = Mode.FREE
		b.inside.fill(0)
		table_event.emit("track_exit", 0, b.id)
		return
	var p := tr.point(b.track_dist)
	b.pos = Vector2(p.x, p.y)
	b.height = p.z


func _step_scoop(b: Ball, delta: float) -> void:
	b.hold -= delta
	if b.hold <= 0.0:
		_start_track(b, "vuk")
		table_event.emit("vuk", 0, b.id)
