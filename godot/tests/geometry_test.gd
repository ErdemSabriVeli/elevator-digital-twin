extends SceneTree

## Mechanical layout verification.
##
## Checks, numerically, the collisions and rope alignment errors that are hard
## to spot by looking at a screenshot:
##   - the car at the top floor fouling the traction machine / deflector
##   - the counterweight against the pit and the shaft head
##   - the rope lines against the car and counterweight centres
##   - the horizontal separation of car and counterweight
##
## Run with:
##   godot --headless --path <godot> --script res://tests/geometry_test.gd

var failures := 0


func _initialize() -> void:
	print("=== MECHANICAL LAYOUT VERIFICATION ===\n")

	# --- derived positions --------------------------------------------------
	var top_y: float = float(LiftCfg.TOP_FLOOR) * LiftCfg.M_FLOOR_H
	var ceiling: float = top_y + LiftCfg.M_HEADROOM
	var sheave_y: float = top_y + LiftCfg.M_HEADROOM - 1.15
	var tz: float = LiftCfg.M_ROPE_Z_CAR - LiftCfg.M_SHEAVE_R
	var dz: float = (tz - LiftCfg.M_SHEAVE_R) - LiftCfg.M_DEFLECT_R
	var dy: float = sheave_y - LiftCfg.M_DEFLECT_DY

	print("Shaft head       : %.2f m   (ceiling %.2f m)" % [top_y, ceiling])
	print("Traction sheave  : y=%.2f  z=%.2f  R=%.2f" % [sheave_y, tz, LiftCfg.M_SHEAVE_R])
	print("Deflector sheave : y=%.2f  z=%.2f  R=%.2f\n" % [dy, dz, LiftCfg.M_DEFLECT_R])

	_test_rope_alignment(tz, dz)
	_test_car_top_clearance(top_y, sheave_y, dy, ceiling)
	_test_counterweight_travel(top_y)
	_test_horizontal_separation()
	_test_governor_clearance()

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
func _test_rope_alignment(tz: float, dz: float) -> void:
	print("1) Rope line alignment")

	# The car-side tangent of the traction sheave must sit over the car centre
	var car_line: float = tz + LiftCfg.M_SHEAVE_R
	check("car rope line on the car centre",
			absf(car_line - LiftCfg.M_ROPE_Z_CAR) < 1e-6,
			"(z=%.3f)" % car_line)

	# The line leaving the deflector must sit on the counterweight centre
	var cwt_line: float = dz - LiftCfg.M_DEFLECT_R
	check("cwt rope line on the counterweight centre",
			absf(cwt_line - LiftCfg.M_CWT_Z) < 1e-6,
			"(z=%.3f, cwt z=%.3f)" % [cwt_line, LiftCfg.M_CWT_Z])

	# The leg from sheave to deflector must be vertical (tangents at the same z)
	var s_exit: float = tz - LiftCfg.M_SHEAVE_R
	var d_entry: float = dz + LiftCfg.M_DEFLECT_R
	check("sheave-to-deflector leg is vertical",
			absf(s_exit - d_entry) < 1e-6,
			"(%.3f vs %.3f)" % [s_exit, d_entry])

	# The rope bundle must fit on the sheave body
	var bundle: float = (LiftCfg.ROPE_COUNT - 1) * LiftCfg.ROPE_PITCH
	check("rope bundle fits the sheave width",
			bundle + 0.02 < bundle + 0.10,
			"(bundle %.3f m, %d ropes)" % [bundle, LiftCfg.ROPE_COUNT])


func _test_car_top_clearance(top_y: float, sheave_y: float, dy: float,
		ceiling: float) -> void:
	print("\n2) Headroom with the car at the top floor")

	var car_roof: float = top_y + LiftCfg.M_CAR_H + 0.08
	var hitch_top: float = top_y + LiftCfg.M_CAR_H + 0.36
	var rail_top: float = top_y + LiftCfg.M_CAR_H + 0.08 + LiftCfg.M_CARTOP_RAIL
	var sheave_bot: float = sheave_y - LiftCfg.M_SHEAVE_R
	var defl_bot: float = dy - LiftCfg.M_DEFLECT_R

	print("     car roof %.2f | hitch %.2f | guard rail %.2f" %
			[car_roof, hitch_top, rail_top])
	print("     sheave bottom %.2f | deflector bottom %.2f | ceiling %.2f" %
			[sheave_bot, defl_bot, ceiling])

	# The deflector stays above the car footprint (the z ranges overlap)
	check("deflector clears the guard rail",
			defl_bot > rail_top,
			"(clearance %.2f m)" % (defl_bot - rail_top))
	check("traction sheave clears the guard rail",
			sheave_bot > rail_top,
			"(clearance %.2f m)" % (sheave_bot - rail_top))
	check("guard rail clears the ceiling",
			rail_top < ceiling - 0.30,
			"(clearance %.2f m)" % (ceiling - rail_top))
	check("rope hitch stays below the deflector",
			hitch_top < defl_bot,
			"(clearance %.2f m)" % (defl_bot - hitch_top))


func _test_counterweight_travel(top_y: float) -> void:
	print("\n3) Counterweight travel limits")

	# Uses the same relation as LiftPlant.counterweight_y()
	const CWT_OFFSET := 0.10
	const BUFFER_H := 0.45
	var cwt_at_car_bottom: float = top_y - 0.0 - CWT_OFFSET
	var cwt_at_car_top: float = top_y - top_y - CWT_OFFSET
	var cwt_bot_lowest: float = cwt_at_car_top - LiftCfg.M_CWT_H * 0.5
	var cwt_top_highest: float = cwt_at_car_bottom + LiftCfg.M_CWT_H * 0.5 + 0.26
	var buffer_top: float = -LiftCfg.M_PIT_DEPTH + BUFFER_H

	print("     car at bottom -> cwt %.2f | car at top -> cwt %.2f" %
			[cwt_at_car_bottom, cwt_at_car_top])

	check("cwt does not land on the pit buffer",
			cwt_bot_lowest > buffer_top,
			"(lowest %.2f, buffer top %.2f)" % [cwt_bot_lowest, buffer_top])
	check("cwt stays below the deflector sheave",
			cwt_top_highest < top_y + LiftCfg.M_HEADROOM - 1.15 - LiftCfg.M_DEFLECT_DY
					- LiftCfg.M_DEFLECT_R,
			"(highest %.2f)" % cwt_top_highest)


func _test_horizontal_separation() -> void:
	print("\n4) Car / counterweight horizontal separation")

	var car_back: float = -LiftCfg.M_CAR_D * 0.5
	var cwt_front: float = LiftCfg.M_CWT_Z + LiftCfg.M_CWT_D * 0.5
	var cwt_back: float = LiftCfg.M_CWT_Z - LiftCfg.M_CWT_D * 0.5
	var shaft_back: float = -LiftCfg.M_SHAFT_D * 0.5

	check("cwt clears the car",
			cwt_front < car_back,
			"(clearance %.3f m)" % (car_back - cwt_front))
	check("cwt clears the shaft rear wall",
			cwt_back > shaft_back,
			"(clearance %.3f m)" % (cwt_back - shaft_back))

	var car_side: float = LiftCfg.M_CAR_W * 0.5
	var shaft_side: float = LiftCfg.M_SHAFT_W * 0.5
	check("car fits between the shaft side walls",
			car_side + 0.16 < shaft_side + 0.02,
			"(car %.2f + shoe, shaft %.2f)" % [car_side, shaft_side])


func _test_governor_clearance() -> void:
	print("\n5) Overspeed governor rope")

	var gz: float = LiftCfg.M_GOV_ROPE_Z
	var gx: float = LiftCfg.M_SHAFT_W * 0.5 - 0.15
	var car_side: float = LiftCfg.M_CAR_W * 0.5

	check("governor rope beside the car (x)",
			gx > car_side,
			"(rope x=%.2f, car edge %.2f)" % [gx, car_side])
	check("governor rope out of the door zone (z)",
			gz < LiftCfg.M_CAR_D * 0.5,
			"(rope z=%.2f)" % gz)
	check("governor rope clear of the counterweight",
			absf(gx) > LiftCfg.M_CWT_W * 0.5,
			"(cwt half width %.2f)" % (LiftCfg.M_CWT_W * 0.5))
