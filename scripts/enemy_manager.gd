class_name EnemyManager
extends Node3D
## Sprite-billboard drones (PLAN.md C3/C4 + F3). AI is the v2.2 port: drift toward
## the player inside 120 u, bob, timed fire with target lead — and, critically, the
## ring-clamp every frame that fixed the "unreachable enemy" bug. Locked-arena
## drones never despawn, so kill-locked doors can always be opened.
##
## 3.0 phase 5 adds three behaviours with readable tells — STINGER (stalks, flashes,
## then dives in a straight line), SPINNER (throws expanding rings with a safe hole
## in the middle) and MINE (drifts, arms with a red blink, bursts; shot from range it
## pops harmlessly and chains into its neighbours) — and gives each boss its own
## attack pattern (see _update_boss).
##
## v4b adds more, each with one rule to learn: LAYER (seeds mines behind itself on the
## straights), RAMMER (a warning tone, then a straight charge: roll through it), MENDER
## (repairs the swarm: kill it first), SPLITTER (bursts into three drones), WRAITH
## (cloaked until it shimmers in to fire: hit it while it shows), CRAWLER (creeps along
## a wall and fires bursts across the tunnel), WARDEN (a front shield turns light
## shots: flank it or use BOLT) and CARRIER (launches drones until its bays are shot
## out). Heavy rammers, splitters and wardens wear their base sprites with a tint.

signal enemy_killed(arena_id: int)
## v4b: a locked arena's tally grows by `count` (a splitter burst into its brood),
## so the room's bulkhead waits for them too
signal arena_reinforced(arena_id: int, count: int)
## v4b: a mender patched the enemy at `pos` (green sparks and a chime)
signal mended(pos: Vector3)
## v4b: a warden's shield turned a shot aside at `pos` (blue sparks and a ping)
signal deflected(pos: Vector3)
## v4b: a line for the HUD ("CARRIER BAYS DOWN")
signal announced(text: String)
## Re-audit Step 6: `src` is the firing enemy's node, so a stray bolt can hit its
## neighbours (infighting) but never its shooter; boss patterns pass null and never
## infight, which keeps every boss fight as designed.
signal enemy_fired(origin: Vector3, velocity: Vector3, dmg: float, shot_size: float,
	seeker: bool, src: Node3D)
signal exploded(pos: Vector3, big: bool)
signal turret_destroyed(pos: Vector3)   # V2.0: game chains fuel cells off this
signal boss_killed
signal boss_phase(phase: int)
signal drop_spawned(pos: Vector3, ring: int, kind: String, value: int)
signal gibs_requested(pos: Vector3, vel: Vector3, ring: int, count: int, tint: Color)   # V2.2 L1

const CONTACT_DMG := 12.0
const ENEMY_CAP := 42
const FRAME_TIME := 0.25
const SHOT_DMG := 9.0            # standard enemy bolt damage (boss shots override)
const HIT_R2 := 13.0             # standard shot-vs-enemy hit radius² (bosses override)

# Phase J boss tuning
const BOSS_ENGAGE := 200.0       # the 120 u drone gate is too small for the room
const BOSS_FIRE_RANGE := 160.0
const BOSS_SHOT_DMG := 14.0
const BOSS_CONTACT_DMG := 20.0
const MAX_SUMMONS := 4
const MAX_LAID_MINES := 5        # 3.0: brood mother's mine cap

# 3.0 phase 5 tuning
const STINGER_STANDOFF := 38.0   # hangs this far off the player's nose
const STINGER_WIND := 0.65       # the tell: freeze + flicker + beep before a dive
const STINGER_DIVE_T := 1.3
const STINGER_DIVE_SPEED := 52.0
const STINGER_DMG := 14.0
const SPINNER_SPOKES := 8
const MINE_ARM_R := 14.0         # arms when the ship comes this close...
const MINE_FUSE := 0.6           # ...and bursts this long after
const MINE_BLAST_R := 9.0
const MINE_DMG := 15.0
const MINE_CHAIN_DMG := 4        # what a burst does to enemies caught in it
## Chance a scored kill drops a timed power-up (heavies carry them more often).
const POWER_DROP := {"hulk": 0.10, "spinner": 0.08, "layer": 0.05, "rammer": 0.06,
	"mender": 0.08, "splitter": 0.04, "wraith": 0.06, "crawler": 0.05, "warden": 0.06,
	"carrier": 0.30, "rammer_hv": 0.12, "splitter_hv": 0.12, "warden_hv": 0.12}
const POWER_DROP_BASE := 0.025

## Per-type tuning (I3). Stats derive from the level's base numbers × these, so each
## type stays relative as the campaign scales. behavior: "chase" | "weave" |
## "turret" | 3.0's "dive" (stinger) | "spin" (spinner) | "mine" | v4b's "lay" (layer)
## | "ram" (rammer) | "mend" (mender) | "cloak" (wraith) | "crawl" (crawler) | "ward"
## (warden) | "carry" (carrier). The splitter chases; its rule is its death.
## 3.0: sizes grew ~12% — the baked sprites leave a margin inside their cell.
## v4b optional keys: gibs (debris chunks, 6), salvage (a sure drop; 0 = the 30% roll,
## -1 = none), drop_mult (pickup odds), hit_r2 (else HIT_R2), split + split_into (the
## brood a death releases), burst (shots per crawler burst), shield (a front shield,
## see hit_enemy), turn (how fast it swings to face you), and for a heavy variant
## model (the base type whose sprite set it wears) + tint (folded into its light).
const TYPES := {
	"drone":  {"hp_mul": 1.0, "hp_add": 0,  "speed_mul": 1.0,  "fire_mul": 1.0,  "score": 100, "size": 4.7, "behavior": "chase"},
	"weaver": {"hp_mul": 1.0, "hp_add": -1, "speed_mul": 1.7,  "fire_mul": 0.85, "score": 150, "size": 3.8, "behavior": "weave"},
	"hulk":   {"hp_mul": 2.0, "hp_add": 3,  "speed_mul": 0.55, "fire_mul": 0.7,  "score": 300, "size": 6.2, "behavior": "chase",
		"gibs": 12, "salvage": 15, "drop_mult": 1.6},
	"turret": {"hp_mul": 1.5, "hp_add": 2,  "speed_mul": 0.0,  "fire_mul": 1.1,  "score": 200, "size": 5.0, "behavior": "turret",
		"salvage": 10},
	"stinger": {"hp_mul": 0.6, "hp_add": 0, "speed_mul": 1.2,  "fire_mul": 1.0,  "score": 175, "size": 4.0, "behavior": "dive"},
	"spinner": {"hp_mul": 1.4, "hp_add": 1, "speed_mul": 0.45, "fire_mul": 1.5,  "score": 250, "size": 5.2, "behavior": "spin",
		"salvage": 8},
	"mine":   {"hp_mul": 0.0, "hp_add": 1,  "speed_mul": 0.3,  "fire_mul": 1.0,  "score": 50,  "size": 3.6, "behavior": "mine",
		"salvage": -1},
	# --- v4b roster ---
	"layer": {"hp_mul": 1.0, "hp_add": 1, "speed_mul": 1.3, "fire_mul": 1.0, "score": 200, "size": 4.8, "behavior": "lay",
		"salvage": 6, "drop_mult": 1.2},
	"rammer": {"hp_mul": 2.2, "hp_add": 3, "speed_mul": 0.8, "fire_mul": 1.0, "score": 300, "size": 5.8, "behavior": "ram",
		"gibs": 10, "salvage": 8, "drop_mult": 1.3, "hit_r2": 20.0},
	"mender": {"hp_mul": 0.8, "hp_add": 0, "speed_mul": 1.1, "fire_mul": 1.0, "score": 225, "size": 4.2, "behavior": "mend",
		"salvage": 6, "drop_mult": 1.5},
	"splitter": {"hp_mul": 1.5, "hp_add": 1, "speed_mul": 0.55, "fire_mul": 1.3, "score": 200, "size": 5.4, "behavior": "chase",
		"split": 3, "split_into": "drone", "hit_r2": 17.0},
	"wraith": {"hp_mul": 0.9, "hp_add": 0, "speed_mul": 1.2, "fire_mul": 1.0, "score": 250, "size": 4.4, "behavior": "cloak",
		"salvage": 6, "drop_mult": 1.2},
	"crawler": {"hp_mul": 1.2, "hp_add": 1, "speed_mul": 0.8, "fire_mul": 1.1, "score": 175, "size": 4.6, "behavior": "crawl",
		"burst": 3, "salvage": 6},
	"warden": {"hp_mul": 1.5, "hp_add": 2, "speed_mul": 0.6, "fire_mul": 1.0, "score": 250, "size": 5.6, "behavior": "ward",
		"shield": true, "turn": 1.1, "salvage": 8, "hit_r2": 18.0},
	"carrier": {"hp_mul": 5.0, "hp_add": 6, "speed_mul": 0.35, "fire_mul": 1.4, "score": 600, "size": 9.5, "behavior": "carry",
		"gibs": 16, "salvage": 25, "drop_mult": 2.0, "hit_r2": 52.0},
	# heavy variants: the same rule in more armour, on their base's sprites, tinted
	"rammer_hv": {"hp_mul": 3.5, "hp_add": 4, "speed_mul": 0.8, "fire_mul": 1.0, "score": 450, "size": 6.8, "behavior": "ram",
		"gibs": 12, "salvage": 15, "drop_mult": 1.6, "hit_r2": 27.0,
		"model": "rammer", "tint": Color(1.35, 0.62, 0.5)},
	"splitter_hv": {"hp_mul": 2.5, "hp_add": 2, "speed_mul": 0.45, "fire_mul": 1.2, "score": 400, "size": 6.6, "behavior": "chase",
		"split": 3, "split_into": "drone", "gibs": 12, "salvage": 15, "drop_mult": 1.6, "hit_r2": 25.0,
		"model": "splitter", "tint": Color(1.05, 0.62, 1.4)},
	"warden_hv": {"hp_mul": 2.5, "hp_add": 3, "speed_mul": 0.45, "fire_mul": 0.9, "score": 450, "size": 6.8, "behavior": "ward",
		"shield": true, "turn": 0.8, "gibs": 12, "salvage": 15, "drop_mult": 1.6, "hit_r2": 26.0,
		"model": "warden", "tint": Color(1.35, 1.1, 0.5)},
}

# v4b roster tuning
const LAY_REACH := 40             # rings a layer may run ahead of where it began
const LAY_LEAD := 4               # rings ahead of the ship it holds (48 u: inside 40-60)
const LAY_SPEED := 24.0           # outruns cruise (18 u/s), not the afterburner (38)
const LAY_T := 2.4                # it drops a mine this often on a straight...
const LAY_CAP := 3                # ...with at most this many of its own alive
const MEND_T := 1.6               # a mender's repair clock (difficulty tempo)...
const MEND_R := 28.0              # ...and how far its repair reaches
const RAMMER_REV := 0.7           # the warning before a charge (× warn_mult)
const RAMMER_SPEED := 78.0
const RAMMER_CHARGE_T := 2.2      # a charge that long burns out against the wall
const RAMMER_HIT_R := 5.5
const RAMMER_DMG := 22.0
const WRAITH_TELL := 0.6          # its shimmer before it fires (× warn_mult)...
const WRAITH_SHOW := 1.0          # ...and how long it stays in view (and hittable) after
const CRAWL_REACH := 10           # rings a crawler may creep from where it landed
const CRAWL_BURST_GAP := 0.13     # seconds between the shots of one burst
const WARDEN_ARC_COS := 0.5736    # cos 55°: a hit inside this front arc meets the shield...
const WARDEN_BLOCK := 3           # ...and is turned aside if it does less than this
const LAUNCH_T := 3.5             # a carrier launches a drone this often...
const CARRIER_LIVE := 3           # ...with at most this many of its own alive...
const BAY_HP := 10                # ...until it has taken this much damage: the bays blow

var path: PathGen
var player: PlayerShip
var level: LevelDef
var world: WorldBuilder   # 3.0: sprites take the baked light of the ring they're in

var enemies: Array[Dictionary] = []
## The live boss's dict (also present in `enemies`), or {} — HUD/radar poll this.
var boss := {}
var _sets := {}   # 3.0: model id -> SpriteForge sprite set (8 angles x 2 frames + flash)
# V2.1: small node cache so arena-discovery and boss-summon spawn bursts (and the
# matching kill bursts) stop churning Sprite3D instantiate/queue_free mid-combat
const NODE_CACHE_CAP := 16
var _node_cache: Array[Sprite3D] = []
# 3.0: mine bursts queue here and resolve at the top of the next update, outside
# any walk over `enemies` — so a chain reaction can never corrupt a loop index
var _pending_blasts: Array[Vector3] = []
# v4b: a splitter's brood hatches the same way, the frame after it dies. Its slots
# are reserved under ENEMY_CAP when it dies, so the brood always counts toward the cap
var _pending_splits: Array[Dictionary] = []
var _reserved := 0

# V2.2 L1: debris tint per archetype (boss gibs use its own modulate tint instead).
# Approximations of each sprite's dominant hull color; the dither pass re-quantizes.
const GIB_TINTS := {
	"drone": Color(0.62, 0.64, 0.7),
	"weaver": Color(0.45, 0.72, 0.5),
	"hulk": Color(0.38, 0.44, 0.66),
	"turret": Color(0.55, 0.55, 0.58),
	"stinger": Color(0.85, 0.72, 0.2),
	"spinner": Color(0.78, 0.35, 0.7),
	"mine": Color(0.4, 0.4, 0.46),
	"layer": Color(0.55, 0.57, 0.33),
	"rammer": Color(0.62, 0.65, 0.72),
	"mender": Color(0.9, 0.92, 0.95),
	"splitter": Color(0.2, 0.7, 0.66),
	"wraith": Color(0.35, 0.22, 0.6),
	"crawler": Color(0.78, 0.42, 0.2),
	"warden": Color(0.85, 0.86, 0.9),
	"carrier": Color(0.32, 0.38, 0.58),
}


func _ready() -> void:
	for id in SpriteModels.ENEMIES + SpriteModels.BOSSES:
		_sets[id] = SpriteForge.sprite_set(id)


## 3.0: weighted timed power-up — OVERDRIVE most common, PHASE SHIELD rarest.
static func random_power() -> String:
	var r := randf()
	if r < 0.40:
		return "overdrive"
	if r < 0.75:
		return "powercore"
	return "phase"


## v4b: the type whose sprite set (and intro) a type shares: a heavy's base type, or
## the type itself.
static func base_type(id: String) -> String:
	var t: Dictionary = TYPES.get(id, {})
	return String(t.get("model", id))


## v4b: what an enemy's light looks like with its tint folded in (a heavy's colour
## ramp, a boss's tint).
func _lit(e: Dictionary) -> Color:
	return _light_for(e.ring) * (e.get("tint", Color.WHITE) as Color)


## Re-audit Step 4: drop every enemy the predicate picks (a resumed checkpoint
## removes cleared arenas' guards and tunnel spawns behind the ship).
func remove_where(pick: Callable) -> int:
	var removed := 0
	for k in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[k]
		if e.get("is_boss", false) or not pick.call(e):
			continue
		_release_node(e.node)
		enemies.remove_at(k)
		removed += 1
	return removed


func clear_all() -> void:
	for e in enemies:
		_release_node(e.node)   # cache keeps up to NODE_CACHE_CAP across levels
	enemies.clear()
	boss = {}
	_pending_blasts.clear()
	_pending_splits.clear()
	_reserved = 0


func _acquire_node(tex: Texture2D, world_size: float) -> Sprite3D:
	if _node_cache.is_empty():
		var s := SpriteGen.make_sprite(tex, world_size)
		add_child(s)
		return s
	var c: Sprite3D = _node_cache.pop_back()
	c.texture = tex
	c.pixel_size = world_size / tex.get_width()
	c.modulate = Color.WHITE   # clears any boss tint from a previous life
	c.visible = true
	return c


func _release_node(s: Sprite3D) -> void:
	if _node_cache.size() >= NODE_CACHE_CAP:
		s.queue_free()
		return
	s.visible = false
	_node_cache.append(s)


## First frame of every enemy type (incl. bosses), for the briefing shader warm-up.
func warmup_textures() -> Array:
	var texes: Array = []
	for id in _sets:
		texes.append(_sets[id].tex[0])
	return texes


## 3.0: pick the baked angle for where the camera sits relative to the enemy's
## facing, and show the current idle frame (or the hit flash while it's fresh).
func _skin(e: Dictionary) -> void:
	var st: Dictionary = e.skin
	var node: Sprite3D = e.node
	var a := SpriteForge.angle_index(e.facing, player.position - node.position, st.angles)
	if e.flash_t > 0.0:
		node.texture = st.flash[a]
	else:
		node.texture = st.tex[a * st.anim + e.frame]


## 3.0: turn toward `want` (flattened to the horizontal) at `rate` per second.
## Interpolates the yaw angle directly: Vector3.slerp builds its axis from a
## cross product, which loses precision (and trips the engine's normalized-axis
## check) when a sloped spawn facing lines up almost exactly with the target.
func _turn(e: Dictionary, want: Vector3, rate: float, delta: float) -> void:
	if want.x * want.x + want.z * want.z < 0.0001:
		return
	var f: Vector3 = e.facing
	var cur := atan2(f.x, f.z)
	var a := cur + wrapf(atan2(want.x, want.z) - cur, -PI, PI) * minf(1.0, rate * delta)
	e.facing = Vector3(sin(a), 0.0, cos(a))


## 3.0: sprites stand in the sector light — a drone under a lamp pops, one in a
## dark arena reads as a silhouette (never fully black: they must stay readable).
func _light_for(ring_idx: int) -> Color:
	if world == null:
		return Color.WHITE
	var l := world.ring_light(ring_idx)
	return Color(clampf(0.45 + l.r * 0.75, 0.5, 1.25), clampf(0.45 + l.g * 0.75, 0.5, 1.25),
		clampf(0.45 + l.b * 0.75, 0.5, 1.25))


## `force` is only for a splitter's brood, whose slots were reserved under the cap when
## its parent died (see _kill).
func spawn(ring_idx: int, arena_id: int, type_id := "drone", force := false) -> void:
	if not force and arena_id < 0 and enemies.size() + _reserved >= ENEMY_CAP:
		return
	var t: Dictionary = TYPES.get(type_id, TYPES["drone"])
	# v4b: a heavy wears its base type's sprite set, tinted
	var st: Dictionary = _sets.get(base_type(type_id), _sets["drone"])
	var ring: Dictionary = path.rings[ring_idx]
	var sprite := _acquire_node(st.tex[0], t.size)
	var pos: Vector3 = ring.p \
		+ ring.r * (randf_range(-1.0, 1.0) * ring.hw * 0.5) \
		+ ring.u * (randf_range(-1.0, 1.0) * ring.hh * 0.4)
	sprite.position = path.clamp_to_ring(pos, ring_idx, 2.5)
	# 3.0: enemies spawn facing back down the tunnel, toward where the player comes from
	var facing: Vector3 = -ring.d
	var side := 0.0
	var wall_v := 0.0
	if t.behavior == "turret" or t.behavior == "crawl":
		# V2.0 wall turret (v4b: and the crawler): flush against one wall
		side = 1.0 if randf() < 0.5 else -1.0
		wall_v = randf_range(-0.35, 0.25)
		sprite.position = _wall_point(ring, side, wall_v)
		facing = ring.r * -side   # its muzzle looks across the tunnel
	var tint: Color = t.get("tint", Color.WHITE)
	sprite.modulate = _light_for(ring_idx) * tint
	var hp := maxi(1, int(round(level.enemy_hp * t.hp_mul)) + int(t.hp_add))
	var e := {
		"node": sprite, "hp": hp,
		"fire_t": 1.5 + randf() * 2.0,
		"bob_p": randf() * TAU, "ring": ring_idx, "arena_id": arena_id,
		"anim_t": randf() * FRAME_TIME, "frame": 0, "flash_t": 0.0,
		"skin": st, "facing": facing, "lit_ring": ring_idx,
		"speed": level.enemy_speed * t.speed_mul,
		"fire": level.enemy_fire * t.fire_mul, "score": int(t.score),
		"behavior": t.behavior, "weave_p": randf() * TAU,
		"hit_r2": float(t.get("hit_r2", HIT_R2)),
		"type": type_id,
		# 3.0 phase 5 state: stinger dive cycle, spinner ring rotation, mine arming
		"mode": "idle" if t.behavior == "mine" else "stalk",
		"mode_t": randf_range(1.0, 2.4), "dive_dir": Vector3.ZERO, "spin_a": randf() * TAU,
		# V2.0: late-campaign (and deep-gauntlet) turrets fire seeking shots —
		# the manual's seeking missile-wall variant. Dodge roll i-frames beat them.
		"seeker": t.behavior == "turret" and (GameState.level_index >= 5
			or (GameState.gauntlet_mode and level.enemy_speed >= 9.0)),
		# v4b: repairs top out at max_hp; a layer's stretch of tunnel and its lane; a
		# heavy's tint; a warden's shield and slow turn
		"max_hp": hp, "lo": ring_idx, "hi": ring_idx, "lane": 0.0, "tint": tint,
		"shielded": bool(t.get("shield", false)), "turn": float(t.get("turn", 5.0)),
	}
	match t.behavior:
		"lay":
			var span := _travel_range(ring_idx, arena_id, 0, LAY_REACH)
			e.lo = span.x
			e.hi = span.y
			e.lane = randf_range(-0.4, 0.4)
		"crawl":
			# its wall, where on it, and the stretch it may creep along
			var span := _travel_range(ring_idx, arena_id, CRAWL_REACH, CRAWL_REACH)
			e.lo = span.x
			e.hi = span.y
			e.side = side
			e.wall_v = wall_v
			e.ring_f = float(ring_idx)
			e.burst = 0
			e.burst_t = 0.0
		"carry":
			e.side = 1.0 if randf() < 0.5 else -1.0   # which flank it turns to you
			e.bays = true
			e.launch_t = 2.0
		"cloak":
			# a wraith arrives unseen; its first shimmer comes after a beat
			e.mode = "cloak"
			e.cloaked = true
			e.tell = WRAITH_TELL
			e.hit_r2 = -1.0
			sprite.visible = false
	enemies.append(e)


## A point flush with one tunnel wall (side -1/+1), `v` of the way up or down it.
func _wall_point(ring: Dictionary, side: float, v: float) -> Vector3:
	return ring.p + ring.r * (side * (ring.hw - 1.6)) + ring.u * (v * (ring.hh - ring.fo - ring.co))


## v4b: the stretch of rings an enemy may travel along — `back` rings behind and
## `ahead` rings in front of `ring_idx`. That's its own arena if it guards one, its
## post if it guards a spur, and otherwise plain tunnel that stops short of any
## arena mouth or bulkhead, so nothing creeps through a sealed door.
func _travel_range(ring_idx: int, arena_id: int, back: int, ahead: int) -> Vector2i:
	if arena_id >= 0 and arena_id < path.arenas.size():
		var a: Dictionary = path.arenas[arena_id]
		return Vector2i(a.start, a.end)
	if path.rings[ring_idx].get("spur", -1) >= 0:
		return Vector2i(ring_idx, ring_idx)
	var doors := {}
	for a in path.arenas:
		if a.door_ring >= 0:
			doors[a.door_ring] = true
	var last := (path.rings.size() if path.is_endless else path.main_ring_count) - 2
	var lo := ring_idx
	while lo > maxi(1, ring_idx - back) and not path.rings[lo - 1].arena and not doors.has(lo - 1):
		lo -= 1
	var hi := ring_idx
	while hi < mini(last, ring_idx + ahead) and not path.rings[hi + 1].arena \
			and not doors.has(hi + 1):
		hi += 1
	return Vector2i(lo, hi)


## Phase J: the boss rides the same enemies array, so shots, splash, homing
## missiles, and the radar all handle it for free — but it takes absolute HP from
## the level (the mul/add formula tops out single digits), gets a hit radius that
## matches its sprite, and runs its own brain in _update_boss.
func spawn_boss(ring_idx: int, lvl: LevelDef) -> void:
	var ring: Dictionary = path.rings[ring_idx]
	# 3.0: each boss is its own baked model (LevelDef.boss_model), not one tinted sprite
	var st: Dictionary = _sets.get(lvl.boss_model, _sets["sentinel"])
	var sprite := _acquire_node(st.tex[0], lvl.boss_size)
	sprite.modulate = lvl.boss_tint
	sprite.position = ring.p
	boss = {
		"node": sprite, "hp": lvl.boss_hp, "max_hp": lvl.boss_hp,
		"fire_t": 2.0, "bob_p": 0.0, "ring": ring_idx, "arena_id": -1,
		"anim_t": 0.0, "frame": 0, "flash_t": 0.0,
		"skin": st, "facing": -ring.d, "lit_ring": ring_idx, "speed": lvl.enemy_speed,
		"fire": lvl.enemy_fire, "score": lvl.boss_hp * 10, "behavior": "boss",
		"weave_p": 0.0, "hit_r2": pow(lvl.boss_size * 0.42, 2.0),
		"is_boss": true, "size": lvl.boss_size, "phase": 1,
		"volley_t": 4.0, "summon_t": 6.0, "anchor": ring.p, "home_ring": ring_idx,
		# 3.0: which attack pattern runs (see _update_boss) and its clocks
		"model": lvl.boss_model, "lay_t": 3.0, "spin_a": 0.0,
		"spiral_t": 0.0, "spiral_cd": 0.0, "spiral_a": 0.0,
		"tint": lvl.boss_tint,   # v4b: the ring re-light folds it in, as for a heavy
	}
	enemies.append(boss)


func update_enemies(delta: float) -> void:
	# 3.0: last frame's mine bursts hit whatever floats next to them (and may
	# queue the next link of a chain for the frame after)
	if not _pending_blasts.is_empty():
		var blasts := _pending_blasts.duplicate()
		_pending_blasts.clear()
		for bp: Vector3 in blasts:
			splash_damage(bp, MINE_BLAST_R, MINE_CHAIN_DMG)
	if not _pending_splits.is_empty():
		_hatch_splits()
	for k in range(enemies.size() - 1, -1, -1):
		var e: Dictionary = enemies[k]
		var node: Sprite3D = e.node
		# sprite animation: 2-frame idle cycle; the hit flash overrides briefly
		# (3.0: the texture itself is chosen by _skin once facing is known)
		e.anim_t += delta
		if e.flash_t > 0.0:
			e.flash_t -= delta
		elif e.anim_t >= FRAME_TIME:
			e.anim_t = 0.0
			e.frame = (e.frame + 1) % 2
		e.bob_p += delta * 2.0
		if e.ring != e.lit_ring:   # 3.0: re-sample the sector light on ring change
			e.lit_ring = e.ring
			node.modulate = _lit(e)   # v4b: with a heavy's (or a boss's) tint folded in
		if e.get("is_boss", false):
			_update_boss(e, delta)
			_skin(e)
			continue  # never despawns, never dies on contact
		if e.behavior == "turret":
			# V2.0 wall turret: a fixed gun, not a ram — no drift, no clamp, no
			# contact damage. Aimed shots inside 110 u; seekers on late levels.
			var turret_to_player: Vector3 = player.position - node.position
			var turret_dist := turret_to_player.length()
			if turret_dist < 110.0:
				e.fire_t -= delta * GameState.enemy_tempo()   # Step 3: difficulty clock
				if e.fire_t <= 0.0:
					e.fire_t = e.fire * 0.9 + randf() * e.fire * 0.5
					var taim: Vector3 = player.position \
						+ player.forward() * (player.speed * turret_dist / 24.0 * 0.35) \
						- node.position
					enemy_fired.emit(node.position, taim.normalized() * 24.0,
						SHOT_DMG + 1.0, 2.1 if e.seeker else 1.8, e.seeker, node)
			if _despawn_far(k, e):
				continue
			_skin(e)
			continue
		# 3.0 phase 5 and v4b behaviours: each returns true when it removed the enemy
		if e.behavior != "chase" and e.behavior != "weave":
			var gone := false
			match e.behavior:
				"dive":
					gone = _update_stinger(k, e, delta)
				"spin":
					gone = _update_spinner(k, e, delta)
				"mine":
					gone = _update_mine(k, e, delta)
				"lay":
					gone = _update_layer(k, e, delta)
				"ram":
					gone = _update_rammer(k, e, delta)
				"mend":
					gone = _update_mender(k, e, delta)
				"cloak":
					gone = _update_wraith(k, e, delta)
				"crawl":
					gone = _update_crawler(k, e, delta)
				"ward":
					gone = _update_warden(k, e, delta)
				"carry":
					gone = _update_carrier(k, e, delta)
			if gone or _despawn_far(k, e):
				continue
			_skin(e)
			continue
		var to_player: Vector3 = player.position - node.position
		var dist := to_player.length()
		if dist < 120.0:
			var dir := to_player / maxf(dist, 0.001)
			if dist > 13.0:
				node.position += dir * (e.speed * delta)
			var heading := dir
			# weavers strafe sideways as they close — harder to draw a bead on
			if e.behavior == "weave":
				e.weave_p += delta * 3.0
				var side := dir.cross(Vector3.UP).normalized()
				var strafe: float = sin(e.weave_p) * e.speed * 0.7
				node.position += side * (strafe * delta)
				# 3.0: they bank into the strafe, so their baked side views show
				heading = dir * maxf(e.speed, 0.1) + side * (strafe * 1.6)
			_turn(e, heading, 5.0, delta)
			node.position.y += sin(e.bob_p) * delta * 1.5
			e.ring = path.nearest_ring(node.position, e.ring)
			node.position = path.clamp_to_ring(node.position, e.ring, 2.2)
			e.fire_t -= delta * GameState.enemy_tempo()
			if e.fire_t <= 0.0 and dist < 95.0:
				e.fire_t = e.fire * 0.8 + randf() * e.fire * 0.6
				# lead the target the way v2.2 does
				var aim: Vector3 = player.position \
					+ player.forward() * (player.speed * dist / 26.0 * 0.4) \
					- node.position
				enemy_fired.emit(node.position, aim.normalized() * 26.0, SHOT_DMG, 1.7, false,
					node)
			if dist < 4.5 and player.wall_hurt_t <= 0.0:
				player.wall_hurt_t = 0.45
				player.take_damage(CONTACT_DMG, "COLLISION")
				_kill(k, false)
				continue
		if _despawn_far(k, e):
			continue
		_skin(e)


## Far-behind despawn — never for locked-arena enemies (they gate a door).
func _despawn_far(k: int, e: Dictionary) -> bool:
	if e.arena_id < 0 and player.ring_idx > 20 \
			and e.node.position.distance_squared_to(player.position) > 90000.0:
		_release_node(e.node)
		enemies.remove_at(k)
		return true
	return false


## 3.0 STINGER: hangs off the player's nose, then telegraphs — freezes, flickers
## white, beeps — and dives in a straight line at where the ship WAS: sidestep or
## roll. A dive that connects spends the stinger; a miss coasts past and resets.
## It only ever winds up in front of the ship, so no dive comes from off-screen.
func _update_stinger(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 130.0 and e.mode == "stalk":
		return false   # dormant until the ship is near
	var dir := to_player / maxf(dist, 0.001)
	# Step 3: the idle gap between dives runs on the difficulty clock; the wind-up
	# and the dive itself keep real time (the wind-up is scaled by warn_mult below)
	e.mode_t -= delta * (GameState.enemy_tempo() if e.mode == "stalk" else 1.0)
	match e.mode:
		"stalk":
			if dist > STINGER_STANDOFF + 6.0:
				node.position += dir * (e.speed * delta)
			elif dist < STINGER_STANDOFF - 10.0:
				node.position -= dir * (e.speed * 0.6 * delta)
			e.weave_p += delta * 2.2
			node.position += dir.cross(Vector3.UP).normalized() \
				* (sin(e.weave_p) * e.speed * 0.5 * delta)
			node.position.y += sin(e.bob_p) * delta * 1.2
			_turn(e, to_player, 4.0, delta)
			if e.mode_t <= 0.0 and dist < STINGER_STANDOFF + 20.0 \
					and player.forward().dot(-dir) > 0.45:
				e.mode = "wind"
				e.mode_t = STINGER_WIND * GameState.warn_mult()
				AudioSys.play_warn()
		"wind":
			_turn(e, to_player, 10.0, delta)
			# the tell: a white flicker (held steady under REDUCE FLASH)
			e.flash_t = 0.05 if GameState.reduce_flashing or int(e.mode_t * 12.0) % 2 == 0 \
				else 0.0
			if e.mode_t <= 0.0:
				e.mode = "dive"
				e.mode_t = STINGER_DIVE_T
				e.dive_dir = dir   # locked now: the ship can still get out of the way
		"dive":
			node.position += (e.dive_dir as Vector3) * (STINGER_DIVE_SPEED * delta)
			_turn(e, e.dive_dir, 12.0, delta)
			if e.mode_t <= 0.0:
				e.mode = "recover"
				e.mode_t = 1.0
		"recover":
			# coast to a stop past the miss, turning back toward the ship
			node.position += (e.dive_dir as Vector3) \
				* (STINGER_DIVE_SPEED * 0.3 * maxf(e.mode_t, 0.0) * delta)
			_turn(e, to_player, 3.0, delta)
			if e.mode_t <= 0.0:
				e.mode = "stalk"
				e.mode_t = randf_range(1.4, 2.6)
	e.ring = path.nearest_ring(node.position, e.ring)
	node.position = path.clamp_to_ring(node.position, e.ring, 2.0)
	if dist < 4.5 and player.wall_hurt_t <= 0.0:
		player.wall_hurt_t = 0.45
		player.take_damage(STINGER_DMG, "STINGER HIT")
		_kill(k, false)
		return true
	return false


## 3.0 SPINNER: turns like a top at a standoff and throws expanding rings of
## plasma at the ship. The ring arrives wide with a hole in the middle — hold
## your line and it passes around you; swerve late and you fly into it.
func _update_spinner(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	e.facing = (e.facing as Vector3).rotated(Vector3.UP, delta * 2.6)   # always turning
	if dist > 120.0:
		return false
	var dir := to_player / maxf(dist, 0.001)
	if dist > 52.0:
		node.position += dir * (e.speed * delta)
	elif dist < 30.0:
		node.position -= dir * (e.speed * delta)
	node.position.y += sin(e.bob_p) * delta * 1.2
	e.ring = path.nearest_ring(node.position, e.ring)
	node.position = path.clamp_to_ring(node.position, e.ring, 2.6)
	e.fire_t -= delta * GameState.enemy_tempo()
	if e.fire_t <= 0.0 and dist < 90.0:
		e.fire_t = e.fire * randf_range(0.9, 1.25)
		_ring_burst(node.position, SPINNER_SPOKES, e.spin_a, 17.0, 4.5, SHOT_DMG, node)
		e.spin_a += PI / SPINNER_SPOKES   # the next ring comes rotated half a gap
	if dist < 4.5 and player.wall_hurt_t <= 0.0:
		player.wall_hurt_t = 0.45
		player.take_damage(CONTACT_DMG, "COLLISION")
		_kill(k, false)
		return true
	return false


## 3.0 MINE: drifts on a slow bob and creeps toward passing hulls. Come within
## MINE_ARM_R and it arms — red blink, beep — then bursts, hurting the ship if it
## is still inside the blast. Shot from range it pops harmlessly (for the player)
## and its burst chains into anything floating next to it.
func _update_mine(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	node.position.y += sin(e.bob_p) * delta * 0.7
	e.facing = (e.facing as Vector3).rotated(Vector3.UP, delta * 0.7)   # lazy tumble
	if e.mode != "armed":
		if dist < MINE_ARM_R:
			e.mode = "armed"
			e.mode_t = MINE_FUSE * GameState.warn_mult()
			AudioSys.play_warn()
		elif dist < 45.0:
			node.position += to_player / maxf(dist, 0.001) * (e.speed * delta)
			e.ring = path.nearest_ring(node.position, e.ring)
			node.position = path.clamp_to_ring(node.position, e.ring, 2.0)
		return false
	e.mode_t -= delta
	# armed: blinks hot red (a steady red glow under REDUCE FLASH)
	var hot: bool = GameState.reduce_flashing or int(e.mode_t * 14.0) % 2 == 0
	node.modulate = Color(1.9, 0.35, 0.25) if hot else _lit(e)
	if e.mode_t > 0.0:
		return false
	if dist < MINE_BLAST_R:
		player.take_damage(MINE_DMG, "MINE BLAST")
		player.bounce += to_player / maxf(dist, 0.001) * 10.0   # the burst shoves the ship
	_kill(k, false)
	return true


## v4b MENDER: a repair drone that never fires. It keeps its distance (40-60 u off the
## ship) and, every MEND_T, patches the most damaged enemy in reach (see _mend_near).
## Kill it first, or the fight never ends.
func _update_mender(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 130.0:
		return false
	var dir := to_player / maxf(dist, 0.001)
	if dist > 60.0:
		node.position += dir * (e.speed * delta)
	elif dist < 40.0:
		node.position -= dir * (e.speed * delta)
	e.weave_p += delta * 1.6
	node.position += dir.cross(Vector3.UP).normalized() * (sin(e.weave_p) * e.speed * 0.4 * delta)
	node.position.y += sin(e.bob_p) * delta * 1.2
	_turn(e, to_player, 3.0, delta)
	e.ring = path.nearest_ring(node.position, e.ring)
	node.position = path.clamp_to_ring(node.position, e.ring, 2.2)
	e.fire_t -= delta * GameState.enemy_tempo()   # the repair clock
	if e.fire_t <= 0.0:
		e.fire_t = MEND_T
		_mend_near(e)
	return _collide(k, dist)


## The most damaged enemy within MEND_R of mender `m` gets +1 HP, never past its full
## hull. Bosses (and mini-bosses) are never patched: their fights stay as designed.
func _mend_near(m: Dictionary) -> void:
	var best: Dictionary = {}
	var best_gap := 0.0
	var at: Vector3 = m.node.position
	for o in enemies:
		if is_same(o, m) or o.get("is_boss", false):
			continue
		if o.node.position.distance_squared_to(at) > MEND_R * MEND_R:
			continue
		var gap: float = 1.0 - o.hp / float(o.max_hp)
		if gap > best_gap:
			best_gap = gap
			best = o
	if best.is_empty():
		return
	best.hp = mini(int(best.hp) + 1, int(best.max_hp))
	mended.emit(best.node.position)


## v4b LAYER: a mine-layer. It keeps LAY_LEAD rings (40-60 u) ahead of the ship down
## the tunnel, never past the end of its stretch (so never through a sealed bulkhead),
## and on the straights drops a mine behind itself, at most LAY_CAP of its own alive.
## It outruns a cruising ship but not the afterburner: boost to catch it.
func _update_layer(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 120.0:
		return false
	var hold: Dictionary = path.rings[clampi(player.ring_idx + LAY_LEAD, e.lo, e.hi)]
	var to_goal: Vector3 = hold.p + hold.r * (e.lane * hold.hw) - node.position
	var step := LAY_SPEED * delta
	if to_goal.length() > step:
		node.position += to_goal.normalized() * step
	node.position.y += sin(e.bob_p) * delta * 1.0
	e.ring = path.nearest_ring(node.position, e.ring)
	node.position = path.clamp_to_ring(node.position, e.ring, 2.4)
	_turn(e, path.rings[e.ring].d, 2.0, delta)   # it flies down the tunnel, tail to you
	e.fire_t -= delta * GameState.enemy_tempo()   # the laying clock
	if e.fire_t <= 0.0:
		e.fire_t = LAY_T
		# a mine only goes down between it and the ship, on a straight, under its cap
		if e.ring > player.ring_idx and _straight(e.ring) \
				and _count_tagged("laid_by", node) < LAY_CAP:
			var before := enemies.size()
			spawn(e.ring, -1, "mine")
			if enemies.size() > before:
				var mine: Dictionary = enemies.back()
				mine["laid_by"] = node
				mine.node.position = path.clamp_to_ring(
					node.position - (path.rings[e.ring].d as Vector3) * 3.0, e.ring, 2.0)
	return _collide(k, dist)


## v4b RAMMER: an armoured kamikaze, too tough to shoot down in time. It cruises
## 60-80 u off the nose; its tell is a warning tone and a red engine flare, then it
## charges in a straight line at where the ship was. A dodge roll as it closes wins:
## met mid-roll it shatters on your shields, and a miss can't stop before the wall
## (both score). Taken head-on it hits hard, and it's spent.
func _update_rammer(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 140.0 and e.mode == "stalk":
		return false
	var dir := to_player / maxf(dist, 0.001)
	e.mode_t -= delta * (GameState.enemy_tempo() if e.mode == "stalk" else 1.0)
	match e.mode:
		"stalk":
			if dist > 80.0:
				node.position += dir * (e.speed * delta)
			elif dist < 60.0:
				node.position -= dir * (e.speed * 0.6 * delta)
			node.position.y += sin(e.bob_p) * delta * 0.8
			_turn(e, to_player, 2.0, delta)
			# like the stinger, it only winds up in front of the ship
			if e.mode_t <= 0.0 and dist < 95.0 and player.forward().dot(-dir) > 0.45:
				e.mode = "rev"
				e.mode_t = RAMMER_REV * GameState.warn_mult()
				AudioSys.play_warn()
		"rev":
			# the tell: its engines flare red (a steady glow under REDUCE FLASH)
			_turn(e, to_player, 6.0, delta)
			var hot: bool = GameState.reduce_flashing or int(e.mode_t * 10.0) % 2 == 0
			node.modulate = Color(1.9, 0.45, 0.3) if hot else _lit(e)
			if e.mode_t <= 0.0:
				e.mode = "charge"
				e.mode_t = RAMMER_CHARGE_T
				e.dive_dir = dir   # locked now: a straight line at where the ship was
				node.modulate = _lit(e)
		"charge":
			node.position += (e.dive_dir as Vector3) * (RAMMER_SPEED * delta)
			_turn(e, e.dive_dir, 12.0, delta)
	e.ring = path.nearest_ring(node.position, e.ring)
	var held := path.clamp_to_ring(node.position, e.ring, 2.0)
	if e.mode == "charge":
		var missed: bool = to_player.dot(e.dive_dir) < 0.0 and dist > RAMMER_HIT_R
		# it can't stop: past the ship and into the wall, or out of charge, it wrecks
		if (missed and held.distance_squared_to(node.position) > 0.04) or e.mode_t <= 0.0:
			_kill(k, true)   # you made it miss: yours
			return true
	node.position = held
	if dist < RAMMER_HIT_R and e.mode != "stalk":
		if player.iframes_t > 0.0:
			_kill(k, true)   # rolled through: it shatters on the shields
			return true
		player.wall_hurt_t = 0.45
		player.take_damage(RAMMER_DMG, "RAMMED")
		player.bounce += (e.dive_dir as Vector3) * 18.0
		_kill(k, false)
		return true
	return false


## v4b WRAITH: a cloaker. Cloaked it can't be seen or hit: no radar blip, no missile
## lock, and shots pass straight through (a blast still finds it). Before it fires it
## shimmers into view: a flicker, or under REDUCE FLASH a steady fade up out of the
## dark. From the first shimmer until it vanishes again, WRAITH_SHOW after its volley,
## it can be hit. That's the window.
func _update_wraith(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 130.0 and e.cloaked:
		return false
	var dir := to_player / maxf(dist, 0.001)
	# the unseen drift runs on the difficulty clock; the tell and the strike keep real
	# time (the tell is scaled by warn_mult below)
	e.mode_t -= delta * (GameState.enemy_tempo() if e.cloaked else 1.0)
	match e.mode:
		"cloak":
			# unseen, it slides to a new spot 30-50 u off the nose
			if dist > 50.0:
				node.position += dir * (e.speed * delta)
			elif dist < 30.0:
				node.position -= dir * (e.speed * delta)
			e.weave_p += delta * 1.4
			node.position += dir.cross(Vector3.UP).normalized() \
				* (sin(e.weave_p) * e.speed * 0.8 * delta)
			if e.mode_t <= 0.0 and dist < 70.0:
				e.mode = "shimmer"
				e.tell = WRAITH_TELL * GameState.warn_mult()
				e.mode_t = e.tell
				e.cloaked = false
				e.hit_r2 = float(TYPES[e.type].get("hit_r2", HIT_R2))
				AudioSys.play_warn()
		"shimmer":
			if GameState.reduce_flashing:
				# no flicker: it brightens steadily from a dark silhouette to full light
				var lit := _lit(e)
				var up := clampf(1.0 - e.mode_t / maxf(e.tell, 0.01), 0.0, 1.0)
				node.visible = true
				node.modulate = Color(lit.r * up, lit.g * up, lit.b * up)
			else:
				node.visible = int(e.mode_t * 14.0) % 2 == 0
			if e.mode_t <= 0.0:
				e.mode = "strike"
				e.mode_t = WRAITH_SHOW
				node.visible = true
				node.modulate = _lit(e)
				for a in [-0.12, 0.0, 0.12]:
					enemy_fired.emit(node.position, dir.rotated(Vector3.UP, a) * 28.0, SHOT_DMG,
						1.7, false, node)
		"strike":
			if e.mode_t <= 0.0:
				e.mode = "cloak"
				e.mode_t = randf_range(2.0, 3.2)
				e.cloaked = true
				e.hit_r2 = -1.0
				node.visible = false
	node.position.y += sin(e.bob_p) * delta * 1.0
	_turn(e, to_player, 4.0, delta)
	e.ring = path.nearest_ring(node.position, e.ring)
	node.position = path.clamp_to_ring(node.position, e.ring, 2.2)
	return not e.cloaked and _collide(k, dist)


## v4b CRAWLER: a wall-walker. It clings to its wall like a turret, creeps along the
## tunnel toward the ship (never past its stretch, see _travel_range) and fires
## bursts across the tunnel: watch the sides, not just the middle.
func _update_crawler(_k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 130.0:
		return false   # dormant until the ship is near
	e.ring_f = move_toward(e.ring_f, clampf(float(player.ring_idx), e.lo, e.hi),
		e.speed / PathGen.SEG * delta)
	var r0 := int(e.ring_f)
	var r1 := mini(r0 + 1, int(e.hi))
	var w: float = e.ring_f - r0
	node.position = _wall_point(path.rings[r0], e.side, e.wall_v).lerp(
		_wall_point(path.rings[r1], e.side, e.wall_v), w)
	e.ring = r0 if w < 0.5 else r1
	e.facing = (path.rings[e.ring].r as Vector3) * -e.side   # muzzle across the tunnel
	var clock := delta * GameState.enemy_tempo()
	if e.burst > 0:
		e.burst_t -= clock
		if e.burst_t <= 0.0:
			e.burst -= 1
			e.burst_t = CRAWL_BURST_GAP
			var aim: Vector3 = player.position \
				+ player.forward() * (player.speed * dist / 24.0 * 0.35) - node.position
			enemy_fired.emit(node.position, aim.normalized() * 24.0, SHOT_DMG, 1.7, false, node)
	else:
		e.fire_t -= clock
		if e.fire_t <= 0.0 and dist < 95.0:
			e.fire_t = e.fire * randf_range(0.9, 1.3)
			e.burst = int(TYPES[e.type].get("burst", 3))
			e.burst_t = 0.0
	return false


## v4b WARDEN: a gunship behind a front shield. A light shot that meets the shield is
## turned aside (see hit_enemy). It swings round to face you only slowly, so come at
## it from the side, punch through with BOLT, or let a missile's blast reach round it.
func _update_warden(k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 130.0:
		return false
	var dir := to_player / maxf(dist, 0.001)
	if dist > 55.0:
		node.position += dir * (e.speed * delta)
	elif dist < 30.0:
		node.position -= dir * (e.speed * 0.7 * delta)
	node.position.y += sin(e.bob_p) * delta * 1.0
	_turn(e, to_player, e.turn, delta)   # slow: a flanking ship gets ahead of the shield
	e.ring = path.nearest_ring(node.position, e.ring)
	node.position = path.clamp_to_ring(node.position, e.ring, 2.6)
	e.fire_t -= delta * GameState.enemy_tempo()
	if e.fire_t <= 0.0 and dist < 95.0:
		e.fire_t = e.fire * randf_range(0.85, 1.2)
		# twin guns at the shield's rim, both on the lead point
		var aim: Vector3 = (player.position + player.forward() * (player.speed * dist / 26.0 * 0.4)
			- node.position).normalized()
		var rim := aim.cross(Vector3.UP).normalized() * 1.4
		enemy_fired.emit(node.position + rim, aim * 26.0, SHOT_DMG, 1.7, false, node)
		enemy_fired.emit(node.position - rim, aim * 26.0, SHOT_DMG, 1.7, false, node)
	return _collide(k, dist)


## v4b CARRIER: a slow capital ship. It turns broadside, so its bays face you, and
## launches a drone every LAUNCH_T (CARRIER_LIVE of its own at most) until it has taken
## BAY_HP of damage: then its bays blow (see _hurt) and it can only shoot back.
func _update_carrier(_k: int, e: Dictionary, delta: float) -> bool:
	var node: Sprite3D = e.node
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > 140.0:
		return false
	var dir := to_player / maxf(dist, 0.001)
	if dist > 80.0:
		node.position += dir * (e.speed * delta)
	elif dist < 50.0:
		node.position -= dir * (e.speed * delta)
	node.position.y += sin(e.bob_p) * delta * 0.6
	_turn(e, dir.cross(Vector3.UP) * e.side, 0.9, delta)   # broadside on
	e.ring = path.nearest_ring(node.position, e.ring)
	node.position = path.clamp_to_ring(node.position, e.ring, 4.0)
	var clock := delta * GameState.enemy_tempo()
	if e.bays:
		e.launch_t -= clock
		if e.launch_t <= 0.0:
			e.launch_t = LAUNCH_T
			if _count_tagged("parent", node) < CARRIER_LIVE:
				var before := enemies.size()
				spawn(e.ring, -1, "drone")
				if enemies.size() > before:
					var d: Dictionary = enemies.back()
					d["parent"] = node
					d.node.position = path.clamp_to_ring(node.position + dir * 3.0, e.ring, 2.0)
					d.fire_t = 1.0 + randf()
					exploded.emit(d.node.position, false)   # the launch puff
	e.fire_t -= clock
	if e.fire_t <= 0.0 and dist < 100.0:
		e.fire_t = e.fire * randf_range(0.9, 1.2)
		enemy_fired.emit(node.position, dir * 22.0, SHOT_DMG + 2.0, 2.2, false, node)
	if dist < 6.0 and player.wall_hurt_t <= 0.0:
		# a capital ship doesn't break on your hull: you bounce off it
		player.wall_hurt_t = 0.45
		player.take_damage(CONTACT_DMG, "COLLISION")
		player.bounce += dir * 16.0
	return false


## Flown into, a small ship scrapes the hull (contact damage) and is spent.
func _collide(k: int, dist: float) -> bool:
	if dist < 4.5 and player.wall_hurt_t <= 0.0:
		player.wall_hurt_t = 0.45
		player.take_damage(CONTACT_DMG, "COLLISION")
		_kill(k, false)
		return true
	return false


## A straight stretch around ring ri: where a laid mine can't be flown around.
func _straight(ri: int) -> bool:
	var last := path.rings.size() - 1
	return (path.rings[maxi(ri - 2, 0)].d as Vector3).dot(path.rings[mini(ri + 2, last)].d) > 0.98


## How many live enemies carry `node` under `key` (a layer's mines).
func _count_tagged(key: String, node: Node3D) -> int:
	var n := 0
	for o in enemies:
		if o.get(key) == node:
			n += 1
	return n


## v4b: last frame's splitter deaths hatch here, each brood fanned out around where
## its parent burst, outside any walk over `enemies`. Their slots were reserved under
## ENEMY_CAP when the parent died, so each one spawns now and frees its reservation.
func _hatch_splits() -> void:
	var splits := _pending_splits.duplicate()
	_pending_splits.clear()
	for s: Dictionary in splits:
		for i in int(s.n):
			_reserved -= 1
			spawn(s.ring, s.arena_id, s.type, true)
			var c: Dictionary = enemies.back()
			var a := TAU * i / float(s.n)
			c.node.position = path.clamp_to_ring((s.pos as Vector3)
				+ Vector3(cos(a) * 2.5, sin(a * 2.0) * 0.8, sin(a) * 2.5), s.ring, 2.0)
			c.fire_t = 1.2 + randf()   # a beat before the brood opens fire
	_reserved = maxi(_reserved, 0)


## 3.0: basis looking from `origin` at the ship — [forward, side, up].
func _aim_basis(origin: Vector3) -> Array[Vector3]:
	var fwd := (player.position - origin).normalized()
	var side := fwd.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = Vector3.RIGHT
	side = side.normalized()
	return [fwd, side, side.cross(fwd)]


## 3.0: an expanding ring of `count` bolts flying at the ship. They leave on a
## small circle (from angle a0) and spread as they travel, so the ring arrives
## wide with a hole in the middle.
func _ring_burst(origin: Vector3, count: int, a0: float, speed: float, spread: float,
		dmg := SHOT_DMG, src: Node3D = null) -> void:
	var b := _aim_basis(origin)
	for i in count:
		var a := a0 + TAU * i / float(count)
		var radial: Vector3 = b[1] * cos(a) + b[2] * sin(a)
		enemy_fired.emit(origin + radial * 1.2, b[0] * speed + radial * spread, dmg, 1.6, false,
			src)


## 3.0: one step of a spiral hose — `arms` emitters wheel around the source and
## each fires straight at the ship's current position, so standing still gets
## you hit and moving keeps you clear (the opposite lesson to the rings).
func _spiral_shot(origin: Vector3, a: float, arms: int, speed: float) -> void:
	var b := _aim_basis(origin)
	for i in arms:
		var aa := a + TAU * i / float(arms)
		var from: Vector3 = origin + (b[1] * cos(aa) + b[2] * sin(aa)) * 7.0
		enemy_fired.emit(from, (player.position - from).normalized() * speed, SHOT_DMG, 1.7,
			false, null)


## Phase J boss brain: three HP-gated phases — aimed heavy shots, then +spread
## volleys below 66%, then frenzy + drone summons below 33%. Hovers around its
## anchor with a widening strafe, keeps a 35-70 u standoff, and rams for heavy
## contact damage without dying (unlike drones).
func _update_boss(e: Dictionary, delta: float) -> void:
	var node: Sprite3D = e.node
	var phase := 1
	var frac: float = e.hp / float(e.max_hp)
	if frac <= 0.33:
		phase = 3
	elif frac <= 0.66:
		phase = 2
	if phase != e.phase:
		e.phase = phase
		boss_phase.emit(phase)
	var to_player: Vector3 = player.position - node.position
	var dist := to_player.length()
	if dist > BOSS_ENGAGE:
		return  # dormant until the player is in the room
	var speed_mul := 1.0 if phase == 1 else (1.3 if phase == 2 else 1.7)
	# --- movement: strafe around the anchor, close past 70 u, back off inside 35 ---
	e.weave_p += delta * 0.9 * speed_mul
	var ring: Dictionary = path.rings[e.ring]
	var target: Vector3 = e.anchor \
		+ ring.r * (sin(e.weave_p) * 14.0) + ring.u * (sin(e.weave_p * 0.63) * 6.0)
	if dist > 70.0:
		target = player.position
	elif dist < 35.0:
		target = node.position - to_player
	var dir := target - node.position
	if dir.length() > 0.5:
		node.position += dir.normalized() * (e.speed * speed_mul * delta)
	# 3.0: keep its face on the player, swinging a little with the strafe
	_turn(e, to_player + dir * 0.35, 1.8, delta)
	node.position.y += sin(e.bob_p) * delta * 1.2
	e.ring = maxi(path.nearest_ring(node.position, e.ring), e.home_ring - 8)
	node.position = path.clamp_to_ring(node.position, e.ring, e.size * 0.5)
	# --- attacks: 3.0 gives every boss its own pattern (LevelDef.boss_model) ---
	# Step 3: every pattern clock (aimed shots, volleys, summons, mines, spiral)
	# runs on the difficulty tempo; movement above stays on real time
	var clock := delta * GameState.enemy_tempo()
	match e.get("model", "sentinel"):
		"brood":
			_brood_attacks(e, phase, dist, clock)
		"maw":
			_maw_attacks(e, phase, dist, clock)
		_:
			_sentinel_attacks(e, phase, dist, clock)
	# --- ram ---
	if dist < e.size * 0.5 + 2.0 and player.wall_hurt_t <= 0.0:
		player.wall_hurt_t = 0.45
		player.take_damage(BOSS_CONTACT_DMG, "COLLISION")
		player.bounce += to_player.normalized() * 22.0


## Aimed heavy shot with target lead — every boss's bread and butter. `slow`
## stretches the interval once a pattern has other things to throw.
func _boss_aimed(e: Dictionary, dist: float, delta: float, slow: float) -> void:
	e.fire_t -= delta
	if e.fire_t <= 0.0 and dist < BOSS_FIRE_RANGE:
		e.fire_t = e.fire * 0.9 * slow
		var node: Sprite3D = e.node
		var aim: Vector3 = player.position \
			+ player.forward() * (player.speed * dist / 32.0 * 0.4) - node.position
		enemy_fired.emit(node.position, aim.normalized() * 32.0, BOSS_SHOT_DMG, 2.4, false,
			null)


## DOCK SENTINEL (L3), the gatekeeper — the Phase J pattern: aimed heavy shots,
## spread volleys from 66%, escort drones from 33%.
func _sentinel_attacks(e: Dictionary, phase: int, dist: float, delta: float) -> void:
	_boss_aimed(e, dist, delta, 1.4 if phase >= 2 else 1.0)
	if phase >= 2:
		e.volley_t -= delta
		if e.volley_t <= 0.0 and dist < BOSS_FIRE_RANGE:
			e.volley_t = 3.2 if phase == 2 else 2.2
			_boss_volley(e.node.position, 5 if phase == 2 else 7)
	if phase == 3:
		e.summon_t -= delta
		if e.summon_t <= 0.0:
			e.summon_t = 6.0
			_boss_summon(e, "drone", 2)


## BROOD MOTHER (L6) fights with her young: STINGER hatchlings from the start
## (more, and sooner, as she weakens), proximity MINES laid across the room from
## 66%, and a short volley in the last phase. Her own mines hurt her too.
func _brood_attacks(e: Dictionary, phase: int, dist: float, delta: float) -> void:
	_boss_aimed(e, dist, delta, 1.5)
	e.summon_t -= delta
	if e.summon_t <= 0.0:
		e.summon_t = 7.0 if phase == 1 else (5.5 if phase == 2 else 4.0)
		_boss_summon(e, "stinger", 1 if phase == 1 else 2)
	if phase >= 2:
		e.lay_t -= delta
		if e.lay_t <= 0.0:
			e.lay_t = 4.5 if phase == 2 else 3.5
			_boss_lay_mine(e)
	if phase == 3:
		e.volley_t -= delta
		if e.volley_t <= 0.0 and dist < BOSS_FIRE_RANGE:
			e.volley_t = 3.0
			_boss_volley(e.node.position, 5)


## THE RIFT MAW (L9), the finale, is a bullet storm: ring bursts from the start
## (hold the centre), a wheeling spiral hose from 66% that runs for 2.6 s then
## rests for 2.2 s (keep moving), and below 33% the spiral doubles and SPINNERS
## crawl out of the rift.
func _maw_attacks(e: Dictionary, phase: int, dist: float, delta: float) -> void:
	var node: Sprite3D = e.node
	_boss_aimed(e, dist, delta, 1.2 if phase == 1 else 1.8)
	e.volley_t -= delta
	if e.volley_t <= 0.0 and dist < BOSS_FIRE_RANGE:
		e.volley_t = 3.6 if phase == 1 else 4.4
		_ring_burst(node.position, 10, e.spin_a, 20.0, 5.0, BOSS_SHOT_DMG * 0.8)
		e.spin_a += PI / 10.0
	if phase >= 2:
		e.spiral_t -= delta
		if e.spiral_t <= -2.2:
			e.spiral_t = 2.6
		if e.spiral_t > 0.0 and dist < BOSS_FIRE_RANGE:
			e.spiral_cd -= delta
			if e.spiral_cd <= 0.0:
				e.spiral_cd = 0.11
				e.spiral_a += 0.55
				_spiral_shot(node.position, e.spiral_a, 2 if phase == 3 else 1, 24.0)
	if phase == 3:
		e.summon_t -= delta
		if e.summon_t <= 0.0:
			e.summon_t = 8.0
			_boss_summon(e, "spinner", 1)


## Horizontal fan of shots centered on the line to the player (±0.35 rad).
func _boss_volley(origin: Vector3, count: int) -> void:
	var to_player := (player.position - origin).normalized()
	for i in count:
		var ang := -0.35 + i * (0.7 / float(count - 1))
		enemy_fired.emit(origin, to_player.rotated(Vector3.UP, ang) * 30.0, SHOT_DMG, 1.7, false,
			null)


## The boss ejects escorts of `type_id` — capped at MAX_SUMMONS live so the room
## never floods. spawn() may refuse (ENEMY_CAP), so tag only entries that
## actually appeared.
func _boss_summon(e: Dictionary, type_id: String, count: int) -> void:
	var live := 0
	for en in enemies:
		if en.get("summoned", false):
			live += 1
	var wanted := mini(count, MAX_SUMMONS - live)
	if wanted <= 0:
		return
	for i in wanted:
		var before := enemies.size()
		spawn(e.ring, -1, type_id)
		if enemies.size() > before:
			var d: Dictionary = enemies[enemies.size() - 1]
			d["summoned"] = true
			d.node.position = e.node.position + Vector3(
				randf_range(-6.0, 6.0), randf_range(-4.0, 4.0), randf_range(-6.0, 6.0))
	exploded.emit(e.node.position, false)  # ejection puff


## Brood mother, phase 2+: drop a mine where she hovers (capped, so the room
## never turns into a minefield). They creep toward the ship like any mine.
func _boss_lay_mine(e: Dictionary) -> void:
	var live := 0
	for en in enemies:
		if en.get("laid", false):
			live += 1
	if live >= MAX_LAID_MINES:
		return
	var before := enemies.size()
	spawn(e.ring, -1, "mine")
	if enemies.size() > before:
		var m: Dictionary = enemies[enemies.size() - 1]
		m["laid"] = true
		m.node.position = path.clamp_to_ring(e.node.position + Vector3(
			randf_range(-5.0, 5.0), randf_range(-3.0, 3.0), randf_range(-5.0, 5.0)), e.ring, 2.0)


## Damage every enemy within radius of pos (MISSILE splash). Returns kills.
func splash_damage(pos: Vector3, radius: float, dmg: int) -> int:
	var kills := 0
	var r2 := radius * radius
	for k in range(enemies.size() - 1, -1, -1):
		if enemies[k].node.position.distance_squared_to(pos) <= r2:
			if _hurt(k, dmg):
				kills += 1
	return kills


## Direct hit. Returns true if the enemy died. v4b: `from_dir` is the shot's travel
## direction (zero for a blast or the plasma bomb). A shielded enemy turns aside a
## light hit (under WARDEN_BLOCK) that meets it inside its front arc: no damage, just
## blue sparks and a ping (`deflected`). So NEUTRON and SCATTER bounce off a warden's
## nose, while BOLT, a shot from the flank and any blast land.
func hit_enemy(index: int, dmg: int, from_dir := Vector3.ZERO) -> bool:
	var e: Dictionary = enemies[index]
	if e.get("shielded", false) and dmg < WARDEN_BLOCK:
		var flat := Vector3(from_dir.x, 0.0, from_dir.z)
		if flat.length_squared() > 0.0001:
			flat = flat.normalized()
			if (e.facing as Vector3).dot(-flat) > WARDEN_ARC_COS:
				deflected.emit((e.node as Node3D).position - flat * 1.6)
				return false
	return _hurt(index, dmg)


## Closest living enemy's sprite node to `from`, or null if none — the lock target
## for heat-seeking missiles (I2b). Re-queried each frame so a missile retargets if
## its locked enemy dies.
func nearest_enemy(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for e in enemies:
		if e.get("cloaked", false):
			continue   # v4b: nothing locks onto a cloaked wraith
		var d: float = e.node.position.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = e.node
	return best


## V2.2 L2b: live-enemy census around a point — the music intensity feed.
func near_count(from: Vector3, r: float) -> int:
	var r2 := r * r
	var n := 0
	for e in enemies:
		if e.node.position.distance_squared_to(from) < r2:
			n += 1
	return n


func _hurt(index: int, dmg: int) -> bool:
	var e: Dictionary = enemies[index]
	e.hp -= dmg
	e.flash_t = 0.09
	if e.hp <= 0:
		_kill(index, true)
		return true
	if e.get("bays", false) and e.max_hp - e.hp >= BAY_HP:
		# v4b: a carrier's first BAY_HP of damage blows its launch bays
		e.bays = false
		exploded.emit((e.node as Node3D).position, true)
		announced.emit("CARRIER BAYS DOWN")
	return false


func _kill(index: int, scored: bool) -> void:
	var e: Dictionary = enemies[index]
	if e.get("is_boss", false):
		# triple offset blast around the big boom; game.gd wakes the exit ring
		exploded.emit(e.node.position, true)
		for i in 3:
			exploded.emit(e.node.position + Vector3(
				randf_range(-8.0, 8.0), randf_range(-5.0, 5.0), randf_range(-8.0, 8.0)), false)
		boss = {}
	else:
		var is_mine: bool = e.get("type", "") == "mine"
		exploded.emit(e.node.position, is_mine)   # 3.0: mines go up with a shock ring
		if is_mine:
			_pending_blasts.append(e.node.position)   # chains next frame (see top of update)
	if e.get("type", "") == "turret":
		turret_destroyed.emit(e.node.position)   # V2.0: chains nearby fuel cells
	elif e.behavior == "lay" or e.behavior == "carry":
		# v4b: its node goes back to the pool, so its mines (or its drones) stop
		# counting as its own
		var tag := "laid_by" if e.behavior == "lay" else "parent"
		for o in enemies:
			if o.get(tag) == e.node:
				o.erase(tag)
	var tdef: Dictionary = TYPES.get(e.get("type", ""), {})
	# v4b: a splitter bursts into its brood next frame (see _hatch_splits). The brood
	# counts toward ENEMY_CAP: only the slots free now (this one leaves the list below)
	# are reserved, so nothing spawned before the hatch can take them. Inside a locked
	# arena the brood joins the room's tally now, before this kill counts, so the
	# bulkhead can't open on the splitter's own death
	var split := int(tdef.get("split", 0))
	if split > 0:
		var n := clampi(ENEMY_CAP - (enemies.size() - 1) - _reserved, 0, split)
		if n > 0:
			_reserved += n
			_pending_splits.append({"pos": e.node.position, "ring": e.ring,
				"arena_id": e.arena_id, "type": tdef.split_into, "n": n})
			if e.arena_id >= 0:
				arena_reinforced.emit(e.arena_id, n)
	# V2.2 L1: debris burst — chunk count scales with the kill's heft (v4b: TYPES.gibs)
	var gcount := 20 if e.get("is_boss", false) else int(tdef.get("gibs", 6))
	# (v4b: a heavy's debris is its base type's, in its tint)
	var gtint: Color = e.node.modulate if e.get("is_boss", false) \
		else GIB_TINTS.get(base_type(e.get("type", "")), Color(0.6, 0.6, 0.65)) \
			* (e.get("tint", Color.WHITE) as Color)
	gibs_requested.emit(e.node.position,
		(e.node.position - player.position).normalized() * 4.0, e.ring, gcount, gtint)
	if gcount >= 12:   # V2.2 L2d: hulk/boss kills punch the music down for a beat
		AudioSys.duck(140 if e.get("is_boss", false) else 100)
	# Phase J feedback: nearby kills thump the camera a little
	if e.node.position.distance_squared_to(player.position) < 2500.0:
		player.shake = minf(0.6, player.shake + 0.12)
	if scored:
		GameState.register_kill(int(e.score))   # streak-multiplied (Phase J)
		var type_id: String = e.get("type", "")
		# V2.2 L3b: salvage — guaranteed from heavies, a 30% roll from the rest
		# (3.0: spinners count as heavies; mines carry nothing but their score).
		# v4b: the sure amounts live in TYPES.salvage
		var salvage := int(tdef.get("salvage", 0))
		if e.get("is_boss", false):
			drop_spawned.emit(e.node.position, e.ring, "salvage", 50)
		elif salvage > 0:
			drop_spawned.emit(e.node.position, e.ring, "salvage", salvage)
		elif salvage == 0 and randf() < 0.30:
			drop_spawned.emit(e.node.position, e.ring, "salvage", 5)
		# Phase J drop roll — one chance per scored kill (never the boss itself;
		# its reward is the exit ring). Tanky types (TYPES.drop_mult) drop more often.
		if not e.get("is_boss", false) and type_id != "mine":
			var mult := float(tdef.get("drop_mult", 1.0))
			var roll := randf()
			if roll < 0.12 * mult:
				drop_spawned.emit(e.node.position, e.ring, "shield", 0)
			elif roll < 0.22 * mult:
				drop_spawned.emit(e.node.position, e.ring, "energy", 0)
			elif roll < 0.30 * mult:
				drop_spawned.emit(e.node.position, e.ring, "missile", 0)
			elif roll < 0.34 * mult:
				drop_spawned.emit(e.node.position, e.ring, "bomb", 0)   # V2.0: rare
			# 3.0: timed power-ups ride a separate roll, so they can come as a bonus
			if randf() < POWER_DROP.get(type_id, POWER_DROP_BASE):
				drop_spawned.emit(e.node.position + Vector3.UP * 1.5, e.ring, random_power(), 0)
	enemy_killed.emit(e.arena_id)
	_release_node(e.node)
	enemies.remove_at(index)
	if e.get("is_boss", false):
		boss_killed.emit()
