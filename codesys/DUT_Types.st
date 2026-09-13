(*
    ============================================================================
    DUT_Types.st   -   Elevator Digital Twin / data types
    CODESYS 3.5 SP17+  |  Structured Text
    ----------------------------------------------------------------------------
    NOTE: every TYPE block in this file must be created as a SEPARATE DUT
          object in the CODESYS project (Application > Add Object > DUT).
    NOTE: the numeric values here are declared identically on the Godot side in
          scripts/IoMap.gd and scripts/Config.gd. If you change one, change the
          other.
    ============================================================================
*)

// ---------------------------------------------------------------------------
// The main state machine states  (Godot: IoMap.State)
// ---------------------------------------------------------------------------
TYPE E_LiftState :
(
    LS_INIT         := 0,   // powered up, position not yet known
    LS_HOMING       := 1,   // travel to the reference floor
    LS_IDLE         := 2,   // idle, waiting for a call
    LS_DOOR_OPENING := 3,
    LS_DOOR_OPEN    := 4,   // counting the dwell time
    LS_DOOR_CLOSING := 5,
    LS_START        := 6,   // brake release + drive enable
    LS_TRAVEL       := 7,   // travelling at rated speed
    LS_DECEL        := 8,   // deceleration ramp
    LS_LEVEL        := 9,   // levelling at the floor (creep speed)
    LS_ARRIVED      := 10,  // stopped, brake applied
    LS_FAULT        := 11,
    LS_FIRE         := 12,  // fire scenario
    LS_INSPECTION   := 13,  // inspection (car top control)
    LS_PARK         := 14,  // returning to the park floor
    LS_RESCUE       := 15,  // mains lost: battery run to the nearest floor
    LS_RELEVEL      := 16   // creeping back to floor level with doors open
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// Direction  (Godot: IoMap.DIR_*)
// ---------------------------------------------------------------------------
TYPE E_Direction :
(
    DIR_NONE := 0,
    DIR_UP   := 1,
    DIR_DOWN := 2
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// The door sub state machine
// ---------------------------------------------------------------------------
TYPE E_DoorState :
(
    DS_CLOSED  := 0,
    DS_OPENING := 1,
    DS_OPEN    := 2,
    DS_CLOSING := 3,
    DS_REOPEN  := 4,   // light curtain broken, reopen
    DS_FAULT   := 5
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// Fault codes  (Godot: IoMap.FAULT_TEXT)
// ---------------------------------------------------------------------------
TYPE E_Fault :
(
    FLT_NONE          := 0,
    FLT_SAFETY_CHAIN  := 1,   // the safety chain is open
    FLT_DOOR_TIMEOUT  := 2,   // the door did not open/close in time
    FLT_TRAVEL_TIMEOUT:= 3,   // floor-to-floor time exceeded
    FLT_DRIVE         := 4,   // drive not ready / drive fault
    FLT_LIMIT         := 5,   // an end limit switch was hit
    FLT_ENCODER       := 6,   // encoder and floor sensor disagree
    FLT_LOCK_LOST     := 7,   // the door lock opened while moving
    FLT_ESTOP         := 8,   // emergency stop button
    FLT_BRAKE         := 9,   // brake feedback disagrees with the command
    FLT_OVERSPEED     := 10,  // the overspeed governor tripped
    FLT_SAFETY_GEAR   := 11   // the safety gear has gripped the rails
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// The registered call set - the dispatcher works on this structure
// ---------------------------------------------------------------------------
TYPE ST_CallSet :
STRUCT
    axUp   : ARRAY[0..15] OF BOOL;   // landing UP calls
    axDown : ARRAY[0..15] OF BOOL;   // landing DOWN calls
    axCar  : ARRAY[0..15] OF BOOL;   // in-car floor buttons
END_STRUCT
END_TYPE


// ---------------------------------------------------------------------------
// Signals from the field  (produced by the Godot physics -> Modbus -> here)
// ---------------------------------------------------------------------------
TYPE ST_LiftInputs :
STRUCT
    // Buttons (momentary)
    stCalls        : ST_CallSet;
    xDoorOpenBtn   : BOOL;
    xDoorCloseBtn  : BOOL;
    xAlarmBtn      : BOOL;
    xFaultReset    : BOOL;

    // Shaft / car sensors
    axFloorZone    : ARRAY[0..15] OF BOOL;  // floor level (door zone) flag
    diPosMM        : DINT;                  // absolute encoder position [mm]
    iActSpeedMMS   : INT;                   // actual speed [mm/s]
    iDoorPosPmil   : INT;                   // door position 0..1000 (0=closed)
    iLoadKg        : INT;

    // Safety chain and limits
    xTopLimit      : BOOL;
    xBotLimit      : BOOL;
    xDoorOpenLimit : BOOL;
    xDoorCloseLimit: BOOL;
    xDoorLocked    : BOOL;   // landing door lock contact chain
    xBrakeFb       : BOOL;   // brake feedback
    xSafetyChain   : BOOL;   // TRUE = the chain is intact
    xGovernorOk    : BOOL;   // the overspeed governor is healthy
    xSafetyGear    : BOOL;   // safety gear wedged on the guide rails
    xMainsOk       : BOOL;   // mains supply healthy
    (* Levelling vanes on the car. Separate from the encoder on purpose: the
       encoder is on the motor and measures rope payout, so it cannot see the
       car hanging lower on a stretched rope. *)
    xRelevelUp     : BOOL;   // car is BELOW floor level -> creep up
    xRelevelDown   : BOOL;   // car is ABOVE floor level -> creep down
    xNtsTop        : BOOL;   // terminal slowdown cam, top end
    xNtsBot        : BOOL;   // terminal slowdown cam, bottom end

    // Mode selectors
    xEStop         : BOOL;
    xOverload      : BOOL;
    xObstruction   : BOOL;   // the light curtain is broken
    xFireCall      : BOOL;
    xInspection    : BOOL;
    xInspUp        : BOOL;
    xInspDown      : BOOL;
    xDriveReady    : BOOL;
    xDriveFault    : BOOL;
END_STRUCT
END_TYPE


// ---------------------------------------------------------------------------
// PLC outputs  (Modbus -> the Godot physics model + visuals)
// ---------------------------------------------------------------------------
TYPE ST_LiftOutputs :
STRUCT
    // Drive
    xDriveEnable  : BOOL;
    xRunUp        : BOOL;
    xRunDown      : BOOL;
    xBrakeRelease : BOOL;
    xLeveling     : BOOL;
    iSpeedSpMMS   : INT;

    // Door
    xDoorOpen     : BOOL;
    xDoorClose    : BOOL;
    xDoorNudge    : BOOL;   // slow forced closing

    // Lamps
    axLampUp      : ARRAY[0..15] OF BOOL;
    axLampDown    : ARRAY[0..15] OF BOOL;
    axLampCar     : ARRAY[0..15] OF BOOL;

    // Indicator / status
    iCurrentFloor : INT;
    iTargetFloor  : INT;
    eDirection    : E_Direction;
    eState        : E_LiftState;
    eFault        : E_Fault;
    xMoving       : BOOL;
    xDoorIsOpen   : BOOL;
    xDoorIsClosed : BOOL;
    xOverloadLamp : BOOL;
    xFaultLamp    : BOOL;
    xFireMode     : BOOL;
    xInspMode     : BOOL;
    xOutOfService : BOOL;
    xGong         : BOOL;
    xAlarm        : BOOL;   // alarm bell (car alarm button)
    xRescue       : BOOL;   // running on the battery rescue drive
    xRelevel      : BOOL;   // re-levelling at the floor with the doors open
    xCabinLight   : BOOL;
    iDoorTimerMs  : INT;    // remaining dwell time [ms]
    iPreTorquePmil: INT;    // pre-torque reference, per mille of rated-load
                            // torque; + = hold the car UP
    iHeartbeat    : INT;
END_STRUCT
END_TYPE
