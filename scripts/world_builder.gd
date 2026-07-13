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
const VIS_AHEAD := 36          # draw window: 432 m ahead > camera.far and every fog_end
const SPAWN_AHEAD := 24        # roll tunnel-spawn dice this far ahead of the player

var path: PathGen
var mats: Dictionary            # {wall, floor, ceil, strip, strip_frames} (TextureGen.theme_set)
var accent_color := Color("55ffee")
var accent2_color := Color("ff5533")

var _chunks: Array[Dictionary] = []      # {node, start, end}
var _built_up_to := 0
var _pending_lights: Array[Dictionary] = []   # {idx, color, mode, phase, pos}
var _spawn_cursor := 0
var _unit_box := BoxMesh.new()     # shared decoration meshes: instances scale via
var _unit_quad := QuadMesh.new()   # their Basis, so no per-instance mesh gen/upload
var _door_mat: StandardMaterial3D
var _caps: Array[MeshInstance3D] = []
var _doors := {}                          # arena_id -> {node, ring, open}
var _lights: Array[Dictionary] = []       # {light, idx, mode, phase, energy}
var _light_t := 0.0
var _portal: Node3D
var _portal_ring: MeshInstance3D
var _portal_pulse := 0.0
var _strip_t := 0.0        # V2.0 accent floor: frame-swap clock
var _strip_frame := 0
var portal_position := Vector3.ZERO
var portal_active := false


func rebuild(new_path: PathGen, theme_mats: Dictionary, accent: Color,
		accent2: Color = Color("ff5533")) -> void:
	clear_world()
	path = new_path
	mats = theme_mats
	accent_color = accent
	accent2_color = accent2
	_door_mat = mats.wall.duplicate()
	_door_mat.albedo_color = Color(0.7, 0.7, 0.75)
	_door_mat.emission_enabled = true
	_door_mat.emission = accent_color
	_door_mat.emission_energy_multiplier = 0.25
	# small synchronous head start (covers the deepest fog at the launch ring);
	# the briefing pump (prebuild_step) builds the rest of a finite level
	var initial: int = mini(CHUNK * 3, path.rings.size() - 1)
	while _built_up_to + CHUNK <= initial:
		_build_chunk(_built_up_to, _built_up_to + CHUNK)
		_built_up_to += CHUNK
	_build_cap(0)
	# K5 endless: no far cap and no exit portal — the tunnel just runs into the fog;
	# arenas (and their doors) are discovered and built while streaming instead
	if not path.is_endless:
		_build_cap(path.rings.size() - 1)
		_spawn_portal()
	_build_doors()


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
	_pending_lights.clear()
	_spawn_cursor = 0


## Budgeted prebuild pump: run while the briefing overlay is up so a finite
## level's whole tunnel is built (and its buffers uploaded — the tunnel renders
## behind the briefing with no draw window) before flight. Mid-level chunk
## builds were the recurring web-build stall this removes.
func prebuild_step(budget_usec: int) -> bool:
	if path == null or path.is_endless:
		return true
	var t0 := Time.get_ticks_usec()
	var last := path.rings.size() - 1
	while _built_up_to < last:
		var end := mini(_built_up_to + CHUNK, last)
		_build_chunk(_built_up_to, end)
		_built_up_to = end
		if Time.get_ticks_usec() - t0 >= budget_usec:
			break
	return _built_up_to >= last


func is_prebuilt() -> bool:
	return path != null and not path.is_endless \
		and _built_up_to >= path.rings.size() - 1


## Synchronous safety net for launches that outran the briefing pump
## (speed-clicks, tests calling _launch_level directly).
func prebuild_all() -> void:
	while not prebuild_step(1 << 30):
		pass


func update_streaming(player_ring: int) -> void:
	var last := path.rings.size() - 1
	# endless mode still streams geometry ahead (finite levels are prebuilt) —
	# hard-capped at ONE chunk build per frame: at cruise speed the player crosses
	# a ring in ~0.67 s, so a 14-ring chunk per frame outruns them ~500× while the
	# per-frame worst case stays one SurfaceTool commit instead of a burst
	if _built_up_to < last and _built_up_to - player_ring < BUILD_AHEAD:
		var end := mini(_built_up_to + CHUNK, last)
		_build_chunk(_built_up_to, end)
		_built_up_to = end
	while not _chunks.is_empty() and _chunks[0].end < player_ring - FREE_BEHIND:
		_chunks[0].node.queue_free()
		_chunks.pop_front()
	while not _lights.is_empty() and _lights[0].idx < player_ring - FREE_BEHIND:
		_lights[0].light.queue_free()
		_lights.pop_front()
	# arena lights are recorded at build time but instantiated by proximity, so a
	# prebuilt level fills its MAX_ARENA_LIGHTS slots exactly like streaming did
	while not _pending_lights.is_empty() \
			and _pending_lights[0].idx < player_ring + BUILD_AHEAD:
		var pl: Dictionary = _pending_lights.pop_front()
		if _lights.size() >= MAX_ARENA_LIGHTS:
			continue
		var light := OmniLight3D.new()
		light.light_color = pl.color
		light.light_energy = 1.1
		light.omni_range = 80.0
		light.position = pl.pos
		add_child(light)
		_lights.append({"light": light, "idx": pl.idx, "mode": pl.mode,
			"phase": pl.phase, "energy": 1.1})
	# tunnel-spawn dice roll just ahead of the player, not at build time: a
	# prebuilt level would roll every ring at once and the 300 u despawn would
	# cull the lot (which is what streaming already did, silently, to every
	# spawn past ~25 rings — so this is also the mid/late-level density fix)
	var spawn_to := mini(_built_up_to, player_ring + SPAWN_AHEAD)
	while _spawn_cursor < spawn_to:
		_spawn_cursor += 1
		if _spawn_cursor > 20 and path.rings[_spawn_cursor].arena_id < 0:
			tunnel_spawn_requested.emit(_spawn_cursor)
	# draw window: prebuilt chunks far beyond the fog stay resident but invisible
	for c in _chunks:
		c.node.visible = c.end >= player_ring - FREE_BEHIND \
			and c.start <= player_ring + VIS_AHEAD


func animate(delta: float) -> void:
	# V2.0 accent floor: march the light band down the corridor — an albedo
	# texture swap on ONE shared material, so no shader variants and WebGL-safe
	if mats.has("strip_frames"):
		_strip_t += delta
		var fi := int(_strip_t / 0.12) % (mats.strip_frames as Array).size()
		if fi != _strip_frame:
			_strip_frame = fi
			(mats.strip as StandardMaterial3D).albedo_texture = mats.strip_frames[fi]
	if _portal and portal_active:
		_portal_pulse += delta * 3.0
		_portal_ring.rotate_object_local(Vector3(0, 0, 1), delta * 1.6)
		_portal.scale = Vector3.ONE * (1.0 + sin(_portal_pulse) * 0.05)
	# K1/V-10: sector light moods — shimmering flicker and hard strobe. Energy-only
	# animation: no material or shader variant changes, so it's WebGL-safe.
	_light_t += delta
	for l in _lights:
		match l.mode:
			"flicker":
				l.light.light_energy = l.energy * (0.72 \
					+ 0.28 * sin(_light_t * 13.0 + l.phase) * sin(_light_t * 7.3 + l.phase * 2.0))
			"strobe":
				l.light.light_energy = l.energy \
					* (1.0 if fmod(_light_t + l.phase, 0.9) < 0.62 else 0.12)


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


## Small meshes carrying every material class this level can draw that isn't in
## view from the start ring — door (emissive wall variant), portal torus (unshaded)
## and portal disc (transparent) — added to the briefing warm-up rig so their
## shader variants compile behind the briefing overlay, not mid-flight.
func warmup_meshes(rig: Node3D, pos: Vector3) -> void:
	var door_mat: StandardMaterial3D = mats.wall.duplicate()
	door_mat.albedo_color = Color(0.7, 0.7, 0.75)
	door_mat.emission_enabled = true
	door_mat.emission = accent_color
	door_mat.emission_energy_multiplier = 0.25
	var torus_mat := StandardMaterial3D.new()
	torus_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	torus_mat.albedo_color = Color("55ffee")
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.albedo_color = Color(0.05, 0.2, 0.27, 0.6)
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var x := -1.4
	for mat: StandardMaterial3D in [door_mat, torus_mat, disc_mat]:
		# cull off so orientation can't hide the quad from the camera; cull mode is
		# rasterizer state, not a shader variant, so the same GL program compiles
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.2, 1.2)
		mi.mesh = quad
		mi.material_override = mat
		mi.position = pos + Vector3(x, 0, 0)
		x += 1.4
		rig.add_child(mi)


## Phase J: boss levels keep the exit ring dormant (dark and inert) until the boss
## falls — the reveal IS the level-complete gate, so no bulkhead is needed.
func set_portal_active(on: bool) -> void:
	portal_active = on
	if _portal:
		_portal.visible = on


# ---------- geometry ----------

func _build_chunk(s: int, e: int) -> void:
	var surfaces := {
		"floor": SurfaceTool.new(), "ceil": SurfaceTool.new(), "wall": SurfaceTool.new(),
		"strip": SurfaceTool.new(),
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
		# V2.0 accent floor strip: a narrow glowing centreline in plain tunnel only
		# (arenas/boss rooms keep their own lighting language). UV.y runs along the
		# tunnel so the marching band in the texture flows with the flight.
		if r0.arena_id < 0 and r1.arena_id < 0:
			var sw := 1.2
			var f0: Vector3 = r0.p + r0.u * (-(r0.hh - r0.fo) + 0.08)
			var f1: Vector3 = r1.p + r1.u * (-(r1.hh - r1.fo) + 0.08)
			_quad(surfaces.strip, r0.u,
				f0 - r0.r * sw, f0 + r0.r * sw, f1 + r1.r * sw, f1 - r1.r * sw,
				[Vector2(0, u0), Vector2(1, u0), Vector2(1, u1), Vector2(0, u1)])
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
		# K2/V-08: sector-style wall relief in arenas — pilasters and ceiling beams.
		# Everything protrudes at most 1.0 u, safely inside every collision margin
		# (player 1.6, enemy clamp ≥2.2, pickups 2.0), so it is purely visual and
		# needs no collision support. Boss rooms stay untouched (Phase J invariants).
		if ring.arena_id >= 0 and not path.is_boss and not ring.arena_center:
			if ri % 3 == 0:
				for side in [-1.0, 1.0]:
					var pilaster := MeshInstance3D.new()
					pilaster.mesh = _unit_box
					pilaster.material_override = mats.wall
					pilaster.transform = Transform3D(
						Basis(ring.r, ring.u * (ring.hh * 2.0), -ring.d * 2.2),
						ring.p + ring.r * (side * (ring.hw - 0.5)))
					chunk_node.add_child(pilaster)
			if ri % 9 == 4:
				var beam := MeshInstance3D.new()
				beam.mesh = _unit_box
				beam.material_override = mats.ceil
				beam.transform = Transform3D(
					Basis(ring.r * (ring.hw * 2.0), ring.u, -ring.d * 1.6),
					ring.p + ring.u * (ring.hh - 0.5))
				chunk_node.add_child(beam)
		if ring.arena_center and ring.arena_id % 4 != 3:
			# K1/V-10: every 4th arena stays unlit — a shadow pocket where only the
			# fog-to-black ambient reads and lurking enemies are radar-first contacts.
			# Deterministic per-ring mood: most steady, some shimmer, a few strobe.
			# Recorded here, instantiated by proximity in update_streaming so a fully
			# prebuilt level doesn't spend all MAX_ARENA_LIGHTS slots on its first six.
			var mode := "steady"
			if ri % 3 == 0:
				mode = "flicker"
			elif ri % 7 == 0:
				mode = "strobe"
			_pending_lights.append({"idx": ri,
				"color": accent2_color if (ri % 2 == 0) else accent_color,
				"mode": mode, "phase": float(ri % 13),
				"pos": ring.p + ring.u * (ring.hh * 0.5)})
		# tunnel enemies no longer spawn here: update_streaming rolls the dice via
		# _spawn_cursor just ahead of the player (arena enemies stay pre-spawned
		# deterministically by the game for exact door kill-counts)


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
	mi.mesh = _unit_quad
	mi.material_override = mats.wall
	mi.transform = Transform3D(
		Basis(ring.r * (ring.hw * 2.0), ring.u * (ring.hh * 2.0), -ring.d), ring.p)
	add_child(mi)
	_caps.append(mi)


func _build_doors() -> void:
	for arena in path.arenas:
		build_door(arena)


## One bulkhead quad. Public because endless mode discovers arenas mid-flight
## (K5) and needs their doors built as they appear.
func build_door(arena: Dictionary) -> void:
	if arena.door_ring < 0 or _doors.has(arena.id):
		return
	var ring: Dictionary = path.rings[arena.door_ring]
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_quad
	mi.material_override = _door_mat   # one shared emissive variant per level
	mi.transform = Transform3D(
		Basis(ring.r * (ring.hw * 2.0 + 2.0), ring.u * (ring.hh * 2.0 + 2.0), -ring.d),
		ring.p)
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
