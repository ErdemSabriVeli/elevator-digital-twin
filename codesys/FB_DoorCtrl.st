(*
    ============================================================================
    FB_DoorCtrl   —   Kapi alt durum makinesi
    ----------------------------------------------------------------------------
    Kabin kapisi + kat kapisi birlikte surulur (kavrama/coupler mantigi).
    Foto bariyer, kapi-ac butonu ve asiri yuk kapiyi geri actirir.
    C_T_NUDGE suresi asilirsa "nudge" (yavas zorlamali kapama) devreye girer.
    Godot karsiligi: SoftPlc.gd -> class DoorCtrl
    ============================================================================
*)
FUNCTION_BLOCK FB_DoorCtrl
VAR_INPUT
    xEnable       : BOOL;    // FALSE -> kapi motorlari serbest (ariza/estop)
    xReqOpen      : BOOL;    // ust mantik: kapiyi ac ve acik tut
    xReqClose     : BOOL;    // ust mantik: kapiyi kapat (hareket edecegiz)
    xOpenLimit    : BOOL;
    xCloseLimit   : BOOL;
    xObstruction  : BOOL;    // foto bariyer kesildi
    xOpenBtn      : BOOL;
    xCloseBtn     : BOOL;
    xOverload     : BOOL;
    tDwell        : TIME := T#4S;
END_VAR
VAR_OUTPUT
    xOpenOut   : BOOL;
    xCloseOut  : BOOL;
    xNudge     : BOOL;
    xIsOpen    : BOOL;
    xIsClosed  : BOOL;
    xDwellDone : BOOL;       // bekleme suresi doldu, kapanmaya hazir
    xFault     : BOOL;
    eState     : E_DoorState;
    iRemainMs  : INT;
END_VAR
VAR
    tonDwell  : TON;
    tonMove   : TON;         // hareket zaman asimi
    tonNudge  : TON;         // kapida cok bekleme
    tRemain   : TIME;
END_VAR

// ---------------------------------------------------------------------------
// Varsayilan cikislar
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
        IF xReqOpen OR xOpenBtn THEN
            eState := DS_OPENING;
        ELSIF NOT xCloseLimit AND xReqClose THEN
            eState := DS_CLOSING;      // tam kapanmamis, tekrar dene
        END_IF

    // -----------------------------------------------------------------------
    DS_OPENING:
        xOpenOut := TRUE;
        tonMove(IN := TRUE, PT := C_T_DOOR_MOVE_MAX);
        IF xOpenLimit THEN
            tonMove(IN := FALSE);
            eState := DS_OPEN;
        ELSIF tonMove.Q THEN
            tonMove(IN := FALSE);
            xFault := TRUE;
            eState := DS_FAULT;
        END_IF

    // -----------------------------------------------------------------------
    DS_OPEN:
        // Bekleme suresi: engel / asiri yuk / ac butonu varken sayac resetlenir
        tonDwell(IN := NOT (xObstruction OR xOverload OR xOpenBtn OR xReqOpen),
                 PT := tDwell);
        tonNudge(IN := TRUE, PT := C_T_NUDGE);
        xNudge := tonNudge.Q;

        tRemain   := tDwell - tonDwell.ET;
        iRemainMs := TIME_TO_INT(tRemain);

        xDwellDone := tonDwell.Q;

        // Kapat butonu bekleme suresini atlatir (engel yoksa)
        IF xCloseBtn AND NOT xObstruction AND NOT xOverload AND NOT xReqOpen THEN
            eState := DS_CLOSING;
            tonDwell(IN := FALSE);
        ELSIF tonDwell.Q AND xReqClose THEN
            eState := DS_CLOSING;
            tonDwell(IN := FALSE);
        ELSIF xNudge AND xReqClose THEN
            eState := DS_CLOSING;      // zorlamali kapama
            tonDwell(IN := FALSE);
        END_IF

    // -----------------------------------------------------------------------
    DS_CLOSING:
        xCloseOut := TRUE;
        tonMove(IN := TRUE, PT := C_T_DOOR_MOVE_MAX);
        iRemainMs := 0;

        // Geri acma sebepleri (nudge modunda foto bariyer yoksayilir,
        // ama ac butonu ve asiri yuk her zaman gecerlidir)
        IF xOpenBtn OR xReqOpen OR xOverload OR (xObstruction AND NOT xNudge) THEN
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
        IF xOpenLimit THEN
            eState := DS_OPEN;
            tonDwell(IN := FALSE);
        END_IF

    // -----------------------------------------------------------------------
    DS_FAULT:
        xOpenOut  := FALSE;
        xCloseOut := FALSE;
        iRemainMs := 0;
        IF NOT xFault THEN                 // disaridan reset edildi
            IF xCloseLimit THEN
                eState := DS_CLOSED;
            ELSE
                eState := DS_OPENING;
            END_IF
        END_IF

END_CASE


(*  Ariza reset (ust mantik cagirir)  *)
METHOD Reset
xFault := FALSE;
END_METHOD
