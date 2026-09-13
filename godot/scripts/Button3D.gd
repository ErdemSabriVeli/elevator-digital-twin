class_name Btn3D
extends Area3D

## A realistic modern elevator button (Schindler/Otis style):
##   - stainless bezel
##   - slightly recessed brushed cap with an engraved numeral
##   - illuminated halo ring around the cap (lit while the call is registered)
##   - optional braille label to its left (ADA 407.4.7.1.2)

signal pushed(key: String)

const HALO_OFF   := Color(0.10, 0.10, 0.11)
const HALO_HOVER := Color(0.42, 0.46, 0.52)
const HALO_ON    := Color(1.00, 0.72, 0.30)     # warm amber - a common choice

## Clear space between the button and its braille (ADA 703.3.2 asks 9.5 mm min).
const BRAILLE_GAP := 0.010

var key := ""
var _halo: MeshInstance3D
var _cap: MeshInstance3D
var _cap_z := 0.0
var _lit := false
var _hover := false
var _flash := 0.0


static func create(parent: Node3D, p_key: String, pos: Vector3,
		text := "", radius := 0.045, face_z := 1.0, braille := "") -> Btn3D:
	var b := Btn3D.new()
	b.key = p_key
	b.position = pos
	parent.add_child(b)

	var fz: float = signf(face_z)

	# --- stainless bezel --------------------------------------------------
	var bezel := Vis.torus(b, radius * 0.92, radius * 1.18,
			Vector3(0, 0, 0.004 * fz), Vis.mat("inox"))
	bezel.rotation_degrees = Vector3(90, 0, 0)

	# --- illuminated halo --------------------------------------------------------
	b._halo = Vis.torus(b, radius * 0.74, radius * 0.93,
			Vector3(0, 0, 0.005 * fz), Vis.emissive(HALO_OFF, 0.12))
	b._halo.rotation_degrees = Vector3(90, 0, 0)

	# --- button cap (slightly recessed) ----------------------------------------
	b._cap_z = 0.002 * fz
	b._cap = Vis.cyl(b, radius * 0.76, 0.008, Vector3(0, 0, b._cap_z),
			Vis.mat("inox_dark"))
	b._cap.rotation_degrees = Vector3(90, 0, 0)
	# cap face (light satin finish)
	var face := Vis.cyl(b, radius * 0.70, 0.004, Vector3(0, 0, b._cap_z + 0.003 * fz),
			Vis.mat("inox"))
	face.rotation_degrees = Vector3(90, 0, 0)

	# --- engraved numeral -----------------------------------------------------
	if text != "":
		# Engraved numeral: glyph height ~85 % of the button diameter
		var l := Vis.label(b, text, Vector3(0, 0, b._cap_z + 0.007 * fz),
				radius * 0.0072, Color(0.12, 0.12, 0.13))
		l.font_size = 120
		l.outline_size = 0
		if fz < 0:
			l.rotation_degrees = Vector3(0, 180, 0)

	# --- braille -------------------------------------------------------------
	# ADA 407.4.7.1.2 puts the braille immediately to the LEFT of its control,
	# and 703.3.2 asks for at least 9.5 mm of clear space from the character it
	# labels, so the block is right-aligned against the button and grows away
	# from it. Sizes and spacing live in Braille.gd, straight from the spec.
	if braille != "":
		var n := Braille.cells(braille).size()
		var x_right := -(radius + BRAILLE_GAP)
		Braille.render(b, braille,
				Vector3((x_right - Braille.width(n)) * fz,
						Braille.height() * 0.5,
						b._cap_z + 0.0015 * fz),
				fz, Vis.mat("braille"))

	# --- click area ------------------------------------------------------
	var shape := CollisionShape3D.new()
	var sp := BoxShape3D.new()
	sp.size = Vector3(radius * 2.6, radius * 2.6, 0.05)
	shape.shape = sp
	b.add_child(shape)

	# The button is only hit by a mouse ray; overlap monitoring is not needed.
	# Leaving monitoring/monitorable on costs a pointless overlap query every
	# physics step.
	b.monitoring = false
	b.monitorable = false
	b.input_ray_pickable = true
	b.input_event.connect(b._on_input_event)
	b.mouse_entered.connect(b._on_hover.bind(true))
	b.mouse_exited.connect(b._on_hover.bind(false))
	return b


func set_lit(on: bool) -> void:
	if on == _lit:
		return
	_lit = on
	_refresh()


func _on_hover(v: bool) -> void:
	_hover = v
	_refresh()


func _on_input_event(_cam: Node, event: InputEvent, _pos: Vector3,
		_normal: Vector3, _idx: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_flash = 0.12
			pushed.emit(key)


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash -= delta
	if _flash <= 0.0:
		_refresh()
	else:
		_halo.material_override = Vis.emissive(Color(1.0, 0.92, 0.75), 4.0)
		_cap.position.z = _cap_z * 0.2 - signf(_cap_z) * 0.004


func _refresh() -> void:
	if _lit:
		_halo.material_override = Vis.emissive(HALO_ON, 3.4)
	elif _hover:
		_halo.material_override = Vis.emissive(HALO_HOVER, 0.9)
	else:
		_halo.material_override = Vis.emissive(HALO_OFF, 0.12)
	_cap.position.z = _cap_z
