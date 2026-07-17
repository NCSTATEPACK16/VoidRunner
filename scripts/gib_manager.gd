class_name GibManager
extends Node3D
## V2.2 L1: pooled sprite debris chunks on kills. Perf contract: hard 48-node pool
## (oldest recycled), zero steady-state allocations, and wall collision reuses
## PathGen.clamp_to_ring — a displaced gib reflects and damps, so debris visibly
## ricochets down the tunnel for near-zero cost. game.gd calls update_gibs() only
## while PLAYING, so pause/menu freeze the sim for free. Billboards can't spin, so
## tumble is 4 pre-rotated frames per chunk shape, cycled on a per-gib clock.

const POOL := 48
const GRAVITY := 14.0
const DAMP := 0.45

var path: PathGen

var _nodes: Array[Sprite3D] = []
var _g: Array[Dictionary] = []
var _order: Array[int] = []       # spawn order for oldest-first recycling
var _frames: Array = []           # [shape][rot 0..3] -> ImageTexture

# L1 hit-stop: Engine.time_scale crush with a REAL-time restore (_process ticks
# every frame regardless of time_scale or game state, so restore can't be missed).
var _stop_restore_ms := 0
var _stop_cooldown_ms := 0


func _ready() -> void:
	for tex in SpriteGen.gib_frames():
		var rots: Array[ImageTexture] = [tex]
		var img: Image = tex.get_image()
		for r in 3:
			img = img.duplicate()
			img.rotate_90(CLOCKWISE)
			rots.append(ImageTexture.create_from_image(img))
		_frames.append(rots)
	for i in POOL:
		var s := SpriteGen.make_sprite(_frames[i % _frames.size()][0], 0.9)
		s.visible = false
		add_child(s)
		_nodes.append(s)
		_g.append({"on": false, "vel": Vector3.ZERO, "tumble": 6.0,
			"life": 1.0, "t": 0.0, "ring": 0, "shape": i % _frames.size()})


func clear_all() -> void:
	for i in POOL:
		_g[i].on = false
		_nodes[i].visible = false
	_order.clear()


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
		Engine.time_scale = 1.0


## Matches EnemyManager.gibs_requested, so game.gd connects it directly.
func burst(pos: Vector3, base_vel: Vector3, ring: int, count: int, tint: Color) -> void:
	hit_stop(90 if count >= 20 else (50 if count >= 12 else 30))   # class rides the count
	for k in count:
		var slot := _take_slot()
		var st: Dictionary = _g[slot]
		var dir := Vector3(randf() - 0.5, randf() - 0.3, randf() - 0.5).normalized()
		st.on = true
		st.vel = base_vel * 0.4 + dir * (7.0 + randf() * 9.0)
		st.tumble = 4.0 + randf() * 8.0   # texture-frames per second
		st.life = 1.6 + randf() * 0.8
		st.t = 0.0
		st.ring = ring
		var n: Sprite3D = _nodes[slot]
		n.position = pos
		n.modulate = tint
		n.scale = Vector3.ONE
		n.visible = true


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
			_nodes[i].visible = false
			_order.erase(i)
			continue
		st.vel.y -= GRAVITY * dt
		var n: Sprite3D = _nodes[i]
		var pos: Vector3 = n.position + st.vel * dt
		if path != null:
			st.ring = path.nearest_ring(pos, st.ring)
			var clamped: Vector3 = path.clamp_to_ring(pos, st.ring, 0.5)
			if clamped.distance_squared_to(pos) > 0.0001:
				st.vel = st.vel.bounce((clamped - pos).normalized()) * DAMP
				pos = clamped
				if randf() < 0.3:   # L1f: debris taps the wall, quietly
					AudioSys.gib_tick()
		n.position = pos
		n.texture = _frames[st.shape][int(st.t * st.tumble) % 4]
		var frac: float = st.t / st.life
		if frac > 0.7:
			n.scale = Vector3.ONE * clampf((1.0 - frac) / 0.3, 0.05, 1.0)
