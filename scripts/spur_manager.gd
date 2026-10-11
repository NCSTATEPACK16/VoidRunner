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
## The hatch reuses the walls' (already-warmed) shader and the cache uses the pickup
## manager's existing station path, so this phase adds NO new shader/material variant.
##
## v4c: a spur has a kind. "supply" is the cache above; a hub's "key" branch holds the
## keycard (a station, collected once), and its "switch" branch holds a wall lever: fly
## through it and it throws (switch_flipped), opening the vault beyond the hub.

signal cache_collected(id: int)
signal switch_flipped

const SNAP_R2 := 64.0        # 8 u — snap trigger radius (> the ~1.6 u wall-clamp margin)
const REARM_R2 := 144.0      # 12 u — must clear the mouth before another snap arms
const CACHE_R2 := 121.0      # 11 u — cache-bundle award radius
const HATCH_HIDE_R2 := 81.0  # 9 u — the hatch "opens" (hides) inside this
const SWITCH_R2 := 25.0      # v4c: fly within 5 u of the lever to throw it
const SWITCH_OFF := Color(1.0, 0.25, 0.15)
const SWITCH_ON := Color(0.3, 1.0, 0.4)

var _path = null
var _player = null
var _pickups = null
var _hatch_mat: Material = null
var _spurs: Array = []       # per spur: {def, hatch: MeshInstance3D, armed, collected}
var caches_found := 0
var switch_on := false            # v4c: the hub switch has been thrown
var _rig: LightRig = null
var _key_station := {}            # the keycard's station (PickupManager), if any
var _switch_node: Sprite3D = null
var _switch_light := -1
var _switch_pos := Vector3.ZERO


## Called by game._load_level_world after path.add_spurs(). Builds a hatch per spur and
## spills each cache chamber's fly-through pickups. A no-op when the path has no spurs.
func setup(path, player, pickups, hatch_mat: Material, rig: LightRig = null) -> void:
	_clear()
	_path = path
	_player = player
	_pickups = pickups
	_hatch_mat = hatch_mat
	_rig = rig
	for sp in path.spurs:
		var hatch := _build_hatch(sp)
		_spurs.append({"def": sp, "hatch": hatch, "armed": true, "collected": false})
		match sp.get("kind", "supply"):
			"key":
				_key_station = pickups.add_station(path.rings[sp.cache].p, "keycard")
			"switch":
				_build_switch(sp)
			_:
				_spill_cache(sp)


## Checkpoints: the spur ids whose caches were already collected.
func collected_ids() -> Array:
	var out := []
	for s in _spurs:
		if s.collected:
			out.append(int(s.def.id))
	return out


## v4c: how many supply caches this level has (the tally's total; key and switch
## branches hold no cache).
func supply_count() -> int:
	var n := 0
	for s in _spurs:
		if s.def.get("kind", "supply") == "supply":
			n += 1
	return n


## A resume marks those caches collected, so they don't pay out twice.
func mark_collected(ids: Array) -> void:
	for s in _spurs:
		if int(s.def.id) in ids:
			s.collected = true


func _clear() -> void:
	for s in _spurs:
		if is_instance_valid(s.hatch):
			s.hatch.queue_free()
	_spurs.clear()
	caches_found = 0
	switch_on = false
	_key_station = {}
	if is_instance_valid(_switch_node):
		_switch_node.queue_free()
	_switch_node = null
	_switch_light = -1


## v4c: the lever on the switch chamber's far wall, lit red until it's thrown.
func _build_switch(sp: Dictionary) -> void:
	var ring: Dictionary = _path.rings[sp.cache + 1]
	_switch_pos = ring.p
	_switch_node = SpriteGen.make_sprite(SpriteForge.pickup_frames("switch")[0], 5.0)
	_switch_node.position = _switch_pos
	add_child(_switch_node)
	if _rig != null:
		_switch_light = _rig.add_static(_switch_pos, SWITCH_OFF, 1.6, 26.0, "pulse")


## v4c: throw the switch (flown through, or restored from a checkpoint).
func set_switch(on: bool) -> void:
	switch_on = on
	if is_instance_valid(_switch_node):
		_switch_node.texture = SpriteForge.pickup_frames("switch_on" if on else "switch")[0]
	if _rig != null and _switch_light >= 0:
		var st: Dictionary = _rig.statics()[_switch_light]
		st.color = SWITCH_ON if on else SWITCH_OFF
		st.mode = "steady" if on else "pulse"


## v4c: the keycard is taken (picked up, or already held on a resume): its station goes.
func take_key() -> void:
	if not _key_station.is_empty():
		_pickups.clear_station(_key_station)


## v4c: where the keycard and the switch are, for the automap (Vector3.INF if none).
func key_pos() -> Vector3:
	var sp: Dictionary = _path.spur_of("key") if _path != null else {}
	return _path.rings[sp.cache].p if not sp.is_empty() else Vector3.INF


func switch_pos() -> Vector3:
	return _switch_pos if is_instance_valid(_switch_node) else Vector3.INF


func _build_hatch(sp: Dictionary) -> MeshInstance3D:
	var er: Dictionary = _path.rings[sp.entry]
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, maxf((er.hh - er.fo - er.co) * 1.6, 3.0), PathGen.SEG * 2.2)
	mi.mesh = box
	mi.material_override = _hatch_mat   # 3.0: a sector prop material (warmed shader)
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
		if sp.get("kind", "supply") == "switch":
			if not switch_on and _player.position.distance_squared_to(_switch_pos) < SWITCH_R2:
				set_switch(true)
				switch_flipped.emit()
			continue
		if sp.get("kind", "supply") != "supply":
			continue   # the key branch's keycard is a station (PickupManager)
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
