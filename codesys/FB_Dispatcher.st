(*
    ============================================================================
    FB_Dispatcher   -   Target floor selection  (collective control)
    ----------------------------------------------------------------------------
    The rule:
      * While the car travels one way it collects every call in that direction.
      * When there is nothing left that way it reverses.
      * When idle it picks a direction from the nearest call.
    Godot counterpart: SoftPlc.gd -> class Dispatcher
    ============================================================================
*)
FUNCTION_BLOCK FB_Dispatcher
VAR_INPUT
    iCurrentFloor : INT;
    eCurDir       : E_Direction;   // the current direction of service
    xBypassHall   : BOOL;          // car is full: serve car calls only
END_VAR
VAR_IN_OUT
    stLatch : ST_CallSet;
END_VAR
VAR_OUTPUT
    iTarget  : INT := -1;
    eNewDir  : E_Direction := DIR_NONE;
    xHasJob  : BOOL;
END_VAR
VAR
    iBest : INT;
END_VAR

// ---------------------------------------------------------------------------
xHasJob := FALSE;
iTarget := -1;
eNewDir := eCurDir;

// 1) Can we keep going the current way?
IF eCurDir = DIR_UP THEN
    iBest := THIS^.NearestAbove(iCurrentFloor);
    IF iBest >= 0 THEN
        iTarget := iBest;  eNewDir := DIR_UP;  xHasJob := TRUE;
        RETURN;
    END_IF
    // nothing above -> reverse downwards
    iBest := THIS^.FarthestBelow(iCurrentFloor);
    IF iBest >= 0 THEN
        iTarget := THIS^.NearestBelow(iCurrentFloor);
        eNewDir := DIR_DOWN;  xHasJob := TRUE;
        RETURN;
    END_IF

ELSIF eCurDir = DIR_DOWN THEN
    iBest := THIS^.NearestBelow(iCurrentFloor);
    IF iBest >= 0 THEN
        iTarget := iBest;  eNewDir := DIR_DOWN;  xHasJob := TRUE;
        RETURN;
    END_IF
    iBest := THIS^.FarthestAbove(iCurrentFloor);
    IF iBest >= 0 THEN
        iTarget := THIS^.NearestAbove(iCurrentFloor);
        eNewDir := DIR_UP;  xHasJob := TRUE;
        RETURN;
    END_IF
END_IF

// 2) Idle: is there a call at this floor?
IF THIS^.CallAtFloor(iCurrentFloor) THEN
    iTarget := iCurrentFloor;
    eNewDir := DIR_NONE;
    xHasJob := TRUE;
    RETURN;
END_IF

// 3) Idle: pick the nearest call
iBest := THIS^.NearestAny(iCurrentFloor);
IF iBest >= 0 THEN
    iTarget := iBest;
    xHasJob := TRUE;
    IF iBest > iCurrentFloor THEN
        eNewDir := DIR_UP;
    ELSIF iBest < iCurrentFloor THEN
        eNewDir := DIR_DOWN;
    ELSE
        eNewDir := DIR_NONE;
    END_IF
ELSE
    eNewDir := DIR_NONE;
END_IF


(*  Should we stop at this floor on the way?  (asked while travelling)  *)
METHOD StopHere : BOOL
VAR_INPUT
    iFloor : INT;
    eDir   : E_Direction;
END_VAR

StopHere := FALSE;
IF (iFloor < 0) OR (iFloor > C_TOP_FLOOR) THEN RETURN; END_IF

// An in-car call always stops the lift
IF stLatch.axCar[iFloor] THEN
    StopHere := TRUE;
    RETURN;
END_IF

(* A full car drives past landings. The calls stay registered and lit - someone
   still wants to travel - this car just is not the one that can take them. *)
IF xBypassHall THEN
    RETURN;
END_IF

CASE eDir OF
    DIR_UP:
        IF stLatch.axUp[iFloor] THEN
            StopHere := TRUE;
        ELSIF stLatch.axDown[iFloor] AND NOT THIS^.AnyAbove(iFloor) THEN
            StopHere := TRUE;   // topmost call: stop for the reverse too
        END_IF

    DIR_DOWN:
        IF stLatch.axDown[iFloor] THEN
            StopHere := TRUE;
        ELSIF stLatch.axUp[iFloor] AND NOT THIS^.AnyBelow(iFloor) THEN
            StopHere := TRUE;
        END_IF
ELSE
    StopHere := THIS^.CallAtFloor(iFloor);
END_CASE

END_METHOD


METHOD CallAtFloor : BOOL
VAR_INPUT
    iFloor : INT;
END_VAR
IF (iFloor < 0) OR (iFloor > C_TOP_FLOOR) THEN
    CallAtFloor := FALSE;
ELSIF xBypassHall THEN
    (* Full car: landing calls are invisible to the search, so the dispatcher
       will not even pick one as a target. *)
    CallAtFloor := stLatch.axCar[iFloor];
ELSE
    CallAtFloor := stLatch.axUp[iFloor] OR stLatch.axDown[iFloor] OR stLatch.axCar[iFloor];
END_IF
END_METHOD


METHOD AnyAbove : BOOL
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR
AnyAbove := FALSE;
FOR k := iFloor + 1 TO C_TOP_FLOOR DO
    IF THIS^.CallAtFloor(k) THEN AnyAbove := TRUE; RETURN; END_IF
END_FOR
END_METHOD


METHOD AnyBelow : BOOL
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR
AnyBelow := FALSE;
FOR k := 0 TO iFloor - 1 DO
    IF THIS^.CallAtFloor(k) THEN AnyBelow := TRUE; RETURN; END_IF
END_FOR
END_METHOD


METHOD NearestAbove : INT
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR
NearestAbove := -1;
FOR k := iFloor + 1 TO C_TOP_FLOOR DO
    IF THIS^.CallAtFloor(k) THEN NearestAbove := k; RETURN; END_IF
END_FOR
END_METHOD


METHOD NearestBelow : INT
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR
NearestBelow := -1;
FOR k := iFloor - 1 TO 0 BY -1 DO
    IF THIS^.CallAtFloor(k) THEN NearestBelow := k; RETURN; END_IF
END_FOR
END_METHOD


METHOD FarthestAbove : INT
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR
FarthestAbove := -1;
FOR k := C_TOP_FLOOR TO iFloor + 1 BY -1 DO
    IF THIS^.CallAtFloor(k) THEN FarthestAbove := k; RETURN; END_IF
END_FOR
END_METHOD


METHOD FarthestBelow : INT
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    k : INT;
END_VAR
FarthestBelow := -1;
FOR k := 0 TO iFloor - 1 DO
    IF THIS^.CallAtFloor(k) THEN FarthestBelow := k; RETURN; END_IF
END_FOR
END_METHOD


(*  The nearest call, in either direction  *)
METHOD NearestAny : INT
VAR_INPUT
    iFloor : INT;
END_VAR
VAR
    d, iUp, iDn : INT;
END_VAR

NearestAny := -1;
iUp := THIS^.NearestAbove(iFloor);
iDn := THIS^.NearestBelow(iFloor);

IF (iUp < 0) AND (iDn < 0) THEN
    RETURN;
ELSIF iUp < 0 THEN
    NearestAny := iDn;
ELSIF iDn < 0 THEN
    NearestAny := iUp;
ELSE
    d := (iUp - iFloor) - (iFloor - iDn);
    IF d <= 0 THEN
        NearestAny := iUp;    // up wins a tie
    ELSE
        NearestAny := iDn;
    END_IF
END_IF

END_METHOD
