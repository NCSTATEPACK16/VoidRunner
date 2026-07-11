class_name HazardManager
extends Node3D
## K3 corridor crushers: piston traps that slam across half the tunnel on a fixed
## cycle — the manual's crushing floors/ceilings, tuned to our fairness bar.
## Telegraphed: the piston judders and clanks before it slams, and it only ever
## covers one lateral half of the corridor, so it is dodged by steering OR by
## boost/brake timing. Damage is shield-scrape scale (wall-bounce philosophy),
## never lethal-instant.

const CYCLE := 2.4
const WARN_AT := 0.9      # judder + clank
const SLAM_AT := 1.2      # fast descend over 0.15 s
const HOLD_TO := 2.0      # crushing until here, then retracts
const DMG := 10.0
const WARN_RANGE_SQ := 90.0 * 90.0

var player: PlayerShip
var path: PathGen

var _traps: Array[Dictionary] = []   # {node, ring, side, phase, hurt_cd, warned}
var _mat: StandardMaterial3D


## Per-level: crushers wear the zone's wall texture with a hot accent edge —
## a duplicate of an already-warmed material class (same as doors), so no new
## shader variant compiles mid-flight.
func setup(wall_mat: StandardMaterial3D, accent: Color) -> void:
	_mat = wall_mat.duplicate()
	_mat.emission_enabled = true
	_mat.emission = accent
	_mat.emission_energy_multiplier = 0.3


func clear_all() -> void:
	for t in _traps:
		t.node.queue_free()
	_traps.clear()


func spawn_trap(ring_idx: int, side: float) -> void:
	var ring: Dictionary = path.rings[ring_idx]
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	# covers one lateral half (plus a little wall overlap so no sliver gap shows)
	box.size = Vector3(ring.hw + 0.8, ring.hh * 2.0, 2.0)
	mi.mesh = box
	mi.material_override = _mat
	add_child(mi)
	var trap := {
		"node": mi, "ring": ring_idx, "side": side,
		"phase": fmod(ring_idx * 0.77, CYCLE), "hurt_cd": 0.0, "warned": false,
	}
	_traps.append(trap)
	_position_trap(trap, 0.0)


func update_traps(delta: float) -> void:
	for t in _traps:
		t.phase = fmod(t.phase + delta, CYCLE)
		t.hurt_cd -= delta
		var ext := 0.0
		if t.phase < WARN_AT:
			t.warned = false
		elif t.phase < SLAM_AT:
			ext = 0.04 + 0.03 * sin(t.phase * 60.0)   # judder telegraph
			if not t.warned:
				t.warned = true
				var ring: Dictionary = path.rings[t.ring]
				if player and ring.p.distance_squared_to(player.position) < WARN_RANGE_SQ:
					AudioSys.play_clank()
		elif t.phase < HOLD_TO:
			ext = clampf((t.phase - SLAM_AT) / 0.15, 0.0, 1.0)
		else:
			ext = 1.0 - clampf((t.phase - HOLD_TO) / (CYCLE - HOLD_TO), 0.0, 1.0)
		_position_trap(t, ext)
		if ext > 0.85 and t.hurt_cd <= 0.0 and player \
				and absi(player.ring_idx - t.ring) <= 1:
			var ring: Dictionary = path.rings[t.ring]
			var lat: float = (player.position - ring.p).dot(ring.r)
			if lat * t.side > -1.0:   # inside the covered half (plus a little grace)
				t.hurt_cd = 0.8
				player.take_damage(DMG, "CRUSHER IMPACT")
				player.bounce += ring.r * (-t.side * 18.0)   # shove into the open half


## ext 0 = parked out of sight beyond the ceiling; ext 1 = floor-to-ceiling slam.
func _position_trap(t: Dictionary, ext: float) -> void:
	var ring: Dictionary = path.rings[t.ring]
	var base: Vector3 = ring.p + ring.r * (t.side * ring.hw * 0.5)
	t.node.transform = Transform3D(
		Basis(ring.r, ring.u, -ring.d),
		base + ring.u * ((ring.hh * 2.0 + 0.5) * (1.0 - ext)))
