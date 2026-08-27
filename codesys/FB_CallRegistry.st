(*
    ============================================================================
    FB_CallRegistry   -   Call latching and lamp driving
    ----------------------------------------------------------------------------
    The buttons are momentary; this block latches the call and clears it once
    it has been served.
    Godot counterpart: SoftPlc.gd -> class CallRegistry
    ============================================================================
*)
FUNCTION_BLOCK FB_CallRegistry
VAR_INPUT
    stBtn       : ST_CallSet;     // the momentary button state from the field
    xClearAll   : BOOL;           // fire / inspection / fault -> clear every call
    xEnable     : BOOL;           // if FALSE, accept no new calls
END_VAR
VAR_IN_OUT
    stLatch     : ST_CallSet;     // the latched call set (shared with the dispatcher)
END_VAR
VAR_OUTPUT
    xAnyCall    : BOOL;
    iCallCount  : INT;
END_VAR
VAR
    i : INT;
END_VAR

// ---------------------------------------------------------------------------
IF xClearAll THEN
    FOR i := 0 TO 15 DO
        stLatch.axUp[i]   := FALSE;
        stLatch.axDown[i] := FALSE;
        stLatch.axCar[i]  := FALSE;
    END_FOR
    xAnyCall   := FALSE;
    iCallCount := 0;
    RETURN;
END_IF

xAnyCall   := FALSE;
iCallCount := 0;

FOR i := 0 TO C_TOP_FLOOR DO

    // --- latch new calls -------------------------------------------------
    IF xEnable THEN
        // there is no up button on the top floor, no down on the bottom
        IF stBtn.axUp[i]   AND (i < C_TOP_FLOOR) THEN stLatch.axUp[i]   := TRUE; END_IF
        IF stBtn.axDown[i] AND (i > 0)           THEN stLatch.axDown[i] := TRUE; END_IF
        IF stBtn.axCar[i]                        THEN stLatch.axCar[i]  := TRUE; END_IF
    END_IF

    // --- count -------------------------------------------------------------
    IF stLatch.axUp[i]   THEN iCallCount := iCallCount + 1; END_IF
    IF stLatch.axDown[i] THEN iCallCount := iCallCount + 1; END_IF
    IF stLatch.axCar[i]  THEN iCallCount := iCallCount + 1; END_IF

END_FOR

xAnyCall := (iCallCount > 0);


(*
    ---------------------------------------------------------------------------
    METHOD ServeFloor : clears the calls for a floor once the car stops there.
    eDir = which direction was served (DIR_NONE clears both)
    ---------------------------------------------------------------------------
*)
METHOD ServeFloor
VAR_INPUT
    iFloor : INT;
    eDir   : E_Direction;
END_VAR

IF (iFloor < 0) OR (iFloor > C_TOP_FLOOR) THEN RETURN; END_IF

stLatch.axCar[iFloor] := FALSE;

CASE eDir OF
    DIR_UP:
        stLatch.axUp[iFloor] := FALSE;
        // if there is nothing further ahead, take the reverse call too
        IF NOT THIS^.CallAbove(iFloor) THEN
            stLatch.axDown[iFloor] := FALSE;
        END_IF

    DIR_DOWN:
        stLatch.axDown[iFloor] := FALSE;
        IF NOT THIS^.CallBelow(iFloor) THEN
            stLatch.axUp[iFloor] := FALSE;
        END_IF
ELSE
    stLatch.axUp[iFloor]   := FALSE;
    stLatch.axDown[iFloor] := FALSE;
END_CASE

END_METHOD


(*  Is there any call waiting ABOVE the given floor?  *)
METHOD CallAbove : BOOL
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR

CallAbove := FALSE;
FOR k := iFloor + 1 TO C_TOP_FLOOR DO
    IF stLatch.axUp[k] OR stLatch.axDown[k] OR stLatch.axCar[k] THEN
        CallAbove := TRUE;
        RETURN;
    END_IF
END_FOR

END_METHOD


(*  Is there any call waiting BELOW the given floor?  *)
METHOD CallBelow : BOOL
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR

CallBelow := FALSE;
FOR k := 0 TO iFloor - 1 DO
    IF stLatch.axUp[k] OR stLatch.axDown[k] OR stLatch.axCar[k] THEN
        CallBelow := TRUE;
        RETURN;
    END_IF
END_FOR

END_METHOD
