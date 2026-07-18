class_name Automap
extends Control
## V2.2 L4a: Tab automap. Renders INSIDE the 320x200 game SubViewport (chunky +
## dithered for free), a north-up top-down XZ projection of the explored rings.
##
## Opening HARD-pauses the tree (get_tree().paused) — constant-forward flight makes
## a live map lethal, and pausing is the safe, Doom-authentic call. The node's
## process_mode is WHEN_PAUSED so it can blink the player blip and take the close
## input while everything else is frozen; conversely it does nothing (and never
## draws) while closed. Dirty-draw: the explored polyline rebuilds only when the
## explored range changes; _draw runs only while open.

const MARGIN := 14.0
const WALL_COL := Color("5a6b7a")
const ARENA_COL := Color("8fb8cc")
const BOSS_COL := Color("ff5040")
const PORTAL_COL := Color("62ffd0")
const SECRET_COL := Color("ffd34d")
const PLAYER_COL := Color("ffffff")

var _path = null            # PathGen (RefCounted — untyped to avoid a cyclic class dep)
var _player = null          # PlayerShip — read for ring_idx + yaw at draw time
var _open := false
var _max_ring := 0          # high-water explored ring index
var _dirty := true
var _pts: PackedVector2Array = PackedVector2Array()      # ring centres in world XZ
var _widths: PackedFloat32Array = PackedFloat32Array()   # per-ring half-width
var _zoom := 1.0
var _blink := 0.0
var _blink_on := true
var _secret_rings: PackedInt32Array = PackedInt32Array()
var _portal_ring := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED   # blink + close input while paused
	mouse_filter = Control.MOUSE_FILTER_IGNORE     # view-only; never eats input
	position = Vector2.ZERO
	size = Vector2(320, 200)
	visible = false


## Called by game._load_level_world with the new level's path — resets exploration.
func setup(path, player) -> void:
	_path = path
	_player = player
	_max_ring = 0
	_zoom = 1.0
	_secret_rings = PackedInt32Array()
	_portal_ring = -1
	_dirty = true


func note_ring(idx: int) -> void:
	if idx > _max_ring:
		_max_ring = idx
		_dirty = true


## Markers the game refreshes when the map opens (found secrets, woken exit portal).
func set_markers(secret_rings: PackedInt32Array, portal_ring: int) -> void:
	_secret_rings = secret_rings
	_portal_ring = portal_ring
	if _open:
		queue_redraw()


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	_blink = 0.0
	_blink_on = true
	_rebuild()                     # build _pts now — headless has no _draw to trigger it
	Engine.time_scale = 1.0        # cancel any active hit-stop crush before the freeze
	get_tree().paused = true
	queue_redraw()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	get_tree().paused = false


func _process(delta: float) -> void:
	if not _open:
		return
	_blink += delta
	if _blink >= 0.4:
		_blink -= 0.4
		_blink_on = not _blink_on
		queue_redraw()             # only the player blip toggles — cheap, tree is paused


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return   # while closed the node is WHEN_PAUSED and gets no input anyway
	if event.is_action_pressed("automap") or event.is_action_pressed("pause_game"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.physical_keycode in [KEY_EQUAL, KEY_BRACKETRIGHT, KEY_KP_ADD]:
			_zoom = minf(_zoom * 1.33, 4.0)
			queue_redraw()
		elif event.physical_keycode in [KEY_MINUS, KEY_BRACKETLEFT, KEY_KP_SUBTRACT]:
			_zoom = maxf(_zoom / 1.33, 0.5)
			queue_redraw()


func _rebuild() -> void:
	_pts = PackedVector2Array()
	_widths = PackedFloat32Array()
	_dirty = false
	if _path == null or _path.rings.is_empty():
		return
	var hi: int = mini(_max_ring + 2, _path.rings.size() - 1)   # +2 ring lookahead
	for i in hi + 1:
		var r: Dictionary = _path.rings[i]
		_pts.append(Vector2(r.p.x, r.p.z))
		_widths.append(r.hw)


func _draw() -> void:
	if _dirty:
		_rebuild()
	draw_rect(Rect2(0, 0, 320, 200), Color.BLACK)   # grid-free black, like a 1995 automap
	if _pts.size() < 2:
		return
	# fit the explored bounds into the rect (north-up), then zoom about the centre
	var lo := _pts[0]
	var hi := _pts[0]
	for p in _pts:
		lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.y)
	var span := hi - lo
	var s: float = minf((320.0 - 2.0 * MARGIN) / maxf(span.x, 1.0),
		(200.0 - 2.0 * MARGIN) / maxf(span.y, 1.0)) * _zoom
	var centre := (lo + hi) * 0.5
	var to_screen := func(w: Vector2) -> Vector2:
		return Vector2(160, 100) + Vector2((w.x - centre.x) * s, (w.y - centre.y) * s)
	# tunnel polyline, thickened per ring half-width; arenas + boss room read distinct
	for i in range(1, _pts.size()):
		var col := WALL_COL
		var ri: Dictionary = _path.rings[i]
		if ri.arena:
			col = BOSS_COL if _path.is_boss else ARENA_COL
		draw_line(to_screen.call(_pts[i - 1]), to_screen.call(_pts[i]), col,
			clampf(_widths[i] * s * 0.12, 1.0, 6.0))
	# markers
	for sr in _secret_rings:
		if sr >= 0 and sr < _pts.size():
			draw_string(ThemeDB.fallback_font, to_screen.call(_pts[sr]) + Vector2(-3, 3),
				"S", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, SECRET_COL)
	if _portal_ring >= 0 and _portal_ring < _pts.size():
		var pp: Vector2 = to_screen.call(_pts[_portal_ring])
		draw_colored_polygon(PackedVector2Array([
			pp + Vector2(0, -4), pp + Vector2(4, 0), pp + Vector2(0, 4), pp + Vector2(-4, 0)]),
			PORTAL_COL)   # exit-portal diamond
	# player: blinking triangle at its ring centre, pointing along yaw (north-up)
	if _player != null and _blink_on:
		var pc: Vector2 = to_screen.call(_pts[clampi(_player.ring_idx, 0, _pts.size() - 1)])
		var fwd := Vector2(-sin(_player.yaw), -cos(_player.yaw))
		var side := Vector2(-fwd.y, fwd.x)
		draw_colored_polygon(PackedVector2Array([
			pc + fwd * 5.0, pc - fwd * 3.0 + side * 3.0, pc - fwd * 3.0 - side * 3.0]),
			PLAYER_COL)
