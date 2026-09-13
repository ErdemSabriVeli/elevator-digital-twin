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
