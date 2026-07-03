class_name PathGen
extends RefCounted
## Ring/path data model + generator — the spine of the game (PLAN.md D1).
## Faithful port of the v2.2 web build's resetGen/forwardFrom/pushRing/genRings,
## plus a Phase E post-pass that identifies arenas and assigns locked doors.
##
## Each ring is a Dictionary:
##   p: Vector3 center · d/r/u: forward/right/up basis · hw/hh: half-width/height
##   arena: bool · arena_center: bool · arena_id: int (-1 outside arenas)

const SEG := 12.0            # metres per ring
const TUNNEL_HW := 9.0
const TUNNEL_HH := 6.0
const ARENA_HW := 30.0
const ARENA_HH := 15.0
## Phase J boss rooms: one straight oversized chamber at the end of a short entry
## tunnel. 46/22 is near the ceiling before fog (150) and camera.far (400) eat it.
const BOSS_HW := 46.0
const BOSS_HH := 22.0
const BOSS_ROOM_RINGS := 24

var rings: Array[Dictionary] = []
## Arena runs: { id, start, end, door_ring (-1 = unlocked), spawn_rings: Array[int], is_final }
var arenas: Array[Dictionary] = []

var _pos := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _yaw_v := 0.0
var _pitch_v := 0.0
var _count := 0
var _next_arena := 32
var _arena_in := 0
var _hw := TUNNEL_HW
var _hh := TUNNEL_HH
var _total := 999999
var _boss := false
var _rng := RandomNumberGenerator.new()


static func forward_from(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-cp * sin(yaw), sin(pitch), -cp * cos(yaw))


func generate(total_rings: int, level_seed: int, arena_spawn_chance: float,
		boss := false) -> void:
	rings.clear()
	arenas.clear()
	_rng.seed = level_seed
	_pos = Vector3.ZERO
	_yaw = 0.0
	_pitch = 0.0
	_yaw_v = 0.0
	_pitch_v = 0.0
	_count = 0
	_boss = boss
	# boss levels have exactly one arena — the room itself; no mid-run arenas/doors
	_next_arena = 999999 if boss else 32
	_arena_in = 0
	_hw = TUNNEL_HW
	_hh = TUNNEL_HH
	_total = total_rings
	_push_ring()
	for k in total_rings - 1:
		_gen_ring()
	_find_arenas(arena_spawn_chance)


func _gen_ring() -> void:
	_count += 1
	var final_len := BOSS_ROOM_RINGS if _boss else 14
	if _boss and _count >= _total - final_len:
		# a curving boss room sweeps its walls oddly — hold it straight and level
		_yaw_v = 0.0
		_pitch_v = 0.0
		_pitch *= 0.8
	elif _count > 14:
		_yaw_v += (_rng.randf() - 0.5) * 0.05
		_yaw_v = clampf(_yaw_v, -0.12, 0.12) * 0.985
		_pitch_v += (_rng.randf() - 0.5) * 0.02 - _pitch * 0.02
		_pitch_v = clampf(_pitch_v, -0.04, 0.04)
	_yaw += _yaw_v
	_pitch = clampf(_pitch + _pitch_v, -0.22, 0.22)
	if _count == _total - final_len:
		_arena_in = final_len  # guaranteed final arena holding the exit portal
	elif _count == _next_arena and _count < _total - 34:
		_arena_in = 10
		_next_arena += 30 + _rng.randi_range(0, 17)
	var t_hw := (BOSS_HW if _boss else ARENA_HW) if _arena_in > 0 else TUNNEL_HW
	var t_hh := (BOSS_HH if _boss else ARENA_HH) if _arena_in > 0 else TUNNEL_HH
	if _arena_in > 0:
		_arena_in -= 1
	_hw += (t_hw - _hw) * 0.3
	_hh += (t_hh - _hh) * 0.3
	_pos += forward_from(_yaw, _pitch) * SEG
	_push_ring()


func _push_ring() -> void:
	var d := forward_from(_yaw, _pitch)
	var r := d.cross(Vector3.UP).normalized()
	var u := r.cross(d).normalized()
	# arena_center rings get ceiling lights; a boss room is long enough to need three
	var center := (_arena_in in [20, 12, 4]) if _boss else _arena_in == 5
	rings.append({
		"p": _pos, "d": d, "r": r, "u": u, "hw": _hw, "hh": _hh,
		"arena": _arena_in > 0, "arena_center": center, "arena_id": -1,
	})


## Phase E post-pass: find contiguous arena runs, tag rings with arena ids, choose a
## locked door ring for every non-final arena, and precompute its enemy spawn rings
## (deterministic, so the kill target is exact and the door can never soft-lock).
func _find_arenas(arena_spawn_chance: float) -> void:
	var run_start := -1
	for i in rings.size():
		if rings[i].arena and run_start < 0:
			run_start = i
		elif not rings[i].arena and run_start >= 0:
			_add_arena(run_start, i - 1, false, arena_spawn_chance)
			run_start = -1
	if run_start >= 0:
		_add_arena(run_start, rings.size() - 1, true, arena_spawn_chance)


func _add_arena(start: int, end: int, is_final: bool, spawn_chance: float) -> void:
	# Phase J: a boss level's only arena is the room itself — always final, so it
	# never gets a bulkhead or random pre-spawns (the boss is placed by game.gd).
	if _boss:
		is_final = true
	var id := arenas.size()
	for i in range(start, end + 1):
		rings[i].arena_id = id
	var door_ring := -1
	var spawn_rings: Array[int] = []
	if not is_final:
		# the door sits a couple of rings into the narrowing mouth after the arena
		door_ring = mini(end + 2, rings.size() - 2)
		var count := maxi(2, roundi((end - start + 1) * spawn_chance)) + _rng.randi_range(0, 2)
		for s in count:
			spawn_rings.append(_rng.randi_range(start, end))
	arenas.append({
		"id": id, "start": start, "end": end, "door_ring": door_ring,
		"spawn_rings": spawn_rings, "is_final": is_final,
	})


# ---------- spatial queries (ports of nearestRing / clampToRing) ----------

func nearest_ring(pos: Vector3, start: int) -> int:
	var i := clampi(start, 0, rings.size() - 1)
	var guard := 0
	while i < rings.size() - 2 and guard < 60 \
			and pos.distance_squared_to(rings[i + 1].p) < pos.distance_squared_to(rings[i].p):
		i += 1
		guard += 1
	while i > 0 and guard < 60 \
			and pos.distance_squared_to(rings[i - 1].p) < pos.distance_squared_to(rings[i].p):
		i -= 1
		guard += 1
	return i


## Returns pos pushed back inside the flyable cross-section of ring idx.
func clamp_to_ring(pos: Vector3, idx: int, margin: float) -> Vector3:
	var ring: Dictionary = rings[idx]
	var rel: Vector3 = pos - ring.p
	var lat: float = rel.dot(ring.r)
	var vert: float = rel.dot(ring.u)
	var m_l: float = ring.hw - margin
	var m_v: float = ring.hh - margin
	if lat > m_l:
		pos += ring.r * (m_l - lat)
	elif lat < -m_l:
		pos += ring.r * (-m_l - lat)
	if vert > m_v:
		pos += ring.u * (m_v - vert)
	elif vert < -m_v:
		pos += ring.u * (-m_v - vert)
	return pos


func corner(ring: Dictionary, sr: float, su: float) -> Vector3:
	return ring.p + ring.r * (sr * ring.hw) + ring.u * (su * ring.hh)
