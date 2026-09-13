(*
    ============================================================================
    FB_LiftCore   -   THE MAIN STATE MACHINE
    ----------------------------------------------------------------------------
    Orchestrates the sub-blocks:
        FB_Safety        safety / faults
        FB_CallRegistry  call latching + lamps
        FB_Dispatcher    target floor selection
        FB_DoorCtrl      door
        FB_Motion        drive reference

    The normal state flow:
        INIT -> HOMING -> IDLE -> DOOR_CLOSING -> START -> TRAVEL -> DECEL
             -> LEVEL -> ARRIVED -> DOOR_OPENING -> DOOR_OPEN -> IDLE ...

    Godot counterpart: SoftPlc.gd -> class LiftCore   (exactly the same
    transitions)
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
    // --- sub-blocks ---------------------------------------------------------
    fbSafety : FB_Safety;
    fbCalls  : FB_CallRegistry;
    fbDisp   : FB_Dispatcher;
    fbDoor   : FB_DoorCtrl;
    fbMotion : FB_Motion;

    // --- retained data ------------------------------------------------------
    stLatch     : ST_CallSet;
    eState      : E_LiftState := LS_INIT;
    eDir        : E_Direction := DIR_NONE;
    iCurFloor   : INT := 0;
    iTargetFlr  : INT := -1;
    xHomed      : BOOL;

    // --- helpers ------------------------------------------------------------
    tonPark     : TON;
    tonGong     : TON;
    tonStart    : TON;
    tonHb       : TON;
    tofAlarm    : TOF;
    xGongArm    : BOOL;
    xFireParked : BOOL;   // reached the recall floor (the fire mode latch)
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
// 1) SAFETY
// ---------------------------------------------------------------------------
// The governor (overspeed) and the brake feedback supervision: both compare a
// measurement from the field against the command.
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
// 2) POSITION / FLOOR TRACKING
// ===========================================================================
iCurFloor := fbMotion.FloorFromPos(stIn.diPosMM);

// Floor sensor vs encoder consistency check (inside the door zone only)
iZoneFloor := -1;
FOR i := 0 TO C_TOP_FLOOR DO
    IF stIn.axFloorZone[i] THEN iZoneFloor := i; END_IF
END_FOR
xZoneMism := (iZoneFloor >= 0) AND (iZoneFloor <> iCurFloor);

// ===========================================================================
// 3) CALL REGISTRATION
// ===========================================================================
xClearCalls := stIn.xFireCall OR stIn.xInspection OR fbSafety.xFault;

fbCalls(
    stBtn     := stIn.stCalls,
    xClearAll := xClearCalls,
    xEnable   := NOT stIn.xInspection AND NOT fbSafety.xFault AND NOT stIn.xFireCall,
    stLatch   := stLatch
);

// ===========================================================================
// 4) TARGET SELECTION
// ===========================================================================
fbDisp(
    iCurrentFloor := iCurFloor,
    eCurDir       := eDir,
    stLatch       := stLatch
);

// ===========================================================================
// 5) THE MAIN STATE MACHINE
// ===========================================================================
xDoorReqOpen := FALSE;
xDoorReqCls  := FALSE;
xServeDone   := FALSE;

// --- globally prioritised transitions --------------------------------------
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
    // Position unknown: creep to the nearest floor
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
                // a call at this floor -> open the door
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
        // Overload inhibits the START (it does not stop a travelling car).
        IF fbDoor.xIsClosed AND stIn.xDoorLocked AND NOT stIn.xOverload THEN
            tonStart(IN := TRUE, PT := C_T_START_DELAY);
            IF tonStart.Q THEN
                tonStart(IN := FALSE);
                eState := LS_START;
            END_IF
        ELSE
            tonStart(IN := FALSE);
        END_IF
        // reopen if a new call arrives for this floor while closing
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

        // Decide on an intermediate stop (before entering the door zone)
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
        // The gong is ARMED here; its duration is counted below independently
        // of the state change (LS_ARRIVED lasts a single scan only).
        xGongArm := TRUE;
        tonGong(IN := FALSE);

        // Clear the calls for this floor and open the door
        eState := LS_DOOR_OPENING;

    // -----------------------------------------------------------------------
    LS_DOOR_OPENING:
        xDoorReqOpen := TRUE;
        IF fbDoor.eState = DS_OPEN THEN
            eState := LS_DOOR_OPEN;
        END_IF

    // -----------------------------------------------------------------------
    LS_DOOR_OPEN:
        // Allow closing if there is new work
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
    // Fire scenario: every call is cleared, the car travels to the recall
    // floor, the door opens and stays open.
    LS_FIRE:
        (* Arrival at the recall floor is LATCHED. Otherwise, once the door
           opens the motion block is disabled, xAtTarget drops and the
           controller tries to close the door again (an open/close loop). *)
        IF NOT xFireParked THEN
            eDir        := DIR_DOWN;
            iTargetFlr  := C_FIRE_FLOOR;
            xDoorReqCls := TRUE;
            IF (iCurFloor = C_FIRE_FLOOR) AND fbMotion.xAtTarget THEN
                xFireParked := TRUE;
            END_IF
        ELSE
            (* parked at the recall floor: drive released, door stays open *)
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
        // open the door if the car is in a door zone (to let people out)
        xDoorReqOpen := (iZoneFloor >= 0);
        IF NOT fbSafety.xFault THEN
            fbDoor.Reset();
            fbMotion.ResetTimeout();
            eState := LS_INIT;
        END_IF

END_CASE

// --- clear the calls on arrival --------------------------------------------
IF xServeDone THEN
    fbCalls.ServeFloor(iCurFloor, eDir);
END_IF

// ===========================================================================
// 5b) GONG AND ALARM BELL
// ===========================================================================
// The gong is armed in LS_ARRIVED and rings for C_T_GONG (state independent).
IF xGongArm THEN
    tonGong(IN := TRUE, PT := C_T_GONG);
    stOut.xGong := NOT tonGong.Q;
    IF tonGong.Q THEN
        xGongArm := FALSE;
    END_IF
ELSE
    stOut.xGong := FALSE;
END_IF

// The alarm button is momentary; the bell keeps ringing for C_T_ALARM after
// it is pressed (TOF = off delay).
tofAlarm(IN := stIn.xAlarmBtn, PT := C_T_ALARM);
stOut.xAlarm := tofAlarm.Q;

// ===========================================================================
// 6) DOOR
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
// 7) MOTION
// ===========================================================================
(*
    No overload check here: the load signal is a start inhibit
    (LS_DOOR_CLOSING); it must not suddenly stop a travelling car.
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
    xInspDown    := stIn.xInspDown,
    iLoadKg      := stIn.iLoadKg
);

// ===========================================================================
// 8) OUTPUTS
// ===========================================================================
stOut.xDriveEnable  := fbMotion.xDriveEnable;
stOut.xRunUp        := fbMotion.xRunUp;
stOut.xRunDown      := fbMotion.xRunDown;
stOut.xBrakeRelease := fbMotion.xBrakeRelease;
stOut.xLeveling     := fbMotion.xLeveling;
stOut.iSpeedSpMMS   := fbMotion.iSpeedSp;
stOut.iPreTorquePmil := fbMotion.iPreTorquePmil;

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

// Heartbeat: increments every 100 ms
tonHb(IN := NOT tonHb.Q, PT := T#100MS);
IF tonHb.Q THEN
    iHb := iHb + 1;
    IF iHb > 32000 THEN iHb := 0; END_IF
END_IF
stOut.iHeartbeat := iHb;
