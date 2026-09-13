(*
    ============================================================================
    GVL_Config   -   Plant parameters (single source of truth)
    Application > Add Object > Global Variable List, named: GVL_Config
    ----------------------------------------------------------------------------
    !! The Godot counterpart is: godot/scripts/Config.gd
       The values in the two files must be identical, otherwise the twin and
       the real PLC behave differently.
    ============================================================================
*)
VAR_GLOBAL CONSTANT

    // --- Shaft geometry -----------------------------------------------------
    C_FLOOR_COUNT      : INT  := 6;      // 0 = ground ... 5 = top floor
    C_TOP_FLOOR        : INT  := 5;
    C_FLOOR_HEIGHT_MM  : DINT := 3200;   // distance between floors
    C_DOOR_ZONE_MM     : DINT := 60;     // floor level +/- the door-zone band
    C_LEVEL_TOL_MM     : DINT := 8;      // "arrived at floor" tolerance
    C_RELEVEL_MM       : DINT := 10;     // out by this much at a floor -> re-level
    C_OVERTRAVEL_MM    : DINT := 400;    // distance to the end limit switch

    // --- Drive profile ------------------------------------------------------
    C_V_RATED_MMS      : INT  := 1600;   // rated speed
    C_V_LEVEL_MMS      : INT  := 150;    // levelling (creep) speed
    C_V_INSPECT_MMS    : INT  := 300;    // inspection speed
    C_V_OVERSPEED_MMS  : INT  := 1840;   // governor electrical trip (115%)
    C_V_GEAR_TRIP_MMS  : INT  := 2000;   // governor mechanical trip -> the
                                         // safety gear grips the rails (125%)
    C_V_ARD_MMS        : INT  := 200;    // rescue speed on battery
    C_V_ZERO_MMS       : INT  := 30;     // drive zero-speed detection
    C_V_CREEP_MMS      : INT  := 40;     // final approach speed at the edge of
                                         // the levelling tolerance
    C_DECEL_DIST_MM    : DINT := 2600;   // distance at which to start slowing.
                                         // Sized for the stopping distance the
                                         // jerk-limited drive actually delivers
                                         // (~610 mm/s2), with margin: sized to
                                         // its bare capability the car arrives
                                         // long, because the loop needs jerk
                                         // time to reverse the acceleration.

    // --- Times --------------------------------------------------------------
    C_T_DOOR_DWELL     : TIME := T#4S;    // door dwell on a car call
    C_T_DOOR_DWELL_HALL: TIME := T#3S;    // on a landing call only
    C_T_DOOR_MOVE_MAX  : TIME := T#8S;    // door movement timeout
    C_T_TRAVEL_MAX     : TIME := T#25S;   // floor-to-floor travel timeout
    C_T_NUDGE          : TIME := T#15S;   // force the door closed after this
    C_T_GONG           : TIME := T#600MS;
    C_T_PARK           : TIME := T#30S;   // return to the park floor when idle
    C_T_BRAKE          : TIME := T#300MS; // brake release/apply delay
    C_T_START_DELAY    : TIME := T#200MS; // drive enable -> motion
    C_T_ALARM          : TIME := T#2S;    // how long the alarm bell rings
    C_T_BRAKE_FB       : TIME := T#1S;    // brake feedback supervision
    C_T_OVERSPEED      : TIME := T#300MS; // overspeed confirmation time
    C_T_ARD_START      : TIME := T#3S;    // mains loss -> battery changeover

    // --- Floors / load ------------------------------------------------------
    C_PARK_FLOOR       : INT  := 0;
    C_FIRE_FLOOR       : INT  := 0;      // fire evacuation floor
    C_LOAD_FULL_KG     : INT  := 630;
    C_LOAD_OVER_KG     : INT  := 693;    // 110% -> overload

    // Masses. The counterweight balances the empty car plus HALF the rated
    // load (a 50% balance factor, the usual choice), so the machine only ever
    // holds the difference - and that difference reverses sign as the car
    // fills. Used to compute the pre-torque reference.
    C_CAR_EMPTY_KG     : INT  := 1200;   // empty car: cabin + sling + doors
    C_CWT_KG           : INT  := 1515;   // = C_CAR_EMPTY_KG + 0.5 * C_LOAD_FULL_KG

END_VAR
