class_name CarRig
extends Node3D

## Modern asansör kabini (gerçek ölçülere göre):
##   - firçalanmis paslanmaz (satine inox) duvar panelleri, derz çizgileriyle
##   - arka duvarda tam boy ayna, 900 mm'de yuvarlak paslanmaz küpeşte
##   - koyu granit zemin, paslanmaz süpürgelik
##   - beyaz asma tavan + 4 gömme spot
##   - COP: kırmızı nokta-matris gösterge, iki kolon yuvarlak buton, braille,
##     kapı aç/kapa, alarm, telefon ızgarası, anahtarlı şalter
##
## Kabin düğümünün Y konumu = encoder konumu (pos_mm / 1000).

const W := LiftCfg.M_CAR_W
const D := LiftCfg.M_CAR_D
const H := LiftCfg.M_CAR_H
const WALL := 0.04
const DOOR_Z := LiftCfg.M_CAR_D * 0.5 + 0.02

const BTN_R := 0.022          # buton bilezik yarıçapı (~44 mm çap)
const COP_X := 0.050          # buton kolon aralığı

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

	# --- halat baglanti kancasi (hitch plate + yay grubu) -------------------
	# Gercek asansorde her halat, plakaya bir baski yayi uzerinden baglanir;
	# yaylar yuku esitler ve halat gerginligini dengeler.
	var hy := H + 0.34
	var rope_w: float = (LiftCfg.ROPE_COUNT - 1) * LiftCfg.ROPE_PITCH
	Vis.box(self, Vector3(rope_w + 0.16, 0.030, 0.14),
			Vector3(0, hy, LiftCfg.M_ROPE_Z_CAR), Vis.mat("steel"))
	Vis.box(self, Vector3(rope_w + 0.16, 0.030, 0.14),
			Vector3(0, hy - 0.16, LiftCfg.M_ROPE_Z_CAR), Vis.mat("steel"))
	for i in range(LiftCfg.ROPE_COUNT):
		var rx: float = (float(i) - (LiftCfg.ROPE_COUNT - 1) * 0.5) * LiftCfg.ROPE_PITCH
		# baski yayi
		Vis.cyl(self, 0.014, 0.13, Vector3(rx, hy - 0.08, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel_dark"))
		# halat sokesi / gerdirme cubugu
		Vis.cyl(self, 0.006, 0.20, Vector3(rx, hy - 0.06, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel"))
		Vis.cyl(self, 0.011, 0.026, Vector3(rx, hy + 0.020, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel_dark"))
	# plakayi kabin sasisine baglayan kirisler
	for sxh: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.05, 0.30, 0.10),
				Vector3(sxh * (rope_w * 0.5 + 0.05), hy - 0.30, LiftCfg.M_ROPE_Z_CAR),
				Vis.mat("steel_dark"))


func _build_shell() -> void:
	# --- zemin: koyu granit + acik bordur ----------------------------------
	Vis.box(self, Vector3(W, LiftCfg.M_CAR_FLOOR_T, D),
			Vector3(0, -LiftCfg.M_CAR_FLOOR_T * 0.5, 0), Vis.mat("steel_dark"))
	Vis.box(self, Vector3(W - 0.02, 0.02, D - 0.02), Vector3(0, 0.01, 0),
			Vis.mat("granite_edge"))
	Vis.box(self, Vector3(W - 0.16, 0.022, D - 0.16), Vector3(0, 0.012, 0),
			Vis.mat("granite"))

	# --- dis kabuk (kuyudan bakildiginda) -----------------------------------
	Vis.box(self, Vector3(W, 0.08, D), Vector3(0, H + 0.04, 0), Vis.mat("inox_dark"))
	Vis.box(self, Vector3(W, H, WALL), Vector3(0, H * 0.5, -D * 0.5), Vis.mat("inox_dark"))
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(WALL, H, D), Vector3(sx * W * 0.5, H * 0.5, 0),
				Vis.mat("inox_dark"))

	# --- on yuz: kapi acikliginin yanlari ve ustu ---------------------------
	var side := (W - LiftCfg.M_DOOR_W) * 0.5
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(side, H, WALL),
				Vector3(sx * (LiftCfg.M_DOOR_W * 0.5 + side * 0.5), H * 0.5, D * 0.5),
				Vis.mat("inox"))
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W, H - LiftCfg.M_DOOR_H, WALL),
			Vector3(0, LiftCfg.M_DOOR_H + (H - LiftCfg.M_DOOR_H) * 0.5, D * 0.5),
			Vis.mat("inox"))
	# esik (paslanmaz)
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.10, 0.03, 0.10),
			Vector3(0, 0.015, D * 0.5 - 0.02), Vis.mat("inox"))

	# --- etek saci (apron / toe guard): esigin altinda, kuyu tarafina bakar ---
	# Gercek asansorlerde kabin kat arasinda kalirsa yolcunun kuyuya dusmesini
	# engelleyen bukumlu sac.
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.22, 0.75, 0.016),
			Vector3(0, -0.375, D * 0.5 + 0.008), Vis.mat("inox_dark"))
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.22, 0.02, 0.06),
			Vector3(0, -0.745, D * 0.5 - 0.022), Vis.mat("inox_dark"))
	for sx4: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.02, 0.75, 0.05),
				Vector3(sx4 * (LiftCfg.M_DOOR_W * 0.5 + 0.10), -0.375, D * 0.5 - 0.018),
				Vis.mat("inox_dark"))

	# --- kabin ustu koruma korkulugu (EN 81 gerekliligi) --------------------
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

	# kabin ustu revizyon kutusu
	Vis.box(self, Vector3(0.36, 0.22, 0.16), Vector3(-0.55, H + 0.20, 0.55), Vis.mat("panel"))
	var l := Vis.label(self, "REVIZYON", Vector3(-0.55, H + 0.35, 0.55), 0.00055,
			Color(0.9, 0.7, 0.2))
	l.outline_size = 0


## Kabin ici kaplama: inox paneller, ayna, kupeste, supurgelik
func _build_interior_finish() -> void:
	var inner_w := W * 0.5 - WALL - 0.005
	var inner_d := D * 0.5 - WALL - 0.005
	var rail_y := 0.90

	# --- arka duvar: alt inox + ust ayna ------------------------------------
	Vis.box(self, Vector3(W - 2 * WALL, rail_y - 0.02, 0.012),
			Vector3(0, (rail_y - 0.02) * 0.5, -inner_d), Vis.mat("inox"))
	Vis.box(self, Vector3(W - 2 * WALL - 0.10, H - rail_y - 0.22, 0.010),
			Vector3(0, rail_y + 0.06 + (H - rail_y - 0.22) * 0.5, -inner_d + 0.004),
			Vis.mat("mirror"))
	# ayna cercevesi
	Vis.box(self, Vector3(W - 2 * WALL - 0.06, 0.02, 0.016),
			Vector3(0, rail_y + 0.04, -inner_d + 0.002), Vis.mat("inox"))
	Vis.box(self, Vector3(W - 2 * WALL - 0.06, 0.02, 0.016),
			Vector3(0, H - 0.14, -inner_d + 0.002), Vis.mat("inox"))

	# --- yan duvarlar: dikey derzli inox paneller ---------------------------
	for sx: float in [-1.0, 1.0]:
		var x := sx * inner_w
		Vis.box(self, Vector3(0.012, H - 0.10, D - 2 * WALL),
				Vector3(x, (H - 0.10) * 0.5, 0), Vis.mat("inox"))
		# panel derz cizgileri
		for k in range(3):
			var z := -D * 0.5 + 0.42 + k * 0.42
			Vis.box(self, Vector3(0.016, H - 0.14, 0.008),
					Vector3(x - sx * 0.004, (H - 0.14) * 0.5 + 0.02, z), Vis.mat("inox_line"))
		# kupeste (yuvarlak paslanmaz boru)
		var rail := Vis.cyl(self, 0.019, D - 2 * WALL - 0.12,
				Vector3(x - sx * 0.055, rail_y, 0), Vis.mat("inox"))
		rail.rotation_degrees = Vector3(90, 0, 0)
		for sz: float in [-1.0, 1.0]:
			Vis.cyl(self, 0.014, 0.055, Vector3(x - sx * 0.028, rail_y,
					sz * (D * 0.5 - WALL - 0.09)), Vis.mat("inox")).rotation_degrees = \
					Vector3(0, 0, 90)

	# --- arka kupeste -------------------------------------------------------
	var brail := Vis.cyl(self, 0.019, W - 2 * WALL - 0.16,
			Vector3(0, rail_y, -inner_d + 0.055), Vis.mat("inox"))
	brail.rotation_degrees = Vector3(0, 0, 90)
	for sx2: float in [-1.0, 1.0]:
		Vis.cyl(self, 0.014, 0.055, Vector3(sx2 * (W * 0.5 - WALL - 0.10), rail_y,
				-inner_d + 0.028), Vis.mat("inox")).rotation_degrees = Vector3(90, 0, 0)

	# --- supurgelik ---------------------------------------------------------
	Vis.box(self, Vector3(W - 2 * WALL, 0.09, 0.014),
			Vector3(0, 0.045, -inner_d + 0.006), Vis.mat("inox_dark"))
	for sx3: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.014, 0.09, D - 2 * WALL),
				Vector3(sx3 * (inner_w - 0.006), 0.045, 0), Vis.mat("inox_dark"))

	# --- kapi ustu paslanmaz bant (header) ----------------------------------
	var fz := D * 0.5 - WALL - 0.006
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.30, 0.11, 0.014),
			Vector3(0, LiftCfg.M_DOOR_H + 0.055, fz), Vis.mat("inox"))
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.30, 0.012, 0.020),
			Vector3(0, LiftCfg.M_DOOR_H + 0.005, fz), Vis.mat("inox_line"))
	# kapi yanlarindaki donus panelleri (front return) derz cizgisi
	for sx7: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.012, LiftCfg.M_DOOR_H, 0.018),
				Vector3(sx7 * (LiftCfg.M_DOOR_W * 0.5 + 0.055),
						LiftCfg.M_DOOR_H * 0.5, fz), Vis.mat("inox_line"))

	# --- kabin ici kamera baglanti noktasi ----------------------------------
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
		# kapak kenar profili (kapanma tarafi)
		Vis.box(leaf, Vector3(0.012, LiftCfg.M_DOOR_H, LiftCfg.M_DOOR_T + 0.006),
				Vector3(-side * (lw * 0.5 - 0.006), LiftCfg.M_DOOR_H * 0.5, 0),
				Vis.mat("inox_dark"))
		# foto bariyer cubugu (kabin ici tarafta)
		Vis.box(leaf, Vector3(0.016, LiftCfg.M_DOOR_H - 0.18, 0.016),
				Vector3(-side * (lw * 0.5 - 0.012), LiftCfg.M_DOOR_H * 0.5, -0.038),
				Vis.mat("rubber"))
		if side < 0:
			door_left = leaf
		else:
			door_right = leaf

	# kapi operatoru (kabin ustu)
	Vis.box(self, Vector3(LiftCfg.M_DOOR_W + 0.3, 0.10, 0.10),
			Vector3(0, H + 0.14, D * 0.5 - 0.05), Vis.mat("steel_dark"))
	Vis.cyl(self, 0.07, 0.10, Vector3(-0.42, H + 0.14, D * 0.5 - 0.05),
			Vis.mat("steel")).rotation_degrees = Vector3(0, 0, 90)


## COP — kabin kumanda paneli (sag on donus duvarinda)
func _build_cop() -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(W * 0.5 - WALL - 0.012, 0, D * 0.5 - 0.34)
	pivot.rotation_degrees = Vector3(0, -90, 0)
	add_child(pivot)

	# --- panel plakasi ------------------------------------------------------
	Vis.box(pivot, Vector3(0.24, 1.36, 0.014), Vector3(0, 1.32, 0.007), Vis.mat("inox"))
	Vis.box(pivot, Vector3(0.225, 1.345, 0.004), Vector3(0, 1.32, 0.015),
			Vis.mat("inox_dark"))

	# --- kirmizi nokta-matris gosterge --------------------------------------
	Vis.box(pivot, Vector3(0.185, 0.115, 0.006), Vector3(0, 1.86, 0.017),
			Vis.mat("display_glass"))
	display = LedDisplay.create(pivot, Vector3(0, 1.86, 0.021), 0.165)

	# --- kat butonlari: 2 kolon, asagidan yukari ----------------------------
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

	# --- kapi ac / kapa / alarm ---------------------------------------------
	btn_open = Btn3D.create(pivot, "door_open", Vector3(-COP_X, 1.18, 0.020),
			"<|>", BTN_R * 0.92)
	btn_open.pushed.connect(_btn_cb)
	btn_close = Btn3D.create(pivot, "door_close", Vector3(COP_X, 1.18, 0.020),
			">|<", BTN_R * 0.92)
	btn_close.pushed.connect(_btn_cb)
	btn_alarm = Btn3D.create(pivot, "alarm", Vector3(-COP_X, 1.09, 0.020),
			"!", BTN_R * 0.92)
	btn_alarm.pushed.connect(_btn_cb)

	# anahtarli salter (sag alt)
	var ks := Vis.cyl(pivot, 0.015, 0.008, Vector3(COP_X, 1.09, 0.019), Vis.mat("inox_dark"))
	ks.rotation_degrees = Vector3(90, 0, 0)
	Vis.box(pivot, Vector3(0.004, 0.016, 0.004), Vector3(COP_X, 1.09, 0.024),
			Vis.mat("inox_line"))

	# --- acil telefon izgarasi ----------------------------------------------
	for r in range(4):
		for c in range(7):
			Vis.cyl(pivot, 0.0035, 0.004,
					Vector3(-0.048 + c * 0.016, 1.00 - r * 0.014, 0.016),
					Vis.mat("inox_line")).rotation_degrees = Vector3(90, 0, 0)

	# --- asiri yuk ikaz lambasi ---------------------------------------------
	overload_lamp = Vis.box(pivot, Vector3(0.104, 0.019, 0.004),
			Vector3(0, 1.762, 0.017), Vis.emissive(Color(0.10, 0.035, 0.03), 0.10))
	_overload_txt = Vis.label(pivot, "ASIRI YUK", Vector3(0, 1.762, 0.021), 0.000125,
			Color(0.34, 0.34, 0.35))
	_overload_txt.outline_size = 0

	# --- kabin kimlik plakasi -----------------------------------------------
	var cap := Vis.label(pivot, "630 kg / 8 kisi", Vector3(0, 0.93, 0.018), 0.00013,
			Color(0.28, 0.29, 0.31))
	cap.outline_size = 0

	# --- yuk gostergesi (panelde) -------------------------------------------
	load_lbl = Vis.label(pivot, "", Vector3(0, 0.90, 0.018), 0.00012,
			Color(0.34, 0.35, 0.38))
	load_lbl.outline_size = 0


func _build_ceiling() -> void:
	# asma tavan
	ceiling_panel = Vis.box(self, Vector3(W - 2 * WALL - 0.04, 0.025, D - 2 * WALL - 0.04),
			Vector3(0, H - 0.05, 0), Vis.mat("ceiling"))
	# cevre isik bandi
	for sx: float in [-1.0, 1.0]:
		Vis.box(self, Vector3(0.03, 0.02, D - 2 * WALL - 0.10),
				Vector3(sx * (W * 0.5 - WALL - 0.03), H - 0.055, 0),
				Vis.emissive(Color(1.0, 0.96, 0.90), 0.45))

	# 4 gomme spot — her biri kendi isigiyla (tek buyuk parlama yerine
	# gercek kabinlerdeki gibi dort ayri yumusak yansima)
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

	# genel dolgu (cok zayif)
	cabin_light = OmniLight3D.new()
	cabin_light.position = Vector3(0, H - 0.60, 0)
	cabin_light.light_energy = 0.35
	cabin_light.omni_range = 3.4
	cabin_light.light_color = Color(0.96, 0.97, 1.0)
	cabin_light.shadow_enabled = false
	add_child(cabin_light)

	# Kabin ici yansima probu: ayna ve paslanmaz yuzeyler kuyuyu/gokyuzunu degil
	# kabinin kendisini yansitsin (ekran-uzayi yansimasinin yapamadigi sey).
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
# CANLI GUNCELLEME
# =============================================================================
func set_door(amount: float) -> void:
	var travel := LiftCfg.M_DOOR_W * 0.5 * amount
	door_left.position.x = -LiftCfg.M_DOOR_W * 0.25 - travel
	door_right.position.x = LiftCfg.M_DOOR_W * 0.25 + travel


## Bu fonksiyonlar her karede cagriliyor; materyal degistirmek (ve
## Vis.emissive icindeki metin anahtari uretmek) yalnizca durum
## DEGISTIGINDE yapilmali.
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
