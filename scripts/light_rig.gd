class_name LightRig
extends Node
## 3.0 Phase 2: the single dynamic-light system. There is no OmniLight3D anywhere
## in the game any more — every world material is shaders/sector.gdshader, which
## takes up to MAX_LIGHTS point lights as uniform arrays. Each frame the game
## calls begin(), feeds this frame's transient lights (headlight, muzzle flash,
## explosions, glowing shots) through add(), and commit() folds in the level's
## static lamps (flickering / strobing arena lights, the exit portal), keeps the
## strongest MAX_LIGHTS by a nearness-weighted score, and pushes one pair of
## arrays to every registered material.
##
## Zero steady-state allocation: the candidate buffers are fixed-size packed
## arrays reused frame to frame.

const MAX_LIGHTS := 8
const MAX_CANDIDATES := 48
## Statics farther than this from the camera can't light anything worth seeing.
const STATIC_CULL := 170.0

var _materials: Array[ShaderMaterial] = []
var _statics: Array[Dictionary] = []   # {pos, color, energy, range, mode, phase, on}
var _t := 0.0
var _cam := Vector3.ZERO

# candidate buffers (xyz = pos, w = range) / (rgb = color * energy) / score
var _cp := PackedVector4Array()
var _cc := PackedVector4Array()
var _cs := PackedFloat32Array()
var _n := 0
# the arrays actually pushed to the shaders
var _out_p := PackedVector4Array()
var _out_c := PackedVector4Array()
var _taken := PackedByteArray()


func _init() -> void:
	_cp.resize(MAX_CANDIDATES)
	_cc.resize(MAX_CANDIDATES)
	_cs.resize(MAX_CANDIDATES)
	_taken.resize(MAX_CANDIDATES)
	_out_p.resize(MAX_LIGHTS)
	_out_c.resize(MAX_LIGHTS)


## Every sector material that should receive dynamic light registers here.
func register(mat: ShaderMaterial) -> ShaderMaterial:
	if not _materials.has(mat):
		_materials.append(mat)
		mat.set_shader_parameter("dyn_pos", _out_p)
		mat.set_shader_parameter("dyn_col", _out_c)
	return mat


func clear_materials() -> void:
	_materials.clear()


func material_count() -> int:
	return _materials.size()


## Level lamps with an animated mood: "steady" | "flicker" | "strobe". Returns an
## id for set_static_on() (the exit portal is dark until its gate wakes).
func add_static(pos: Vector3, color: Color, energy: float, light_range: float,
		mode := "steady", phase := 0.0) -> int:
	_statics.append({"pos": pos, "color": color, "energy": energy, "range": light_range,
		"mode": mode, "phase": phase, "on": true, "live": energy})
	return _statics.size() - 1


func set_static_on(id: int, on: bool) -> void:
	if id >= 0 and id < _statics.size():
		_statics[id].on = on


func clear_statics() -> void:
	_statics.clear()


func statics() -> Array[Dictionary]:
	return _statics


func begin(camera_pos: Vector3) -> void:
	_cam = camera_pos
	_n = 0


## One transient light for this frame only. Silently dropped past MAX_CANDIDATES.
func add(pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	if _n >= MAX_CANDIDATES or energy <= 0.01 or light_range <= 0.0:
		return
	_cp[_n] = Vector4(pos.x, pos.y, pos.z, light_range)
	_cc[_n] = Vector4(color.r * energy, color.g * energy, color.b * energy, 0.0)
	# strong + near wins; a light's own range counts toward how far it matters
	var d := maxf(pos.distance_to(_cam) - light_range * 0.35, 1.0)
	_cs[_n] = energy * light_range / d
	_n += 1


## Animate the statics, pick the best MAX_LIGHTS, push them to every material.
func commit(delta: float) -> void:
	_t += delta
	for s in _statics:
		if not s.on:
			continue
		var e: float = s.energy
		if not GameState.reduce_flashing:   # M1.2: moods hold steady on request
			match s.mode:
				"flicker":
					e *= 0.55 + 0.45 * sin(_t * 13.0 + s.phase) * sin(_t * 7.3 + s.phase * 2.0)
				"strobe":
					e *= 1.0 if fmod(_t + s.phase, 0.9) < 0.62 else 0.08
		s.live = e
		if (s.pos as Vector3).distance_squared_to(_cam) < STATIC_CULL * STATIC_CULL:
			add(s.pos, s.color, e, s.range)
	for k in _n:
		_taken[k] = 0
	for slot in MAX_LIGHTS:
		var best := -1
		var best_s := -1.0
		for k in _n:
			if _taken[k] == 0 and _cs[k] > best_s:
				best_s = _cs[k]
				best = k
		if best >= 0:
			_taken[best] = 1
			_out_p[slot] = _cp[best]
			_out_c[slot] = _cc[best]
		else:
			_out_p[slot] = Vector4(0.0, 0.0, 0.0, 0.0)   # range 0 = slot off
			_out_c[slot] = Vector4(0.0, 0.0, 0.0, 0.0)
	for m in _materials:
		m.set_shader_parameter("dyn_pos", _out_p)
		m.set_shader_parameter("dyn_col", _out_c)


## Slots currently lit — tests and the perf probe read this.
func active_count() -> int:
	var n := 0
	for p in _out_p:
		if p.w > 0.0:
			n += 1
	return n
