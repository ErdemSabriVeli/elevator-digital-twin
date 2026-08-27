class_name CarRig
extends Node3D

## A modern elevator car, built to real dimensions:
##   - brushed stainless (satin inox) wall panels with reveal lines
##   - full-height mirror on the rear wall, round stainless handrail at 900 mm
##   - dark granite floor, stainless skirting
##   - white suspended ceiling + 4 recessed downlights
##   - COP: red dot-matrix indicator, two columns of round buttons, braille,
##     door open/close, alarm, phone grille, key switch
##
## The Y position of the car node = the encoder position (pos_mm / 1000).

const W := LiftCfg.M_CAR_W
const D := LiftCfg.M_CAR_D
const H := LiftCfg.M_CAR_H
const WALL := 0.04
const DOOR_Z := LiftCfg.M_CAR_D * 0.5 + 0.02

const BTN_R := 0.022          # button halo radius (~44 mm diameter)
const COP_X := 0.050          # button column spacing

var door_left: Node3D
var door_right: Node3D
var floor_buttons: Array = []
var btn_open: Btn3D
var btn_close: Btn3D
var btn_alarm: Btn3D
var display: LedDisplay
var load_lbl: Label3D
var cabin_light: OmniLight3D
var ceiling_panel: MeshInstance3D
var spots: Array[MeshInstance3D] = []
var _downlights: Array[OmniLight3D] = []
var overload_lamp: MeshInstance3D
var interior_cam_mount: Node3D
var _overload_txt: Label3D

var _btn_cb: Callable


func build(btn_callback: Callable) -> void:
	_btn_cb = btn_callback
	_build_sling()
	_build_shell()
	_build_interior_finish()
	_build_doors()
	_build_cop()
	_build_ceiling()


# =============================================================================
func _build_sling() -> void:
	Vis.box(self, Vector3(W + 0.24, 0.14, 0.22), Vector3(0, H + 0.22, 0), Vis.mat("steel_dark"))
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.10, H + 0.30, 0.16),
				Vector3(sx * (W * 0.5 + 0.07), H * 0.5 + 0.05, 0), Vis.mat("steel_dark"))
		for sy: float in [0.10, H + 0.12]:
			Vis.box(self, Vector3(0.14, 0.14, 0.20),
					Vector3(sx * (W * 0.5 + 0.16), sy, 0), Vis.mat("rubber"))
	Vis.box(self, Vector3(W + 0.24, 0.12, 0.22), Vector3(0, -0.16, 0), Vis.mat("steel_dark"))

	# --- rope hitch (hitch plate + spring set) ------------------------------
	# On a real elevator every rope attaches to the plate through a compression
	# spring; the springs equalise the load and balance the rope tension.
	var hy := H + 0.34
	var rope_w: float = (LiftCfg.ROPE_COUNT - 1) * LiftCfg.ROPE_PITCH
	Vis.box(self, Vector3(rope_w + 0.16, 0.030, 0.14),
			Vector3(0, hy, LiftCfg.M_ROPE_Z_CAR), Vis.mat("steel"))
	Vis.box(self, Vector3(rope_w + 0.16, 0.030, 0.14),
			Vector3(0, hy - 0.16, LiftCfg.M_ROPE_Z_CAR), Vis.mat("steel"))
	for i in range(LiftCfg.ROPE_COUNT):
		var rx: float = (float(i) - (LiftCfg.ROPE_COUNT - 1) * 0.5) * LiftCfg.ROPE_PITCH
		# compression spring
		Vis.cyl(self, 0.014, 0.13, Vector3(rx, hy - 0.08, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel_dark"))
		# rope socket / tension rod
		Vis.cyl(self, 0.006, 0.20, Vector3(rx, hy - 0.06, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel"))
		Vis.cyl(self, 0.011, 0.026, Vector3(rx, hy + 0.020, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel_dark"))
	# beams tying the plate to the car sling
	for sxh: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.05, 0.30, 0.10),
				Vector3(sxh * (rope_w * 0.5 + 0.05), hy - 0.30, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel_dark"))


func _build_shell() -> void:
	# --- floor: dark granite + light border ---------------------------------
	Vis.box(self, Vector3(W, LiftCfg.M_CAR_FLOOR_T, D),
			Vector3(0, -LiftCfg.M_CAR_FLOOR_T * 0.5, 0), Vis.mat("steel_dark"))
	Vis.box(self, Vector3(W - 0.02, 0.02, D - 0.02), Vector3(0, 0.01, 0),
			Vis.mat("granite_edge"))
	Vis.box(self, Vector3(W - 0.16, 0.022, D - 0.16), Vector3(0, 0.012, 0),
			Vis.mat("granite"))

	# --- outer shell (as seen from the shaft) -------------------------------
	Vis.box(self, Vector3(W, 0.08, D), Vector3(0, H + 0.04, 0), Vis.mat("inox_dark"))
	Vis.box(self, Vector3(W, H, WALL), Vector3(0, H * 0.5, -D * 0.5), Vis.mat("inox_dark"))
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(WALL, H, D), Vector3(sx * W * 0.5, H * 0.5, 0),
				Vis.mat("inox_dark"))

	# --- front face: sides and head of the door opening ----------------------
	var side := (W - LiftCfg.M_DOOR_W) * 0.5
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(side, H, WALL),
				Vector3(sx * (LiftCfg.M_DOOR_W * 0.5 + side * 0.5), H * 0.5, D * 0.5),
				Vis.mat("inox"))
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W, H - LiftCfg.M_DOOR_H, WALL),
			Vector3(0, LiftCfg.M_DOOR_H + (H - LiftCfg.M_DOOR_H) * 0.5, D * 0.5),
			Vis.mat("inox"))
	# sill (stainless)
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.10, 0.03, 0.10),
			Vector3(0, 0.015, D * 0.5 - 0.02), Vis.mat("inox"))

	# --- apron (toe guard): below the sill, facing into the shaft -----------
	# On a real elevator this folded sheet stops a passenger falling into the
	# shaft if the car is stranded between floors.
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.22, 0.75, 0.016),
			Vector3(0, -0.375, D * 0.5 + 0.008), Vis.mat("inox_dark"))
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.22, 0.02, 0.06),
			Vector3(0, -0.745, D * 0.5 - 0.022), Vis.mat("inox_dark"))
	for sx4: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.02, 0.75, 0.05),
				Vector3(sx4 * (LiftCfg.M_DOOR_W * 0.5 + 0.10), -0.375, D * 0.5 - 0.018),
				Vis.mat("inox_dark"))

	# --- car top guard rail (an EN 81 requirement) --------------------------
	var rail_h := LiftCfg.M_CARTOP_RAIL
	for sx5: float in [-1.0, 1.0]:
		for sz5: float in [-1.0, 1.0]:
			Vis.cyl(self, 0.018, rail_h,
					Vector3(sx5 * (W * 0.5 - 0.10), H + 0.08 + rail_h * 0.5,
							sz5 * (D * 0.5 - 0.10)), Vis.mat("steel"))
	for sz6: float in [-1.0, 1.0]:
		for hy: float in [rail_h * 0.5, rail_h]:
			var b := Vis.cyl(self, 0.016, W - 0.20,
					Vector3(0, H + 0.08 + hy, sz6 * (D * 0.5 - 0.10)), Vis.mat("steel"))
			b.rotation_degrees = Vector3(0, 0, 90)
	for sx6: float in [-1.0, 1.0]:
		for hy2: float in [rail_h * 0.5, rail_h]:
			var b2 := Vis.cyl(self, 0.016, D - 0.20,
					Vector3(sx6 * (W * 0.5 - 0.10), H + 0.08 + hy2, 0), Vis.mat("steel"))
			b2.rotation_degrees = Vector3(90, 0, 0)

	# car top inspection box
	Vis.box(self, Vector3(0.36, 0.22, 0.16), Vector3(-0.55, H + 0.20, 0.55), Vis.mat("panel"))
	var l := Vis.label(self, "INSPECTION", Vector3(-0.55, H + 0.35, 0.55), 0.00055,
			Color(0.9, 0.7, 0.2))
	l.outline_size = 0


## Car interior finish: inox panels, mirror, handrail, skirting
func _build_interior_finish() -> void:
	var inner_w := W * 0.5 - WALL - 0.005
	var inner_d := D * 0.5 - WALL - 0.005
	var rail_y := 0.90

	# --- rear wall: inox below, mirror above --------------------------------
	Vis.box(self, Vector3(W - 2 * WALL, rail_y - 0.02, 0.012),
			Vector3(0, (rail_y - 0.02) * 0.5, -inner_d), Vis.mat("inox"))
	Vis.box(self, Vector3(W - 2 * WALL - 0.10, H - rail_y - 0.22, 0.010),
			Vector3(0, rail_y + 0.06 + (H - rail_y - 0.22) * 0.5, -inner_d + 0.004),
			Vis.mat("mirror"))
	# mirror frame
	Vis.box(self, Vector3(W - 2 * WALL - 0.06, 0.02, 0.016),
			Vector3(0, rail_y + 0.04, -inner_d + 0.002), Vis.mat("inox"))
	Vis.box(self, Vector3(W - 2 * WALL - 0.06, 0.02, 0.016),
			Vector3(0, H - 0.14, -inner_d + 0.002), Vis.mat("inox"))

	# --- side walls: inox panels with vertical reveals ----------------------
	for sx: float in [-1.0, 1.0]:
		var x := sx * inner_w
		Vis.box(self, Vector3(0.012, H - 0.10, D - 2 * WALL),
				Vector3(x, (H - 0.10) * 0.5, 0), Vis.mat("inox"))
		# panel reveal lines
		for k in range(3):
			var z := -D * 0.5 + 0.42 + k * 0.42
			Vis.box(self, Vector3(0.016, H - 0.14, 0.008),
					Vector3(x - sx * 0.004, (H - 0.14) * 0.5 + 0.02, z), Vis.mat("inox_line"))
		# handrail (round stainless tube)
		var rail := Vis.cyl(self, 0.019, D - 2 * WALL - 0.12,
				Vector3(x - sx * 0.055, rail_y, 0), Vis.mat("inox"))
		rail.rotation_degrees = Vector3(90, 0, 0)
		for sz: float in [-1.0, 1.0]:
			Vis.cyl(self, 0.014, 0.055, Vector3(x - sx * 0.028, rail_y,
					sz * (D * 0.5 - WALL - 0.09)), Vis.mat("inox")).rotation_degrees = \
					Vector3(0, 0, 90)

	# --- rear handrail ------------------------------------------------------
	var brail := Vis.cyl(self, 0.019, W - 2 * WALL - 0.16,
			Vector3(0, rail_y, -inner_d + 0.055), Vis.mat("inox"))
	brail.rotation_degrees = Vector3(0, 0, 90)
	for sx2: float in [-1.0, 1.0]:
		Vis.cyl(self, 0.014, 0.055, Vector3(sx2 * (W * 0.5 - WALL - 0.10), rail_y,
				-inner_d + 0.028), Vis.mat("inox")).rotation_degrees = Vector3(90, 0, 0)

	# --- skirting -----------------------------------------------------------
	Vis.box(self, Vector3(W - 2 * WALL, 0.09, 0.014),
			Vector3(0, 0.045, -inner_d + 0.006), Vis.mat("inox_dark"))
	for sx3: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.014, 0.09, D - 2 * WALL),
				Vector3(sx3 * (inner_w - 0.006), 0.045, 0), Vis.mat("inox_dark"))

	# --- stainless header above the door ------------------------------------
	var fz := D * 0.5 - WALL - 0.006
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.30, 0.11, 0.014),
			Vector3(0, LiftCfg.M_DOOR_H + 0.055, fz), Vis.mat("inox"))
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.30, 0.012, 0.020),
			Vector3(0, LiftCfg.M_DOOR_H + 0.005, fz), Vis.mat("inox_line"))
	# reveal line on the front return panels beside the door
	for sx7: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.012, LiftCfg.M_DOOR_H, 0.018),
				Vector3(sx7 * (LiftCfg.M_DOOR_W * 0.5 + 0.055),
						LiftCfg.M_DOOR_H * 0.5, fz), Vis.mat("inox_line"))

	# --- in-car camera mount point ------------------------------------------
	interior_cam_mount = Node3D.new()
	interior_cam_mount.position = Vector3(-0.62, 1.58, -D * 0.5 + 0.24)
	add_child(interior_cam_mount)


func _build_doors() -> void:
	var lw := LiftCfg.M_DOOR_W * 0.5

	for side in [-1, 1]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * lw * 0.5, 0, DOOR_Z)
		add_child(leaf)
		Vis.box(leaf, Vector3(lw, LiftCfg.M_DOOR_H, LiftCfg.M_DOOR_T),
				Vector3(0, LiftCfg.M_DOOR_H * 0.5, 0), Vis.mat("inox"))
		# door edge profile (closing side)
		Vis.box(leaf, Vector3(0.012, LiftCfg.M_DOOR_H, LiftCfg.M_DOOR_T + 0.006),
				Vector3(-side * (lw * 0.5 - 0.006), LiftCfg.M_DOOR_H * 0.5, 0),
				Vis.mat("inox_dark"))
		# photo curtain bar (on the car side)
		Vis.box(leaf, Vector3(0.016, LiftCfg.M_DOOR_H - 0.18, 0.016),
				Vector3(-side * (lw * 0.5 - 0.012), LiftCfg.M_DOOR_H * 0.5, -0.038),
				Vis.mat("rubber"))
		if side < 0:
			door_left = leaf
		else:
			door_right = leaf

	# door operator (on the car top)
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.3, 0.10, 0.10),
			Vector3(0, H + 0.14, D * 0.5 - 0.05), Vis.mat("steel_dark"))
	Vis.cyl(self, 0.07, 0.10, Vector3(-0.42, H + 0.14, D * 0.5 - 0.05),
			Vis.mat("steel")).rotation_degrees = Vector3(0, 0, 90)


## COP — car operating panel (on the right front return wall)
func _build_cop() -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(W * 0.5 - WALL - 0.012, 0, D * 0.5 - 0.34)
	pivot.rotation_degrees = Vector3(0, -90, 0)
	add_child(pivot)

	# --- panel plate --------------------------------------------------------
	Vis.box(pivot, Vector3(0.24, 1.36, 0.014), Vector3(0, 1.32, 0.007), Vis.mat("inox"))
	Vis.box(pivot, Vector3(0.225, 1.345, 0.004), Vector3(0, 1.32, 0.015),
			Vis.mat("inox_dark"))

	# --- red dot-matrix indicator -------------------------------------------
	Vis.box(pivot, Vector3(0.185, 0.115, 0.006), Vector3(0, 1.86, 0.017),
			Vis.mat("display_glass"))
	display = LedDisplay.create(pivot, Vector3(0, 1.86, 0.021), 0.165)

	# --- floor buttons: 2 columns, bottom to top ----------------------------
	var rows := int(ceil(LiftCfg.FLOOR_COUNT / 2.0))
	floor_buttons.resize(LiftCfg.FLOOR_COUNT)
	for f in range(LiftCfg.FLOOR_COUNT):
		var row := f / 2
		var col := f % 2
		var y := 1.34 + float(row) * 0.078
		var x := (-COP_X if col == 0 else COP_X)
		var b := Btn3D.create(pivot, "car_%d" % f, Vector3(x, y, 0.020),
				LiftIo.floor_name(f), BTN_R, 1.0, true)
		b.pushed.connect(_btn_cb)
		floor_buttons[f] = b
	var _unused := rows

	# --- door open / close / alarm ------------------------------------------
	btn_open = Btn3D.create(pivot, "door_open", Vector3(-COP_X, 1.18, 0.020),
			"<|>", BTN_R * 0.92)
	btn_open.pushed.connect(_btn_cb)
	btn_close = Btn3D.create(pivot, "door_close", Vector3(COP_X, 1.18, 0.020),
			">|<", BTN_R * 0.92)
	btn_close.pushed.connect(_btn_cb)
	btn_alarm = Btn3D.create(pivot, "alarm", Vector3(-COP_X, 1.09, 0.020),
			"!", BTN_R * 0.92)
	btn_alarm.pushed.connect(_btn_cb)

	# key switch (bottom right)
	var ks := Vis.cyl(pivot, 0.015, 0.008, Vector3(COP_X, 1.09, 0.019), Vis.mat("inox_dark"))
	ks.rotation_degrees = Vector3(90, 0, 0)
	Vis.box(pivot, Vector3(0.004, 0.016, 0.004), Vector3(COP_X, 1.09, 0.024),
			Vis.mat("inox_line"))

	# --- emergency phone grille ---------------------------------------------
	for r in range(4):
		for c in range(7):
			Vis.cyl(pivot, 0.0035, 0.004,
					Vector3(-0.048 + c * 0.016, 1.00 - r * 0.014, 0.016),
					Vis.mat("inox_line")).rotation_degrees = Vector3(90, 0, 0)

	# --- overload warning lamp ----------------------------------------------
	overload_lamp = Vis.box(pivot, Vector3(0.104, 0.019, 0.004),
			Vector3(0, 1.762, 0.017), Vis.emissive(Color(0.10, 0.035, 0.03), 0.10))
	_overload_txt = Vis.label(pivot, "OVERLOAD", Vector3(0, 1.762, 0.021), 0.000125,
			Color(0.34, 0.34, 0.35))
	_overload_txt.outline_size = 0

	# --- car rating plate ---------------------------------------------------
	var cap := Vis.label(pivot, "630 kg / 8 persons", Vector3(0, 0.93, 0.018), 0.00013,
			Color(0.28, 0.29, 0.31))
	cap.outline_size = 0

	# --- load readout (on the panel) ----------------------------------------
	load_lbl = Vis.label(pivot, "", Vector3(0, 0.90, 0.018), 0.00012,
			Color(0.34, 0.35, 0.38))
	load_lbl.outline_size = 0


func _build_ceiling() -> void:
	# suspended ceiling
	ceiling_panel = Vis.box(self, Vector3(W - 2 * WALL - 0.04, 0.025, D - 2 * WALL - 0.04),
			Vector3(0, H - 0.05, 0), Vis.mat("ceiling"))
	# perimeter light strip
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.03, 0.02, D - 2 * WALL - 0.10),
				Vector3(sx * (W * 0.5 - WALL - 0.03), H - 0.055, 0),
				Vis.emissive(Color(1.0, 0.96, 0.90), 0.45))

	# 4 recessed downlights — each with its own light, so instead of one big
	# highlight you get four separate soft reflections, as in a real car
	for sx2: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx2 * (W * 0.25), H - 0.062, sz * (D * 0.24))
			var ring := Vis.cyl(self, 0.055, 0.010, p, Vis.mat("inox"))
			var glow := Vis.cyl(self, 0.045, 0.008, p + Vector3(0, -0.004, 0),
					Vis.emissive(Color(1.0, 0.97, 0.92), 0.95))
			spots.append(glow)
			var _r := ring

			var dl := OmniLight3D.new()
			dl.position = p + Vector3(0, -0.05, 0)
			dl.light_energy = 0.62
			dl.omni_range = 2.9
			dl.omni_attenuation = 1.4
			dl.light_color = Color(1.0, 0.97, 0.93)
			dl.shadow_enabled = false
			add_child(dl)
			_downlights.append(dl)

	# general fill (very weak)
	cabin_light = OmniLight3D.new()
	cabin_light.position = Vector3(0, H - 0.60, 0)
	cabin_light.light_energy = 0.35
	cabin_light.omni_range = 3.4
	cabin_light.light_color = Color(0.96, 0.97, 1.0)
	cabin_light.shadow_enabled = false
	add_child(cabin_light)

	# In-car reflection probe: the mirror and stainless surfaces should reflect
	# the car itself, not the shaft or the sky — something screen-space
	# reflection cannot do.
	var probe := ReflectionProbe.new()
	probe.size = Vector3(W + 0.1, H + 0.1, D + 0.1)
	probe.position = Vector3(0, H * 0.5, 0)
	probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	probe.box_projection = true
	probe.interior = true
	probe.intensity = 1.0
	probe.max_distance = 12.0
	add_child(probe)


# =============================================================================
# LIVE UPDATE
# =============================================================================
func set_door(amount: float) -> void:
	var travel := LiftCfg.M_DOOR_W * 0.5 * amount
	door_left.position.x = -LiftCfg.M_DOOR_W * 0.25 - travel
	door_right.position.x = LiftCfg.M_DOOR_W * 0.25 + travel


## These are called every frame; swapping a material (and building the text
## key inside Vis.emissive) must only happen when the state actually CHANGES.
var _light_on := true
var _overload_on := false


func set_light(on: bool) -> void:
	if on == _light_on:
		return
	_light_on = on
	cabin_light.visible = on
	for d in _downlights:
		d.visible = on
	var m := Vis.emissive(Color(1.0, 0.97, 0.92), 0.95 if on else 0.05)
	for s in spots:
		s.material_override = m


func set_overload(on: bool) -> void:
	if on == _overload_on:
		return
	_overload_on = on
	overload_lamp.material_override = Vis.emissive(
			Color(0.95, 0.12, 0.06) if on else Color(0.10, 0.035, 0.03), 2.2 if on else 0.10)
	_overload_txt.modulate = Color(1.0, 0.92, 0.90) if on else Color(0.34, 0.34, 0.35)


func set_display(text: String, arrow: int) -> void:
	display.set_text(text, arrow)


func set_load_text(t: String) -> void:
	load_lbl.text = t
