(*
    ============================================================================
    FB_Safety   —   Guvenlik denetimi ve ariza yonetimi
    ----------------------------------------------------------------------------
    Onceligi en yuksek olan hata kodu cikar. Ariza kalicidir; reset butonu ile
    (ve hata sebebi ortadan kalkmissa) silinir.
    Godot karsiligi: SoftPlc.gd -> class Safety
    ============================================================================
*)
FUNCTION_BLOCK FB_Safety
VAR_INPUT
    xSafetyChain  : BOOL;   // TRUE = saglam
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
    xZoneMismatch : BOOL;   // encoder ile kat sensoru uyusmuyor
    xOverspeed    : BOOL;   // hiz regulatoru devreye girdi
    xBrakeMismatch: BOOL;   // fren geri beslemesi kumandayla uyusmuyor
    xReset        : BOOL;
END_VAR
VAR_OUTPUT
    eFault    : E_Fault;
    xFault    : BOOL;
    xRunAllow : BOOL;       // hareket izni
END_VAR
VAR
    xResetEdge : R_TRIG;
    tonOverspd : TON;
END_VAR

// ---------------------------------------------------------------------------
xResetEdge(CLK := xReset);

// --- Ariza tespiti (oncelik sirasiyla) -------------------------------------
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
        eFault := FLT_LOCK_LOST;       // hareket halinde kilit acildi

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
    // sebep hala duruyorsa reset kabul edilmez
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
    Regulator islevi: gercek hiz anma hizinin %115'ini (C_V_OVERSPEED_MMS)
    C_T_OVERSPEED suresince asarsa devreye girer.
    Godot karsiligi: SoftPlc.gd -> Safety.overspeed_trip()
*)
METHOD OverspeedTrip : BOOL
VAR_INPUT
    iActSpeedMMS : INT;
END_VAR

tonOverspd(IN := (iActSpeedMMS > C_V_OVERSPEED_MMS), PT := C_T_OVERSPEED);
OverspeedTrip := tonOverspd.Q;

END_METHOD
