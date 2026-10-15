extends SceneTree
## Sucht Stellen, an denen ein Ball liegen bleiben kann.
##
## Lässt an einem Raster von Startpunkten je einen Ball ohne Anfangsgeschwindigkeit
## fallen (Flipper in Ruhe, kein automatisches Anstupsen) und meldet alle Positionen,
## an denen er nach einigen Sekunden still liegt. Beabsichtigte Ruhepunkte
## (Plunger, Scoop) werden ignoriert.
##
## Aufruf: godot --headless --path . --script tests/rest_test.gd

const Phys := preload("res://scripts/physics.gd")
const STEP := 30
const SIM_TIME := 4.0
const DT := 1.0 / 120.0


func _init() -> void:
	var p = Phys.new()
	p._build()
	p.auto_unstick = false
	p.table_event.connect(func(_k, _i, _b): pass)
	var spots := {}
	var tested := 0
	for y in range(120, 1560, STEP):
		for x in range(55, 900, STEP):
			var start := Vector2(x, y)
			if y < 480 and start.distance_to(Phys.ARC_CENTER) > Phys.ARC_RADIUS - 25.0:
				continue
			if _inside_sling(p, start):
				continue
			p.clear_balls()
			p.serve_ball()
			var b = p.balls[0]
			b.pos = start
			# Winziger Seitenimpuls: echte Bälle balancieren nie exakt auf einem Pfostenscheitel.
			b.vel = Vector2(0.5 if (x / STEP) % 2 == 0 else -0.5, 0.0)
			tested += 1
			var still := 0.0
			var t := 0.0
			while t < SIM_TIME and not p.balls.is_empty():
				p.physics_step(DT)
				t += DT
				if p.balls.is_empty():
					break
				b = p.balls[0]
				if b.mode != Phys.Mode.FREE:
					break
				still = still + DT if b.vel.length() < 15.0 else 0.0
				if still > 1.0:
					break
			if p.balls.is_empty() or b.mode != Phys.Mode.FREE or still <= 1.0:
				continue
			if b.pos.x > 900.0:
				continue
			var key := Vector2i(roundi(b.pos.x / 10.0) * 10, roundi(b.pos.y / 10.0) * 10)
			spots[key] = int(spots.get(key, 0)) + 1
	print("Getestete Startpunkte: ", tested)
	if spots.is_empty():
		print("OK: keine Ruhepunkte gefunden")
	else:
		print("Ruhepunkte (Position: Anzahl Bälle):")
		for k in spots:
			print("  ", k, ": ", spots[k])
	quit(1 if not spots.is_empty() else 0)


## Startpunkte im Inneren der Slingshots ergeben keinen Sinn.
func _inside_sling(p, pt: Vector2) -> bool:
	for sl in p.slings:
		var a: Vector2 = sl.b
		var c: Vector2 = sl.a
		var tri := PackedVector2Array([a, Vector2(a.x, a.y + 120), c])
		if Geometry2D.is_point_in_polygon(pt, tri):
			return true
	return false
