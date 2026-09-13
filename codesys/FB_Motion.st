(*
    ============================================================================
    FB_Motion   -   Motion / speed profile / floor tracking
    ----------------------------------------------------------------------------
    Produces the drive (VVVF) reference:  direction + speed setpoint + brake.
    The profile:
        |error| >= C_DECEL_DIST_MM        -> rated speed
        C_DOOR_ZONE_MM < |error| < decel  -> linear deceleration ramp
        |error| <= C_DOOR_ZONE_MM         -> levelling (creep) speed
        |error| <= C_LEVEL_TOL_MM         -> stop, apply the brake
    Godot counterpart: SoftPlc.gd -> class Motion
    ============================================================================
*)
FUNCTION_BLOCK FB_Motion
VAR_INPUT
    xEnable      : BOOL;      // permission to move (door locked + safety ok)
    iTargetFloor : INT := -1;
    diPosMM      : DINT;      // absolute encoder position
    xTopLimit    : BOOL;
    xBotLimit    : BOOL;
    xInspection  : BOOL;
    xInspUp      : BOOL;
    xInspDown    : BOOL;
    iLoadKg      : INT;       // load cell reading
END_VAR
VAR_OUTPUT
    xDriveEnable  : BOOL;
    xRunUp        : BOOL;
    xRunDown      : BOOL;
    xBrakeRelease : BOOL;
    xLeveling     : BOOL;
    iSpeedSp      : INT;
    eDir          : E_Direction;
    xAtTarget     : BOOL;
    xTimeout      : BOOL;
    diErrMM       : DINT;
    iPreTorquePmil: INT;      // pre-torque reference, per mille of the
                              // rated-load torque; + = hold the car UP
END_VAR
VAR
    diTargetMM : DINT;
    diAbsErr   : DINT;
    tonTravel  : TON;
    tonBrakeFb : TON;
    tonBrake   : TON;
    tonTorque  : TON;
    xMoveReq   : BOOL;
    diNet      : DINT;
END_VAR

// ---------------------------------------------------------------------------
// Pre-torque (load compensation)
// ---------------------------------------------------------------------------
// A gearless machine holds the car purely by friction on the sheave, so at the
// instant the brake lifts the only thing opposing the load imbalance is motor
// torque. If the drive is not already producing it, the car rolls back - down
// when it is heavy, up when it is light. Real controllers read the load cell
// and feed the drive a torque reference BEFORE the brake opens.
//
// Scaled per mille of the torque needed for a full rated-load imbalance, so
// the value stays in INT range and is independent of the machine rating.
diNet := INT_TO_DINT(C_CAR_EMPTY_KG) + INT_TO_DINT(iLoadKg) - INT_TO_DINT(C_CWT_KG);
iPreTorquePmil := DINT_TO_INT(diNet * 1000 / INT_TO_DINT(C_LOAD_FULL_KG));

// ---------------------------------------------------------------------------
// Inspection mode: no target, creep speed only while a button is held
// ---------------------------------------------------------------------------
IF xInspection THEN
    xAtTarget := FALSE;
    tonTravel(IN := FALSE);
    xTimeout  := FALSE;

    IF xEnable AND xInspUp AND NOT xInspDown AND NOT xTopLimit THEN
        xDriveEnable := TRUE;
        tonTorque(IN := TRUE, PT := C_T_START_DELAY);
        xBrakeRelease := tonTorque.Q;
        xRunUp := TRUE;  xRunDown := FALSE;
        iSpeedSp := C_V_INSPECT_MMS;  eDir := DIR_UP;
    ELSIF xEnable AND xInspDown AND NOT xInspUp AND NOT xBotLimit THEN
        xDriveEnable := TRUE;
        tonTorque(IN := TRUE, PT := C_T_START_DELAY);
        xBrakeRelease := tonTorque.Q;
        xRunUp := FALSE; xRunDown := TRUE;
        iSpeedSp := C_V_INSPECT_MMS;  eDir := DIR_DOWN;
    ELSE
        xDriveEnable := FALSE; xBrakeRelease := FALSE;
        tonTorque(IN := FALSE);
        xRunUp := FALSE; xRunDown := FALSE;
        iSpeedSp := 0;  eDir := DIR_NONE;
    END_IF
    xLeveling := TRUE;
    RETURN;
END_IF

// ---------------------------------------------------------------------------
// Normal mode
// ---------------------------------------------------------------------------
IF (iTargetFloor < 0) OR (iTargetFloor > C_TOP_FLOOR) OR NOT xEnable THEN
    xDriveEnable  := FALSE;
    xRunUp        := FALSE;
    xRunDown      := FALSE;
    xBrakeRelease := FALSE;
    xLeveling     := FALSE;
    iSpeedSp      := 0;
    eDir          := DIR_NONE;
    xAtTarget     := FALSE;
    tonTorque(IN := FALSE);
    (* The OUTPUT FLAG must be cleared along with the timer; otherwise a
       timeout that fired once sticks and the fault can never be reset. *)
    tonTravel(IN := FALSE);
    xTimeout      := FALSE;
    RETURN;
END_IF

diTargetMM := INT_TO_DINT(iTargetFloor) * C_FLOOR_HEIGHT_MM;
diErrMM    := diTargetMM - diPosMM;
diAbsErr   := ABS(diErrMM);

// --- has the target been reached? ------------------------------------------
IF diAbsErr <= C_LEVEL_TOL_MM THEN
    xAtTarget     := TRUE;
    xMoveReq      := FALSE;
    xRunUp        := FALSE;
    xRunDown      := FALSE;
    iSpeedSp      := 0;
    eDir          := DIR_NONE;
    xLeveling     := FALSE;
    tonTravel(IN := FALSE);
    tonTorque(IN := FALSE);

    // release the drive after the brake-apply delay
    tonBrake(IN := TRUE, PT := C_T_BRAKE);
    xBrakeRelease := NOT tonBrake.Q;
    xDriveEnable  := NOT tonBrake.Q;
    RETURN;
END_IF

xAtTarget := FALSE;
tonBrake(IN := FALSE);

// --- the end limits --------------------------------------------------------
IF (diErrMM > 0) AND xTopLimit THEN
    xDriveEnable := FALSE; xRunUp := FALSE; xRunDown := FALSE;
    iSpeedSp := 0; xBrakeRelease := FALSE; eDir := DIR_NONE;
    tonTorque(IN := FALSE);
    RETURN;
END_IF
IF (diErrMM < 0) AND xBotLimit THEN
    xDriveEnable := FALSE; xRunUp := FALSE; xRunDown := FALSE;
    iSpeedSp := 0; xBrakeRelease := FALSE; eDir := DIR_NONE;
    tonTorque(IN := FALSE);
    RETURN;
END_IF

// --- speed profile ---------------------------------------------------------
IF diAbsErr <= C_DOOR_ZONE_MM THEN
    iSpeedSp  := C_V_LEVEL_MMS;
    xLeveling := TRUE;
ELSIF diAbsErr >= C_DECEL_DIST_MM THEN
    iSpeedSp  := C_V_RATED_MMS;
    xLeveling := FALSE;
ELSE
    // Linear ramp:  C_V_LEVEL at the door-zone edge, C_V_RATED at the decel distance
    iSpeedSp := C_V_LEVEL_MMS
              + DINT_TO_INT( ((diAbsErr - C_DOOR_ZONE_MM)
                            * INT_TO_DINT(C_V_RATED_MMS - C_V_LEVEL_MMS))
                            / (C_DECEL_DIST_MM - C_DOOR_ZONE_MM) );
    xLeveling := FALSE;
END_IF

// --- direction and drive ---------------------------------------------------
// The drive is enabled first and the brake only opens once it has had time to
// build torque against the load. Lift the shoes before the machine is holding
// and the car drops away under its own imbalance.
xDriveEnable  := TRUE;
tonTorque(IN := TRUE, PT := C_T_START_DELAY);
xBrakeRelease := tonTorque.Q;

IF diErrMM > 0 THEN
    xRunUp := TRUE;  xRunDown := FALSE;  eDir := DIR_UP;
ELSE
    xRunUp := FALSE; xRunDown := TRUE;   eDir := DIR_DOWN;
END_IF

// --- travel timeout --------------------------------------------------------
tonTravel(IN := TRUE, PT := C_T_TRAVEL_MAX);
xTimeout := tonTravel.Q;


(*  Reset the timeout counter when a new target is given  *)
METHOD ResetTimeout
tonTravel(IN := FALSE);
xTimeout := FALSE;
END_METHOD


(*  Floor number from the encoder position (the nearest floor)  *)
METHOD FloorFromPos : INT
VAR_INPUT
    diPos : DINT;
END_VAR
VAR
    i : INT;
END_VAR

FloorFromPos := 0;
FOR i := 0 TO C_TOP_FLOOR DO
    IF ABS(diPos - (INT_TO_DINT(i) * C_FLOOR_HEIGHT_MM)) <= (C_FLOOR_HEIGHT_MM / 2) THEN
        FloorFromPos := i;
        RETURN;
    END_IF
END_FOR

IF diPos > (INT_TO_DINT(C_TOP_FLOOR) * C_FLOOR_HEIGHT_MM) THEN
    FloorFromPos := C_TOP_FLOOR;
END_IF

END_METHOD


(*
    Brake feedback supervision: the command and the field must agree.
    xBrakeCmd = brake release command, xBrakeFb = brake actually released.
    Returns TRUE if they disagree for C_T_BRAKE_FB.
    Godot counterpart: SoftPlc.gd -> Motion.brake_mismatch()
*)
METHOD BrakeMismatch : BOOL
VAR_INPUT
    xBrakeCmd : BOOL;
    xBrakeFb  : BOOL;
END_VAR

tonBrakeFb(IN := (xBrakeCmd <> xBrakeFb), PT := C_T_BRAKE_FB);
BrakeMismatch := tonBrakeFb.Q;

END_METHOD
