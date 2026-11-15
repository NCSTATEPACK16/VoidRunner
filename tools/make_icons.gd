extends Node
## Paints the app icons and the link-preview card (see scripts/icon_gen.gd) into
## build/icons/, where the web and iOS exports pick them up:
##   godot --headless tools/make_icons.tscn
## build/ is gitignored, and the .gdignore written below keeps Godot from importing
## or packing the output. The export reads the PNGs straight from disk.

const OUT := "res://build/icons/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT + ".gdignore", FileAccess.WRITE).close()
	for size in [144, 180, 512]:
		_save(IconGen.icon(size), "icon_%d.png" % size)
	_save(IconGen.card(), "card_1200x630.png")
	# PR D2: the iOS preset reads these (App Store icon, launch screen mark)
	_save(IconGen.store_icon(), "icon_1024.png")
	for scale in [2, 3]:
		_save(IconGen.launch_image(scale), "launch@%dx.png" % scale)
	get_tree().quit()


func _save(img: Image, file_name: String) -> void:
	var err := img.save_png(OUT + file_name)
	if err != OK:
		push_error("make_icons: could not write %s (error %d)" % [file_name, err])
		get_tree().quit(1)
		return
	print("[icons] %s %dx%d" % [file_name, img.get_width(), img.get_height()])
