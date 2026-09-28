class_name SpriteForge
## 3.0 Phase 3: pre-rendered 3D sprites, baked at boot — the way mid-90s DOS
## sprites were made (model it, turntable-render it at fixed angles, palettize it),
## except the "3D package" is Godot itself and the models are code
## (SpriteModels). Nothing is imported, so hard rule #1 holds unchanged.
##
## One SubViewport per sprite class (enemies 64 px, bosses 128 px, pickups 32 px)
## renders a whole atlas in a single pass: an orthographic camera and view-space
## studio lighting make every cell light identically, so a grid of rotated model
## copies IS a turntable. RenderingServer.force_draw() renders it synchronously,
## the atlas is read back once and sliced into ImageTextures; hit-flash frames are
## derived with native Image ops. The viewports are freed right after.
##
## A sprite set is {angles, anim, tex: Array (angles * anim), flash: Array (angles)}
## with tex[a * anim + f] = angle a, idle frame f. Angle 0 is the model's front;
## angle_index() maps a facing + camera direction to the cell to show.
##
## Headless runs (the smoke test) have no renderer: bake() falls back to the old
## hand-plotted SpriteGen pixel sprites packed into the same set shape (1 angle),
## so every consumer runs the same code paths either way.

const ANGLES := 8
const ANIM := 2
const CELL_WORLD := 2.6   # world units one atlas cell spans

static var _sets := {}       # model id -> sprite set
static var _pickups := {}    # pickup kind -> Array[ImageTexture] (spin frames)
static var _prop: Array[ImageTexture] = []
static var _baked := false
static var gpu_baked := false   # true when the GPU turntable path produced the sets


## Bake every sprite class. Call once, early, from a node inside the tree.
static func bake(host: Node) -> void:
	if _baked:
		return
	_baked = true
	if DisplayServer.get_name() == "headless":
		_fallback()
		return
	var sheets := [
		{"cell": 64, "angles": ANGLES, "anim": ANIM, "pitch": 14.0, "ids": SpriteModels.ENEMIES},
		{"cell": 128, "angles": ANGLES, "anim": ANIM, "pitch": 10.0, "ids": SpriteModels.BOSSES},
		{"cell": 32, "angles": 8, "anim": 1, "pitch": 24.0,
			"ids": SpriteModels.PICKUPS + ["prop"]},
	]
	var vps: Array[SubViewport] = []
	for sh in sheets:
		vps.append(_build_sheet(host, sh))
	# Node3D transforms reach the RenderingServer on the frame flush; force them
	# now so the synchronous draw below sees every model where it belongs
	for vp in vps:
		_flush(vp)
	RenderingServer.force_draw(false)
	for k in sheets.size():
		var img: Image = vps[k].get_texture().get_image()
		vps[k].queue_free()
		if img == null or img.is_empty():
			push_warning("SpriteForge: atlas readback failed; using pixel fallback sprites")
			_sets.clear()
			_pickups.clear()
			_prop.clear()
			_fallback()
			return
		img.convert(Image.FORMAT_RGBA8)
		_slice(img, sheets[k])
	gpu_baked = true


static func sprite_set(id: String) -> Dictionary:
	_ensure()
	return _sets.get(id, _sets["drone"])


static func pickup_frames(kind: String) -> Array:
	_ensure()
	return _pickups.get(kind, _pickups["shield"])


static func prop_texture() -> Texture2D:
	_ensure()
	return _prop[0]


## Which baked angle to show for a sprite facing `facing`, seen along `to_cam`
## (sprite -> camera). Angle a was rendered with the model yawed by a * 360/angles
## in front of the bake camera, so the camera sits at -theta from the model's front.
static func angle_index(facing: Vector3, to_cam: Vector3, angles: int) -> int:
	if angles <= 1:
		return 0
	var theta := wrapf(atan2(to_cam.x, to_cam.z) - atan2(facing.x, facing.z), -PI, PI)
	return posmod(roundi(-theta / (TAU / angles)), angles)


static func _ensure() -> void:
	if not _baked:
		_baked = true
		_fallback()


static func _build_sheet(host: Node, sh: Dictionary) -> SubViewport:
	var cols: int = sh.angles
	var rows: int = sh.ids.size() * sh.anim
	var cell: int = sh.cell
	var vp := SubViewport.new()
	vp.size = Vector2i(cols * cell, rows * cell)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = rows * CELL_WORLD
	cam.near = 0.5
	cam.far = 60.0
	cam.position = Vector3(0, 0, 30)
	vp.add_child(cam)
	cam.current = true
	var w := CELL_WORLD
	for idx in sh.ids.size():
		for f in sh.anim:
			var row: int = idx * sh.anim + f
			for a in cols:
				var pivot := Node3D.new()
				pivot.position = Vector3((a + 0.5) * w - cols * w * 0.5,
					rows * w * 0.5 - (row + 0.5) * w, 0.0)
				pivot.rotation.x = deg_to_rad(sh.pitch)   # look down on it a little
				var model := SpriteModels.build(sh.ids[idx], f)
				model.rotation.y = a * TAU / cols
				pivot.add_child(model)
				vp.add_child(pivot)
	return vp


static func _flush(n: Node) -> void:
	if n is Node3D:
		(n as Node3D).force_update_transform()
	for c in n.get_children():
		_flush(c)


static func _slice(img: Image, sh: Dictionary) -> void:
	var cell: int = sh.cell
	for idx in sh.ids.size():
		var id: String = sh.ids[idx]
		var tex: Array[ImageTexture] = []
		var flash: Array[ImageTexture] = []
		for a in sh.angles:
			for f in sh.anim:
				var region := img.get_region(Rect2i(a * cell, (idx * sh.anim + f) * cell, cell, cell))
				tex.append(ImageTexture.create_from_image(region))
				if f == 0:
					flash.append(ImageTexture.create_from_image(_flash_of(region)))
		if id == "prop":
			_prop = [tex[0]]
		elif SpriteModels.PICKUPS.has(id):
			_pickups[id] = tex
		else:
			_sets[id] = {"angles": sh.angles, "anim": sh.anim, "tex": tex, "flash": flash}


## Hit flash: the sprite washed 70% toward white, original silhouette kept —
## all native Image ops (blend, then mask-copy back onto a clear image).
static func _flash_of(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var tmp := src.duplicate() as Image
	var white := Image.create(w, h, false, Image.FORMAT_RGBA8)
	white.fill(Color(1, 1, 1, 0.7))
	tmp.blend_rect(white, Rect2i(0, 0, w, h), Vector2i.ZERO)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.blit_rect_mask(tmp, src, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return out


## No renderer: the pre-3.0 hand-plotted sprites, packed as 1-angle sets.
static func _fallback() -> void:
	var legacy := {
		"drone": SpriteGen.drone_frames(), "weaver": SpriteGen.weaver_frames(),
		"hulk": SpriteGen.hulk_frames(), "turret": SpriteGen.turret_frames(),
	}
	for id in SpriteModels.ENEMIES:
		var fr: Array = legacy.get(id, legacy["drone"])
		_sets[id] = {"angles": 1, "anim": 2, "tex": [fr[0], fr[1]], "flash": [fr[2]]}
	var boss := SpriteGen.boss_frames()
	for id in SpriteModels.BOSSES:
		_sets[id] = {"angles": 1, "anim": 2, "tex": [boss[0], boss[1]], "flash": [boss[2]]}
	for kind in SpriteModels.PICKUPS:
		_pickups[kind] = [SpriteGen.pickup_texture(kind)]
	_prop = [SpriteGen.prop_texture()]
