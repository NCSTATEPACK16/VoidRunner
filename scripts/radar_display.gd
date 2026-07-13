class_name RadarDisplay
extends Control
## Circular radar (PLAN.md H, pulled forward with the HUD): port of drawRadar.
## Rotates with yaw so "up" = ship forward; red = enemies, orange = incoming fire.

const RANGE := 110.0

var player: PlayerShip
var enemy_mgr: EnemyManager
var shot_mgr: ShotManager

var _sweep := 0.0


func _process(delta: float) -> void:
	_sweep += delta * 1.6
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := Vector2(s, s) * 0.5
	var radius := s * 0.5 - 1.0
	draw_circle(c, radius, Color(0.016, 0.086, 0.055, 0.9))
	var ring_col := Color(0.24, 0.82, 0.55, 0.28)
	draw_arc(c, radius, 0, TAU, 24, ring_col)
	draw_arc(c, radius * 0.66, 0, TAU, 20, ring_col)
	draw_arc(c, radius * 0.33, 0, TAU, 16, ring_col)
	draw_line(c - Vector2(0, radius), c + Vector2(0, radius), ring_col)
	draw_line(c - Vector2(radius, 0), c + Vector2(radius, 0), ring_col)
	# rotating sweep
	var sweep_dir := Vector2(cos(_sweep), sin(_sweep))
	draw_line(c, c + sweep_dir * radius, Color(0.24, 1.0, 0.63, 0.45))
	if player == null:
		return
	# player frame in the horizontal plane
	var fx := -sin(player.yaw)
	var fz := -cos(player.yaw)
	var rx := -fz
	var rz := fx
	for e in enemy_mgr.enemies:
		var dx: float = e.node.position.x - player.position.x
		var dz: float = e.node.position.z - player.position.z
		var lat := dx * rx + dz * rz
		var ahead := dx * fx + dz * fz
		var is_boss: bool = e.get("is_boss", false)
		var out_of_range := lat * lat + ahead * ahead > RANGE * RANGE
		if out_of_range and not is_boss:
			continue
		var p := c + Vector2(lat / RANGE * radius, -ahead / RANGE * radius)
		if is_boss:
			# the boss room is longer than radar range — pin the blip to the rim
			# so the signature is findable from the room mouth, blinking at ~2 Hz
			if out_of_range:
				p = c + Vector2(lat, -ahead).normalized() * radius
			if int(Time.get_ticks_msec() / 250) % 2 == 0:
				draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), Color("ff9a30"))
		else:
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(2, 2)), Color("ff3838"))
	for shot_pos in shot_mgr.eshot_cache:  # V2.1: shared per-frame cache (no realloc)
		var ex: float = shot_pos.x - player.position.x
		var ez: float = shot_pos.z - player.position.z
		var elat := ex * rx + ez * rz
		var eahead := ex * fx + ez * fz
		if elat * elat + eahead * eahead > RANGE * RANGE:
			continue
		var q := c + Vector2(elat / RANGE * radius, -eahead / RANGE * radius)
		draw_rect(Rect2(q, Vector2(1, 1)), Color(1.0, 0.59, 0.16, 0.9))
	# player marker
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -3), c + Vector2(-2.5, 2.5), c + Vector2(2.5, 2.5),
	]), Color("7dffc8"))
