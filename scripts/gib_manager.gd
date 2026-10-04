class_name GibManager
extends Node3D
## V2.2 L1: pooled debris chunks on kills. Perf contract: hard 48-chunk pool (oldest
## recycled), zero steady-state allocations, and wall collision reuses
## PathGen.clamp_to_ring — a displaced gib reflects and damps, so debris visibly
## ricochets down the tunnel for near-zero cost. game.gd calls update_gibs() only
## while PLAYING, so pause/menu freeze the sim for free. Billboards can't spin, so
## tumble is 4 pre-rotated frames per chunk shape, cycled on a per-gib clock.
## v4 perf groundwork: every chunk is one instance of a single FxBatch (one draw call
## for all the debris, was one per chunk), and a fresh chunk glows yellow-hot, cooling
## down the FIRE ramp into its hull tint over COOL_T.

const POOL := 48
const GRAVITY := 14.0
const DAMP := 0.45
const SIZE := 0.9
const COOL_T := 0.6

var path: PathGen

var _g: Array[Dictionary] = []
var _order: Array[int] = []       # spawn order for oldest-first recycling
var _fx: FxBatch                  # cells: shape * 4 + quarter-turn

# L1 hit-stop: Engine.time_scale crush with a REAL-time restore (_process ticks
# every frame regardless of time_scale or game state, so restore can't be missed).
var _stop_restore_ms := 0
var _stop_cooldown_ms := 0


func _ready() -> void:
	var shapes := SpriteGen.gib_frames()
	var cells: Array = []
	for tex in shapes:
		cells.append(tex)
		var img: Image = tex.get_image()
		for r in 3:
			img = img.duplicate()
			img.rotate_90(CLOCKWISE)
			cells.append(ImageTexture.create_from_image(img))
	_fx = FxBatch.new(cells, POOL, true)
	add_child(_fx)
	for i in POOL:
		_g.append({"on": false, "pos": Vector3.ZERO, "vel": Vector3.ZERO, "tumble": 6.0,
			"life": 1.0, "t": 0.0, "ring": 0, "shape": i % shapes.size(),
			"tint": Color.WHITE, "scale": 1.0})


func clear_all() -> void:
	for i in POOL:
		_g[i].on = false
	_order.clear()
	sync_batch()


func active_count() -> int:
	var n := 0
	for st in _g:
		if st.on:
			n += 1
	return n


## Freeze-frame: kill punctuation. 150 ms cooldown keeps multi-kills punchy, not
## stuttery; `force` lets the boss-death slow-mo override a burst's own stop.
func hit_stop(ms: int, scale := 0.08, force := false) -> void:
	var now := Time.get_ticks_msec()
	if not force and now < _stop_cooldown_ms:
		return
	_stop_cooldown_ms = now + ms + 150
	_stop_restore_ms = now + ms
	Engine.time_scale = scale


func _process(_delta: float) -> void:
	if _stop_restore_ms > 0 and Time.get_ticks_msec() >= _stop_restore_ms:
		_stop_restore_ms = 0
		Engine.time_scale = GameState.time_scale_base   # Step 3: GAME SPEED assist


## Matches EnemyManager.gibs_requested, so game.gd connects it directly.
func burst(pos: Vector3, base_vel: Vector3, ring: int, count: int, tint: Color) -> void:
	hit_stop(90 if count >= 20 else (50 if count >= 12 else 30))   # class rides the count
	for k in count:
		var slot := _take_slot()
		var st: Dictionary = _g[slot]
		var dir := Vector3(randf() - 0.5, randf() - 0.3, randf() - 0.5).normalized()
		st.on = true
		st.pos = pos
		st.vel = base_vel * 0.4 + dir * (7.0 + randf() * 9.0)
		st.tumble = 4.0 + randf() * 8.0   # texture-frames per second
		st.life = 1.6 + randf() * 0.8
		st.t = 0.0
		st.ring = ring
		st.tint = tint
		st.scale = 1.0


func _take_slot() -> int:
	for i in POOL:
		if not _g[i].on:
			_order.append(i)
			return i
	var oldest: int = _order.pop_front()   # cap hit: recycle the oldest chunk
	_order.append(oldest)
	return oldest


func update_gibs(delta: float) -> void:
	_sim(delta)


func _sim(dt: float) -> void:
	for i in POOL:
		var st: Dictionary = _g[i]
		if not st.on:
			continue
		st.t += dt
		if st.t >= st.life:
			st.on = false
			_order.erase(i)
			continue
		st.vel.y -= GRAVITY * dt
		var pos: Vector3 = st.pos + st.vel * dt
		if path != null:
			st.ring = path.nearest_ring(pos, st.ring)
			var clamped: Vector3 = path.clamp_to_ring(pos, st.ring, 0.5)
			if clamped.distance_squared_to(pos) > 0.0001:
				st.vel = st.vel.bounce((clamped - pos).normalized()) * DAMP
				pos = clamped
				if randf() < 0.3:   # L1f: debris taps the wall, quietly
					AudioSys.gib_tick()
		st.pos = pos
		var frac: float = st.t / st.life
		if frac > 0.7:
			st.scale = clampf((1.0 - frac) / 0.3, 0.05, 1.0)


## v4: draw every live chunk through the one batch. game.gd calls this once a frame,
## after everything that can spawn debris has run.
func sync_batch() -> void:
	_fx.begin()
	for st in _g:
		if st.on:
			_fx.add(st.pos, SIZE * st.scale, st.shape * 4 + int(st.t * st.tumble) % 4,
				heat_color(st.tint, st.t))
	_fx.end()


## Warm-up: one chunk in view, so the batch's shader variant compiles behind the
## briefing. The next sync_batch() clears it.
func warmup_batch(at: Vector3) -> void:
	_fx.begin()
	_fx.add(at, 0.7, 0, heat_color(Color.WHITE, 0.0))
	_fx.end()


## v4 hot debris: yellow-hot at t = 0, then down the FIRE ramp (orange, then ember red)
## while it blends into the hull tint, which it reaches at COOL_T. The ramp's white top
## is left out: on grey-shaded chunks it read as pale cream rather than hot metal.
static func heat_color(tint: Color, t: float) -> Color:
	var heat := clampf(1.0 - t / COOL_T, 0.0, 1.0)
	if heat <= 0.0:
		return tint
	return tint.lerp(Palette.ramp_f(Palette.FIRE, 0.3 + 0.55 * heat), minf(1.0, heat * 2.0))
