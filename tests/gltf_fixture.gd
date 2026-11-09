## PR E test helper (preloaded, not a class): writes a tiny glTF cube to `path`, so
## the CC0 model path is tested on a file the test itself makes (the real CC0
## sources arrive in PR F). `size` is the cube's edge; `centre` shifts it off-origin.
static func write_cube(path: String, size := 2.0, centre := Vector3.ZERO) -> void:
	var h := size * 0.5
	var pos := PackedFloat32Array()
	for i in 8:
		pos.append(centre.x + (h if i & 1 else -h))
		pos.append(centre.y + (h if i & 2 else -h))
		pos.append(centre.z + (h if i & 4 else -h))
	var tri := PackedInt32Array([0, 2, 1, 1, 2, 3, 4, 5, 6, 5, 7, 6, 0, 1, 4, 1, 5, 4,
		2, 6, 3, 3, 6, 7, 0, 4, 2, 2, 4, 6, 1, 3, 5, 3, 7, 5])
	var idx := PackedByteArray()
	for t in tri:
		idx.append(t & 0xff)
		idx.append((t >> 8) & 0xff)
	var buf := pos.to_byte_array() + idx
	var lo := Vector3(centre) - Vector3.ONE * h
	var hi := Vector3(centre) + Vector3.ONE * h
	var gltf := {
		"asset": {"version": "2.0", "generator": "voidrunner tests"},
		"scene": 0, "scenes": [{"nodes": [0]}],
		"nodes": [{"mesh": 0, "name": "cube"}],
		"meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1}]}],
		"buffers": [{"byteLength": buf.size(),
			"uri": "data:application/octet-stream;base64," + Marshalls.raw_to_base64(buf)}],
		"bufferViews": [
			{"buffer": 0, "byteOffset": 0, "byteLength": 96, "target": 34962},
			{"buffer": 0, "byteOffset": 96, "byteLength": idx.size(), "target": 34963}],
		"accessors": [
			{"bufferView": 0, "componentType": 5126, "count": 8, "type": "VEC3",
				"min": [lo.x, lo.y, lo.z], "max": [hi.x, hi.y, hi.z]},
			{"bufferView": 1, "componentType": 5123, "count": tri.size(), "type": "SCALAR"}],
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(gltf))
	f.close()
