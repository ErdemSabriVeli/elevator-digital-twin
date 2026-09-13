extends SceneTree

## Scenario test that runs without a graphical interface.
## SoftPlc (the twin of the ST code) and LiftPlant (the physics model) are
## run together.
##
## Run with:
##   godot --headless --path <godot folder> --script res://tests/sim_test.gd

const DT := 1.0 / 60.0

var plant: LiftPlant
var plc: SoftPlc
var regs_out := PackedInt32Array()
var regs_in := PackedInt32Array()
var hb := 0
var t := 0.0
var failures := 0


func _initialize() -> void:
	print("=== ELEVATOR DIGITAL TWIN - SCENARIO TESTS ===\n")

	test_car_call()
	test_collective()
	test_estop()
	test_overload()
	test_fire()
	test_light_curtain()
	test_travel_timeout()
	test_brake_feedback()
	test_overspeed()
	test_gong_and_alarm()
	test_ride_quality()
	test_load_compensation()
	test_safety_gear()
	test_mains_failure()
	test_relevelling()
	test_levelling_accuracy()
	test_brake_only_at_rest()
	test_full_load_bypass()
	test_door_zone_interlock()
	test_encoder_correction()
	test_terminal_slowdown()
	test_special_services()

	print("\n=== RESULT: %s ===" % ("ALL TESTS PASSED" if failures == 0
			else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


# =============================================================================
func reset(start_floor := 0) -> void:
	plant = LiftPlant.new()
	plant.pos_mm = float(start_floor * LiftCfg.FLOOR_HEIGHT_MM)
	plc = SoftPlc.new()
	regs_out.resize(LiftIo.REG_COUNT)
	regs_in.resize(LiftIo.REG_COUNT)
	for i in LiftIo.REG_COUNT:
		regs_out[i] = 0
	hb = 0
	t = 0.0
	# a few scans so the PLC completes its INIT -> IDLE transition
	step(0.5)


func step(seconds: float) -> void:
	var n := int(seconds / DT)
	for i in range(n):
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_in = plant.build_registers(hb)
		regs_out = plc.scan(regs_in, DT)
		t += DT


## Simulate until the condition holds (at most `timeout` seconds).
func step_until(cond: Callable, timeout := 40.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_in = plant.build_registers(hb)
		regs_out = plc.scan(regs_in, DT)
		elapsed += DT
		t += DT
		if cond.call():
			return true
	return false


func state() -> int:
	return regs_out[LiftIo.OUT_STATE]

func cur_floor() -> int:
	return regs_out[LiftIo.OUT_CUR_FLOOR]

func status(bit: int) -> bool:
	return LiftIo.get_bit(regs_out[LiftIo.OUT_STATUS], bit)

func fault() -> int:
	return regs_out[LiftIo.OUT_FAULT]


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [ ok  ] %s %s" % [name, detail])
	else:
		failures += 1
		print("  [FAIL ] %s %s" % [name, detail])


func press_for(key: String, seconds := 0.3) -> void:
	plant.press(key)
	step(seconds)


# --- multi-line conditions (a lambda is limited to one line) ----------------
func _cond_at_fire_floor() -> bool:
	return cur_floor() == LiftCfg.FIRE_FLOOR and plant.door_pos > 0.95


func _cond_door_closing() -> bool:
	return plant.door_pos < 0.8 \
			and LiftIo.get_bit(regs_out[LiftIo.OUT_DOOR_CMD], LiftIo.DOOR_CLOSE_CMD)


# =============================================================================
func test_car_call() -> void:
	print("1) Car call: ground -> floor 3")
	reset(0)

	check("IDLE at the start", state() == LiftIo.State.IDLE,
			"(state=%s)" % LiftIo.STATE_TEXT[state()])

	press_for("car_3")
	var arrived := step_until(func(): return cur_floor() == 3 and status(LiftIo.ST_DOOR_OPEN))
	check("reached floor 3 and opened the door", arrived,
			"(floor=%d, pos=%.0f mm, time=%.1f s)" % [cur_floor(), plant.pos_mm, t])
	check("levelling tolerance", absf(plant.pos_mm - 3 * LiftCfg.FLOOR_HEIGHT_MM)
			<= LiftCfg.LEVEL_TOL_MM,
			"(error=%.1f mm)" % (plant.pos_mm - 3 * LiftCfg.FLOOR_HEIGHT_MM))

	var closed := step_until(func(): return status(LiftIo.ST_DOOR_CLOSED), 15.0)
	check("door closed after the dwell time", closed)
	step(0.2)   # let the FSM reach IDLE on the next scan (same behaviour as the ST)
	check("returned to an idle state", state() == LiftIo.State.IDLE or state() == LiftIo.State.PARK,
			"(state=%s)" % LiftIo.STATE_TEXT[state()])


func test_collective() -> void:
	print("\n2) Collective control: a floor 2 call while coming down from floor 5")
	reset(0)

	press_for("car_5")
	var up := step_until(func(): return cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN))
	check("went up to floor 5", up, "(time=%.1f s)" % t)

	# a down call at floor 2, on the way while travelling down
	press_for("hall_down_2")
	var stopped := step_until(func(): return cur_floor() == 2 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("stopped at floor 2 on the way down", stopped, "(floor=%d)" % cur_floor())
	check("floor 2 down lamp cleared",
			not LiftIo.get_bit(regs_out[LiftIo.OUT_LAMP_DOWN], 2))


func test_estop() -> void:
	print("\n3) Emergency stop: safety while moving")
	reset(0)

	press_for("car_5")
	var moving := step_until(func(): return status(LiftIo.ST_MOVING) and plant.pos_mm > 1500.0)
	check("the car started moving", moving, "(pos=%.0f mm)" % plant.pos_mm)

	plant.sw_estop = true
	step(1.5)
	check("motion stopped on emergency stop", absf(plant.speed_mms) < 1.0,
			"(speed=%.1f mm/s)" % plant.speed_mms)
	check("fault code is ESTOP", fault() == LiftIo.Fault.ESTOP,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])

	plant.sw_estop = false
	press_for("reset")
	step(1.0)
	check("fault cleared after reset", fault() == LiftIo.Fault.NONE)
	# All calls are cleared on a fault (EN 81 practice): the car must not set
	# off by itself, the passenger has to register a new call.
	check("the fault cleared the calls", regs_out[LiftIo.OUT_LAMP_CAR] == 0,
			"(lamp=%d)" % regs_out[LiftIo.OUT_LAMP_CAR])

	press_for("car_5")
	var resumed := step_until(func(): return cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("a new call produced a trip", resumed, "(floor=%d)" % cur_floor())


func test_overload() -> void:
	print("\n4) Overload: the door must not close and the car must not start")
	reset(0)

	# go to floor 2 and open the door first, then load passengers (overload)
	press_for("car_2")
	var at2 := step_until(func(): return cur_floor() == 2 and plant.door_pos > 0.99)
	check("reached floor 2", at2)

	plant.load_kg = 750          # > 693 kg -> overload
	step(8.0)
	check("overload lamp lit", status(LiftIo.ST_OVERLOAD))
	check("the door stayed open", plant.door_pos > 0.9, "(door=%.0f%%)" % (plant.door_pos * 100))

	# with the overload still present a new call must not start the car
	press_for("car_4")
	step(6.0)
	check("no start while overloaded",
			absf(plant.pos_mm - 2 * LiftCfg.FLOOR_HEIGHT_MM) < 50.0,
			"(pos=%.0f mm)" % plant.pos_mm)

	plant.load_kg = 80
	var moved := step_until(func(): return cur_floor() == 4 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("the trip completed once the load dropped", moved, "(floor=%d)" % cur_floor())


func test_fire() -> void:
	print("\n5) Fire mode: recall to the evacuation floor")
	reset(4)

	plant.sw_fire = true
	var evac := step_until(_cond_at_fire_floor, 45.0)
	check("recalled to the fire floor and opened the door", evac,
			"(floor=%d, door=%.0f%%)" % [cur_floor(), plant.door_pos * 100])
	check("fire mode flag", status(LiftIo.ST_FIRE))

	# Regression: it must not enter an open/close loop (the period was ~9 s)
	step(25.0)
	check("the door stayed open for 25 s", plant.door_pos > 0.95,
			"(door=%.0f%%)" % (plant.door_pos * 100))


func test_light_curtain() -> void:
	print("\n6) Light curtain: a closing door must reopen")
	reset(0)

	press_for("car_2")
	var opened := step_until(func(): return cur_floor() == 2 and plant.door_pos > 0.99)
	check("the door opened at floor 2", opened)

	# wait for it to start closing
	var closing := step_until(_cond_door_closing, 15.0)
	check("the door started to close", closing, "(door=%.0f%%)" % (plant.door_pos * 100))

	plant.sw_obstruction = true
	var reopened := step_until(func(): return plant.door_pos > 0.99, 10.0)
	plant.sw_obstruction = false
	check("it reopened when the curtain was broken", reopened,
			"(door=%.0f%%)" % (plant.door_pos * 100))

	var closed2 := step_until(func(): return plant.door_pos < 0.01, 20.0)
	check("it closed again once the obstruction cleared", closed2)


# =============================================================================
func test_travel_timeout() -> void:
	print("\n7) Travel timeout and recovery from the fault")
	reset(0)

	press_for("car_5")
	var moving := step_until(func(): return status(LiftIo.ST_MOVING) and plant.pos_mm > 800.0)
	check("the car started moving", moving, "(pos=%.0f mm)" % plant.pos_mm)

	# the car is jammed: the drive runs but the position does not advance
	plant.sw_car_jammed = true
	var timed_out := step_until(func(): return fault() == LiftIo.Fault.TRAVEL_TIMEOUT, 40.0)
	check("the travel timeout fault was raised", timed_out,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])

	# Clear the jam and reset. If the timer OUTPUT flag is not cleared as well
	# the fault comes straight back -> the check below catches that.
	plant.sw_car_jammed = false
	press_for("reset")
	step(0.5)
	check("fault cleared after reset", fault() == LiftIo.Fault.NONE,
			"(code=%d)" % fault())
	step(3.0)
	check("the fault does not return (no latched flag)",
			fault() == LiftIo.Fault.NONE, "(code=%d)" % fault())

	press_for("car_4")
	var ok := step_until(func(): return cur_floor() == 4 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("a normal trip is possible after the fault", ok, "(floor=%d)" % cur_floor())


func test_brake_feedback() -> void:
	print("\n8) Brake feedback supervision")
	reset(0)

	plant.sw_brake_stuck = true      # the brake is mechanically stuck: no response to the release command
	press_for("car_3")
	var brake_flt := step_until(func(): return fault() == LiftIo.Fault.BRAKE, 25.0)
	check("brake fault detected", brake_flt,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])
	check("the car stayed where it was", absf(plant.pos_mm) < 20.0,
			"(pos=%.0f mm)" % plant.pos_mm)

	plant.sw_brake_stuck = false
	press_for("reset")
	step(2.0)
	check("the fault cleared once the brake recovered", fault() == LiftIo.Fault.NONE,
			"(code=%d)" % fault())


func test_overspeed() -> void:
	print("\n9) Overspeed - the governor trips")
	reset(0)

	press_for("car_5")
	var fast := step_until(func(): return plant.speed_mms > 900.0)
	check("the car got up to speed", fast, "(speed=%.0f mm/s)" % plant.speed_mms)

	plant.sw_overspeed = true        # drive runaway
	var trip := step_until(func(): return fault() == LiftIo.Fault.OVERSPEED, 12.0)
	check("the governor caught the overspeed", trip,
			"(code=%d, peak speed observed)" % fault())
	step(2.0)
	check("the car was stopped on overspeed", absf(plant.speed_mms) < 5.0,
			"(speed=%.1f mm/s)" % plant.speed_mms)


func test_gong_and_alarm() -> void:
	print("\n10) Gong duration and the alarm bell")
	reset(0)

	press_for("car_2")
	var arrived := step_until(func(): return status(LiftIo.ST_GONG))
	check("the gong rang on arrival", arrived)

	# how long did the gong last?
	var t0 := t
	var still := step_until(func(): return not status(LiftIo.ST_GONG), 5.0)
	var dur := t - t0
	check("gong duration is close to the configured value", still and dur > LiftCfg.T_GONG * 0.5,
			"(%.2f s, target %.2f s)" % [dur, LiftCfg.T_GONG])

	# alarm bell
	check("the alarm is off to begin with", not status(LiftIo.ST_ALARM))
	plant.press("alarm")
	step(0.3)
	check("the alarm button started the bell", status(LiftIo.ST_ALARM))
	step(LiftCfg.T_ALARM + 0.5)
	check("the bell stopped when the time ran out", not status(LiftIo.ST_ALARM))


# =============================================================================
func test_ride_quality() -> void:
	print("\n11) Ride quality: jerk-limited S-curve profile")
	reset(0)

	press_for("car_5")

	# measure the rate of change of acceleration (jerk) over the trip
	var prev_a := plant.accel_mms2
	var max_jerk := 0.0
	var max_acc := 0.0
	var elapsed := 0.0
	while elapsed < 20.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		t += DT
		# Only measure while the drive is producing torque. The brake-holding /
		# emergency-stop path is deliberately harsh and not subject to the
		# comfort limit.
		if plant.powered:
			max_jerk = maxf(max_jerk, absf(plant.accel_mms2 - prev_a) / DT)
			max_acc = maxf(max_acc, absf(plant.accel_mms2))
		prev_a = plant.accel_mms2
		if cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN):
			break

	check("reached floor 5", cur_floor() == 5, "(floor=%d)" % cur_floor())
	# the limit is relaxed at creep speed, so leave some headroom
	check("jerk limit not exceeded", max_jerk <= LiftCfg.JERK_MMS3 * 8.5,
			"(measured %.0f mm/s3, target %.0f, tolerated %.0f)"
					% [max_jerk, LiftCfg.JERK_MMS3, LiftCfg.JERK_MMS3 * 8.5])
	check("acceleration limit not exceeded", max_acc <= LiftCfg.DECEL_MMS2 * 1.05,
			"(measured %.0f mm/s2, limit %.0f)" % [max_acc, LiftCfg.DECEL_MMS2])
	check("levelling held",
			absf(plant.pos_mm - 5 * LiftCfg.FLOOR_HEIGHT_MM) <= LiftCfg.LEVEL_TOL_MM,
			"(error %.1f mm)" % (plant.pos_mm - 5 * LiftCfg.FLOOR_HEIGHT_MM))


# =============================================================================
## Measures how far the car moves the WRONG way in the first moments of a trip.
## Returns the worst excursion in mm, signed the same way as the travel.
func rollback_mm(start_floor: int, target: String, load: int,
		compensate: bool, up: bool) -> float:
	reset(start_floor)
	plant.load_kg = load
	plant.sw_no_load_comp = not compensate
	var p0 := plant.pos_mm
	press_for(target)
	var worst := 0.0
	var elapsed := 0.0
	while elapsed < 3.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		t += DT
		var d := plant.pos_mm - p0
		worst = minf(worst, d) if up else maxf(worst, d)
		# stop once the car is clearly under way in the intended direction
		if absf(plant.speed_mms) > 200.0:
			break
	return absf(worst)


func test_load_compensation() -> void:
	print("\n12) Load compensation: pre-torque against rollback")
	reset(0)

	# The counterweight cancels the empty car plus half the rated load, so the
	# residual reverses sign as the car fills.
	plant.load_kg = LiftCfg.LOAD_FULL_KG
	step(0.1)
	check("full car: pre-torque holds it UP",
			LiftIo.to_signed(regs_out[LiftIo.OUT_PRETORQUE]) > 0,
			"(%d permille)" % LiftIo.to_signed(regs_out[LiftIo.OUT_PRETORQUE]))
	plant.load_kg = 0
	step(0.1)
	check("empty car: pre-torque holds it DOWN",
			LiftIo.to_signed(regs_out[LiftIo.OUT_PRETORQUE]) < 0,
			"(%d permille)" % LiftIo.to_signed(regs_out[LiftIo.OUT_PRETORQUE]))
	plant.load_kg = LiftCfg.CWT_KG - LiftCfg.CAR_EMPTY_KG      # exactly balanced
	step(0.1)
	check("balanced car: no pre-torque",
			LiftIo.to_signed(regs_out[LiftIo.OUT_PRETORQUE]) == 0,
			"(%d kg, %d permille)"
					% [plant.load_kg, LiftIo.to_signed(regs_out[LiftIo.OUT_PRETORQUE])])

	# A full car going up is the worst case: the load pulls it down and the
	# brake is what has been holding it.
	var with_comp := rollback_mm(1, "car_4", LiftCfg.LOAD_FULL_KG, true, true)
	var without := rollback_mm(1, "car_4", LiftCfg.LOAD_FULL_KG, false, true)
	check("compensated start does not roll back", with_comp < 1.0,
			"(%.2f mm)" % with_comp)
	check("uncompensated full car sinks on brake release", without > 5.0,
			"(%.1f mm)" % without)

	# An empty car going down is the mirror image: it is lighter than the
	# counterweight, so with no torque it gets pulled up.
	var up_kick := rollback_mm(4, "car_1", 0, false, false)
	check("uncompensated empty car lifts on brake release", up_kick > 5.0,
			"(%.1f mm)" % up_kick)

	# The whole point: the imbalance must not survive into the ride.
	reset(0)
	plant.load_kg = LiftCfg.LOAD_FULL_KG
	press_for("car_5")
	var arrived := step_until(func(): return cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	var level_err := plant.pos_mm - 5 * LiftCfg.FLOOR_HEIGHT_MM
	check("a full car still levels correctly",
			arrived and absf(level_err) <= LiftCfg.LEVEL_TOL_MM,
			"(error %.1f mm)" % level_err)


func test_safety_gear() -> void:
	print("\n13) Safety gear: the governor grips when the controller cannot stop it")
	reset(5)

	press_for("car_0")
	var moving := step_until(func(): return plant.speed_mms < -400.0, 10.0)
	check("the car is on its way down", moving, "(speed=%.0f mm/s)" % plant.speed_mms)

	# A runaway fast enough that the car passes the mechanical trip speed while
	# the controller is still confirming the electrical one.
	plant.sw_severe_runaway = true
	var gripped := step_until(func(): return plant.safety_gear_set, 12.0)
	check("the safety gear engaged", gripped)
	check("it engaged past the governor trip speed",
			gripped and LiftCfg.V_GEAR_TRIP_MMS > LiftCfg.V_OVERSPEED_MMS,
			"(gear %d mm/s, electrical %d mm/s)"
					% [LiftCfg.V_GEAR_TRIP_MMS, LiftCfg.V_OVERSPEED_MMS])

	var stopped := step_until(func(): return absf(plant.speed_mms) < 1.0, 3.0)
	check("the wedges brought the car to a stop", stopped,
			"(speed=%.1f mm/s)" % plant.speed_mms)
	step(0.3)
	check("reported as a safety gear fault", fault() == LiftIo.Fault.SAFETY_GEAR,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])

	# The wedges hold the car up; it cannot sink further even with the drive off.
	var p_held := plant.pos_mm
	step(2.0)
	check("the car is held on the rails", plant.pos_mm >= p_held - 1.0,
			"(drift %.2f mm)" % (plant.pos_mm - p_held))

	# A set gear is not something the panel can clear.
	plant.sw_severe_runaway = false
	press_for("reset")
	step(1.0)
	check("RESET does not clear a set safety gear",
			fault() == LiftIo.Fault.SAFETY_GEAR, "(code=%d)" % fault())
	press_for("car_2")
	step(3.0)
	check("and the lift will not run", absf(plant.pos_mm - p_held) < 5.0,
			"(moved %.1f mm)" % (plant.pos_mm - p_held))

	# Freeing the wedges is a hands-on job at the car; after that it resets.
	plant.release_safety_gear()
	press_for("reset")
	step(1.0)
	check("clears once the wedges are freed by hand",
			fault() == LiftIo.Fault.NONE, "(code=%d)" % fault())
	press_for("car_2")
	var ran := step_until(func(): return cur_floor() == 2 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("and the lift runs again", ran, "(floor=%d)" % cur_floor())


## Traps the car between floors, then cuts the mains.
func strand_and_cut(start_floor: int, target: String, load: int) -> void:
	reset(start_floor)
	plant.load_kg = load
	press_for(target)
	step_until(func(): return absf(plant.speed_mms) > 800.0, 10.0)
	plant.sw_mains_fail = true


func test_mains_failure() -> void:
	print("\n14) Mains failure: the rescue drive takes the car to a floor")

	# A heavy car sinks, so the rescue drive should let gravity do the work and
	# go DOWN, even though the passenger asked to go up.
	strand_and_cut(1, "car_5", LiftCfg.LOAD_FULL_KG)
	var p_cut := plant.pos_mm
	step(1.0)
	check("the drive drops out with the mains", absf(plant.speed_mms) < 1.0,
			"(speed=%.1f mm/s)" % plant.speed_mms)
	check("state is RESCUE", state() == LiftIo.State.RESCUE,
			"(state=%s)" % LiftIo.STATE_TEXT[state()])
	check("rescue status bit set", status(LiftIo.ST_RESCUE))

	var landed := step_until(func(): return plant.door_pos > 0.95, 60.0)
	check("reached a floor and opened the doors", landed,
			"(floor=%d, door=%.0f%%)" % [cur_floor(), plant.door_pos * 100])
	check("it went DOWN, the way the load was already pulling",
			plant.pos_mm < p_cut, "(%.0f mm -> %.0f mm)" % [p_cut, plant.pos_mm])
	check("it stopped at the FIRST floor it reached, not the call",
			cur_floor() == 1, "(floor=%d, call was 5)" % cur_floor())

	# The battery only runs the car at creep speed.
	var peak := 0.0
	var p2 := plant.pos_mm
	step(3.0)
	check("it stays put with the doors open", absf(plant.pos_mm - p2) < 2.0
			and plant.door_pos > 0.95, "(door=%.0f%%)" % (plant.door_pos * 100))

	# Mains back -> normal service.
	plant.sw_mains_fail = false
	step(1.0)
	check("normal service resumes when the mains return",
			state() != LiftIo.State.RESCUE and not status(LiftIo.ST_RESCUE),
			"(state=%s)" % LiftIo.STATE_TEXT[state()])
	press_for("car_3")
	var ran := step_until(func(): return cur_floor() == 3 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("and the lift runs again", ran, "(floor=%d)" % cur_floor())

	# An empty car is lighter than the counterweight, so it floats UP instead.
	strand_and_cut(1, "car_5", 0)
	var p_cut2 := plant.pos_mm
	var landed2 := step_until(func(): return plant.door_pos > 0.95, 60.0)
	check("an empty car is rescued UPWARDS", landed2 and plant.pos_mm > p_cut2,
			"(%.0f mm -> %.0f mm, floor=%d)" % [p_cut2, plant.pos_mm, cur_floor()])

	# Rescue speed: measured over the run above.
	strand_and_cut(1, "car_5", LiftCfg.LOAD_FULL_KG)
	var elapsed := 0.0
	while elapsed < 40.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		# Only while the rescue inverter is actually driving. Before the
		# changeover the car is still coasting down from its mains-powered run.
		if plant.powered:
			peak = maxf(peak, absf(plant.speed_mms))
		if plant.door_pos > 0.95:
			break
	check("it creeps on the battery", peak <= LiftCfg.V_ARD_MMS * 1.15,
			"(peak %.0f mm/s, rescue speed %d)" % [peak, LiftCfg.V_ARD_MMS])


func test_relevelling() -> void:
	print("\n15) Re-levelling: the encoder cannot see the car sag")
	reset(0)

	# Rope stretch is real but small on a six-floor rise. Say so with a number
	# rather than pretending otherwise.
	plant.load_kg = 0
	var s_empty := plant.rope_stretch_mm()
	plant.load_kg = LiftCfg.LOAD_FULL_KG
	var s_full := plant.rope_stretch_mm()
	check("a full car hangs lower than an empty one", s_full > s_empty,
			"(%.2f mm vs %.2f mm at the bottom of the shaft)" % [s_full, s_empty])
	check("the encoder does not see it",
			absf(plant.car_pos_mm() - plant.pos_mm) > 0.5,
			"(encoder %.1f mm, car %.1f mm)" % [plant.pos_mm, plant.car_pos_mm()])

	# Now a fault that really does move the car at the floor: a brake that no
	# longer quite holds. Re-levelling is what masks it until it gets bad.
	reset(2)
	plant.load_kg = LiftCfg.LOAD_FULL_KG
	press_for("car_3")
	var arrived := step_until(func(): return cur_floor() == 3 and plant.door_pos > 0.95, 30.0)
	check("at floor 3 with the doors open", arrived)

	plant.sw_brake_creep = true
	var sagged := step_until(func(): return state() == LiftIo.State.RELEVEL, 15.0)
	check("the car sinking triggers a re-level", sagged,
			"(offset %.1f mm, threshold %d)" % [plant.floor_offset_mm(), LiftCfg.RELEVEL_MM])
	check("re-level status bit set", status(LiftIo.ST_RELEVEL))
	check("and it does it with the doors OPEN", plant.door_pos > 0.9,
			"(door=%.0f%%)" % (plant.door_pos * 100))
	check("moving with the doors open is not a lock fault here",
			fault() == LiftIo.Fault.NONE,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])

	var corrected := step_until(func(): return state() != LiftIo.State.RELEVEL, 15.0)
	check("it creeps back to level", corrected
			and absf(plant.floor_offset_mm()) <= LiftCfg.RELEVEL_MM,
			"(offset %.1f mm)" % plant.floor_offset_mm())

	# Outside the door zone, moving with the lock open is still the dangerous
	# fault it always was.
	plant.sw_brake_creep = false
	reset(0)
	press_for("car_4")
	var midflight := step_until(func(): return plant.pos_mm > 5000.0, 20.0)
	plant.door_pos = 0.5                        # lock contact drops mid-travel
	step(0.3)
	check("a lock lost between floors is still a fault", midflight
			and fault() == LiftIo.Fault.LOCK_LOST,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])


func test_levelling_accuracy() -> void:
	print("\n16) Levelling accuracy over every run length")

	# Single-floor runs are the tight case and were the one length no scenario
	# exercised: the car cannot reach rated speed AND stop from it in 3.2 m, so
	# a profile that lets it try arrives long. Floor 0 is the other awkward one
	# — the position register cannot go below it, so the error can never turn
	# negative there and a controller that picks its direction from the sign of
	# a zero error drives itself into the pit.
	var runs := [[2, 3], [3, 2], [0, 1], [1, 0], [4, 5], [5, 4],
			[0, 5], [5, 0], [1, 4], [4, 1], [0, 2], [2, 0]]
	var worst := 0.0
	var worst_run := ""
	var bad := ""

	for r in runs:
		var from: int = r[0]
		var to: int = r[1]
		reset(from)
		press_for("car_%d" % to)
		var ok := step_until(func(): return cur_floor() == to and status(LiftIo.ST_DOOR_OPEN), 45.0)
		var err: float = plant.pos_mm - float(to * LiftCfg.FLOOR_HEIGHT_MM)
		if not ok:
			bad = "%d->%d never arrived (floor=%d, pos=%.0f)" % [from, to, cur_floor(), plant.pos_mm]
			break
		if fault() != LiftIo.Fault.NONE:
			bad = "%d->%d faulted: %s" % [from, to, LiftIo.FAULT_TEXT[fault()]]
			break
		if absf(err) > absf(worst):
			worst = err
			worst_run = "%d->%d" % [from, to]

	check("every run arrives without a fault", bad == "", bad)
	check("and lands inside the levelling tolerance",
			bad == "" and absf(worst) <= LiftCfg.LEVEL_TOL_MM,
			"(worst %+.1f mm on %s, tolerance %d)"
					% [worst, worst_run, LiftCfg.LEVEL_TOL_MM])

	# The car must not sail through the floor and crawl back either.
	reset(2)
	press_for("car_3")
	var peak_past := 0.0
	var elapsed := 0.0
	while elapsed < 30.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		peak_past = maxf(peak_past, plant.pos_mm - 3.0 * LiftCfg.FLOOR_HEIGHT_MM)
		if status(LiftIo.ST_DOOR_OPEN):
			break
	check("a one-floor run does not overshoot the floor", peak_past < 20.0,
			"(went %.1f mm past)" % peak_past)


## Highest speed at which the controller asked for the brake during a normal
## run. The brake is a HOLDING brake: the drive is supposed to bring the car to
## a stand and the shoes only then go on. Setting it at speed makes the brake do
## the stopping, which is both a harsh stop and wear it is not rated for.
func brake_speed_on_run(from: int, to: int) -> float:
	reset(from)
	press_for("car_%d" % to)
	var was_released := false
	var worst := 0.0
	var elapsed := 0.0
	while elapsed < 45.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		var released := LiftIo.get_bit(regs_out[LiftIo.OUT_DRIVE_CMD], LiftIo.DRV_BRAKE)
		if was_released and not released:
			worst = maxf(worst, absf(plant.speed_mms))
		was_released = released
		if status(LiftIo.ST_DOOR_OPEN):
			break
	return worst


func test_brake_only_at_rest() -> void:
	print("\n17) The brake is a holding brake, not a service brake")

	var worst := 0.0
	var worst_run := ""
	for r in [[2, 3], [0, 5], [5, 0], [1, 0]]:
		var v := brake_speed_on_run(r[0], r[1])
		if v > worst:
			worst = v
			worst_run = "%d->%d" % [r[0], r[1]]
	check("it never goes on while the car is still running",
			worst <= float(LiftCfg.V_ZERO_MMS),
			"(worst %.1f mm/s on %s, zero-speed threshold %d)"
					% [worst, worst_run, LiftCfg.V_ZERO_MMS])

	# An emergency stop is the exception, and has to be.
	reset(0)
	press_for("car_5")
	step_until(func(): return plant.speed_mms > 800.0, 15.0)
	plant.sw_estop = true
	step(0.2)
	check("an emergency stop still drops it immediately",
			not LiftIo.get_bit(regs_out[LiftIo.OUT_DRIVE_CMD], LiftIo.DRV_BRAKE),
			"(speed was %.0f mm/s)" % plant.speed_mms)


func test_full_load_bypass() -> void:
	print("\n18) Full-load bypass: a full car does not stop for landing calls")
	reset(0)

	# Someone is waiting at floor 2, and the car going up past them is full.
	plant.load_kg = LiftCfg.LOAD_FULL_KG
	press_for("hall_up_2")
	press_for("car_5")
	var arrived := step_until(func(): return cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("the full car ran straight through to floor 5", arrived,
			"(floor=%d)" % cur_floor())
	check("it did not stop at floor 2 on the way", plant.trip_count <= 1,
			"(%d stops)" % plant.trip_count)
	check("but the landing call is still registered and lit",
			LiftIo.get_bit(regs_out[LiftIo.OUT_LAMP_UP], 2),
			"(lamp=%d)" % regs_out[LiftIo.OUT_LAMP_UP])

	# Once people get out it is that call's turn.
	plant.load_kg = 80
	var served := step_until(func(): return cur_floor() == 2 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("and it is served once the car empties", served, "(floor=%d)" % cur_floor())
	check("the lamp cleared", not LiftIo.get_bit(regs_out[LiftIo.OUT_LAMP_UP], 2))

	# A car call is never bypassed - the passenger is already inside.
	reset(0)
	plant.load_kg = LiftCfg.LOAD_FULL_KG
	press_for("car_2")
	var car_call := step_until(func(): return cur_floor() == 2 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("a car call is answered however full it is", car_call,
			"(floor=%d, %d kg)" % [cur_floor(), plant.load_kg])


func test_door_zone_interlock() -> void:
	print("\n19) Unlocking zone: the doors cannot open between floors")
	reset(0)

	# Strand the car mid-shaft with an emergency stop, then let a trapped
	# passenger lean on the door-open button. This is the interlock every real
	# lift has: the coupler vane on the car door only engages the landing door
	# rollers inside the zone, so there is nothing to open onto the shaft wall
	# with. EN 81-20 5.3.9.
	press_for("car_5")
	step_until(func(): return plant.pos_mm > 4700.0, 20.0)
	plant.sw_estop = true
	step(2.0)
	plant.sw_estop = false
	step(0.5)
	check("the car is stranded between floors", not plant.in_door_zone(),
			"(pos=%.0f mm, %+.0f mm from the nearest sill)"
					% [plant.pos_mm, plant.floor_offset_mm()])

	for i in range(12):
		press_for("door_open", 0.5)
	check("leaning on DOOR OPEN does nothing there", plant.door_pos < 0.01,
			"(door=%.0f%%)" % (plant.door_pos * 100))
	check("no door timeout was raised either",
			fault() == LiftIo.Fault.ESTOP,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])

	# Recover: the car homes to a floor, and there the button works again.
	press_for("reset")
	var homed := step_until(func(): return plant.in_door_zone() and fault() == 0, 30.0)
	check("it homes to a floor after the reset", homed,
			"(pos=%.0f mm)" % plant.pos_mm)
	press_for("door_open")
	var opened := step_until(func(): return plant.door_pos > 0.95, 10.0)
	check("and DOOR OPEN works once it is at a sill", opened,
			"(door=%.0f%%)" % (plant.door_pos * 100))


	# The controller gate above is the belt; this is the braces. The interlock
	# is a mechanism, so the PLANT has to enforce it on its own — otherwise a
	# controller that wrongly commands door-open mid-shaft would sail through
	# the twin unnoticed, which defeats the point of having one.
	var fake := PackedInt32Array()
	fake.resize(LiftIo.REG_COUNT)
	fake[LiftIo.OUT_DOOR_CMD] = LiftIo.set_bit(0, LiftIo.DOOR_OPEN_CMD, true)

	var p := LiftPlant.new()
	p.pos_mm = 2.5 * LiftCfg.FLOOR_HEIGHT_MM        # squarely between floors
	for i in range(240):
		p.apply_outputs(fake)
		p.step(DT)
	check("the plant refuses the command on its own, mid-shaft",
			p.door_pos < 0.01,
			"(door=%.0f%%, %+.0f mm from the nearest sill)"
					% [p.door_pos * 100, p.floor_offset_mm()])

	var q := LiftPlant.new()
	q.pos_mm = 2.0 * LiftCfg.FLOOR_HEIGHT_MM        # at a sill
	for i in range(240):
		q.apply_outputs(fake)
		q.step(DT)
	check("and obeys the same command at a sill", q.door_pos > 0.95,
			"(door=%.0f%%)" % (q.door_pos * 100))


func test_encoder_correction() -> void:
	print("\n20) Encoder drift is trimmed against the floor vanes")
	reset(0)

	# The encoder is on the motor and counts rope payout, so it drifts. The
	# vanes in the shaft are the only absolute reference there is, and a real
	# controller re-datums against them every time the car comes to rest level.
	plant.sw_rope_slip = true          # the rope creeps a little over the sheave

	var worst := 0.0
	var diverge := 0.0
	for f in [1, 3, 5, 2, 0]:
		press_for("car_%d" % f)
		var ok := step_until(func(): return cur_floor() == f and status(LiftIo.ST_DOOR_OPEN), 45.0)
		if not ok:
			check("reached floor %d despite the slip" % f, false,
					"(floor=%d, fault=%s)" % [cur_floor(), LiftIo.FAULT_TEXT[fault()]])
			return
		# The car's real position is what matters, not the encoder's opinion.
		worst = maxf(worst, absf(plant.floor_offset_mm()))
		diverge = maxf(diverge, absf(plant.pos_mm - plant.car_pos_mm()))
		step(3.0)

	check("a slipping rope does not stop the lift working", fault() == LiftIo.Fault.NONE,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])
	check("and the car still lands level at every floor",
			worst <= LiftCfg.DOOR_ZONE_MM,
			"(worst %.0f mm off the sill over five trips)" % worst)
	# The creep is signed, so a round trip largely cancels it - but at the top
	# of the run the count and the car are a long way apart, and the lift kept
	# working only because the vanes re-datumed it at every stop.
	check("the encoder and the car really did diverge", diverge > 50.0,
			"(worst %.0f mm apart)" % diverge)

	# Slip bad enough to lose half a floor in one trip is past trimming: the
	# vane and the corrected position then disagree about which floor this is,
	# and that has to be reported rather than quietly absorbed.
	reset(0)
	plant.sw_rope_slip = true
	plant.rope_slip_frac = 0.15
	press_for("car_5")
	var caught := step_until(func(): return fault() == LiftIo.Fault.ENCODER, 60.0)
	check("gross slip is reported instead of absorbed", caught,
			"(code=%d %s, car %.0f mm behind the encoder)"
					% [fault(), LiftIo.FAULT_TEXT[fault()],
					plant.pos_mm - plant.car_pos_mm()])

	# The other way the position can be wrong is that the sensor reading the
	# vanes has failed. Then the count says "arrived" with nothing underneath to
	# confirm it, and the only safe answer is to stop and say so — the doors are
	# interlocked to the zone anyway, so they could not open there.
	reset(0)
	press_for("car_3")
	step_until(func(): return plant.pos_mm > 1000.0, 15.0)
	plant.sw_vane_dead = true
	var noticed := step_until(func(): return fault() == LiftIo.Fault.ENCODER, 30.0)
	check("a dead floor sensor is noticed on arrival", noticed,
			"(code=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])
	check("and the doors stayed shut with no vane to confirm the floor",
			plant.door_pos < 0.01, "(door=%.0f%%)" % (plant.door_pos * 100))


func test_terminal_slowdown() -> void:
	print("\n21) Terminal slowdown: the cams do not believe the encoder")

	# On a healthy lift the cams are invisible: they sit just above what the
	# approach curve wants there, so they never bite.
	reset(0)
	var peak_healthy := 0.0
	press_for("car_5")
	var elapsed := 0.0
	while elapsed < 45.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		peak_healthy = maxf(peak_healthy, absf(plant.speed_mms))
		if status(LiftIo.ST_DOOR_OPEN):
			break
	check("a normal run still reaches rated speed",
			peak_healthy > float(LiftCfg.V_RATED_MMS) * 0.95,
			"(peak %.0f mm/s of %d)" % [peak_healthy, LiftCfg.V_RATED_MMS])

	# Now take away everything else. The vane sensor dies AND the count jumps
	# back three metres, so the controller thinks it has much further to go and
	# keeps asking for rated speed straight at the top terminal. With no vane to
	# contradict the count while the car is moving, the cams are the only thing
	# left in the shaft that still knows where the terminal is. That is the
	# whole reason they are wired independently of the encoder.
	reset(0)
	press_for("car_5")
	step_until(func(): return plant.pos_mm > 12000.0, 30.0)
	plant.sw_vane_dead = true
	plant.slip_encoder(-3000.0)
	var top_mm := float(LiftCfg.TOP_FLOOR * LiftCfg.FLOOR_HEIGHT_MM)
	var speed_at_top := 0.0
	var overrun := 0.0
	elapsed = 0.0
	while elapsed < 25.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		if plant.car_pos_mm() >= top_mm and speed_at_top == 0.0:
			speed_at_top = maxf(absf(plant.speed_mms), 0.01)
		overrun = maxf(overrun, plant.car_pos_mm() - top_mm)
		if absf(plant.speed_mms) < 1.0 and elapsed > 2.0:
			break

	var with_cam := speed_at_top
	var hit_with_cam := plant.buffer_struck
	check("the cam slowed it before the terminal",
			speed_at_top < float(LiftCfg.V_RATED_MMS) * 0.85,
			"(crossed the top floor at %.0f mm/s instead of %d)"
					% [speed_at_top, LiftCfg.V_RATED_MMS])
	check("the limit switch then stopped it short of the buffer",
			not hit_with_cam and overrun < float(LiftCfg.OVERTRAVEL_MM) + LiftCfg.RUNBY_MM,
			"(overran %.0f mm; switch at %d, buffer at %.0f)"
					% [overrun, LiftCfg.OVERTRAVEL_MM,
					LiftCfg.OVERTRAVEL_MM + LiftCfg.RUNBY_MM])

	# Same fault again with the cams dead. Now nothing in the shaft slows the
	# car before the limit switch, and the brake alone cannot stop it in the
	# runby - it reaches the buffer. That gap is what the cams buy.
	reset(0)
	plant.sw_nts_dead = true
	press_for("car_5")
	step_until(func(): return plant.pos_mm > 12000.0, 30.0)
	plant.sw_vane_dead = true
	plant.slip_encoder(-3000.0)
	var bare_top := 0.0
	elapsed = 0.0
	while elapsed < 25.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		if plant.car_pos_mm() >= top_mm and bare_top == 0.0:
			bare_top = maxf(absf(plant.speed_mms), 0.01)
		if absf(plant.speed_mms) < 1.0 and elapsed > 2.0:
			break
	check("without the cams it arrives at the terminal much faster",
			bare_top > with_cam + 200.0,
			"(%.0f mm/s against %.0f with the cams)" % [bare_top, with_cam])
	check("and reaches the buffer, which is what the cams prevent",
			plant.buffer_struck, "(buffer struck: %s)" % plant.buffer_struck)


func test_special_services() -> void:
	print("\n22) Independent service and firefighter Phase II")
	reset(0)

	# --- Independent (attendant) service ---------------------------------
	# A key switch in the car takes it out of the landing-call system: it
	# answers only what is pressed inside, and the doors stay open until
	# somebody presses CLOSE. An attendant holding a floor while a bed is
	# loaded is the whole reason it exists.
	plant.sw_independent = true
	step(0.3)
	check("independent service is flagged", status(LiftIo.ST_INDEPENDENT))

	press_for("hall_up_2")
	press_for("car_4")
	var at4 := step_until(func(): return cur_floor() == 4 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("it serves the car call", at4, "(floor=%d)" % cur_floor())
	check("and drove past the landing call", plant.trip_count <= 1,
			"(%d stops)" % plant.trip_count)
	check("the landing call is still waiting",
			LiftIo.get_bit(regs_out[LiftIo.OUT_LAMP_UP], 2))

	# The dwell expires and the door still does not close on its own.
	step(12.0)
	check("the door stays open past the dwell", plant.door_pos > 0.95,
			"(door=%.0f%%, dwell is %.0f s)" % [plant.door_pos * 100, LiftCfg.T_DOOR_DWELL])
	press_for("door_close", 4.0)
	check("CLOSE is what shuts it", plant.door_pos < 0.05,
			"(door=%.0f%%)" % (plant.door_pos * 100))

	plant.sw_independent = false
	var served := step_until(func(): return cur_floor() == 2 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("the landing call is served once the key is turned back", served,
			"(floor=%d)" % cur_floor())

	# --- Firefighter Phase II --------------------------------------------
	# Phase I recalls the car; the second key switch inside hands it over.
	reset(4)
	plant.sw_fire = true
	var recalled := step_until(_cond_at_fire_floor, 45.0)
	check("Phase I parked the car at the recall floor", recalled,
			"(floor=%d)" % cur_floor())

	plant.sw_fire_ph2 = true
	step(0.5)
	check("the in-car key hands over to Phase II",
			state() == LiftIo.State.FIRE_PH2,
			"(state=%s)" % LiftIo.STATE_TEXT[state()])

	# Constant pressure: hold CLOSE for a moment, let go, and the door comes
	# straight back — the firefighter has to keep a hand on it.
	for i in range(60):
		plant.hold("door_close", true)
		step(DT)
	plant.hold("door_close", false)
	var part_closed := plant.door_pos
	step(4.0)
	check("letting go of CLOSE re-opens the door",
			part_closed < 0.95 and plant.door_pos > 0.95,
			"(fell to %.0f%%, back to %.0f%%)" % [part_closed * 100, plant.door_pos * 100])

	# Holding it shuts the door and lets the car run.
	for i in range(900):
		plant.hold("door_close", true)
		step(DT)
		if plant.door_pos <= 0.005:
			break
	plant.hold("door_close", false)
	check("holding CLOSE shuts it", plant.door_pos <= 0.005,
			"(door=%.0f%%)" % (plant.door_pos * 100))

	press_for("car_3")
	var moved := step_until(func(): return cur_floor() == 3 and absf(plant.speed_mms) < 1.0, 45.0)
	check("the firefighter can send the car to a floor", moved,
			"(floor=%d)" % cur_floor())
	step(3.0)
	check("but the door does NOT open on arrival by itself",
			plant.door_pos < 0.05, "(door=%.0f%%)" % (plant.door_pos * 100))

	for i in range(900):
		plant.hold("door_open", true)
		step(DT)
		if plant.door_pos > 0.995:
			break
	plant.hold("door_open", false)
	check("holding OPEN is what opens it", plant.door_pos > 0.95,
			"(door=%.0f%%)" % (plant.door_pos * 100))
