(*
    ============================================================================
    FB_Motion   -   Motion / speed profile / floor tracking
    ----------------------------------------------------------------------------
    Produces the drive (VVVF) reference:  direction + speed setpoint + brake.
    The profile:
        |error| >= C_DECEL_DIST_MM        -> rated speed
        C_DOOR_ZONE_MM < |error| < decel  -> SQRT distance-to-go curve
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
    iActSpeedMMS : INT;       // measured car speed
    xRescue      : BOOL;      // battery rescue run: creep speed only
    xRelevel     : BOOL;      // re-levelling at a floor, doors open
    xRelevelUp   : BOOL;      // levelling vane: car is low
    xRelevelDown : BOOL;      // levelling vane: car is high
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
    rFrac      : REAL;
    rRun       : REAL;
    iVPeak     : INT;
    iLastTarget: INT := -1;
    diRunDist  : DINT;
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
// Re-levelling: creep back to floor level with the doors still open
// ---------------------------------------------------------------------------
// This loop runs on the levelling VANES, not on the encoder. The encoder sits
// on the motor and measures rope payout; it cannot see the car hanging lower
// because the rope stretched under a load that walked in. Only a sensor on the
// car reading a plate in the shaft can.
IF xRelevel THEN
    xAtTarget := FALSE;
    tonTravel(IN := FALSE);
    xTimeout  := FALSE;

    IF xEnable AND xRelevelUp AND NOT xRelevelDown THEN
        xDriveEnable := TRUE;
        tonTorque(IN := TRUE, PT := C_T_START_DELAY);
        xBrakeRelease := tonTorque.Q;
        xRunUp := TRUE;  xRunDown := FALSE;
        iSpeedSp := C_V_LEVEL_MMS;  eDir := DIR_UP;
    ELSIF xEnable AND xRelevelDown AND NOT xRelevelUp THEN
        xDriveEnable := TRUE;
        tonTorque(IN := TRUE, PT := C_T_START_DELAY);
        xBrakeRelease := tonTorque.Q;
        xRunUp := FALSE; xRunDown := TRUE;
        iSpeedSp := C_V_LEVEL_MMS;  eDir := DIR_DOWN;
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

(* The run length is settled the moment a target is picked, so the profile can
   be sized from it. Picking up a nearer floor mid-run re-sizes it, which is
   what should happen. *)
IF iTargetFloor <> iLastTarget THEN
    iLastTarget := iTargetFloor;
    diRunDist   := diAbsErr;
END_IF

// --- has the target been reached? ------------------------------------------
// Being inside the levelling window is not enough on its own: a car crossing
// it at speed is not "arrived". Drop the drive there and the brake has to stop
// the car, which puts it well past the floor. Real controllers wait for the
// drive to report zero speed before they set the brake and call it done.
IF diAbsErr <= C_LEVEL_TOL_MM THEN
    (* Zero the reference and pick NO direction. At zero error the sign of the
       error means nothing, and asking for a direction from it drives the car
       off the floor - which is exactly what happens at the bottom, where the
       position register floors at 0 and the error can no longer go negative. *)
    xRunUp    := FALSE;
    xRunDown  := FALSE;
    iSpeedSp  := 0;
    eDir      := DIR_NONE;
    xLeveling := FALSE;
    tonTravel(IN := FALSE);

    IF ABS(iActSpeedMMS) <= C_V_ZERO_MMS THEN
        xAtTarget := TRUE;
        xMoveReq  := FALSE;
        tonTorque(IN := FALSE);
        // release the drive after the brake-apply delay
        tonBrake(IN := TRUE, PT := C_T_BRAKE);
        xBrakeRelease := NOT tonBrake.Q;
        xDriveEnable  := NOT tonBrake.Q;
    ELSE
        (* Still rolling. Hold the machine up against a zero reference and let
           it bring the car to a stand; the brake goes on after that, not
           instead of it. *)
        xAtTarget     := FALSE;
        tonBrake(IN := FALSE);
        xDriveEnable  := TRUE;
        xBrakeRelease := TRUE;
    END_IF
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
    (* The curve carries on inside the door zone rather than holding a constant
       creep. Held at C_V_LEVEL right up to the tolerance edge the car cannot
       stop inside the window - it needs about 10 mm to shed 150 mm/s and the
       window is 8 - so it sails through, reverses, and hunts. *)
    rFrac := DINT_TO_REAL(diAbsErr - C_LEVEL_TOL_MM)
             / DINT_TO_REAL(C_DOOR_ZONE_MM - C_LEVEL_TOL_MM);
    IF rFrac < 0.0 THEN
        rFrac := 0.0;
    END_IF
    iSpeedSp := REAL_TO_INT(INT_TO_REAL(C_V_LEVEL_MMS) * SQRT(rFrac));
    IF iSpeedSp < C_V_CREEP_MMS THEN
        iSpeedSp := C_V_CREEP_MMS;
    END_IF
    xLeveling := TRUE;
ELSIF diAbsErr >= C_DECEL_DIST_MM THEN
    iSpeedSp  := C_V_RATED_MMS;
    xLeveling := FALSE;
ELSE
    (* Distance-to-go curve: C_V_LEVEL at the door-zone edge, C_V_RATED at the
       decel distance. Square root, not linear, because that is the shape of
       constant deceleration - v = SQRT(2*a*s). A linear ramp asks the car to
       shed speed at a rate that keeps growing as it closes on the floor, which
       the drive cannot follow, so it arrives long. *)
    rFrac := DINT_TO_REAL(diAbsErr - C_DOOR_ZONE_MM)
             / DINT_TO_REAL(C_DECEL_DIST_MM - C_DOOR_ZONE_MM);
    IF rFrac > 1.0 THEN
        rFrac := 1.0;
    END_IF
    iSpeedSp := REAL_TO_INT(INT_TO_REAL(C_V_RATED_MMS) * SQRT(rFrac));
    IF iSpeedSp < C_V_LEVEL_MMS THEN
        iSpeedSp := C_V_LEVEL_MMS;
    END_IF
    xLeveling := FALSE;
END_IF

(* Short-run profile. A car that cannot reach rated speed AND still stop from
   it must not try - it arrives long and has to crawl back. One decel distance
   to speed up and one to slow down, so a run of twice the decel distance is
   the shortest that still justifies rated speed; anything shorter gets a
   proportionally lower peak. *)
rRun := DINT_TO_REAL(diRunDist) / DINT_TO_REAL(2 * C_DECEL_DIST_MM);
IF rRun > 1.0 THEN
    rRun := 1.0;
END_IF
iVPeak := REAL_TO_INT(INT_TO_REAL(C_V_RATED_MMS) * SQRT(rRun));
IF iVPeak < C_V_LEVEL_MMS THEN
    iVPeak := C_V_LEVEL_MMS;
END_IF
IF iSpeedSp > iVPeak THEN
    iSpeedSp := iVPeak;
END_IF

// The battery behind the rescue drive is small: it only ever moves the car at
// creep speed, and only as far as the next floor.
IF xRescue THEN
    iSpeedSp := MIN(iSpeedSp, C_V_ARD_MMS);
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
