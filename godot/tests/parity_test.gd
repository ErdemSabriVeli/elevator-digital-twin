extends SceneTree

## ST <-> GDScript ESLESME TESTI
##
## Bu projede kontrol mantigi iki yerde yasiyor:
##   codesys/*.st        -> gercek PLC'de calisan kod
##   godot/scripts/*.gd  -> ayni mantigin GDScript ikizi
##
## Ikisi sessizce birbirinden kayarsa dijital ikiz gercek PLC'yi temsil etmez
## ve bunu fark etmek cok zordur. Bu test ST kaynagini AYRISTIRIR ve GDScript
## tarafiyla karsilastirir:
##   - GVL_Config.st sabitleri  <-> Config.gd
##   - DUT_Types.st enum'lari   <-> IoMap.gd (State / Fault / DoorState / yon)
##   - PLC_PRG.st bit indisleri <-> IoMap.gd (CMD / LIMIT / STATUS)
##
## Calistirma:
##   godot --headless --path <godot> --script res://tests/parity_test.gd

var failures := 0
var st_dir := ""


func _initialize() -> void:
	print("=== ST <-> GDScript ESLESME TESTI ===\n")
	st_dir = ProjectSettings.globalize_path("res://").path_join("../codesys")

	if not DirAccess.dir_exists_absolute(st_dir):
		print("  [HATA ] codesys klasoru bulunamadi: %s" % st_dir)
		quit(1)
		return

	test_constants()
	test_enums()
	test_bit_map()

	print("\n=== SONUC: %s ===" % ("ST ILE IKIZ ORTUSUYOR" if failures == 0
			else "%d UYUSMAZLIK" % failures))
	quit(1 if failures > 0 else 0)


func check(name: String, ok: bool, detail := "") -> void:
	if not ok:
		failures += 1
		print("  [HATA ] %s %s" % [name, detail])


func ok_line(text: String) -> void:
	print("  [gecti] %s" % text)


func read_st(fname: String) -> String:
	var f := FileAccess.open(st_dir.path_join(fname), FileAccess.READ)
	if f == null:
		check("dosya okunabildi: %s" % fname, false)
		return ""
	var s := f.get_as_text()
	f.close()
	return s


## "T#600MS" / "T#4S" -> saniye
func parse_time(lit: String) -> float:
	var t := lit.strip_edges().to_upper()
	if not t.begins_with("T#"):
		return -1.0
	t = t.substr(2)
	var total := 0.0
	var re := RegEx.new()
	re.compile("(\\d+)(MS|S|M|H)")
	for m in re.search_all(t):
		var v := float(m.get_string(1))
		match m.get_string(2):
			"MS": total += v * 0.001
			"S": total += v
			"M": total += v * 60.0
			"H": total += v * 3600.0
	return total


# =============================================================================
func test_constants() -> void:
	print("1) GVL_Config.st  <->  Config.gd sabitleri")

	var src := read_st("GVL_Config.st")
	if src == "":
		return

	var cfg: Dictionary = load("res://scripts/Config.gd").get_script_constant_map()

	var re := RegEx.new()
	re.compile("(?m)^\\s*(C_[A-Z0-9_]+)\\s*:\\s*([A-Z]+)\\s*:=\\s*([^;]+);")

	var matches := re.search_all(src)
	check("ST sabitleri ayristirildi", matches.size() > 15,
			"(sadece %d sabit bulundu)" % matches.size())

	var n := 0
	var bad := 0
	for m in matches:
		var st_name := m.get_string(1)
		var st_type := m.get_string(2)
		var st_val := m.get_string(3).strip_edges()
		var gd_name := st_name.substr(2)   # C_ onekini at

		if not cfg.has(gd_name):
			check("%s -> Config.gd icinde karsiligi yok (%s)" % [st_name, gd_name], false)
			bad += 1
			continue

		var gd_val = cfg[gd_name]
		var good := false
		var shown := ""

		if st_type == "TIME":
			var sec := parse_time(st_val)
			good = is_equal_approx(float(gd_val), sec)
			shown = "ST %s = %.3f s, GD %s" % [st_val, sec, str(gd_val)]
		else:
			good = int(st_val) == int(gd_val)
			shown = "ST %s, GD %s" % [st_val, str(gd_val)]

		if not good:
			check("%s UYUSMUYOR" % st_name, false, "(%s)" % shown)
			bad += 1
		n += 1

	if bad == 0:
		ok_line("%d sabitin tamami ortusuyor" % n)


# =============================================================================
func test_enums() -> void:
	print("\n2) DUT_Types.st  <->  IoMap.gd enum'lari")

	var src := read_st("DUT_Types.st")
	if src == "":
		return

	var io: Dictionary = load("res://scripts/IoMap.gd").get_script_constant_map()

	_cmp_enum(src, "E_LiftState", "LS_", io.get("State", {}), "State")
	_cmp_enum(src, "E_Fault", "FLT_", io.get("Fault", {}), "Fault")
	_cmp_enum(src, "E_DoorState", "DS_", io.get("DoorState", {}), "DoorState")

	# Yon enum'u IoMap'te ayri sabitler olarak duruyor
	var dirs := _parse_enum(src, "E_Direction")
	var dir_map := {
		"DIR_NONE": io.get("DIR_NONE"),
		"DIR_UP": io.get("DIR_UP"),
		"DIR_DOWN": io.get("DIR_DOWN"),
	}
	var bad := 0
	for k in dirs:
		if dirs[k] != dir_map.get(k):
			check("E_Direction.%s" % k, false,
					"(ST %d, GD %s)" % [dirs[k], str(dir_map.get(k))])
			bad += 1
	if bad == 0 and dirs.size() > 0:
		ok_line("E_Direction (%d deger) ortusuyor" % dirs.size())


func _parse_enum(src: String, type_name: String) -> Dictionary:
	var out := {}
	var block := RegEx.new()
	block.compile("(?s)TYPE\\s+%s\\s*:\\s*\\((.*?)\\)\\s*INT\\s*;" % type_name)
	var bm := block.search(src)
	if bm == null:
		return out
	var body := bm.get_string(1)
	var re := RegEx.new()
	re.compile("([A-Z][A-Z0-9_]*)\\s*:=\\s*(\\d+)")
	for m in re.search_all(body):
		out[m.get_string(1)] = int(m.get_string(2))
	return out


func _cmp_enum(src: String, type_name: String, prefix: String,
		gd_enum: Dictionary, gd_label: String) -> void:
	var st_enum := _parse_enum(src, type_name)
	check("%s ayristirilamadi" % type_name, st_enum.size() > 0)
	if st_enum.is_empty():
		return

	var bad := 0
	for st_key in st_enum:
		var gd_key: String = st_key.substr(prefix.length())
		if not gd_enum.has(gd_key):
			check("%s.%s -> IoMap.%s icinde yok" % [type_name, st_key, gd_label], false)
			bad += 1
			continue
		if st_enum[st_key] != gd_enum[gd_key]:
			check("%s.%s" % [type_name, st_key], false,
					"(ST %d, GD %d)" % [st_enum[st_key], gd_enum[gd_key]])
			bad += 1
	if bad == 0:
		ok_line("%s (%d deger) ortusuyor" % [type_name, st_enum.size()])


# =============================================================================
func test_bit_map() -> void:
	print("\n3) PLC_PRG.st  <->  IoMap.gd bit indisleri")

	var src := read_st("PLC_PRG.st")
	if src == "":
		return

	var io: Dictionary = load("res://scripts/IoMap.gd").get_script_constant_map()

	var cmd_map := {
		"xDoorOpenBtn": "CMD_DOOR_OPEN", "xDoorCloseBtn": "CMD_DOOR_CLOSE",
		"xAlarmBtn": "CMD_ALARM", "xEStop": "CMD_ESTOP",
		"xOverload": "CMD_OVERLOAD", "xFireCall": "CMD_FIRE",
		"xInspection": "CMD_INSPECTION", "xFaultReset": "CMD_RESET",
		"xObstruction": "CMD_OBSTRUCTION", "xDriveReady": "CMD_DRIVE_READY",
		"xDriveFault": "CMD_DRIVE_FAULT", "xInspUp": "CMD_INSP_UP",
		"xInspDown": "CMD_INSP_DOWN",
	}
	var lim_map := {
		"xTopLimit": "LIM_TOP", "xBotLimit": "LIM_BOTTOM",
		"xDoorOpenLimit": "LIM_DOOR_OPEN", "xDoorCloseLimit": "LIM_DOOR_CLOSE",
		"xDoorLocked": "LIM_DOOR_LOCK", "xBrakeFb": "LIM_BRAKE_FB",
		"xSafetyChain": "LIM_SAFETY", "xGovernorOk": "LIM_GOVERNOR",
	}
	_cmp_getbits(src, "wCmd", cmd_map, io)
	_cmp_getbits(src, "wLim", lim_map, io)

	var st_map := {
		"xMoving": "ST_MOVING", "xDoorIsOpen": "ST_DOOR_OPEN",
		"xDoorIsClosed": "ST_DOOR_CLOSED", "xOverloadLamp": "ST_OVERLOAD",
		"xFaultLamp": "ST_FAULT", "xFireMode": "ST_FIRE",
		"xInspMode": "ST_INSPECTION", "xOutOfService": "ST_OUT_OF_SVC",
		"xGong": "ST_GONG", "xCabinLight": "ST_CABIN_LIGHT",
		"xAlarm": "ST_ALARM",
	}
	var re := RegEx.new()
	re.compile("F_SetBit\\(wTmp,\\s*(\\d+),\\s*GVL_IO\\.g_stOut\\.(\\w+)\\)")
	var seen := {}
	for m in re.search_all(src):
		var field := m.get_string(2)
		if st_map.has(field):
			seen[field] = int(m.get_string(1))

	var bad := 0
	for field in st_map:
		var const_name: String = st_map[field]
		if not seen.has(field):
			check("STATUS.%s ST tarafinda yazilmiyor" % field, false)
			bad += 1
			continue
		if seen[field] != io.get(const_name):
			check("STATUS bit %s" % field, false,
					"(ST %d, GD %s=%s)" % [seen[field], const_name,
					str(io.get(const_name))])
			bad += 1
	if bad == 0:
		ok_line("STATUS (%d bit) ortusuyor" % st_map.size())


func _cmp_getbits(src: String, word: String, name_map: Dictionary,
		io: Dictionary) -> void:
	var re := RegEx.new()
	re.compile("GVL_IO\\.g_stIn\\.(\\w+)\\s*:=\\s*F_GetBit\\(%s,\\s*(\\d+)\\)" % word)
	var seen := {}
	for m in re.search_all(src):
		seen[m.get_string(1)] = int(m.get_string(2))

	var bad := 0
	for field in name_map:
		var const_name: String = name_map[field]
		if not seen.has(field):
			check("%s.%s ST tarafinda okunmuyor" % [word, field], false)
			bad += 1
			continue
		if seen[field] != io.get(const_name):
			check("%s bit %s" % [word, field], false,
					"(ST %d, GD %s=%s)" % [seen[field], const_name,
					str(io.get(const_name))])
			bad += 1
	if bad == 0:
		ok_line("%s (%d bit) ortusuyor" % [word, name_map.size()])
