(*
    ============================================================================
    FB_Motion   —   Hareket / hiz profili / kat takibi
    ----------------------------------------------------------------------------
    Surucu (VVVF) referansi uretir:  yon + hiz setpoint + fren.
    Profil:
        |hata| >= C_DECEL_DIST_MM        -> nominal hiz
        C_DOOR_ZONE_MM < |hata| < decel  -> lineer yavaslama rampasi
        |hata| <= C_DOOR_ZONE_MM         -> seviyeleme (surunme) hizi
        |hata| <= C_LEVEL_TOL_MM         -> dur, fren tut
    Godot karsiligi: SoftPlc.gd -> class Motion
    ============================================================================
*)
FUNCTION_BLOCK FB_Motion
VAR_INPUT
    xEnable      : BOOL;      // hareket izni (kapi kilitli + guvenlik ok)
    iTargetFloor : INT := -1;
    diPosMM      : DINT;      // encoder mutlak konum
    xTopLimit    : BOOL;
    xBotLimit    : BOOL;
    xInspection  : BOOL;
    xInspUp      : BOOL;
    xInspDown    : BOOL;
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
END_VAR
VAR
    diTargetMM : DINT;
    diAbsErr   : DINT;
    tonTravel  : TON;
    tonBrakeFb : TON;
    tonBrake   : TON;
    xMoveReq   : BOOL;
END_VAR

// ---------------------------------------------------------------------------
// Revizyon modu: hedef yok, sadece butona basildigi surece surunme hizinda
// ---------------------------------------------------------------------------
IF xInspection THEN
    xAtTarget := FALSE;
    tonTravel(IN := FALSE);
    xTimeout  := FALSE;

    IF xEnable AND xInspUp AND NOT xInspDown AND NOT xTopLimit THEN
        xDriveEnable := TRUE; xBrakeRelease := TRUE;
        xRunUp := TRUE;  xRunDown := FALSE;
        iSpeedSp := C_V_INSPECT_MMS;  eDir := DIR_UP;
    ELSIF xEnable AND xInspDown AND NOT xInspUp AND NOT xBotLimit THEN
        xDriveEnable := TRUE; xBrakeRelease := TRUE;
        xRunUp := FALSE; xRunDown := TRUE;
        iSpeedSp := C_V_INSPECT_MMS;  eDir := DIR_DOWN;
    ELSE
        xDriveEnable := FALSE; xBrakeRelease := FALSE;
        xRunUp := FALSE; xRunDown := FALSE;
        iSpeedSp := 0;  eDir := DIR_NONE;
    END_IF
    xLeveling := TRUE;
    RETURN;
END_IF

// ---------------------------------------------------------------------------
// Normal mod
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
    (* Zamanlayici ile birlikte CIKIS BAYRAGI da temizlenmelidir; aksi halde
       bir kez olusan zaman asimi kalici kalir ve ariza reset edilemez. *)
    tonTravel(IN := FALSE);
    xTimeout      := FALSE;
    RETURN;
END_IF

diTargetMM := INT_TO_DINT(iTargetFloor) * C_FLOOR_HEIGHT_MM;
diErrMM    := diTargetMM - diPosMM;
diAbsErr   := ABS(diErrMM);

// --- hedefe varildi mi? ----------------------------------------------------
IF diAbsErr <= C_LEVEL_TOL_MM THEN
    xAtTarget     := TRUE;
    xMoveReq      := FALSE;
    xRunUp        := FALSE;
    xRunDown      := FALSE;
    iSpeedSp      := 0;
    eDir          := DIR_NONE;
    xLeveling     := FALSE;
    tonTravel(IN := FALSE);

    // fren tutma gecikmesi sonrasi surucuyu birak
    tonBrake(IN := TRUE, PT := C_T_BRAKE);
    xBrakeRelease := NOT tonBrake.Q;
    xDriveEnable  := NOT tonBrake.Q;
    RETURN;
END_IF

xAtTarget := FALSE;
tonBrake(IN := FALSE);

// --- ucdaki limitler -------------------------------------------------------
IF (diErrMM > 0) AND xTopLimit THEN
    xDriveEnable := FALSE; xRunUp := FALSE; xRunDown := FALSE;
    iSpeedSp := 0; xBrakeRelease := FALSE; eDir := DIR_NONE;
    RETURN;
END_IF
IF (diErrMM < 0) AND xBotLimit THEN
    xDriveEnable := FALSE; xRunUp := FALSE; xRunDown := FALSE;
    iSpeedSp := 0; xBrakeRelease := FALSE; eDir := DIR_NONE;
    RETURN;
END_IF

// --- hiz profili -----------------------------------------------------------
IF diAbsErr <= C_DOOR_ZONE_MM THEN
    iSpeedSp  := C_V_LEVEL_MMS;
    xLeveling := TRUE;
ELSIF diAbsErr >= C_DECEL_DIST_MM THEN
    iSpeedSp  := C_V_RATED_MMS;
    xLeveling := FALSE;
ELSE
    // Lineer rampa:  door-zone kenarinda C_V_LEVEL, decel mesafesinde C_V_RATED
    iSpeedSp := C_V_LEVEL_MMS
              + DINT_TO_INT( ((diAbsErr - C_DOOR_ZONE_MM)
                            * INT_TO_DINT(C_V_RATED_MMS - C_V_LEVEL_MMS))
                            / (C_DECEL_DIST_MM - C_DOOR_ZONE_MM) );
    xLeveling := FALSE;
END_IF

// --- yon ve surucu ---------------------------------------------------------
xDriveEnable  := TRUE;
xBrakeRelease := TRUE;

IF diErrMM > 0 THEN
    xRunUp := TRUE;  xRunDown := FALSE;  eDir := DIR_UP;
ELSE
    xRunUp := FALSE; xRunDown := TRUE;   eDir := DIR_DOWN;
END_IF

// --- hareket zaman asimi ---------------------------------------------------
tonTravel(IN := TRUE, PT := C_T_TRAVEL_MAX);
xTimeout := tonTravel.Q;


(*  Yeni hedef verildiginde zaman asimi sayacini sifirla  *)
METHOD ResetTimeout
tonTravel(IN := FALSE);
xTimeout := FALSE;
END_METHOD


(*  Encoder konumundan kat numarasi (en yakin kat)  *)
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
    Fren geri beslemesi denetimi: kumanda ile saha uyusmali.
    xBrakeCmd = fren coz komutu, xBrakeFb = fren gercekten cozuldu sinyali.
    Uyusmazlik C_T_BRAKE_FB suresince surerse TRUE doner.
    Godot karsiligi: SoftPlc.gd -> Motion.brake_mismatch()
*)
METHOD BrakeMismatch : BOOL
VAR_INPUT
    xBrakeCmd : BOOL;
    xBrakeFb  : BOOL;
END_VAR

tonBrakeFb(IN := (xBrakeCmd <> xBrakeFb), PT := C_T_BRAKE_FB);
BrakeMismatch := tonBrakeFb.Q;

END_METHOD
