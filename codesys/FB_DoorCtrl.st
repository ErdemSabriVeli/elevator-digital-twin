(*
    ============================================================================
    FB_DoorCtrl   -   The door sub state machine
    ----------------------------------------------------------------------------
    The car door and the landing door are driven together (coupler logic).
    The light curtain, the door-open button and an overload all reopen it.
    Past C_T_NUDGE the "nudge" (slow forced closing) mode takes over.
    Godot counterpart: SoftPlc.gd -> class DoorCtrl
    ============================================================================
*)
FUNCTION_BLOCK FB_DoorCtrl
VAR_INPUT
    xEnable       : BOOL;    // FALSE -> door motors released (fault/estop)
    xReqOpen      : BOOL;    // from above: open the door and hold it open
    xReqClose     : BOOL;    // from above: close the door (we are about to move)
    xOpenLimit    : BOOL;
    xCloseLimit   : BOOL;
    xObstruction  : BOOL;    // the light curtain is broken
    xOpenBtn      : BOOL;
    xCloseBtn     : BOOL;
    xOverload     : BOOL;
    xDoorZone     : BOOL;    // car is inside the unlocking zone
    xConstPress   : BOOL;    // firefighter mode: the buttons must be HELD
    tDwell        : TIME := T#4S;
END_VAR
VAR_OUTPUT
    xOpenOut   : BOOL;
    xCloseOut  : BOOL;
    xNudge     : BOOL;
    xIsOpen    : BOOL;
    xIsClosed  : BOOL;
    xDwellDone : BOOL;       // the dwell has expired, ready to close
    xFault     : BOOL;
    eState     : E_DoorState;
    iRemainMs  : INT;
END_VAR
VAR
    tonDwell  : TON;
    tonMove   : TON;         // movement timeout
    tonNudge  : TON;         // standing at the door too long
    tRemain   : TIME;
END_VAR

// ---------------------------------------------------------------------------
// Default outputs
xOpenOut   := FALSE;
xCloseOut  := FALSE;
xIsOpen    := xOpenLimit;
xIsClosed  := xCloseLimit;
xDwellDone := FALSE;

IF NOT xEnable THEN
    eState := DS_CLOSED;
    tonDwell(IN := FALSE);
    tonMove(IN := FALSE);
    tonNudge(IN := FALSE);
    xNudge := FALSE;
    iRemainMs := 0;
    RETURN;
END_IF

// ---------------------------------------------------------------------------
CASE eState OF

    // -----------------------------------------------------------------------
    DS_CLOSED:
        tonDwell(IN := FALSE);
        tonNudge(IN := FALSE);
        xNudge := FALSE;
        (* Outside the unlocking zone the doors stay shut, however hard the
           button is leaned on. The coupler vane on the car door only engages
           the landing door rollers inside the zone - a stranded car cannot
           open onto the shaft wall, and that is not a policy but a mechanism.
           EN 81-20 5.3.9. *)
        IF (xReqOpen OR xOpenBtn) AND xDoorZone THEN
            eState := DS_OPENING;
        ELSIF NOT xCloseLimit AND xReqClose THEN
            eState := DS_CLOSING;      // not fully closed, try again
        END_IF

    // -----------------------------------------------------------------------
    DS_OPENING:
        xOpenOut := TRUE;
        tonMove(IN := TRUE, PT := C_T_DOOR_MOVE_MAX);
        (* Under constant pressure the door only travels while the button is
           held. Let go half way and it goes straight back - the firefighter
           keeps a hand on it so the door can never be left open on a floor
           they have not chosen to be on. EN 81-72. *)
        IF xConstPress AND NOT xOpenBtn AND NOT xOpenLimit THEN
            tonMove(IN := FALSE);
            eState := DS_CLOSING;
        ELSIF xOpenLimit THEN
            tonMove(IN := FALSE);
            eState := DS_OPEN;
        ELSIF tonMove.Q THEN
            tonMove(IN := FALSE);
            xFault := TRUE;
            eState := DS_FAULT;
        END_IF

    // -----------------------------------------------------------------------
    DS_OPEN:
        // Dwell: the timer resets while an obstruction / overload / open button is present
        tonDwell(IN := NOT (xObstruction OR xOverload OR xOpenBtn OR xReqOpen),
                 PT := tDwell);
        tonNudge(IN := TRUE, PT := C_T_NUDGE);
        xNudge := tonNudge.Q;

        tRemain   := tDwell - tonDwell.ET;
        iRemainMs := TIME_TO_INT(tRemain);

        xDwellDone := tonDwell.Q;

        (* Under constant pressure nothing shuts the door but the button. *)
        IF xConstPress THEN
            IF xCloseBtn THEN
                eState := DS_CLOSING;
                tonDwell(IN := FALSE);
            END_IF
        // The close button skips the dwell (if nothing is in the way)
        ELSIF xCloseBtn AND NOT xObstruction AND NOT xOverload AND NOT xReqOpen THEN
            eState := DS_CLOSING;
            tonDwell(IN := FALSE);
        ELSIF tonDwell.Q AND xReqClose THEN
            eState := DS_CLOSING;
            tonDwell(IN := FALSE);
        ELSIF xNudge AND xReqClose THEN
            eState := DS_CLOSING;      // forced closing
            tonDwell(IN := FALSE);
        END_IF

    // -----------------------------------------------------------------------
    DS_CLOSING:
        xCloseOut := TRUE;
        tonMove(IN := TRUE, PT := C_T_DOOR_MOVE_MAX);
        iRemainMs := 0;

        (* Under constant pressure the door closes only while the button is
           held, and NOTHING else reopens it - not the light curtain, not an
           overload. A firefighter may have to close on smoke or debris, which
           is exactly the case the curtain would otherwise veto. *)
        IF xConstPress THEN
            IF NOT xCloseBtn AND NOT xCloseLimit THEN
                tonMove(IN := FALSE);
                eState := DS_REOPEN;
            ELSIF xCloseLimit THEN
                tonMove(IN := FALSE);
                tonNudge(IN := FALSE);
                xNudge := FALSE;
                eState := DS_CLOSED;
            END_IF
        // Reasons to reopen (in nudge mode the light curtain is ignored,
        // but the open button and an overload always count)
        ELSIF xOpenBtn OR xReqOpen OR xOverload OR (xObstruction AND NOT xNudge) THEN
            tonMove(IN := FALSE);
            eState := DS_REOPEN;
        ELSIF xCloseLimit THEN
            tonMove(IN := FALSE);
            tonNudge(IN := FALSE);
            xNudge := FALSE;
            eState := DS_CLOSED;
        ELSIF tonMove.Q THEN
            tonMove(IN := FALSE);
            xFault := TRUE;
            eState := DS_FAULT;
        END_IF

    // -----------------------------------------------------------------------
    DS_REOPEN:
        xOpenOut := TRUE;
        (* Under constant pressure a re-open is only the button being let go,
           so pressing it again resumes closing from where it stopped. *)
        IF xConstPress AND xCloseBtn THEN
            eState := DS_CLOSING;
        ELSIF xOpenLimit THEN
            eState := DS_OPEN;
            tonDwell(IN := FALSE);
        END_IF

    // -----------------------------------------------------------------------
    DS_FAULT:
        xOpenOut  := FALSE;
        xCloseOut := FALSE;
        iRemainMs := 0;
        IF NOT xFault THEN                 // reset from outside
            IF xCloseLimit THEN
                eState := DS_CLOSED;
            ELSE
                eState := DS_OPENING;
            END_IF
        END_IF

END_CASE


(*  Fault reset (called from above)  *)
METHOD Reset
xFault := FALSE;
END_METHOD
