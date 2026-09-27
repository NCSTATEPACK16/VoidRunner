class_name SpriteModels
## 3.0 Phase 3: every enemy, boss, pickup and prop as a small code-built 3D model
## — Godot primitive meshes + shaders/studio.gdshader materials. SpriteForge
## renders these into sprite atlases at boot; they never appear in the game world
## as geometry. Conventions: centred on the origin, front facing +Z (toward the
## bake camera at yaw 0), fitting inside a radius of about 1.15 units. `frame`
## (0/1) is the 2-frame idle animation: glows pulse, rings turn, wings flap.

const STUDIO := preload("res://shaders/studio.gdshader")

## enemy id -> builder name; ids match EnemyManager.TYPES and LevelDef.boss_model
const ENEMIES := ["drone", "weaver", "hulk", "turret", "stinger", "spinner", "mine"]
const BOSSES := ["sentinel", "brood", "maw"]
const PICKUPS := ["shield", "energy", "missile", "bomb", "salvage", "overdrive", "phase",
	"powercore"]

static var _mats := {}


static func build(id: String, frame: int) -> Node3D:
	var root := Node3D.new()
	match id:
		"drone": _drone(root, frame)
		"weaver": _weaver(root, frame)
		"hulk": _hulk(root, frame)
		"turret": _turret(root, frame)
		"stinger": _stinger(root, frame)
		"spinner": _spinner(root, frame)
		"mine": _mine(root, frame)
		"sentinel": _sentinel(root, frame)
		"brood": _brood(root, frame)
		"maw": _maw(root, frame)
		"prop": _fuel_cell(root)
		_: _pickup(root, id)
	return root


# ---------------------------------------------------------------- kit

## Cached studio material. glow = emission strength (0 = lit surface, 1 = light).
static func m(col: String, chrome := 0.3, glow := 0.0, gloss := 28.0, spec := 0.7,
		rim := 0.55) -> ShaderMaterial:
	var key := "%s|%.2f|%.2f|%.1f|%.2f|%.2f" % [col, chrome, glow, gloss, spec, rim]
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = STUDIO
	var c := Color(col)
	mat.set_shader_parameter("base", c)
	mat.set_shader_parameter("emit", Color(c.r, c.g, c.b, glow))
	mat.set_shader_parameter("chrome", chrome)
	mat.set_shader_parameter("gloss", gloss)
	mat.set_shader_parameter("spec", spec)
	mat.set_shader_parameter("rim", rim)
	_mats[key] = mat
	return mat


## A lit glow part: fully emissive, brightened a notch on the bright anim frame.
static func glow(col: String, frame := 0) -> ShaderMaterial:
	return m(col, 0.0, 1.0 if frame == 1 else 0.85, 28.0, 0.0, 0.0)


static func part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3,
		rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.scale = scl
	root.add_child(mi)
	return mi


static func sphere(r: float, h := -1.0, seg := 20) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h if h > 0.0 else r * 2.0
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 6)
	return s


static func box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b


static func cyl(r_top: float, r_bot: float, h: float, seg := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 16
	c.rings = 6
	return c


static func torus(inner: float, outer: float, seg := 24) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = seg
	t.ring_segments = 10
	return t


static func prism(x: float, y: float, z: float) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = Vector3(x, y, z)
	return p


# ---------------------------------------------------------------- enemies

## Sentry saucer: chrome hull, canopy dome, a big red eye, thruster pods.
static func _drone(root: Node3D, f: int) -> void:
	var hull := m("8a9ac0", 0.45)
	var gun := m("4a5468", 0.25)
	var dark := m("262c3a", 0.15)
	part(root, sphere(0.78, 0.92), hull, Vector3(0, 0.02, 0))
	part(root, torus(0.72, 1.08), gun, Vector3(0, -0.04, 0))
	part(root, sphere(0.38, 0.5), m("2a6a88", 0.7, 0.0, 40.0, 1.0), Vector3(0, 0.4, -0.04))
	part(root, cyl(0.27, 0.27, 0.2), dark, Vector3(0, 0.02, 0.64), Vector3(90, 0, 0))
	part(root, sphere(0.19), glow("ff3020", f), Vector3(0, 0.02, 0.72))
	for s in [-1.0, 1.0]:
		part(root, capsule(0.15, 0.72), gun, Vector3(s * 0.98, -0.1, -0.05), Vector3(90, 0, 0))
		part(root, sphere(0.1), glow("ff8a20" if f == 0 else "ffc040", f),
			Vector3(s * 0.98, -0.1, -0.44))
	part(root, cyl(0.3, 0.38, 0.24), dark, Vector3(0, -0.38, 0))
	part(root, cyl(0.03, 0.03, 0.42), gun, Vector3(0.22, 0.62, -0.18))
	part(root, sphere(0.07), glow("ff3020", f), Vector3(0.22, 0.85, -0.18))


## Interceptor: slim green fuselage, swept chrome wings, cyan canopy, twin burners.
static func _weaver(root: Node3D, f: int) -> void:
	var body := m("2ed070", 0.35, 0.0, 34.0)
	var wing := m("a8b0c4", 0.55)
	var gun := m("3a4458", 0.2)
	part(root, capsule(0.2, 1.7), body, Vector3(0, 0, -0.05), Vector3(90, 0, 0))
	part(root, cyl(0.0, 0.2, 0.5), body, Vector3(0, 0, 1.05), Vector3(90, 0, 0))
	part(root, sphere(0.16, 0.26), m("40f0ff", 0.6, 0.5, 40.0, 1.0), Vector3(0, 0.15, 0.35))
	for s in [-1.0, 1.0]:
		part(root, box(1.15, 0.06, 0.5), wing, Vector3(s * 0.62, -0.02, -0.3), Vector3(0, s * 24, 0))
		part(root, box(0.16, 0.08, 0.3), glow("ff3040", f), Vector3(s * 1.16, -0.02, -0.62))
		part(root, cyl(0.12, 0.12, 0.34), gun, Vector3(s * 0.22, 0, -0.88), Vector3(90, 0, 0))
		part(root, sphere(0.11 if f == 0 else 0.14), glow("ff9020", f),
			Vector3(s * 0.22, 0, -1.07))
	part(root, box(0.06, 0.42, 0.42), wing, Vector3(0, 0.26, -0.72), Vector3(-20, 0, 0))


## Juggernaut: heavy blue plate, shoulder cannons, a red visor slit, stomping legs.
static func _hulk(root: Node3D, f: int) -> void:
	var plate := m("3a58d0", 0.3, 0.0, 22.0)
	var plate2 := m("5a78e8", 0.3, 0.0, 22.0)
	var steel := m("b8c0d0", 0.55)
	var gun := m("3a4050", 0.2)
	part(root, box(1.3, 1.0, 1.0), plate, Vector3(0, 0.1, 0))
	part(root, box(1.0, 0.5, 0.22), plate2, Vector3(0, 0.22, 0.56))
	part(root, box(0.72, 0.14, 0.1), glow("ff2a20", f), Vector3(0, 0.36, 0.68))
	part(root, box(0.42, 0.32, 0.42), plate, Vector3(0, 0.74, 0.06))
	for s in [-1.0, 1.0]:
		part(root, box(0.5, 0.52, 0.8), steel, Vector3(s * 0.9, 0.36, 0), Vector3(0, 0, -s * 12))
		part(root, cyl(0.12, 0.12, 0.8), gun, Vector3(s * 0.9, 0.0, 0.42), Vector3(90, 0, 0))
		part(root, sphere(0.085), glow("ff9020", f), Vector3(s * 0.9, 0.0, 0.84))
		var lift: float = 0.04 * s * (1 if f == 0 else -1)
		part(root, box(0.36, 0.6, 0.46), gun, Vector3(s * 0.4, -0.66 + lift, 0))
		part(root, box(0.46, 0.15, 0.62), steel, Vector3(s * 0.4, -0.98 + lift, 0.06))


## Wall gun pod: octagonal mount plate, chrome dome, twin barrels, targeting eye.
static func _turret(root: Node3D, f: int) -> void:
	var mount := m("4a5468", 0.2)
	var steel := m("9aa6c0", 0.5)
	part(root, cyl(0.95, 0.95, 0.22, 8), mount, Vector3(0, 0, -0.55), Vector3(90, 22.5, 0))
	part(root, torus(0.58, 0.82), steel, Vector3(0, 0, -0.38), Vector3(90, 0, 0))
	part(root, sphere(0.56), steel, Vector3(0, 0, -0.22))
	for s in [-1.0, 1.0]:
		part(root, cyl(0.08, 0.08, 0.95), m("262c3a", 0.2), Vector3(s * 0.19, -0.05, 0.36),
			Vector3(90, 0, 0))
		part(root, sphere(0.07), glow("ff8a20", f), Vector3(s * 0.19, -0.05, 0.84))
	part(root, sphere(0.13), glow("ff2020" if f == 0 else "ff8080", f), Vector3(0, 0.26, 0.28))
	for a in 8:
		var ang := a * TAU / 8.0 + TAU / 16.0
		part(root, box(0.14, 0.14, 0.06), glow("eac21a", 0),
			Vector3(cos(ang) * 0.84, sin(ang) * 0.84, -0.42))


## Stinger (new): a wasp-striped kamikaze — needle nose, red eyes, flapping wings.
static func _stinger(root: Node3D, f: int) -> void:
	var gold := m("eac21a", 0.35, 0.0, 30.0)
	var black := m("1c1a20", 0.3)
	part(root, sphere(0.34), gold, Vector3(0, 0, 0.18))
	part(root, sphere(0.42, 0.84), black, Vector3(0, 0, -0.5), Vector3.ZERO, Vector3(1, 1, 1.45))
	for z in [-0.28, -0.62]:
		part(root, torus(0.36, 0.47), gold, Vector3(0, 0, z), Vector3(90, 0, 0), Vector3(1, 1, 0.9))
	part(root, sphere(0.25), black, Vector3(0, 0.02, 0.58))
	for s in [-1.0, 1.0]:
		part(root, sphere(0.1), glow("ff2020", f), Vector3(s * 0.13, 0.1, 0.74))
	part(root, cyl(0.0, 0.08, 0.55), m("d8e0f0", 0.7), Vector3(0, 0, 1.0), Vector3(90, 0, 0))
	var flap := 34.0 if f == 0 else 10.0
	for s in [-1.0, 1.0]:
		for z in [0.22, -0.12]:
			part(root, box(0.92, 0.03, 0.34), m("9ad8ff", 0.6, 0.15, 40.0, 1.0),
				Vector3(s * 0.5, 0.26, z), Vector3(0, 0, s * flap))


## Spinner (new): a magenta core inside a cage, a turning ring of emitters.
static func _spinner(root: Node3D, f: int) -> void:
	part(root, sphere(0.36), glow("e03cb0" if f == 0 else "ff80e0", f), Vector3.ZERO)
	part(root, torus(0.44, 0.54), m("9aa6c0", 0.6), Vector3.ZERO, Vector3(90, 0, 0))
	part(root, torus(0.44, 0.54), m("9aa6c0", 0.6), Vector3.ZERO, Vector3(90, 90, 0))
	var ring := m("4a5468", 0.3)
	part(root, torus(0.86, 1.04, 32), ring, Vector3.ZERO)
	var turn := 0.0 if f == 0 else 45.0
	for a in 4:
		var ang := deg_to_rad(a * 90.0 + turn)
		part(root, sphere(0.15), glow("ff9020", f), Vector3(cos(ang) * 0.95, 0, sin(ang) * 0.95))


## Mine (new): a spiked chrome ball with a blinking red band.
static func _mine(root: Node3D, f: int) -> void:
	var steel := m("7a8298", 0.55)
	part(root, sphere(0.52), steel, Vector3.ZERO)
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD,
		Vector3.BACK, Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
		Vector3(1, 1, -1), Vector3(-1, 1, -1), Vector3(1, -1, -1), Vector3(-1, -1, -1)]
	for d in dirs:
		var dn: Vector3 = d.normalized()
		var spike := part(root, cyl(0.0, 0.09, 0.42), m("c8d0e0", 0.7), dn * 0.62)
		# a cone's tip is its +Y end; turn +Y onto the spike direction (the model
		# is not in the tree yet, so no look_at — it needs a global transform)
		var q := Quaternion(Vector3.UP, dn) if dn.dot(Vector3.UP) > -0.99 \
			else Quaternion(Vector3.RIGHT, PI)
		spike.transform = Transform3D(Basis(q), dn * 0.62)
	part(root, torus(0.5, 0.58), glow("ff2020", 1) if f == 0 else m("401010", 0.1),
		Vector3.ZERO)


# ---------------------------------------------------------------- bosses

## Dock Sentinel (L3): an armored warship, eye bank across the brow, mantis claws.
static func _sentinel(root: Node3D, f: int) -> void:
	var hull := m("8a96b0", 0.45, 0.0, 24.0)
	var deck := m("5a6680", 0.3)
	var dark := m("222838", 0.2)
	part(root, box(1.9, 0.62, 1.2), hull, Vector3(0, -0.05, 0))
	part(root, box(1.3, 0.4, 0.95), deck, Vector3(0, 0.44, -0.05))
	part(root, sphere(0.34, 0.5), m("40c8f0", 0.7, 0.35, 40.0, 1.0), Vector3(0, 0.72, 0.05))
	part(root, box(1.5, 0.22, 0.1), dark, Vector3(0, 0.12, 0.62))
	for k in 5:
		part(root, sphere(0.085), glow("ff2a20", f), Vector3(-0.56 + k * 0.28, 0.12, 0.68))
	for s in [-1.0, 1.0]:
		part(root, box(0.26, 0.3, 1.45), deck, Vector3(s * 1.12, -0.24, 0.28), Vector3(0, s * 10, 0))
		part(root, cyl(0.0, 0.14, 0.45), m("d8e0f0", 0.7), Vector3(s * 1.22, -0.24, 1.1),
			Vector3(90, 0, 0))
		part(root, cyl(0.2, 0.2, 0.5), dark, Vector3(s * 0.5, 0.0, -0.78), Vector3(90, 0, 0))
		part(root, sphere(0.17 if f == 0 else 0.21), glow("ff9020", f), Vector3(s * 0.5, 0, -1.03))
	for k in 4:
		part(root, box(0.22, 0.08, 0.3), glow("ffb030" if (k + f) % 2 == 0 else "ff7010", 1),
			Vector3(-0.45 + k * 0.3, -0.38, 0.35))


## Brood Mother (L6): a bloated hive queen — glowing egg sacs, chitin, mandibles.
static func _brood(root: Node3D, f: int) -> void:
	var flesh := m("d07080", 0.25, 0.0, 16.0, 0.9)
	var chitin := m("6a2a90", 0.45, 0.0, 30.0)
	var bone := m("e8d8b0", 0.3)
	part(root, sphere(0.72), flesh, Vector3(0, -0.05, -0.3), Vector3.ZERO, Vector3(1.15, 0.9, 1.25))
	var sacs := [Vector3(0.62, 0.2, -0.2), Vector3(-0.62, 0.2, -0.2), Vector3(0.5, -0.35, -0.55),
		Vector3(-0.5, -0.35, -0.55), Vector3(0.0, 0.55, -0.45), Vector3(0.3, 0.45, 0.05),
		Vector3(-0.3, 0.45, 0.05)]
	for p in sacs:
		part(root, sphere(0.15 if f == 0 else 0.17), glow("9ad62a", f), p)
	part(root, sphere(0.42), chitin, Vector3(0, 0.12, 0.52))
	part(root, sphere(0.3), chitin, Vector3(0, 0.2, 0.92))
	for s in [-1.0, 1.0]:
		part(root, sphere(0.07), glow("ff2020", f), Vector3(s * 0.12, 0.3, 1.18))
		part(root, sphere(0.05), glow("ff2020", f), Vector3(s * 0.24, 0.22, 1.12))
		part(root, cyl(0.0, 0.07, 0.4), bone, Vector3(s * 0.16, 0.02, 1.25),
			Vector3(90, 0, s * (18 if f == 0 else 30)))
		for k in 3:
			part(root, capsule(0.06, 1.0), bone, Vector3(s * 0.5, -0.1, 0.55 - k * 0.32),
				Vector3(0, s * (20 - k * 20), s * -55))
	for k in 3:
		part(root, cyl(0.0, 0.08, 0.35), chitin, Vector3(-0.2 + k * 0.2, 0.62, 0.52), Vector3(-20, 0, 0))


## The Rift Maw (L9): a toothed ring holding a white-hot core, horns at the diagonals.
static func _maw(root: Node3D, f: int) -> void:
	var ring := m("4a2a7a", 0.5, 0.0, 30.0)
	var horn := m("9a70e0", 0.6, 0.0, 34.0)
	part(root, torus(0.56, 1.02, 32), ring, Vector3.ZERO, Vector3(90, 0, 0))
	for k in 12:
		var a := k * TAU / 12.0
		var p := Vector3(cos(a) * 0.62, sin(a) * 0.62, 0.0)
		var tooth := part(root, cyl(0.0, 0.08, 0.3), m("f0e8d0", 0.4), p)
		tooth.rotation = Vector3(0, 0, a + PI / 2.0)
	part(root, sphere(0.3 if f == 0 else 0.36), glow("c8fcff", f), Vector3.ZERO)
	part(root, sphere(0.42), glow("22c4d8", 0), Vector3(0, 0, -0.18))
	for k in 4:
		var a := k * TAU / 4.0 + TAU / 8.0
		var h := part(root, cyl(0.0, 0.16, 0.6), horn, Vector3(cos(a) * 1.1, sin(a) * 1.1, 0))
		h.rotation = Vector3(0, 0, a - PI / 2.0)
	for k in 3:
		part(root, sphere(0.07), glow("ff40c0", f), Vector3(-0.3 + k * 0.3, 0.9, 0.22))


# ---------------------------------------------------------------- pickups + props

static func _pickup(root: Node3D, kind: String) -> void:
	var ring := m("c8d0e0", 0.7)
	match kind:
		"shield":
			part(root, box(0.9, 0.3, 0.22), m("37ff9a", 0.3, 0.45), Vector3.ZERO)
			part(root, box(0.3, 0.9, 0.22), m("37ff9a", 0.3, 0.45), Vector3.ZERO)
			part(root, torus(0.72, 0.86), ring, Vector3.ZERO, Vector3(90, 0, 0))
		"energy":
			part(root, cyl(0.0, 0.56, 0.8, 6), m("22c4d8", 0.5, 0.4, 40.0, 1.0), Vector3(0, 0.4, 0))
			part(root, cyl(0.56, 0.0, 0.8, 6), m("0b8aa0", 0.5, 0.3, 40.0, 1.0), Vector3(0, -0.4, 0))
		"missile":
			for x in [-0.32, 0.0, 0.32]:
				part(root, capsule(0.13, 0.95), m("b8c0d0", 0.5), Vector3(x, -0.05, 0))
				part(root, sphere(0.13), m("e8302a", 0.4, 0.2), Vector3(x, 0.4, 0))
			part(root, box(0.95, 0.18, 0.3), m("3a4458", 0.2), Vector3(0, -0.3, 0))
		"bomb":
			part(root, sphere(0.48), m("f07818", 0.2, 0.7), Vector3.ZERO)
			part(root, sphere(0.28), glow("fffcd0", 1), Vector3(0, 0, 0.3))
			part(root, torus(0.5, 0.62), m("3a4050", 0.3), Vector3.ZERO, Vector3(70, 0, 0))
		"salvage":
			part(root, cyl(0.52, 0.52, 0.3, 12), m("ffd040", 0.4, 0.15, 34.0), Vector3.ZERO,
				Vector3(90, 0, 0))
			for k in 8:
				var a := k * TAU / 8.0
				var t := part(root, box(0.22, 0.22, 0.26), m("f0c030", 0.4, 0.1),
					Vector3(cos(a) * 0.62, sin(a) * 0.62, 0))
				t.rotation.z = a
			part(root, cyl(0.18, 0.18, 0.3, 12), m("5a3e1c", 0.3), Vector3.ZERO, Vector3(90, 0, 0))
		"overdrive":
			var bolt := m("ff4030", 0.2, 0.6)
			part(root, box(0.22, 0.55, 0.2), bolt, Vector3(0.1, 0.28, 0), Vector3(0, 0, -25))
			part(root, box(0.5, 0.16, 0.2), bolt, Vector3(0, 0.0, 0))
			part(root, box(0.22, 0.55, 0.2), bolt, Vector3(-0.1, -0.28, 0), Vector3(0, 0, -25))
			part(root, torus(0.72, 0.86), m("eac21a", 0.6), Vector3.ZERO, Vector3(90, 0, 0))
		"phase":
			part(root, sphere(0.62), m("4c7ce8", 0.85, 0.25, 50.0, 1.2), Vector3.ZERO)
			part(root, torus(0.64, 0.74), glow("c8e0ff", 1), Vector3.ZERO, Vector3(20, 0, 0))
		"powercore":
			part(root, cyl(0.0, 0.46, 0.58, 4), m("8a5ae8", 0.5, 0.35, 40.0, 1.0), Vector3(0, 0.29, 0))
			part(root, cyl(0.46, 0.0, 0.58, 4), m("5a2ac0", 0.5, 0.3, 40.0, 1.0), Vector3(0, -0.29, 0))
			part(root, torus(0.76, 0.88), m("e03cb0", 0.3, 0.5), Vector3.ZERO, Vector3(90, 0, 0))


## K3 fuel cell: a hazard-banded canister with a hot core window.
static func _fuel_cell(root: Node3D) -> void:
	part(root, cyl(0.42, 0.42, 1.25), m("7a8298", 0.45), Vector3.ZERO)
	part(root, cyl(0.46, 0.46, 0.16), m("f0a020", 0.3), Vector3(0, 0.35, 0))
	part(root, cyl(0.46, 0.46, 0.16), m("f0a020", 0.3), Vector3(0, -0.35, 0))
	part(root, cyl(0.3, 0.42, 0.14), m("3a4458", 0.3), Vector3(0, 0.68, 0))
	part(root, box(0.3, 0.26, 0.1), glow("ff4020", 1), Vector3(0, 0, 0.42))
