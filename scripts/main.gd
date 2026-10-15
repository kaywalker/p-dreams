extends Node2D
## LIFTOFF – Spielablauf, Regeln, Eingabe (Touch + Tastatur) und Layout.
##
## Aufbau: Die Physik (physics.gd) simuliert den Tisch, table_view.gd zeigt ihn
## in 3D (gerendert in einen SubViewport), display.gd ist das Farb-Display.
## Alles zusammen liegt in `world`, das gedreht und skaliert wird, damit der
## Tisch den Bildschirm des Gaming-Tables optimal ausfüllt.

const Phys := preload("res://scripts/physics.gd")
const ViewScript := preload("res://scripts/table_view.gd")
const ArtScript := preload("res://scripts/playfield_art.gd")
const DisplayScript := preload("res://scripts/display.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const Layout := preload("res://scripts/layout.gd")

enum State { ATTRACT, PLAYING, BONUS, GAME_OVER }

const BALLS_PER_GAME := 3
const BALL_SAVE_TIME := 10.0
const MULTIBALL_SAVE_TIME := 15.0
const MISSION_TIME := 30.0
const MAX_PLAYERS := 4
const CONFIG_PATH := "user://liftoff.cfg"
const DISPLAY_POS := Vector2(0, -330)
const CONTENT := Rect2(-70, -340, 1140, 2230)
const MISSIONS := ["METEOR STORM", "STERNJAGD", "GRAVITY"]
const MISSION_HINT := ["BUMPER = 10.000", "LILA PFEILE = 50.000", "TARGETS = 25.000"]

var world: Node2D
var phys: Node
var view: Node3D
var display: Node2D
var sfx: Node
var overlay: Node2D
var view_vp: SubViewport
var view_sprite: Sprite2D
var art_vp: SubViewport

var state := State.ATTRACT
var state_time := 0.0
var paused := false
var rotation_deg := 90
var music_on := true
var low_quality := false
var autoplay := false
var screenshot_path := ""
var screenshot_frame := 240

# Spieler
var num_players := 1
var current := 0
var scores: Array[int] = []
var ball_no: Array[int] = []
var p_locks: Array[int] = []
var p_mission: Array[int] = []
var highscores: Array[int] = []
var new_high := false

# Zustand des aktuellen Balls
var multiplier := 1
var bonus := 0
var lanes := [false, false, false]
var fuel := 0
var lock_lit := false
var multiball := false
var super_lit := false
var jackpot_value := 250000
var jackpot_shots: Array = []
var mission_shots: Array = []
var stand_lit := [false, false, false]
var stand_banks := 0
var upper_timer := 0.0
var mission_lit := false
var mission_active := -1
var mission_time := 0.0
var mission_score := 0
var extra_lit := false
var extra_balls := 0
var ball_save := 0.0
var ball_save_armed := true
var skill_pending := true
var skill_lane := 0
var skill_window := 0.0
var combo_timer := 0.0
var combo_last := ""
var combo_count := 0
var inlane_lit := [0.0, 0.0]
var tilt_level := 0.0
var tilted := false
var drop_reset_timer := -1.0
var serve_queue := 0
var serve_timer := 0.0
var auto_launch := 0
var auto_launch_timer := 0.0

# Eingabe
var touches := {}
## Gehaltene Tasten: "Code:Position" -> {side: "L"/"R"/"P", code, physical}.
## Jede Taste einzeln, damit z. B. A und Pfeil-links sich nicht gegenseitig
## loslassen; wird jedes Frame mit dem echten Tastaturzustand abgeglichen.
var held_keys := {}
var _left_was := false
var _right_was := false

var _stats := {}
var _rng := RandomNumberGenerator.new()
var _auto_plunge_target := 0.8
var _insert_pos := {}


func _ready() -> void:
	_rng.randomize()
	_load_config()
	_parse_args()
	for ins in Layout.inserts():
		_insert_pos[ins["key"]] = ins["pos"]

	phys = Phys.new()
	add_child(phys)
	phys.table_event.connect(_on_table_event)

	# Spielfelddruck einmalig in eine Textur rendern.
	art_vp = SubViewport.new()
	art_vp.size = Vector2i(1500, 2700)
	art_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	art_vp.disable_3d = true
	var art := ArtScript.new()
	art.scale = Vector2(1.5, 1.5)
	art_vp.add_child(art)
	add_child(art_vp)

	# 3D-Tisch in eigenem SubViewport.
	view_vp = SubViewport.new()
	view_vp.own_world_3d = true
	view_vp.msaa_3d = Viewport.MSAA_DISABLED if low_quality else Viewport.MSAA_4X
	view_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view = ViewScript.new()
	view_vp.add_child(view)
	add_child(view_vp)
	view.setup(phys, art_vp.get_texture())

	world = Node2D.new()
	add_child(world)
	view_sprite = Sprite2D.new()
	view_sprite.centered = false
	view_sprite.texture = view_vp.get_texture()
	view_sprite.position = Layout.VIEW.position
	world.add_child(view_sprite)
	display = DisplayScript.new()
	display.position = DISPLAY_POS
	world.add_child(display)
	overlay = Node2D.new()
	world.add_child(overlay)
	overlay.draw.connect(_draw_overlay)

	sfx = SfxScript.new()
	sfx.music_on = music_on
	add_child(sfx)

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
		elif arg == "--no-music":
			music_on = false
		elif arg == "--low":
			low_quality = true
		elif arg.begins_with("--screenshot="):
			screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--screenshot-frame="):
			screenshot_frame = int(arg.get_slice("=", 1))


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
	# 3D-Auflösung passend zur Bildschirmgröße (Pixel 1:1).
	var px := Layout.VIEW.size * s
	var cap := 1400.0 if low_quality else 2600.0
	if px.y > cap:
		px *= cap / px.y
	view_vp.size = Vector2i(maxi(64, int(px.x)), maxi(64, int(px.y)))
	view_sprite.scale = Layout.VIEW.size / Vector2(view_vp.size)


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
	p_locks.clear()
	p_mission.clear()
	for i in num_players:
		scores.append(0)
		ball_no.append(1)
		p_locks.append(0)
		p_mission.append(0)
	current = 0
	jackpot_value = 250000
	new_high = false
	extra_balls = 0
	stand_banks = 0
	display.clear_callouts()
	sfx.play("start")
	_start_ball()


func _start_ball() -> void:
	multiplier = 1
	bonus = 0
	lanes = [false, false, false]
	fuel = 0
	lock_lit = false
	multiball = false
	super_lit = false
	mission_lit = false
	mission_active = -1
	extra_lit = false
	ball_save = 0.0
	ball_save_armed = true
	skill_pending = true
	skill_lane = _rng.randi_range(0, 2)
	skill_window = 0.0
	combo_timer = 0.0
	upper_timer = 0.0
	jackpot_shots.clear()
	mission_shots.clear()
	stand_lit = [false, false, false]
	tilt_level = 0.0
	tilted = false
	drop_reset_timer = -1.0
	serve_queue = 0
	auto_launch = 0
	phys.kickback_lit = true
	phys.set_flippers_enabled(true)
	phys.clear_balls()
	phys.reset_drops()
	phys.serve_ball()
	_set_state(State.PLAYING)
	var title := "SPIELER %d" % (current + 1) if num_players > 1 else "BALL %d" % ball_no[current]
	display.callout(title, "SKILL SHOT: BLINKENDE LANE TREFFEN!", Color(0.5, 0.9, 1.0), 2.2, "info")


func _end_ball() -> void:
	mission_active = -1
	multiball = false
	_set_state(State.BONUS)
	sfx.play("drain")
	if tilted:
		bonus = 0


func _finish_bonus() -> void:
	_add_score(bonus * multiplier, false)
	if extra_balls > 0:
		extra_balls -= 1
		_start_ball()
		display.callout("SHOOT AGAIN", "GLEICHER SPIELER", Color(1.0, 0.8, 0.3), 2.0)
		return
	ball_no[current] += 1
	current = (current + 1) % num_players
	if ball_no[current] > BALLS_PER_GAME:
		_game_over()
	else:
		_start_ball()


func _game_over() -> void:
	phys.clear_balls()
	_set_state(State.GAME_OVER)
	sfx.play("over")
	for sc in scores:
		if highscores.size() < 5 or sc > highscores[highscores.size() - 1]:
			highscores.append(sc)
			new_high = true
	highscores.sort()
	highscores.reverse()
	while highscores.size() > 5:
		highscores.pop_back()
	if new_high:
		_save_config()
	if autoplay:
		_stat("games", 1)
		print("[autoplay] Spiel beendet, Punkte: ", scores)


func _add_score(points: int, with_bonus := true) -> void:
	if state != State.PLAYING and state != State.BONUS:
		return
	if tilted:
		return
	scores[current] += points
	if mission_active >= 0:
		mission_score += points
	if with_bonus:
		bonus += points / 20


func _callout(title: String, sub := "", col := Color(1.0, 0.8, 0.25), time := 1.6, style := "normal") -> void:
	display.callout(title, sub, col, time, style)


func _serve_extra(count: int) -> void:
	serve_queue += count
	auto_launch += count


# ---------------------------------------------------------------- Tisch-Ereignisse

func _on_table_event(kind: String, id: int, ball_id: int) -> void:
	_stat(kind, 1)
	if state != State.PLAYING:
		return
	if tilted and kind != "drain":
		return
	if skill_window > 0.0 and kind not in ["launch", "lane", "spinner", "orbit"]:
		skill_window = 0.0
	match kind:
		"bumper":
			_add_score(10000 if mission_active == 0 else 1000)
			sfx.play("bumper", -2.0, 0.9 + 0.1 * id)
			if mission_active == 0:
				view.flash("both", 0.3)
		"sling":
			_add_score(250)
			sfx.play("sling", -4.0)
		"spinner":
			_add_score(500 if mission_active == 1 else 100)
			sfx.play("spinner", -10.0, 1.0 + _rng.randf_range(-0.05, 0.05))
		"drop":
			_add_score(25000 if mission_active == 2 else 2500)
			sfx.play("drop")
			if mission_active == 2:
				drop_reset_timer = 0.4
			if phys.drops_down() == 3:
				_drop_bank_complete()
		"standup":
			_on_standup(id)
		"lane":
			_on_lane(id)
		"inlane":
			_add_score(1000)
			inlane_lit[id] = 1.5
			sfx.play("lane", -6.0, 0.7)
		"outlane":
			_add_score(5000)
		"kickback":
			_add_score(5000)
			_callout("KICKBACK", "", Color(1.0, 0.3, 0.3), 1.0, "info")
			sfx.play("kickback")
			view.flash("left", 0.8)
		"orbit":
			_add_score(5000)
			sfx.play("ramp", -6.0, 1.4)
			view.flash("right" if id == 0 else "left", 0.5)
			_shot("lorb" if id == 0 else "rorb")
		"ramp":
			sfx.play("ramp")
			view.flash("left" if id == 1 else "right", 0.6)
			bonus += 2000
			_on_ramp(id)
		"track_exit":
			if phys.find_ball(ball_id) and phys.find_ball(ball_id).pos.x > 700.0:
				upper_timer = 3.0
		"scoop":
			_on_scoop(ball_id)
		"vuk":
			sfx.play("kickback", -2.0, 1.4)
			view.rocket_shake = maxf(view.rocket_shake, 0.4)
		"launch":
			sfx.play("launch", -3.0)
			if ball_save_armed:
				ball_save = BALL_SAVE_TIME
				ball_save_armed = false
			if skill_pending:
				skill_pending = false
				skill_window = 5.0
		"drain":
			_on_drain()


## Zentrale Auswertung der fünf Hauptschüsse: Jackpots, Missionen, Combos.
func _shot(key: String) -> void:
	var combo := combo_timer > 0.0 and combo_last != key and key != "rorb"
	if combo:
		combo_count += 1
		var pts := 25000 * combo_count
		_add_score(pts)
		_callout("COMBO x%d" % combo_count, DisplayScript.fmt(pts), Color(0.3, 0.95, 1.0), 1.4)
		sfx.play("complete", -2.0, 1.1 + 0.1 * combo_count)
	else:
		combo_count = 0
	if key != "rorb":
		combo_last = key
		combo_timer = 3.0
	if multiball and jackpot_shots.has(key):
		jackpot_shots.erase(key)
		_add_score(jackpot_value)
		_callout("JACKPOT!", DisplayScript.fmt(jackpot_value), Color(1.0, 0.3, 0.4), 2.0, "big")
		jackpot_value += 25000
		sfx.play("jackpot")
		view.flash("both", 1.0)
		view.shake = 0.8
		view.rocket_shake = 1.0
		if jackpot_shots.is_empty() and not super_lit:
			super_lit = true
			_callout("SUPER JACKPOT", "LAUNCH PAD IST BEREIT", Color(1.0, 0.3, 0.9), 1.8)
	elif mission_active == 1 and mission_shots.has(key):
		mission_shots.erase(key)
		_add_score(50000)
		_callout("STERN GEFANGEN", "50.000", Color(1.0, 0.35, 0.9), 1.2, "info")
		sfx.play("complete", 0.0, 1.3)
		_pick_mission_shot(key)


func _pick_mission_shot(exclude: String) -> void:
	var pool := ["lorb", "lramp", "scoop", "pocket", "rramp"]
	pool.erase(exclude)
	for k in mission_shots:
		pool.erase(k)
	if not pool.is_empty():
		mission_shots.append(pool[_rng.randi_range(0, pool.size() - 1)])


func _on_lane(id: int) -> void:
	if skill_window > 0.0:
		skill_window = 0.0
		if id == skill_lane:
			_add_score(75000)
			_callout("SKILL SHOT!", "75.000", Color(0.4, 1.0, 0.6), 2.0, "big")
			sfx.play("jackpot", -2.0, 1.2)
			view.flash("both", 1.0)
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
		phys.kickback_lit = true
		if multiplier < 5:
			multiplier += 1
			_callout("BONUS %dX" % multiplier, "SKY LANES KOMPLETT", Color(0.4, 0.7, 1.0))
		else:
			_add_score(40000)
			_callout("SKY LANES", "50.000", Color(0.4, 0.7, 1.0))


func _on_standup(id: int) -> void:
	_add_score(25000 if mission_active == 2 else 2000)
	sfx.play("drop", -2.0, 1.4)
	if not stand_lit[id]:
		stand_lit[id] = true
	if stand_lit[0] and stand_lit[1] and stand_lit[2]:
		stand_lit = [false, false, false]
		stand_banks += 1
		jackpot_value += 100000
		_add_score(20000)
		sfx.play("complete")
		if stand_banks == 2 and not extra_lit:
			extra_lit = true
			_callout("EXTRA BALL", "LEUCHTET AM LAUNCH PAD", Color(1.0, 0.8, 0.2), 2.0)
		else:
			_callout("STARGATE", "JACKPOT +100.000", Color(0.3, 0.95, 1.0), 1.6)
	_shot("pocket")


func _on_ramp(side: int) -> void:
	_shot("lramp" if side == 0 else "rramp")
	if multiball or mission_active == 1:
		return
	if lock_lit:
		_add_score(30000)
		_callout("RAMPE", "LOCK LEUCHTET – LAUNCH PAD!", Color(1.0, 0.7, 0.2), 1.3, "info")
		return
	fuel = mini(fuel + 1, 3)
	_add_score(10000 * fuel)
	if fuel >= 3:
		lock_lit = true
		_callout("LOCK IS LIT", "SCHIESS AUFS LAUNCH PAD", Color(1.0, 0.7, 0.2), 2.0)
		sfx.play("complete")
	else:
		_callout("RAMPE", "TREIBSTOFF %d/3" % fuel, Color(0.4, 1.0, 0.6), 1.2, "info")


func _on_scoop(ball_id: int) -> void:
	sfx.play("saucer")
	view.rocket_shake = maxf(view.rocket_shake, 0.6)
	if upper_timer > 0.0:
		upper_timer = 0.0
		_add_score(50000)
		_callout("UPPER COMBO", "50.000", Color(0.3, 0.95, 1.0), 1.4)
	_shot("scoop")
	var hold := 1.0
	var handled := false
	if multiball and super_lit:
		handled = true
		super_lit = false
		var pts := jackpot_value * 4
		_add_score(pts)
		_callout("SUPER JACKPOT!", DisplayScript.fmt(pts), Color(1.0, 0.3, 0.9), 2.6, "big")
		sfx.play("jackpot")
		view.flash("both", 1.0)
		view.shake = 1.0
		view.rocket_shake = 1.0
		jackpot_shots = ["lorb", "lramp", "scoop", "pocket", "rramp"]
		hold = 2.4
	elif lock_lit and not multiball:
		handled = true
		lock_lit = false
		fuel = 0
		p_locks[current] += 1
		if p_locks[current] >= 2:
			p_locks[current] = 0
			_start_multiball()
			hold = 2.8
		else:
			_callout("BALL 1 GESPERRT", "NOCH EIN LOCK BIS MULTIBALL", Color(1.0, 0.7, 0.2), 2.0)
			sfx.play("complete")
			hold = 1.6
	if mission_lit and mission_active < 0 and not multiball:
		handled = true
		mission_lit = false
		_start_mission()
		hold = maxf(hold, 2.0)
	if extra_lit:
		handled = true
		extra_lit = false
		extra_balls += 1
		_callout("EXTRA BALL", "", Color(1.0, 0.8, 0.2), 2.2, "big")
		sfx.play("extra")
		hold = maxf(hold, 2.0)
	if not handled:
		_add_score(7500)
		_callout("LAUNCH PAD", "7.500", Color(1.0, 0.75, 0.2), 1.0, "info")
	phys.set_scoop_hold(ball_id, hold)


func _start_multiball() -> void:
	multiball = true
	super_lit = false
	jackpot_shots = ["lorb", "lramp", "scoop", "pocket", "rramp"]
	_serve_extra(2)
	ball_save = MULTIBALL_SAVE_TIME
	_callout("MULTIBALL!", "ALLE ROTEN PFEILE = JACKPOT", Color(1.0, 0.35, 0.35), 3.0, "big")
	sfx.play("multiball")
	view.flash("both", 1.0)
	view.shake = 1.0
	view.rocket_shake = 1.0


func _start_mission() -> void:
	mission_active = p_mission[current] % MISSIONS.size()
	p_mission[current] += 1
	mission_time = MISSION_TIME
	mission_score = 0
	mission_shots.clear()
	if mission_active == 1:
		_pick_mission_shot("")
		_pick_mission_shot("")
	_callout(MISSIONS[mission_active], MISSION_HINT[mission_active], Color(1.0, 0.35, 0.9), 2.5, "big")
	sfx.play("multiball", -3.0, 1.2)
	if mission_active == 2:
		phys.reset_drops()


func _end_mission() -> void:
	_callout("MISSION ENDE", "SUMME " + DisplayScript.fmt(mission_score), Color(1.0, 0.35, 0.9), 2.0)
	mission_active = -1
	mission_shots.clear()


func _drop_bank_complete() -> void:
	_add_score(25000)
	sfx.play("complete")
	view.flash("right", 0.8)
	drop_reset_timer = 1.0
	if mission_active == 2:
		return
	if mission_active < 0 and not mission_lit:
		mission_lit = true
		_callout("MISSION BEREIT", "SCHIESS AUFS LAUNCH PAD", Color(1.0, 0.35, 0.9), 2.0)
	else:
		_callout("TARGETS", "25.000", Color(1.0, 0.75, 0.2), 1.2, "info")


func _on_drain() -> void:
	var remaining: int = phys.balls.size() + serve_queue
	if ball_save > 0.0 and not tilted:
		_serve_extra(1)
		if not multiball:
			ball_save = 0.0
		_callout("BALL SAVED", "", Color(0.4, 1.0, 0.6), 1.5, "info")
		sfx.play("extra", -4.0)
		return
	if multiball and remaining <= 1:
		multiball = false
		super_lit = false
		jackpot_shots.clear()
		_callout("MULTIBALL ENDE", "JACKPOT JETZT " + DisplayScript.fmt(jackpot_value), Color(1.0, 0.5, 0.4), 1.8, "info")
	if remaining == 0:
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
	phys.physics_step(delta)

	if state == State.PLAYING:
		_update_rules(delta)

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
		if OS.has_environment("PB_TRACE") and Engine.get_physics_frames() % 60 == 0:
			var desc := []
			for b in phys.balls:
				desc.append("%s/%s/%d" % [b.pos.round(), b.vel.round(), b.mode])
			print("t=%.1f st=%s mb=%s balls=%s" % [Engine.get_physics_frames() / 120.0, State.keys()[state],
				multiball, desc])


func _update_rules(delta: float) -> void:
	var in_lane: bool = phys.ball_in_plunger()
	if ball_save > 0.0 and not (in_lane and phys.balls.size() == 1):
		ball_save = maxf(0.0, ball_save - delta)
	skill_window = maxf(0.0, skill_window - delta)
	combo_timer = maxf(0.0, combo_timer - delta)
	inlane_lit[0] = maxf(0.0, inlane_lit[0] - delta)
	inlane_lit[1] = maxf(0.0, inlane_lit[1] - delta)
	upper_timer = maxf(0.0, upper_timer - delta)
	tilt_level = maxf(0.0, tilt_level - delta * 0.35)
	if skill_pending and in_lane and int(state_time / 0.6) != int((state_time - delta) / 0.6):
		skill_lane = (skill_lane + 1) % 3
	if mission_active >= 0:
		mission_time -= delta
		if mission_time <= 0.0:
			_end_mission()
	if drop_reset_timer > 0.0:
		drop_reset_timer -= delta
		if drop_reset_timer <= 0.0:
			phys.reset_drops()
	# Ball-Nachschub (Multiball, Ballretter) mit automatischem Abschuss.
	serve_timer = maxf(0.0, serve_timer - delta)
	if serve_queue > 0 and serve_timer <= 0.0 and not phys.lane_occupied():
		phys.serve_ball()
		serve_queue -= 1
		serve_timer = 0.9
		auto_launch_timer = 0.5
	if auto_launch > 0 and phys.ball_in_plunger():
		auto_launch_timer -= delta
		if auto_launch_timer <= 0.0:
			auto_launch -= 1
			phys.launch(_rng.randf_range(0.55, 0.85))


func _process(_delta: float) -> void:
	if screenshot_path != "" and Engine.get_process_frames() == screenshot_frame:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(screenshot_path)
		get_tree().quit()
	_update_lamps()
	_update_display()
	if state == State.ATTRACT:
		overlay.queue_redraw()


func _update_controls() -> void:
	var left := _key_side_held("L")
	var right := _key_side_held("R")
	var plunger := _key_side_held("P")
	for side in touches.values():
		if side == "L":
			left = true
		else:
			right = true
			if phys.ball_in_plunger() and auto_launch == 0:
				plunger = true
	if autoplay:
		var ai := _autoplay_controls()
		left = ai.x > 0.5
		right = ai.y > 0.5
		plunger = phys.ball_in_plunger() and auto_launch == 0 and phys.plunger_charge < _auto_plunge_target
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
	phys.set_flipper(0, left)
	phys.set_flipper(1, right)
	var was_held: bool = phys.plunger_held
	phys.set_plunger(plunger)
	if autoplay and was_held and not plunger:
		_auto_plunge_target = _rng.randf_range(0.1, 1.0)


func _rotate_lanes(dir: int) -> void:
	if tilted or (lanes[0] and lanes[1] and lanes[2]):
		return
	if dir < 0:
		lanes = [lanes[1], lanes[2], lanes[0]]
	else:
		lanes = [lanes[2], lanes[0], lanes[1]]


func _nudge() -> void:
	if state != State.PLAYING or tilted:
		return
	phys.nudge(Vector2(_rng.randf_range(-140, 140), -200))
	tilt_level += 1.0
	sfx.play("sling", -8.0, 0.5)
	if tilt_level > 2.6:
		tilted = true
		phys.set_flippers_enabled(false)
		phys.kickback_lit = false
		_callout("TILT", "", Color(1.0, 0.15, 0.15), 3.0, "big")
		sfx.play("over")
	elif tilt_level > 1.5:
		_callout("DANGER", "NICHT SO WILD!", Color(1.0, 0.3, 0.2), 1.0, "info")


func _update_lamps() -> void:
	var l := {}
	var in_lane: bool = phys.ball_in_plunger()
	for i in 3:
		if skill_pending and in_lane:
			l["lane%d" % i] = 3 if i == skill_lane else 0
		else:
			l["lane%d" % i] = 1 if lanes[i] else 0
	for m in range(2, 6):
		l["mult%d" % m] = 1 if multiplier >= m else 0
	for i in 3:
		if lock_lit or i < fuel:
			l["fuel%d" % i] = 1
		else:
			l["fuel%d" % i] = 2 if i == fuel and not multiball else 0
	var locks := p_locks[current] if state == State.PLAYING else 0
	l["lock0"] = 1 if locks >= 1 else (2 if lock_lit else 0)
	l["lock1"] = 1 if locks >= 2 else (2 if lock_lit and locks == 1 else 0)
	l["extra"] = 2 if extra_lit else 0
	l["mission_lit"] = 2 if mission_lit else 0
	for i in 3:
		if mission_active == i:
			l["mode%d" % i] = 3
		elif state == State.PLAYING and p_mission[current] > i:
			l["mode%d" % i] = 1
		else:
			l["mode%d" % i] = 0
	for i in 3:
		l["stand%d" % i] = 1 if stand_lit[i] else 0
	l["kickback"] = 1 if phys.kickback_lit else 0
	l["special"] = 0
	l["inlane0"] = 1 if inlane_lit[0] > 0.0 else 0
	l["inlane1"] = 1 if inlane_lit[1] > 0.0 else 0
	l["upper"] = 3 if upper_timer > 0.0 else 0
	l["save"] = 2 if ball_save > 0.0 else (1 if extra_balls > 0 else 0)
	for key in Layout.SHOTS:
		l["shot_" + key] = _shot_lamp(key)
	if state == State.ATTRACT or state == State.GAME_OVER:
		# Lichtshow: Regenbogen-Welle von unten nach oben.
		var t := state_time
		for k in l.keys():
			var p: Vector2 = _insert_pos.get(k, Vector2.ZERO)
			var on := 1 if sin(t * 4.0 + p.y / 160.0 + p.x / 400.0) > 0.55 else 0
			if k.begins_with("shot_"):
				l[k] = [on, Color.from_hsv(fmod(t * 0.3 + p.x / 1000.0, 1.0), 0.8, 1.0)]
			else:
				l[k] = on
	if tilted:
		for k in l.keys():
			l[k] = 0
	view.lamps = l
	# Rampenbeleuchtung je nach Modus.
	if multiball:
		view.ramp_color = Color(1.0, 0.2, 0.25)
	elif mission_active >= 0:
		view.ramp_color = Color(1.0, 0.3, 0.9)
	elif lock_lit:
		view.ramp_color = Color(1.0, 0.65, 0.1)
	else:
		view.ramp_color = Color(0.3, 0.9, 1.0)
	view.rocket_thrust = 0.7 if multiball else (0.25 if lock_lit else 0.0)


## Pfeil vor einem Hauptschuss: [Zustand, Farbe].
func _shot_lamp(key: String) -> Array:
	if state != State.PLAYING:
		return [0, Color.WHITE]
	if multiball:
		if key == "scoop" and super_lit:
			return [3, Color(1.0, 0.25, 0.9)]
		if jackpot_shots.has(key):
			return [3, Color(1.0, 0.15, 0.2)]
		return [0, Color.RED]
	if mission_active == 1 and mission_shots.has(key):
		return [3, Color(1.0, 0.3, 0.9)]
	match key:
		"scoop":
			if lock_lit:
				return [2, Color(1.0, 0.6, 0.1)]
			if mission_lit:
				return [2, Color(1.0, 0.3, 0.9)]
			if extra_lit:
				return [2, Color(1.0, 0.85, 0.2)]
			if upper_timer > 0.0:
				return [3, Color(0.2, 0.95, 1.0)]
		"lramp", "rramp":
			if not lock_lit:
				return [2, Color(0.25, 1.0, 0.4)]
		"lorb":
			if combo_timer > 0.0 and combo_last != "lorb":
				return [2, Color(0.2, 0.95, 1.0)]
		"pocket":
			if mission_active == 2:
				return [3, Color(1.0, 0.3, 0.9)]
			return [1, Color(0.2, 0.7, 1.0)]
	if combo_timer > 0.0 and combo_last != key:
		return [2, Color(0.2, 0.95, 1.0)]
	return [0, Color.WHITE]


func _update_display() -> void:
	var info := {"highscores": highscores, "scores": scores, "player": current}
	match state:
		State.ATTRACT:
			info["mode"] = "attract"
		State.GAME_OVER:
			info["mode"] = "over"
			info["new_high"] = new_high
		State.BONUS:
			info["mode"] = "bonus"
			info["bonus"] = bonus
			info["mult"] = multiplier
		State.PLAYING:
			info["mode"] = "game"
			info["score"] = scores[current]
			info["ball"] = ball_no[current]
			info["mult"] = multiplier
			info["tilt_warn"] = tilt_level > 1.5 and not tilted
			if paused:
				info["status"] = "PAUSE"
			elif multiball:
				info["status"] = "MULTIBALL – ROTE PFEILE = " + DisplayScript.fmt(jackpot_value)
				info["status_color"] = Color(1.0, 0.4, 0.4)
				if super_lit:
					info["status"] = "SUPER JACKPOT AM LAUNCH PAD!"
			elif mission_active >= 0:
				info["status"] = "%s  %ds" % [MISSIONS[mission_active], ceili(mission_time)]
				info["status_color"] = Color(1.0, 0.4, 0.9)
				info["bar"] = mission_time / MISSION_TIME
			elif ball_save > 0.0:
				info["status"] = "BALL SAVE"
				info["status_color"] = Color(1.0, 0.8, 0.3)
				info["bar"] = ball_save / BALL_SAVE_TIME
			elif lock_lit:
				info["status"] = "LOCK IS LIT – LAUNCH PAD"
				info["status_color"] = Color(1.0, 0.7, 0.2)
			else:
				info["status"] = "TREIBSTOFF %d/3   LOCKS %d/2" % [fuel, p_locks[current]]
				info["status_color"] = Color(0.5, 1.0, 0.6)
				info["bar"] = fuel / 3.0
	display.info = info


# ---------------------------------------------------------------- Overlay (Startbildschirm)

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
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.02, 0.02, 0.08, 0.82)
	panel.border_color = Color(0.35, 0.85, 1.0, 0.9)
	panel.set_border_width_all(3)
	panel.set_corner_radius_all(22)
	overlay.draw_style_box(panel, Rect2(80, 1250, 780, 360))
	overlay.draw_string(font, Vector2(80, 1305), "SPIELER WÄHLEN", HORIZONTAL_ALIGNMENT_CENTER, 780, 36,
		Color(1.0, 0.8, 0.3))
	var pulse := 0.6 + 0.4 * sin(state_time * 4.0)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.1, 0.15, 0.4, 0.95)
	btn.border_color = Color(0.35, 0.85, 1.0, pulse)
	btn.set_border_width_all(3)
	btn.set_corner_radius_all(16)
	var buttons := _player_buttons()
	for i in buttons.size():
		var r := buttons[i]
		overlay.draw_style_box(btn, r)
		overlay.draw_string(font, r.position + Vector2(0, 82), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 72, Color.WHITE)
		overlay.draw_string(font, r.position + Vector2(0, 115), "SPIELER", HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, 18, Color(0.7, 0.85, 1.0))
	var btn2 := StyleBoxFlat.new()
	btn2.bg_color = Color(0.15, 0.08, 0.25, 0.95)
	btn2.border_color = Color(1.0, 0.5, 0.9, 0.8)
	btn2.set_border_width_all(2)
	btn2.set_corner_radius_all(14)
	for pair in [[_rotate_button(), "ANSICHT DREHEN (%d°)" % rotation_deg],
			[_music_button(), "MUSIK: " + ("AN" if music_on else "AUS")]]:
		var r: Rect2 = pair[0]
		overlay.draw_style_box(btn2, r)
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
			touches[index] = "L" if p.x < Phys.CENTER_X else "R"


func _pointer_up(index: int) -> void:
	touches.erase(index)


## Welche Flipper-Seite eine Taste steuert ("L", "R", Plunger "P" oder "").
static func _side_for(code: Key, location: KeyLocation) -> String:
	match code:
		KEY_A, KEY_LEFT, KEY_Y, KEY_Z:
			return "L"
		KEY_L, KEY_RIGHT:
			return "R"
		KEY_SHIFT, KEY_CTRL:
			return "R" if location == KEY_LOCATION_RIGHT else "L"
		KEY_SPACE, KEY_DOWN, KEY_ENTER, KEY_KP_ENTER:
			return "P"
	return ""


## Ist mindestens eine Taste dieser Seite gedrückt? Tasten, die das System
## nicht mehr als gedrückt meldet, werden dabei verworfen. Das fängt den Fall
## ab, dass Windows/macOS beim Loslassen einer von zwei gleichzeitig
## gehaltenen Tasten kein Ereignis schickt – sonst bliebe ein Flipper
## dauerhaft oben.
func _key_side_held(side: String) -> bool:
	var result := false
	for id in held_keys.keys():
		var h: Dictionary = held_keys[id]
		var code: Key = h["code"]
		# Shift/Ctrl lassen sich nicht pro Seite abfragen (siehe _key()).
		if code != KEY_SHIFT and code != KEY_CTRL:
			var still: bool = Input.is_physical_key_pressed(code) if h["physical"] else Input.is_key_pressed(code)
			if not still:
				held_keys.erase(id)
				continue
		if h["side"] == side:
			result = true
	return result


func _release_held(code: Key) -> void:
	for id in held_keys.keys():
		if held_keys[id]["code"] == code:
			held_keys.erase(id)


func _notification(what: int) -> void:
	# Fensterwechsel (Cmd-Tab, Alt-Tab): alle Flipper loslassen.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		held_keys.clear()
		touches.clear()


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
	var physical := e.physical_keycode != KEY_NONE
	var code: Key = e.physical_keycode if physical else e.keycode
	var side := _side_for(code, e.location)
	if side != "":
		var id := "%d:%d" % [code, e.location]
		if side == "P" and state == State.ATTRACT:
			if down:
				_start_game(1)
		elif down:
			held_keys[id] = {"side": side, "code": code, "physical": physical}
		else:
			held_keys.erase(id)
	# Shift/Ctrl gibt es links und rechts, Godot führt aber nur eine gemeinsame
	# Taste. Ob noch eine davon gehalten wird, verrät der Modifier-Zustand des
	# Ereignisses. Ist keine mehr gedrückt, werden beide Seiten losgelassen –
	# auch wenn das System das Loslassen der ersten Taste verschluckt hat.
	var modifier_key := code == KEY_SHIFT or code == KEY_CTRL
	if not down or not modifier_key:
		if not e.shift_pressed:
			_release_held(KEY_SHIFT)
		if not e.ctrl_pressed:
			_release_held(KEY_CTRL)
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
		KEY_N, KEY_UP:
			_nudge()
		KEY_F11:
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_ESCAPE:
			if state == State.ATTRACT:
				get_tree().quit()
			else:
				paused = false
				phys.clear_balls()
				display.clear_callouts()
				_set_state(State.ATTRACT)


# ---------------------------------------------------------------- Autoplay

## Einfacher Bot für Tests und Demo: flippert, wenn ein Ball über einem
## Flipper ist. Liefert (links, rechts) als Vector2 mit 0/1.
func _autoplay_controls() -> Vector2:
	var out := Vector2.ZERO
	var pulse := fmod(phys.time, 0.9) < 0.2
	for b in phys.balls:
		if b.mode != Phys.Mode.FREE:
			continue
		var p: Vector2 = b.pos
		var v: Vector2 = b.vel
		if p.y > 1490.0 and p.y < 1640.0 and (v.y > 40.0 or pulse):
			if p.x < Phys.CENTER_X and p.x > 300.0:
				out.x = 1.0
			elif p.x >= Phys.CENTER_X and p.x < 640.0:
				out.y = 1.0
	return out


func _check_ball_sane() -> void:
	for b in phys.balls:
		if b.pos.x < 20.0 or b.pos.x > 980.0 or b.pos.y < 0.0:
			push_error("Ball hat den Tisch verlassen: %s" % b.pos)
			_stat("escaped", 1)
			b.pos = Vector2(470, 1700)


func _exit_tree() -> void:
	if autoplay:
		print("[autoplay] Statistik: ", _stats)
		print("[autoplay] Punkte: ", scores, " Status: ", State.keys()[state])
