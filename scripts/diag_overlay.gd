class_name DiagOverlay
extends CanvasLayer
## Step 7: a hidden diagnostics readout for the real-device pass. Off by default and
## never saved; Shift+F3, a long press on the build stamp, or ?diag=1 shows it.
## Frame stats use wall-clock time, so hit-stop and the GAME SPEED assist (both of
## which change Engine.time_scale) don't skew them. Runs while the tree is paused.

const WINDOW_USEC := 1_000_000   # stats cover the last second of frames
const REFRESH := 0.25            # text refresh period, seconds of real time
const ROWS := 7
const NONE := "—"

## Time.get_ticks_msec() at the first controllable frame (game._report_first_flight).
static var first_flight_ms := 0
## Web only: the unmasked GPU string (WEBGL_debug_renderer_info). Browsers mask
## Godot's own adapter name to "WebKit WebGL", so game.gd reads this once at boot.
static var web_gpu := ""

var view: SubViewport            # the 320x200 game view whose draws we count
var _samples := PackedInt64Array()
var _next_text_usec := 0
var _label: Label
var _panel: ColorRect


func _ready() -> void:
	layer = 101   # above the CRT pass (100) so the numbers stay readable
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = ColorRect.new()
	_panel.color = Color(0, 0, 0, 0.72)
	_panel.position = Vector2(2, 2)
	_panel.size = Vector2(170, ROWS * 9 + 4)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = Label.new()
	_label.position = Vector2(5, 3)
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	_label.add_theme_constant_override("line_spacing", 1)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = false


func set_shown(on: bool) -> void:
	visible = on
	_next_text_usec = 0
	if not OS.has_feature("web"):
		_samples.clear()   # desktop stops sampling while hidden: drop the stale gap


func toggle() -> void:
	set_shown(not visible)


## Stats over frame end times (µs): fps, average and worst frame time, in ms.
## Fewer than two samples give zeros.
static func frame_stats(samples_usec: PackedInt64Array) -> Dictionary:
	var n := samples_usec.size()
	if n < 2:
		return {fps = 0.0, avg_ms = 0.0, worst_ms = 0.0}
	var worst := 0
	for i in range(1, n):
		worst = maxi(worst, samples_usec[i] - samples_usec[i - 1])
	var span := float(samples_usec[n - 1] - samples_usec[0])
	return {fps = (n - 1) / (span / 1e6) if span > 0.0 else 0.0,
		avg_ms = span / 1000.0 / (n - 1), worst_ms = worst / 1000.0}


func snapshot() -> Dictionary:
	var s := frame_stats(_samples)
	var draws := 0
	var objs := 0
	if view != null:
		var rid := view.get_viewport_rid()
		draws = RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		objs = RenderingServer.viewport_get_render_info(rid,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
			RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
	s.draw_calls = draws
	s.objects = objs
	s.bake_ms = SpriteForge.bake_ms
	s.bake_gpu = SpriteForge.gpu_baked
	s.prebaked = SpriteForge.prebaked
	s.boss_bake_ms = SpriteForge.boss_bake_ms
	s.objects_bake_ms = SpriteForge.objects_bake_ms
	s.first_flight_ms = first_flight_ms
	s.renderer = RenderingServer.get_current_rendering_method()
	s.adapter = web_gpu if web_gpu != "" else RenderingServer.get_video_adapter_name()
	s.vendor = RenderingServer.get_video_adapter_vendor()
	s.api = RenderingServer.get_video_adapter_api_version()
	return s


## The seven readout rows. Anything missing or empty prints as a dash.
static func lines(s: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	out.append("FPS %s  AVG %sms  WORST %sms" % [_num(s, "fps", 0), _num(s, "avg_ms", 1),
		_num(s, "worst_ms", 0)])
	out.append("DRAWS %s  OBJS %s" % [_num(s, "draw_calls", 0), _num(s, "objects", 0)])
	out.append("BAKE %sms GPU %s PRE %s" % [_num(s, "bake_ms", 0), _yn(s, "bake_gpu"),
		_yn(s, "prebaked")])
	out.append("BOSS %sms  OBJ %sms" % [_num(s, "boss_bake_ms", 0), _num(s, "objects_bake_ms", 0)])
	var ff: float = float(s.get("first_flight_ms", 0))
	out.append("FLIGHT %s" % ("%.1fs" % (ff / 1000.0) if ff > 0.0 else NONE))
	# the 320-px canvas holds about 60 PixelFont characters a row
	out.append(("%s · %s" % [_str(s, "renderer"), _str(s, "api")]).substr(0, 60))
	out.append(("GPU %s" % _str(s, "adapter")).substr(0, 60))
	return out


static func _num(s: Dictionary, key: String, decimals: int) -> String:
	if not s.has(key):
		return NONE
	var v := float(s[key])
	return ("%." + str(decimals) + "f") % v


static func _yn(s: Dictionary, key: String) -> String:
	return NONE if not s.has(key) else ("Y" if bool(s[key]) else "N")


static func _str(s: Dictionary, key: String) -> String:
	var v := str(s.get(key, ""))
	return v if v != "" else NONE


func _process(_delta: float) -> void:
	if not visible and not OS.has_feature("web"):
		return   # web keeps sampling so vrReport() has live numbers (Step 7 Task 3)
	var now := Time.get_ticks_usec()
	_samples.append(now)
	var cut := 0
	while cut < _samples.size() - 1 and now - _samples[cut] > WINDOW_USEC:
		cut += 1
	if cut > 0:
		_samples = _samples.slice(cut)
	if visible and now >= _next_text_usec and _samples.size() >= 2:
		_next_text_usec = now + int(REFRESH * 1e6)
		_label.text = "\n".join(lines(snapshot()))
		_panel.size = _label.get_combined_minimum_size() + Vector2(6, 2)   # fit the text
