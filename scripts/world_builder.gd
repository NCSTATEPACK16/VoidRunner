class_name WorldBuilder
extends Node3D
## Builds and streams the tunnel geometry (PLAN.md D2): chunked meshes ahead of
## the player, freed behind — the Godot port of the web build's buildChunk/
## disposeChunk/ensureWorld/buildCap/spawnPortal, plus locked-arena bulkheads.
##
## 3.0 Phase 2 rebuilt the look:
##  * octagonal cross-sections (PathGen.section) — floor, ceiling, two walls and
##    four 45-degree corner trims, each face picking a texture variant per ring
##  * lamp fixtures placed along the path (visible full-bright tiles) whose light
##    is BAKED into the vertex colors of everything nearby — the sector-lighting
##    look of 1995 software renderers, at zero per-frame cost
##  * one shader for all of it (sector.gdshader); animated and moving light goes
##    through LightRig, so there is no OmniLight3D left in the world
##  * split bulkhead doors that slide into the walls, a vortex exit gate

signal tunnel_spawn_requested(ring_idx: int)

const CHUNK := 14              # rings per geometry chunk
const BUILD_AHEAD := 110       # keep geometry built this many rings ahead
const FREE_BEHIND := 18        # free geometry this many rings behind
const VIS_AHEAD := 36          # draw window: 432 m ahead > camera.far and every fog_end
const SPAWN_AHEAD := 24        # roll tunnel-spawn dice this far ahead of the player
const TILE := 8.0              # world metres per 64 px texture tile across a face
const U_PER_RING := 1.5        # texture tiles per 12 m ring segment along the tunnel
const LAMP_REACH := 5          # rings either side a lamp's baked light can touch
## Endless streaming builds a chunk over several frames, this many rings per
## frame (~1-2 ms), instead of one 14-ring spike. 110 rings of lookahead means a
## chunk can take many frames and still land long before the player does.
const STREAM_RINGS_PER_FRAME := 3

const SECTOR_SHADER := preload("res://shaders/sector.gdshader")
const PORTAL_SHADER := preload("res://shaders/portal.gdshader")

var path: PathGen
var light_rig: LightRig        # wired by game.gd; every sector material registers here
var theme: Dictionary = {}     # TextureGen.THEMES entry for this level
var mats: Dictionary = {}      # texture key -> ShaderMaterial (TextureGen.KEYS)
var accent_color := Color("55ffee")
var accent2_color := Color("ff5533")

var _textures: Dictionary = {}
var _chunks: Array[Dictionary] = []      # {node, start, end}
var _built_up_to := 0
var _spawn_cursor := 0
var _lamp_cache := {}                    # ring -> Array of lamp dicts (lazy, deterministic)
var _near_cache := {}                    # ring -> lamps within LAMP_REACH rings (flattened)
var _face_light := {}                    # ring -> PackedColorArray(16): 8 faces x 2 points
var _job := {}                           # streamed chunk in progress (see _begin_chunk)
var _ring_light := {}                    # ring -> Color, average baked light (sprite tinting)
var _caps: Array[MeshInstance3D] = []
var _doors := {}                          # arena_id -> {nodes: [left, right], ring, open, w}
var _door_mat: ShaderMaterial
var _portal: Node3D
var _portal_ring: MeshInstance3D
var _portal_pulse := 0.0
var _portal_light := -1
var portal_position := Vector3.ZERO
var portal_active := false


## theme_id: a TextureGen.THEMES key. Textures are painted once per theme.
func rebuild(new_path: PathGen, theme_id: String) -> void:
	clear_world()
	path = new_path
	theme = TextureGen.THEMES[theme_id]
	accent_color = theme.accent
	accent2_color = theme.accent2
	_textures = TextureGen.theme_textures(theme_id)
	if light_rig:
		light_rig.clear_materials()
	mats.clear()
	for key in TextureGen.KEYS:
		mats[key] = _sector_mat(_textures[key])
	# the floor strip's chevrons march down the corridor (v runs along the tunnel)
	(mats.strip as ShaderMaterial).set_shader_parameter("uv_scroll", Vector2(0.0, -1.6))
	# v4a: colour cycling on this theme's glowing surfaces, and on the bulkheads
	var cyc := TextureGen.cycle_keys(theme_id)
	for key in cyc:
		(mats[key] as ShaderMaterial).set_shader_parameter("cycle_speed", cyc[key])
	_door_mat = prop_material("door", 1.0, Color.WHITE, accent_color * 0.12)
	_door_mat.set_shader_parameter("cycle_speed", TextureGen.DOOR_CYCLE)
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
		_build_cap(_main_last())   # V2.2 L5: cap the real level end, not the last spur
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
		for n in _doors[id].nodes:
			n.queue_free()
	_doors.clear()
	if _portal:
		_portal.queue_free()
		_portal = null
	_portal_light = -1
	portal_active = false
	_built_up_to = 0
	_spawn_cursor = 0
	_lamp_cache.clear()
	_near_cache.clear()
	_face_light.clear()
	_ring_light.clear()
	_job = {}
	if light_rig:
		light_rig.clear_statics()


## A sector material for primitive meshes (boxes, quads) that carry no vertex
## light: lit at a fixed level instead, optionally tinted / self-glowing. Shares
## the one sector shader, so it never costs a new shader compile.
func prop_material(tex_key: String, light := 0.7, tint := Color.WHITE,
		emit := Color.BLACK) -> ShaderMaterial:
	var m := _sector_mat(_textures[tex_key])
	m.set_shader_parameter("use_vertex_light", 0.0)
	m.set_shader_parameter("base_light", light)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("emit_col", Color(emit.r, emit.g, emit.b))
	return m


## Baked light (decoded: 1.0 = neutral) arriving at pos near ring i, facing nrm.
func light_at(i: int, pos: Vector3, nrm: Vector3) -> Color:
	var c := _light(clampi(i, 0, path.rings.size() - 1), pos, nrm, 1.0)
	return Color(c.r * 2.0, c.g * 2.0, c.b * 2.0)


## Average baked light inside a ring (1.0 = neutral), for tinting things that
## stand in it — a drone in a dark arena reads as a silhouette, one under a lamp
## pops, and a phantom wall panel matches the wall it hides in.
func ring_light(ring_idx: int) -> Color:
	if _ring_light.has(ring_idx):
		return _ring_light[ring_idx]
	if path == null or ring_idx < 0 or ring_idx >= path.rings.size():
		return Color(0.8, 0.8, 0.8)
	var ring: Dictionary = path.rings[ring_idx]
	var c := Color(0, 0, 0)
	for side in [-1.0, 1.0]:
		c += light_at(ring_idx, ring.p + ring.r * (side * (ring.hw - 1.0)), ring.r * -side)
		c += light_at(ring_idx, ring.p + ring.u * (side * (ring.hh - 1.0)), ring.u * -side)
	c = c * 0.25
	_ring_light[ring_idx] = c
	return c


func _sector_mat(tex: Texture2D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SECTOR_SHADER
	m.set_shader_parameter("albedo_tex", tex)
	if light_rig:
		light_rig.register(m)
	return m


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


## Re-audit Step 4: a resumed checkpoint starts mid-level. Without this the first
## streaming frame would roll every ring from the start up to the ship at once.
func skip_spawns_to(ring_idx: int) -> void:
	_spawn_cursor = maxi(_spawn_cursor, ring_idx)


func update_streaming(player_ring: int) -> void:
	var last := path.rings.size() - 1
	# endless mode still streams geometry ahead (finite levels are prebuilt) —
	# one chunk at a time, STREAM_RINGS_PER_FRAME rings of it per frame
	if _job.is_empty() and _built_up_to < last and _built_up_to - player_ring < BUILD_AHEAD:
		_job = _begin_chunk(_built_up_to, mini(_built_up_to + CHUNK, last))
	if not _job.is_empty() and _step_chunk(_job, STREAM_RINGS_PER_FRAME):
		_finish_chunk(_job)
		_built_up_to = _job.e
		_job = {}
	while not _chunks.is_empty() and _chunks[0].end < player_ring - FREE_BEHIND:
		_chunks[0].node.queue_free()
		_chunks.pop_front()
	# tunnel-spawn dice roll just ahead of the player, not at build time: a
	# prebuilt level would roll every ring at once and the 300 u despawn would
	# cull the lot
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


## The two leaves slide apart into the walls.
func open_door(arena_id: int) -> void:
	if not _doors.has(arena_id) or _doors[arena_id].open:
		return
	var d: Dictionary = _doors[arena_id]
	d.open = true
	var ring: Dictionary = path.rings[d.ring]
	var tween := create_tween().set_parallel(true)
	for k in 2:
		var leaf: Node3D = d.nodes[k]
		var dir := -1.0 if k == 0 else 1.0
		tween.tween_property(leaf, "position", leaf.position + ring.r * (dir * d.w), 0.9) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func is_door_open(arena_id: int) -> bool:
	return _doors.has(arena_id) and _doors[arena_id].open


## Small meshes for every material class this level can draw that isn't in view
## from the start ring — the exit gate's vortex + frame (portal shader) and a
## door leaf — added to the briefing warm-up rig so their shader variants compile
## behind the briefing overlay, not mid-flight.
func warmup_meshes(rig: Node3D, pos: Vector3) -> void:
	var x := -1.4
	for m: Material in [_portal_material(false), _portal_material(true), _door_mat]:
		var mi := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.2, 1.2)
		mi.mesh = quad
		mi.material_override = m
		mi.position = pos + Vector3(x, 0, 0)
		x += 1.4
		rig.add_child(mi)


## Phase J: boss levels keep the exit ring dormant (dark and inert) until the boss
## falls — the reveal IS the level-complete gate, so no bulkhead is needed.
func set_portal_active(on: bool) -> void:
	portal_active = on
	if _portal:
		_portal.visible = on
	if light_rig and _portal_light >= 0:
		light_rig.set_static_on(_portal_light, on)


# ---------- lamps + baked light ----------

func _dark_arena(ring: Dictionary) -> bool:
	# K1/V-10: every 4th arena stays unlit — a shadow pocket where enemies are
	# radar-first contacts. Boss rooms are never dark.
	return ring.arena_id >= 0 and ring.arena_id % 4 == 3 and not path.is_boss


func _is_ceiling_lamp(i: int, ring: Dictionary) -> bool:
	if ring.get("spur", -1) >= 0:
		return i % 3 == 0
	if ring.arena_id >= 0:
		return not _dark_arena(ring) and (ring.arena_center or i % 6 == 3)
	return i % 4 == 2


func _is_wall_light(i: int, ring: Dictionary) -> bool:
	if ring.get("spur", -1) >= 0:
		return false
	if ring.arena_id >= 0:
		return not _dark_arena(ring) and i % 4 == 1
	return i % 6 == 4


## Lamps hung on ring i's segment (i -> i+1), deterministic, cached.
func _lamps(i: int) -> Array:
	if _lamp_cache.has(i):
		return _lamp_cache[i]
	var lamps: Array = []
	if i >= 0 and i < path.rings.size() - 1:
		var ring: Dictionary = path.rings[i]
		var nxt: Dictionary = path.rings[i + 1]
		if ring.get("spur", -1) == nxt.get("spur", -1):
			var mid: Vector3 = (ring.p + nxt.p) * 0.5
			var arena: bool = ring.arena_id >= 0
			if _is_ceiling_lamp(i, ring):
				var big: bool = ring.arena_center
				lamps.append({"pos": mid + ring.u * (ring.hh - ring.co - 1.0),
					"color": theme.lamp,
					"energy": 1.5 if big else (1.05 if arena else 1.3),
					"range": 80.0 if big else (46.0 if arena else 30.0)})
			if _is_wall_light(i, ring):
				for side in [-1.0, 1.0]:
					lamps.append({"pos": mid + ring.r * (side * (ring.hw - 1.0)),
						"color": theme.lamp2, "energy": 0.75 if arena else 0.95,
						"range": 34.0 if arena else 24.0})
	_lamp_cache[i] = lamps
	return lamps


## Every lamp within LAMP_REACH rings of ring i, gathered once per ring.
func _near_lamps(i: int) -> Array:
	if _near_cache.has(i):
		return _near_cache[i]
	var out: Array = []
	for k in range(i - LAMP_REACH, i + LAMP_REACH + 1):
		out.append_array(_lamps(k))
	_near_cache[i] = out
	return out


## Baked light for both end points of all 8 section faces of ring i, cached —
## the segment before and the segment after a ring share these exactly.
func _ring_face_light(i: int) -> PackedColorArray:
	if _face_light.has(i):
		return _face_light[i]
	var ring: Dictionary = path.rings[i]
	var sec := PathGen.section(ring)
	var out := PackedColorArray()
	out.resize(16)
	for k in 8:
		var k2 := (k + 1) % 8
		var n := _fnorm(ring, sec[k], sec[k2])
		out[k * 2] = _light(i, _wp(ring, sec[k]), n, FACE_AMB[k])
		out[k * 2 + 1] = _light(i, _wp(ring, sec[k2]), n, FACE_AMB[k])
	_face_light[i] = out
	return out


## Baked light arriving at a vertex: zone ambient + every lamp within reach,
## half-lambert on the face normal. Returned already encoded at half scale.
func _light(i: int, pos: Vector3, nrm: Vector3, face_amb: float) -> Color:
	var ring: Dictionary = path.rings[i]
	var amb_scale := 1.0
	if ring.get("spur", -1) >= 0:
		amb_scale = 0.8
	elif _dark_arena(ring):
		amb_scale = 0.45
	elif ring.arena_id >= 0:
		amb_scale = 1.2 if path.is_boss else 1.1
	var c: Color = theme.amb * (amb_scale * face_amb)
	for lamp in _near_lamps(i):
		var d: Vector3 = lamp.pos - pos
		var dist := d.length()
		if dist >= lamp.range:
			continue
		var att: float = 1.0 - dist / lamp.range
		att *= att
		var ndl := clampf(nrm.dot(d / maxf(dist, 0.001)), 0.0, 1.0) * 0.7 + 0.3
		c += lamp.color * (lamp.energy * att * ndl)
	return Color(minf(c.r * 0.5, 1.0), minf(c.g * 0.5, 1.0), minf(c.b * 0.5, 1.0), 1.0)


# ---------- geometry ----------

## Texture variant for face k of ring i's segment (see PathGen.section).
func _face_key(i: int, k: int, ring: Dictionary) -> String:
	if k % 2 == 1:
		return "trim"
	var arena: bool = ring.arena_id >= 0
	var h := (i * 2654435761) >> 7 & 0xff   # cheap stable per-ring hash
	match k:
		0:
			return "floor_b" if (arena or (i / 3) % 4 == 0) else "floor"
		4:
			return "ceil_lamp" if _is_ceiling_lamp(i, ring) else "ceil"
	if _is_wall_light(i, ring):
		return "wall_b"
	if arena and not path.is_boss:
		if i % 3 == 0:
			return "wall_d"
		return "wall_c" if h % 5 == 0 else "wall_a"
	if h % 7 == 0:
		return "wall_c"
	if h % 7 == 3:
		return "wall_d"
	return "wall_a"


## Per-face ambient shaping: ceilings and floors sit a little darker than walls.
const FACE_AMB := [0.85, 0.9, 1.0, 0.9, 0.7, 0.9, 1.0, 0.9]


## Mesh data for one surface while a chunk is being built.
class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()

	func quad(p: Array, nr: Array, cl: Array, t: Array) -> void:
		for idx in [0, 1, 2, 0, 2, 3]:
			v.append(p[idx])
			n.append(nr[idx])
			c.append(cl[idx])
			uv.append(t[idx])


func _acc(accs: Dictionary, key: String) -> Acc:
	if not accs.has(key):
		accs[key] = Acc.new()
	return accs[key]


func _wp(ring: Dictionary, s: Vector2) -> Vector3:
	return ring.p + ring.r * s.x + ring.u * s.y


## Inward normal of the face a->b (sections run counter-clockwise).
func _fnorm(ring: Dictionary, a: Vector2, b: Vector2) -> Vector3:
	var d := b - a
	var n2 := Vector2(-d.y, d.x).normalized()
	return (ring.r * n2.x + ring.u * n2.y).normalized()


## v texture coordinate of section point pt on face k.
func _face_v(k: int, ring: Dictionary, pt: Vector2, first: bool) -> float:
	match k:
		0, 4:
			return pt.x / TILE + 0.5
		2, 6:
			return (ring.hh - ring.co - ring.ch - pt.y) / TILE
	return 0.0 if first else 1.0


func _build_chunk(s: int, e: int) -> void:
	var job := _begin_chunk(s, e)
	_step_chunk(job, 1 << 30)
	_finish_chunk(job)


func _begin_chunk(s: int, e: int) -> Dictionary:
	return {"s": s, "e": e, "i": s, "accs": {}}


## Build up to max_rings more ring segments of the job. True once it's complete.
func _step_chunk(job: Dictionary, max_rings: int) -> bool:
	var accs: Dictionary = job.accs
	var stop: int = mini(job.e, job.i + max_rings)
	for i in range(job.i, stop):
		_build_segment(accs, i)
	job.i = stop
	return job.i >= job.e


func _finish_chunk(job: Dictionary) -> void:
	var chunk_node := Node3D.new()
	for key in job.accs:
		var acc: Acc = job.accs[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = acc.v
		arrays[Mesh.ARRAY_NORMAL] = acc.n
		arrays[Mesh.ARRAY_COLOR] = acc.c
		arrays[Mesh.ARRAY_TEX_UV] = acc.uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mats[key]
		chunk_node.add_child(mi)
	add_child(chunk_node)
	_chunks.append({"node": chunk_node, "start": job.s, "end": job.e})


## One ring segment (ring i -> i+1): the 8 section faces, the floor strip, arena
## relief, and any animated arena lamp.
func _build_segment(accs: Dictionary, i: int) -> void:
	# V2.2 L5: never stitch a quad across a spur boundary — spur rings append far
	# from where they branch, so main-end->spur-start (and spur->spur) are disjoint
	if path.rings[i].get("spur", -1) != path.rings[i + 1].get("spur", -1):
		return
	var r0: Dictionary = path.rings[i]
	var r1: Dictionary = path.rings[i + 1]
	var s0 := PathGen.section(r0)
	var s1 := PathGen.section(r1)
	var l0 := _ring_face_light(i)
	var l1 := _ring_face_light(i + 1)
	var u0 := i * U_PER_RING
	var u1 := (i + 1) * U_PER_RING
	for k in 8:
		var k2 := (k + 1) % 8
		var n0 := _fnorm(r0, s0[k], s0[k2])
		var n1 := _fnorm(r1, s1[k], s1[k2])
		_acc(accs, _face_key(i, k, r0)).quad(
			[_wp(r0, s0[k]), _wp(r0, s0[k2]), _wp(r1, s1[k2]), _wp(r1, s1[k])],
			[n0, n0, n1, n1], [l0[k * 2], l0[k * 2 + 1], l1[k * 2 + 1], l1[k * 2]],
			[Vector2(u0, _face_v(k, r0, s0[k], true)), Vector2(u0, _face_v(k, r0, s0[k2], false)),
				Vector2(u1, _face_v(k, r1, s1[k2], false)), Vector2(u1, _face_v(k, r1, s1[k], true))])
	# V2.0 accent floor strip: a narrow glowing centreline in plain tunnel only
	# (arenas/boss rooms keep their own lighting language). v runs along the
	# tunnel so the scrolling chevrons flow with the flight.
	if r0.arena_id < 0 and r1.arena_id < 0:
		var sw := 1.2
		var f0: Vector3 = r0.p + r0.u * (-(r0.hh - r0.fo) + 0.06)
		var f1: Vector3 = r1.p + r1.u * (-(r1.hh - r1.fo) + 0.06)
		var sl0: Color = l0[0].lerp(l0[1], 0.5)   # floor face, midway across
		var sl1: Color = l1[0].lerp(l1[1], 0.5)
		_acc(accs, "strip").quad(
			[f0 - r0.r * sw, f0 + r0.r * sw, f1 + r1.r * sw, f1 - r1.r * sw],
			[r0.u, r0.u, r1.u, r1.u], [sl0, sl0, sl1, sl1],
			[Vector2(0, i), Vector2(1, i), Vector2(1, i + 1), Vector2(0, i + 1)])
	# K2/V-08: sector-style wall relief in arenas — pipe columns on the walls and
	# pipe beams across the ceiling, baked into the chunk mesh (lit like
	# everything else, zero extra nodes). Everything protrudes at most 1.0 u,
	# safely inside every collision margin. Boss rooms stay clean (Phase J).
	if r0.arena_id >= 0 and not path.is_boss and not r0.arena_center \
			and r0.get("spur", -1) < 0:
		var wall_h: float = (r0.hh - r0.co - r0.ch) + (r0.hh - r0.fo - r0.ch)
		var wall_mid: float = ((r0.hh - r0.co - r0.ch) - (r0.hh - r0.fo - r0.ch)) * 0.5
		if i % 3 == 0:
			for side in [-1.0, 1.0]:
				_box(accs, "trim", i,
					r0.p + r0.r * (side * (r0.hw - 0.5)) + r0.u * wall_mid,
					r0.r, r0.u, -r0.d, Vector3(0.5, wall_h * 0.5, 1.1), true)
		if i % 9 == 4:
			_box(accs, "trim", i, r0.p + r0.u * (r0.hh - r0.co - 0.5),
				r0.r, r0.u, -r0.d, Vector3(r0.hw - r0.ch, 0.5, 0.8), false)
	# arena mood lights (K1/V-10): the big centre lamp is baked steady; the
	# flickering / strobing ones add an animated LightRig lamp on top
	if r0.arena_center and not _dark_arena(r0) and light_rig:
		var mode := "steady"
		if i % 3 == 0:
			mode = "flicker"
		elif i % 7 == 0:
			mode = "strobe"
		if mode != "steady":
			light_rig.add_static(r0.p + r0.u * (r0.hh * 0.5),
				theme.lamp if i % 2 == 0 else theme.lamp2, 0.9, 60.0, mode, float(i % 13))


## A lit box (6 faces) around centre c with axes ax/ay/az and half extents he.
## uv_swap turns the texture 90 degrees so trim pipes run up a column.
func _box(accs: Dictionary, key: String, i: int, c: Vector3, ax: Vector3, ay: Vector3,
		az: Vector3, he: Vector3, uv_swap: bool) -> void:
	var acc := _acc(accs, key)
	var axes := [ax, ay, az]
	for f in 6:
		var a: int = f / 2
		var sgn := 1.0 if f % 2 == 0 else -1.0
		var n: Vector3 = axes[a] * sgn
		var t1: Vector3 = axes[(a + 1) % 3]
		var t2: Vector3 = axes[(a + 2) % 3]
		var e1: float = he[(a + 1) % 3]
		var e2: float = he[(a + 2) % 3]
		var fc: Vector3 = c + n * he[a]
		var pts := [fc - t1 * e1 - t2 * e2, fc + t1 * e1 - t2 * e2,
			fc + t1 * e1 + t2 * e2, fc - t1 * e1 + t2 * e2]
		var ls := []
		for p in pts:
			ls.append(_light(i, p, n, 1.0))
		var r1 := maxf(e1 * 2.0 / TILE, 0.25)
		var r2 := maxf(e2 * 2.0 / TILE, 0.25)
		var uvs := [Vector2(0, 0), Vector2(r1, 0), Vector2(r1, r2), Vector2(0, r2)]
		if uv_swap:
			uvs = [Vector2(0, 0), Vector2(0, r1), Vector2(r2, r1), Vector2(r2, 0)]
		acc.quad(pts, [n, n, n, n], ls, uvs)


## V2.2 L5: the level's real exit is the main path's end, not the last spur ring.
## Falls back to the full ring count for any path built before generate() ran.
func _main_last() -> int:
	return (path.main_ring_count if path.main_ring_count > 0 else path.rings.size()) - 1


func _build_cap(idx: int) -> void:
	var ring: Dictionary = path.rings[idx]
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	mi.mesh = quad
	mi.material_override = prop_material("wall_d", 0.45)
	mi.transform = Transform3D(
		Basis(ring.r * (ring.hw * 2.0), ring.u * (ring.hh * 2.0), -ring.d), ring.p)
	add_child(mi)
	_caps.append(mi)


func _build_doors() -> void:
	for arena in path.arenas:
		build_door(arena)


## A split bulkhead: two leaves meeting on the ring's centreline, each carrying
## its half of the door texture. Public because endless mode discovers arenas
## mid-flight (K5) and needs their doors built as they appear.
func build_door(arena: Dictionary) -> void:
	if arena.door_ring < 0 or _doors.has(arena.id):
		return
	var ring: Dictionary = path.rings[arena.door_ring]
	var w: float = ring.hw + 1.0
	var h: float = ring.hh + 1.0
	var leaves: Array[MeshInstance3D] = []
	for k in 2:
		var x0 := -w if k == 0 else 0.0
		var x1 := 0.0 if k == 0 else w
		var u0 := 0.0 if k == 0 else 0.5
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(x0, -h, 0), Vector3(x1, -h, 0), Vector3(x1, h, 0),
			Vector3(x0, -h, 0), Vector3(x1, h, 0), Vector3(x0, h, 0)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK,
			Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([
			Vector2(u0, 1), Vector2(u0 + 0.5, 1), Vector2(u0 + 0.5, 0),
			Vector2(u0, 1), Vector2(u0 + 0.5, 0), Vector2(u0, 0)])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _door_mat   # one shared material per level
		mi.transform = Transform3D(Basis(ring.r, ring.u, -ring.d), ring.p)
		add_child(mi)
		leaves.append(mi)
	_doors[arena.id] = {"nodes": leaves, "ring": arena.door_ring, "open": false, "w": w}


func _ring_transform(ring: Dictionary) -> Transform3D:
	return Transform3D(Basis(ring.r, ring.u, -ring.d), ring.p)


func _portal_material(solid: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PORTAL_SHADER
	m.set_shader_parameter("solid", 1.0 if solid else 0.0)
	m.set_shader_parameter("col_a", accent_color)
	m.set_shader_parameter("col_b", accent_color.darkened(0.8))
	return m


func _spawn_portal() -> void:
	var ring: Dictionary = path.rings[maxi(_main_last() - 5, 0)]
	_portal = Node3D.new()
	_portal_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 4.5
	torus.outer_radius = 5.9
	torus.rings = 20
	torus.ring_segments = 8
	_portal_ring.mesh = torus
	_portal_ring.material_override = _portal_material(true)
	# TorusMesh lies flat around Y; stand it up so the hole faces along the ring axis
	_portal_ring.rotation_degrees.x = 90.0
	var disc := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(9.2, 9.2)
	disc.mesh = quad
	disc.material_override = _portal_material(false)
	_portal.add_child(_portal_ring)
	_portal.add_child(disc)
	_portal.transform = _ring_transform(ring)
	add_child(_portal)
	portal_position = ring.p
	portal_active = true
	if light_rig:
		_portal_light = light_rig.add_static(ring.p, accent_color, 1.4, 50.0)
