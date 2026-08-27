extends SceneTree

## ST STATIC CHECK
##
## The codesys/*.st files cannot be compiled without CODESYS. This check
## catches most of what the compiler would catch, straight from the source:
##
##   A) Block balance       IF/CASE/FOR/WHILE/VAR_*/TYPE/STRUCT/METHOD
##   B) Constants           is every C_* used declared in GVL_Config.st
##   C) Enum literals       do FLT_/LS_/DS_/DIR_ exist in DUT_Types.st
##   D) Struct fields       are stIn./stOut. fields declared in the DUT
##   E) Method calls        does fbX.Method() exist as a METHOD on the FB
##   F) FB parameters       is the name in fbX(name := ...) an input of the FB
##
## WHAT IT DOES NOT DO: type checking, expression validity, a real build.
## Those can only be verified by compiling in CODESYS.
##
## Run with:
##   godot --headless --path <godot> --script res://tests/st_lint_test.gd

var failures := 0
var st_dir := ""
var files: Dictionary = {}          # file name -> text with comments stripped


func _initialize() -> void:
	print("=== ST STATIC CHECK ===\n")
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

	print("\n=== RESULT: %s ===" % ("ST SOURCE IS CONSISTENT" if failures == 0
			else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func fail(msg: String) -> void:
	failures += 1
	print("  [FAIL ] %s" % msg)


func ok_line(msg: String) -> void:
	print("  [ ok  ] %s" % msg)


## Strips (* ... *) and // ... comments
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
		fail("could not open the codesys folder: %s" % st_dir)
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
		fail("no .st files found")
		return false
	return true


func count_word(src: String, word: String) -> int:
	var re := RegEx.new()
	re.compile("\\b%s\\b" % word)
	return re.search_all(src).size()


# =============================================================================
# A) Block balance
# =============================================================================
func check_block_balance() -> void:
	print("A) Block balance")

	# NOTE: these files are written to be pasted into CODESYS; the POU body and
	# its declaration live in the same file, so no END_ counterpart is expected
	# for FUNCTION_BLOCK/PROGRAM. METHOD does have its END_METHOD.
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
				fail("%s: %s=%d but %s=%d" % [fname, p[0], o, p[1], c])
				bad += 1

		# VAR / VAR_INPUT / VAR_OUTPUT / VAR_IN_OUT / VAR_GLOBAL  <-> END_VAR
		var re_var := RegEx.new()
		re_var.compile("\\bVAR(_INPUT|_OUTPUT|_IN_OUT|_GLOBAL|_TEMP|_STAT)?\\b")
		var nv := re_var.search_all(src).size()
		var ne := count_word(src, "END_VAR")
		if nv != ne:
			fail("%s: VAR blocks=%d but END_VAR=%d" % [fname, nv, ne])
			bad += 1

	if bad == 0:
		ok_line("block balance is fine in %d files" % files.size())


# =============================================================================
# B) Constants
# =============================================================================
func check_constants() -> void:
	print("\nB) Constants (C_*)")

	var cfg: String = files.get("GVL_Config.st", "")
	if cfg == "":
		fail("GVL_Config.st not found")
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
					fail("%s: %s is not declared in GVL_Config.st" % [fname, name])
					bad += 1
	if bad == 0:
		ok_line("%d constant declarations, every use resolved" % declared.size())


# =============================================================================
# C) Enum literals
# =============================================================================
func check_enum_literals() -> void:
	print("\nC) Enum literals")

	var dut: String = files.get("DUT_Types.st", "")
	if dut == "":
		fail("DUT_Types.st not found")
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
					fail("%s: %s is not declared in DUT_Types.st" % [fname, name])
					bad += 1
	if bad == 0:
		ok_line("%d enum literals, every use resolved" % declared.size())


# =============================================================================
# D) Struct fields
# =============================================================================
func check_struct_fields() -> void:
	print("\nD) Struct fields (stIn / stOut)")

	var dut: String = files.get("DUT_Types.st", "")
	if dut == "":
		return

	var fin := _struct_fields(dut, "ST_LiftInputs")
	var fout := _struct_fields(dut, "ST_LiftOutputs")
	if fin.is_empty() or fout.is_empty():
		fail("ST_LiftInputs / ST_LiftOutputs could not be parsed")
		return

	var bad := 0
	bad += _check_fields("stIn", fin)
	bad += _check_fields("stOut", fout)
	if bad == 0:
		ok_line("stIn (%d fields) and stOut (%d fields) uses all resolved"
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
					fail("%s: %s.%s is not in the struct" % [fname, prefix, field])
					bad += 1
	return bad


# =============================================================================
# E) Method calls
# =============================================================================
func check_method_calls() -> void:
	print("\nE) FB method calls")

	var fb_methods := {}      # FB_Xxx -> {method: true}
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
					fail("%s: %s.%s() -> no such METHOD in %s"
							% [fname, iname, meth, fbtype])
					bad += 1
	if bad == 0:
		ok_line("every fbX.Method() call was found on its FB")


## Builds an instance -> type map from "fbSafety : FB_Safety;" declarations
func _instance_types(src: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("\\b(fb[A-Za-z0-9_]*)\\s*:\\s*(FB_[A-Za-z0-9_]+)")
	for m in re.search_all(src):
		out[m.get_string(1)] = m.get_string(2)
	return out


# =============================================================================
# F) FB call parameters
# =============================================================================
func check_fb_parameters() -> void:
	print("\nF) FB call parameters")

	# the input/output variable names of each FB
	var fb_params := {}
	for fname in files:
		if not fname.begins_with("FB_"):
			continue
		var fbn: String = fname.get_basename()
		fb_params[fbn] = _fb_io_names(files[fname])

	var bad := 0
	for fname in files:
		var inst := _instance_types(files[fname])
		# multi-line body call:  fbX( name := ..., name2 := ... );
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
					fail("%s: %s(%s := ...) -> no such input in %s"
							% [fname, iname, pname, fbtype])
					bad += 1
	if bad == 0:
		ok_line("every FB call parameter is declared on its FB")


## The variable names in an FB's VAR_INPUT / VAR_IN_OUT / VAR_OUTPUT blocks
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
