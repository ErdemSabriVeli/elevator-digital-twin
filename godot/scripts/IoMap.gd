class_name LiftIo
extends RefCounted

## Modbus register map — must match codesys/GVL_IO.st exactly.
##
## IN  = Godot -> PLC   (Holding Registers, master write, PLC %IW)
## OUT = PLC -> Godot   (Input Registers,   master read,  PLC %QW)

const REG_COUNT := 16

# =============================================================================
# Godot -> PLC   (Holding Registers)
# =============================================================================
const IN_HALL_UP      := 0     # bit n = UP call button on floor n
const IN_HALL_DOWN    := 1
const IN_CAR_CALL     := 2
const IN_CMD          := 3
const IN_FLOOR_ZONE   := 4
const IN_LIMITS       := 5
const IN_POS_MM       := 6
const IN_SPEED_MMS    := 7
const IN_DOOR_PMIL    := 8
const IN_LOAD_KG      := 9
const IN_HEARTBEAT    := 10

# IN_CMD bits
const CMD_DOOR_OPEN   := 0
const CMD_DOOR_CLOSE  := 1
const CMD_ALARM       := 2
const CMD_ESTOP       := 3
const CMD_OVERLOAD    := 4
const CMD_FIRE        := 5
const CMD_INSPECTION  := 6
const CMD_RESET       := 7
const CMD_OBSTRUCTION := 8
const CMD_DRIVE_READY := 9
const CMD_DRIVE_FAULT := 10
const CMD_INSP_UP     := 11
const CMD_INSP_DOWN   := 12
const CMD_INDEPENDENT := 13    # attendant key switch in the car
const CMD_FIRE_PH2    := 14    # firefighter key switch in the car

# IN_LIMITS bits
const LIM_TOP         := 0
const LIM_BOTTOM      := 1
const LIM_DOOR_OPEN   := 2
const LIM_DOOR_CLOSE  := 3
const LIM_DOOR_LOCK   := 4
const LIM_BRAKE_FB    := 5
const LIM_SAFETY      := 6
const LIM_GOVERNOR    := 7
const LIM_SAFETY_GEAR := 8     # wedges gripping the guide rails
const LIM_MAINS_OK    := 9     # mains supply healthy
# Levelling vanes on the car, read against the shaft plates. Separate from the
# encoder on purpose: the encoder is on the motor and measures rope payout, so
# it cannot see the car hanging lower on a stretched rope.
const LIM_RELEVEL_UP  := 10    # car is BELOW floor level -> creep up
const LIM_RELEVEL_DN  := 11    # car is ABOVE floor level -> creep down
const LIM_NTS_TOP     := 12    # terminal slowdown cam, top end
const LIM_NTS_BOT     := 13    # terminal slowdown cam, bottom end
const LIM_DOOR_STALL  := 14    # door operator stalled at its force limit

# =============================================================================
# PLC -> Godot   (Input Registers)
# =============================================================================
const OUT_DRIVE_CMD   := 0
const OUT_DOOR_CMD    := 1
const OUT_LAMP_UP     := 2
const OUT_LAMP_DOWN   := 3
const OUT_LAMP_CAR    := 4
const OUT_STATUS      := 5
const OUT_CUR_FLOOR   := 6
const OUT_TGT_FLOOR   := 7
const OUT_DIRECTION   := 8
const OUT_SPEED_SP    := 9
const OUT_STATE       := 10
const OUT_FAULT       := 11
const OUT_HEARTBEAT   := 12
const OUT_DOOR_TIMER  := 13
const OUT_PRETORQUE   := 14    # signed, per mille of the rated-load torque

# OUT_DRIVE_CMD bits
const DRV_ENABLE      := 0
const DRV_UP          := 1
const DRV_DOWN        := 2
const DRV_BRAKE       := 3
const DRV_LEVELING    := 4

# OUT_DOOR_CMD bits
const DOOR_OPEN_CMD   := 0
const DOOR_CLOSE_CMD  := 1
const DOOR_NUDGE_CMD  := 2

# OUT_STATUS bits
const ST_MOVING       := 0
const ST_DOOR_OPEN    := 1
const ST_DOOR_CLOSED  := 2
const ST_OVERLOAD     := 3
const ST_FAULT        := 4
const ST_FIRE         := 5
const ST_INSPECTION   := 6
const ST_OUT_OF_SVC   := 7
const ST_GONG         := 8
const ST_ARROW_UP     := 9
const ST_ARROW_DOWN   := 10
const ST_CABIN_LIGHT  := 11
const ST_ALARM        := 12
const ST_RESCUE       := 13    # running on the battery rescue drive
const ST_RELEVEL      := 14    # re-levelling at the floor, doors open
const ST_INDEPENDENT  := 15    # independent (attendant) service

# =============================================================================
# Enums  (DUT_Types.st)
# =============================================================================
const DIR_NONE := 0
const DIR_UP   := 1
const DIR_DOWN := 2

enum State {
	INIT = 0, HOMING = 1, IDLE = 2, DOOR_OPENING = 3, DOOR_OPEN = 4,
	DOOR_CLOSING = 5, START = 6, TRAVEL = 7, DECEL = 8, LEVEL = 9,
	ARRIVED = 10, FAULT = 11, FIRE = 12, INSPECTION = 13, PARK = 14,
	RESCUE = 15, RELEVEL = 16, FIRE_PH2 = 17
}

enum DoorState { CLOSED = 0, OPENING = 1, OPEN = 2, CLOSING = 3, REOPEN = 4, FAULT = 5 }

enum Fault {
	NONE = 0, SAFETY_CHAIN = 1, DOOR_TIMEOUT = 2, TRAVEL_TIMEOUT = 3,
	DRIVE = 4, LIMIT = 5, ENCODER = 6, LOCK_LOST = 7, ESTOP = 8,
	BRAKE = 9, OVERSPEED = 10, SAFETY_GEAR = 11
}

const STATE_TEXT := {
	0: "INIT", 1: "HOMING", 2: "IDLE", 3: "DOOR OPENING", 4: "DOOR OPEN",
	5: "DOOR CLOSING", 6: "START", 7: "TRAVEL", 8: "DECEL",
	9: "LEVELLING", 10: "ARRIVED", 11: "FAULT", 12: "FIRE",
	13: "INSPECTION", 14: "PARK", 15: "RESCUE (ARD)", 16: "RE-LEVELLING",
	17: "FIREFIGHTER PHASE II"
}

const FAULT_TEXT := {
	0: "-", 1: "Safety chain open", 2: "Door timeout",
	3: "Travel timeout", 4: "Drive fault", 5: "Limit switch",
	6: "Encoder / floor sensor mismatch", 7: "Door lock lost",
	8: "Emergency stop", 9: "Brake feedback mismatch",
	10: "OVERSPEED - governor tripped",
	11: "SAFETY GEAR SET - manual release needed"
}

const DIR_TEXT := { 0: "-", 1: "UP", 2: "DOWN" }

# =============================================================================
# Bit helpers  (FUN_Bits.st)
# =============================================================================
static func get_bit(val: int, bit: int) -> bool:
	if bit < 0 or bit > 15:
		return false
	return (val & (1 << bit)) != 0

static func set_bit(val: int, bit: int, on: bool) -> int:
	if bit < 0 or bit > 15:
		return val
	if on:
		return val | (1 << bit)
	return val & ~(1 << bit)

## Modbus carries WORDs; a signed field comes back as two.s complement.
static func to_signed(w: int) -> int:
	w &= 0xFFFF
	return w - 65536 if w >= 32768 else w


static func floor_name(f: int) -> String:
	if f == 0:
		return "G"
	return str(f)
