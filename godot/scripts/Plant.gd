class_name LiftPlant
extends RefCounted

## The physical plant model — the "real world" side of the digital twin.
##
## It takes the PLC outputs (drive / door commands), integrates car and door
## motion, and in return produces the field sensors (encoder, floor sensor,
## limit switches, door limits, lock contact).
##
## The PLC computes NOTHING in this model; it only commands.

# --- state -------------------------------------------------------------------
var pos_mm := 0.0                 # absolute car position
var speed_mms := 0.0              # signed: + is up
var accel_mms2 := 0.0             # current acceleration (for the S-curve profile)
var door_pos := 0.0               # 0 = fully closed, 1 = fully open
var load_kg := 75

# --- fault / mode injection (toggled from the HUD) --------------------------
var sw_estop := false
var sw_safety_chain := true       # false = chain broken
var sw_governor_ok := true
var sw_drive_fault := false
var sw_fire := false
var sw_inspection := false
var sw_obstruction := false       # light curtain permanently blocked
var sw_rope_slip := false         # encoder drift simulation
var sw_brake_stuck := false       # brake mechanically stuck
var sw_overspeed := false         # mild drive runaway -> electrical trip
var sw_severe_runaway := false    # runaway the controller cannot catch in time
var sw_car_jammed := false        # car jammed / ropes slipping completely
var sw_no_load_comp := false      # drive ignores the pre-torque reference

## Safety gear: the wedges the governor pulls onto the guide rails once the car
## passes the mechanical trip speed. It is not a fault the panel can clear -
## freeing the wedges is a hands-on job at the car, so it stays set until
## release_safety_gear() is called.
var safety_gear_set := false

const BRAKE_RESPONSE_S := 0.15    # brake coil response time
var _brake_t := 0.0
var _torque_ramp := 0.0           # 0..1, how much pre-torque the drive has built
var _a_loop := 0.0                # the speed loop's share of the acceleration

# --- PLC commands (last received) -------------------------------------------
var c_drive_enable := false
var c_run_up := false
var c_run_down := false
var c_brake := false
var c_speed_sp := 0
var c_pretorque := 0              # per mille of the rated-load torque
var c_door_open := false
var c_door_close := false
var c_door_nudge := false

# --- momentary buttons -------------------------------------------------------
var _pulse := {}                  # key -> remaining time

# --- measurement / observation -----------------------------------------------
var brake_engaged := true
var powered := false              # is the drive actually producing torque
var travel_distance_mm := 0.0
var trip_count := 0
var _was_moving := false


func _init() -> void:
	pos_mm = float(LiftCfg.PARK_FLOOR * LiftCfg.FLOOR_HEIGHT_MM)


# =============================================================================
# BUTTONS
# =============================================================================
func press(key: String) -> void:
	_pulse[key] = LiftCfg.BTN_PULSE_S

func hold(key: String, on: bool) -> void:
	if on:
		_pulse[key] = 0.05      # refreshed every frame
	else:
		_pulse.erase(key)

func is_pressed(key: String) -> bool:
	return _pulse.has(key)

func _tick_buttons(dt: float) -> void:
	for k in _pulse.keys():
		_pulse[k] -= dt
		if _pulse[k] <= 0.0:
			_pulse.erase(k)


# =============================================================================
# APPLY PLC OUTPUTS
# =============================================================================
func apply_outputs(o: PackedInt32Array) -> void:
	if o.size() < LiftIo.REG_COUNT:
		return
	var d := o[LiftIo.OUT_DRIVE_CMD]
	c_drive_enable = LiftIo.get_bit(d, LiftIo.DRV_ENABLE)
	c_run_up = LiftIo.get_bit(d, LiftIo.DRV_UP)
	c_run_down = LiftIo.get_bit(d, LiftIo.DRV_DOWN)
	c_brake = LiftIo.get_bit(d, LiftIo.DRV_BRAKE)
	c_speed_sp = o[LiftIo.OUT_SPEED_SP]
	c_pretorque = LiftIo.to_signed(o[LiftIo.OUT_PRETORQUE])

	var dc := o[LiftIo.OUT_DOOR_CMD]
	c_door_open = LiftIo.get_bit(dc, LiftIo.DOOR_OPEN_CMD)
	c_door_close = LiftIo.get_bit(dc, LiftIo.DOOR_CLOSE_CMD)
	c_door_nudge = LiftIo.get_bit(dc, LiftIo.DOOR_NUDGE_CMD)


# =============================================================================
# PHYSICS STEP
# =============================================================================
func step(dt: float) -> void:
	_tick_buttons(dt)

	# --- brake: responds to the command with a delay (coil current + spring) ---
	# With sw_brake_stuck on the brake stays mechanically engaged; even with a
	# release command no feedback arrives -> the PLC sees a brake fault.
	if sw_brake_stuck:
		_brake_t = 0.0
		brake_engaged = true
	elif c_brake != (not brake_engaged):
		_brake_t += dt
		if _brake_t >= BRAKE_RESPONSE_S:
			_brake_t = 0.0
			brake_engaged = not c_brake
	else:
		_brake_t = 0.0

	var v_target := 0.0
	powered = c_drive_enable and not brake_engaged \
			and not sw_estop and sw_safety_chain

	# sw_overspeed: drive runaway — actual speed exceeds the reference and the
	# governor must trip.
	var v_ref := float(c_speed_sp)
	if sw_severe_runaway:
		v_ref *= 1.45      # fast enough that the governor grips before the PLC reacts
	elif sw_overspeed:
		v_ref *= 1.20      # past the electrical trip, short of the mechanical one

	if powered:
		if c_run_up and not c_run_down:
			v_target = v_ref
		elif c_run_down and not c_run_up:
			v_target = -v_ref

	# --- S-curve speed profile (jerk limited) ------------------------------
	# A real elevator drive does not apply acceleration instantly; the rate of
	# change of acceleration (jerk) is bounded. That is why passengers feel no
	# jolt, and it gives starts and stops their characteristic smoothness.
	#
	#   a_stop = sqrt(2 * jerk * |error|)  -> the acceleration that can still be
	#   bled to zero; approaching the target it backs off on its own, no overshoot.
	var a_max := LiftCfg.ACCEL_MMS2
	if absf(v_target) < absf(speed_mms):
		a_max = LiftCfg.DECEL_MMS2
	var jerk := LiftCfg.JERK_MMS3

	# The jerk limit is a COMFORT constraint and only matters at speeds the
	# passenger feels. At creep (levelling) speed a real drive also reacts
	# quickly, so we relax the limit here too — otherwise the car overshoots
	# floor level and oscillates around it.
	var creep := LiftCfg.V_LEVEL_MMS * 1.3
	if absf(speed_mms) <= creep and absf(v_target) <= creep:
		jerk = LiftCfg.JERK_MMS3 * 8.0

	# --- load imbalance and the drive's answer to it -------------------------
	# The machine is a friction sheave, not a screw: once the brake lifts, the
	# only thing holding the car is motor torque. The counterweight cancels the
	# empty car plus half the rated load, so what is left over pulls the car
	# down when it is full and up when it is empty.
	#
	# The drive builds its pre-torque BEFORE the brake opens (it is enabled a
	# start delay earlier), which is why a correctly compensated lift does not
	# move at all at the moment of release.
	_torque_ramp = move_toward(_torque_ramp, 1.0 if c_drive_enable else 0.0,
			dt / LiftCfg.T_TORQUE_RAMP)
	var a_bias := imbalance_accel_mms2()
	var a_ff := 0.0
	if not sw_no_load_comp:
		a_ff = pretorque_accel_mms2(c_pretorque) * _torque_ramp

	if not powered:
		# BRAKE: a friction element. It pulls speed to zero and holds it there;
		# it can NEVER drive the car backwards. That is why the jerk integrator
		# is not used here (with it, acceleration overshoots zero and the car
		# would reverse). It also holds against the imbalance, so a_bias does
		# not apply while the shoes are on.
		accel_mms2 = 0.0
		_a_loop = 0.0
		speed_mms = move_toward(speed_mms, 0.0, LiftCfg.DECEL_MMS2 * 3.0 * dt)
	else:
		var v_err := v_target - speed_mms
		var a_cmd := 0.0
		if absf(v_err) > 0.001:
			var a_stop := sqrt(2.0 * jerk * absf(v_err))
			a_cmd = signf(v_err) * minf(a_max, a_stop)
			# Do not command an acceleration that would overshoot the target in a
			# single step. (FORCING acceleration to zero after overshooting would
			# violate the jerk limit ourselves; we bound the command instead.)
			var a_reach := v_err / dt
			if absf(a_cmd) > absf(a_reach):
				a_cmd = a_reach

		# The speed loop only has to make up whatever the feed-forward missed —
		# the residual is what the passenger feels as rollback.
		_a_loop = move_toward(_a_loop, a_cmd, jerk * dt)
		accel_mms2 = _a_loop + a_bias + a_ff
		speed_mms += accel_mms2 * dt

	# --- overspeed governor and safety gear ---------------------------------
	# Two stages, and they are separate devices. At C_V_OVERSPEED_MMS the
	# governor's electrical contact opens and the controller is expected to stop
	# the car itself. If it cannot — a drive fast enough that the controller is
	# still confirming while the car accelerates — the governor grips its rope at
	# C_V_GEAR_TRIP_MMS and that pulls the safety gear wedges onto the guide
	# rails. The wedges only bite downwards, which is why they are the answer to
	# a falling car and not to an overspeeding one going up.
	if not safety_gear_set and speed_mms < -float(LiftCfg.V_GEAR_TRIP_MMS):
		safety_gear_set = true
		sw_governor_ok = false          # the governor contact goes with it

	if safety_gear_set:
		# Progressive gear: the wedges slip against the rails at a roughly
		# constant retardation rather than stopping the car dead.
		speed_mms = move_toward(speed_mms, 0.0, LiftCfg.A_GEAR_MMS2 * dt)
		accel_mms2 = 0.0
		_a_loop = 0.0
		# Set wedges hold against downward motion; the car can still be lifted
		# off them, which is how they are freed.
		speed_mms = maxf(speed_mms, 0.0)

	# --- position integration ----------------------------------------------
	var slip := 1.0
	if sw_car_jammed:
		slip = 0.0                           # car does not advance -> travel timeout
	elif sw_rope_slip and absf(speed_mms) > 10.0:
		slip = 0.92                          # rope slip -> encoder drift
	var d_mm := speed_mms * dt * slip
	pos_mm += d_mm
	travel_distance_mm += absf(d_mm)

	# --- mechanical limit (buffer) -----------------------------------------
	var pos_min := -float(LiftCfg.OVERTRAVEL_MM) - 100.0
	var pos_max := float(LiftCfg.TOP_FLOOR * LiftCfg.FLOOR_HEIGHT_MM + LiftCfg.OVERTRAVEL_MM) + 100.0
	if pos_mm <= pos_min:
		pos_mm = pos_min
		speed_mms = 0.0
	elif pos_mm >= pos_max:
		pos_mm = pos_max
		speed_mms = 0.0

	# --- door ---------------------------------------------------------------
	# The door motor only runs while the car is nearly stopped (mechanical
	# coupling).
	#
	# A real door operator does not run at constant speed: it slows near both
	# ends and speeds up in the middle. That protects the mechanism and avoids
	# slamming. The speed factor is modelled with a half-sine envelope over
	# position.
	if absf(speed_mms) < 100.0:
		var env: float = 0.35 + 0.65 * sin(PI * clampf(door_pos, 0.0, 1.0))
		if c_door_open:
			door_pos = minf(1.0, door_pos + env * dt / LiftCfg.DOOR_OPEN_TIME)
		elif c_door_close:
			var sp := env * dt / LiftCfg.DOOR_CLOSE_TIME
			if c_door_nudge:
				sp *= LiftCfg.DOOR_NUDGE_SCALE
			door_pos = maxf(0.0, door_pos - sp)

	# --- trip counter ------------------------------------------------------
	var mv := absf(speed_mms) > 5.0
	if _was_moving and not mv:
		trip_count += 1
	_was_moving = mv


# =============================================================================
# SENSORS -> MODBUS HOLDING REGISTERS
# =============================================================================
func build_registers(heartbeat: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(LiftIo.REG_COUNT)

	# --- call buttons ------------------------------------------------------
	var up := 0
	var dn := 0
	var car := 0
	for f in range(LiftCfg.FLOOR_COUNT):
		if is_pressed("hall_up_%d" % f):
			up = LiftIo.set_bit(up, f, true)
		if is_pressed("hall_down_%d" % f):
			dn = LiftIo.set_bit(dn, f, true)
		if is_pressed("car_%d" % f):
			car = LiftIo.set_bit(car, f, true)
	r[LiftIo.IN_HALL_UP] = up
	r[LiftIo.IN_HALL_DOWN] = dn
	r[LiftIo.IN_CAR_CALL] = car

	# --- command bits ------------------------------------------------------
	var overload := load_kg > LiftCfg.LOAD_OVER_KG
	var cmd := 0
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DOOR_OPEN, is_pressed("door_open"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DOOR_CLOSE, is_pressed("door_close"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_ALARM, is_pressed("alarm"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_ESTOP, sw_estop)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_OVERLOAD, overload)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_FIRE, sw_fire)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_INSPECTION, sw_inspection)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_RESET, is_pressed("reset"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_OBSTRUCTION, _obstructed())
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DRIVE_READY, not sw_drive_fault)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DRIVE_FAULT, sw_drive_fault)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_INSP_UP, is_pressed("insp_up"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_INSP_DOWN, is_pressed("insp_down"))
	r[LiftIo.IN_CMD] = cmd

	# --- floor (door zone) sensors -----------------------------------------
	var zone := 0
	for f in range(LiftCfg.FLOOR_COUNT):
		if absf(pos_mm - f * LiftCfg.FLOOR_HEIGHT_MM) <= LiftCfg.DOOR_ZONE_MM:
			zone = LiftIo.set_bit(zone, f, true)
	r[LiftIo.IN_FLOOR_ZONE] = zone

	# --- limits and lock ---------------------------------------------------
	var top_lim := pos_mm >= float(LiftCfg.TOP_FLOOR * LiftCfg.FLOOR_HEIGHT_MM + LiftCfg.OVERTRAVEL_MM)
	var bot_lim := pos_mm <= -float(LiftCfg.OVERTRAVEL_MM)
	var d_open := door_pos >= 0.995
	var d_close := door_pos <= 0.005
	# Landing door lock chain: counted as locked when the door is fully closed
	# (a landing door cannot be opened out in the shaft).
	var locked := d_close

	var lim := 0
	lim = LiftIo.set_bit(lim, LiftIo.LIM_TOP, top_lim)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_BOTTOM, bot_lim)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_DOOR_OPEN, d_open)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_DOOR_CLOSE, d_close)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_DOOR_LOCK, locked)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_BRAKE_FB, not brake_engaged)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_SAFETY, sw_safety_chain and not sw_estop)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_GOVERNOR, sw_governor_ok)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_SAFETY_GEAR, safety_gear_set)
	r[LiftIo.IN_LIMITS] = lim

	# --- analogue ----------------------------------------------------------
	r[LiftIo.IN_POS_MM] = clampi(int(round(pos_mm)), 0, 65535)
	r[LiftIo.IN_SPEED_MMS] = clampi(int(absf(speed_mms)), 0, 65535)
	r[LiftIo.IN_DOOR_PMIL] = clampi(int(door_pos * 1000.0), 0, 1000)
	r[LiftIo.IN_LOAD_KG] = clampi(load_kg, 0, 65535)
	r[LiftIo.IN_HEARTBEAT] = heartbeat & 0x7FFF

	return r


## Frees the safety gear wedges. On a real lift this is a hands-on job at the
## car, not something the panel can do, so nothing in the control logic calls it.
func release_safety_gear() -> void:
	safety_gear_set = false
	sw_governor_ok = true


## Moving mass seen by the machine: both hanging masses plus the rotating
## inertia of sheave and motor, referred to the rope.
func moving_mass_kg() -> float:
	return (LiftCfg.CAR_EMPTY_KG + load_kg + LiftCfg.CWT_KG) * LiftCfg.ROT_INERTIA


## Acceleration the load imbalance produces with the brake off and no torque.
## Negative = the car is heavier than the counterweight and sinks.
func imbalance_accel_mms2() -> float:
	var net := float(LiftCfg.CAR_EMPTY_KG + load_kg - LiftCfg.CWT_KG)
	return -net * LiftCfg.G_MMS2 / moving_mass_kg()


## Acceleration the drive produces for a given pre-torque reference. Full scale
## (1000) is the torque that balances a full rated-load imbalance.
func pretorque_accel_mms2(permille: int) -> float:
	var kg := float(permille) * 0.001 * float(LiftCfg.LOAD_FULL_KG)
	return kg * LiftCfg.G_MMS2 / moving_mass_kg()


func _obstructed() -> bool:
	# The manual light-curtain switch or a "passenger passing" pulse
	return sw_obstruction or is_pressed("obstruct")


# =============================================================================
# Helpers (for the visual side)
# =============================================================================
func car_y() -> float:
	return pos_mm * 0.001

func nearest_floor() -> int:
	return clampi(int(round(pos_mm / LiftCfg.FLOOR_HEIGHT_MM)), 0, LiftCfg.TOP_FLOOR)

func counterweight_y() -> float:
	# 1:1 roping: as the car goes up the counterweight comes down.
	# The offset is chosen so the counterweight does not land on the pit buffer
	# when the car is at the top (see tests/geometry_test.gd).
	var top := float(LiftCfg.TOP_FLOOR) * LiftCfg.M_FLOOR_H
	return top - car_y() - 0.10
