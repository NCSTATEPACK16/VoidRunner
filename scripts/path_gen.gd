class_name PathGen
extends RefCounted
## Ring/path data model + generator — the spine of the game (PLAN.md D1).
## Faithful port of the v2.2 web build's resetGen/forwardFrom/pushRing/genRings,
## plus a Phase E post-pass that identifies arenas and assigns locked doors.
##
## Each ring is a Dictionary:
##   p: Vector3 center · d/r/u: forward/right/up basis · hw/hh: half-width/height
##   fo/co: floor-raise / ceiling-drop offsets (K2/V-08 — 0 in arenas & boss rooms)
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
## V2.2 L5: dead-end supply spurs appended AFTER the main path — each is
## { id, entry, start, end, cache, side }. Spur rings carry a `spur` id key; main
## rings do not (read with .get("spur", -1)). main_ring_count marks the boundary so
## the exit cap/portal land at the real level end, not inside a spur.
var spurs: Array[Dictionary] = []
var main_ring_count := 0
var is_boss := false
var is_endless := false      # K5 Void Gauntlet: no end cap, no portal, rings grow on demand

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
var _fo := 0.0               # K2: floor raised above -hh by this much
var _co := 0.0               # K2: ceiling dropped below +hh by this much
var _next_corner := 0
var _corner_in := 0
var _corner_dir := 1.0
var _total := 999999
var _boss := false
var _scanned_up_to := 0      # K5: ring index arena discovery has processed so far
var _rng := RandomNumberGenerator.new()


static func forward_from(yaw: float, pitch: float) -> Vector3:
	var cp := cos(pitch)
	return Vector3(-cp * sin(yaw), sin(pitch), -cp * cos(yaw))


func generate(total_rings: int, level_seed: int, arena_spawn_chance: float,
		boss := false, endless := false) -> void:
	rings.clear()
	arenas.clear()
	spurs.clear()
	_rng.seed = level_seed
	_pos = Vector3.ZERO
	_yaw = 0.0
	_pitch = 0.0
	_yaw_v = 0.0
	_pitch_v = 0.0
	_count = 0
	_boss = boss
	is_boss = boss
	is_endless = endless
	_scanned_up_to = 0
	# boss levels have exactly one arena — the room itself; no mid-run arenas/doors
	_next_arena = 999999 if boss else 32
	_arena_in = 0
	_hw = TUNNEL_HW
	_hh = TUNNEL_HH
	_fo = 0.0
	_co = 0.0
	# K2/V-08: hard ~90° corners are a tunnel-level feature; boss approach stays smooth
	_next_corner = 999999 if boss else 40 + _rng.randi_range(0, 25)
	_corner_in = 0
	# endless: the final-arena/exit logic keys on _total, so park it out of reach —
	# total_rings is just the initial batch; extend_to() grows the path from there
	_total = 999999 if endless else total_rings
	_push_ring()
	for k in total_rings - 1:
		_gen_ring()
	if not endless:
		_find_arenas(arena_spawn_chance)
	main_ring_count = rings.size()   # V2.2 L5: boundary before any spurs are appended


## K5: grow an endless path so rings always exist well ahead of the player.
## No-op for campaign paths and when the target is already generated.
func extend_to(target_rings: int) -> void:
	if not is_endless:
		return
	while rings.size() < target_rings:
		_gen_ring()


## K5: scan newly generated rings for COMPLETED arena runs (a run still open at
## the tail is left for the next call) and register them exactly like the campaign
## post-pass — locked door, deterministic spawn rings. Returns the new arena dicts
## so the game can spawn their guards and the world can build their bulkheads.
func discover_arenas(arena_spawn_chance: float) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var run_start := -1
	var i := _scanned_up_to
	while i < rings.size():
		if rings[i].arena and run_start < 0:
			run_start = i
		elif not rings[i].arena and run_start >= 0:
			_add_arena(run_start, i - 1, false, arena_spawn_chance)
			found.append(arenas.back())
			run_start = -1
		i += 1
	_scanned_up_to = rings.size() if run_start < 0 else run_start
	return found


## K5/V2.1: cheap guard so the per-frame gauntlet stream can skip the arena scan
## entirely when extend_to() generated nothing new this frame.
func has_unscanned() -> bool:
	return is_endless and _scanned_up_to < rings.size()


func _gen_ring() -> void:
	_count += 1
	var final_len := BOSS_ROOM_RINGS if _boss else 14
	if _boss and _count >= _total - final_len:
		# a curving boss room sweeps its walls oddly — hold it straight and level
		_yaw_v = 0.0
		_pitch_v = 0.0
		_pitch *= 0.8
	elif _corner_in > 0:
		# K2/V-08: mid-corner — hold a hard constant turn rate, level the pitch
		_corner_in -= 1
		_yaw_v = _corner_dir * 0.36
		_pitch_v = 0.0
		_pitch *= 0.85
		if _corner_in == 0:
			_yaw_v = 0.0
	elif _count > 14:
		_yaw_v += (_rng.randf() - 0.5) * 0.05
		_yaw_v = clampf(_yaw_v, -0.12, 0.12) * 0.985
		_pitch_v += (_rng.randf() - 0.5) * 0.02 - _pitch * 0.02
		_pitch_v = clampf(_pitch_v, -0.04, 0.04)
		# K2/V-08: schedule an occasional hard corner (~82° over 4 rings), only in
		# plain tunnel and clear of arena mouths and the guaranteed final arena
		if _arena_in == 0 and _count >= _next_corner \
				and _count + 16 < _next_arena and _count < _total - 34:
			_corner_in = 4
			_corner_dir = 1.0 if _rng.randf() < 0.5 else -1.0
			_next_corner = _count + 45 + _rng.randi_range(0, 30)
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
	# K2/V-08: floor/ceiling height variation — a slow random walk in plain tunnel,
	# decayed to flat inside arenas (combat spaces stay clean). A boss room snaps
	# exactly flat at its mouth — its dimensions are a Phase J invariant.
	if _boss and _count >= _total - final_len:
		_fo = 0.0
		_co = 0.0
	elif _arena_in > 0 or _count <= 14:
		_fo *= 0.5
		_co *= 0.5
	else:
		_fo = clampf(_fo + (_rng.randf() - 0.5) * 0.8, 0.0, 2.4)
		_co = clampf(_co + (_rng.randf() - 0.5) * 0.8, 0.0, 2.4)
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
		"fo": _fo, "co": _co,
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


## V2.2 L5a: branch dead-end supply spurs off non-final arenas. Spur rings APPEND to
## the same rings array (indices >= main_ring_count) so clamp_to_ring / corner / world
## building work unchanged; each carries a `spur` id. The whole generator cursor is
## snapshotted and restored so the main path is byte-identical afterward. Campaign,
## non-boss only — a no-op otherwise. Called by game._load_level_world after generate().
func add_spurs(count: int) -> void:
	if is_boss or is_endless or count <= 0 or arenas.size() < 2:
		return
	var save := {"pos": _pos, "yaw": _yaw, "pitch": _pitch, "yaw_v": _yaw_v,
		"pitch_v": _pitch_v, "count": _count, "hw": _hw, "hh": _hh,
		"fo": _fo, "co": _co, "arena_in": _arena_in}
	var eligible: Array[int] = []
	for i in range(1, arenas.size()):   # skip arena 0 (near spawn) and the final arena
		if not arenas[i].get("is_final", false):
			eligible.append(i)
	var made := 0
	var idx := 0
	while made < count and idx < eligible.size():
		_grow_spur(made, eligible[idx])
		made += 1
		idx += maxi(1, eligible.size() / count)   # spread the spurs across the level
	_pos = save.pos; _yaw = save.yaw; _pitch = save.pitch
	_yaw_v = save.yaw_v; _pitch_v = save.pitch_v; _count = save.count
	_hw = save.hw; _hh = save.hh; _fo = save.fo; _co = save.co; _arena_in = save.arena_in


func _grow_spur(id: int, ai: int) -> void:
	var arena: Dictionary = arenas[ai]
	var entry: int = (arena.start + arena.end) / 2
	var er: Dictionary = rings[entry]
	var side: float = -1.0 if (id % 2 == 0) else 1.0
	# head off toward the `side` wall at 60..110 deg from the arena heading
	var entry_yaw: float = atan2(-er.d.x, -er.d.z)
	_yaw = entry_yaw - side * deg_to_rad(60.0 + _rng.randf() * 50.0)
	_pitch = 0.0
	_yaw_v = 0.0
	_pitch_v = 0.0
	_fo = 0.0
	_co = 0.0
	_arena_in = 0
	# first spur ring sits ON the arena wall so the hatch-crossing snap lands right here
	_hw = 6.0
	_hh = 4.5
	_pos = er.p + er.r * (side * er.hw)
	_push_ring()
	var start := rings.size() - 1
	rings[start]["spur"] = id
	var body := 8 + _rng.randi_range(0, 8)   # 8..16 narrow rings winding outward
	for k in body:
		_yaw += (_rng.randf() - 0.5) * 0.06
		_pitch = clampf(_pitch + (_rng.randf() - 0.5) * 0.03, -0.15, 0.15)
		_pos += forward_from(_yaw, _pitch) * SEG
		_push_ring()
		rings[rings.size() - 1]["spur"] = id
	var cache_start := rings.size()          # 4-ring turnaround cache chamber
	for k in 4:
		_hw = 14.0
		_hh = 8.0
		_pos += forward_from(_yaw, _pitch) * SEG
		_push_ring()
		rings[rings.size() - 1]["spur"] = id
	spurs.append({"id": id, "entry": entry, "start": start,
		"end": rings.size() - 1, "cache": cache_start + 1, "side": side})


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
## K2: the vertical bounds are asymmetric — fo raises the floor, co drops the ceiling.
func clamp_to_ring(pos: Vector3, idx: int, margin: float) -> Vector3:
	var ring: Dictionary = rings[idx]
	var rel: Vector3 = pos - ring.p
	var lat: float = rel.dot(ring.r)
	var vert: float = rel.dot(ring.u)
	var m_l: float = ring.hw - margin
	var m_top: float = ring.hh - ring.co - margin
	var m_bot: float = ring.hh - ring.fo - margin
	if lat > m_l:
		pos += ring.r * (m_l - lat)
	elif lat < -m_l:
		pos += ring.r * (-m_l - lat)
	if vert > m_top:
		pos += ring.u * (m_top - vert)
	elif vert < -m_bot:
		pos += ring.u * (-m_bot - vert)
	return pos


func corner(ring: Dictionary, sr: float, su: float) -> Vector3:
	var v: float = su * ring.hh + (ring.fo if su < 0.0 else -ring.co)
	return ring.p + ring.r * (sr * ring.hw) + ring.u * v
