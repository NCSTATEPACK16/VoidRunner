class_name PaletteLUT
extends Node
## 3.0 Phase 1: owns the GPU side of the 256-color palette.
##
## * `palette_texture` — the 256 Palette.ALL entries as a 256x1 texture.
## * `lut_texture` — a 512x512 nearest-color lookup table, rendered exactly once
##   by shaders/palette_lut.gdshader into a SubViewport (UPDATE_ONCE). Building it
##   on the GPU takes one draw; the same table in GDScript would be ~8M distance
##   tests (seconds on the single-threaded web build).
##
## The viewport stays alive for the life of the game — its render target IS the
## table the dither shader samples every frame.

const LUT_SIZE := 512

var palette_texture: ImageTexture
var lut_texture: Texture2D

var _vp: SubViewport


func _ready() -> void:
	var img := Image.create(Palette.ALL.size(), 1, false, Image.FORMAT_RGB8)
	for i in Palette.ALL.size():
		img.set_pixel(i, 0, Palette.ALL[i])
	palette_texture = ImageTexture.create_from_image(img)
	_vp = SubViewport.new()
	_vp.size = Vector2i(LUT_SIZE, LUT_SIZE)
	_vp.disable_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_vp)
	var rect := ColorRect.new()
	rect.size = Vector2(LUT_SIZE, LUT_SIZE)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/palette_lut.gdshader")
	mat.set_shader_parameter("palette_tex", palette_texture)
	mat.set_shader_parameter("palette_size", Palette.ALL.size())
	rect.material = mat
	_vp.add_child(rect)
	lut_texture = _vp.get_texture()
