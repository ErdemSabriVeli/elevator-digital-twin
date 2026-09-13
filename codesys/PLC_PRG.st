(*
    ============================================================================
    PLC_PRG   -   Main program (Task: 10 ms cyclic recommended)
    ----------------------------------------------------------------------------
    Flow:
        1) Modbus Holding Registers -> ST_LiftInputs            (Godot -> PLC)
        2) FB_LiftCore                                          (control logic)
        3) ST_LiftOutputs -> Modbus Input Registers             (PLC -> Godot)
        4) Twin connection supervision (heartbeat)

    For the register map see the GVL_IO.st header or docs/io-map.md.
    ============================================================================
*)
PROGRAM PLC_PRG
VAR
    fbLift  : FB_LiftCore;

    i       : INT;
    wTmp    : WORD;
    wCmd    : WORD;
    wLim    : WORD;

    // Twin (Godot) connection supervision
    tonTwinLost : TON;
    iHbPrev     : INT;

    // Manual test flags (can be forced from the CODESYS watch window)
    xForceOffline : BOOL;
END_VAR

// ===========================================================================
// 1) INPUTS:  Modbus Holding Registers -> ST_LiftInputs
// ===========================================================================
wCmd := GVL_IO.g_awMbIn[3];
wLim := GVL_IO.g_awMbIn[5];

FOR i := 0 TO 15 DO
    GVL_IO.g_stIn.stCalls.axUp[i]   := F_GetBit(GVL_IO.g_awMbIn[0], i);
    GVL_IO.g_stIn.stCalls.axDown[i] := F_GetBit(GVL_IO.g_awMbIn[1], i);
    GVL_IO.g_stIn.stCalls.axCar[i]  := F_GetBit(GVL_IO.g_awMbIn[2], i);
    GVL_IO.g_stIn.axFloorZone[i]    := F_GetBit(GVL_IO.g_awMbIn[4], i);
END_FOR

// CMD_BITS
GVL_IO.g_stIn.xDoorOpenBtn  := F_GetBit(wCmd,  0);
GVL_IO.g_stIn.xDoorCloseBtn := F_GetBit(wCmd,  1);
GVL_IO.g_stIn.xAlarmBtn     := F_GetBit(wCmd,  2);
GVL_IO.g_stIn.xEStop        := F_GetBit(wCmd,  3);
GVL_IO.g_stIn.xOverload     := F_GetBit(wCmd,  4);
GVL_IO.g_stIn.xFireCall     := F_GetBit(wCmd,  5);
GVL_IO.g_stIn.xInspection   := F_GetBit(wCmd,  6);
GVL_IO.g_stIn.xFaultReset   := F_GetBit(wCmd,  7);
GVL_IO.g_stIn.xObstruction  := F_GetBit(wCmd,  8);
GVL_IO.g_stIn.xDriveReady   := F_GetBit(wCmd,  9);
GVL_IO.g_stIn.xDriveFault   := F_GetBit(wCmd, 10);
GVL_IO.g_stIn.xInspUp       := F_GetBit(wCmd, 11);
GVL_IO.g_stIn.xInspDown     := F_GetBit(wCmd, 12);

// LIMIT_BITS
GVL_IO.g_stIn.xTopLimit       := F_GetBit(wLim, 0);
GVL_IO.g_stIn.xBotLimit       := F_GetBit(wLim, 1);
GVL_IO.g_stIn.xDoorOpenLimit  := F_GetBit(wLim, 2);
GVL_IO.g_stIn.xDoorCloseLimit := F_GetBit(wLim, 3);
GVL_IO.g_stIn.xDoorLocked     := F_GetBit(wLim, 4);
GVL_IO.g_stIn.xBrakeFb        := F_GetBit(wLim, 5);
GVL_IO.g_stIn.xSafetyChain    := F_GetBit(wLim, 6);
GVL_IO.g_stIn.xGovernorOk     := F_GetBit(wLim, 7);
GVL_IO.g_stIn.xSafetyGear     := F_GetBit(wLim, 8);
GVL_IO.g_stIn.xMainsOk        := F_GetBit(wLim, 9);
GVL_IO.g_stIn.xRelevelUp      := F_GetBit(wLim, 10);
GVL_IO.g_stIn.xRelevelDown    := F_GetBit(wLim, 11);

// Analogue values
(* Signed: the car really can sit below the bottom floor, in the pit, and a
   controller that cannot see that drives itself into the buffer. WORD_TO_INT
   reinterprets the register as a signed millimetre count. *)
GVL_IO.g_stIn.diPosMM      := INT_TO_DINT(WORD_TO_INT(GVL_IO.g_awMbIn[6]));
GVL_IO.g_stIn.iActSpeedMMS := WORD_TO_INT(GVL_IO.g_awMbIn[7]);
GVL_IO.g_stIn.iDoorPosPmil := WORD_TO_INT(GVL_IO.g_awMbIn[8]);
GVL_IO.g_stIn.iLoadKg      := WORD_TO_INT(GVL_IO.g_awMbIn[9]);

// ---------------------------------------------------------------------------
// Twin connection supervision: if the heartbeat has not changed for 2 s the
// simulation is gone. The safety chain is then treated as "open" and the
// elevator does not move.
// ---------------------------------------------------------------------------
IF WORD_TO_INT(GVL_IO.g_awMbIn[10]) <> iHbPrev THEN
    iHbPrev := WORD_TO_INT(GVL_IO.g_awMbIn[10]);
    tonTwinLost(IN := FALSE);
    GVL_IO.g_xTwinOnline := TRUE;
END_IF
tonTwinLost(IN := TRUE, PT := T#2S);
IF tonTwinLost.Q OR xForceOffline THEN
    GVL_IO.g_xTwinOnline := FALSE;
END_IF

IF NOT GVL_IO.g_xTwinOnline THEN
    GVL_IO.g_stIn.xSafetyChain := FALSE;
END_IF

// ===========================================================================
// 2) CONTROL LOGIC
// ===========================================================================
fbLift(stIn := GVL_IO.g_stIn);
GVL_IO.g_stOut := fbLift.stOut;

// ===========================================================================
// 3) OUTPUTS:  ST_LiftOutputs -> Modbus Input Registers
// ===========================================================================

// DRIVE_CMD
wTmp := 0;
wTmp := F_SetBit(wTmp, 0, GVL_IO.g_stOut.xDriveEnable);
wTmp := F_SetBit(wTmp, 1, GVL_IO.g_stOut.xRunUp);
wTmp := F_SetBit(wTmp, 2, GVL_IO.g_stOut.xRunDown);
wTmp := F_SetBit(wTmp, 3, GVL_IO.g_stOut.xBrakeRelease);
wTmp := F_SetBit(wTmp, 4, GVL_IO.g_stOut.xLeveling);
GVL_IO.g_awMbOut[0] := wTmp;

// DOOR_CMD
wTmp := 0;
wTmp := F_SetBit(wTmp, 0, GVL_IO.g_stOut.xDoorOpen);
wTmp := F_SetBit(wTmp, 1, GVL_IO.g_stOut.xDoorClose);
wTmp := F_SetBit(wTmp, 2, GVL_IO.g_stOut.xDoorNudge);
GVL_IO.g_awMbOut[1] := wTmp;

// Lamps
wTmp := 0;
FOR i := 0 TO 15 DO wTmp := F_SetBit(wTmp, i, GVL_IO.g_stOut.axLampUp[i]); END_FOR
GVL_IO.g_awMbOut[2] := wTmp;

wTmp := 0;
FOR i := 0 TO 15 DO wTmp := F_SetBit(wTmp, i, GVL_IO.g_stOut.axLampDown[i]); END_FOR
GVL_IO.g_awMbOut[3] := wTmp;

wTmp := 0;
FOR i := 0 TO 15 DO wTmp := F_SetBit(wTmp, i, GVL_IO.g_stOut.axLampCar[i]); END_FOR
GVL_IO.g_awMbOut[4] := wTmp;

// STATUS_BITS
wTmp := 0;
wTmp := F_SetBit(wTmp,  0, GVL_IO.g_stOut.xMoving);
wTmp := F_SetBit(wTmp,  1, GVL_IO.g_stOut.xDoorIsOpen);
wTmp := F_SetBit(wTmp,  2, GVL_IO.g_stOut.xDoorIsClosed);
wTmp := F_SetBit(wTmp,  3, GVL_IO.g_stOut.xOverloadLamp);
wTmp := F_SetBit(wTmp,  4, GVL_IO.g_stOut.xFaultLamp);
wTmp := F_SetBit(wTmp,  5, GVL_IO.g_stOut.xFireMode);
wTmp := F_SetBit(wTmp,  6, GVL_IO.g_stOut.xInspMode);
wTmp := F_SetBit(wTmp,  7, GVL_IO.g_stOut.xOutOfService);
wTmp := F_SetBit(wTmp,  8, GVL_IO.g_stOut.xGong);
wTmp := F_SetBit(wTmp,  9, GVL_IO.g_stOut.eDirection = DIR_UP);
wTmp := F_SetBit(wTmp, 10, GVL_IO.g_stOut.eDirection = DIR_DOWN);
wTmp := F_SetBit(wTmp, 11, GVL_IO.g_stOut.xCabinLight);
wTmp := F_SetBit(wTmp, 12, GVL_IO.g_stOut.xAlarm);
wTmp := F_SetBit(wTmp, 13, GVL_IO.g_stOut.xRescue);
wTmp := F_SetBit(wTmp, 14, GVL_IO.g_stOut.xRelevel);
GVL_IO.g_awMbOut[5] := wTmp;

GVL_IO.g_awMbOut[6]  := INT_TO_WORD(GVL_IO.g_stOut.iCurrentFloor);
GVL_IO.g_awMbOut[7]  := INT_TO_WORD(GVL_IO.g_stOut.iTargetFloor);
GVL_IO.g_awMbOut[8]  := INT_TO_WORD(GVL_IO.g_stOut.eDirection);
GVL_IO.g_awMbOut[9]  := INT_TO_WORD(GVL_IO.g_stOut.iSpeedSpMMS);
GVL_IO.g_awMbOut[10] := INT_TO_WORD(GVL_IO.g_stOut.eState);
GVL_IO.g_awMbOut[11] := INT_TO_WORD(GVL_IO.g_stOut.eFault);
GVL_IO.g_awMbOut[12] := INT_TO_WORD(GVL_IO.g_stOut.iHeartbeat);
GVL_IO.g_awMbOut[13] := INT_TO_WORD(GVL_IO.g_stOut.iDoorTimerMs);
GVL_IO.g_awMbOut[14] := INT_TO_WORD(GVL_IO.g_stOut.iPreTorquePmil);
