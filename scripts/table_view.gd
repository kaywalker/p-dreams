extends Node3D
## 3D-Darstellung des Tisches. Baut aus der Geometrie in physics.gd einen
## echten Flippertisch (Holzgehäuse, Metallführungen, Gummis, Bumper,
## Kunststofframpe, Lampen-Einsätze) und gleicht ihn jedes Frame mit dem
## Physik-Zustand ab. Die Kamera schaut senkrecht von oben – wie man auf
## einen Gaming-Table blickt.
##
## Maßstab: 1 Tischeinheit = 0.01 3D-Einheiten. Tisch-x -> 3D-x, Tisch-y -> 3D-z.

const Layout := preload("res://scripts/layout.gd")
const Phys := preload("res://scripts/physics.gd")
const S := 0.01

var phys: Node
var art_texture: Texture2D
## Lampenzustände von main.gd: 0 = aus, 1 = an, 2 = blinkt, 3 = schnell blinkt.
var lamps := {}
var flash_left := 0.0
var flash_right := 0.0
var flash_bumpers := 0.0
var shake := 0.0

var camera: Camera3D
var _ball_nodes: Array[MeshInstance3D] = []
var _flipper_nodes: Array[Node3D] = []
var _bumper_nodes: Array[Dictionary] = []
var _drop_nodes: Array[Node3D] = []
var _standup_mats: Array[StandardMaterial3D] = []
var _rail_mats: Array[StandardMaterial3D] = []
var _rocket: Node3D
var _flame: MeshInstance3D
var _flame_mat: StandardMaterial3D
## Von main.gd gesetzt: Rakete wackelt / Triebwerk brennt (0..1).
var rocket_shake := 0.0
var rocket_thrust := 0.0
## Farbe der Rampen-Beleuchtung (RGB, je nach Modus).
var ramp_color := Color(0.3, 0.9, 1.0)
var _sling_nodes: Array[Dictionary] = []
var _post_nodes: Array[Dictionary] = []
var _insert_mats := {}
var _insert_colors := {}
var _spinner: Node3D
var _plunger: Node3D
var _gate: Node3D
var _flasher_l: OmniLight3D
var _flasher_r: OmniLight3D
var _flasher_mats: Array[StandardMaterial3D] = []
var _bumper_light: OmniLight3D
var _time := 0.0
var _cam_base := Vector3.ZERO

var _m_chrome: StandardMaterial3D
var _m_metal: StandardMaterial3D
var _m_rubber: StandardMaterial3D
var _m_wood: StandardMaterial3D
var _m_black: StandardMaterial3D
var _m_ramp: StandardMaterial3D
var _m_ball: StandardMaterial3D


static func v3(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x * S, h * S, p.y * S)


func setup(physics: Node, art: Texture2D) -> void:
	phys = physics
	art_texture = art
	_make_materials()
	_build_environment()
	_build_cabinet()
	_build_walls()
	_build_posts_and_bumpers()
	_build_slings()
	_build_flippers()
	_build_drops()
	_build_tracks()
	_build_rocket()
	_build_inserts()
	_build_toys()


# ---------------------------------------------------------------- Materialien

func _mat(col: Color, metallic := 0.0, rough := 0.5, emission := Color.BLACK, energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = rough
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	return m


func _make_materials() -> void:
	_m_chrome = _mat(Color(0.86, 0.88, 0.92), 1.0, 0.12)
	_m_metal = _mat(Color(0.72, 0.74, 0.8), 0.9, 0.3)
	_m_rubber = _mat(Color(0.95, 0.95, 0.92), 0.0, 0.8)
	_m_black = _mat(Color(0.03, 0.03, 0.04), 0.2, 0.4)
	_m_ball = _mat(Color(0.95, 0.96, 1.0), 0.85, 0.1)
	_m_wood = _mat(Color(0.32, 0.17, 0.08), 0.0, 0.55)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.02
	var grain := NoiseTexture2D.new()
	grain.width = 256
	grain.height = 1024
	grain.noise = noise
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.22, 0.1, 0.04))
	ramp.set_color(1, Color(0.45, 0.25, 0.12))
	grain.color_ramp = ramp
	_m_wood.albedo_color = Color.WHITE
	_m_wood.albedo_texture = grain
	_m_ramp = _mat(Color(0.45, 0.8, 1.0, 0.28), 0.0, 0.05, Color(0.3, 0.7, 1.0), 0.15)
	_m_ramp.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_m_ramp.cull_mode = BaseMaterial3D.CULL_DISABLED


# ---------------------------------------------------------------- Mesh-Helfer

func _add(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi


func _cyl(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top * S
	c.bottom_radius = r_bot * S
	c.height = h * S
	c.radial_segments = 32
	c.rings = 1
	return c


func _torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner * S
	t.outer_radius = outer * S
	t.rings = 32
	t.ring_segments = 12
	return t


## Extrudiertes Polygon (Tischkoordinaten) von Höhe h0 bis h1.
## Oberseite bekommt UVs = Tischkoordinaten, damit der Spielfelddruck passt.
func _prism(poly: PackedVector2Array, h0: float, h1: float, sides := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in tris:
		var p := poly[i]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(p.x / Phys.W, p.y / Phys.H))
		st.add_vertex(v3(p, h1))
	if sides:
		var area := 0.0
		for i in poly.size():
			area += poly[i].cross(poly[(i + 1) % poly.size()])
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var e := b - a
			var n2 := Vector2(e.y, -e.x) if area > 0.0 else Vector2(-e.y, e.x)
			var n := Vector3(n2.x, 0.0, n2.y).normalized()
			var quad := [v3(a, h0), v3(b, h0), v3(b, h1), v3(a, h0), v3(b, h1), v3(a, h1)]
			for q in quad:
				st.set_normal(n)
				st.set_uv(Vector2(0, 0))
				st.add_vertex(q)
	return st.commit()


## Quader entlang einer Strecke (für Wände).
func _seg_box(a: Vector2, b: Vector2, thick: float, h0: float, h1: float, mat: Material) -> MeshInstance3D:
	var d := b - a
	var box := BoxMesh.new()
	box.size = Vector3(d.length() * S, (h1 - h0) * S, thick * 2.0 * S)
	var mi := _add(box, mat, v3((a + b) * 0.5, (h0 + h1) * 0.5))
	mi.rotation.y = -atan2(d.y, d.x)
	return mi


# ---------------------------------------------------------------- Aufbau

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.background_color = Color(0.01, 0.01, 0.02)
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.15, 0.2, 0.45)
	sky_mat.sky_horizon_color = Color(0.9, 0.75, 0.95)
	sky_mat.ground_horizon_color = Color(0.5, 0.3, 0.55)
	sky_mat.ground_bottom_color = Color(0.05, 0.03, 0.1)
	sky_mat.sky_energy_multiplier = 1.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.7)
	env.ambient_light_energy = 0.18
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 0.95
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48), deg_to_rad(-25), 0)
	sun.light_energy = 0.55
	sun.light_color = Color(1.0, 0.95, 0.9)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.9
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)

	# Allgemeine Beleuchtung (GI) an den Seiten, wie die Lampen unter den Rails.
	for i in 4:
		for side in 2:
			var l := OmniLight3D.new()
			l.position = Vector3(0.6 if side == 0 else 9.0, 1.4, 2.0 + i * 4.6)
			l.light_color = Color(1.0, 0.85, 0.65)
			l.light_energy = 0.3
			l.omni_range = 5.5
			add_child(l)

	_bumper_light = OmniLight3D.new()
	_bumper_light.position = Vector3(4.7, 1.2, 6.5)
	_bumper_light.light_color = Color(1.0, 0.75, 0.3)
	_bumper_light.light_energy = 0.0
	_bumper_light.omni_range = 4.0
	add_child(_bumper_light)

	# Kamera senkrecht über dem Tisch, so dass die Spielfeldebene exakt
	# Layout.VIEW ausfüllt.
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var view := Layout.VIEW
	var half_h := view.size.y * S * 0.5
	var height := half_h / tan(deg_to_rad(camera.fov * 0.5))
	_cam_base = Vector3(view.get_center().x * S, height, view.get_center().y * S)
	camera.position = _cam_base
	camera.rotation = Vector3(-PI / 2, 0, 0)
	camera.near = 1.0
	camera.far = height + 5.0
	add_child(camera)


func _build_cabinet() -> void:
	# Spielfeld mit Druck.
	var pf := _mat(Color.WHITE, 0.0, 0.32)
	pf.albedo_texture = art_texture
	pf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var field := PackedVector2Array([Vector2(0, 0), Vector2(Phys.W, 0), Vector2(Phys.W, Phys.H),
		Vector2(0, Phys.H)])
	_add(_prism(field, -2, 0, false), pf, Vector3.ZERO)

	# Apron (zwei Hälften, dazwischen läuft der Ball ab) mit Chromkante.
	var apron_mat := _mat(Color.WHITE, 0.1, 0.4)
	apron_mat.albedo_texture = art_texture
	var left := PackedVector2Array([Vector2(36, 1692), Vector2(395, 1700), Vector2(395, 1810),
		Vector2(36, 1810)])
	var right := PackedVector2Array([Vector2(545, 1700), Vector2(898, 1692), Vector2(898, 1810),
		Vector2(545, 1810)])
	for poly in [left, right]:
		_add(_prism(poly, 0, 14), apron_mat, Vector3.ZERO)
	_seg_box(Vector2(36, 1691), Vector2(395, 1699), 2.5, 13, 16, _m_chrome)
	_seg_box(Vector2(545, 1699), Vector2(898, 1691), 2.5, 13, 16, _m_chrome)

	# Holz-Seitenwände mit Chrom-Abschluss (Side Rails) und Lockdown Bar.
	_add(_prism(PackedVector2Array([Vector2(-140, -80), Vector2(36, -80), Vector2(36, 1900),
		Vector2(-140, 1900)]), -2, 70), _m_wood, Vector3.ZERO)
	_add(_prism(PackedVector2Array([Vector2(964, -80), Vector2(1140, -80), Vector2(1140, 1900),
		Vector2(964, 1900)]), -2, 70), _m_wood, Vector3.ZERO)
	_add(_prism(PackedVector2Array([Vector2(36, -80), Vector2(964, -80), Vector2(964, 0),
		Vector2(36, 0)]), -2, 70), _m_wood, Vector3.ZERO)
	for x in [30.0, 970.0]:
		var rail := BoxMesh.new()
		rail.size = Vector3(0.12, 0.05, 19.6)
		_add(rail, _m_metal, Vector3(x * S, 0.72, 9.0))
	var bar := BoxMesh.new()
	bar.size = Vector3(12.4, 0.5, 0.75)
	_add(bar, _mat(Color(0.08, 0.08, 0.1), 0.6, 0.35), Vector3(5.0, 0.4, 18.45))


func _wall_mat(style: String) -> StandardMaterial3D:
	match style:
		"wood":
			return _m_wood
		"plastic":
			return _mat(Color(0.2, 0.9, 1.0, 0.75), 0.0, 0.15, Color(0.2, 0.8, 1.0), 0.6)
		"ramp":
			return _m_ramp
	return _m_metal


func _build_walls() -> void:
	for w in phys.walls:
		match w.style:
			"metal", "plastic", "ramp":
				var h := 42.0 if w.style != "plastic" else 30.0
				_seg_box(w.a, w.b, w.thick, 0, h, _wall_mat(w.style))
				if w.style == "metal":
					_add(_cyl(w.thick, w.thick, h), _m_metal, v3(w.a, h * 0.5))
					_add(_cyl(w.thick, w.thick, h), _m_metal, v3(w.b, h * 0.5))
			"wood":
				_seg_box(w.a, w.b, w.thick, 0, 70, _m_wood)
			"gate":
				_gate = Node3D.new()
				_gate.position = v3(w.a, 30)
				_gate.rotation.y = -atan2(w.b.y - w.a.y, w.b.x - w.a.x)
				add_child(_gate)
				var d: float = (w.b - w.a).length()
				var flap := BoxMesh.new()
				flap.size = Vector3(d * S, 0.24, 0.02)
				_add(flap, _m_chrome, Vector3(d * S * 0.5, -0.12, 0), _gate)


func _build_posts_and_bumpers() -> void:
	var cap_cols := [Color(1.0, 0.25, 0.4), Color(0.25, 0.55, 1.0), Color(1.0, 0.7, 0.15)]
	for c in phys.circles:
		if c.kind == "bumper":
			var node := Node3D.new()
			node.position = v3(c.c)
			add_child(node)
			var col: Color = cap_cols[c.id % 3]
			_add(_cyl(c.r + 6, c.r + 8, 4), _m_black, Vector3(0, 0.02, 0), node)
			var body_mat := _mat(Color(col, 0.85), 0.0, 0.2, col, 0.4)
			body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_add(_cyl(c.r * 0.8, c.r * 0.85, 30), body_mat, Vector3(0, 0.19, 0), node)
			var cap_mat := _mat(col.darkened(0.2), 0.0, 0.3, col, 0.3)
			var cap := _add(_cyl(c.r + 2, c.r + 2, 10), cap_mat, Vector3(0, 0.39, 0), node)
			var top_mat := _mat(Color(0.95, 0.95, 0.95), 0.0, 0.3, col, 0.15)
			_add(_cyl(c.r * 0.6, c.r * 0.6, 2), top_mat, Vector3(0, 0.45, 0), node)
			var skirt := _add(_torus(c.r - 2, c.r + 3), _m_chrome, Vector3(0, 0.08, 0), node)
			_bumper_nodes.append({"phys": c, "body": body_mat, "cap": cap_mat, "top": top_mat,
				"skirt": skirt, "color": col, "cap_node": cap})
		elif c.kind == "pin":
			_add(_cyl(c.r, c.r, 40), _m_chrome, v3(c.c, 20))
		else:
			_add(_cyl(3, 3, 44), _m_chrome, v3(c.c, 22))
			_add(_cyl(5, 5, 4), _m_chrome, v3(c.c, 44))
			var ring := _add(_torus(c.r - 4.5, c.r + 1.0), _m_rubber, v3(c.c, 16))
			_post_nodes.append({"phys": c, "ring": ring})


func _build_slings() -> void:
	for s in phys.slings:
		var a: Vector2 = s.b
		var c: Vector2 = s.a
		var b := Vector2(a.x, a.y + 120)
		var centroid := (a + b + c) / 3.0
		var inner := PackedVector2Array()
		for p in [a, b, c]:
			inner.append(centroid + (p - centroid) * 0.82)
		_add(_prism(inner, 0, 36), _mat(Color(0.12, 0.1, 0.16), 0.3, 0.4), Vector3.ZERO)
		var col := Color(1.0, 0.25, 0.65)
		var plastic := _mat(Color(col, 0.7), 0.0, 0.15, col, 0.5)
		plastic.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var cover := PackedVector2Array()
		for p in [a, b, c]:
			cover.append(centroid + (p - centroid) * 1.12)
		_add(_prism(cover, 40, 44), plastic, Vector3.ZERO)
		var band := _seg_box(c, a, 3.0, 8, 26, _m_rubber)
		_sling_nodes.append({"phys": s, "plastic": plastic, "band": band, "base": band.position,
			"normal": (c - a).orthogonal().normalized(), "color": col})


func _flipper_poly(rb: float, rt: float, length: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 13:
		var ang := PI / 2 + PI * i / 12.0
		pts.append(Vector2(cos(ang), sin(ang)) * rb)
	for i in 13:
		var ang := -PI / 2 + PI * i / 12.0
		pts.append(Vector2(length, 0) + Vector2(cos(ang), sin(ang)) * rt)
	return pts


func _build_flippers() -> void:
	var white := _mat(Color(0.96, 0.96, 0.98), 0.0, 0.2)
	var red := _mat(Color(0.95, 0.12, 0.2), 0.0, 0.6)
	for f in phys.flippers:
		var node := Node3D.new()
		node.position = v3(f.pivot)
		add_child(node)
		var mesh_root := Node3D.new()
		mesh_root.position = Vector3(-f.pivot.x * S, 0, -f.pivot.y * S)
		var body := _flipper_poly(f.rb - 3.0, f.rt - 3.0, f.length)
		var rubber := _flipper_poly(f.rb + 1.0, f.rt + 1.0, f.length)
		var body_w := PackedVector2Array()
		var rubber_w := PackedVector2Array()
		for p in body:
			body_w.append(p + f.pivot)
		for p in rubber:
			rubber_w.append(p + f.pivot)
		node.add_child(mesh_root)
		_add(_prism(rubber_w, 3, 17), red, Vector3.ZERO, mesh_root)
		_add(_prism(body_w, 0, 24), white, Vector3.ZERO, mesh_root)
		_add(_cyl(6, 6, 4), _m_chrome, Vector3(0, 0.25, 0), node)
		_flipper_nodes.append(node)


func _build_drops() -> void:
	var col := Color(1.0, 0.75, 0.15)
	for d in phys.drops:
		var node := Node3D.new()
		node.position = v3((d.a + d.b) * 0.5)
		node.rotation.y = -atan2(d.b.y - d.a.y, d.b.x - d.a.x)
		add_child(node)
		var length: float = (d.b - d.a).length()
		var box := BoxMesh.new()
		box.size = Vector3(length * S, 0.44, 0.1)
		_add(box, _mat(col, 0.0, 0.35, col, 0.25), Vector3(0, 0.22, 0), node)
		var stripe := BoxMesh.new()
		stripe.size = Vector3(length * S * 0.9, 0.06, 0.105)
		_add(stripe, _mat(Color.WHITE, 0.0, 0.3, Color.WHITE, 0.6), Vector3(0, 0.33, 0), node)
		_drop_nodes.append(node)
	# Standups in der Stargate-Tasche.
	for t in phys.standups:
		var m := _mat(Color(0.2, 0.9, 1.0), 0.0, 0.3, Color(0.2, 0.9, 1.0), 0.3)
		var box := BoxMesh.new()
		box.size = Vector3((t.b.x - t.a.x) * S, 0.38, 0.06)
		_add(box, m, v3((t.a + t.b) * 0.5, 19))
		_add(_cyl(2, 2, 40), _m_metal, v3((t.a + t.b) * 0.5 + Vector2(0, -8), 20))
		_standup_mats.append(m)


## Rampen und Drahtbahnen aus den Tracks der Physik.
func _build_tracks() -> void:
	var rail_mat := _mat(Color(0.7, 0.95, 1.0), 0.3, 0.2, Color(0.3, 0.9, 1.0), 1.6)
	rail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rail_mats.append(rail_mat)
	for key in phys.tracks:
		var tr = phys.tracks[key]
		var plastic_end: float = tr.lengths[tr.plastic_until]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var rails := SurfaceTool.new()
		rails.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wire := SurfaceTool.new()
		wire.begin(Mesh.PRIMITIVE_TRIANGLES)
		var step := 12.0
		var n := int(tr.total / step) + 1
		var prev := {}
		var half := 22.0
		for i in n + 1:
			var dist := minf(i * step, tr.total - 0.01)
			var p3: Vector3 = tr.point(dist)
			var q3: Vector3 = tr.point(minf(dist + 6.0, tr.total))
			var p := Vector2(p3.x, p3.y)
			var dir := Vector2(q3.x, q3.y) - p
			dir = dir.normalized() if dir.length() > 0.5 else Vector2.UP
			var nrm := dir.orthogonal()
			var h := p3.z
			var cur := {
				"l": v3(p + nrm * half, h - 2), "r": v3(p - nrm * half, h - 2),
				"lt": v3(p + nrm * half, h + 22), "rt": v3(p - nrm * half, h + 22),
				"wl": v3(p + nrm * 12.0, h - 6), "wr": v3(p - nrm * 12.0, h - 6),
				"wtl": v3(p + nrm * 16.0, h + 10), "wtr": v3(p - nrm * 16.0, h + 10),
			}
			if not prev.is_empty():
				if dist <= plastic_end:
					for q in [prev["l"], cur["l"], cur["r"], prev["l"], cur["r"], prev["r"]]:
						st.add_vertex(q)
					for q in [prev["l"], prev["lt"], cur["lt"], prev["l"], cur["lt"], cur["l"],
							prev["r"], cur["r"], cur["rt"], prev["r"], cur["rt"], prev["rt"]]:
						st.add_vertex(q)
					_strip(rails, prev["lt"], cur["lt"], 5.0)
					_strip(rails, prev["rt"], cur["rt"], 5.0)
				elif h > 4.0 or key == "vuk":
					for k in ["wl", "wr", "wtl", "wtr"]:
						_strip(wire, prev[k], cur[k], 3.0)
			prev = cur
			if i % 10 == 5 and h > 50.0 and key != "vuk":
				_add(_cyl(2.5, 2.5, h), _m_chrome, v3(p + nrm * (half + 4), h * 0.5))
		st.generate_normals()
		_add(st.commit(), _m_ramp, Vector3.ZERO)
		rails.generate_normals()
		_add(rails.commit(), rail_mat, Vector3.ZERO)
		wire.generate_normals()
		var wire_mat := _mat(Color(0.9, 0.92, 0.97), 0.7, 0.2, Color(0.75, 0.8, 0.9), 0.35)
		wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_add(wire.commit(), wire_mat, Vector3.ZERO)


## Dünnes Band (zwei Dreiecke, kreuzweise) als Draht zwischen zwei Punkten.
func _strip(st: SurfaceTool, a: Vector3, b: Vector3, width: float) -> void:
	var up := Vector3(0, width * S, 0)
	var dir := (b - a).normalized()
	var side := dir.cross(Vector3.UP).normalized() * width * S
	for q in [a - up * 0.5, b - up * 0.5, b + up * 0.5, a - up * 0.5, b + up * 0.5, a + up * 0.5,
			a - side * 0.5, b - side * 0.5, b + side * 0.5, a - side * 0.5, b + side * 0.5, a + side * 0.5]:
		st.add_vertex(q)


## Launch Pad: Scoop-Ring und die Rakete als Toy über der Gasse.
func _build_rocket() -> void:
	_add(_torus(18, 24), _m_chrome, v3(Phys.SCOOP_POS, 1))
	_rocket = Node3D.new()
	_rocket.position = v3(Vector2(470, 850), 72)
	add_child(_rocket)
	var white := _mat(Color(0.92, 0.93, 0.98), 0.3, 0.25)
	var red := _mat(Color(0.95, 0.2, 0.35), 0.1, 0.3)
	# Rumpf liegt entlang der Tischachse, Spitze zeigt nach oben (-z).
	var body := _add(_cyl(26, 26, 130), white, Vector3.ZERO, _rocket)
	body.rotation.x = PI / 2
	var nose := _add(_cyl(0.5, 26, 60), red, Vector3(0, 0, -0.95), _rocket)
	nose.rotation.x = -PI / 2
	var engine := _add(_cyl(20, 14, 18), _mat(Color(0.3, 0.3, 0.35), 0.8, 0.3), Vector3(0, 0, 0.74), _rocket)
	engine.rotation.x = PI / 2
	var window := _add(_cyl(11, 11, 4), _mat(Color(0.2, 0.75, 1.0), 0.2, 0.1, Color(0.2, 0.75, 1.0), 1.5),
		Vector3(0, 0.25, -0.35), _rocket)
	window.rotation.x = 0
	for side in [-1.0, 1.0]:
		var fin := BoxMesh.new()
		fin.size = Vector3(0.5, 0.05, 0.4)
		_add(fin, red, Vector3(0.4 * side, -0.05, 0.45), _rocket)
	var stripe := _add(_cyl(26.5, 26.5, 10), red, Vector3(0, 0, 0.25), _rocket)
	stripe.rotation.x = PI / 2
	_flame_mat = _mat(Color(1.0, 0.6, 0.1, 0.8), 0.0, 0.5, Color(1.0, 0.55, 0.1), 0.0)
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame = _add(_cyl(16, 1, 70), _flame_mat, Vector3(0, 0, 1.18), _rocket)
	_flame.rotation.x = -PI / 2
	# Halterungen
	for z in [-0.3, 0.4]:
		_add(_cyl(3, 3, 72), _m_metal, Vector3(0.36, -0.36, z), _rocket)
		_add(_cyl(3, 3, 72), _m_metal, Vector3(-0.36, -0.36, z), _rocket)


func _insert_mesh(ins: Dictionary) -> Mesh:
	var s: float = ins["size"]
	var poly := PackedVector2Array()
	match ins["shape"]:
		"arrow":
			var ang: float = ins.get("angle", 0.0)
			var dir := Vector2.from_angle(ang)
			var side := dir.orthogonal()
			for p in [dir * s, -dir * s * 0.7 + side * s * 0.85, -dir * s * 0.3,
					-dir * s * 0.7 - side * s * 0.85]:
				poly.append(p)
		"rect":
			poly = PackedVector2Array([Vector2(-s, -s * 0.6), Vector2(s, -s * 0.6),
				Vector2(s, s * 0.6), Vector2(-s, s * 0.6)])
		_:
			for i in 24:
				poly.append(Vector2.from_angle(TAU * i / 24.0) * s)
	var origin := PackedVector2Array()
	var pos: Vector2 = ins["pos"]
	for p in poly:
		origin.append(p + pos)
	return _prism(origin, 0, 1.2, false)


func _build_inserts() -> void:
	for ins in Layout.inserts():
		var col: Color = ins["color"]
		var m := _mat(col.darkened(0.55), 0.0, 0.15, col, 0.05)
		m.emission_enabled = true
		_add(_insert_mesh(ins), m, Vector3.ZERO)
		_insert_mats[ins["key"]] = m
		_insert_colors[ins["key"]] = col
		if ins.has("text"):
			var lbl := Label3D.new()
			lbl.text = ins["text"]
			lbl.font_size = 48
			lbl.pixel_size = 0.0045
			lbl.outline_size = 0
			lbl.modulate = Color(1, 1, 1, 0.9)
			lbl.rotation = Vector3(-PI / 2, 0, 0)
			lbl.position = v3(ins["pos"], 1.6)
			lbl.shaded = false
			add_child(lbl)


func _build_toys() -> void:
	# Spinner in der Orbit-Bahn.
	var x0: float = Phys.SPINNER_X0
	var x1: float = Phys.SPINNER_X1
	var y: float = Phys.SPINNER_Y
	for x in [x0 - 4.0, x1 + 4.0]:
		_add(_cyl(3, 3, 56), _m_chrome, v3(Vector2(x, y), 28))
	_spinner = Node3D.new()
	_spinner.position = v3(Vector2((x0 + x1) * 0.5, y), 50)
	add_child(_spinner)
	var plate := BoxMesh.new()
	plate.size = Vector3((x1 - x0) * S, 0.34, 0.015)
	var plate_mat := _mat(Color(0.8, 0.85, 0.95), 0.9, 0.2, Color(0.3, 0.9, 1.0), 0.2)
	_add(plate, plate_mat, Vector3(0, -0.17, 0), _spinner)

	# Plunger mit Stange und Griff.
	_plunger = Node3D.new()
	add_child(_plunger)
	var rod := _cyl(5, 5, 160)
	var rod_mi := _add(rod, _m_chrome, Vector3(0, 0, 0.8), _plunger)
	rod_mi.rotation.x = PI / 2
	var tip := _cyl(12, 12, 10)
	var tip_mi := _add(tip, _mat(Color(0.15, 0.15, 0.18), 0.4, 0.4), Vector3(0, 0, 0.0), _plunger)
	tip_mi.rotation.x = PI / 2
	var knob := SphereMesh.new()
	knob.radius = 0.22
	knob.height = 0.3
	_add(knob, _mat(Color(0.9, 0.1, 0.2), 0.2, 0.25), Vector3(0, 0.3, 1.72), _plunger)

	# Blitzlichter oben links und rechts.
	for side in 2:
		var pos := Vector2(140, 300) if side == 0 else Vector2(805, 220)
		var col := Color(1.0, 0.2, 0.3) if side == 0 else Color(0.25, 0.6, 1.0)
		var dome := SphereMesh.new()
		dome.radius = 0.2
		dome.height = 0.2
		dome.is_hemisphere = true
		var mat := _mat(Color(col, 0.8), 0.0, 0.1, col, 0.2)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_add(_cyl(24, 26, 6), _m_black, v3(pos, 3))
		_add(dome, mat, v3(pos, 6))
		_flasher_mats.append(mat)
		var light := OmniLight3D.new()
		light.position = v3(pos, 60)
		light.light_color = col
		light.light_energy = 0.0
		light.omni_range = 7.0
		add_child(light)
		if side == 0:
			_flasher_l = light
		else:
			_flasher_r = light


func _ensure_balls(count: int) -> void:
	while _ball_nodes.size() < count:
		var sphere := SphereMesh.new()
		sphere.radius = Phys.BALL_R * S
		sphere.height = Phys.BALL_R * 2.0 * S
		sphere.radial_segments = 32
		sphere.rings = 16
		var mi := _add(sphere, _m_ball, Vector3.ZERO)
		_ball_nodes.append(mi)


# ---------------------------------------------------------------- Update

func _is_lit(state: int, phase := 0.0) -> bool:
	match state:
		1:
			return true
		2:
			return fmod(_time + phase, 0.5) < 0.25
		3:
			return fmod(_time + phase, 0.16) < 0.08
	return false


func _process(delta: float) -> void:
	if phys == null:
		return
	_time += delta

	# Bälle.
	_ensure_balls(phys.balls.size())
	for i in _ball_nodes.size():
		var mi := _ball_nodes[i]
		if i < phys.balls.size():
			var b = phys.balls[i]
			mi.visible = true
			mi.position = v3(b.pos, Phys.BALL_R + b.height)
			mi.basis = b.roll
		else:
			mi.visible = false

	# Flipper.
	for i in _flipper_nodes.size():
		_flipper_nodes[i].rotation.y = -phys.flippers[i].angle

	# Bumper.
	var any_bumper := 0.0
	for bn in _bumper_nodes:
		var c = bn["phys"]
		var t := clampf(c.flash / 0.18, 0.0, 1.0)
		any_bumper = maxf(any_bumper, t)
		(bn["cap"] as StandardMaterial3D).emission_energy_multiplier = 0.3 + 4.0 * t
		(bn["body"] as StandardMaterial3D).emission_energy_multiplier = 0.4 + 4.0 * t
		(bn["top"] as StandardMaterial3D).emission_energy_multiplier = 0.15 + 6.0 * t
		(bn["skirt"] as Node3D).position.y = 0.08 - 0.06 * t
	flash_bumpers = maxf(flash_bumpers - delta * 4.0, any_bumper)
	_bumper_light.light_energy = 2.5 * flash_bumpers

	# Slingshots.
	for sn in _sling_nodes:
		var s = sn["phys"]
		var t := clampf(s.flash / 0.15, 0.0, 1.0)
		(sn["plastic"] as StandardMaterial3D).emission_energy_multiplier = 0.5 + 5.0 * t
		var band := sn["band"] as Node3D
		var nrm: Vector2 = sn["normal"]
		band.position = (sn["base"] as Vector3) + Vector3(nrm.x, 0, nrm.y) * 0.06 * t

	# Pfosten zittern leicht bei harten Treffern.
	for pn in _post_nodes:
		var c = pn["phys"]
		(pn["ring"] as Node3D).scale = Vector3.ONE * (1.0 + 0.15 * c.flash / 0.1)

	# Drop-Targets fallen ins Spielfeld.
	for i in _drop_nodes.size():
		var target := 0.0 if phys.drops[i].active else -0.5
		var node := _drop_nodes[i]
		node.position.y = lerpf(node.position.y, target, minf(1.0, delta * 18.0))

	# Standups leuchten bei Treffern.
	for i in _standup_mats.size():
		var t := clampf(phys.standups[i].flash / 0.25, 0.0, 1.0)
		_standup_mats[i].emission_energy_multiplier = 0.3 + 4.0 * t

	# Rakete und Rampenlicht.
	rocket_shake = maxf(0.0, rocket_shake - delta * 1.5)
	_rocket.rotation.z = sin(_time * 40.0) * 0.06 * rocket_shake
	_rocket.position.y = 0.72 + absf(sin(_time * 31.0)) * 0.03 * rocket_shake
	var thrust := clampf(rocket_thrust + rocket_shake * 0.5, 0.0, 1.0)
	_flame.visible = thrust > 0.02
	_flame.scale = Vector3(1.0, 0.6 + 0.4 * thrust + 0.1 * sin(_time * 50.0), 1.0)
	_flame_mat.emission_energy_multiplier = 4.0 * thrust
	for m in _rail_mats:
		m.emission = m.emission.lerp(ramp_color, minf(1.0, delta * 4.0))

	# Spinner, Gate und Plunger.
	_spinner.rotation.x = phys.spinner_angle
	if _gate:
		var swing := 0.0
		for b in phys.balls:
			if b.pos.x > 880.0 and b.pos.y < 600.0 and b.pos.y > 440.0:
				swing = 1.2
		_gate.rotation.x = lerpf(_gate.rotation.x, swing, minf(1.0, delta * 12.0))
	var py: float = Phys.PLUNGER_Y + Phys.PLUNGER_TRAVEL * phys.plunger_charge
	_plunger.position = v3(Vector2(Phys.LANE_X, py + 5.0), 14)

	# Lampen-Einsätze.
	for key in _insert_mats:
		var val = lamps.get(key, 0)
		var state := 0
		if val is Array:
			state = int(val[0])
			_insert_mats[key].emission = val[1]
			_insert_mats[key].albedo_color = (val[1] as Color).darkened(0.6)
		else:
			state = int(val)
		var lit := _is_lit(state, float(hash(key) % 7) * 0.03)
		var m: StandardMaterial3D = _insert_mats[key]
		var target := 3.2 if lit else 0.06
		m.emission_energy_multiplier = lerpf(m.emission_energy_multiplier, target, minf(1.0, delta * 25.0))

	# Blitzlichter.
	flash_left = maxf(0.0, flash_left - delta * 3.0)
	flash_right = maxf(0.0, flash_right - delta * 3.0)
	_flasher_l.light_energy = 6.0 * flash_left
	_flasher_r.light_energy = 6.0 * flash_right
	_flasher_mats[0].emission_energy_multiplier = 0.2 + 8.0 * flash_left
	_flasher_mats[1].emission_energy_multiplier = 0.2 + 8.0 * flash_right

	# Kamera-Wackler bei großen Ereignissen.
	shake = maxf(0.0, shake - delta * 2.5)
	var off := Vector3(sin(_time * 53.0), 0, cos(_time * 47.0)) * 0.06 * shake * shake
	camera.position = _cam_base + off


func flash(which: String, amount := 1.0) -> void:
	if which == "left" or which == "both":
		flash_left = maxf(flash_left, amount)
	if which == "right" or which == "both":
		flash_right = maxf(flash_right, amount)
