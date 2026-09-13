class_name Vis
extends RefCounted

## Material library + procedural mesh helpers.
## All 3D geometry is generated in code; nothing is placed by hand in the scene.

static var _cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


# =============================================================================
# Procedural textures — for a real material feel
# =============================================================================

## Brushed stainless: fine unidirectional lines (roughness map).
static func tex_brushed() -> ImageTexture:
	if _tex_cache.has("brushed"):
		return _tex_cache["brushed"]
	var n := 256
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20240816
	# a base brightness per column -> vertical brush grain
	var cols := PackedFloat32Array()
	cols.resize(n)
	for x in n:
		cols[x] = rng.randf_range(0.80, 1.0)
	for x in n:
		# smooth against neighbouring columns — real satin grain is fine
		var v := (cols[x] * 2.0 + cols[(x + n - 1) % n] + cols[(x + 1) % n]) * 0.25
		for y in n:
			var g: float = clampf(v + rng.randf_range(-0.018, 0.018), 0.0, 1.0)
			img.set_pixel(x, y, Color(g, g, g))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache["brushed"] = t
	return t


## Dark granite: speckled albedo.
static func tex_granite() -> ImageTexture:
	if _tex_cache.has("granite"):
		return _tex_cache["granite"]
	var n := 256
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7781
	for y in n:
		for x in n:
			var g := 0.14 + rng.randf_range(-0.03, 0.03)
			img.set_pixel(x, y, Color(g * 1.02, g, g * 0.97))
	# light and dark speckles
	for i in range(1400):
		var cx := rng.randi_range(0, n - 1)
		var cy := rng.randi_range(0, n - 1)
		var r := rng.randi_range(1, 3)
		var c := Color(0.42, 0.42, 0.44) if rng.randf() < 0.55 else Color(0.05, 0.05, 0.06)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r:
					img.set_pixel((cx + dx + n) % n, (cy + dy + n) % n, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache["granite"] = t
	return t


## Light marble: albedo with soft veining.
static func tex_marble() -> ImageTexture:
	if _tex_cache.has("marble"):
		return _tex_cache["marble"]
	var n := 256
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 991
	noise.frequency = 0.030
	noise.fractal_octaves = 4
	for y in n:
		for x in n:
			var v := noise.get_noise_2d(float(x), float(y) * 0.45)
			var g: float = clampf(0.62 + v * 0.07, 0.0, 1.0)
			# thin veins
			if absf(v) < 0.012:
				g = clampf(g - 0.10, 0.0, 1.0)
			img.set_pixel(x, y, Color(g, g * 0.995, g * 0.97))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex_cache["marble"] = t
	return t


static func mat(name: String) -> StandardMaterial3D:
	if _cache.has(name):
		return _cache[name]

	var m := StandardMaterial3D.new()
	match name:
		"concrete":
			m.albedo_color = Color(0.42, 0.43, 0.45)
			m.roughness = 0.95
		"concrete_dark":
			m.albedo_color = Color(0.20, 0.21, 0.23)
			m.roughness = 0.95
		"slab":
			m.albedo_color = Color(0.55, 0.55, 0.57)
			m.roughness = 0.85
		"steel":
			m.albedo_color = Color(0.62, 0.65, 0.69)
			m.metallic = 0.85
			m.roughness = 0.32
		"steel_dark":
			m.albedo_color = Color(0.24, 0.26, 0.29)
			m.metallic = 0.75
			m.roughness = 0.45
		"steel_brushed":
			m.albedo_color = Color(0.70, 0.72, 0.75)
			m.metallic = 0.90
			m.roughness = 0.22
		"rail":
			m.albedo_color = Color(0.45, 0.47, 0.50)
			m.metallic = 0.95
			m.roughness = 0.18
		"rubber":
			m.albedo_color = Color(0.09, 0.09, 0.10)
			m.roughness = 1.0
		"glass":
			m.albedo_color = Color(0.55, 0.72, 0.80, 0.20)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.35
			m.roughness = 0.05
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glass_dark":
			m.albedo_color = Color(0.15, 0.18, 0.22, 0.35)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic = 0.5
			m.roughness = 0.08
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"tile":
			m.albedo_color = Color(0.74, 0.73, 0.70)
			m.roughness = 0.35
			m.metallic = 0.05
		"tile_dark":
			m.albedo_color = Color(0.30, 0.31, 0.33)
			m.roughness = 0.40
		"wood":
			m.albedo_color = Color(0.36, 0.24, 0.15)
			m.roughness = 0.65
		"panel":
			m.albedo_color = Color(0.16, 0.17, 0.19)
			m.metallic = 0.4
			m.roughness = 0.4
		"rope":                     # galvanised steel rope
			m.albedo_color = Color(0.40, 0.40, 0.38)
			m.metallic = 0.85
			m.roughness = 0.42
		"motor":                    # PM disc motor body (cast, painted)
			m.albedo_color = Color(0.22, 0.25, 0.29)
			m.metallic = 0.35
			m.roughness = 0.55
		"motor_fin":
			m.albedo_color = Color(0.30, 0.33, 0.37)
			m.metallic = 0.45
			m.roughness = 0.48
		"brake_disc":
			m.albedo_color = Color(0.52, 0.53, 0.55)
			m.metallic = 0.90
			m.roughness = 0.30
		"caliper":
			m.albedo_color = Color(0.62, 0.28, 0.12)   # orange brake caliper
			m.metallic = 0.30
			m.roughness = 0.50
		"bedplate":
			m.albedo_color = Color(0.30, 0.31, 0.33)
			m.metallic = 0.60
			m.roughness = 0.55
		"led_off":
			m.albedo_color = Color(0.13, 0.14, 0.16)
			m.roughness = 0.5
		# --- real elevator materials -----------------------------------------
		"inox":                     # brushed stainless (satin) - main car finish
			m.albedo_color = Color(0.69, 0.70, 0.72)
			m.metallic = 0.96
			m.roughness = 0.56
			m.metallic_specular = 0.42
			m.roughness_texture = tex_brushed()
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
			m.uv1_scale = Vector3(11, 11, 1)
		"inox_dark":                # darker brushed (door header, jamb)
			m.albedo_color = Color(0.48, 0.49, 0.51)
			m.metallic = 0.95
			m.metallic_specular = 0.40
			m.roughness = 0.60
			m.roughness_texture = tex_brushed()
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
			m.uv1_scale = Vector3(11, 11, 1)
		"braille":                  # raised braille dots
			# Same stainless as the panel, but no brush grain: the grain is
			# coarser than a 1.5 mm dot, and dots on a panel in daily use get
			# polished by fingertips, so they read a little brighter.
			m.albedo_color = Color(0.74, 0.75, 0.77)
			m.metallic = 0.94
			m.metallic_specular = 0.60
			m.roughness = 0.28
		"inox_line":                # panel reveal line
			m.albedo_color = Color(0.18, 0.19, 0.20)
			m.metallic = 0.70
			m.roughness = 0.55
		"mirror":                   # car rear wall mirror (faint green glass tint)
			m.albedo_color = Color(0.86, 0.90, 0.87)
			m.metallic = 1.0
			m.roughness = 0.06
		"granite":                  # car floor - dark granite
			m.albedo_color = Color(1, 1, 1)
			m.albedo_texture = tex_granite()
			m.metallic = 0.04
			m.roughness = 0.28
			m.uv1_scale = Vector3(4, 4, 1)
		"granite_edge":
			m.albedo_color = Color(0.62, 0.60, 0.56)
			m.metallic = 0.10
			m.roughness = 0.30
		"display_glass":            # indicator cover glass
			m.albedo_color = Color(0.03, 0.03, 0.035)
			m.metallic = 0.20
			m.roughness = 0.12
		"ceiling":                  # car false ceiling
			m.albedo_color = Color(0.88, 0.89, 0.90)
			m.metallic = 0.30
			m.roughness = 0.45
		"marble":                   # landing floor
			m.albedo_color = Color(1, 1, 1)
			m.albedo_texture = tex_marble()
			m.metallic = 0.05
			m.roughness = 0.24
			m.uv1_scale = Vector3(5, 5, 1)
		"wall_paint":               # landing wall
			m.albedo_color = Color(0.56, 0.555, 0.545)
			m.roughness = 0.85
		"car_shell":
			m.albedo_color = Color(0.26, 0.34, 0.44)
			m.metallic = 0.65
			m.roughness = 0.30
		"cwt":
			m.albedo_color = Color(0.28, 0.30, 0.33)
			m.metallic = 0.7
			m.roughness = 0.55
		"ground":
			m.albedo_color = Color(0.30, 0.31, 0.32)
			m.roughness = 0.95
		_:
			m.albedo_color = Color(0.8, 0.8, 0.8)

	_cache[name] = m
	return m


static func emissive(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "em_%s_%.2f" % [color.to_html(false), energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	_cache[key] = m
	return m


# =============================================================================
# Mesh helpers
# =============================================================================
## Meshes of identical size are shared: this cuts both the resource count and
## the draw calls (Godot can instance the same mesh+material pair).
## Pass shared=false if you are going to MUTATE the mesh afterwards, otherwise
## every instance sharing it changes with it.
static var _mesh_cache: Dictionary = {}

## Small details cast no shadow: the shadow pass multiplies draw calls, while
## the shadow of a 2 cm screw contributes nothing visually.
const SHADOW_MIN_SIZE := 0.26


static func _apply_shadow(mi: MeshInstance3D, biggest: float) -> void:
	if biggest < SHADOW_MIN_SIZE:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func box(parent: Node3D, size: Vector3, pos: Vector3,
		m: Material, name := "", shared := true) -> MeshInstance3D:
	var mesh: BoxMesh
	var key := "b:%.4f,%.4f,%.4f" % [size.x, size.y, size.z]
	if shared and _mesh_cache.has(key):
		mesh = _mesh_cache[key]
	else:
		mesh = BoxMesh.new()
		mesh.size = size
		if shared:
			_mesh_cache[key] = mesh

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	_apply_shadow(mi, maxf(size.x, maxf(size.y, size.z)))
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi


static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3,
		m: Material, name := "", shared := true) -> MeshInstance3D:
	var mesh: CylinderMesh
	var key := "c:%.4f,%.4f" % [radius, height]
	if shared and _mesh_cache.has(key):
		mesh = _mesh_cache[key]
	else:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		# fewer radial segments on thin parts (no visible difference)
		mesh.radial_segments = 20 if radius > 0.05 else 10
		mesh.rings = 1
		if shared:
			_mesh_cache[key] = mesh

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	_apply_shadow(mi, maxf(radius * 2.0, height))
	if name != "":
		mi.name = name
	parent.add_child(mi)
	return mi


## A raised, domed dot (braille). The profile matters: a braille dot is read by
## sliding a fingertip across it, so it is a hemisphere, not a flat disc.
static func dome(parent: Node3D, radius: float, height: float, pos: Vector3,
		m: Material) -> MeshInstance3D:
	var mesh: SphereMesh
	var key := "d:%.5f,%.5f" % [radius, height]
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key]
	else:
		mesh = SphereMesh.new()
		mesh.radius = radius
		mesh.height = height * 2.0        # is_hemisphere keeps the upper half
		mesh.is_hemisphere = true
		mesh.radial_segments = 10
		mesh.rings = 4
		_mesh_cache[key] = mesh

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	_apply_shadow(mi, maxf(radius * 2.0, height))
	parent.add_child(mi)
	return mi


## A cylinder between two points (rope segment, profile, tie rod).
static func rod(parent: Node3D, p1: Vector3, p2: Vector3, radius: float,
		m: Material) -> MeshInstance3D:
	var d := p2 - p1
	var len := d.length()
	if len < 1e-6:
		len = 1e-6

	# There are hundreds of arc segments, mostly the same length -> sharing is key
	var mesh: CylinderMesh
	var key := "r:%.4f,%.4f" % [radius, len]
	if _mesh_cache.has(key):
		mesh = _mesh_cache[key]
	else:
		mesh = CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = len
		mesh.radial_segments = 8
		mesh.rings = 1
		_mesh_cache[key] = mesh

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var dir := d / len
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.999:
		up = Vector3.RIGHT
	var b := Basis()
	b.y = dir
	b.x = up.cross(dir).normalized()
	b.z = b.x.cross(b.y)
	mi.transform = Transform3D(b, p1 + d * 0.5)
	parent.add_child(mi)
	return mi


## An arc in the YZ plane (rope wrap over a sheave).
## Angle 0 = +Z direction, 90 = +Y (top).  x stays constant.
static func arc_yz(parent: Node3D, x: float, cy: float, cz: float, radius: float,
		from_deg: float, to_deg: float, segments: int, thickness: float,
		m: Material) -> void:
	var prev := Vector3.ZERO
	for i in range(segments + 1):
		var t := float(i) / float(segments)
		var a := deg_to_rad(lerpf(from_deg, to_deg, t))
		var p := Vector3(x, cy + radius * sin(a), cz + radius * cos(a))
		if i > 0:
			rod(parent, prev, p, thickness, m)
		prev = p


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3,
		m: Material) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


static func label(parent: Node3D, text: String, pos: Vector3, size: float,
		color: Color = Color.WHITE) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.pixel_size = size
	l.font_size = 64
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.modulate = color
	l.position = pos
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.double_sided = true
	l.shaded = false
	l.no_depth_test = false
	parent.add_child(l)
	return l
