class_name FxBatch
extends MultiMeshInstance3D
## v4 perf groundwork: one draw call for a whole effect layer. Every effect used to
## be its own Sprite3D, so a heavy fight cost a draw call per spark, puff, blast and
## chunk of debris, and single-threaded WebGL (iPad above all) is bound by draw
## calls. Here a layer's frames sit side by side in one atlas strip and every live
## effect is one MultiMesh instance: its transform holds position and size, its
## custom data picks the atlas cell.
##
## The material is a StandardMaterial3D in particle-billboard mode, the same path
## CPUParticles3D draws through on GL Compatibility and WebGL, with the flags
## SpriteGen.make_sprite gives a Sprite3D (unshaded, nearest filtering, alpha
## scissor, both faces, sRGB vertex colour as albedo when tinted), so a batched
## effect looks like the sprite it replaces. tests/fx_parity_probe.gd checks that.
##
## Immediate mode: the owner rebuilds the layer from its live effects once a frame,
##   begin(), then add(pos, size, cell[, tint]) per effect, then end().

## Atlas cells (the layer's animation frames or variants).
var cells := 1
## Most instances the layer can draw; add() refuses past it.
var capacity := 0
var _n := 0
var _tinted := false


## frames: square textures of one size. cap: the layer's live cap. tinted: a colour
## per instance (debris takes its hull tint), otherwise every instance is white.
func _init(frames: Array = [], cap := 0, tinted := false) -> void:
	if frames.is_empty():
		return
	capacity = cap
	_tinted = tinted
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.particles_anim_v_frames = 1
	mat.particles_anim_loop = false
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# a tint rides in the instance colour, as a Sprite3D's modulate rides in its
	# vertex colour. Untinted layers must not read it at all: without per-instance
	# colours the multimesh feeds zero alpha, and alpha scissor discards everything.
	mat.vertex_color_use_as_albedo = tinted
	mat.vertex_color_is_srgb = tinted
	material_override = mat
	set_frames(frames)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D   # the formats first: they lock
	mm.use_colors = tinted                          # once instance_count is set
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()   # 1 x 1, centred; the billboard turns it to the camera
	mm.instance_count = cap
	mm.visible_instance_count = 0
	# effects fly all over the level: a fixed, huge box means culling never hides
	# the layer and the server never rebuilds the box from moving instances
	mm.custom_aabb = AABB(Vector3.ONE * -1.0e5, Vector3.ONE * 2.0e5)
	multimesh = mm
	visible = false


## Swap in a new frame set (the player-bolt layer refills when the weapons arrive).
func set_frames(frames: Array) -> void:
	cells = frames.size()
	var mat: StandardMaterial3D = material_override
	mat.particles_anim_h_frames = cells
	mat.albedo_texture = ImageTexture.create_from_image(atlas(frames))


## Square frames of one size, left to right in one strip.
static func atlas(frames: Array) -> Image:
	var w: int = (frames[0] as Texture2D).get_width()
	var img := Image.create(w * frames.size(), w, false, Image.FORMAT_RGBA8)
	for i in frames.size():
		var src: Image = (frames[i] as Texture2D).get_image()
		if src.get_format() != Image.FORMAT_RGBA8:
			src.convert(Image.FORMAT_RGBA8)
		img.blit_rect(src, Rect2i(0, 0, w, w), Vector2i(i * w, 0))
	return img


func begin() -> void:
	_n = 0


## One effect this frame: world position, world size (the quad's edge) and atlas
## cell. Past capacity it is dropped, like the per-layer caps upstream.
func add(pos: Vector3, size: float, cell: int, tint := Color.WHITE) -> void:
	if _n >= capacity:
		return
	multimesh.set_instance_transform(_n, Transform3D(Basis.from_scale(Vector3.ONE * size), pos))
	multimesh.set_instance_custom_data(_n, cell_data(cell, cells))
	if _tinted:
		multimesh.set_instance_color(_n, tint)
	_n += 1


## The custom data that picks `cell` out of a strip of `n`: the particle billboard
## takes the frame from .z (0..1 across the strip, floored) and a spin from .x (0).
static func cell_data(cell: int, n: int) -> Color:
	return Color(0.0, 0.0, (clampi(cell, 0, n - 1) + 0.5) / n, 0.0)


## Draw what was added since begin(). An empty layer hides, so it costs no draw call.
func end() -> void:
	multimesh.visible_instance_count = _n
	visible = _n > 0


## Instances drawn this frame.
func count() -> int:
	return multimesh.visible_instance_count
