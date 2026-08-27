(*
    ============================================================================
    GVL_IO   -   the Modbus TCP Slave Device register area
    Application > Add Object > Global Variable List, named: GVL_IO
    ----------------------------------------------------------------------------
    How the CODESYS "Modbus TCP Slave Device" works:
       Holding Registers  -> PLC inputs   (%IW)  : Godot writes, the PLC reads
       Input Registers    -> PLC outputs  (%QW)  : the PLC writes, Godot reads

    IMPORTANT: the %IW0 / %QW0 start addresses below may differ in your own
    project. In the device tree open "Modbus_TCP_Slave_Device > Modbus TCP
    Slave Device I/O Mapping", read off the real start address and correct the
    AT clauses here accordingly.

    Alternative (if you would rather not use AT): delete the AT clauses, leave
    the arrays as plain variables and bind each channel individually to
    GVL_IO.g_awMbIn[x] / g_awMbOut[x] on the I/O Mapping tab.
    ============================================================================
*)
VAR_GLOBAL

    // Godot -> PLC  (Holding Registers, master write)
    g_awMbIn  AT %IW0 : ARRAY[0..15] OF WORD;

    // PLC -> Godot  (Input Registers, master read)
    g_awMbOut AT %QW0 : ARRAY[0..15] OF WORD;

    // Application layer (filled / read by PRG_ModbusIO)
    g_stIn  : ST_LiftInputs;
    g_stOut : ST_LiftOutputs;

    // Connection supervision
    g_xTwinOnline   : BOOL;        // is the Godot heartbeat changing
    g_iTwinHbLast   : INT;
    g_tTwinLostTime : TIME;

END_VAR


(*
    ============================================================================
    REGISTER MAP  (the same as docs/io-map.md)
    ----------------------------------------------------------------------------
    Godot -> PLC   g_awMbIn[n]    (Holding Register n)
      0  HALL_UP        bit n = landing UP call button, floor n
      1  HALL_DOWN      bit n = landing DOWN call button, floor n
      2  CAR_CALL       bit n = in-car button for floor n
      3  CMD_BITS       0 door-open btn    1 door-close btn  2 alarm
                        3 emergency stop   4 overload        5 fire call
                        6 inspection       7 fault reset     8 light curtain
                        9 drive ready     10 drive fault    11 inspection UP
                       12 inspection DOWN
      4  FLOOR_ZONE     bit n = the car is in the door zone of floor n
      5  LIMIT_BITS     0 top limit        1 bottom limit    2 door open limit
                        3 door close limit 4 door lock       5 brake feedback
                        6 safety chain     7 overspeed governor
      6  CAR_POS_MM     absolute position [mm]  (0..65535)
      7  CAR_SPEED_MMS  actual speed [mm/s]
      8  DOOR_POS_PMIL  door position 0..1000
      9  LOAD_KG        car load [kg]
     10  TWIN_HB        Godot heartbeat (+1 every cycle)
     11..15  reserved

    PLC -> Godot   g_awMbOut[n]   (Input Register n)
      0  DRIVE_CMD      0 enable  1 up      2 down    3 brake-release
                        4 levelling
      1  DOOR_CMD       0 open    1 close   2 nudge
      2  LAMP_HALL_UP   bit n
      3  LAMP_HALL_DOWN bit n
      4  LAMP_CAR       bit n
      5  STATUS_BITS    0 moving   1 door open  2 door closed  3 overload
                        4 fault    5 fire       6 inspection   7 out of service
                        8 gong     9 arrow-up  10 arrow-down  11 car light
                       12 alarm bell
      6  CURRENT_FLOOR
      7  TARGET_FLOOR
      8  DIRECTION      0 none 1 up 2 down
      9  SPEED_SP_MMS   speed reference [mm/s]
     10  STATE_CODE     E_LiftState
     11  FAULT_CODE     E_Fault
     12  PLC_HB         PLC heartbeat
     13  DOOR_TIMER_MS  remaining door dwell time [ms]
     14..15  reserved
    ============================================================================
*)
