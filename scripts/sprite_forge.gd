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
##
## v4b: each (model, frame) is built once and duplicated across its angle cells
## (meshes and materials are shared), and a class too tall for one viewport is
## split across several (see sheet_chunks).

const ANGLES := 8
const ANIM := 2
const CELL_WORLD := 2.6   # world units one atlas cell spans
## v4b: no bake viewport grows past this — the texture size every WebGL2 device must
## support. A taller sprite class is split across several viewports.
const MAX_SHEET_PX := 2048

static var _sets := {}       # model id -> sprite set
static var _pickups := {}    # pickup kind -> Array[ImageTexture] (spin frames)
static var _prop: Array[ImageTexture] = []
static var _baked := false
static var gpu_baked := false   # true when the GPU turntable path produced the sets
static var bake_ms := 0         # v4b: how long bake() took, either path
static var boss_bake_ms := 0    # the deferred boss sheet's bake (see bake_bosses)
static var _bosses_baked := false
static var _host: Node = null   # bake()'s host, reused by the deferred boss bake
static var sheet_count := 0     # v4b: bake viewports used (0 on the pixel fallback)
## Bake-only RenderingServer instances (the angle copies), freed after readback.
static var _rids: Array[RID] = []


## Bake the enemy and pickup sprites. Call once, early, from a node inside the tree.
## The boss sheet (the largest: 128 px cells) waits for the first boss — see
## bake_bosses — so the title comes up sooner.
static func bake(host: Node) -> void:
	if _baked:
		return
	_baked = true
	_host = host
	var t0 := Time.get_ticks_msec()
	_bake(host)
	bake_ms = Time.get_ticks_msec() - t0


## The boss and mini-boss sheet. Runs on the first sprite_set() of a boss model,
## which happens while a level loads (spawn_boss / spawn_miniboss in
## game._load_level_world): under the web loading overlay, behind the briefing on
## desktop. Safe to call any time; a no-op once done.
static func bake_bosses() -> void:
	if _bosses_baked:
		return
	_bosses_baked = true
	if not gpu_baked:
		return   # the pixel fallback already packed the bosses
	var host := _host
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		host = (Engine.get_main_loop() as SceneTree).root
	var t0 := Time.get_ticks_msec()
	if not _bake_classes(host, [{"cell": 128, "angles": ANGLES, "anim": ANIM,
			"pitch": 10.0, "ids": SpriteModels.BOSSES}]):
		push_warning("SpriteForge: boss atlas readback failed; using pixel fallback bosses")
		_fallback_bosses()
	boss_bake_ms = Time.get_ticks_msec() - t0


static func _bake(host: Node) -> void:
	if DisplayServer.get_name() == "headless":
		_fallback()
		_bosses_baked = true
		return
	if _bake_classes(host, [
		{"cell": 64, "angles": ANGLES, "anim": ANIM, "pitch": 14.0, "ids": SpriteModels.ENEMIES},
		{"cell": 32, "angles": 8, "anim": 1, "pitch": 24.0,
			"ids": SpriteModels.PICKUPS + ["prop"]},
	]):
		gpu_baked = true
	else:
		push_warning("SpriteForge: atlas readback failed; using pixel fallback sprites")
		_sets.clear()
		_pickups.clear()
		_prop.clear()
		_fallback()
		_bosses_baked = true


## Renders and slices the given sprite classes in one synchronous GPU pass. False
## if a readback came back empty (the caller falls back to pixel sprites).
static func _bake_classes(host: Node, classes: Array) -> bool:
	var sheets: Array[Dictionary] = []
	for cls in classes:
		for ids in sheet_chunks(cls.ids, cls.cell, cls.anim):
			var sh: Dictionary = cls.duplicate()
			sh.ids = ids
			sheets.append(sh)
	sheet_count += sheets.size()
	var vps: Array[SubViewport] = []
	for sh in sheets:
		vps.append(_build_sheet(host, sh))
	# Node3D transforms reach the RenderingServer on the frame flush; force them
	# now so the synchronous draw below sees every model where it belongs
	for vp in vps:
		_flush(vp)
	RenderingServer.force_draw(false)
	for r in _rids:
		RenderingServer.free_rid(r)
	_rids.clear()
	for k in sheets.size():
		var img: Image = vps[k].get_texture().get_image()
		vps[k].queue_free()
		if img == null or img.is_empty():
			for j in range(k + 1, sheets.size()):
				vps[j].queue_free()
			return false
		img.convert(Image.FORMAT_RGBA8)
		_slice(img, sheets[k])
	return true


static func sprite_set(id: String) -> Dictionary:
	_ensure()
	if not _bosses_baked and SpriteModels.BOSSES.has(id):
		bake_bosses()
	return _sets.get(id, _sets["drone"])


## True once the boss sheet exists (warm-up lists include it only then).
static func bosses_ready() -> bool:
	return _bosses_baked


static func pickup_frames(kind: String) -> Array:
	_ensure()
	return _pickups.get(kind, _pickups["shield"])


static func prop_texture() -> Texture2D:
	_ensure()
	return _prop[0]


## v4b: a sprite class's ids, split into as few equal viewports as keep each one
## within MAX_SHEET_PX tall (a row of cells per id and anim frame).
static func sheet_chunks(ids: Array, cell: int, anim: int) -> Array:
	var per := maxi(1, MAX_SHEET_PX / (cell * anim))
	var count := ceili(ids.size() / float(per))
	var size := ceili(ids.size() / float(maxi(count, 1)))
	var out: Array = []
	for i in range(0, ids.size(), maxi(size, 1)):
		out.append(ids.slice(i, i + size))
	return out


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
		_bosses_baked = true


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
	var scenario := vp.find_world_3d().scenario
	for idx in sh.ids.size():
		for f in sh.anim:
			var row: int = idx * sh.anim + f
			# v4b: one build per (model, frame), shared by every angle. Angle 0 is the
			# node tree itself; the other angles are bare RenderingServer instances of
			# its meshes (no nodes to duplicate and add to the tree: that cost ~220 ms
			# of a ~700 ms bake)
			var proto := SpriteModels.build(sh.ids[idx], f)
			var parts := _mesh_parts(proto)
			for a in cols:
				var pivot := Transform3D(Basis.from_euler(Vector3(deg_to_rad(sh.pitch), 0, 0)),
					Vector3((a + 0.5) * w - cols * w * 0.5, rows * w * 0.5 - (row + 0.5) * w, 0.0))
				proto.rotation.y = a * TAU / cols
				var at := pivot * proto.transform
				if a > 0:
					for pt in parts:
						var r := RenderingServer.instance_create2(pt.mesh, scenario)
						RenderingServer.instance_set_transform(r, at * pt.xf)
						RenderingServer.instance_geometry_set_material_override(r, pt.mat)
						_rids.append(r)
			proto.rotation.y = 0.0
			var holder := Node3D.new()
			holder.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(sh.pitch), 0, 0)),
				Vector3(0.5 * w - cols * w * 0.5, rows * w * 0.5 - (row + 0.5) * w, 0.0))
			holder.add_child(proto)
			vp.add_child(holder)
	return vp


## Every mesh under a model root with its transform relative to the root and its
## material — what an angle copy needs to be drawn without nodes.
static func _mesh_parts(root: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack: Array = [[root, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		for c in (item[0] as Node).get_children():
			if not (c is Node3D):
				continue
			var xf: Transform3D = item[1] * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var mi := c as MeshInstance3D
				out.append({"mesh": mi.mesh.get_rid(), "xf": xf,
					"mat": mi.material_override.get_rid() if mi.material_override else RID()})
			stack.append([c, xf])
	return out


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
				# v4b: the flash is cut from the bright idle frame, so glows and vent
				# slits are at full blaze inside the white pop
				if f == sh.anim - 1:
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
	_fallback_bosses()
	for kind in SpriteModels.PICKUPS:
		_pickups[kind] = [SpriteGen.pickup_texture(kind)]
	_prop = [SpriteGen.prop_texture()]


static func _fallback_bosses() -> void:
	var boss := SpriteGen.boss_frames()
	for id in SpriteModels.BOSSES:
		_sets[id] = {"angles": 1, "anim": 2, "tex": [boss[0], boss[1]], "flash": [boss[2]]}
