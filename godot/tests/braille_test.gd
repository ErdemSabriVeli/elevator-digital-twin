extends SceneTree

## Tactile signage verification.
##
## Braille is the one part of the panel a sighted reviewer cannot check by
## looking at a screenshot — wrong dots still look like plausible dots. So this
## reads the dots back out of the built 3D scene and decodes them, rather than
## trusting the code that placed them.
##
## It checks:
##   - the encoding table against the braille standard, written out literally
##   - that digits carry a number sign, so "3" cannot be read as the letter "c"
##   - that every car button carries its OWN pattern (the old code drew one
##     fixed pattern, the letter "o", on all six floor buttons)
##   - dot size and spacing against ADA 703.3 / BANA, which is an ergonomic
##     spec: dots outside it cannot be read by touch
##   - that the blocks fit the panel and clear the neighbouring button
##
## Run with:
##   godot --headless --path <godot> --script res://tests/braille_test.gd

## The braille standard, spelled out here so the test does not simply agree
## with Braille.gd about what braille is.
const EXPECTED := {
	"G":     [[1, 2, 4, 5]],
	"1":     [[3, 4, 5, 6], [1]],
	"2":     [[3, 4, 5, 6], [1, 2]],
	"3":     [[3, 4, 5, 6], [1, 4]],
	"4":     [[3, 4, 5, 6], [1, 4, 5]],
	"5":     [[3, 4, 5, 6], [1, 5]],
	"OPEN":  [[1, 3, 5], [1, 2, 3, 4], [1, 5], [1, 3, 4, 5]],
	"CLOSE": [[1, 4], [1, 2, 3], [1, 3, 5], [2, 3, 4], [1, 5]],
	"ALARM": [[1], [1, 2, 3], [1], [1, 2, 3, 5], [1, 3, 4]],
}

## Inner (dark) COP plate half width — see CarRig._build_cop.
const PLATE_HALF_W := 0.1125

var failures := 0
var car: CarRig


func _initialize() -> void:
	print("=== BRAILLE VERIFICATION ===\n")

	test_encoding()
	test_dimensions()

	car = CarRig.new()
	root.add_child(car)
	car.build(func(_k: String) -> void: pass)

	test_car_buttons()
	test_fit()

	print("\n=== RESULT: %s ===" % ("ALL CHECKS PASSED" if failures == 0
			else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [ ok  ] %s %s" % [name, detail])
	else:
		failures += 1
		print("  [FAIL ] %s %s" % [name, detail])


# =============================================================================
func test_encoding() -> void:
	print("1) Encoding")

	var bad := ""
	for label in EXPECTED:
		var got := Braille.cells(label)
		if str(got) != str(EXPECTED[label]):
			bad = "%s -> %s, expected %s" % [label, str(got), str(EXPECTED[label])]
			break
	check("every label matches the braille standard", bad == "", bad)

	# A digit is the letter a-j plus a number sign. Drop the sign and "3"
	# silently becomes "c" — the failure mode this guards.
	check("a digit is not the bare letter",
			str(Braille.cells("3")) != str(Braille.cells("c")),
			"(3 = %s, c = %s)" % [str(Braille.cells("3")), str(Braille.cells("c"))])

	# One number sign introduces a whole run, it is not repeated per digit.
	check("one number sign per run of digits",
			Braille.cells("12").size() == 3,
			"(12 = %s)" % str(Braille.cells("12")))

	# The old code drew the same three dots on every button.
	var seen := {}
	var dupe := ""
	for f in range(LiftCfg.FLOOR_COUNT):
		var name := LiftIo.floor_name(f)
		var k := str(Braille.cells(name))
		if seen.has(k):
			dupe = "%s and %s are identical" % [seen[k], name]
		seen[k] = name
	check("every floor has a distinct pattern", dupe == "", dupe)

	var all_letters := {}
	var clash := ""
	for ch in Braille.LETTER:
		var k: String = str(Braille.LETTER[ch])
		if all_letters.has(k):
			clash = "%s and %s share a pattern" % [all_letters[k], ch]
		all_letters[k] = ch
		for n in Braille.LETTER[ch]:
			if n < 1 or n > 6:
				clash = "%s uses dot %d" % [ch, n]
	check("the 26 letters are distinct and inside the 6-dot cell", clash == "", clash)


func test_dimensions() -> void:
	print("\n2) Dot geometry (ADA 703.3 / BANA)")

	var mm := func(m: float) -> float: return m * 1000.0
	check("dot base diameter 1.5 - 1.6 mm",
			mm.call(Braille.DOT_BASE_M) >= 1.5 and mm.call(Braille.DOT_BASE_M) <= 1.6,
			"(%.2f mm)" % mm.call(Braille.DOT_BASE_M))
	check("dot height 0.6 - 0.9 mm",
			mm.call(Braille.DOT_HEIGHT_M) >= 0.6 and mm.call(Braille.DOT_HEIGHT_M) <= 0.9,
			"(%.2f mm)" % mm.call(Braille.DOT_HEIGHT_M))
	check("dot spacing within a cell 2.3 - 2.5 mm",
			mm.call(Braille.DOT_PITCH_M) >= 2.3 and mm.call(Braille.DOT_PITCH_M) <= 2.5,
			"(%.2f mm)" % mm.call(Braille.DOT_PITCH_M))
	check("spacing between cells 6.1 - 7.6 mm",
			mm.call(Braille.CELL_PITCH_M) >= 6.1 and mm.call(Braille.CELL_PITCH_M) <= 7.6,
			"(%.2f mm)" % mm.call(Braille.CELL_PITCH_M))
	check("cells do not run into each other",
			Braille.CELL_PITCH_M > Braille.DOT_PITCH_M + Braille.DOT_BASE_M,
			"(gap %.2f mm)" % mm.call(Braille.CELL_PITCH_M - Braille.DOT_PITCH_M
					- Braille.DOT_BASE_M))


# =============================================================================
func test_car_buttons() -> void:
	print("\n3) Dots read back out of the built panel")

	var targets: Array = []
	for f in range(LiftCfg.FLOOR_COUNT):
		targets.append([LiftIo.floor_name(f), car.floor_buttons[f]])
	targets.append(["OPEN", car.btn_open])
	targets.append(["CLOSE", car.btn_close])
	targets.append(["ALARM", car.btn_alarm])

	for t in targets:
		var label: String = t[0]
		var btn: Btn3D = t[1]
		var got := decode(btn)
		var want: Array = EXPECTED[label]
		check("button \"%s\" reads back as \"%s\"" % [label, label],
				str(got) == str(want),
				"(%d dots)" % dot_count(btn) if str(got) == str(want)
						else "(got %s, expected %s)" % [str(got), str(want)])


func test_fit() -> void:
	print("\n4) Fit on the panel")

	var targets: Array = []
	for f in range(LiftCfg.FLOOR_COUNT):
		targets.append([LiftIo.floor_name(f), car.floor_buttons[f], CarRig.BTN_R])
	targets.append(["OPEN", car.btn_open, CarRig.BTN_R * 0.92])
	targets.append(["CLOSE", car.btn_close, CarRig.BTN_R * 0.92])
	targets.append(["ALARM", car.btn_alarm, CarRig.BTN_R * 0.92])

	var worst_edge := 1.0
	var worst_gap := 1.0
	var worst_lbl := ""
	var overlap := ""

	for t in targets:
		var label: String = t[0]
		var btn: Btn3D = t[1]
		var radius: float = t[2]
		var lo := INF
		var hi := -INF
		for c in btn.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
				lo = minf(lo, btn.position.x + c.position.x)
				hi = maxf(hi, btn.position.x + c.position.x)
		if lo == INF:
			continue

		var edge := lo - Braille.DOT_BASE_M * 0.5 - (-PLATE_HALF_W)
		if edge < worst_edge:
			worst_edge = edge
			worst_lbl = label

		var gap := (btn.position.x - radius) - (hi + Braille.DOT_BASE_M * 0.5)
		worst_gap = minf(worst_gap, gap)

		# nothing may sit on top of another button's cap
		for u in targets:
			var other: Btn3D = u[1]
			if other == btn:
				continue
			if absf(other.position.y - btn.position.y) > 0.01:
				continue
			var oa: float = other.position.x - u[2]
			var ob: float = other.position.x + u[2]
			if hi > oa and lo < ob:
				overlap = "%s overruns the %s button" % [label, u[0]]

	check("inside the panel plate", worst_edge > 0.0,
			"(tightest %.1f mm, on \"%s\")" % [worst_edge * 1000.0, worst_lbl])
	check("clear of its own button (ADA asks 9.5 mm)",
			worst_gap >= 0.0095, "(tightest %.1f mm)" % (worst_gap * 1000.0))
	check("clear of the neighbouring button", overlap == "", overlap)


# =============================================================================
func dot_count(btn: Btn3D) -> int:
	var n := 0
	for c in btn.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
			n += 1
	return n


## Reads the raised dots back off a button and rebuilds the cells they spell.
## Decoding the geometry (rather than asking the renderer what it drew) is what
## makes this a test: a wrong pattern and a misplaced dot both show up here.
##
## The lattice is anchored on the leftmost and topmost dot present, which
## assumes the first cell has a dot in its left column and some cell has a dot
## in the top row. Every label on this panel does; one that did not would fail
## loudly here rather than pass quietly.
func decode(btn: Btn3D) -> Array:
	var pts: Array[Vector2] = []
	for c in btn.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is SphereMesh:
			pts.append(Vector2(c.position.x, c.position.y))
	if pts.is_empty():
		return []

	var min_x := INF
	var max_y := -INF
	for p in pts:
		min_x = minf(min_x, p.x)
		max_y = maxf(max_y, p.y)

	var cells := {}
	for p in pts:
		var dx := p.x - min_x
		var k := int(round(dx / Braille.CELL_PITCH_M))
		var col := int(round((dx - k * Braille.CELL_PITCH_M) / Braille.DOT_PITCH_M))
		var row := int(round((max_y - p.y) / Braille.DOT_PITCH_M))
		var n := row + 1 + (3 if col == 1 else 0)
		if not cells.has(k):
			cells[k] = []
		cells[k].append(n)

	var out: Array = []
	for k in range(cells.size()):
		var a: Array = cells.get(k, [])
		a.sort()
		out.append(a)
	return out
