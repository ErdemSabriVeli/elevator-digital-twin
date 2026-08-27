(*
    ============================================================================
    FB_Safety   -   Safety supervision and fault handling
    ----------------------------------------------------------------------------
    The highest-priority fault code wins. A fault latches; it is cleared by the
    reset button (and only once its cause has gone).
    Godot counterpart: SoftPlc.gd -> class Safety
    ============================================================================
*)
FUNCTION_BLOCK FB_Safety
VAR_INPUT
    xSafetyChain  : BOOL;   // TRUE = intact
    xGovernorOk   : BOOL;
    xEStop        : BOOL;
    xDriveReady   : BOOL;
    xDriveFault   : BOOL;
    xTopLimit     : BOOL;
    xBotLimit     : BOOL;
    xDoorLocked   : BOOL;
    xMoving       : BOOL;
    xDoorTimeout  : BOOL;
    xTravelTimeout: BOOL;
    xZoneMismatch : BOOL;   // encoder and floor sensor disagree
    xOverspeed    : BOOL;   // the overspeed governor tripped
    xBrakeMismatch: BOOL;   // brake feedback disagrees with the command
    xReset        : BOOL;
END_VAR
VAR_OUTPUT
    eFault    : E_Fault;
    xFault    : BOOL;
    xRunAllow : BOOL;       // permission to move
END_VAR
VAR
    xResetEdge : R_TRIG;
    tonOverspd : TON;
END_VAR

// ---------------------------------------------------------------------------
xResetEdge(CLK := xReset);

// --- Fault detection (in priority order) -----------------------------------
IF eFault = FLT_NONE THEN

    IF xEStop THEN
        eFault := FLT_ESTOP;

    ELSIF NOT xSafetyChain OR NOT xGovernorOk THEN
        eFault := FLT_SAFETY_CHAIN;

    ELSIF xOverspeed THEN
        eFault := FLT_OVERSPEED;

    ELSIF xDriveFault OR NOT xDriveReady THEN
        eFault := FLT_DRIVE;

    ELSIF xBrakeMismatch THEN
        eFault := FLT_BRAKE;

    ELSIF xTopLimit OR xBotLimit THEN
        eFault := FLT_LIMIT;

    ELSIF xMoving AND NOT xDoorLocked THEN
        eFault := FLT_LOCK_LOST;       // the lock opened while moving

    ELSIF xTravelTimeout THEN
        eFault := FLT_TRAVEL_TIMEOUT;

    ELSIF xDoorTimeout THEN
        eFault := FLT_DOOR_TIMEOUT;

    ELSIF xZoneMismatch THEN
        eFault := FLT_ENCODER;
    END_IF

END_IF

// --- Reset ------------------------------------------------------------------
IF xResetEdge.Q THEN
    // a reset is refused while the cause is still present
    IF NOT xEStop
       AND xSafetyChain AND xGovernorOk
       AND xDriveReady AND NOT xDriveFault
       AND NOT xTopLimit AND NOT xBotLimit THEN
        eFault := FLT_NONE;
    END_IF
END_IF

xFault    := (eFault <> FLT_NONE);

xRunAllow := NOT xFault
             AND xSafetyChain AND xGovernorOk
             AND xDriveReady AND NOT xDriveFault
             AND NOT xEStop;


(*
    Governor function: it trips when the actual speed exceeds 115% of rated
    (C_V_OVERSPEED_MMS) for C_T_OVERSPEED.
    Godot counterpart: SoftPlc.gd -> Safety.overspeed_trip()
*)
METHOD OverspeedTrip : BOOL
VAR_INPUT
    iActSpeedMMS : INT;
END_VAR

tonOverspd(IN := (iActSpeedMMS > C_V_OVERSPEED_MMS), PT := C_T_OVERSPEED);
OverspeedTrip := tonOverspd.Q;

END_METHOD
