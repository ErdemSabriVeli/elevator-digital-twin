class_name SoftPlc
extends RefCounted

## A LINE-FOR-LINE GDScript twin of the ST code in codesys/.
##
## Class <-> POU mapping:
##   Ton           <-> TON (standard)
##   CallRegistry  <-> FB_CallRegistry.st
##   Dispatcher    <-> FB_Dispatcher.st
##   DoorCtrl      <-> FB_DoorCtrl.st
##   Motion        <-> FB_Motion.st
##   Safety        <-> FB_Safety.st
##   LiftCore      <-> FB_LiftCore.st
##   scan()        <-> PLC_PRG.st  (including the Modbus register <-> struct
##                                  conversion)
##
## The block call order is kept identical to the ST, so the "one scan of lag"
## behaviour matches too and CODESYS and Godot produce the same result.

# =============================================================================
# Helper: TON timer
# =============================================================================
class Ton extends RefCounted:
	var et := 0.0
	var q := false

	func update(inp: bool, pt: float, dt: float) -> bool:
		if inp:
			et = minf(et + dt, pt)
			q = et >= pt
		else:
			et = 0.0
			q = false
		return q

	func reset() -> void:
		et = 0.0
		q = false


## TOF - off delay: Q is TRUE while the input is TRUE, and stays TRUE for PT
## after the input falls. (The standard CODESYS TOF.)
class Tof extends RefCounted:
	var et := 0.0
	var q := false

	func update(inp: bool, pt: float, dt: float) -> bool:
		if inp:
			et = 0.0
			q = true
		elif q:
			et += dt
			if et >= pt:
				q = false
		return q

	func reset() -> void:
		et = 0.0
		q = false


class RTrig extends RefCounted:
	var _last := false
	var q := false

	func update(clk: bool) -> bool:
		q = clk and not _last
		_last = clk
		return q


# =============================================================================
# ST_CallSet
# =============================================================================
class CallSet extends RefCounted:
	var up: Array[bool] = []
	var down: Array[bool] = []
	var car: Array[bool] = []

	func _init() -> void:
		up.resize(16)
		down.resize(16)
		car.resize(16)

	func clear() -> void:
		for i in 16:
			up[i] = false
			down[i] = false
			car[i] = false


# =============================================================================
# ST_LiftInputs
# =============================================================================
class Inputs extends RefCounted:
	var calls := CallSet.new()
	var door_open_btn := false
	var door_close_btn := false
	var alarm_btn := false
	var fault_reset := false

	var floor_zone: Array[bool] = []
	var pos_mm := 0
	var act_speed_mms := 0
	var door_pos_pmil := 0
	var load_kg := 0

	var top_limit := false
	var bot_limit := false
	var door_open_limit := false
	var door_close_limit := false
	var door_locked := false
	var brake_fb := false
	var safety_chain := true
	var governor_ok := true

	var estop := false
	var overload := false
	var obstruction := false
	var fire_call := false
	var inspection := false
	var insp_up := false
	var insp_down := false
	var drive_ready := true
	var drive_fault := false

	func _init() -> void:
		floor_zone.resize(16)


# =============================================================================
# ST_LiftOutputs
# =============================================================================
class Outputs extends RefCounted:
	var drive_enable := false
	var run_up := false
	var run_down := false
	var brake_release := false
	var leveling := false
	var speed_sp_mms := 0

	var door_open := false
	var door_close := false
	var door_nudge := false

	var lamp_up: Array[bool] = []
	var lamp_down: Array[bool] = []
	var lamp_car: Array[bool] = []

	var current_floor := 0
	var target_floor := -1
	var direction := LiftIo.DIR_NONE
	var state := LiftIo.State.INIT
	var fault := LiftIo.Fault.NONE
	var moving := false
	var door_is_open := false
	var door_is_closed := false
	var overload_lamp := false
	var fault_lamp := false
	var fire_mode := false
	var insp_mode := false
	var out_of_service := false
	var gong := false
	var alarm := false
	var cabin_light := true
	var door_timer_ms := 0
	var pretorque_pmil := 0
	var heartbeat := 0

	func _init() -> void:
		lamp_up.resize(16)
		lamp_down.resize(16)
		lamp_car.resize(16)


# =============================================================================
# FB_CallRegistry
# =============================================================================
class CallRegistry extends RefCounted:
	var latch := CallSet.new()
	var any_call := false
	var call_count := 0

	func scan(btn: CallSet, clear_all: bool, enable: bool) -> void:
		if clear_all:
			latch.clear()
			any_call = false
			call_count = 0
			return

		any_call = false
		call_count = 0

		for i in range(LiftCfg.TOP_FLOOR + 1):
			if enable:
				if btn.up[i] and i < LiftCfg.TOP_FLOOR:
					latch.up[i] = true
				if btn.down[i] and i > 0:
					latch.down[i] = true
				if btn.car[i]:
					latch.car[i] = true

			if latch.up[i]:
				call_count += 1
			if latch.down[i]:
				call_count += 1
			if latch.car[i]:
				call_count += 1

		any_call = call_count > 0

	func serve_floor(f: int, dir: int) -> void:
		if f < 0 or f > LiftCfg.TOP_FLOOR:
			return
		latch.car[f] = false
		match dir:
			LiftIo.DIR_UP:
				latch.up[f] = false
				if not call_above(f):
					latch.down[f] = false
			LiftIo.DIR_DOWN:
				latch.down[f] = false
				if not call_below(f):
					latch.up[f] = false
			_:
				latch.up[f] = false
				latch.down[f] = false

	func call_above(f: int) -> bool:
		for k in range(f + 1, LiftCfg.TOP_FLOOR + 1):
			if latch.up[k] or latch.down[k] or latch.car[k]:
				return true
		return false

	func call_below(f: int) -> bool:
		for k in range(0, f):
			if latch.up[k] or latch.down[k] or latch.car[k]:
				return true
		return false


# =============================================================================
# FB_Dispatcher
# =============================================================================
class Dispatcher extends RefCounted:
	var latch: CallSet
	var target := -1
	var new_dir := LiftIo.DIR_NONE
	var has_job := false

	func _init(p_latch: CallSet) -> void:
		latch = p_latch

	func scan(cur_floor: int, cur_dir: int) -> void:
		has_job = false
		target = -1
		new_dir = cur_dir

		# 1) keep going in the current direction
		if cur_dir == LiftIo.DIR_UP:
			var b := nearest_above(cur_floor)
			if b >= 0:
				target = b; new_dir = LiftIo.DIR_UP; has_job = true
				return
			if farthest_below(cur_floor) >= 0:
				target = nearest_below(cur_floor)
				new_dir = LiftIo.DIR_DOWN; has_job = true
				return

		elif cur_dir == LiftIo.DIR_DOWN:
			var b2 := nearest_below(cur_floor)
			if b2 >= 0:
				target = b2; new_dir = LiftIo.DIR_DOWN; has_job = true
				return
			if farthest_above(cur_floor) >= 0:
				target = nearest_above(cur_floor)
				new_dir = LiftIo.DIR_UP; has_job = true
				return

		# 2) a call at the current floor
		if call_at(cur_floor):
			target = cur_floor
			new_dir = LiftIo.DIR_NONE
			has_job = true
			return

		# 3) the nearest call
		var n := nearest_any(cur_floor)
		if n >= 0:
			target = n
			has_job = true
			if n > cur_floor:
				new_dir = LiftIo.DIR_UP
			elif n < cur_floor:
				new_dir = LiftIo.DIR_DOWN
			else:
				new_dir = LiftIo.DIR_NONE
		else:
			new_dir = LiftIo.DIR_NONE

	func stop_here(f: int, dir: int) -> bool:
		if f < 0 or f > LiftCfg.TOP_FLOOR:
			return false
		if latch.car[f]:
			return true
		match dir:
			LiftIo.DIR_UP:
				if latch.up[f]:
					return true
				if latch.down[f] and not any_above(f):
					return true
			LiftIo.DIR_DOWN:
				if latch.down[f]:
					return true
				if latch.up[f] and not any_below(f):
					return true
			_:
				return call_at(f)
		return false

	func call_at(f: int) -> bool:
		if f < 0 or f > LiftCfg.TOP_FLOOR:
			return false
		return latch.up[f] or latch.down[f] or latch.car[f]

	func any_above(f: int) -> bool:
		for k in range(f + 1, LiftCfg.TOP_FLOOR + 1):
			if call_at(k):
				return true
		return false

	func any_below(f: int) -> bool:
		for k in range(0, f):
			if call_at(k):
				return true
		return false

	func nearest_above(f: int) -> int:
		for k in range(f + 1, LiftCfg.TOP_FLOOR + 1):
			if call_at(k):
				return k
		return -1

	func nearest_below(f: int) -> int:
		for k in range(f - 1, -1, -1):
			if call_at(k):
				return k
		return -1

	func farthest_above(f: int) -> int:
		for k in range(LiftCfg.TOP_FLOOR, f, -1):
			if call_at(k):
				return k
		return -1

	func farthest_below(f: int) -> int:
		for k in range(0, f):
			if call_at(k):
				return k
		return -1

	func nearest_any(f: int) -> int:
		var u := nearest_above(f)
		var d := nearest_below(f)
		if u < 0 and d < 0:
			return -1
		if u < 0:
			return d
		if d < 0:
			return u
		return u if (u - f) - (f - d) <= 0 else d


# =============================================================================
# FB_DoorCtrl
# =============================================================================
class DoorCtrl extends RefCounted:
	var open_out := false
	var close_out := false
	var nudge := false
	var is_open := false
	var is_closed := false
	var dwell_done := false
	var fault := false
	var state := LiftIo.DoorState.CLOSED
	var remain_ms := 0

	var _t_dwell := Ton.new()
	var _t_move := Ton.new()
	var _t_nudge := Ton.new()

	func scan(enable: bool, req_open: bool, req_close: bool,
			open_limit: bool, close_limit: bool, obstruction: bool,
			open_btn: bool, close_btn: bool, overload: bool,
			dwell: float, dt: float) -> void:

		open_out = false
		close_out = false
		is_open = open_limit
		is_closed = close_limit
		dwell_done = false

		if not enable:
			state = LiftIo.DoorState.CLOSED
			_t_dwell.reset(); _t_move.reset(); _t_nudge.reset()
			nudge = false
			remain_ms = 0
			return

		match state:
			LiftIo.DoorState.CLOSED:
				_t_dwell.reset()
				_t_nudge.reset()
				nudge = false
				if req_open or open_btn:
					state = LiftIo.DoorState.OPENING
				elif not close_limit and req_close:
					state = LiftIo.DoorState.CLOSING

			LiftIo.DoorState.OPENING:
				open_out = true
				_t_move.update(true, LiftCfg.T_DOOR_MOVE_MAX, dt)
				if open_limit:
					_t_move.reset()
					state = LiftIo.DoorState.OPEN
				elif _t_move.q:
					_t_move.reset()
					fault = true
					state = LiftIo.DoorState.FAULT

			LiftIo.DoorState.OPEN:
				_t_dwell.update(not (obstruction or overload or open_btn or req_open), dwell, dt)
				_t_nudge.update(true, LiftCfg.T_NUDGE, dt)
				nudge = _t_nudge.q
				remain_ms = int(maxf(0.0, dwell - _t_dwell.et) * 1000.0)
				dwell_done = _t_dwell.q

				if close_btn and not obstruction and not overload and not req_open:
					state = LiftIo.DoorState.CLOSING
					_t_dwell.reset()
				elif _t_dwell.q and req_close:
					state = LiftIo.DoorState.CLOSING
					_t_dwell.reset()
				elif nudge and req_close:
					state = LiftIo.DoorState.CLOSING
					_t_dwell.reset()

			LiftIo.DoorState.CLOSING:
				close_out = true
				_t_move.update(true, LiftCfg.T_DOOR_MOVE_MAX, dt)
				remain_ms = 0
				if open_btn or req_open or overload or (obstruction and not nudge):
					_t_move.reset()
					state = LiftIo.DoorState.REOPEN
				elif close_limit:
					_t_move.reset()
					_t_nudge.reset()
					nudge = false
					state = LiftIo.DoorState.CLOSED
				elif _t_move.q:
					_t_move.reset()
					fault = true
					state = LiftIo.DoorState.FAULT

			LiftIo.DoorState.REOPEN:
				open_out = true
				if open_limit:
					state = LiftIo.DoorState.OPEN
					_t_dwell.reset()

			LiftIo.DoorState.FAULT:
				open_out = false
				close_out = false
				remain_ms = 0
				if not fault:
					state = LiftIo.DoorState.CLOSED if close_limit else LiftIo.DoorState.OPENING

	func reset() -> void:
		fault = false


# =============================================================================
# FB_Motion
# =============================================================================
class Motion extends RefCounted:
	var drive_enable := false
	var run_up := false
	var run_down := false
	var brake_release := false
	var leveling := false
	var speed_sp := 0
	var dir := LiftIo.DIR_NONE
	var at_target := false
	var timeout := false
	var err_mm := 0
	var pretorque_pmil := 0

	var _t_travel := Ton.new()
	var _t_brake := Ton.new()
	var _t_torque := Ton.new()
	var _t_brake_fb := Ton.new()

	func scan(enable: bool, target_floor: int, pos_mm: int,
			top_limit: bool, bot_limit: bool,
			inspection: bool, insp_up: bool, insp_down: bool,
			load_kg: int, dt: float) -> void:

		# --- pre-torque (load compensation) ---------------------------------
		# A gearless machine holds the car purely by friction on the sheave, so
		# at the instant the brake lifts the only thing opposing the load
		# imbalance is motor torque. If the drive is not already producing it,
		# the car rolls back - down when it is heavy, up when it is light. Real
		# controllers read the load cell and feed the drive a torque reference
		# BEFORE the brake opens.
		#
		# Scaled per mille of the torque needed for a full rated-load imbalance.
		var net := LiftCfg.CAR_EMPTY_KG + load_kg - LiftCfg.CWT_KG
		pretorque_pmil = int(net * 1000 / LiftCfg.LOAD_FULL_KG)

		# --- inspection mode ------------------------------------------------
		if inspection:
			at_target = false
			_t_travel.reset()
			timeout = false
			if enable and insp_up and not insp_down and not top_limit:
				drive_enable = true
				_t_torque.update(true, LiftCfg.T_START_DELAY, dt)
				brake_release = _t_torque.q
				run_up = true; run_down = false
				speed_sp = LiftCfg.V_INSPECT_MMS; dir = LiftIo.DIR_UP
			elif enable and insp_down and not insp_up and not bot_limit:
				drive_enable = true
				_t_torque.update(true, LiftCfg.T_START_DELAY, dt)
				brake_release = _t_torque.q
				run_up = false; run_down = true
				speed_sp = LiftCfg.V_INSPECT_MMS; dir = LiftIo.DIR_DOWN
			else:
				drive_enable = false; brake_release = false
				_t_torque.reset()
				run_up = false; run_down = false
				speed_sp = 0; dir = LiftIo.DIR_NONE
			leveling = true
			return

		# --- no target / not permitted --------------------------------------
		if target_floor < 0 or target_floor > LiftCfg.TOP_FLOOR or not enable:
			drive_enable = false
			run_up = false
			run_down = false
			brake_release = false
			leveling = false
			speed_sp = 0
			dir = LiftIo.DIR_NONE
			at_target = false
			_t_torque.reset()
			# The OUTPUT FLAG has to be cleared along with the timer; otherwise a
			# timeout that fired once sticks and the fault can never be reset.
			_t_travel.reset()
			timeout = false
			return

		var target_mm := target_floor * LiftCfg.FLOOR_HEIGHT_MM
		err_mm = target_mm - pos_mm
		var abs_err: int = abs(err_mm)

		# --- target reached --------------------------------------------------
		if abs_err <= LiftCfg.LEVEL_TOL_MM:
			at_target = true
			run_up = false
			run_down = false
			speed_sp = 0
			dir = LiftIo.DIR_NONE
			leveling = false
			_t_travel.reset()
			_t_torque.reset()
			_t_brake.update(true, LiftCfg.T_BRAKE, dt)
			brake_release = not _t_brake.q
			drive_enable = not _t_brake.q
			return

		at_target = false
		_t_brake.reset()

		# --- the end limits ---------------------------------------------------
		if (err_mm > 0 and top_limit) or (err_mm < 0 and bot_limit):
			drive_enable = false; run_up = false; run_down = false
			speed_sp = 0; brake_release = false; dir = LiftIo.DIR_NONE
			_t_torque.reset()
			return

		# --- speed profile ----------------------------------------------------
		if abs_err <= LiftCfg.DOOR_ZONE_MM:
			speed_sp = LiftCfg.V_LEVEL_MMS
			leveling = true
		elif abs_err >= LiftCfg.DECEL_DIST_MM:
			speed_sp = LiftCfg.V_RATED_MMS
			leveling = false
		else:
			speed_sp = LiftCfg.V_LEVEL_MMS + int(
				(abs_err - LiftCfg.DOOR_ZONE_MM)
				* (LiftCfg.V_RATED_MMS - LiftCfg.V_LEVEL_MMS)
				/ (LiftCfg.DECEL_DIST_MM - LiftCfg.DOOR_ZONE_MM))
			leveling = false

		# The drive is enabled first and the brake only opens once it has had
		# time to build torque against the load. Lift the shoes before the
		# machine is holding and the car drops away under its own imbalance.
		drive_enable = true
		_t_torque.update(true, LiftCfg.T_START_DELAY, dt)
		brake_release = _t_torque.q
		if err_mm > 0:
			run_up = true; run_down = false; dir = LiftIo.DIR_UP
		else:
			run_up = false; run_down = true; dir = LiftIo.DIR_DOWN

		_t_travel.update(true, LiftCfg.T_TRAVEL_MAX, dt)
		timeout = _t_travel.q

	func reset_timeout() -> void:
		_t_travel.reset()
		timeout = false

	## Brake feedback supervision: the command and the field must agree.
	## brake_cmd = brake release command, brake_fb = brake actually released
	func brake_mismatch(brake_cmd: bool, brake_fb: bool, dt: float) -> bool:
		_t_brake_fb.update(brake_cmd != brake_fb, LiftCfg.T_BRAKE_FB, dt)
		return _t_brake_fb.q

	static func floor_from_pos(pos_mm: int) -> int:
		for i in range(LiftCfg.TOP_FLOOR + 1):
			if abs(pos_mm - i * LiftCfg.FLOOR_HEIGHT_MM) <= LiftCfg.FLOOR_HEIGHT_MM / 2:
				return i
		if pos_mm > LiftCfg.TOP_FLOOR * LiftCfg.FLOOR_HEIGHT_MM:
			return LiftCfg.TOP_FLOOR
		return 0


# =============================================================================
# FB_Safety
# =============================================================================
class Safety extends RefCounted:
	var fault := LiftIo.Fault.NONE
	var is_fault := false
	var run_allow := false
	var _reset_edge := RTrig.new()
	var _t_overspeed := Ton.new()

	## Governor function: it trips if the actual speed exceeds 115% of rated.
	func overspeed_trip(act_speed_mms: int, dt: float) -> bool:
		_t_overspeed.update(act_speed_mms > LiftCfg.V_OVERSPEED_MMS,
				LiftCfg.T_OVERSPEED, dt)
		return _t_overspeed.q

	func scan(safety_chain: bool, governor_ok: bool, estop: bool,
			drive_ready: bool, drive_fault: bool,
			top_limit: bool, bot_limit: bool, door_locked: bool,
			moving: bool, door_timeout: bool, travel_timeout: bool,
			zone_mismatch: bool, overspeed: bool, brake_mismatch: bool,
			reset: bool) -> void:

		_reset_edge.update(reset)

		if fault == LiftIo.Fault.NONE:
			if estop:
				fault = LiftIo.Fault.ESTOP
			elif not safety_chain or not governor_ok:
				fault = LiftIo.Fault.SAFETY_CHAIN
			elif overspeed:
				fault = LiftIo.Fault.OVERSPEED
			elif drive_fault or not drive_ready:
				fault = LiftIo.Fault.DRIVE
			elif brake_mismatch:
				fault = LiftIo.Fault.BRAKE
			elif top_limit or bot_limit:
				fault = LiftIo.Fault.LIMIT
			elif moving and not door_locked:
				fault = LiftIo.Fault.LOCK_LOST
			elif travel_timeout:
				fault = LiftIo.Fault.TRAVEL_TIMEOUT
			elif door_timeout:
				fault = LiftIo.Fault.DOOR_TIMEOUT
			elif zone_mismatch:
				fault = LiftIo.Fault.ENCODER

		if _reset_edge.q:
			if (not estop and safety_chain and governor_ok
					and drive_ready and not drive_fault
					and not top_limit and not bot_limit):
				fault = LiftIo.Fault.NONE

		is_fault = fault != LiftIo.Fault.NONE
		run_allow = (not is_fault and safety_chain and governor_ok
				and drive_ready and not drive_fault and not estop)


# =============================================================================
# FB_LiftCore
# =============================================================================
class LiftCore extends RefCounted:
	var safety := Safety.new()
	var calls := CallRegistry.new()
	var disp: Dispatcher
	var door := DoorCtrl.new()
	var motion := Motion.new()
	var out := Outputs.new()

	var state := LiftIo.State.INIT
	var dir := LiftIo.DIR_NONE
	var cur_floor := 0
	var target_flr := -1
	var homed := false

	var _t_park := Ton.new()
	var _t_gong := Ton.new()
	var _t_start := Ton.new()
	var _t_alarm := Tof.new()
	var _gong_arm := false
	var _fire_parked := false
	var _hb_acc := 0.0
	var _hb := 0
	var _zone_mism := false
	var _zone_floor := -1

	func _init() -> void:
		disp = Dispatcher.new(calls.latch)

	func scan(inp: Inputs, dt: float) -> Outputs:
		# --- 1) safety -------------------------------------------------------
		# The governor (overspeed) and the brake feedback supervision: both
		# compare a measurement from the field against the command.
		var overspeed := safety.overspeed_trip(inp.act_speed_mms, dt)
		var brake_bad := motion.brake_mismatch(out.brake_release, inp.brake_fb, dt)

		safety.scan(inp.safety_chain, inp.governor_ok, inp.estop,
				inp.drive_ready, inp.drive_fault, inp.top_limit, inp.bot_limit,
				inp.door_locked, out.moving, door.fault, motion.timeout,
				_zone_mism, overspeed, brake_bad, inp.fault_reset)

		# --- 2) position / floor tracking -------------------------------------
		cur_floor = Motion.floor_from_pos(inp.pos_mm)
		_zone_floor = -1
		for i in range(LiftCfg.TOP_FLOOR + 1):
			if inp.floor_zone[i]:
				_zone_floor = i
		_zone_mism = _zone_floor >= 0 and _zone_floor != cur_floor

		# --- 3) call registration ---------------------------------------------
		var clear_calls: bool = inp.fire_call or inp.inspection or safety.is_fault
		calls.scan(inp.calls, clear_calls,
				not inp.inspection and not safety.is_fault and not inp.fire_call)

		# --- 4) target selection ----------------------------------------------
		disp.scan(cur_floor, dir)

		# --- 5) the main state machine ----------------------------------------
		var door_req_open := false
		var door_req_close := false
		var serve_done := false

		if safety.is_fault and state != LiftIo.State.FAULT:
			state = LiftIo.State.FAULT
		elif inp.inspection and state != LiftIo.State.INSPECTION and not safety.is_fault:
			state = LiftIo.State.INSPECTION
		elif (inp.fire_call and state != LiftIo.State.FIRE
				and not safety.is_fault and not inp.inspection):
			state = LiftIo.State.FIRE

		match state:
			LiftIo.State.INIT:
				dir = LiftIo.DIR_NONE
				target_flr = -1
				if safety.run_allow:
					if inp.floor_zone[cur_floor]:
						homed = true
						state = LiftIo.State.IDLE
					else:
						state = LiftIo.State.HOMING

			LiftIo.State.HOMING:
				door_req_close = true
				if door.is_closed and inp.door_locked:
					target_flr = cur_floor
					if motion.at_target:
						homed = true
						state = LiftIo.State.ARRIVED

			LiftIo.State.IDLE:
				target_flr = -1
				_t_park.update(not calls.any_call, LiftCfg.T_PARK, dt)
				if disp.has_job:
					_t_park.reset()
					if disp.target == cur_floor:
						dir = disp.new_dir
						target_flr = cur_floor
						serve_done = true
						state = LiftIo.State.DOOR_OPENING
					else:
						dir = disp.new_dir
						target_flr = disp.target
						motion.reset_timeout()
						state = LiftIo.State.DOOR_CLOSING
				elif _t_park.q and cur_floor != LiftCfg.PARK_FLOOR:
					_t_park.reset()
					target_flr = LiftCfg.PARK_FLOOR
					dir = LiftIo.DIR_DOWN if cur_floor > LiftCfg.PARK_FLOOR else LiftIo.DIR_UP
					motion.reset_timeout()
					state = LiftIo.State.PARK

			LiftIo.State.DOOR_CLOSING:
				door_req_close = true
				# Overload inhibits the START (it does not stop a travelling car).
				if door.is_closed and inp.door_locked and not inp.overload:
					_t_start.update(true, LiftCfg.T_START_DELAY, dt)
					if _t_start.q:
						_t_start.reset()
						state = LiftIo.State.START
				else:
					_t_start.reset()
				if calls.latch.car[cur_floor] or inp.door_open_btn:
					state = LiftIo.State.DOOR_OPENING

			LiftIo.State.START:
				door_req_close = true
				if motion.brake_release and motion.speed_sp > 0:
					state = LiftIo.State.TRAVEL
				if motion.at_target:
					state = LiftIo.State.ARRIVED

			LiftIo.State.TRAVEL:
				door_req_close = true
				if _zone_floor >= 0 and _zone_floor != target_flr:
					if disp.stop_here(_zone_floor, dir):
						target_flr = _zone_floor
						motion.reset_timeout()
				if motion.leveling:
					state = LiftIo.State.LEVEL
				elif abs(motion.err_mm) < LiftCfg.DECEL_DIST_MM:
					state = LiftIo.State.DECEL

			LiftIo.State.DECEL:
				door_req_close = true
				if motion.leveling:
					state = LiftIo.State.LEVEL

			LiftIo.State.LEVEL:
				door_req_close = true
				if motion.at_target:
					state = LiftIo.State.ARRIVED

			LiftIo.State.ARRIVED:
				target_flr = -1
				serve_done = true
				# The gong is ARMED here; its duration is counted below,
				# independently of the state change (ARRIVED lasts one scan).
				_gong_arm = true
				_t_gong.reset()
				state = LiftIo.State.DOOR_OPENING

			LiftIo.State.DOOR_OPENING:
				door_req_open = true
				if door.state == LiftIo.DoorState.OPEN:
					state = LiftIo.State.DOOR_OPEN

			LiftIo.State.DOOR_OPEN:
				door_req_close = disp.has_job or door.dwell_done
				if door.state == LiftIo.DoorState.CLOSED:
					state = LiftIo.State.IDLE
					dir = disp.new_dir

			LiftIo.State.PARK:
				door_req_close = true
				if disp.has_job:
					dir = disp.new_dir
					target_flr = disp.target
					motion.reset_timeout()
					state = LiftIo.State.DOOR_CLOSING
				elif motion.at_target:
					dir = LiftIo.DIR_NONE
					state = LiftIo.State.IDLE

			LiftIo.State.FIRE:
				# Arrival at the fire recall floor is LATCHED. Otherwise, once the
				# door opens the motion block is disabled, at_target drops and
				# the controller tries to close the door again (an open/close
				# loop).
				if not _fire_parked:
					dir = LiftIo.DIR_DOWN
					target_flr = LiftCfg.FIRE_FLOOR
					door_req_close = true
					if cur_floor == LiftCfg.FIRE_FLOOR and motion.at_target:
						_fire_parked = true
				else:
					# parked at the recall floor: drive released, door stays open
					target_flr = -1
					dir = LiftIo.DIR_NONE
					door_req_open = true
				if not inp.fire_call:
					_fire_parked = false
					state = LiftIo.State.IDLE

			LiftIo.State.INSPECTION:
				target_flr = -1
				dir = LiftIo.DIR_NONE
				if not inp.inspection:
					state = LiftIo.State.INIT

			LiftIo.State.FAULT:
				target_flr = -1
				dir = LiftIo.DIR_NONE
				door_req_open = _zone_floor >= 0
				if not safety.is_fault:
					door.reset()
					motion.reset_timeout()
					state = LiftIo.State.INIT

		if serve_done:
			calls.serve_floor(cur_floor, dir)

		# --- 5b) gong and alarm bell ------------------------------------------
		# The gong is armed in ARRIVED and rings for C_T_GONG (state independent).
		if _gong_arm:
			_t_gong.update(true, LiftCfg.T_GONG, dt)
			out.gong = not _t_gong.q
			if _t_gong.q:
				_gong_arm = false
		else:
			out.gong = false

		# The alarm button is momentary; the bell keeps ringing for T_ALARM
		# after it is pressed (a TOF).
		_t_alarm.update(inp.alarm_btn, LiftCfg.T_ALARM, dt)
		out.alarm = _t_alarm.q

		# --- 6) door -----------------------------------------------------------
		var dwell: float = LiftCfg.T_DOOR_DWELL if (calls.latch.car[cur_floor] or dir == LiftIo.DIR_NONE) \
				else LiftCfg.T_DOOR_DWELL_HALL

		door.scan(not inp.estop and inp.safety_chain, door_req_open, door_req_close,
				inp.door_open_limit, inp.door_close_limit, inp.obstruction,
				inp.door_open_btn, inp.door_close_btn, inp.overload, dwell, dt)

		# --- 7) motion ---------------------------------------------------------
		# No overload check here: the start inhibit lives in DOOR_CLOSING.
		motion.scan(safety.run_allow and door.is_closed and inp.door_locked and homed,
				target_flr, inp.pos_mm, inp.top_limit, inp.bot_limit,
				inp.inspection, inp.insp_up, inp.insp_down, inp.load_kg, dt)

		# --- 8) outputs --------------------------------------------------------
		out.drive_enable = motion.drive_enable
		out.run_up = motion.run_up
		out.run_down = motion.run_down
		out.brake_release = motion.brake_release
		out.leveling = motion.leveling
		out.speed_sp_mms = motion.speed_sp
		out.pretorque_pmil = motion.pretorque_pmil

		out.door_open = door.open_out
		out.door_close = door.close_out
		out.door_nudge = door.nudge
		out.door_is_open = door.is_open
		out.door_is_closed = door.is_closed
		out.door_timer_ms = door.remain_ms

		for i in 16:
			out.lamp_up[i] = calls.latch.up[i]
			out.lamp_down[i] = calls.latch.down[i]
			out.lamp_car[i] = calls.latch.car[i]

		out.current_floor = cur_floor
		out.target_floor = target_flr
		out.direction = dir
		out.state = state
		out.fault = safety.fault
		out.moving = motion.run_up or motion.run_down
		out.overload_lamp = inp.overload
		out.fault_lamp = safety.is_fault
		out.fire_mode = state == LiftIo.State.FIRE
		out.insp_mode = state == LiftIo.State.INSPECTION
		out.out_of_service = safety.is_fault or state == LiftIo.State.INSPECTION \
				or state == LiftIo.State.FIRE
		out.cabin_light = not safety.is_fault or safety.fault != LiftIo.Fault.SAFETY_CHAIN

		_hb_acc += dt
		while _hb_acc >= 0.1:
			_hb_acc -= 0.1
			_hb = (_hb + 1) % 32001
		out.heartbeat = _hb

		return out


# =============================================================================
# PLC_PRG  -  the Modbus register <-> struct conversion
# =============================================================================
var core := LiftCore.new()
var _inp := Inputs.new()


## One PLC scan. mb_in: 16 holding registers, returns: 16 input registers.
func scan(mb_in: PackedInt32Array, dt: float) -> PackedInt32Array:
	# --- 1) inputs ---------------------------------------------------------
	var cmd := mb_in[LiftIo.IN_CMD]
	var lim := mb_in[LiftIo.IN_LIMITS]

	for i in 16:
		_inp.calls.up[i] = LiftIo.get_bit(mb_in[LiftIo.IN_HALL_UP], i)
		_inp.calls.down[i] = LiftIo.get_bit(mb_in[LiftIo.IN_HALL_DOWN], i)
		_inp.calls.car[i] = LiftIo.get_bit(mb_in[LiftIo.IN_CAR_CALL], i)
		_inp.floor_zone[i] = LiftIo.get_bit(mb_in[LiftIo.IN_FLOOR_ZONE], i)

	_inp.door_open_btn = LiftIo.get_bit(cmd, LiftIo.CMD_DOOR_OPEN)
	_inp.door_close_btn = LiftIo.get_bit(cmd, LiftIo.CMD_DOOR_CLOSE)
	_inp.alarm_btn = LiftIo.get_bit(cmd, LiftIo.CMD_ALARM)
	_inp.estop = LiftIo.get_bit(cmd, LiftIo.CMD_ESTOP)
	_inp.overload = LiftIo.get_bit(cmd, LiftIo.CMD_OVERLOAD)
	_inp.fire_call = LiftIo.get_bit(cmd, LiftIo.CMD_FIRE)
	_inp.inspection = LiftIo.get_bit(cmd, LiftIo.CMD_INSPECTION)
	_inp.fault_reset = LiftIo.get_bit(cmd, LiftIo.CMD_RESET)
	_inp.obstruction = LiftIo.get_bit(cmd, LiftIo.CMD_OBSTRUCTION)
	_inp.drive_ready = LiftIo.get_bit(cmd, LiftIo.CMD_DRIVE_READY)
	_inp.drive_fault = LiftIo.get_bit(cmd, LiftIo.CMD_DRIVE_FAULT)
	_inp.insp_up = LiftIo.get_bit(cmd, LiftIo.CMD_INSP_UP)
	_inp.insp_down = LiftIo.get_bit(cmd, LiftIo.CMD_INSP_DOWN)

	_inp.top_limit = LiftIo.get_bit(lim, LiftIo.LIM_TOP)
	_inp.bot_limit = LiftIo.get_bit(lim, LiftIo.LIM_BOTTOM)
	_inp.door_open_limit = LiftIo.get_bit(lim, LiftIo.LIM_DOOR_OPEN)
	_inp.door_close_limit = LiftIo.get_bit(lim, LiftIo.LIM_DOOR_CLOSE)
	_inp.door_locked = LiftIo.get_bit(lim, LiftIo.LIM_DOOR_LOCK)
	_inp.brake_fb = LiftIo.get_bit(lim, LiftIo.LIM_BRAKE_FB)
	_inp.safety_chain = LiftIo.get_bit(lim, LiftIo.LIM_SAFETY)
	_inp.governor_ok = LiftIo.get_bit(lim, LiftIo.LIM_GOVERNOR)

	_inp.pos_mm = mb_in[LiftIo.IN_POS_MM]
	_inp.act_speed_mms = mb_in[LiftIo.IN_SPEED_MMS]
	_inp.door_pos_pmil = mb_in[LiftIo.IN_DOOR_PMIL]
	_inp.load_kg = mb_in[LiftIo.IN_LOAD_KG]

	# --- 2) control logic --------------------------------------------------
	var o := core.scan(_inp, dt)

	# --- 3) outputs --------------------------------------------------------
	var mb_out := PackedInt32Array()
	mb_out.resize(LiftIo.REG_COUNT)

	var w := 0
	w = LiftIo.set_bit(w, LiftIo.DRV_ENABLE, o.drive_enable)
	w = LiftIo.set_bit(w, LiftIo.DRV_UP, o.run_up)
	w = LiftIo.set_bit(w, LiftIo.DRV_DOWN, o.run_down)
	w = LiftIo.set_bit(w, LiftIo.DRV_BRAKE, o.brake_release)
	w = LiftIo.set_bit(w, LiftIo.DRV_LEVELING, o.leveling)
	mb_out[LiftIo.OUT_DRIVE_CMD] = w

	w = 0
	w = LiftIo.set_bit(w, LiftIo.DOOR_OPEN_CMD, o.door_open)
	w = LiftIo.set_bit(w, LiftIo.DOOR_CLOSE_CMD, o.door_close)
	w = LiftIo.set_bit(w, LiftIo.DOOR_NUDGE_CMD, o.door_nudge)
	mb_out[LiftIo.OUT_DOOR_CMD] = w

	var wu := 0
	var wd := 0
	var wc := 0
	for i in 16:
		wu = LiftIo.set_bit(wu, i, o.lamp_up[i])
		wd = LiftIo.set_bit(wd, i, o.lamp_down[i])
		wc = LiftIo.set_bit(wc, i, o.lamp_car[i])
	mb_out[LiftIo.OUT_LAMP_UP] = wu
	mb_out[LiftIo.OUT_LAMP_DOWN] = wd
	mb_out[LiftIo.OUT_LAMP_CAR] = wc

	w = 0
	w = LiftIo.set_bit(w, LiftIo.ST_MOVING, o.moving)
	w = LiftIo.set_bit(w, LiftIo.ST_DOOR_OPEN, o.door_is_open)
	w = LiftIo.set_bit(w, LiftIo.ST_DOOR_CLOSED, o.door_is_closed)
	w = LiftIo.set_bit(w, LiftIo.ST_OVERLOAD, o.overload_lamp)
	w = LiftIo.set_bit(w, LiftIo.ST_FAULT, o.fault_lamp)
	w = LiftIo.set_bit(w, LiftIo.ST_FIRE, o.fire_mode)
	w = LiftIo.set_bit(w, LiftIo.ST_INSPECTION, o.insp_mode)
	w = LiftIo.set_bit(w, LiftIo.ST_OUT_OF_SVC, o.out_of_service)
	w = LiftIo.set_bit(w, LiftIo.ST_GONG, o.gong)
	w = LiftIo.set_bit(w, LiftIo.ST_ARROW_UP, o.direction == LiftIo.DIR_UP)
	w = LiftIo.set_bit(w, LiftIo.ST_ARROW_DOWN, o.direction == LiftIo.DIR_DOWN)
	w = LiftIo.set_bit(w, LiftIo.ST_CABIN_LIGHT, o.cabin_light)
	w = LiftIo.set_bit(w, LiftIo.ST_ALARM, o.alarm)
	mb_out[LiftIo.OUT_STATUS] = w

	mb_out[LiftIo.OUT_CUR_FLOOR] = o.current_floor
	mb_out[LiftIo.OUT_TGT_FLOOR] = o.target_floor & 0xFFFF
	mb_out[LiftIo.OUT_DIRECTION] = o.direction
	mb_out[LiftIo.OUT_SPEED_SP] = o.speed_sp_mms
	mb_out[LiftIo.OUT_STATE] = o.state
	mb_out[LiftIo.OUT_FAULT] = o.fault
	mb_out[LiftIo.OUT_HEARTBEAT] = o.heartbeat
	mb_out[LiftIo.OUT_DOOR_TIMER] = o.door_timer_ms
	mb_out[LiftIo.OUT_PRETORQUE] = o.pretorque_pmil & 0xFFFF

	return mb_out
