class_name LogoGen
## 3.0 Phase 4: the title logo, painted at boot from PixelFont's own letterforms
## in the style of mid-90s DOS title screens: each glyph pixel blown up into a
## block, extruded back-right into a violet "3D" slab, outlined in black, faced
## with a chrome gradient (white sky -> cyan -> deep blue horizon | orange -> gold
## ground) and a hard specular line across the top of every stroke.


static func chrome(text: String, scale := 3, extrude := 4) -> ImageTexture:
	var cw := PixelFont.ADVANCE * scale
	var gh := 7 * scale
	var w := text.length() * cw + extrude + 2
	var h := gh + extrude + 2
	# 1) the letter mask at block scale
	var mask := PackedByteArray()
	mask.resize(w * h)
	for i in text.length():
		var rows := PixelFont.glyph_rows(text[i])
		for ry in mini(rows.size(), 7):
			for rx in rows[ry].length():
				if rows[ry][rx] != "#":
					continue
				for by in scale:
					for bx in scale:
						var x := 1 + i * cw + rx * scale + bx
						var y := 1 + ry * scale + by
						mask[y * w + x] = 1
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	# 2) extrusion: the mask stamped back-right, darkest furthest away
	for d in range(extrude, 0, -1):
		var col := Palette.ramp(Palette.VIOLET, clampi(2 + (extrude - d) * 2, 1, 8))
		for y in h:
			for x in w:
				if mask[y * w + x] == 1 and x + d < w and y + d < h:
					img.set_pixel(x + d, y + d, col)
	# 3) black outline around the face
	for y in h:
		for x in w:
			if mask[y * w + x] == 1:
				continue
			for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + n.x
				var ny: int = y + n.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and mask[ny * w + nx] == 1:
					img.set_pixel(x, y, Color(0, 0, 0, 1))
					break
	# 4) chrome face: sky gradient above the horizon line, sunset below it
	var horizon := 1 + int(gh * 0.52)
	for y in h:
		for x in w:
			if mask[y * w + x] != 1:
				continue
			var c: Color
			if y < horizon:
				var t := float(y - 1) / float(horizon - 1)
				c = Palette.ramp(Palette.GREY, 15) if t < 0.18 \
					else (Palette.ramp(Palette.CYAN, 13) if t < 0.5 else Palette.ramp(Palette.BLUE, 7 + roundi((1.0 - t) * 4.0)))
			elif y == horizon:
				c = Palette.ramp(Palette.BLUE, 3)
			else:
				var t2 := float(y - horizon) / float(gh + 1 - horizon)
				c = Palette.ramp(Palette.ORANGE, 9 + roundi(t2 * 3.0)) if t2 < 0.55 \
					else Palette.ramp(Palette.GOLD, 12 + roundi((t2 - 0.55) * 6.0))
			# specular: the first row of every stroke catches the light
			if y > 0 and mask[(y - 1) * w + x] == 0 and y < horizon:
				c = Palette.ramp(Palette.GREY, 15)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)
