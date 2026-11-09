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

## PR E: the atlases are baked at build time by tools/bake_sprites.tscn into
## BAKED_DIR (PNG sheets + manifest.json) and loaded instead of rendered. Bump
## BAKE_VERSION when the sheet layout or slicing changes; the manifest's source hash
## (source_hash) catches model edits that weren't rebaked (smoke + check_budgets).
const BAKE_VERSION := 1
const BAKED_DIR := "res://resources/baked"
## The files whose content decides what the sprites look like.
const SOURCE_FILES := ["res://scripts/sprite_models.gd", "res://shaders/studio.gdshader",
	"res://scripts/texture_gen.gd"]

static var prebaked := false     # true when the sets came from BAKED_DIR, not a render
static var render_only := false  # tests: skip BAKED_DIR and render (the bake A/B, parity)
static var _manifest := {}       # the loaded manifest (prebaked only)
static var _sets := {}       # model id -> sprite set
static var _pickups := {}    # pickup kind -> Array[ImageTexture] (spin frames)
static var _prop: Array[ImageTexture] = []
static var _baked := false
static var gpu_baked := false   # true when the GPU turntable path produced the sets
static var bake_ms := 0         # v4b: how long bake() took, either path
static var boss_bake_ms := 0    # the deferred boss sheet's bake (see bake_bosses)
static var _bosses_baked := false
static var objects_bake_ms := 0   # v4c: the deferred OBJECTS sheet's bake (see bake_objects)
static var _objects_baked := false
static var _host: Node = null   # bake()'s host, reused by the deferred boss bake
static var sheet_count := 0     # v4b: bake viewports used (0 on the pixel fallback)
## Bake-only RenderingServer instances (the angle copies), freed after readback.
static var _rids: Array[RID] = []


## PR E: every sprite class and its fidelity. `when` is when the boot path renders
## it: boot, or deferred to the first boss / mission object of a level load. Angles,
## anim frames and cell size are per class; PR F tunes them for its pilot.
static func classes() -> Array:
	var pilot := SpriteModels.pilot_ids(SpriteModels.ENEMIES)
	var pilot_boss := SpriteModels.pilot_ids(SpriteModels.BOSSES)
	var out: Array = [
		{"name": "enemies", "cell": 64, "angles": ANGLES, "anim": ANIM, "pitch": 14.0,
			"ids": _without(SpriteModels.ENEMIES, pilot), "when": "boot"},
		{"name": "pickups", "cell": 32, "angles": 8, "anim": 1, "pitch": 24.0,
			"ids": SpriteModels.PICKUPS + ["prop"], "when": "boot"},
		{"name": "bosses", "cell": 128, "angles": ANGLES, "anim": ANIM, "pitch": 10.0,
			"ids": _without(SpriteModels.BOSSES, pilot_boss), "when": "boss"},
		{"name": "objects", "cell": 64, "angles": ANGLES, "anim": ANIM, "pitch": 14.0,
			"ids": SpriteModels.OBJECTS, "when": "objects"},
	]
	# PR F: the CC0 pilot, at its own (higher) fidelity
	if not pilot.is_empty():
		out.append({"name": "pilot", "cell": 64, "angles": SpriteModels.PILOT_ANGLES,
			"anim": SpriteModels.PILOT_ANIM, "pitch": 20.0, "ids": pilot, "when": "boot"})
	if not pilot_boss.is_empty():
		# flat CC0 ships read as a sliver edge-on, so the camera looks down on the deck more
		out.append({"name": "pilot_boss", "cell": 128, "angles": SpriteModels.PILOT_ANGLES,
			"anim": SpriteModels.PILOT_ANIM, "pitch": 24.0, "ids": pilot_boss, "when": "boss"})
	return out


static func _without(ids: Array, drop: Array) -> Array:
	return ids.filter(func(id: String) -> bool: return not drop.has(id))


static func _classes_when(when: String) -> Array:
	return classes().filter(func(c: Dictionary) -> bool: return c.when == when)


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
	if prebaked and _load_baked(["bosses", "pilot_boss"]):
		boss_bake_ms = Time.get_ticks_msec() - t0
		return
	if not _bake_classes(host, _classes_when("boss")):
		push_warning("SpriteForge: boss atlas readback failed; using pixel fallback bosses")
		_fallback_bosses()
	boss_bake_ms = Time.get_ticks_msec() - t0


## v4c: the mission-object sheet (generator, reactor, rift anchor; 64 px cells). Same
## deal as the bosses: it bakes on the first sprite_set() of an OBJECTS id, while a
## level loads, so the boot bake stays as short as it was. Safe to call any time.
static func bake_objects() -> void:
	if _objects_baked:
		return
	_objects_baked = true
	if not gpu_baked:
		return   # the pixel fallback already packed the objects
	var host := _host
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		host = (Engine.get_main_loop() as SceneTree).root
	var t0 := Time.get_ticks_msec()
	if prebaked and _load_baked(["objects"]):
		objects_bake_ms = Time.get_ticks_msec() - t0
		return
	if not _bake_classes(host, _classes_when("objects")):
		push_warning("SpriteForge: object atlas readback failed; using pixel fallback objects")
		_fallback_objects()
	objects_bake_ms = Time.get_ticks_msec() - t0


static func _bake(host: Node) -> void:
	if DisplayServer.get_name() == "headless":
		_fallback()
		_bosses_baked = true
		_objects_baked = true
		return
	# PR E: the build-time atlases, when they match this build; else render them
	if not render_only and _load_baked(["enemies", "pickups", "pilot"]):
		prebaked = true
		gpu_baked = true
		return
	if _bake_classes(host, _classes_when("boot")):
		gpu_baked = true
	else:
		push_warning("SpriteForge: atlas readback failed; using pixel fallback sprites")
		_sets.clear()
		_pickups.clear()
		_prop.clear()
		_fallback()
		_bosses_baked = true
		_objects_baked = true


## Renders and slices the given sprite classes in one synchronous GPU pass. False
## if a readback came back empty (the caller falls back to pixel sprites).
static func _bake_classes(host: Node, classes: Array, save_dir := "") -> bool:
	var sheets: Array[Dictionary] = []
	for cls in classes:
		var chunk := 0
		for ids in sheet_chunks(cls.ids, cls.cell, cls.anim):
			var sh: Dictionary = cls.duplicate()
			sh.ids = ids
			sh.file = "%s_%d.png" % [cls.get("name", "sheet"), chunk]
			chunk += 1
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
	SpriteModels.clear_glb_cache()   # PR F: the parsed CC0 models aren't needed past the draw
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
		if save_dir != "":
			img.save_png(save_dir.path_join(sheets[k].file))
			_saved.append(_sheet_entry(sheets[k]))
		_slice(img, sheets[k])
	return true


static func sprite_set(id: String) -> Dictionary:
	_ensure()
	if not _bosses_baked and SpriteModels.BOSSES.has(id):
		bake_bosses()
	if not _objects_baked and SpriteModels.OBJECTS.has(id):
		bake_objects()
	return _sets.get(id, _sets["drone"])


## PR E (tools/bake_sprites.tscn): render every class and write the sheets plus
## manifest.json into `dir` (a filesystem path or res://). Needs a renderer.
static var _saved: Array = []


static func bake_to_disk(host: Node, dir: String) -> Dictionary:
	_saved.clear()
	DirAccess.make_dir_recursive_absolute(dir)
	var t0 := Time.get_ticks_msec()
	if not _bake_classes(host, classes(), dir):
		return {}
	var man := {"bake_version": BAKE_VERSION, "source_hash": source_hash(),
		"sheets": _saved.duplicate(true)}
	var f := FileAccess.open(dir.path_join("manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(man, "\t", false) + "\n")
	f.close()
	man["ms"] = Time.get_ticks_msec() - t0
	return man


static func _sheet_entry(sh: Dictionary) -> Dictionary:
	return {"class": sh.get("name", ""), "file": sh.file, "cell": sh.cell,
		"angles": sh.angles, "anim": sh.anim, "ids": sh.ids}


## Load every class from the prebaked sheets over whatever is there (forge probe
## parity, the smoke test). False if any class can't come from them.
static func load_all_baked(dir := BAKED_DIR) -> bool:
	_manifest = {}
	return _load_baked(classes().map(func(c: Dictionary) -> String: return c.name), dir)


## The parsed manifest in `dir`, or {} if it's missing or from another layout.
static func read_manifest(dir := BAKED_DIR) -> Dictionary:
	var path := dir.path_join("manifest.json")
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary) or int((data as Dictionary).get("bake_version", -1)) != BAKE_VERSION:
		return {}
	return data


## Slice the prebaked sheets of the named classes into the sets. False (and nothing
## half-loaded is kept for those ids) if the manifest is missing, from another
## BAKE_VERSION, doesn't cover a class's ids, or a sheet won't decode.
static func _load_baked(names: Array, dir := BAKED_DIR) -> bool:
	var man: Dictionary = _manifest if dir == BAKED_DIR and not _manifest.is_empty() \
		else read_manifest(dir)
	if dir == BAKED_DIR:
		_manifest = man   # cached for the deferred boss / object loads
	if man.is_empty():
		return false
	var want := classes().filter(func(c: Dictionary) -> bool: return names.has(c.name))
	var todo: Array = []
	for cls in want:
		var covered := {}
		for sh in man.get("sheets", []):
			if sh.get("class") == cls.name:
				todo.append(sh)
				for id in sh.get("ids", []):
					covered[id] = true
		for id in cls.ids:
			if not covered.has(id):
				return false   # the manifest predates this sprite: render instead
	var imgs: Array[Image] = []
	for sh in todo:
		var bytes := FileAccess.get_file_as_bytes(dir.path_join(str(sh.file)))
		var img := Image.new()
		if bytes.is_empty() or img.load_png_from_buffer(bytes) != OK:
			return false
		img.convert(Image.FORMAT_RGBA8)
		imgs.append(img)
	for i in todo.size():
		var sh: Dictionary = todo[i]
		_slice(imgs[i], {"cell": int(sh.cell), "angles": int(sh.angles), "anim": int(sh.anim),
			"ids": sh.ids})
	return true


## PR E: md5 over everything that decides how the sprites look — the model and
## shader sources, the class table and any CC0 model files. Dev-only (exported
## scripts are compiled, so the hash only means something in a checkout).
static func source_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for path in SOURCE_FILES:
		ctx.update(FileAccess.get_file_as_bytes(path))
	var table := classes().map(func(c: Dictionary) -> String:
		return "%s|%d|%d|%d|%.1f|%s" % [c.name, c.cell, c.angles, c.anim, c.pitch, ",".join(c.ids)])
	ctx.update(("\n".join(table) + "\nv%d" % BAKE_VERSION).to_utf8_buffer())
	for id in SpriteModels.glb_ids():
		ctx.update(str(id).to_utf8_buffer())
		ctx.update(FileAccess.get_file_as_bytes(str(SpriteModels.glb_source(id).path)))
	return ctx.finish().hex_encode()


## True once the boss sheet exists (warm-up lists include it only then).
static func bosses_ready() -> bool:
	return _bosses_baked


## True once the objects sheet exists (warm-up lists include it only then).
static func objects_ready() -> bool:
	return _objects_baked


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
		_objects_baked = true


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
						# PR F: CC0 models keep a material per surface
						for si in pt.surf.size():
							if pt.surf[si].is_valid():
								RenderingServer.instance_set_surface_override_material(r, si, pt.surf[si])
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
				var surf: Array[RID] = []
				if mi.material_override == null:
					for si in mi.mesh.get_surface_count():
						var sm := mi.get_surface_override_material(si)
						surf.append(sm.get_rid() if sm else RID())
				out.append({"mesh": mi.mesh.get_rid(), "xf": xf, "surf": surf,
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
			_sets[id] = {"angles": sh.angles, "anim": sh.anim, "tex": tex, "flash": flash,
				"view": SpriteModels.view_scale(id)}


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
	_fallback_objects()
	for kind in SpriteModels.PICKUPS:
		_pickups[kind] = [SpriteGen.pickup_texture(kind)]
	_prop = [SpriteGen.prop_texture()]


static func _fallback_bosses() -> void:
	var boss := SpriteGen.boss_frames()
	for id in SpriteModels.BOSSES:
		_sets[id] = {"angles": 1, "anim": 2, "tex": [boss[0], boss[1]], "flash": [boss[2]]}


static func _fallback_objects() -> void:
	for id in SpriteModels.OBJECTS:
		var fr := SpriteGen.object_frames(id)
		_sets[id] = {"angles": 1, "anim": 2, "tex": [fr[0], fr[1]], "flash": [fr[2]]}
