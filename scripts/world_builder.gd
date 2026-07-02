class_name WorldBuilder
extends Node3D
## Builds and streams the tunnel geometry (PLAN.md D2): chunked quad meshes ahead of
## the player, freed behind — the Godot port of the web build's buildChunk/disposeChunk/
## ensureWorld/buildCap/spawnPortal, plus Phase E door quads for locked arenas.

signal tunnel_spawn_requested(ring_idx: int)

const CHUNK := 14              # rings per geometry chunk
const BUILD_AHEAD := 110       # keep geometry built this many rings ahead
const FREE_BEHIND := 18        # free geometry this many rings behind
const MAX_ARENA_LIGHTS := 6

var path: PathGen
var mats: Dictionary            # {wall, floor, ceil} StandardMaterial3D
var accent_color := Color("55ffee")

var _chunks: Array[Dictionary] = []      # {node, start, end}
var _built_up_to := 0
var _caps: Array[MeshInstance3D] = []
var _doors := {}                          # arena_id -> {node, ring, open}
var _lights: Array[Dictionary] = []       # {light, idx}
var _portal: Node3D
var _portal_ring: MeshInstance3D
var _portal_pulse := 0.0
var portal_position := Vector3.ZERO
var portal_active := false


func rebuild(new_path: PathGen, theme_mats: Dictionary, accent: Color) -> void:
	clear_world()
	path = new_path
	mats = theme_mats
	accent_color = accent
	var initial: int = mini(CHUNK * 8, path.rings.size() - 1)
	while _built_up_to + CHUNK <= initial:
		_build_chunk(_built_up_to, _built_up_to + CHUNK)
		_built_up_to += CHUNK
	_build_cap(0)
	_build_cap(path.rings.size() - 1)
	_build_doors()
	_spawn_portal()


func clear_world() -> void:
	for c in _chunks:
		c.node.queue_free()
	_chunks.clear()
	for cap in _caps:
		cap.queue_free()
	_caps.clear()
	for id in _doors:
		_doors[id].node.queue_free()
	_doors.clear()
	for l in _lights:
		l.light.queue_free()
	_lights.clear()
	if _portal:
		_portal.queue_free()
		_portal = null
	portal_active = false
	_built_up_to = 0


func ensure_world(player_ring: int) -> void:
	var last := path.rings.size() - 1
	while _built_up_to < last and _built_up_to - player_ring < BUILD_AHEAD:
		var end := mini(_built_up_to + CHUNK, last)
		_build_chunk(_built_up_to, end)
		_built_up_to = end
	while not _chunks.is_empty() and _chunks[0].end < player_ring - FREE_BEHIND:
		_chunks[0].node.queue_free()
		_chunks.pop_front()
	while not _lights.is_empty() and _lights[0].idx < player_ring - FREE_BEHIND:
		_lights[0].light.queue_free()
		_lights.pop_front()


func animate(delta: float) -> void:
	if _portal and portal_active:
		_portal_pulse += delta * 3.0
		_portal_ring.rotate_object_local(Vector3(0, 0, 1), delta * 1.6)
		_portal.scale = Vector3.ONE * (1.0 + sin(_portal_pulse) * 0.05)


## True when a closed door blocks travel at or before this ring.
func door_blocking(ring_idx: int) -> int:
	for id in _doors:
		var d: Dictionary = _doors[id]
		if not d.open and ring_idx >= d.ring - 1:
			return d.ring
	return -1


func open_door(arena_id: int) -> void:
	if not _doors.has(arena_id) or _doors[arena_id].open:
		return
	var d: Dictionary = _doors[arena_id]
	d.open = true
	var ring: Dictionary = path.rings[d.ring]
	var tween := create_tween()
	tween.tween_property(d.node, "position", d.node.position + ring.u * (ring.hh * 2.2), 0.9) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func is_door_open(arena_id: int) -> bool:
	return _doors.has(arena_id) and _doors[arena_id].open


# ---------- geometry ----------

func _build_chunk(s: int, e: int) -> void:
	var surfaces := {
		"floor": SurfaceTool.new(), "ceil": SurfaceTool.new(), "wall": SurfaceTool.new(),
	}
	for key in surfaces:
		surfaces[key].begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(s, e):
		var r0: Dictionary = path.rings[i]
		var r1: Dictionary = path.rings[i + 1]
		var u0 := i * 1.3
		var u1 := (i + 1) * 1.3
		var vf0: float = r0.hw / 3.0
		var vf1: float = r1.hw / 3.0
		var vw0: float = r0.hh / 3.0
		var vw1: float = r1.hh / 3.0
		_quad(surfaces.floor, r0.u,
			path.corner(r0, -1, -1), path.corner(r0, 1, -1),
			path.corner(r1, 1, -1), path.corner(r1, -1, -1),
			[Vector2(u0, 0), Vector2(u0, vf0), Vector2(u1, vf1), Vector2(u1, 0)])
		_quad(surfaces.ceil, -r0.u,
			path.corner(r0, -1, 1), path.corner(r0, 1, 1),
			path.corner(r1, 1, 1), path.corner(r1, -1, 1),
			[Vector2(u0, 0), Vector2(u0, vf0), Vector2(u1, vf1), Vector2(u1, 0)])
		_quad(surfaces.wall, r0.r,
			path.corner(r0, -1, -1), path.corner(r0, -1, 1),
			path.corner(r1, -1, 1), path.corner(r1, -1, -1),
			[Vector2(u0, 0), Vector2(u0, vw0), Vector2(u1, vw1), Vector2(u1, 0)])
		_quad(surfaces.wall, -r0.r,
			path.corner(r0, 1, -1), path.corner(r0, 1, 1),
			path.corner(r1, 1, 1), path.corner(r1, 1, -1),
			[Vector2(u0, 0), Vector2(u0, vw0), Vector2(u1, vw1), Vector2(u1, 0)])
	var chunk_node := Node3D.new()
	for key in surfaces:
		var mi := MeshInstance3D.new()
		mi.mesh = surfaces[key].commit()
		mi.material_override = mats[key]
		chunk_node.add_child(mi)
	add_child(chunk_node)
	_chunks.append({"node": chunk_node, "start": s, "end": e})
	for ri in range(s, e):
		var ring: Dictionary = path.rings[ri]
		if ring.arena_center and _lights.size() < MAX_ARENA_LIGHTS:
			var light := OmniLight3D.new()
			light.light_color = Color("ff5533") if (ri % 2 == 0) else Color("3388ff")
			light.light_energy = 1.1
			light.omni_range = 80.0
			light.position = ring.p + ring.u * (ring.hh * 0.5)
			add_child(light)
			_lights.append({"light": light, "idx": ri})
		# tunnel enemies spawn by chance as geometry streams in (arena enemies are
		# pre-spawned deterministically by the game for exact door kill-counts)
		if ri > 20 and ring.arena_id < 0:
			tunnel_spawn_requested.emit(ri)


func _quad(st: SurfaceTool, normal: Vector3, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		uvs: Array) -> void:
	st.set_normal(normal)
	for tri in [[0, 1, 2], [0, 2, 3]]:
		for idx in tri:
			st.set_uv(uvs[idx])
			st.add_vertex([a, b, c, d][idx])


func _build_cap(idx: int) -> void:
	var ring: Dictionary = path.rings[idx]
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(ring.hw * 2.0, ring.hh * 2.0)
	mi.mesh = quad
	mi.material_override = mats.wall
	mi.transform = _ring_transform(ring)
	add_child(mi)
	_caps.append(mi)


func _build_doors() -> void:
	for arena in path.arenas:
		if arena.door_ring < 0:
			continue
		var ring: Dictionary = path.rings[arena.door_ring]
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(ring.hw * 2.0 + 2.0, ring.hh * 2.0 + 2.0)
		mi.mesh = quad
		var door_mat: StandardMaterial3D = mats.wall.duplicate()
		door_mat.albedo_color = Color(0.7, 0.7, 0.75)
		door_mat.emission_enabled = true
		door_mat.emission = accent_color
		door_mat.emission_energy_multiplier = 0.25
		mi.material_override = door_mat
		mi.transform = _ring_transform(ring)
		add_child(mi)
		_doors[arena.id] = {"node": mi, "ring": arena.door_ring, "open": false}


func _ring_transform(ring: Dictionary) -> Transform3D:
	return Transform3D(Basis(ring.r, ring.u, -ring.d), ring.p)


func _spawn_portal() -> void:
	var ring: Dictionary = path.rings[path.rings.size() - 6]
	_portal = Node3D.new()
	_portal_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 4.5
	torus.outer_radius = 5.9
	torus.rings = 20
	torus.ring_segments = 8
	var torus_mat := StandardMaterial3D.new()
	torus_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus_mat.albedo_color = Color("55ffee")
	_portal_ring.mesh = torus
	_portal_ring.material_override = torus_mat
	# TorusMesh lies flat around Y; stand it up so the hole faces along the ring axis
	_portal_ring.rotation_degrees.x = 90.0
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 4.5
	cyl.bottom_radius = 4.5
	cyl.height = 0.1
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.albedo_color = Color(0.05, 0.2, 0.27, 0.6)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.mesh = cyl
	disc.material_override = disc_mat
	disc.rotation_degrees.x = 90.0
	_portal.add_child(_portal_ring)
	_portal.add_child(disc)
	_portal.transform = _ring_transform(ring)
	var light := OmniLight3D.new()
	light.light_color = Color("55ffee")
	light.light_energy = 1.6
	light.omni_range = 60.0
	_portal.add_child(light)
	add_child(_portal)
	portal_position = ring.p
	portal_active = true
