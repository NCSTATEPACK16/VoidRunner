class_name SpurManager
extends Node3D
## V2.2 L5b: dead-end supply spurs. For each PathGen spur it builds a hatch panel on
## the arena wall (a proud tinted quad, like the phantom-wall secrets, that hides as
## the player closes so flight through it is unobstructed) and runs THE risky
## mechanism — a ring-index snap when the player crosses the spur mouth.
##
## Why the snap: PathGen.nearest_ring is index-LOCAL (it walks i+/-1 from the current
## ring), but spur rings append to the END of the rings array while sitting physically
## at a mid-level arena wall. So the arena(~mid index) -> spur(~end index) crossing is
## a jump nearest_ring can't bridge on its own; without the snap the arena wall clamp
## just pushes the player back. The snap relocates ring_idx at the mouth; hysteresis
## (re-arm only after clearing the mouth) stops entry/exit ping-pong.
##
## The hatch reuses the walls' (already-warmed) material and the cache uses the pickup
## manager's existing station path, so this phase adds NO new shader/material variant.

signal cache_collected(id: int)

const SNAP_R2 := 64.0        # 8 u — snap trigger radius (> the ~1.6 u wall-clamp margin)
const REARM_R2 := 144.0      # 12 u — must clear the mouth before another snap arms
const CACHE_R2 := 121.0      # 11 u — cache-bundle award radius
const HATCH_HIDE_R2 := 81.0  # 9 u — the hatch "opens" (hides) inside this

var _path = null
var _player = null
var _pickups = null
var _wall_mat: Material = null
var _spurs: Array = []       # per spur: {def, hatch: MeshInstance3D, armed, collected}
var caches_found := 0


## Called by game._load_level_world after path.add_spurs(). Builds a hatch per spur and
## spills each cache chamber's fly-through pickups. A no-op when the path has no spurs.
func setup(path, player, pickups, wall_mat: Material, tint: Color) -> void:
	_clear()
	_path = path
	_player = player
	_pickups = pickups
	_wall_mat = wall_mat
	for sp in path.spurs:
		var hatch := _build_hatch(sp, tint)
		_spurs.append({"def": sp, "hatch": hatch, "armed": true, "collected": false})
		_spill_cache(sp)


func _clear() -> void:
	for s in _spurs:
		if is_instance_valid(s.hatch):
			s.hatch.queue_free()
	_spurs.clear()
	caches_found = 0


func _build_hatch(sp: Dictionary, tint: Color) -> MeshInstance3D:
	var er: Dictionary = _path.rings[sp.entry]
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, maxf((er.hh - er.fo - er.co) * 1.6, 3.0), PathGen.SEG * 2.2)
	mi.mesh = box
	var mat: StandardMaterial3D = _wall_mat.duplicate()   # same warmed shader as the walls
	mat.albedo_color = tint
	mi.material_override = mat
	mi.transform = Transform3D(Basis(er.r, er.u, -er.d),
		er.p + er.r * (sp.side * (er.hw - 1.0)))
	add_child(mi)
	return mi


func _spill_cache(sp: Dictionary) -> void:
	# persistent (non-expiring) fly-through pickups in the chamber; the salvage/score
	# bundle is awarded on arrival in update() (stations don't carry a salvage value)
	var ring: Dictionary = _path.rings[sp.cache]
	_pickups.add_station(ring.p + ring.r * 3.0, "shield")
	_pickups.add_station(ring.p - ring.r * 3.0, "energy")


func update(_delta: float) -> void:
	if _player == null:
		return
	for s in _spurs:
		var sp: Dictionary = s.def
		var d2: float = _player.position.distance_squared_to(_path.rings[sp.start].p)
		if is_instance_valid(s.hatch):
			s.hatch.visible = d2 > HATCH_HIDE_R2   # auto-open (hide) as the player nears
		if d2 > REARM_R2:
			s.armed = true
		elif s.armed and d2 < SNAP_R2:
			if _player.ring_idx < sp.start:
				_player.snap_ring(sp.start)   # cross INTO the spur index space
			else:
				_player.snap_ring(sp.entry)   # cross BACK to the arena
			s.armed = false
		if not s.collected \
				and _player.position.distance_squared_to(_path.rings[sp.cache].p) < CACHE_R2:
			s.collected = true
			caches_found += 1
			GameState.score += 300
			GameState.salvage_run += 25
			GameState.salvage_changed.emit(GameState.salvage_total())
			if randf() < 0.2:
				GameState.plasma_bombs += 1
			cache_collected.emit(sp.id)
