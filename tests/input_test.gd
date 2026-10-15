extends SceneTree
## Prüft die Flipper-Steuerung mit simulierten Tastendrücken, insbesondere
## gleichzeitiges Drücken von links und rechts.
##
## Aufruf: godot --headless --path . --script tests/input_test.gd

var main: Node
var failures := 0


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


var _shift_down := {}


## Simuliert eine Taste wie Windows/macOS: Der Modifier-Zustand des Ereignisses
## gibt an, ob danach noch eine Shift-Taste gedrückt ist.
func _key(code: Key, down: bool, loc := KEY_LOCATION_UNSPECIFIED, swallow := false) -> void:
	if code == KEY_SHIFT:
		if down:
			_shift_down[loc] = true
		else:
			_shift_down.erase(loc)
	if swallow:
		return
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.location = loc
	e.pressed = down
	e.shift_pressed = not _shift_down.is_empty()
	Input.parse_input_event(e)


func _frames(n := 3) -> void:
	for i in n:
		await process_frame
		await physics_frame


func _check(name: String, left: bool, right: bool) -> void:
	var f = main.phys.flippers
	var ok: bool = f[0].pressed == left and f[1].pressed == right
	print(("OK    " if ok else "FEHLER"), " ", name, "  (links=", f[0].pressed, " rechts=", f[1].pressed, ")")
	if not ok:
		failures += 1


func _run() -> void:
	await _frames()
	_key(KEY_1, true)
	_key(KEY_1, false)
	await _frames()

	# Beide Shift-Tasten, in verschiedener Reihenfolge loslassen.
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT)
	await _frames()
	_check("Shift L+R gedrückt", true, true)
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT)
	await _frames()
	_check("Shift L losgelassen", false, true)
	_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	await _frames()
	_check("Shift R losgelassen", false, false)

	# Betriebssystem verschluckt das Loslassen der ersten Shift-Taste
	# (bekanntes Verhalten unter Windows/macOS, wenn beide gedrückt sind).
	_key(KEY_SHIFT, true, KEY_LOCATION_LEFT)
	_key(KEY_SHIFT, true, KEY_LOCATION_RIGHT)
	await _frames()
	_key(KEY_SHIFT, false, KEY_LOCATION_LEFT, true)
	await _frames()
	_check("Shift L los (Ereignis verschluckt)", true, true)
	_key(KEY_SHIFT, false, KEY_LOCATION_RIGHT)
	await _frames()
	_check("Shift R los: beide Flipper unten", false, false)

	# Pfeiltasten gleichzeitig.
	_key(KEY_LEFT, true)
	_key(KEY_RIGHT, true)
	await _frames()
	_check("Pfeile L+R gedrückt", true, true)
	_key(KEY_RIGHT, false)
	_key(KEY_LEFT, false)
	await _frames()
	_check("Pfeile losgelassen", false, false)

	# Zwei Tasten für dieselbe Seite: eine loslassen, andere hält weiter.
	_key(KEY_A, true)
	_key(KEY_LEFT, true)
	_key(KEY_A, false)
	await _frames()
	_check("A los, Pfeil links hält", true, false)
	_key(KEY_LEFT, false)
	await _frames()
	_check("Pfeil links los", false, false)

	# Fokusverlust (z. B. Cmd-Tab) mit gedrückten Tasten.
	_key(KEY_L, true)
	_key(KEY_A, true)
	await _frames()
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await _frames()
	_check("Fokusverlust", false, false)
	_key(KEY_L, false)
	_key(KEY_A, false)

	# Touch: links und rechts gleichzeitig, dann beide loslassen.
	var vp := root.get_visible_rect().size
	for spec in [[0, true, -1.0], [1, true, 1.0]]:
		_touch(spec[0], spec[1], spec[2])
	await _frames()
	_check("Touch L+R", true, true)
	_touch(1, false, 1.0)
	_touch(0, false, -1.0)
	await _frames()
	_check("Touch losgelassen", false, false)

	print("Fehler: ", failures)
	quit(1 if failures > 0 else 0)


## Touch auf der linken (side < 0) oder rechten Spielfeldhälfte.
func _touch(index: int, down: bool, side: float) -> void:
	var table_pos := Vector2(470.0 + side * 200.0, 1400.0)
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = down
	e.position = main.world.get_global_transform() * table_pos
	Input.parse_input_event(e)
