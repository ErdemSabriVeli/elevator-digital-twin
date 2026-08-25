(*
    ============================================================================
    FB_LiftCore   —   ANA DURUM MAKINESI
    ----------------------------------------------------------------------------
    Alt bloklari orkestra eder:
        FB_Safety        guvenlik / ariza
        FB_CallRegistry  cagri latch + lambalar
        FB_Dispatcher    hedef kat secimi
        FB_DoorCtrl      kapi
        FB_Motion        surucu referansi

    Durum akisi (normal):
        INIT -> HOMING -> IDLE -> DOOR_CLOSING -> START -> TRAVEL -> DECEL
             -> LEVEL -> ARRIVED -> DOOR_OPENING -> DOOR_OPEN -> IDLE ...

    Godot karsiligi: SoftPlc.gd -> class LiftCore   (birebir ayni gecisler)
    ============================================================================
*)
FUNCTION_BLOCK FB_LiftCore
VAR_INPUT
    stIn : ST_LiftInputs;
END_VAR
VAR_OUTPUT
    stOut : ST_LiftOutputs;
END_VAR
VAR
    // --- alt bloklar --------------------------------------------------------
    fbSafety : FB_Safety;
    fbCalls  : FB_CallRegistry;
    fbDisp   : FB_Dispatcher;
    fbDoor   : FB_DoorCtrl;
    fbMotion : FB_Motion;

    // --- kalici veri --------------------------------------------------------
    stLatch     : ST_CallSet;
    eState      : E_LiftState := LS_INIT;
    eDir        : E_Direction := DIR_NONE;
    iCurFloor   : INT := 0;
    iTargetFlr  : INT := -1;
    xHomed      : BOOL;

    // --- yardimcilar --------------------------------------------------------
    tonPark     : TON;
    tonGong     : TON;
    tonStart    : TON;
    tonHb       : TON;
    tofAlarm    : TOF;
    xGongArm    : BOOL;
    xFireParked : BOOL;   // tahliye katina varildi (yangin modu mandali)
    xOverspeed  : BOOL;
    xBrakeBad   : BOOL;
    iHb         : INT;
    xZoneMism   : BOOL;
    xDoorReqOpen: BOOL;
    xDoorReqCls : BOOL;
    xClearCalls : BOOL;
    xServeDone  : BOOL;
    i           : INT;
    iZoneFloor  : INT;
    tDwellUse   : TIME;
END_VAR

// ===========================================================================
// 1) GUVENLIK
// ---------------------------------------------------------------------------
// Regulator (asiri hiz) ve fren geri besleme denetimi: her ikisi de sahadan
// gelen olcumu kumanda ile karsilastirir.
// ===========================================================================
xOverspeed := fbSafety.OverspeedTrip(stIn.iActSpeedMMS);
xBrakeBad  := fbMotion.BrakeMismatch(stOut.xBrakeRelease, stIn.xBrakeFb);

fbSafety(
    xSafetyChain   := stIn.xSafetyChain,
    xGovernorOk    := stIn.xGovernorOk,
    xEStop         := stIn.xEStop,
    xDriveReady    := stIn.xDriveReady,
    xDriveFault    := stIn.xDriveFault,
    xTopLimit      := stIn.xTopLimit,
    xBotLimit      := stIn.xBotLimit,
    xDoorLocked    := stIn.xDoorLocked,
    xMoving        := stOut.xMoving,
    xDoorTimeout   := fbDoor.xFault,
    xTravelTimeout := fbMotion.xTimeout,
    xZoneMismatch  := xZoneMism,
    xOverspeed     := xOverspeed,
    xBrakeMismatch := xBrakeBad,
    xReset         := stIn.xFaultReset
);

// ===========================================================================
// 2) KONUM / KAT TAKIBI
// ===========================================================================
iCurFloor := fbMotion.FloorFromPos(stIn.diPosMM);

// Kat sensoru ile encoder tutarlilik kontrolu (sadece door-zone icinde)
iZoneFloor := -1;
FOR i := 0 TO C_TOP_FLOOR DO
    IF stIn.axFloorZone[i] THEN iZoneFloor := i; END_IF
END_FOR
xZoneMism := (iZoneFloor >= 0) AND (iZoneFloor <> iCurFloor);

// ===========================================================================
// 3) CAGRI KAYDI
// ===========================================================================
xClearCalls := stIn.xFireCall OR stIn.xInspection OR fbSafety.xFault;

fbCalls(
    stBtn     := stIn.stCalls,
    xClearAll := xClearCalls,
    xEnable   := NOT stIn.xInspection AND NOT fbSafety.xFault AND NOT stIn.xFireCall,
    stLatch   := stLatch
);

// ===========================================================================
// 4) HEDEF SECIMI
// ===========================================================================
fbDisp(
    iCurrentFloor := iCurFloor,
    eCurDir       := eDir,
    stLatch       := stLatch
);

// ===========================================================================
// 5) ANA DURUM MAKINESI
// ===========================================================================
xDoorReqOpen := FALSE;
xDoorReqCls  := FALSE;
xServeDone   := FALSE;

// --- global oncelikli gecisler ---------------------------------------------
IF fbSafety.xFault AND (eState <> LS_FAULT) THEN
    eState := LS_FAULT;
ELSIF stIn.xInspection AND (eState <> LS_INSPECTION) AND NOT fbSafety.xFault THEN
    eState := LS_INSPECTION;
ELSIF stIn.xFireCall AND (eState <> LS_FIRE) AND NOT fbSafety.xFault
      AND NOT stIn.xInspection THEN
    eState := LS_FIRE;
END_IF

CASE eState OF

    // -----------------------------------------------------------------------
    LS_INIT:
        eDir       := DIR_NONE;
        iTargetFlr := -1;
        IF fbSafety.xRunAllow THEN
            IF stIn.axFloorZone[iCurFloor] THEN
                xHomed := TRUE;
                eState := LS_IDLE;
            ELSE
                eState := LS_HOMING;
            END_IF
        END_IF

    // -----------------------------------------------------------------------
    // Konum bilinmiyor: en yakin kata surunme hiziyla git
    LS_HOMING:
        xDoorReqCls := TRUE;
        IF fbDoor.xIsClosed AND stIn.xDoorLocked THEN
            iTargetFlr := iCurFloor;
            IF fbMotion.xAtTarget THEN
                xHomed := TRUE;
                eState := LS_ARRIVED;
            END_IF
        END_IF

    // -----------------------------------------------------------------------
    LS_IDLE:
        iTargetFlr := -1;
        tonPark(IN := NOT fbCalls.xAnyCall, PT := C_T_PARK);

        IF fbDisp.xHasJob THEN
            tonPark(IN := FALSE);
            IF fbDisp.iTarget = iCurFloor THEN
                // ayni katta cagri -> kapiyi ac
                eDir       := fbDisp.eNewDir;
                iTargetFlr := iCurFloor;
                xServeDone := TRUE;
                eState     := LS_DOOR_OPENING;
            ELSE
                eDir       := fbDisp.eNewDir;
                iTargetFlr := fbDisp.iTarget;
                fbMotion.ResetTimeout();
                eState     := LS_DOOR_CLOSING;
            END_IF

        ELSIF tonPark.Q AND (iCurFloor <> C_PARK_FLOOR) THEN
            tonPark(IN := FALSE);
            iTargetFlr := C_PARK_FLOOR;
            IF iCurFloor > C_PARK_FLOOR THEN eDir := DIR_DOWN; ELSE eDir := DIR_UP; END_IF
            fbMotion.ResetTimeout();
            eState := LS_PARK;
        END_IF

    // -----------------------------------------------------------------------
    LS_DOOR_CLOSING:
        xDoorReqCls := TRUE;
        // Asiri yuk KALKISI engeller (seyir halindeki kabini durdurmaz).
        IF fbDoor.xIsClosed AND stIn.xDoorLocked AND NOT stIn.xOverload THEN
            tonStart(IN := TRUE, PT := C_T_START_DELAY);
            IF tonStart.Q THEN
                tonStart(IN := FALSE);
                eState := LS_START;
            END_IF
        ELSE
            tonStart(IN := FALSE);
        END_IF
        // kapanma sirasinda yeni bir cagri ayni kattan gelirse geri ac
        IF stLatch.axCar[iCurFloor] OR stIn.xDoorOpenBtn THEN
            eState := LS_DOOR_OPENING;
        END_IF

    // -----------------------------------------------------------------------
    LS_START:
        xDoorReqCls := TRUE;
        IF fbMotion.xBrakeRelease AND (fbMotion.iSpeedSp > 0) THEN
            eState := LS_TRAVEL;
        END_IF
        IF fbMotion.xAtTarget THEN
            eState := LS_ARRIVED;
        END_IF

    // -----------------------------------------------------------------------
    LS_TRAVEL:
        xDoorReqCls := TRUE;

        // Yol uzerindeki kata ugrama karari (door-zone'a girmeden once verilir)
        IF (iZoneFloor >= 0) AND (iZoneFloor <> iTargetFlr) THEN
            IF fbDisp.StopHere(iZoneFloor, eDir) THEN
                iTargetFlr := iZoneFloor;
                fbMotion.ResetTimeout();
            END_IF
        END_IF

        IF fbMotion.xLeveling THEN
            eState := LS_LEVEL;
        ELSIF ABS(fbMotion.diErrMM) < C_DECEL_DIST_MM THEN
            eState := LS_DECEL;
        END_IF

    // -----------------------------------------------------------------------
    LS_DECEL:
        xDoorReqCls := TRUE;
        IF fbMotion.xLeveling THEN
            eState := LS_LEVEL;
        END_IF

    // -----------------------------------------------------------------------
    LS_LEVEL:
        xDoorReqCls := TRUE;
        IF fbMotion.xAtTarget THEN
            eState := LS_ARRIVED;
        END_IF

    // -----------------------------------------------------------------------
    LS_ARRIVED:
        iTargetFlr := -1;
        xServeDone := TRUE;
        // Gong burada KURULUR; calma suresi durum degisiminden bagimsiz
        // olarak asagida sayilir (LS_ARRIVED yalnizca tek tarama surer).
        xGongArm := TRUE;
        tonGong(IN := FALSE);

        // Bu kat icin cagrilari sil ve kapiyi ac
        eState := LS_DOOR_OPENING;

    // -----------------------------------------------------------------------
    LS_DOOR_OPENING:
        xDoorReqOpen := TRUE;
        IF fbDoor.eState = DS_OPEN THEN
            eState := LS_DOOR_OPEN;
        END_IF

    // -----------------------------------------------------------------------
    LS_DOOR_OPEN:
        // Yeni is varsa kapanmaya izin ver
        xDoorReqCls := fbDisp.xHasJob OR fbDoor.xDwellDone;
        IF fbDoor.eState = DS_CLOSED THEN
            eState := LS_IDLE;
            eDir   := fbDisp.eNewDir;
        END_IF

    // -----------------------------------------------------------------------
    LS_PARK:
        xDoorReqCls := TRUE;
        IF fbDisp.xHasJob THEN
            eDir       := fbDisp.eNewDir;
            iTargetFlr := fbDisp.iTarget;
            fbMotion.ResetTimeout();
            eState     := LS_DOOR_CLOSING;
        ELSIF fbMotion.xAtTarget THEN
            eDir   := DIR_NONE;
            eState := LS_IDLE;
        END_IF

    // -----------------------------------------------------------------------
    // Yangin senaryosu: tum cagrilar silinir, tahliye katina inilir,
    // kapi acilir ve acik kalir.
    LS_FIRE:
        (* Tahliye katina varis MANDALLANIR. Aksi halde kapi acilinca hareket
           blogu devre disi kalir, xAtTarget duser ve kumanda kapiyi yeniden
           kapatmaya calisir (ac-kapa dongusu olusur). *)
        IF NOT xFireParked THEN
            eDir        := DIR_DOWN;
            iTargetFlr  := C_FIRE_FLOOR;
            xDoorReqCls := TRUE;
            IF (iCurFloor = C_FIRE_FLOOR) AND fbMotion.xAtTarget THEN
                xFireParked := TRUE;
            END_IF
        ELSE
            (* tahliye katinda park: surucu serbest, kapi acik kalir *)
            iTargetFlr   := -1;
            eDir         := DIR_NONE;
            xDoorReqOpen := TRUE;
        END_IF

        IF NOT stIn.xFireCall THEN
            xFireParked := FALSE;
            eState := LS_IDLE;
        END_IF

    // -----------------------------------------------------------------------
    LS_INSPECTION:
        iTargetFlr := -1;
        eDir       := DIR_NONE;
        IF NOT stIn.xInspection THEN
            eState := LS_INIT;
        END_IF

    // -----------------------------------------------------------------------
    LS_FAULT:
        iTargetFlr := -1;
        eDir       := DIR_NONE;
        // kabin door-zone icindeyse kapiyi ac (yolcu tahliyesi)
        xDoorReqOpen := (iZoneFloor >= 0);
        IF NOT fbSafety.xFault THEN
            fbDoor.Reset();
            fbMotion.ResetTimeout();
            eState := LS_INIT;
        END_IF

END_CASE

// --- kata varinca cagrilari sil --------------------------------------------
IF xServeDone THEN
    fbCalls.ServeFloor(iCurFloor, eDir);
END_IF

// ===========================================================================
// 5b) GONG VE ALARM ZILI
// ===========================================================================
// Gong LS_ARRIVED'de kurulur, C_T_GONG boyunca calar (durumdan bagimsiz).
IF xGongArm THEN
    tonGong(IN := TRUE, PT := C_T_GONG);
    stOut.xGong := NOT tonGong.Q;
    IF tonGong.Q THEN
        xGongArm := FALSE;
    END_IF
ELSE
    stOut.xGong := FALSE;
END_IF

// Alarm butonu anlik (momentary) gelir; zil basildiktan sonra C_T_ALARM
// suresince calmaya devam eder (TOF = kapanma gecikmesi).
tofAlarm(IN := stIn.xAlarmBtn, PT := C_T_ALARM);
stOut.xAlarm := tofAlarm.Q;

// ===========================================================================
// 6) KAPI
// ===========================================================================
IF stLatch.axCar[iCurFloor] OR (eDir = DIR_NONE) THEN
    tDwellUse := C_T_DOOR_DWELL;
ELSE
    tDwellUse := C_T_DOOR_DWELL_HALL;
END_IF

fbDoor(
    xEnable      := NOT stIn.xEStop AND stIn.xSafetyChain,
    xReqOpen     := xDoorReqOpen,
    xReqClose    := xDoorReqCls,
    xOpenLimit   := stIn.xDoorOpenLimit,
    xCloseLimit  := stIn.xDoorCloseLimit,
    xObstruction := stIn.xObstruction,
    xOpenBtn     := stIn.xDoorOpenBtn,
    xCloseBtn    := stIn.xDoorCloseBtn,
    xOverload    := stIn.xOverload,
    tDwell       := tDwellUse
);

// ===========================================================================
// 7) HAREKET
// ===========================================================================
(*
    Asiri yuk burada YOK: yuk sinyali kalkis kilididir (LS_DOOR_CLOSING),
    seyir halindeki kabini aniden durdurmamalidir.
*)
fbMotion(
    xEnable      := fbSafety.xRunAllow
                    AND fbDoor.xIsClosed
                    AND stIn.xDoorLocked
                    AND xHomed,
    iTargetFloor := iTargetFlr,
    diPosMM      := stIn.diPosMM,
    xTopLimit    := stIn.xTopLimit,
    xBotLimit    := stIn.xBotLimit,
    xInspection  := stIn.xInspection,
    xInspUp      := stIn.xInspUp,
    xInspDown    := stIn.xInspDown
);

// ===========================================================================
// 8) CIKISLAR
// ===========================================================================
stOut.xDriveEnable  := fbMotion.xDriveEnable;
stOut.xRunUp        := fbMotion.xRunUp;
stOut.xRunDown      := fbMotion.xRunDown;
stOut.xBrakeRelease := fbMotion.xBrakeRelease;
stOut.xLeveling     := fbMotion.xLeveling;
stOut.iSpeedSpMMS   := fbMotion.iSpeedSp;

stOut.xDoorOpen     := fbDoor.xOpenOut;
stOut.xDoorClose    := fbDoor.xCloseOut;
stOut.xDoorNudge    := fbDoor.xNudge;
stOut.xDoorIsOpen   := fbDoor.xIsOpen;
stOut.xDoorIsClosed := fbDoor.xIsClosed;
stOut.iDoorTimerMs  := fbDoor.iRemainMs;

FOR i := 0 TO 15 DO
    stOut.axLampUp[i]   := stLatch.axUp[i];
    stOut.axLampDown[i] := stLatch.axDown[i];
    stOut.axLampCar[i]  := stLatch.axCar[i];
END_FOR

stOut.iCurrentFloor := iCurFloor;
stOut.iTargetFloor  := iTargetFlr;
stOut.eDirection    := eDir;
stOut.eState        := eState;
stOut.eFault        := fbSafety.eFault;
stOut.xMoving       := fbMotion.xRunUp OR fbMotion.xRunDown;
stOut.xOverloadLamp := stIn.xOverload;
stOut.xFaultLamp    := fbSafety.xFault;
stOut.xFireMode     := (eState = LS_FIRE);
stOut.xInspMode     := (eState = LS_INSPECTION);
stOut.xOutOfService := fbSafety.xFault OR (eState = LS_INSPECTION) OR (eState = LS_FIRE);
stOut.xCabinLight   := NOT fbSafety.xFault OR (fbSafety.eFault <> FLT_SAFETY_CHAIN);

// Heartbeat: 100 ms'de bir artar
tonHb(IN := NOT tonHb.Q, PT := T#100MS);
IF tonHb.Q THEN
    iHb := iHb + 1;
    IF iHb > 32000 THEN iHb := 0; END_IF
END_IF
stOut.iHeartbeat := iHb;
