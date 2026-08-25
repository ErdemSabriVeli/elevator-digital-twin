extends SceneTree

## ST STATIK DENETIMI
##
## codesys/*.st dosyalari CODESYS olmadan derlenemez. Bu denetim, derleyicinin
## yakalayacagi hatalarin buyuk bolumunu kaynak uzerinden yakalar:
##
##   A) Blok dengesi        IF/CASE/FOR/WHILE/VAR_*/TYPE/STRUCT/METHOD
##   B) Sabitler            kullanilan her C_* GVL_Config.st'de tanimli mi
##   C) Enum literalleri    FLT_/LS_/DS_/DIR_ DUT_Types.st'de var mi
##   D) Struct alanlari     stIn./stOut. alanlari DUT'ta tanimli mi
##   E) Metot cagrilari     fbX.Metot() hedef FB'de METHOD olarak var mi
##   F) FB parametreleri    fbX(ad := ...) icindeki ad, FB'nin girisi mi
##
## NE YAPMAZ: tip denetimi, ifade dogrulugu, gercek derleme. Bunlar ancak
## CODESYS'te derleyerek dogrulanir.
##
## Calistirma:
##   godot --headless --path <godot> --script res://tests/st_lint_test.gd

var failures := 0
var st_dir := ""
var files: Dictionary = {}          # dosya adi -> yorumlari temizlenmis metin


func _initialize() -> void:
	print("=== ST STATIK DENETIMI ===\n")
	st_dir = ProjectSettings.globalize_path("res://").path_join("../codesys")

	if not _load_files():
		quit(1)
		return

	check_block_balance()
	check_constants()
	check_enum_literals()
	check_struct_fields()
	check_method_calls()
	check_fb_parameters()

	print("\n=== SONUC: %s ===" % ("ST KAYNAGI TUTARLI" if failures == 0
			else "%d SORUN" % failures))
	quit(1 if failures > 0 else 0)


func fail(msg: String) -> void:
	failures += 1
	print("  [HATA ] %s" % msg)


func ok_line(msg: String) -> void:
	print("  [gecti] %s" % msg)


## (* ... *) ve // ... yorumlarini temizler
func strip_comments(src: String) -> String:
	var re_block := RegEx.new()
	re_block.compile("(?s)\\(\\*.*?\\*\\)")
	var s := re_block.sub(src, "", true)
	var re_line := RegEx.new()
	re_line.compile("//[^\n]*")
	return re_line.sub(s, "", true)


func _load_files() -> bool:
	var d := DirAccess.open(st_dir)
	if d == null:
		fail("codesys klasoru acilamadi: %s" % st_dir)
		return false
	for f in d.get_files():
		if not f.ends_with(".st"):
			continue
		var fa := FileAccess.open(st_dir.path_join(f), FileAccess.READ)
		if fa == null:
			continue
		files[f] = strip_comments(fa.get_as_text())
		fa.close()
	if files.is_empty():
		fail("hic .st dosyasi bulunamadi")
		return false
	return true


func count_word(src: String, word: String) -> int:
	var re := RegEx.new()
	re.compile("\\b%s\\b" % word)
	return re.search_all(src).size()


# =============================================================================
# A) Blok dengesi
# =============================================================================
func check_block_balance() -> void:
	print("A) Blok dengesi")

	# NOT: bu dosyalar CODESYS'e yapistirmak icin hazirlanmistir; POU govdesi
	# ile bildirimi ayni dosyadadir, bu yuzden FUNCTION_BLOCK/PROGRAM icin
	# END_ karsiligi aranmaz. METHOD'un END_METHOD'u vardir.
	var pairs := [
		["IF", "END_IF"], ["CASE", "END_CASE"], ["FOR", "END_FOR"],
		["WHILE", "END_WHILE"], ["REPEAT", "END_REPEAT"],
		["STRUCT", "END_STRUCT"], ["TYPE", "END_TYPE"],
		["METHOD", "END_METHOD"],
	]
	var bad := 0
	for fname in files:
		var src: String = files[fname]
		for p in pairs:
			var o := count_word(src, p[0])
			var c := count_word(src, p[1])
			if o != c:
				fail("%s: %s=%d fakat %s=%d" % [fname, p[0], o, p[1], c])
				bad += 1

		# VAR / VAR_INPUT / VAR_OUTPUT / VAR_IN_OUT / VAR_GLOBAL  <-> END_VAR
		var re_var := RegEx.new()
		re_var.compile("\\bVAR(_INPUT|_OUTPUT|_IN_OUT|_GLOBAL|_TEMP|_STAT)?\\b")
		var nv := re_var.search_all(src).size()
		var ne := count_word(src, "END_VAR")
		if nv != ne:
			fail("%s: VAR blogu=%d fakat END_VAR=%d" % [fname, nv, ne])
			bad += 1

	if bad == 0:
		ok_line("%d dosyada blok dengesi tamam" % files.size())


# =============================================================================
# B) Sabitler
# =============================================================================
func check_constants() -> void:
	print("\nB) Sabitler (C_*)")

	var cfg: String = files.get("GVL_Config.st", "")
	if cfg == "":
		fail("GVL_Config.st bulunamadi")
		return

	var declared := {}
	var re_decl := RegEx.new()
	re_decl.compile("(?m)^\\s*(C_[A-Z0-9_]+)\\s*:")
	for m in re_decl.search_all(cfg):
		declared[m.get_string(1)] = true

	var re_use := RegEx.new()
	re_use.compile("\\bC_[A-Z0-9_]+\\b")
	var bad := 0
	var seen := {}
	for fname in files:
		for m in re_use.search_all(files[fname]):
			var name := m.get_string(0)
			if not declared.has(name):
				var key := "%s|%s" % [fname, name]
				if not seen.has(key):
					seen[key] = true
					fail("%s: %s GVL_Config.st'de tanimli degil" % [fname, name])
					bad += 1
	if bad == 0:
		ok_line("%d sabit tanimi, tum kullanimlar cozumlendi" % declared.size())


# =============================================================================
# C) Enum literalleri
# =============================================================================
func check_enum_literals() -> void:
	print("\nC) Enum literalleri")

	var dut: String = files.get("DUT_Types.st", "")
	if dut == "":
		fail("DUT_Types.st bulunamadi")
		return

	var declared := {}
	var re_decl := RegEx.new()
	re_decl.compile("\\b(FLT|LS|DS|DIR)_[A-Z0-9_]+\\s*:=\\s*\\d+")
	for m in re_decl.search_all(dut):
		declared[m.get_string(0).split(":=")[0].strip_edges()] = true

	var re_use := RegEx.new()
	re_use.compile("\\b(FLT|LS|DS|DIR)_[A-Z0-9_]+\\b")
	var bad := 0
	var seen := {}
	for fname in files:
		for m in re_use.search_all(files[fname]):
			var name := m.get_string(0)
			if not declared.has(name):
				var key := "%s|%s" % [fname, name]
				if not seen.has(key):
					seen[key] = true
					fail("%s: %s DUT_Types.st'de tanimli degil" % [fname, name])
					bad += 1
	if bad == 0:
		ok_line("%d enum literali, tum kullanimlar cozumlendi" % declared.size())


# =============================================================================
# D) Struct alanlari
# =============================================================================
func check_struct_fields() -> void:
	print("\nD) Struct alanlari (stIn / stOut)")

	var dut: String = files.get("DUT_Types.st", "")
	if dut == "":
		return

	var fin := _struct_fields(dut, "ST_LiftInputs")
	var fout := _struct_fields(dut, "ST_LiftOutputs")
	if fin.is_empty() or fout.is_empty():
		fail("ST_LiftInputs / ST_LiftOutputs ayristirilamadi")
		return

	var bad := 0
	bad += _check_fields("stIn", fin)
	bad += _check_fields("stOut", fout)
	if bad == 0:
		ok_line("stIn (%d alan) ve stOut (%d alan) kullanimlari cozumlendi"
				% [fin.size(), fout.size()])


func _struct_fields(dut: String, type_name: String) -> Dictionary:
	var out := {}
	var re_block := RegEx.new()
	re_block.compile("(?s)TYPE\\s+%s\\s*:\\s*STRUCT(.*?)END_STRUCT" % type_name)
	var m := re_block.search(dut)
	if m == null:
		return out
	var re_f := RegEx.new()
	re_f.compile("(?m)^\\s*([a-zA-Z_][A-Za-z0-9_]*)\\s*:")
	for fm in re_f.search_all(m.get_string(1)):
		out[fm.get_string(1)] = true
	return out


func _check_fields(prefix: String, fields: Dictionary) -> int:
	var re := RegEx.new()
	re.compile("\\b(?:g_)?%s\\.([A-Za-z0-9_]+)" % prefix)
	var bad := 0
	var seen := {}
	for fname in files:
		for m in re.search_all(files[fname]):
			var field := m.get_string(1)
			if not fields.has(field):
				var key := "%s|%s.%s" % [fname, prefix, field]
				if not seen.has(key):
					seen[key] = true
					fail("%s: %s.%s struct'ta yok" % [fname, prefix, field])
					bad += 1
	return bad


# =============================================================================
# E) Metot cagrilari
# =============================================================================
func check_method_calls() -> void:
	print("\nE) FB metot cagrilari")

	var fb_methods := {}      # FB_Xxx -> {metot: true}
	for fname in files:
		if not fname.begins_with("FB_"):
			continue
		var fb: String = fname.get_basename()
		var re := RegEx.new()
		re.compile("(?m)^\\s*METHOD\\s+([A-Za-z0-9_]+)")
		var set := {}
		for m in re.search_all(files[fname]):
			set[m.get_string(1)] = true
		fb_methods[fb] = set

	var bad := 0
	for fname in files:
		var inst := _instance_types(files[fname])
		var re_call := RegEx.new()
		re_call.compile("\\b(fb[A-Za-z0-9_]*)\\.([A-Za-z][A-Za-z0-9_]*)\\s*\\(")
		var seen := {}
		for m in re_call.search_all(files[fname]):
			var iname := m.get_string(1)
			var meth := m.get_string(2)
			if not inst.has(iname):
				continue
			var fbtype: String = inst[iname]
			if not fb_methods.has(fbtype):
				continue
			if not fb_methods[fbtype].has(meth):
				var key := "%s|%s.%s" % [fname, iname, meth]
				if not seen.has(key):
					seen[key] = true
					fail("%s: %s.%s() -> %s icinde METHOD yok"
							% [fname, iname, meth, fbtype])
					bad += 1
	if bad == 0:
		ok_line("tum fbX.Metot() cagrilari hedef FB'de bulundu")


## "fbSafety : FB_Safety;" bildirimlerinden ornek -> tip haritasi
func _instance_types(src: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("\\b(fb[A-Za-z0-9_]*)\\s*:\\s*(FB_[A-Za-z0-9_]+)")
	for m in re.search_all(src):
		out[m.get_string(1)] = m.get_string(2)
	return out


# =============================================================================
# F) FB cagri parametreleri
# =============================================================================
func check_fb_parameters() -> void:
	print("\nF) FB cagri parametreleri")

	# her FB'nin girdi/cikti degisken adlari
	var fb_params := {}
	for fname in files:
		if not fname.begins_with("FB_"):
			continue
		var fbn: String = fname.get_basename()
		fb_params[fbn] = _fb_io_names(files[fname])

	var bad := 0
	for fname in files:
		var inst := _instance_types(files[fname])
		# cok satirli govde cagrisi:  fbX( ad := ..., ad2 := ... );
		var re_call := RegEx.new()
		re_call.compile("(?s)\\b(fb[A-Za-z0-9_]*)\\s*\\(([^;]*?)\\)\\s*;")
		for m in re_call.search_all(files[fname]):
			var iname := m.get_string(1)
			if not inst.has(iname):
				continue
			var fbtype: String = inst[iname]
			if not fb_params.has(fbtype):
				continue
			var args := m.get_string(2)
			var re_named := RegEx.new()
			re_named.compile("([A-Za-z_][A-Za-z0-9_]*)\\s*:=")
			for a in re_named.search_all(args):
				var pname := a.get_string(1)
				if not fb_params[fbtype].has(pname):
					fail("%s: %s(%s := ...) -> %s icinde boyle bir giris yok"
							% [fname, iname, pname, fbtype])
					bad += 1
	if bad == 0:
		ok_line("tum FB cagri parametreleri hedef FB'de tanimli")


## FB'nin VAR_INPUT / VAR_IN_OUT / VAR_OUTPUT bloklarindaki degisken adlari
func _fb_io_names(src: String) -> Dictionary:
	var out := {}
	var re_block := RegEx.new()
	re_block.compile("(?s)\\bVAR_(INPUT|IN_OUT|OUTPUT)\\b(.*?)END_VAR")
	for b in re_block.search_all(src):
		var re_n := RegEx.new()
		re_n.compile("(?m)^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*:")
		for m in re_n.search_all(b.get_string(2)):
			out[m.get_string(1)] = true
	return out
