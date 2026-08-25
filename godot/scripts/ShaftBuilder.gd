class_name ShaftRig
extends Node3D

## Asansor kuyusu, kat holleri, kat kapilari, makine dairesi ve karsi agirlik.
## Tum geometri prosedureldir.
##
## Koordinat sistemi:
##   Y = 0        -> zemin kat (kabin taban seviyesi)
##   +Z          -> kat holu / kapi yonu
##   Kuyu merkezi X = 0, Z = 0

const HALF_W := LiftCfg.M_SHAFT_W * 0.5
const HALF_D := LiftCfg.M_SHAFT_D * 0.5
const DOOR_Z := HALF_D - 0.02          # kat kapisi duzlemi
const COL := 0.12                      # kolon kesiti

var landing_left: Array[Node3D] = []
var landing_right: Array[Node3D] = []
var hall_up: Array = []
var hall_down: Array = []
var displays: Array[LedDisplay] = []

# --- tahrik sistemi ---------------------------------------------------------
var machine_root: Node3D
var sheave: Node3D                       # tahrik kasnagi (doner)
var deflector: Node3D                    # saptirma makarasi (doner)
var brake_disc: Node3D
var brake_pads: Array[MeshInstance3D] = []
var _brake_pad_sign: Array[float] = []
const BRAKE_ON_X := 0.019      # balata diske temas ediyor (fren tutuyor)
const BRAKE_OFF_X := 0.031     # balata geri cekildi (fren cozuldu)
var governor: Node3D
var gov_tension: Node3D
var gov_clamp: Node3D
var counterweight: Node3D

# --- halatlar (her biri icin kabin ve karsi agirlik tarafi dusey kol) -------
var _rope_car: Array[MeshInstance3D] = []
var _rope_cwt: Array[MeshInstance3D] = []
var _rope_car_mesh: CylinderMesh          # 5 kabin halati bu mesh'i paylasir
var _rope_cwt_mesh: CylinderMesh          # 5 karsi agirlik halati
var _rope_x_pos: Array[float] = []

var panel_leds: Array[MeshInstance3D] = []

var _btn_cb: Callable
var _sheave_angle := 0.0

var top_y: float
var sheave_y: float


func build(btn_callback: Callable) -> void:
	_btn_cb = btn_callback
	top_y = float(LiftCfg.TOP_FLOOR) * LiftCfg.M_FLOOR_H
	sheave_y = top_y + LiftCfg.M_HEADROOM - 1.15

	_build_ground()
	_build_pit()
	_build_structure()
	_build_rails()
	for f in range(LiftCfg.FLOOR_COUNT):
		_build_floor(f)
	_build_machine_room()
	_build_counterweight()
	_build_ropes()


# =============================================================================
func _build_ground() -> void:
	var g := PlaneMesh.new()
	g.size = Vector2(60, 60)
	var mi := MeshInstance3D.new()
	mi.mesh = g
	mi.material_override = Vis.mat("ground")
	mi.position = Vector3(0, -LiftCfg.M_PIT_DEPTH - 0.02, 0)
	add_child(mi)


func _build_pit() -> void:
	var d := LiftCfg.M_PIT_DEPTH
	# kuyu dibi tabani
	Vis.box(self, Vector3(LiftCfg.M_SHAFT_W + 0.4, 0.25, LiftCfg.M_SHAFT_D + 0.4),
			Vector3(0, -d - 0.125, 0), Vis.mat("concrete_dark"))
	# tamponlar (buffer)
	for x: float in [-0.55, 0.55]:
		Vis.cyl(self, 0.10, 0.55, Vector3(x, -d + 0.27, 0), Vis.mat("steel_dark"))
		Vis.cyl(self, 0.14, 0.10, Vector3(x, -d + 0.05, 0), Vis.mat("rubber"))
	# karsi agirlik tamponu
	Vis.cyl(self, 0.10, 0.45, Vector3(0, -d + 0.22, LiftCfg.M_CWT_Z), Vis.mat("steel_dark"))


func _build_structure() -> void:
	var h := LiftCfg.total_height() + LiftCfg.M_PIT_DEPTH
	var y0 := -LiftCfg.M_PIT_DEPTH + h * 0.5

	# --- 4 kose kolonu ------------------------------------------------------
	# On taraftakiler kuyunun icine kaydirilir; boylece kat holu duvarinin
	# arkasinda kalir ve holden gorunmez.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var cz := sz * (HALF_D + COL * 0.5)
			if sz > 0.0:
				cz = HALF_D - COL * 0.5 - 0.02
			Vis.box(self, Vector3(COL, h, COL),
					Vector3(sx * (HALF_W + COL * 0.5), y0, cz),
					Vis.mat("steel_dark"))

	# --- her kat hizasinda cevre kirisi -------------------------------------
	for f in range(LiftCfg.FLOOR_COUNT + 1):
		var y := float(f) * LiftCfg.M_FLOOR_H - 0.12
		if f == LiftCfg.FLOOR_COUNT:
			y = top_y + LiftCfg.M_HEADROOM - 0.4
		for sz: float in [-1.0, 1.0]:
			var bz := sz * (HALF_D + COL * 0.5)
			if sz > 0.0:
				bz = HALF_D - COL * 0.5 - 0.02
			Vis.box(self, Vector3(LiftCfg.M_SHAFT_W + 2 * COL, 0.10, COL),
					Vector3(0, y, bz), Vis.mat("steel_dark"))
		for sx: float in [-1.0, 1.0]:
			Vis.box(self, Vector3(COL, 0.10, LiftCfg.M_SHAFT_D),
					Vector3(sx * (HALF_W + COL * 0.5), y, 0), Vis.mat("steel_dark"))

	# --- cam panelli sirt ve sol yuz (panoramik kuyu) -----------------------
	Vis.box(self, Vector3(LiftCfg.M_SHAFT_W, h - 0.5, 0.02),
			Vector3(0, y0, -HALF_D - 0.03), Vis.mat("glass_dark"))
	Vis.box(self, Vector3(0.02, h - 0.5, LiftCfg.M_SHAFT_D),
			Vector3(-HALF_W - 0.03, y0, 0), Vis.mat("glass_dark"))
	# sag yuz acik birakildi -> mekanizma gorunur


func _build_rails() -> void:
	var h := LiftCfg.total_height() + LiftCfg.M_PIT_DEPTH
	var y0 := -LiftCfg.M_PIT_DEPTH + h * 0.5
	# kabin kilavuz raylari (T profil basitlestirilmis)
	for sx: float in [-1.0, 1.0]:
		var x := sx * (HALF_W - 0.06)
		Vis.box(self, Vector3(0.05, h, 0.16), Vector3(x, y0, 0), Vis.mat("rail"))
		Vis.box(self, Vector3(0.12, h, 0.04), Vector3(x + sx * 0.03, y0, 0), Vis.mat("rail"))
	# karsi agirlik raylari
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.04, h, 0.10),
				Vector3(sx * 0.62, y0, LiftCfg.M_CWT_Z - 0.12), Vis.mat("rail"))


# =============================================================================
func _build_floor(f: int) -> void:
	var y := float(f) * LiftCfg.M_FLOOR_H
	var root := Node3D.new()
	root.name = "Floor_%d" % f
	root.position = Vector3(0, y, 0)
	add_child(root)

	var hall_z := HALF_D + LiftCfg.M_HALL_D * 0.5

	# --- hol dosemesi: mermer + koyu bordur ---------------------------------
	Vis.box(root, Vector3(LiftCfg.M_HALL_W, LiftCfg.M_SLAB_T, LiftCfg.M_HALL_D),
			Vector3(0, -LiftCfg.M_SLAB_T * 0.5, hall_z), Vis.mat("slab"))
	Vis.box(root, Vector3(LiftCfg.M_HALL_W - 0.06, 0.02, LiftCfg.M_HALL_D - 0.06),
			Vector3(0, 0.01, hall_z), Vis.mat("granite_edge"))
	Vis.box(root, Vector3(LiftCfg.M_HALL_W - 0.5, 0.024, LiftCfg.M_HALL_D - 0.5),
			Vector3(0, 0.012, hall_z), Vis.mat("marble"))

	# --- hol duvarlari (kesit gorunumu: sag yuz ve on cephe acik) -----------
	var hw := LiftCfg.M_FLOOR_H - 0.28
	Vis.box(root, Vector3(LiftCfg.M_HALL_W, hw, 0.10),
			Vector3(0, hw * 0.5, HALF_D + LiftCfg.M_HALL_D), Vis.mat("wall_paint"))
	Vis.box(root, Vector3(0.10, hw, LiftCfg.M_HALL_D),
			Vector3(-LiftCfg.M_HALL_W * 0.5, hw * 0.5, hall_z), Vis.mat("wall_paint"))
	# supurgelikler (arka duvar + asansor cephesi)
	Vis.box(root, Vector3(LiftCfg.M_HALL_W, 0.10, 0.02),
			Vector3(0, 0.05, HALF_D + LiftCfg.M_HALL_D - 0.06), Vis.mat("inox_dark"))
	var sk_w := (LiftCfg.M_HALL_W - LiftCfg.M_DOOR_W - 0.30) * 0.5
	for sx2: float in [-1.0, 1.0]:
		var sk_x := sx2 * (LiftCfg.M_DOOR_W * 0.5 + 0.15 + sk_w * 0.5)
		Vis.box(root, Vector3(sk_w, 0.10, 0.02),
				Vector3(sk_x, 0.05, HALF_D + 0.13), Vis.mat("inox_dark"))

	# hol arka duvari (asansor cephesi) - kapi boslugu birakilir
	var wall_h := LiftCfg.M_FLOOR_H - 0.4
	var side_w := (LiftCfg.M_HALL_W - LiftCfg.M_DOOR_W - 0.24) * 0.5
	for sx: float in [-1.0, 1.0]:
		Vis.box(root, Vector3(side_w, wall_h, 0.12),
				Vector3(sx * (LiftCfg.M_DOOR_W * 0.5 + 0.12 + side_w * 0.5),
						wall_h * 0.5, HALF_D + 0.06), Vis.mat("wall_paint"))
	# lento
	Vis.box(root, Vector3(LiftCfg.M_DOOR_W + 0.24, wall_h - LiftCfg.M_DOOR_H - 0.06,
			0.12), Vector3(0, LiftCfg.M_DOOR_H + 0.06 + (wall_h - LiftCfg.M_DOOR_H - 0.06) * 0.5,
			HALF_D + 0.06), Vis.mat("wall_paint"))

	# --- paslanmaz kapi sovesi (jamb) --------------------------------------
	var frame_z := HALF_D + 0.13
	for sx: float in [-1.0, 1.0]:
		# sove govdesi
		Vis.box(root, Vector3(0.13, LiftCfg.M_DOOR_H + 0.15, 0.075),
				Vector3(sx * (LiftCfg.M_DOOR_W * 0.5 + 0.065),
						(LiftCfg.M_DOOR_H + 0.15) * 0.5, frame_z),
				Vis.mat("inox"))
		# sovenin kuyuya donen ic yuzu
		Vis.box(root, Vector3(0.02, LiftCfg.M_DOOR_H + 0.15, 0.10),
				Vector3(sx * (LiftCfg.M_DOOR_W * 0.5 + 0.005),
						(LiftCfg.M_DOOR_H + 0.15) * 0.5, HALF_D + 0.055),
				Vis.mat("inox_dark"))
	# ust sove
	Vis.box(root, Vector3(LiftCfg.M_DOOR_W + 0.26, 0.13, 0.075),
			Vector3(0, LiftCfg.M_DOOR_H + 0.085, frame_z), Vis.mat("inox"))
	# esik (paslanmaz)
	Vis.box(root, Vector3(LiftCfg.M_DOOR_W + 0.22, 0.03, 0.13),
			Vector3(0, 0.015, DOOR_Z - 0.01), Vis.mat("inox"))

	# --- kat kapisi kanatlari (merkezi acilim, firçalanmis inox) ------------
	var lw := LiftCfg.M_DOOR_W * 0.5
	for side in [-1, 1]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * lw * 0.5, 0, DOOR_Z)
		root.add_child(leaf)
		Vis.box(leaf, Vector3(lw, LiftCfg.M_DOOR_H, LiftCfg.M_DOOR_T),
				Vector3(0, LiftCfg.M_DOOR_H * 0.5, 0), Vis.mat("inox"))
		# kapanma kenari profili
		Vis.box(leaf, Vector3(0.014, LiftCfg.M_DOOR_H, LiftCfg.M_DOOR_T + 0.008),
				Vector3(-side * (lw * 0.5 - 0.007), LiftCfg.M_DOOR_H * 0.5, 0),
				Vis.mat("inox_dark"))
		if side < 0:
			landing_left.append(leaf)
		else:
			landing_right.append(leaf)

	# --- hol gostergesi: kirmizi nokta-matris (kapi ustu) -------------------
	var ind_y := LiftCfg.M_DOOR_H + 0.30
	Vis.box(root, Vector3(0.40, 0.17, 0.035),
			Vector3(0, ind_y, HALF_D + 0.155), Vis.mat("inox"))
	Vis.box(root, Vector3(0.345, 0.125, 0.008),
			Vector3(0, ind_y, HALF_D + 0.176), Vis.mat("display_glass"))
	var disp := LedDisplay.create(root, Vector3(0, ind_y, HALF_D + 0.182), 0.315)
	displays.append(disp)

	# --- kat numarasi plakasi (sovenin yaninda) ----------------------------
	Vis.box(root, Vector3(0.13, 0.13, 0.008),
			Vector3(-(LiftCfg.M_DOOR_W * 0.5 + 0.20), 1.62, HALF_D + 0.125),
			Vis.mat("inox"))
	var fl := Vis.label(root, LiftIo.floor_name(f),
			Vector3(-(LiftCfg.M_DOOR_W * 0.5 + 0.20), 1.62, HALF_D + 0.132), 0.0012,
			Color(0.16, 0.17, 0.18))
	fl.outline_size = 0
	# buyuk duvar numarasi
	var fl2 := Vis.label(root, LiftIo.floor_name(f),
			Vector3(-(LiftCfg.M_DOOR_W * 0.5 + 0.80), 1.80, HALF_D + 0.121), 0.0032,
			Color(0.45, 0.47, 0.50))
	fl2.outline_size = 0

	# --- hol cagri butonu plakasi -------------------------------------------
	var bx := LiftCfg.M_DOOR_W * 0.5 + 0.28
	Vis.box(root, Vector3(0.115, 0.235, 0.012),
			Vector3(bx, 1.12, HALF_D + 0.126), Vis.mat("inox"))
	Vis.box(root, Vector3(0.100, 0.220, 0.004),
			Vector3(bx, 1.12, HALF_D + 0.134), Vis.mat("inox_dark"))

	if f < LiftCfg.TOP_FLOOR:
		var b := Btn3D.create(root, "hall_up_%d" % f,
				Vector3(bx, 1.175, HALF_D + 0.138), "^", 0.024)
		b.pushed.connect(_btn_cb)
		hall_up.append(b)
	else:
		hall_up.append(null)

	if f > 0:
		var b2 := Btn3D.create(root, "hall_down_%d" % f,
				Vector3(bx, 1.065, HALF_D + 0.138), "v", 0.024)
		b2.pushed.connect(_btn_cb)
		hall_down.append(b2)
	else:
		hall_down.append(null)

	# --- kumanda panosu (MRL: en ust kat holunde) ---------------------------
	if f == LiftCfg.TOP_FLOOR:
		_build_control_panel(root)

	# --- hol aydinlatmasi ---------------------------------------------------
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, LiftCfg.M_FLOOR_H - 0.55, hall_z - 0.4)
	lamp.light_energy = 0.95
	lamp.omni_range = 7.0
	lamp.light_color = Color(1.0, 0.96, 0.90)
	lamp.shadow_enabled = false
	root.add_child(lamp)
	# gomme tavan armaturu (cerceve + difuzor)
	Vis.box(root, Vector3(1.16, 0.06, 0.56),
			Vector3(0, LiftCfg.M_FLOOR_H - 0.44, hall_z - 0.4), Vis.mat("inox_dark"))
	Vis.box(root, Vector3(1.06, 0.03, 0.46),
			Vector3(0, LiftCfg.M_FLOOR_H - 0.455, hall_z - 0.4),
			Vis.emissive(Color(1.0, 0.96, 0.88), 0.30))


# =============================================================================
# TAHRIK MAKINESI  (dislisiz / PM gearless, makine dairesiz yerlesim)
# -----------------------------------------------------------------------------
# Gercek bir MRL asansorde:
#   - Sabit miknatisli senkron motor, redüktörsüz; tahrik kasnagi motor miline
#     dogrudan baglidir.
#   - Kasnak uzerinde her halat icin ayri V/U kanal bulunur.
#   - Motorun diger ucunda fren diski ve iki elektromanyetik kaliper vardir;
#     bobin enerjilenince pabuclar acilir (fren cozulur).
#   - Mil ucunda enkoder, govde uzerinde sogutma kanatlari.
#   - Kasnak ile karsi agirlik hatti arasindaki mesafeyi saptirma makarasi ayarlar.
# =============================================================================
func _build_machine_room() -> void:
	var y := top_y + LiftCfg.M_HEADROOM
	var root := Node3D.new()
	root.name = "Machine"
	add_child(root)

	# kuyu tavani (halat gecisi icin ortasi acik iki parca)
	for sz: float in [-1.0, 1.0]:
		Vis.box(root, Vector3(LiftCfg.M_SHAFT_W + 0.5, 0.16, LiftCfg.M_SHAFT_D * 0.34),
				Vector3(0, y, sz * (HALF_D - LiftCfg.M_SHAFT_D * 0.17)),
				Vis.mat("concrete"))

	# --- tasiyici celik kirisler + kaide -----------------------------------
	for sx: float in [-1.0, 1.0]:
		Vis.box(root, Vector3(0.16, 0.28, LiftCfg.M_SHAFT_D + 0.3),
				Vector3(sx * 0.78, sheave_y + 0.70, -0.20), Vis.mat("steel_dark"))
	# makine kaidesi (bedplate) + titresim takozlari
	Vis.box(root, Vector3(1.30, 0.09, 0.70),
			Vector3(-0.10, sheave_y + 0.52, -0.30), Vis.mat("bedplate"))
	for sx2: float in [-1.0, 1.0]:
		for sz2: float in [-1.0, 1.0]:
			Vis.box(root, Vector3(0.13, 0.05, 0.13),
					Vector3(-0.10 + sx2 * 0.52, sheave_y + 0.585, -0.30 + sz2 * 0.24),
					Vis.mat("rubber"))

	# ==========================================================================
	# Tahrik kasnagi hatti:  kabin tarafi z = 0, karsi agirlik tarafi z = -2R
	# ==========================================================================
	var tz := LiftCfg.M_ROPE_Z_CAR - LiftCfg.M_SHEAVE_R      # kasnak merkezi z
	var mroot := Node3D.new()
	mroot.position = Vector3(0, sheave_y, tz)
	root.add_child(mroot)
	machine_root = mroot

	var rope_w: float = (LiftCfg.ROPE_COUNT - 1) * LiftCfg.ROPE_PITCH   # halat demeti genisligi

	# --- PM disk motor govdesi (kasnagin solunda) ---------------------------
	var mb := Vis.cyl(mroot, 0.35, 0.30, Vector3(-0.34, 0, 0), Vis.mat("motor"))
	mb.rotation_degrees = Vector3(0, 0, 90)
	# sogutma kanatlari
	for i in range(16):
		var a := TAU * float(i) / 16.0
		var fin := Vis.box(mroot, Vector3(0.28, 0.72, 0.022), Vector3(-0.34, 0, 0),
				Vis.mat("motor_fin"))
		fin.rotation = Vector3(a, 0, 0)
	# klemens kutusu
	Vis.box(mroot, Vector3(0.20, 0.16, 0.22), Vector3(-0.34, 0.40, 0), Vis.mat("motor_fin"))
	# mil
	var shaft := Vis.cyl(mroot, 0.055, 1.05, Vector3(-0.05, 0, 0), Vis.mat("steel"))
	shaft.rotation_degrees = Vector3(0, 0, 90)

	# --- tahrik kasnagi (donen) --------------------------------------------
	sheave = Node3D.new()
	mroot.add_child(sheave)
	var hub := Vis.cyl(sheave, LiftCfg.M_SHEAVE_R - 0.035, rope_w + 0.10,
			Vector3.ZERO, Vis.mat("steel"))
	hub.rotation_degrees = Vector3(0, 0, 90)
	# halat kanallari: her halat icin bir bilezik (aralarinda yuksek yaka)
	for r in range(LiftCfg.ROPE_COUNT):
		var rx := _rope_x(r)
		var flange := Vis.cyl(sheave, LiftCfg.M_SHEAVE_R, 0.010,
				Vector3(rx - LiftCfg.ROPE_PITCH * 0.5, 0, 0), Vis.mat("steel_dark"))
		flange.rotation_degrees = Vector3(0, 0, 90)
	var last_flange := Vis.cyl(sheave, LiftCfg.M_SHEAVE_R, 0.010,
			Vector3(_rope_x(LiftCfg.ROPE_COUNT - 1) + LiftCfg.ROPE_PITCH * 0.5, 0, 0),
			Vis.mat("steel_dark"))
	last_flange.rotation_degrees = Vector3(0, 0, 90)
	# govde delikleri (donus gozle gorulur olsun)
	for i in range(6):
		var a2 := TAU * float(i) / 6.0
		var sp := Vis.box(sheave, Vector3(rope_w + 0.12, 0.09, 0.09),
				Vector3(0, (LiftCfg.M_SHEAVE_R - 0.13) * sin(a2),
						(LiftCfg.M_SHEAVE_R - 0.13) * cos(a2)), Vis.mat("motor"))
		sp.rotation = Vector3(a2, 0, 0)

	# --- fren diski + iki elektromanyetik kaliper ---------------------------
	brake_disc = Node3D.new()
	mroot.add_child(brake_disc)
	var bd := Vis.cyl(brake_disc, 0.255, 0.022, Vector3(0.34, 0, 0),
			Vis.mat("brake_disc"))
	bd.rotation_degrees = Vector3(0, 0, 90)
	var bh := Vis.cyl(brake_disc, 0.09, 0.06, Vector3(0.34, 0, 0), Vis.mat("steel"))
	bh.rotation_degrees = Vector3(0, 0, 90)

	# Kaliper diskin cemberini kavrar; iki pabuc diskin iki duz yuzune basar.
	# Bobin enerjilenince (fren cozulunce) pabuclar geri ceker.
	for sz3: float in [-1.0, 1.0]:
		var cal := Node3D.new()
		cal.position = Vector3(0.34, 0, sz3 * 0.215)
		mroot.add_child(cal)
		# bobin / govde (diskin disinda kalir)
		Vis.box(cal, Vector3(0.15, 0.17, 0.11), Vector3(0, 0, sz3 * 0.085),
				Vis.mat("caliper"))
		Vis.box(cal, Vector3(0.055, 0.09, 0.07), Vector3(0, 0, sz3 * 0.02),
				Vis.mat("motor_fin"))
		for sxp: float in [-1.0, 1.0]:
			# pabuc kolu
			Vis.box(cal, Vector3(0.022, 0.12, 0.08), Vector3(sxp * 0.052, 0, sz3 * 0.045),
					Vis.mat("caliper"))
			# balata
			var pad := Vis.box(cal, Vector3(0.016, 0.10, 0.075),
					Vector3(sxp * BRAKE_ON_X, 0, 0), Vis.mat("rubber"))
			brake_pads.append(pad)
			_brake_pad_sign.append(sxp)

	# --- enkoder (mil ucu) ---------------------------------------------------
	var enc := Vis.cyl(mroot, 0.055, 0.07, Vector3(0.52, 0, 0), Vis.mat("panel"))
	enc.rotation_degrees = Vector3(0, 0, 90)
	Vis.box(mroot, Vector3(0.03, 0.03, 0.10), Vector3(0.52, 0.05, 0.05),
			Vis.mat("inox_line"))

	# ==========================================================================
	# Saptirma makarasi: kasnaktan inen hatti karsi agirlik hattina tasir
	# ==========================================================================
	var dz := (tz - LiftCfg.M_SHEAVE_R) - LiftCfg.M_DEFLECT_R
	deflector = Node3D.new()
	deflector.position = Vector3(0, sheave_y - LiftCfg.M_DEFLECT_DY, dz)
	root.add_child(deflector)
	var dsh := Vis.cyl(deflector, LiftCfg.M_DEFLECT_R - 0.03, rope_w + 0.09,
			Vector3.ZERO, Vis.mat("steel"))
	dsh.rotation_degrees = Vector3(0, 0, 90)
	for r2 in range(LiftCfg.ROPE_COUNT + 1):
		var fx := _rope_x(0) + (r2 - 0.5) * LiftCfg.ROPE_PITCH
		var fl := Vis.cyl(deflector, LiftCfg.M_DEFLECT_R, 0.009, Vector3(fx, 0, 0),
				Vis.mat("steel_dark"))
		fl.rotation_degrees = Vector3(0, 0, 90)
	# makara yataklama braketi
	Vis.box(root, Vector3(rope_w + 0.30, 0.06, 0.10),
			Vector3(0, sheave_y - LiftCfg.M_DEFLECT_DY + LiftCfg.M_DEFLECT_R + 0.10, dz),
			Vis.mat("steel_dark"))
	for sx3: float in [-1.0, 1.0]:
		Vis.box(root, Vector3(0.05, LiftCfg.M_DEFLECT_DY, 0.08),
				Vector3(sx3 * (rope_w * 0.5 + 0.10),
						sheave_y - LiftCfg.M_DEFLECT_DY * 0.5 + 0.10, dz),
				Vis.mat("steel_dark"))

	# ==========================================================================
	# Hiz regulatoru (governor) — kendi halat ilmegi ile
	# ==========================================================================
	_build_governor(root)

	# makine bolumu aydinlatmasi
	var l := OmniLight3D.new()
	l.position = Vector3(0.30, sheave_y + 0.50, 0.55)
	l.light_energy = 1.5
	l.omni_range = 5.0
	l.shadow_enabled = false
	root.add_child(l)
	var l2 := OmniLight3D.new()
	l2.position = Vector3(-0.45, sheave_y - 0.20, 0.45)
	l2.light_energy = 0.9
	l2.omni_range = 3.5
	l2.light_color = Color(0.92, 0.95, 1.0)
	l2.shadow_enabled = false
	root.add_child(l2)
	# armatur govdesi
	Vis.box(root, Vector3(0.50, 0.05, 0.16), Vector3(0.30, sheave_y + 0.62, 0.55),
			Vis.emissive(Color(1.0, 0.97, 0.90), 0.9))


## Halat n'in X konumu (demet ortalanmis)
func _rope_x(i: int) -> float:
	return (float(i) - (LiftCfg.ROPE_COUNT - 1) * 0.5) * LiftCfg.ROPE_PITCH


## Hiz regulatoru: tepede kasnak, kuyu dibinde gergi makarasi, arada kapali
## halat ilmegi. Kabine baglanan kavrama halat boyunca kabinle birlikte gider.
func _build_governor(root: Node3D) -> void:
	var gz := LiftCfg.M_GOV_ROPE_Z
	var gx := HALF_W - 0.15
	var top := sheave_y - 0.10
	var bot := -LiftCfg.M_PIT_DEPTH + 0.55

	# regulator govdesi
	Vis.box(root, Vector3(0.16, 0.34, 0.30), Vector3(gx, top + 0.30, gz),
			Vis.mat("panel"))
	governor = Node3D.new()
	governor.position = Vector3(gx, top, gz)
	root.add_child(governor)
	var gs := Vis.cyl(governor, LiftCfg.M_GOV_R, 0.05, Vector3.ZERO, Vis.mat("steel"))
	gs.rotation_degrees = Vector3(0, 0, 90)
	for i in range(4):
		var a := TAU * float(i) / 4.0
		var sp := Vis.box(governor, Vector3(0.06, 0.05, LiftCfg.M_GOV_R * 1.5),
				Vector3.ZERO, Vis.mat("steel_dark"))
		sp.rotation = Vector3(a, 0, 0)

	# gergi makarasi (kuyu dibi)
	gov_tension = Node3D.new()
	gov_tension.position = Vector3(gx, bot, gz)
	root.add_child(gov_tension)
	var ts := Vis.cyl(gov_tension, LiftCfg.M_GOV_R * 0.85, 0.05, Vector3.ZERO,
			Vis.mat("steel"))
	ts.rotation_degrees = Vector3(0, 0, 90)
	Vis.box(root, Vector3(0.08, 0.45, 0.08), Vector3(gx, bot - 0.30, gz),
			Vis.mat("steel_dark"))
	Vis.box(root, Vector3(0.26, 0.05, 0.26), Vector3(gx, bot - 0.52, gz),
			Vis.mat("steel_dark"))

	# kapali halat ilmegi: iki dusey kol + ustte/altta yaylar
	var r_out := LiftCfg.M_GOV_R
	for sz: float in [-1.0, 1.0]:
		Vis.rod(root, Vector3(gx, top, gz + sz * r_out),
				Vector3(gx, bot, gz + sz * LiftCfg.M_GOV_R * 0.85),
				LiftCfg.M_ROPE_R * 0.8, Vis.mat("rope"))
	Vis.arc_yz(root, gx, top, gz, r_out, 0.0, 180.0, 10, LiftCfg.M_ROPE_R * 0.8,
			Vis.mat("rope"))
	Vis.arc_yz(root, gx, bot, gz, LiftCfg.M_GOV_R * 0.85, 180.0, 360.0, 10,
			LiftCfg.M_ROPE_R * 0.8, Vis.mat("rope"))

	# kabine baglanan kavrama (kabinle birlikte hareket eder)
	gov_clamp = Node3D.new()
	root.add_child(gov_clamp)
	Vis.box(gov_clamp, Vector3(0.09, 0.12, 0.07), Vector3(gx, 0, gz + r_out),
			Vis.mat("caliper"))
	Vis.rod(gov_clamp, Vector3(gx, 0, gz + r_out),
			Vector3(HALF_W - 0.06, -0.10, gz + r_out + 0.02), 0.012, Vis.mat("steel"))


## Kumanda panosu — MRL duzeninde en ust kat holunde bulunur.
func _build_control_panel(root: Node3D) -> void:
	var pan := Node3D.new()
	pan.position = Vector3(-LiftCfg.M_HALL_W * 0.5 + 0.20, 0.0,
			HALF_D + LiftCfg.M_HALL_D * 0.55)
	pan.rotation_degrees = Vector3(0, 90, 0)
	root.add_child(pan)

	Vis.box(pan, Vector3(1.00, 1.70, 0.26), Vector3(0, 1.05, 0), Vis.mat("panel"))
	Vis.box(pan, Vector3(0.86, 1.48, 0.02), Vector3(0, 1.05, 0.14), Vis.mat("steel_dark"))
	var t := Vis.label(pan, "CODESYS PLC", Vector3(0, 1.80, 0.14), 0.0009,
			Color(0.75, 0.85, 0.95))
	t.outline_size = 0
	var t2 := Vis.label(pan, "ASANSOR KUMANDA PANOSU", Vector3(0, 0.30, 0.14), 0.00045,
			Color(0.55, 0.60, 0.66))
	t2.outline_size = 0

	# durum LED'leri
	var names := ["DRIVE", "RUN", "DOOR", "FAULT", "LINK", "HB"]
	for i in range(6):
		var led := Vis.cyl(pan, 0.026, 0.014,
				Vector3(-0.32 + i * 0.13, 1.52, 0.16),
				Vis.emissive(Color(0.1, 0.4, 0.1), 0.4))
		led.rotation_degrees = Vector3(90, 0, 0)
		panel_leds.append(led)
		var nl := Vis.label(pan, names[i], Vector3(-0.32 + i * 0.13, 1.42, 0.15), 0.00030,
				Color(0.70, 0.74, 0.80))
		nl.outline_size = 0

	# terminal siralari (gorsel detay)
	for r in range(4):
		Vis.box(pan, Vector3(0.70, 0.05, 0.03), Vector3(0, 1.15 - r * 0.16, 0.15),
				Vis.mat("steel_brushed"))


# =============================================================================
func _build_counterweight() -> void:
	counterweight = Node3D.new()
	counterweight.name = "Counterweight"
	add_child(counterweight)
	Vis.box(counterweight, Vector3(LiftCfg.M_CWT_W, LiftCfg.M_CWT_H, LiftCfg.M_CWT_D),
			Vector3.ZERO, Vis.mat("cwt"))
	# agirlik dilimleri
	for i in range(7):
		Vis.box(counterweight, Vector3(LiftCfg.M_CWT_W + 0.02, 0.02, LiftCfg.M_CWT_D + 0.02),
				Vector3(0, -LiftCfg.M_CWT_H * 0.5 + 0.12 + i * 0.21, 0),
				Vis.mat("steel_dark"))
	# --- halat baglanti kancasi (hitch plate + yaylar) ----------------------
	var rope_w: float = (LiftCfg.ROPE_COUNT - 1) * LiftCfg.ROPE_PITCH
	var chy := LiftCfg.M_CWT_H * 0.5 + 0.20
	Vis.box(counterweight, Vector3(rope_w + 0.14, 0.028, 0.12),
			Vector3(0, chy, 0), Vis.mat("steel"))
	Vis.box(counterweight, Vector3(rope_w + 0.14, 0.028, 0.12),
			Vector3(0, chy - 0.14, 0), Vis.mat("steel"))
	for i in range(LiftCfg.ROPE_COUNT):
		var rx := _rope_x(i)
		Vis.cyl(counterweight, 0.013, 0.115, Vector3(rx, chy - 0.07, 0),
				Vis.mat("steel_dark"))
		Vis.cyl(counterweight, 0.006, 0.18, Vector3(rx, chy - 0.05, 0), Vis.mat("steel"))
		Vis.cyl(counterweight, 0.010, 0.024, Vector3(rx, chy + 0.018, 0),
				Vis.mat("steel_dark"))
	# aski cercevesi (yan dikmeler)
	for sxc: float in [-1.0, 1.0]:
		Vis.box(counterweight, Vector3(0.05, 0.42, LiftCfg.M_CWT_D + 0.05),
				Vector3(sxc * (LiftCfg.M_CWT_W * 0.5 - 0.03),
						LiftCfg.M_CWT_H * 0.5 - 0.02, 0), Vis.mat("steel"))
	Vis.box(counterweight, Vector3(LiftCfg.M_CWT_W, 0.05, LiftCfg.M_CWT_D + 0.05),
			Vector3(0, LiftCfg.M_CWT_H * 0.5 + 0.06, 0), Vis.mat("steel"))


## Askı halatlari — 1:1 roping:
##   kabin kancasi -> dusey -> tahrik kasnagi uzerinde 180 derece sarim ->
##   dusey -> saptirma makarasi uzerinde 180 derece sarim -> dusey ->
##   karsi agirlik kancasi
## Kasnaklar uzerindeki yaylar sabit geometridir; yalnizca dusey kollarin
## boyu her karede guncellenir.
func _build_ropes() -> void:
	var tz := LiftCfg.M_ROPE_Z_CAR - LiftCfg.M_SHEAVE_R
	var dz := (tz - LiftCfg.M_SHEAVE_R) - LiftCfg.M_DEFLECT_R
	var dy := sheave_y - LiftCfg.M_DEFLECT_DY

	var ropes := Node3D.new()
	ropes.name = "Ropes"
	add_child(ropes)

	for i in range(LiftCfg.ROPE_COUNT):
		var rx := _rope_x(i)
		_rope_x_pos.append(rx)

		# --- tahrik kasnagi uzerinde sarim (kabin tarafi -> karsi taraf) ----
		Vis.arc_yz(ropes, rx, sheave_y, tz, LiftCfg.M_SHEAVE_R, 0.0, 180.0, 14,
				LiftCfg.M_ROPE_R, Vis.mat("rope"))
		# --- kasnaktan saptirma makarasina inen kisa kol --------------------
		Vis.rod(ropes, Vector3(rx, sheave_y, tz - LiftCfg.M_SHEAVE_R),
				Vector3(rx, dy, dz + LiftCfg.M_DEFLECT_R),
				LiftCfg.M_ROPE_R, Vis.mat("rope"))
		# --- saptirma makarasi uzerinde sarim -------------------------------
		Vis.arc_yz(ropes, rx, dy, dz, LiftCfg.M_DEFLECT_R, 0.0, 180.0, 12,
				LiftCfg.M_ROPE_R, Vis.mat("rope"))

		# --- dinamik dusey kollar -------------------------------------------
		# Bir taraftaki 5 halatin boyu her zaman ayni; tek mesh'i paylasirlar.
		# Boylece her karede 10 degil 2 mesh guncellenir.
		var rc := Vis.cyl(ropes, LiftCfg.M_ROPE_R, 1.0,
				Vector3(rx, 0, LiftCfg.M_ROPE_Z_CAR), Vis.mat("rope"), "", false)
		if _rope_car_mesh == null:
			_rope_car_mesh = rc.mesh as CylinderMesh
		else:
			rc.mesh = _rope_car_mesh
		_rope_car.append(rc)

		var rw := Vis.cyl(ropes, LiftCfg.M_ROPE_R, 1.0,
				Vector3(rx, 0, LiftCfg.M_CWT_Z), Vis.mat("rope"), "", false)
		if _rope_cwt_mesh == null:
			_rope_cwt_mesh = rw.mesh as CylinderMesh
		else:
			rw.mesh = _rope_cwt_mesh
		_rope_cwt.append(rw)


# =============================================================================
# CANLI GUNCELLEME
# =============================================================================
func set_landing_door(f: int, amount: float) -> void:
	if f < 0 or f >= landing_left.size():
		return
	var travel := LiftCfg.M_DOOR_W * 0.5 * amount
	landing_left[f].position.x = -LiftCfg.M_DOOR_W * 0.25 - travel
	landing_right[f].position.x = LiftCfg.M_DOOR_W * 0.25 + travel


func close_other_doors(except_floor: int) -> void:
	for f in range(landing_left.size()):
		if f != except_floor:
			set_landing_door(f, 0.0)


func update_ropes(car_y: float, cwt_y: float) -> void:
	# Kabin tarafi: tahrik kasnaginin +Z teget noktasindan kabin kancasina.
	# Bitis kotu, kanca plakasindaki halat sokesinin icine denk gelir.
	var top_car := car_y + LiftCfg.M_CAR_H + 0.355
	var len_car := maxf(0.02, sheave_y - top_car)
	# Karsi agirlik tarafi: saptirma makarasinin -Z teget noktasindan asagi
	var dy := sheave_y - LiftCfg.M_DEFLECT_DY
	var top_cwt := cwt_y + LiftCfg.M_CWT_H * 0.5 + 0.215
	var len_cwt := maxf(0.02, dy - top_cwt)

	_rope_car_mesh.height = len_car
	_rope_cwt_mesh.height = len_cwt
	var y_car := top_car + len_car * 0.5
	var y_cwt := top_cwt + len_cwt * 0.5
	for i in range(_rope_car.size()):
		_rope_car[i].position = Vector3(_rope_x_pos[i], y_car, LiftCfg.M_ROPE_Z_CAR)
		_rope_cwt[i].position = Vector3(_rope_x_pos[i], y_cwt, LiftCfg.M_CWT_Z)

	counterweight.position = Vector3(0, cwt_y, LiftCfg.M_CWT_Z)

	# regulator kavramasi kabinle birlikte gider
	if gov_clamp != null:
		gov_clamp.position.y = car_y + LiftCfg.M_CAR_H * 0.5


## Kasnaklari halat hiziyla dondurur.
## speed_mms > 0 = kabin yukari; bu durumda kabin tarafindaki halat yukari
## hareket eder, dolayisiyla kasnagin +Z yuzu yukari gider (aci azalir).
func spin_sheave(speed_mms: float, dt: float) -> void:
	var v := speed_mms * 0.001                      # m/s
	_sheave_angle -= v / LiftCfg.M_SHEAVE_R * dt
	if sheave != null:
		sheave.rotation.x = _sheave_angle
	if brake_disc != null:
		brake_disc.rotation.x = _sheave_angle
	if deflector != null:
		deflector.rotation.x -= v / LiftCfg.M_DEFLECT_R * dt
	if governor != null:
		governor.rotation.x -= v / LiftCfg.M_GOV_R * dt
	if gov_tension != null:
		gov_tension.rotation.x -= v / (LiftCfg.M_GOV_R * 0.85) * dt


## Fren balatalarini konumlandirir (PLC'nin fren-coz cikisina gore).
func set_brake(released: bool) -> void:
	var x := BRAKE_OFF_X if released else BRAKE_ON_X
	for i in range(brake_pads.size()):
		brake_pads[i].position.x = _brake_pad_sign[i] * x


func set_display(f: int, text: String, arrow: int) -> void:
	if f < 0 or f >= displays.size():
		return
	displays[f].set_text(text, arrow)


var _led_state: Array[bool] = [false, false, false, false, false, false]

## Her karede cagrilir; yalnizca degisen LED'in materyali guncellenir.
func set_panel_leds(bits: Array) -> void:
	for i in range(mini(bits.size(), panel_leds.size())):
		var on: bool = bits[i]
		if i < _led_state.size() and _led_state[i] == on:
			continue
		if i < _led_state.size():
			_led_state[i] = on
		var c := Color(0.15, 0.95, 0.25) if on else Color(0.08, 0.20, 0.08)
		panel_leds[i].material_override = Vis.emissive(c, 3.0 if on else 0.3)
