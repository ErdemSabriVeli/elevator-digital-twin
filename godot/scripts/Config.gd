class_name LiftCfg
extends RefCounted

## Plant parameters.
##
## UPPER SECTION (SHARED WITH THE PLC): must match the values in
## codesys/GVL_Config.st exactly. Change one and you must change the other,
## otherwise the digital twin behaves differently from the real PLC.
##
## LOWER SECTION: only concerns the 3D / physics side; it has no counterpart
## in the PLC.

# =============================================================================
# SHARED WITH THE PLC  (GVL_Config.st)
# =============================================================================
const FLOOR_COUNT        := 6         # 0 = ground ... 5 = top floor
const TOP_FLOOR          := 5
const FLOOR_HEIGHT_MM    := 3200
const DOOR_ZONE_MM       := 60
const LEVEL_TOL_MM       := 8
const OVERTRAVEL_MM      := 400

const V_RATED_MMS        := 1600
const V_LEVEL_MMS        := 150
const V_INSPECT_MMS      := 300
const DECEL_DIST_MM      := 2000

const T_DOOR_DWELL       := 4.0       # s
const T_DOOR_DWELL_HALL  := 3.0
const T_DOOR_MOVE_MAX    := 8.0
const T_TRAVEL_MAX       := 25.0
const T_NUDGE            := 15.0
const T_GONG             := 0.6
const T_PARK             := 30.0
const T_BRAKE            := 0.3
const T_START_DELAY      := 0.2
const T_ALARM            := 2.0       # how long the bell rings after a press
const T_BRAKE_FB         := 1.0       # brake feedback supervision window
const T_OVERSPEED        := 0.3       # overspeed confirmation time
const V_OVERSPEED_MMS    := 1840      # governor trip speed (115 %)

const PARK_FLOOR         := 0
const FIRE_FLOOR         := 0
const LOAD_FULL_KG       := 630
const LOAD_OVER_KG       := 693

# Masses. The counterweight balances the empty car plus HALF the rated load
# (a 50 % balance factor, the usual choice). So the machine only ever has to
# hold the difference, and that difference reverses sign as the car fills:
# an empty car is lighter than the counterweight, a full one is heavier.
const CAR_EMPTY_KG       := 1200      # empty car: cabin + sling + doors
const CWT_KG             := 1515      # = CAR_EMPTY_KG + 0.5 * LOAD_FULL_KG

# =============================================================================
# SIMULATION ONLY (plant model)
# =============================================================================
const ACCEL_MMS2         := 900.0     # drive acceleration limit
const DECEL_MMS2         := 1100.0
const JERK_MMS3          := 1300.0    # rate of change of acceleration (S-curve)
const DOOR_OPEN_TIME     := 2.0       # time to open fully [s]
const DOOR_CLOSE_TIME    := 2.4
const DOOR_NUDGE_SCALE   := 0.45      # speed factor while nudging
const BTN_PULSE_S        := 0.25      # momentary button pulse width
const ENC_NOISE_MM       := 0.0       # optional encoder noise
const G_MMS2             := 9810.0    # gravity
const ROT_INERTIA        := 1.10      # sheave + motor inertia, as a factor on
                                      # the moving mass
const T_TORQUE_RAMP      := 0.25      # time for the drive to build pre-torque

# =============================================================================
# 3D GEOMETRY  [metres]
# =============================================================================
const M_FLOOR_H     := 3.2            # = FLOOR_HEIGHT_MM / 1000
const M_SHAFT_W     := 2.50           # shaft inner width (X)
const M_SHAFT_D     := 2.30           # shaft inner depth (Z)
const M_WALL_T      := 0.16
const M_PIT_DEPTH   := 1.40
# Shaft head: refuge space for the traction machine, the deflector sheave and
# the car-top guard rail. 4-5 m is typical in real MRL installations.
const M_HEADROOM    := 5.00

const M_CAR_W       := 2.00
const M_CAR_D       := 1.70
const M_CAR_H       := 2.30
const M_CAR_FLOOR_T := 0.10

const M_DOOR_W      := 1.00           # total door opening width
const M_DOOR_H      := 2.10
const M_DOOR_T      := 0.05

const M_HALL_W      := 5.00           # landing width
const M_HALL_D      := 4.00           # landing depth (+Z direction)
const M_SLAB_T      := 0.28

const M_CWT_W       := 1.10           # counterweight width (X)
const M_CWT_D       := 0.22           # thickness (Z)
const M_CWT_H       := 1.60
const M_CWT_Z       := -1.02          # between the shaft rear wall and the car

# --- Suspension system (1:1 roping, with a deflector sheave) ----------------
const M_ROPE_R      := 0.008          # steel rope radius (~16 mm diameter)
const ROPE_COUNT    := 5              # number of parallel ropes
const ROPE_PITCH    := 0.036          # rope spacing (groove pitch)
const M_SHEAVE_R    := 0.32           # traction sheave radius
const M_DEFLECT_R   := 0.19           # deflector sheave radius
const M_DEFLECT_DY  := 0.30           # deflector drop below the sheave
const M_CARTOP_RAIL := 0.75           # car-top guard rail height

# Rope lines:  car at z = 0 (above the car centre),
# counterweight at z = M_CWT_Z.  The traction sheave separates them by 2R.
const M_ROPE_Z_CAR  := 0.0
const M_GOV_ROPE_Z  := -0.55          # governor rope in the rear shaft corner
const M_GOV_R       := 0.17           # governor sheave radius

# Floor number -> world Y (car floor level)
static func floor_y(f: int) -> float:
	return float(f) * M_FLOOR_H

static func mm_to_m(mm: float) -> float:
	return mm * 0.001

static func total_height() -> float:
	return float(TOP_FLOOR) * M_FLOOR_H + M_HEADROOM
