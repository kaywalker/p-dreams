extends Node2D
## Modernes Farb-Display (wie das LCD in der Backbox aktueller Flipper).
##
## main.gd füllt jedes Frame `info` (Punkte, Spieler, Status) und ruft
## `callout()` für große animierte Einblendungen auf.

const SIZE := Vector2(1000, 250)

var info := {}
var font: Font
var bold: FontVariation
var _time := 0.0
var _callouts: Array[Dictionary] = []
var _stars: Array[Vector3] = []
var _panel: StyleBoxFlat
var _score_shown := 0.0


func _ready() -> void:
	font = ThemeDB.fallback_font
	bold = FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 1.1
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 90:
		_stars.append(Vector3(rng.randf_range(0, SIZE.x), rng.randf_range(0, SIZE.y), rng.randf_range(0.3, 1.0)))
	_panel = StyleBoxFlat.new()
	_panel.bg_color = Color(0.02, 0.02, 0.06)
	_panel.border_color = Color(0.55, 0.58, 0.68)
	_panel.set_border_width_all(6)
	_panel.set_corner_radius_all(18)
	_panel.shadow_color = Color(0.3, 0.6, 1.0, 0.25)
	_panel.shadow_size = 18


## Große Einblendung. `style`: "normal", "big" (Jackpot) oder "info".
func callout(title: String, sub := "", color := Color(1.0, 0.8, 0.25), time := 1.8, style := "normal") -> void:
	_callouts.append({"title": title, "sub": sub, "color": color, "time": time, "total": time,
		"style": style})
	while _callouts.size() > 4:
		_callouts.pop_front()


func clear_callouts() -> void:
	_callouts.clear()


func has_callout() -> bool:
	return not _callouts.is_empty()


func _process(delta: float) -> void:
	_time += delta
	if not _callouts.is_empty():
		_callouts[0]["time"] = float(_callouts[0]["time"]) - delta
		if float(_callouts[0]["time"]) <= 0.0:
			_callouts.pop_front()
	var target := float(info.get("score", 0))
	_score_shown = target if absf(target - _score_shown) < 10.0 else lerpf(_score_shown, target, minf(1.0, delta * 9.0))
	queue_redraw()


static func fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func _str(pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0,
		outline := 0, outline_col := Color.BLACK) -> void:
	if outline > 0:
		draw_string_outline(bold, pos, s, align, width, size, outline, outline_col)
	draw_string(bold, pos, s, align, width, size, col)


func _fit_size(s: String, size: int, max_w: float) -> int:
	var w := bold.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w <= max_w:
		return size
	return maxi(12, int(size * max_w / w))


func _draw() -> void:
	draw_style_box(_panel, Rect2(Vector2.ZERO, SIZE))
	var inner := Rect2(Vector2(10, 10), SIZE - Vector2(20, 20))
	# Hintergrund: Verlauf und fliegende Sterne.
	var top := Color(0.05, 0.02, 0.16)
	var bottom := Color(0.0, 0.08, 0.18)
	draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end,
		Vector2(inner.position.x, inner.end.y)]), PackedColorArray([top, top, bottom, bottom]))
	for st in _stars:
		var x := fposmod(st.x - _time * 60.0 * st.z, inner.size.x) + inner.position.x
		var y := st.y * (inner.size.y / SIZE.y) + inner.position.y
		draw_line(Vector2(x, y), Vector2(x + 8.0 * st.z, y), Color(0.7, 0.85, 1.0, 0.25 + 0.5 * st.z), 1.5)
	# Horizont-Gitter unten.
	for i in 9:
		var gy := inner.end.y - pow(float(i) / 8.0, 2.0) * 60.0
		draw_line(Vector2(inner.position.x, gy), Vector2(inner.end.x, gy), Color(1.0, 0.2, 0.8, 0.08 + 0.02 * i), 1.0)

	if not _callouts.is_empty():
		_draw_callout(_callouts[0], inner)
		return

	match str(info.get("mode", "attract")):
		"attract":
			_draw_attract(inner)
		"game":
			_draw_game(inner)
		"bonus":
			_draw_bonus(inner)
		"over":
			_draw_over(inner)


func _draw_attract(r: Rect2) -> void:
	var page := int(_time / 4.0) % 3
	var cx := r.position.x
	var w := r.size.x
	if page == 0:
		var pulse := 0.5 + 0.5 * sin(_time * 3.0)
		_str(Vector2(cx, r.position.y + 125), "LIFTOFF", 120, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w,
			14, Color(1.0, 0.2, 0.7, 0.4 + 0.4 * pulse))
		_str(Vector2(cx, r.position.y + 185), "A PINBALL DREAM", 30, Color(0.6, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, w)
	elif page == 1:
		_str(Vector2(cx, r.position.y + 45), "HIGHSCORES", 34, Color(1.0, 0.8, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w)
		var hs: Array = info.get("highscores", [])
		if hs.is_empty():
			_str(Vector2(cx, r.position.y + 130), "NOCH KEINE – SEI DIE ERSTE!", 30, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
		for i in mini(4, hs.size()):
			var y := r.position.y + 90 + i * 36
			var col := Color(1.0, 0.9, 0.5) if i == 0 else Color(0.85, 0.9, 1.0)
			_str(Vector2(cx + 260, y), "%d." % (i + 1), 30, col)
			_str(Vector2(cx + 300, y), fmt(int(hs[i])), 30, col, HORIZONTAL_ALIGNMENT_RIGHT, 380)
	else:
		var blink := fmod(_time, 1.0) < 0.6
		_str(Vector2(cx, r.position.y + 95), "TIPPE AUF 1–4 SPIELER", 52,
			Color(1, 1, 1) if blink else Color(0.6, 0.7, 0.9), HORIZONTAL_ALIGNMENT_CENTER, w, 8, Color(0.2, 0.4, 1.0, 0.5))
		_str(Vector2(cx, r.position.y + 160), "ODER TASTE 1–4 / ENTER", 28, Color(0.6, 0.9, 1.0), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_game(r: Rect2) -> void:
	var cx := r.position.x
	var w := r.size.x
	var players: Array = info.get("scores", [0])
	var cur := int(info.get("player", 0))
	_str(Vector2(cx + 20, r.position.y + 38), "SPIELER %d" % (cur + 1), 28, Color(0.6, 0.9, 1.0))
	_str(Vector2(cx, r.position.y + 38), "BALL %d" % int(info.get("ball", 1)), 28, Color(0.6, 0.9, 1.0),
		HORIZONTAL_ALIGNMENT_RIGHT, w - 20)
	var score_text := fmt(int(_score_shown))
	var size := _fit_size(score_text, 104, w - 60)
	_str(Vector2(cx, r.position.y + 140), score_text, size, Color(1.0, 0.95, 0.85), HORIZONTAL_ALIGNMENT_CENTER, w,
		12, Color(1.0, 0.45, 0.1, 0.55))
	# Andere Spieler klein.
	if players.size() > 1:
		var txt := ""
		for i in players.size():
			if i != cur:
				txt += "  P%d %s" % [i + 1, fmt(int(players[i]))]
		_str(Vector2(cx, r.position.y + 72), txt, 20, Color(0.7, 0.75, 0.9, 0.8), HORIZONTAL_ALIGNMENT_CENTER, w)
	# Statuszeile: Mission/Multiball mit Fortschrittsbalken.
	var status := str(info.get("status", ""))
	var bar := float(info.get("bar", -1.0))
	var status_col: Color = info.get("status_color", Color(0.5, 1.0, 0.6))
	if bar >= 0.0:
		var br := Rect2(cx + 20, r.position.y + 168, w - 40, 44)
		draw_rect(br, Color(0, 0, 0, 0.5))
		draw_rect(Rect2(br.position, Vector2(br.size.x * clampf(bar, 0.0, 1.0), br.size.y)), Color(status_col, 0.45))
		draw_rect(br, Color(status_col, 0.9), false, 2.0)
	_str(Vector2(cx, r.position.y + 202), status, 30, status_col, HORIZONTAL_ALIGNMENT_CENTER, w)
	var mult := int(info.get("mult", 1))
	if mult > 1:
		_str(Vector2(cx, r.position.y + 140), "%dX" % mult, 40, Color(0.4, 0.7, 1.0), HORIZONTAL_ALIGNMENT_RIGHT, w - 20)
	if bool(info.get("tilt_warn", false)):
		_str(Vector2(cx + 20, r.position.y + 140), "DANGER", 32, Color(1, 0.2, 0.2))


func _draw_bonus(r: Rect2) -> void:
	var cx := r.position.x
	var w := r.size.x
	_str(Vector2(cx, r.position.y + 55), "BONUS", 44, Color(1.0, 0.8, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w)
	var b := int(info.get("bonus", 0))
	var m := int(info.get("mult", 1))
	_str(Vector2(cx, r.position.y + 130), "%s  ×  %d" % [fmt(b), m], 60, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	_str(Vector2(cx, r.position.y + 200), "= " + fmt(b * m), 44, Color(0.5, 1.0, 0.6), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_over(r: Rect2) -> void:
	var cx := r.position.x
	var w := r.size.x
	_str(Vector2(cx, r.position.y + 60), "GAME OVER", 54, Color(1.0, 0.3, 0.4), HORIZONTAL_ALIGNMENT_CENTER, w, 8,
		Color(0, 0, 0, 0.6))
	var players: Array = info.get("scores", [0])
	if players.size() == 1:
		_str(Vector2(cx, r.position.y + 160), fmt(int(players[0])), 80, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w)
	else:
		for i in players.size():
			var x := cx + 20 + (i % 2) * (w / 2.0)
			var y := r.position.y + 120 + (i / 2) * 60
			_str(Vector2(x, y), "P%d  %s" % [i + 1, fmt(int(players[i]))], 40, Color.WHITE)
	if bool(info.get("new_high", false)):
		_str(Vector2(cx, r.position.y + 225), "NEUER HIGHSCORE!", 26, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER, w)


func _draw_callout(c: Dictionary, r: Rect2) -> void:
	var total := float(c["total"])
	var age := total - float(c["time"])
	var col: Color = c["color"]
	var style := str(c["style"])
	# Hintergrund-Effekt: Strahlen bei großen Callouts.
	var center := r.get_center()
	if style == "big":
		for i in 16:
			var ang := TAU * i / 16.0 + _time * 0.8
			var p1 := center + Vector2.from_angle(ang - 0.08) * 700.0
			var p2 := center + Vector2.from_angle(ang + 0.08) * 700.0
			draw_colored_polygon(PackedVector2Array([center, p1, p2]), Color(col, 0.12))
		if fmod(age, 0.2) < 0.1 and age < 0.8:
			draw_rect(r, Color(col, 0.25))
	var pop := 1.0 + 0.6 * exp(-age * 9.0) * (1.0 if age < 0.4 else 0.0)
	var fade := clampf(float(c["time"]) * 4.0, 0.0, 1.0)
	var title := str(c["title"])
	var size := _fit_size(title, 92 if style != "info" else 64, r.size.x - 40)
	draw_set_transform(center, 0.0, Vector2(pop, pop))
	var y_off := -10.0 if str(c["sub"]) != "" else 30.0
	_str(Vector2(-r.size.x * 0.5, y_off), title, size, Color(col, fade), HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
		12, Color(0, 0, 0, 0.7 * fade))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var sub := str(c["sub"])
	if sub != "":
		var sub_size := _fit_size(sub, 40, r.size.x - 40)
		_str(Vector2(r.position.x, r.position.y + 200), sub, sub_size, Color(1, 1, 1, fade),
			HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 6, Color(0, 0, 0, 0.6 * fade))
