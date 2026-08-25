(*
    ============================================================================
    Bit yardimci fonksiyonlari
    Her FUNCTION ayri bir POU olarak eklenmelidir (Add Object > POU > Function).
    ============================================================================
*)

FUNCTION F_GetBit : BOOL
VAR_INPUT
    wVal : WORD;
    iBit : INT;
END_VAR

IF (iBit < 0) OR (iBit > 15) THEN
    F_GetBit := FALSE;
ELSE
    F_GetBit := (wVal AND SHL(WORD#1, INT_TO_BYTE(iBit))) <> 0;
END_IF

END_FUNCTION


FUNCTION F_SetBit : WORD
VAR_INPUT
    wVal : WORD;
    iBit : INT;
    xVal : BOOL;
END_VAR

IF (iBit < 0) OR (iBit > 15) THEN
    F_SetBit := wVal;
ELSIF xVal THEN
    F_SetBit := wVal OR SHL(WORD#1, INT_TO_BYTE(iBit));
ELSE
    F_SetBit := wVal AND (NOT SHL(WORD#1, INT_TO_BYTE(iBit)));
END_IF

END_FUNCTION
