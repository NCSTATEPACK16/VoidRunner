extends RefCounted
## Rail flying for the headless probes (v4c A2): preload it, call the statics.
##   const RailAssist := preload("res://tests/rail_assist.gd")
##   RailAssist.step(game, f)        # once per step, before game._process(dt)
## It stands in for a pilot who does everything a level asks on the way down the tunnel:
##   - steer: face the centreline a few rings ahead, so a drift off-centre always closes
##     and the ship meets bends, bulkheads and the exit portal square on;
##   - guards: clear the regular enemies near the ship so locked arenas open, and wake and
##     wear down a mini-boss through the real hit path (miniboss_killed and the room's tally
##     fire as in play). Main bosses are left alone unless `boss_hits` asks for them;
##   - the hub keycard: once the ship is at the hub room, hop it to the key and collect the
##     card through the real pickup path (GameState.has_key is never set by hand);
##   - objectives: blow generators, reactors and anchors as the ship passes, and gather
##     pods just ahead (each only if the build has them: every hook is has_method-guarded).
## The ship never flies the side branches: a "hop" puts it on the target for one pickup
## update and then puts it back exactly where it was.

const CLEAR_EVERY := 30        ## steps between clears of the regular enemies...
const CLEAR_R := 60.0          ## ...within this far of the ship...
const CLEAR_RINGS := 15        ## ...and this many rings (a looping tunnel passes rooms
                               ## close by in space that are far ahead along it)
const BOSS_HIT_EVERY := 60     ## steps between hits on an engaged (mini-)boss
const BOSS_HIT := 0.12         ## each hit takes this share of its max HP
const OBJECTIVE_RINGS := 3     ## an objective goes down once the ship is this close (rings)
const POD_RINGS := 2           ## a pod is fetched once it is this close ahead (rings)


## Everything for one step: steer, guards, the hub key, the objectives.
## `boss_hits` also walks a main boss down through its phases (the soak does; a perf
## run leaves bosses to the player).
static func step(game: Node3D, frame: int, boss_hits := false) -> void:
	steer(game)
	clear_guards(game, frame)
	hit_boss(game, frame, boss_hits)
	fetch_key(game)
	do_objectives(game)


## Face the centreline three rings ahead (never past the main run: a hub's branches are
## appended after it; the endless run has no such cap).
static func steer(game: Node3D) -> void:
	var path: PathGen = game.path
	var last: int = path.rings.size() - 1 if path.is_endless else path.main_ring_count - 1
	var ahead: Vector3 = path.rings[mini(game.player.ring_idx + 3, last)].p
	var to: Vector3 = (ahead - game.player.position).normalized()
	game.player.yaw = atan2(-to.x, -to.z)
	game.player.pitch = clampf(asin(clampf(to.y, -1.0, 1.0)), -0.6, 0.6)


## Every CLEAR_EVERY steps, kill the regular enemies near the ship (bosses and
## mini-bosses are not regular: see hit_boss).
static func clear_guards(game: Node3D, frame: int) -> void:
	if frame % CLEAR_EVERY != 0:
		return
	var em: EnemyManager = game.enemy_mgr
	for k in range(em.enemies.size() - 1, -1, -1):
		var e: Dictionary = em.enemies[k]
		if not e.get("is_boss", false) \
				and absi(int(e.ring) - game.player.ring_idx) <= CLEAR_RINGS \
				and e.node.position.distance_to(game.player.position) < CLEAR_R:
			em.hit_enemy(k, 999)


## Wear the engaged boss down by BOSS_HIT of its max HP every BOSS_HIT_EVERY steps, so it
## passes through its phases and dies by the real kill path. A mini-boss is always fair
## game (its room's bulkhead needs it dead); a main boss only when `main_too`.
static func hit_boss(game: Node3D, frame: int, main_too := false) -> void:
	var em: EnemyManager = game.enemy_mgr
	if frame % BOSS_HIT_EVERY != 0 or not em.boss_visible():
		return
	if not main_too and not em.boss.get("miniboss", false):
		return
	if em.boss.node.position.distance_to(game.player.position) >= EnemyManager.BOSS_ENGAGE:
		return
	var idx: int = em.enemies.find(em.boss)
	if idx >= 0:
		em.hit_enemy(idx, maxi(1, int(em.boss.max_hp * BOSS_HIT)))


## At the hub room with no keycard yet: hop to the key, let the pickup manager collect it,
## hop back.
static func fetch_key(game: Node3D) -> void:
	var hub = game.get("_hub_arena")
	if GameState.has_key or hub == null or int(hub) < 0:
		return
	var arena: Dictionary = game.path.arenas[int(hub)]
	if game.player.ring_idx < int(arena.start) - 2:
		return
	var key_at: Vector3 = game.spur_mgr.key_pos()
	if key_at == Vector3.INF:
		return
	hop_collect(game, key_at)


## Put the ship at `pos` for one zero-length pickup update, then back where it was.
static func hop_collect(game: Node3D, pos: Vector3) -> void:
	var p = game.player
	var was_pos: Vector3 = p.position
	var was_ring: int = p.ring_idx
	p.position = pos
	game.pickup_mgr.update_pickups(0.0)
	p.position = was_pos
	p.ring_idx = was_ring


## Blow each objective prop once the ship is within OBJECTIVE_RINGS of it, and fetch any
## pod within POD_RINGS ahead. Skips whatever this build doesn't have yet.
static func do_objectives(game: Node3D) -> void:
	var reach := PathGen.SEG
	if game.prop_mgr.has_method("objective_positions"):
		for o in game.prop_mgr.objective_positions():
			if o.pos.distance_to(game.player.position) > reach * OBJECTIVE_RINGS:
				continue
			var props: Array = game.prop_mgr.props
			for i in props.size():
				if props[i].id == o.id and props[i].kind == o.kind:
					game.prop_mgr.damage_prop(i, 99999.0)
					break
	if game.pickup_mgr.has_method("live_stations"):
		for s in game.pickup_mgr.live_stations("pod"):
			var to: Vector3 = s.pos - game.player.position
			if to.length() < reach * POD_RINGS:
				hop_collect(game, s.pos)
