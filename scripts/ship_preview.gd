class_name ShipPreview
extends SubViewportContainer
## PR G: the Upgrade Bay's live ship turntable. A small SubViewport with its own
## world renders the player's ship, built from primitives in code, and each
## installed ship-system rank adds a visible part: SHIELD a halo ring, HEAT SINK
## radiator fins, ENERGY a brighter core, MSL RACK pods under the wings, MAGNET a
## dish, HULL armour plates, ENGINES bigger nozzles, THRUSTERS side pods.
## Plain colours, kept to the game's grey-plus-one-accent look.

const SPIN := 0.7   # rad/s

var _vp: SubViewport
var _pivot: Node3D
var _parts: Node3D
var part_names: Array[String] = []   # what the last rebuild added, for tests


func _init(px: Vector2i = Vector2i(134, 50)) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # decoration: never eats a Bay click
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vp = SubViewport.new()
	_vp.size = px
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.1, 3.7)
	cam.fov = 34.0
	_vp.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0.0, 0.05, 0.0))
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.light_energy = 1.3
	_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.35, 0.38, 0.45)
	_vp.add_child(env)
	_pivot = Node3D.new()
	_pivot.rotation.x = 0.12
	_vp.add_child(_pivot)
	_pivot.add_child(_base_hull())
	_parts = Node3D.new()
	_pivot.add_child(_parts)
	refresh()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_pivot.rotation.y = fmod(_pivot.rotation.y + SPIN * delta, TAU)


## Rebuild the rank parts from GameState.ship_ranks.
func refresh() -> void:
	for c in _parts.get_children():
		c.free()
	part_names.clear()
	var r: Dictionary = GameState.ship_ranks
	var steel := _mat(Color(0.55, 0.57, 0.62))
	var glow_a := _glow(Color(0.35, 0.85, 1.0))
	# ENGINES: nozzle size grows per rank, rank 2 adds a third centre nozzle
	var nz := 0.13 + 0.05 * int(r.get("engines", 0))
	for x in [-0.28, 0.28] + ([0.0] if int(r.get("engines", 0)) >= 2 else []):
		_add("nozzle", _cyl(nz, nz * 1.25, 0.32, steel), Vector3(x, 0.0, 1.0), Vector3(PI / 2, 0, 0))
		_add("flame", _sphere(nz * 0.8, _glow(Color(1.0, 0.6, 0.2))), Vector3(x, 0.0, 1.2))
	if int(r.get("engines", 0)) > 0:
		part_names.append("engines")
	# THRUSTERS: side pods, longer at rank 2
	if int(r.get("thrusters", 0)) > 0:
		var ln := 0.35 + 0.15 * int(r.thrusters)
		for s in [-1.0, 1.0]:
			_add("thrusters", _cyl(0.08, 0.08, ln, steel), Vector3(s * 0.95, 0.06, 0.25),
				Vector3(PI / 2, 0, 0))
			_add("thrusters", _sphere(0.07, glow_a), Vector3(s * 0.95, 0.06, 0.25 + ln * 0.5))
	# SHIELD: halo ring, thicker per rank
	if int(r.get("shield", 0)) > 0:
		var tor := TorusMesh.new()
		tor.inner_radius = 1.15
		tor.outer_radius = 1.15 + 0.04 * int(r.shield)
		tor.material = _glow(Color(0.3, 0.6, 1.0))
		_add("shield", _mi(tor), Vector3.ZERO, Vector3(0.0, 0.0, 0.0))
	# HEAT SINK: radiator fins along the spine
	for i in int(r.get("heat", 0)) * 2:
		_add("heat", _box(Vector3(0.03, 0.18, 0.16), _mat(Color(0.75, 0.3, 0.25))),
			Vector3(-0.1 + 0.2 * (i % 2), 0.22, 0.35 - 0.22 * (i / 2)))
	# ENERGY: the cockpit core brightens per rank
	var e_rank := int(r.get("energy", 0))
	_add("energy" if e_rank > 0 else "core",
		_sphere(0.12 + 0.03 * e_rank, _glow(Color(0.4, 1.0, 0.5).lerp(Color.WHITE, 0.25 * e_rank))),
		Vector3(0.0, 0.16, -0.25))
	# MSL RACK: pods under the wings, one pair per rank
	for i in int(r.get("rack", 0)):
		for s in [-1.0, 1.0]:
			_add("rack", _cyl(0.05, 0.05, 0.42, _mat(Color(0.85, 0.8, 0.35))),
				Vector3(s * (0.5 + 0.16 * i), -0.14, 0.05), Vector3(PI / 2, 0, 0))
	# MAGNET: dish on a mast
	if int(r.get("magnet", 0)) > 0:
		_add("magnet", _cyl(0.015, 0.015, 0.25, steel), Vector3(0.0, 0.32, 0.55))
		_add("magnet", _cyl(0.16, 0.02, 0.05, _mat(Color(0.95, 0.7, 0.25))), Vector3(0.0, 0.46, 0.55))
	# HULL: armour plates on the flanks
	if int(r.get("hull", 0)) > 0:
		for s in [-1.0, 1.0]:
			_add("hull", _box(Vector3(0.06, 0.16, 0.9), _mat(Color(0.5, 0.52, 0.58))),
				Vector3(s * 0.25, 0.02, 0.1))


func has_part(name: String) -> bool:
	return part_names.has(name)


func _base_hull() -> Node3D:
	var root := Node3D.new()
	var body := _mat(Color(0.62, 0.64, 0.7))
	var dark := _mat(Color(0.25, 0.27, 0.33))
	var nose := PrismMesh.new()
	nose.size = Vector3(0.5, 0.3, 1.0)
	var nose_mi := _mi(nose)
	nose_mi.material_override = body
	nose_mi.position = Vector3(0.0, 0.0, -0.65)
	nose_mi.rotation = Vector3(-PI / 2, 0.0, 0.0)
	root.add_child(nose_mi)
	var fus := BoxMesh.new()
	fus.size = Vector3(0.46, 0.26, 1.1)
	var fus_mi := _mi(fus)
	fus_mi.material_override = body
	fus_mi.position = Vector3(0.0, 0.0, 0.45)
	root.add_child(fus_mi)
	for s in [-1.0, 1.0]:
		var wing := BoxMesh.new()
		wing.size = Vector3(0.9, 0.05, 0.55)
		var w := _mi(wing)
		w.material_override = dark
		w.position = Vector3(s * 0.6, -0.04, 0.35)
		w.rotation = Vector3(0.0, s * 0.35, 0.0)
		root.add_child(w)
	var canopy := SphereMesh.new()
	canopy.radius = 0.16
	canopy.height = 0.2
	var c := _mi(canopy)
	c.material_override = _mat(Color(0.2, 0.35, 0.55))
	c.position = Vector3(0.0, 0.14, -0.05)
	c.scale = Vector3(1.0, 1.0, 1.8)
	root.add_child(c)
	return root


func _add(name: String, mi: MeshInstance3D, pos: Vector3, rot := Vector3.ZERO) -> void:
	mi.position = pos
	mi.rotation = rot
	_parts.add_child(mi)
	if name != "nozzle" and name != "flame" and name != "core" and not part_names.has(name):
		part_names.append(name)


func _mi(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _box(size: Vector3, m: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	b.material = m
	return _mi(b)


func _cyl(top: float, bottom: float, h: float, m: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	c.material = m
	return _mi(c)


func _sphere(r: float, m: Material) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 8
	s.rings = 4
	s.material = m
	return _mi(s)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	m.metallic = 0.3
	return m


func _glow(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m
