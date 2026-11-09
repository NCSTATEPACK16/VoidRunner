extends Node
## PR E: the build-time sprite bake. Renders every SpriteForge class (enemies,
## pickups, bosses, mission objects) and writes the atlases plus manifest.json into
## resources/baked/, which the game loads instead of rendering at boot:
##   xvfb-run -a godot --rendering-driver opengl3 tools/bake_sprites.tscn   (Linux)
##   godot tools/bake_sprites.tscn                                          (the Neo, windowed)
## Headless can't render, so it refuses. Rebake and commit after any change to the
## sprite models, the studio shader, TextureGen or the class table; the smoke test and
## tools/check_budgets.py fail while the manifest's source hash is stale.
## Each PNG gets an importer="keep" .import, so it ships byte for byte and the game
## decodes it itself (headless runs and the export read the same file).

const OUT := "res://resources/baked"


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("bake_sprites: needs a renderer (run under xvfb-run, or windowed)")
		get_tree().quit(1)
		return
	await get_tree().process_frame   # let the window and renderer settle
	var dir := ProjectSettings.globalize_path(OUT)
	for f in DirAccess.get_files_at(dir) if DirAccess.dir_exists_absolute(dir) else PackedStringArray():
		if f.ends_with(".png") or f.ends_with(".png.import"):
			DirAccess.remove_absolute(dir.path_join(f))   # no stale sheets left behind
	var man := SpriteForge.bake_to_disk(self, dir)
	if man.is_empty():
		printerr("bake_sprites: an atlas readback came back empty")
		get_tree().quit(1)
		return
	var total := 0
	for sh in man.sheets:
		var path := dir.path_join(str(sh.file))
		var imp := FileAccess.open(path + ".import", FileAccess.WRITE)
		imp.store_string("[remap]\n\nimporter=\"keep\"\n")
		imp.close()
		var size := FileAccess.get_file_as_bytes(path).size()
		total += size
		print("[bake] %s  %s  %d ids  %d px cells  %d KB" % [sh.file, sh["class"],
			sh.ids.size(), int(sh.cell), size / 1024])
	print("[bake] %d sheets, %d KB, source %s, %d ms" % [man.sheets.size(), total / 1024,
		man.source_hash, int(man.ms)])
	print("BAKE SPRITES COMPLETE")
	get_tree().quit()
