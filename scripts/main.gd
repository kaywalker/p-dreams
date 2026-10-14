extends Node2D
## LIFTOFF – Spielablauf, Regeln, Eingabe (Touch + Tastatur) und Layout.
##
## Der Tisch wird so gedreht und skaliert, dass er den Bildschirm des
## Gaming-Tables optimal ausfüllt. Drehung per Taste R oder Touch-Button im
## Startbildschirm; die Einstellung wird gespeichert.

const TableScript := preload("res://scripts/table.gd")
const DmdScript := preload("res://scripts/dmd.gd")
const SfxScript := preload("res://scripts/sfx.gd")

enum State { ATTRACT, PLAYING, BONUS, GAME_OVER }

const BALLS_PER_GAME := 3
const BALL_SAVE_TIME := 10.0
const MAX_PLAYERS := 4
const CONFIG_PATH := "user://liftoff.cfg"
const CONTENT := Rect2(-20, -290, 1040, 2110)
const DMD_POS := Vector2(0, -268)

var world: Node2D
var table: Node2D
var dmd: Node2D
var sfx: Node
var overlay: Node2D

var state := State.ATTRACT
var state_time := 0.0
var paused := false
var rotation_deg := 90
var music_on := true
var autoplay := false
var screenshot_path := ""
var screenshot_frame := 240

# Spieler
var num_players := 1
var current := 0
var scores: Array[int] = []
var ball_no: Array[int] = []
var highscores: Array[int] = []

# Zustand des aktuellen Balls
var multiplier := 1
var bonus := 0
var lanes := [false, false, false]
var fuel := 0
var launch_lit := false
var extra_lit := false
var extra_used := false
var extra_balls := 0
var jackpot_value := 100000
var ball_save := 0.0
var ball_save_armed := true
var orbit_lit := 0.0
var drop_reset_timer := -1.0
var game_over_shown := false

# Anzeige-Meldungen: [{title, sub, time}]
var messages: Array[Dictionary] = []

# Eingabe
var touches := {}
var key_left := false
var key_right := false
var key_plunger := false
var _left_was := false
var _right_was := false

# Autoplay-Statistik (für Tests)
var _stats := {}
var _rng := RandomNumberGenerator.new()
var _auto_plunge_target := 0.8


func _ready() -> void:
	_rng.randomize()
	_load_config()
	_parse_args()
	world = Node2D.new()
	add_child(world)
	table = TableScript.new()
	world.add_child(table)
	dmd = DmdScript.new()
	dmd.position = DMD_POS
	world.add_child(dmd)
	overlay = Node2D.new()
	world.add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	sfx = SfxScript.new()
	sfx.music_on = music_on
	add_child(sfx)
	table.table_event.connect(_on_table_event)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_set_state(State.ATTRACT)
	if autoplay:
		_start_game(1)


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg == "--autoplay":
			autoplay = true
		elif arg.begins_with("--rotation="):
			rotation_deg = int(arg.get_slice("=", 1)) % 360
		elif arg == "--windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--screenshot-frame="):
			screenshot_frame = int(arg.get_slice("=", 1))
		elif arg == "--no-music":
			music_on = false


# ---------------------------------------------------------------- Layout

func _layout() -> void:
	var vp := get_viewport_rect().size
	var rotated := CONTENT.size
	if rotation_deg % 180 != 0:
		rotated = Vector2(CONTENT.size.y, CONTENT.size.x)
	var s := minf(vp.x / rotated.x, vp.y / rotated.y)
	var xf := Transform2D(deg_to_rad(rotation_deg), Vector2(s, s), 0.0, Vector2.ZERO)
	xf.origin = vp * 0.5 - xf.basis_xform(CONTENT.get_center())
	world.transform = xf


func _rotate_view() -> void:
	rotation_deg = (rotation_deg + 90) % 360
	_layout()
	_save_config()


# ---------------------------------------------------------------- Konfiguration

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	rotation_deg = int(cfg.get_value("settings", "rotation", rotation_deg))
	music_on = bool(cfg.get_value("settings", "music", music_on))
	var list: Array = cfg.get_value("scores", "top", [])
	highscores.clear()
	for v in list:
		highscores.append(int(v))


func _save_config() -> void:
	if autoplay:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "rotation", rotation_deg)
	cfg.set_value("settings", "music", music_on)
	cfg.set_value("scores", "top", highscores)
	cfg.save(CONFIG_PATH)


# ---------------------------------------------------------------- Spielablauf

func _set_state(s: State) -> void:
	state = s
	state_time = 0.0
	overlay.queue_redraw()


func _start_game(players: int) -> void:
	num_players = clampi(players, 1, MAX_PLAYERS)
	scores.clear()
	ball_no.clear()
	for i in num_players:
		scores.append(0)
		ball_no.append(1)
	current = 0
	jackpot_value = 100000
	messages.clear()
	game_over_shown = false
	sfx.play("start")
	_start_ball()


func _start_ball() -> void:
	multiplier = 1
	bonus = 0
	lanes = [false, false, false]
	lanes[_rng.randi_range(0, 2)] = true
	fuel = 0
	launch_lit = false
	extra_lit = false
	ball_save = 0.0
	ball_save_armed = true
	drop_reset_timer = -1.0
	table.reset_drops()
	table.serve_ball()
	_set_state(State.PLAYING)
	var title := "PLAYER %d" % (current + 1) if num_players > 1 else "BALL %d" % ball_no[current]
	_msg(title, "BALL %d - SHOOT!" % ball_no[current] if num_players > 1 else "SHOOT!", 2.0)


func _end_ball() -> void:
	_set_state(State.BONUS)
	sfx.play("drain")


func _finish_bonus() -> void:
	_add_score(bonus * multiplier, false)
	if extra_balls > 0:
		extra_balls -= 1
		_msg("SHOOT AGAIN", "SAME PLAYER", 2.0)
		_start_ball()
		return
	ball_no[current] += 1
	extra_used = false
	current = (current + 1) % num_players
	if ball_no[current] > BALLS_PER_GAME:
		_game_over()
	else:
		_start_ball()


func _game_over() -> void:
	table.remove_ball()
	_set_state(State.GAME_OVER)
	sfx.play("over")
	var new_best := false
	for sc in scores:
		if highscores.size() < 5 or sc > highscores[highscores.size() - 1]:
			highscores.append(sc)
			new_best = true
	highscores.sort()
	highscores.reverse()
	while highscores.size() > 5:
		highscores.pop_back()
	if new_best:
		_save_config()
	if autoplay:
		_stat("games", 1)
		print("[autoplay] Spiel beendet, Punkte: ", scores)


func _add_score(points: int, with_bonus := true) -> void:
	if state != State.PLAYING and state != State.BONUS:
		return
	scores[current] += points
	if with_bonus:
		bonus += points / 20


func _msg(title: String, sub := "", time := 1.6) -> void:
	messages.append({"title": title, "sub": sub, "time": time})
	while messages.size() > 3:
		messages.pop_front()


# ---------------------------------------------------------------- Tisch-Ereignisse

func _on_table_event(kind: String, id: int) -> void:
	_stat(kind, 1)
	if state != State.PLAYING:
		return
	match kind:
		"bumper":
			_add_score(1000)
			sfx.play("bumper", -2.0, 0.9 + 0.1 * id)
		"sling":
			_add_score(250)
			sfx.play("sling", -4.0)
		"drop":
			_add_score(2500)
			sfx.play("drop")
			if table.drops_down() == 3:
				_add_score(25000)
				drop_reset_timer = 1.2
				sfx.play("complete")
				if not extra_used and not extra_lit:
					extra_lit = true
					_msg("TARGETS!", "EXTRA BALL IS LIT", 2.0)
				else:
					_msg("TARGETS!", "25.000", 1.5)
		"lane":
			if not lanes[id]:
				lanes[id] = true
				_add_score(1000)
				sfx.play("lane")
			else:
				_add_score(200)
				sfx.play("lane", -8.0, 0.8)
			if lanes[0] and lanes[1] and lanes[2]:
				lanes = [false, false, false]
				_add_score(10000)
				sfx.play("complete")
				if multiplier < 5:
					multiplier += 1
					_msg("BONUS %dX" % multiplier, "STAR LANES COMPLETE", 1.8)
				else:
					_msg("STAR LANES", "50.000", 1.5)
					_add_score(40000)
		"inlane":
			_add_score(1000)
			sfx.play("lane", -6.0, 0.7)
		"outlane":
			_add_score(5000)
		"orbit":
			_add_score(5000 if orbit_lit <= 0.0 else 25000)
			_msg("ORBIT", _fmt(5000 if orbit_lit <= 0.0 else 25000), 1.2)
			orbit_lit = 0.0
			sfx.play("ramp", -6.0, 1.4)
		"ramp":
			fuel = mini(fuel + 1, 3)
			_add_score(10000 * fuel)
			bonus += 2000
			orbit_lit = 6.0
			sfx.play("ramp")
			if fuel >= 3 and not launch_lit:
				launch_lit = true
				_msg("FUEL FULL", "SHOOT HYPERSPACE!", 2.2)
			else:
				_msg("RAMP", "FUEL %d/3" % fuel if fuel < 3 else _fmt(30000), 1.4)
		"saucer":
			sfx.play("saucer")
			var any := false
			if launch_lit:
				any = true
				_add_score(jackpot_value)
				_msg("LIFTOFF!", "JACKPOT " + _fmt(jackpot_value), 2.6)
				jackpot_value += 50000
				launch_lit = false
				fuel = 0
				sfx.play("jackpot")
			if extra_lit:
				any = true
				extra_lit = false
				extra_used = true
				extra_balls += 1
				_msg("EXTRA BALL", "", 2.0)
				sfx.play("extra")
			if not any:
				_add_score(7500)
				_msg("HYPERSPACE", _fmt(7500), 1.2)
		"launch":
			sfx.play("launch", -3.0)
			if ball_save_armed:
				ball_save = BALL_SAVE_TIME
				ball_save_armed = false
		"drain":
			if ball_save > 0.0:
				ball_save = 0.0
				table.serve_ball()
				ball_save_armed = true
				_msg("BALL SAVED", "", 1.8)
				sfx.play("extra", -4.0)
			else:
				_end_ball()


func _stat(key: String, n: int) -> void:
	if autoplay:
		_stats[key] = int(_stats.get(key, 0)) + n


# ---------------------------------------------------------------- Schleife

func _physics_process(delta: float) -> void:
	if paused:
		return
	state_time += delta
	_update_controls()
	table.physics_step(delta)

	if ball_save > 0.0 and not table.in_lane:
		ball_save = maxf(0.0, ball_save - delta)
	orbit_lit = maxf(0.0, orbit_lit - delta)
	if drop_reset_timer > 0.0:
		drop_reset_timer -= delta
		if drop_reset_timer <= 0.0:
			table.reset_drops()
	if not messages.is_empty():
		messages[0]["time"] = float(messages[0]["time"]) - delta
		if float(messages[0]["time"]) <= 0.0:
			messages.pop_front()

	match state:
		State.BONUS:
			if state_time > 3.0:
				_finish_bonus()
		State.GAME_OVER:
			if state_time > 5.0:
				_set_state(State.ATTRACT)
				if autoplay:
					_start_game(1)

	if autoplay:
		_check_ball_sane()
		if OS.has_environment('PB_TRACE') and Engine.get_physics_frames() % 60 == 0:
			print('t=%.1f st=%s mode=%d pos=%s vel=%s lane=%s ch=%.2f' % [Engine.get_physics_frames()/120.0, State.keys()[state], table.ball_mode, table.ball_pos.round(), table.ball_vel.round(), table.in_lane, table.plunger_charge])


func _process(_delta: float) -> void:
	if screenshot_path != "" and Engine.get_process_frames() == screenshot_frame:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		get_tree().quit()
	_update_lamps()
	_update_dmd()
	if state == State.ATTRACT:
		overlay.queue_redraw()


func _update_controls() -> void:
	var left := key_left
	var right := key_right
	var plunger := key_plunger
	for side in touches.values():
		if side == "L":
			left = true
		else:
			right = true
			if table.ball_in_plunger():
				plunger = true
	if autoplay:
		var ai := _autoplay_controls()
		left = ai.x > 0.5
		right = ai.y > 0.5
		plunger = table.ball_in_plunger() and table.plunger_charge < _auto_plunge_target
	if state != State.PLAYING:
		left = false
		right = false
		plunger = false

	if left and not _left_was:
		sfx.play("flipper", -6.0, 1.05)
		_rotate_lanes(-1)
	if right and not _right_was:
		sfx.play("flipper", -6.0, 0.95)
		_rotate_lanes(1)
	if not left and _left_was:
		sfx.play("flipper", -14.0, 0.7)
	if not right and _right_was:
		sfx.play("flipper", -14.0, 0.7)
	_left_was = left
	_right_was = right
	table.set_flipper(0, left)
	table.set_flipper(1, right)
	var was_held: bool = table.plunger_held
	table.set_plunger(plunger)
	if autoplay and was_held and not plunger:
		_auto_plunge_target = _rng.randf_range(0.55, 1.0)


func _rotate_lanes(dir: int) -> void:
	if lanes[0] and lanes[1] and lanes[2]:
		return
	if dir < 0:
		lanes = [lanes[1], lanes[2], lanes[0]]
	else:
		lanes = [lanes[2], lanes[0], lanes[1]]


func _update_lamps() -> void:
	var l := {}
	for i in 3:
		l["lane%d" % i] = 1 if lanes[i] else 0
	for m in range(2, 6):
		l["mult%d" % m] = 1 if multiplier >= m else 0
	for i in 3:
		if i < fuel:
			l["fuel%d" % i] = 1
		elif i == fuel:
			l["fuel%d" % i] = 2
		else:
			l["fuel%d" % i] = 0
	l["launch"] = 2 if launch_lit else 0
	l["extra"] = 2 if extra_lit else 0
	l["orbit"] = 2 if orbit_lit > 0.0 else 0
	l["save"] = 2 if ball_save > 0.0 or (ball_save_armed and state == State.PLAYING) else (1 if extra_balls > 0 else 0)
	if state == State.ATTRACT:
		var phase := int(state_time * 6.0)
		for k in l.keys():
			l[k] = 1 if (phase + hash(k)) % 4 == 0 else 0
	table.lamps = l


# ---------------------------------------------------------------- Anzeige

static func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _update_dmd() -> void:
	dmd.clear()
	var blink := fmod(state_time, 0.4) < 0.2
	match state:
		State.ATTRACT:
			var page := int(state_time / 4.0) % 3
			if page == 0:
				dmd.text_center(2, "LIFTOFF", 2)
				dmd.text_center(20, "A PINBALL DREAM")
			elif page == 1:
				dmd.text_center(0, "HIGH SCORES")
				for i in mini(3, highscores.size()):
					dmd.text(14, 9 + i * 8, "%d." % (i + 1), 1, 2)
					dmd.text_right(114, 9 + i * 8, _fmt(highscores[i]))
				if highscores.is_empty():
					dmd.text_center(16, "NOCH KEINE", 1, 2)
			else:
				dmd.text_center(2, "PRESS START", 1, 3 if blink else 1)
				dmd.text_center(12, "TIPPE 1-4 SPIELER")
				dmd.text_center(22, "ODER TASTE 1-4", 1, 2)
		State.GAME_OVER:
			dmd.text_center(0, "GAME OVER", 1, 3)
			if num_players == 1:
				dmd.text_center(11, _fmt(scores[0]), 2)
			else:
				for i in num_players:
					var x := 2 + (i % 2) * 64
					var y := 10 + (i / 2) * 11
					dmd.text(x, y, "%d" % (i + 1), 1, 1)
					dmd.text_right(x + 62, y, _fmt(scores[i]))
		State.BONUS:
			dmd.text_center(0, "BONUS", 1)
			dmd.headline(10, "%s X %d" % [_fmt(bonus), multiplier])
			dmd.text_center(25, "= " + _fmt(bonus * multiplier), 1, 2)
		State.PLAYING:
			if paused:
				dmd.headline(8, "PAUSE")
				return
			if not messages.is_empty():
				var m: Dictionary = messages[0]
				var flash := float(m["time"]) > 0.6 or blink
				dmd.headline(3 if m["sub"] != "" else 9, str(m["title"]), 3 if flash else 2)
				if m["sub"] != "":
					dmd.text_center(23, str(m["sub"]), 1, 2)
				return
			dmd.text(1, 0, "PLAYER %d" % (current + 1), 1, 2)
			dmd.text_right(127, 0, "BALL %d" % ball_no[current], 1, 2)
			dmd.text_center(9, _fmt(scores[current]), 2)
			var status := "FUEL %d/3" % fuel
			if launch_lit:
				status = "JACKPOT " + _fmt(jackpot_value)
			elif ball_save > 0.0:
				status = "BALL SAVE %d" % ceili(ball_save)
			dmd.text(1, 25, status, 1, 2)
			dmd.text_right(127, 25, "%dX" % multiplier, 1, 2)


func _player_buttons() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in MAX_PLAYERS:
		out.append(Rect2(110 + i * 185, 1330, 160, 130))
	return out


func _rotate_button() -> Rect2:
	return Rect2(110, 1500, 345, 80)


func _music_button() -> Rect2:
	return Rect2(480, 1500, 345, 80)


func _draw_overlay() -> void:
	if state != State.ATTRACT:
		return
	var font := ThemeDB.fallback_font
	overlay.draw_rect(Rect2(80, 1250, 780, 360), Color(0.0, 0.0, 0.05, 0.75))
	overlay.draw_rect(Rect2(80, 1250, 780, 360), Color(0.35, 0.85, 1.0, 0.8), false, 3.0)
	overlay.draw_string(font, Vector2(80, 1305), "SPIELER WÄHLEN", HORIZONTAL_ALIGNMENT_CENTER, 780, 36,
		Color(1.0, 0.75, 0.25))
	var pulse := 0.6 + 0.4 * sin(state_time * 4.0)
	var buttons := _player_buttons()
	for i in buttons.size():
		var r := buttons[i]
		overlay.draw_rect(r, Color(0.1, 0.15, 0.35, 0.9))
		overlay.draw_rect(r, Color(0.35, 0.85, 1.0, pulse), false, 3.0)
		overlay.draw_string(font, r.position + Vector2(0, 80), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 72, Color.WHITE)
		overlay.draw_string(font, r.position + Vector2(0, 115), "SPIELER", HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 18, Color(0.7, 0.85, 1.0))
	for pair in [[_rotate_button(), "ANSICHT DREHEN (%d°)" % rotation_deg],
			[_music_button(), "MUSIK: " + ("AN" if music_on else "AUS")]]:
		var r: Rect2 = pair[0]
		overlay.draw_rect(r, Color(0.12, 0.1, 0.25, 0.9))
		overlay.draw_rect(r, Color(1.0, 0.6, 0.9, 0.7), false, 2.0)
		overlay.draw_string(font, r.position + Vector2(0, 50), pair[1], HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 24, Color.WHITE)


# ---------------------------------------------------------------- Eingabe

func _to_table(screen_pos: Vector2) -> Vector2:
	return world.get_global_transform().affine_inverse() * screen_pos


func _pointer_down(index: int, screen_pos: Vector2) -> void:
	var p := _to_table(screen_pos)
	match state:
		State.ATTRACT:
			var buttons := _player_buttons()
			for i in buttons.size():
				if buttons[i].has_point(p):
					_start_game(i + 1)
					return
			if _rotate_button().has_point(p):
				_rotate_view()
			elif _music_button().has_point(p):
				_toggle_music()
		State.PLAYING, State.BONUS:
			touches[index] = "L" if p.x < TableScript.CENTER_X else "R"


func _pointer_up(index: int) -> void:
	touches.erase(index)


func _toggle_music() -> void:
	music_on = not music_on
	sfx.music_on = music_on
	_save_config()
	overlay.queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			_pointer_down(te.index, te.position)
		else:
			_pointer_up(te.index)
	elif event is InputEventMouseButton:
		var me := event as InputEventMouseButton
		if me.button_index == MOUSE_BUTTON_LEFT:
			if me.pressed:
				_pointer_down(-1, me.position)
			else:
				_pointer_up(-1)
	elif event is InputEventKey:
		_key(event as InputEventKey)


func _key(e: InputEventKey) -> void:
	if e.echo:
		return
	var down := e.pressed
	match e.keycode:
		KEY_A, KEY_LEFT, KEY_Y, KEY_Z:
			key_left = down
		KEY_L, KEY_RIGHT:
			key_right = down
		KEY_SHIFT, KEY_CTRL:
			if e.location == KEY_LOCATION_RIGHT:
				key_right = down
			else:
				key_left = down
		KEY_SPACE, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER:
			if state == State.ATTRACT and down:
				_start_game(1)
			else:
				key_plunger = down
	if not down:
		return
	match e.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4:
			if state == State.ATTRACT:
				_start_game(e.keycode - KEY_0)
		KEY_R:
			_rotate_view()
		KEY_M:
			_toggle_music()
		KEY_P:
			if state == State.PLAYING:
				paused = not paused
		KEY_N:
			if state == State.PLAYING:
				table.nudge(Vector2(_rng.randf_range(-120, 120), -180))
		KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_ESCAPE:
			if state == State.ATTRACT:
				get_tree().quit()
			else:
				paused = false
				table.remove_ball()
				messages.clear()
				_set_state(State.ATTRACT)


# ---------------------------------------------------------------- Autoplay

## Einfacher Bot: flippert, wenn der Ball über einem Flipper ist. Liefert
## (links, rechts) als Vector2 mit 0/1.
func _autoplay_controls() -> Vector2:
	var out := Vector2.ZERO
	if table.ball_mode != table.BallMode.FREE:
		return out
	var p: Vector2 = table.ball_pos
	var v: Vector2 = table.ball_vel
	var pulse := fmod(table.time, 0.9) < 0.2
	if p.y > 1490.0 and p.y < 1640.0 and (v.y > 40.0 or pulse):
		if p.x < TableScript.CENTER_X and p.x > 300.0:
			out.x = 1.0
		elif p.x >= TableScript.CENTER_X and p.x < 640.0:
			out.y = 1.0
	return out


func _check_ball_sane() -> void:
	if table.ball_mode == table.BallMode.NONE:
		return
	var p: Vector2 = table.ball_pos
	if p.x < 20.0 or p.x > 980.0 or p.y < 0.0:
		push_error("Ball hat den Tisch verlassen: %s" % p)
		_stat("escaped", 1)
		table.remove_ball()
		_end_ball()


func _exit_tree() -> void:
	if autoplay:
		var sc := scores.duplicate()
		print("[autoplay] Statistik: ", _stats)
		print("[autoplay] Punkte: ", sc, " Status: ", State.keys()[state])
