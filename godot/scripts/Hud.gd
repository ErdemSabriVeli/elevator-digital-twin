class_name LiftHud
extends CanvasLayer

## Operator arayuzu: durum paneli, canli Modbus register tablosu,
## cagri butonlari ve ariza enjeksiyon anahtarlari.

signal btn_pressed(key: String)
signal sw_toggled(name: String, value: bool)
signal plc_mode_requested(mode: int)
signal connect_requested(host: String, port: int)
signal load_changed(kg: int)
signal cam_requested(mode: int)
signal lobby_floor_changed(f: int)

const FONT_S := 12
const FONT_M := 14
const FONT_L := 17

var _status: Label
var _regs: Label
var _fault: Label
var _conn: Label
var _load_lbl: Label
var _host_edit: LineEdit
var _port_edit: LineEdit
var _btn_soft: Button
var _btn_modbus: Button
var _switches := {}
var _root: Control


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_status_panel()
	_build_register_panel()
	_build_control_panel()
	_build_help()


# =============================================================================
func _panel(pos_preset: int, offset: Vector2, min_size := Vector2.ZERO) -> VBoxContainer:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.86)
	sb.border_color = Color(0.30, 0.34, 0.40, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_preset(pos_preset)
	pc.position += offset
	pc.custom_minimum_size = min_size
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(pc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	pc.add_child(vb)
	return vb


func _title(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_S)
	l.add_theme_color_override("font_color", Color(0.55, 0.72, 0.95))
	parent.add_child(l)
	return l


func _sep(parent: Node) -> void:
	var s := HSeparator.new()
	parent.add_child(s)


# =============================================================================
func _build_status_panel() -> void:
	var vb := _panel(Control.PRESET_TOP_LEFT, Vector2(14, 14), Vector2(330, 0))

	_conn = Label.new()
	_conn.add_theme_font_size_override("font_size", FONT_M)
	vb.add_child(_conn)

	_sep(vb)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", FONT_M)
	_status.add_theme_color_override("font_color", Color(0.88, 0.91, 0.95))
	vb.add_child(_status)

	_fault = Label.new()
	_fault.add_theme_font_size_override("font_size", FONT_M)
	_fault.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	vb.add_child(_fault)


func _build_register_panel() -> void:
	var vb := _panel(Control.PRESET_TOP_RIGHT, Vector2(-320, 14), Vector2(306, 0))
	_title(vb, "MODBUS REGISTER  (canli)")
	_regs = Label.new()
	_regs.add_theme_font_size_override("font_size", FONT_S)
	_regs.add_theme_color_override("font_color", Color(0.72, 0.85, 0.72))
	vb.add_child(_regs)


func _build_control_panel() -> void:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	sb.border_color = Color(0.30, 0.34, 0.40, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	pc.add_theme_stylebox_override("panel", sb)
	pc.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	pc.position += Vector2(14, -596)
	pc.custom_minimum_size = Vector2(300, 582)
	_root.add_child(pc)

	var sc := ScrollContainer.new()
	pc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(268, 0)
	vb.add_theme_constant_override("separation", 4)
	sc.add_child(vb)

	# --- PLC secimi ---------------------------------------------------------
	_title(vb, "KONTROL KAYNAGI")
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	_btn_soft = _mk_button(hb, "SoftPLC", func(): plc_mode_requested.emit(PlcLink.Mode.SOFT))
	_btn_modbus = _mk_button(hb, "CODESYS", func(): plc_mode_requested.emit(PlcLink.Mode.MODBUS))

	var hb2 := HBoxContainer.new()
	vb.add_child(hb2)
	_host_edit = LineEdit.new()
	_host_edit.text = "127.0.0.1"
	_host_edit.custom_minimum_size = Vector2(120, 0)
	_host_edit.add_theme_font_size_override("font_size", FONT_S)
	hb2.add_child(_host_edit)
	_port_edit = LineEdit.new()
	_port_edit.text = "502"
	_port_edit.custom_minimum_size = Vector2(52, 0)
	_port_edit.add_theme_font_size_override("font_size", FONT_S)
	hb2.add_child(_port_edit)
	_mk_button(hb2, "Baglan", func():
		connect_requested.emit(_host_edit.text, int(_port_edit.text)))

	_sep(vb)

	# --- kat cagrilari ------------------------------------------------------
	_title(vb, "KAT HOLU CAGRILARI")
	for f in range(LiftCfg.TOP_FLOOR, -1, -1):
		var row := HBoxContainer.new()
		vb.add_child(row)
		var l := Label.new()
		l.text = "Kat %s" % LiftIo.floor_name(f)
		l.custom_minimum_size = Vector2(52, 0)
		l.add_theme_font_size_override("font_size", FONT_S)
		row.add_child(l)
		if f < LiftCfg.TOP_FLOOR:
			_mk_button(row, "^ yukari", _emit_btn.bind("hall_up_%d" % f), 88)
		else:
			_spacer(row, 88)
		if f > 0:
			_mk_button(row, "v asagi", _emit_btn.bind("hall_down_%d" % f), 88)
		else:
			_spacer(row, 88)

	_sep(vb)

	# --- kabin ici ----------------------------------------------------------
	_title(vb, "KABIN ICI")
	var grid := GridContainer.new()
	grid.columns = 3
	vb.add_child(grid)
	for f in range(LiftCfg.FLOOR_COUNT):
		_mk_button(grid, LiftIo.floor_name(f), _emit_btn.bind("car_%d" % f), 82)

	var hb3 := HBoxContainer.new()
	vb.add_child(hb3)
	_mk_button(hb3, "Kapi AC", _emit_btn.bind("door_open"), 82)
	_mk_button(hb3, "Kapi KAPA", _emit_btn.bind("door_close"), 82)
	_mk_button(hb3, "Alarm", _emit_btn.bind("alarm"), 82)

	_sep(vb)

	# --- ariza / mod --------------------------------------------------------
	_title(vb, "ARIZA VE MOD ENJEKSIYONU")
	_mk_switch(vb, "estop", "Acil stop (E)")
	_mk_switch(vb, "safety", "Guvenlik zinciri KOPUK")
	_mk_switch(vb, "drive", "Surucu arizasi")
	_mk_switch(vb, "fire", "Yangin modu")
	_mk_switch(vb, "inspection", "Revizyon modu")
	_mk_switch(vb, "obstruction", "Foto bariyer surekli kesik")
	_mk_switch(vb, "slip", "Halat kaymasi (encoder)")
	_mk_switch(vb, "brake", "Fren takili kaldi")
	_mk_switch(vb, "overspeed", "Surucu kacagi (asiri hiz)")
	_mk_switch(vb, "jam", "Kabin sikisti")

	var hb4 := HBoxContainer.new()
	vb.add_child(hb4)
	_mk_button(hb4, "Yolcu gecti (darbe)", _emit_btn.bind("obstruct"), 128)
	_mk_button(hb4, "ARIZA RESET", _emit_btn.bind("reset"), 118)

	var hb5 := HBoxContainer.new()
	vb.add_child(hb5)
	_mk_button(hb5, "Revizyon ^", _emit_btn.bind("insp_up"), 118)
	_mk_button(hb5, "Revizyon v", _emit_btn.bind("insp_down"), 118)

	_sep(vb)

	# --- yuk ----------------------------------------------------------------
	_load_lbl = Label.new()
	_load_lbl.add_theme_font_size_override("font_size", FONT_S)
	_load_lbl.text = "Kabin yuku: 75 kg"
	vb.add_child(_load_lbl)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 900
	sl.step = 5
	sl.value = 75
	sl.custom_minimum_size = Vector2(260, 18)
	sl.value_changed.connect(func(v):
		_load_lbl.text = "Kabin yuku: %d kg   %s" % [int(v),
				"(ASIRI YUK)" if int(v) > LiftCfg.LOAD_OVER_KG else ""]
		load_changed.emit(int(v)))
	vb.add_child(sl)

	_sep(vb)

	# --- kamera -------------------------------------------------------------
	_title(vb, "KAMERA")
	var hb6 := HBoxContainer.new()
	vb.add_child(hb6)
	_mk_button(hb6, "Dis", func(): cam_requested.emit(CamRig.Mode.ORBIT), 60)
	_mk_button(hb6, "Kabin", func(): cam_requested.emit(CamRig.Mode.INTERIOR), 60)
	_mk_button(hb6, "Hol", func(): cam_requested.emit(CamRig.Mode.LOBBY), 60)
	_mk_button(hb6, "Makine", func(): cam_requested.emit(CamRig.Mode.MACHINE), 68)

	var hb7 := HBoxContainer.new()
	vb.add_child(hb7)
	var lf := Label.new()
	lf.text = "Hol kati:"
	lf.add_theme_font_size_override("font_size", FONT_S)
	hb7.add_child(lf)
	for f in range(LiftCfg.FLOOR_COUNT):
		_mk_button(hb7, LiftIo.floor_name(f), func(): lobby_floor_changed.emit(f), 30)


func _build_help() -> void:
	var l := Label.new()
	l.text = "Sag tik: dondur  |  Tekerlek: zoom  |  Orta tik: kaydir  |  " \
		+ "1-4: kamera  |  F: kabini takip  |  F1: PLC kaynagi  |  F2: paneller  |  " \
		+ "3D butonlara sol tik"
	l.add_theme_font_size_override("font_size", FONT_S)
	l.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	l.position += Vector2(0, -22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(l)


# =============================================================================
func _mk_button(parent: Node, text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", FONT_S)
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 24)
	else:
		b.custom_minimum_size = Vector2(0, 24)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _spacer(parent: Node, w: int) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 1)
	parent.add_child(c)


func _mk_switch(parent: Node, name: String, text: String) -> CheckButton:
	var cb := CheckButton.new()
	cb.text = text
	cb.add_theme_font_size_override("font_size", FONT_S)
	cb.custom_minimum_size = Vector2(0, 22)
	cb.toggled.connect(func(v): sw_toggled.emit(name, v))
	parent.add_child(cb)
	_switches[name] = cb
	return cb


func _emit_btn(key: String) -> void:
	btn_pressed.emit(key)


func set_switch(name: String, v: bool) -> void:
	if _switches.has(name):
		_switches[name].set_pressed_no_signal(v)


func toggle_visible() -> void:
	_root.visible = not _root.visible


# =============================================================================
# CANLI GUNCELLEME
# =============================================================================
## Arayuz 60 Hz'de guncellenmeye gerek duymaz; metin uretimi (ozellikle
## register tablosu) her karede yapilinca bosuna CPU ve cop uretimi olur.
const UI_HZ := 15.0
var _ui_acc := 999.0


func update_view(plant: LiftPlant, link: PlcLink,
		regs_in: PackedInt32Array, regs_out: PackedInt32Array,
		delta := 0.0) -> void:
	_ui_acc += delta
	if _ui_acc < 1.0 / UI_HZ:
		return
	_ui_acc = 0.0

	# --- baglanti -----------------------------------------------------------
	var col := Color(0.35, 0.95, 0.45)
	var head := ""
	if link.mode == PlcLink.Mode.SOFT:
		head = "● SoftPLC  (ST kodunun Godot ikizi)"
		col = Color(0.45, 0.75, 1.0)
	elif link.mb.online:
		head = "● CODESYS BAGLI  %s:%d   rtt %d ms" % [link.host, link.port, link.mb.rtt_ms]
	else:
		head = "● CODESYS YOK  %s:%d %s" % [link.host, link.port,
				"→ SoftPLC yedegi" if link.using_fallback else ""]
		col = Color(1.0, 0.55, 0.30)
	_conn.text = head
	_conn.add_theme_color_override("font_color", col)

	_btn_soft.disabled = link.mode == PlcLink.Mode.SOFT
	_btn_modbus.disabled = link.mode == PlcLink.Mode.MODBUS

	# --- durum --------------------------------------------------------------
	var st: int = regs_out[LiftIo.OUT_STATE]
	var cur: int = regs_out[LiftIo.OUT_CUR_FLOOR]
	var tgt: int = regs_out[LiftIo.OUT_TGT_FLOOR]
	var dir: int = regs_out[LiftIo.OUT_DIRECTION]
	var status_bits: int = regs_out[LiftIo.OUT_STATUS]

	var tgt_txt := "-" if tgt > LiftCfg.TOP_FLOOR else LiftIo.floor_name(tgt)

	var lines := []
	lines.append("Durum      : %s" % LiftIo.STATE_TEXT.get(st, str(st)))
	lines.append("Kat        : %s      Hedef: %s" % [LiftIo.floor_name(cur), tgt_txt])
	lines.append("Yon        : %s" % LiftIo.DIR_TEXT.get(dir, "-"))
	lines.append("Hiz        : %4d mm/s  (ref %d)" % [
			int(absf(plant.speed_mms)), regs_out[LiftIo.OUT_SPEED_SP]])
	lines.append("Konum      : %6.0f mm  (%.2f m)" % [plant.pos_mm, plant.pos_mm * 0.001])
	lines.append("Kapi       : %3d %%   %s" % [int(plant.door_pos * 100.0),
			"BEKLEME %.1f s" % (regs_out[LiftIo.OUT_DOOR_TIMER] / 1000.0)
			if regs_out[LiftIo.OUT_DOOR_TIMER] > 0 else ""])
	lines.append("Yuk        : %d kg %s" % [plant.load_kg,
			"ASIRI YUK" if LiftIo.get_bit(status_bits, LiftIo.ST_OVERLOAD) else ""])
	lines.append("Fren       : %s     Surucu: %s" % [
			"TUTUYOR" if plant.brake_engaged else "COZULDU",
			"ENABLE" if plant.c_drive_enable else "off"])
	lines.append("Sefer      : %d      Yol: %.1f m" % [
			plant.trip_count, plant.travel_distance_mm * 0.001])
	_status.text = "\n".join(lines)

	var flt: int = regs_out[LiftIo.OUT_FAULT]
	if flt != 0:
		_fault.text = "ARIZA %d: %s   (RESET ile silinir)" % [flt,
				LiftIo.FAULT_TEXT.get(flt, "?")]
	elif LiftIo.get_bit(status_bits, LiftIo.ST_INSPECTION):
		_fault.text = "REVIZYON MODU"
	elif LiftIo.get_bit(status_bits, LiftIo.ST_FIRE):
		_fault.text = "YANGIN MODU - tahliye kati"
	else:
		_fault.text = ""

	# --- register tablosu ---------------------------------------------------
	var names_in := ["HALL_UP", "HALL_DOWN", "CAR_CALL", "CMD", "FLOOR_ZONE",
			"LIMITS", "POS_MM", "SPEED", "DOOR_PMIL", "LOAD_KG", "HB"]
	var names_out := ["DRIVE_CMD", "DOOR_CMD", "LAMP_UP", "LAMP_DN", "LAMP_CAR",
			"STATUS", "CUR_FLR", "TGT_FLR", "DIR", "SPEED_SP", "STATE", "FAULT",
			"HB", "DOOR_T"]

	var t := "-- Godot > PLC (holding) --\n"
	for i in range(names_in.size()):
		t += "%2d %-10s %5d  %s\n" % [i, names_in[i], regs_in[i], _bits(regs_in[i], i <= 5)]
	t += "\n-- PLC > Godot (input) --\n"
	for i in range(names_out.size()):
		t += "%2d %-10s %5d  %s\n" % [i, names_out[i], regs_out[i],
				_bits(regs_out[i], i <= 5)]
	_regs.text = t


func _bits(v: int, show: bool) -> String:
	if not show:
		return ""
	var s := ""
	for b in range(11, -1, -1):
		s += "1" if LiftIo.get_bit(v, b) else "."
	return s
