(*
    ============================================================================
    GVL_Config   —   Tesis parametreleri (tek kaynak)
    Application > Add Object > Global Variable List  adiyla: GVL_Config
    ----------------------------------------------------------------------------
    !! Godot tarafindaki karsiligi: godot/scripts/Config.gd
       Iki dosyadaki degerler ayni olmak zorunda, yoksa twin ile gercek PLC
       farkli davranir.
    ============================================================================
*)
VAR_GLOBAL CONSTANT

    // --- Kuyu geometrisi ----------------------------------------------------
    C_FLOOR_COUNT      : INT  := 6;      // 0 = zemin ... 5 = en ust kat
    C_TOP_FLOOR        : INT  := 5;
    C_FLOOR_HEIGHT_MM  : DINT := 3200;   // katlar arasi mesafe
    C_DOOR_ZONE_MM     : DINT := 60;     // kat seviyesi +/- door-zone bolgesi
    C_LEVEL_TOL_MM     : DINT := 8;      // "kata geldi" toleransi
    C_OVERTRAVEL_MM    : DINT := 400;    // ucdaki limit switch mesafesi

    // --- Surus profili ------------------------------------------------------
    C_V_RATED_MMS      : INT  := 1600;   // nominal hiz
    C_V_LEVEL_MMS      : INT  := 150;    // seviyeleme (surunme) hizi
    C_V_INSPECT_MMS    : INT  := 300;    // revizyon hizi
    C_V_OVERSPEED_MMS  : INT  := 1840;   // regulator devreye girme hizi (%115)
    C_DECEL_DIST_MM    : DINT := 2000;   // yavaslamaya baslama mesafesi
                                         // (jerk sinirli surucunun durma
                                         //  mesafesine gore boyutlandirildi)

    // --- Zamanlar -----------------------------------------------------------
    C_T_DOOR_DWELL     : TIME := T#4S;    // kabin cagrisinda kapi acik kalma
    C_T_DOOR_DWELL_HALL: TIME := T#3S;    // sadece hol cagrisinda
    C_T_DOOR_MOVE_MAX  : TIME := T#8S;    // kapi hareket zaman asimi
    C_T_TRAVEL_MAX     : TIME := T#25S;   // kat arasi hareket zaman asimi
    C_T_NUDGE          : TIME := T#15S;   // bu sureden sonra zorlamali kapama
    C_T_GONG           : TIME := T#600MS;
    C_T_PARK           : TIME := T#30S;   // bosta bekleyince park katina don
    C_T_BRAKE          : TIME := T#300MS; // fren cozme/tutma gecikmesi
    C_T_START_DELAY    : TIME := T#200MS; // surucu enable -> hareket
    C_T_ALARM          : TIME := T#2S;    // alarm zili calma suresi
    C_T_BRAKE_FB       : TIME := T#1S;    // fren geri besleme denetimi
    C_T_OVERSPEED      : TIME := T#300MS; // asiri hiz onaylama suresi

    // --- Kat / yuk ----------------------------------------------------------
    C_PARK_FLOOR       : INT  := 0;
    C_FIRE_FLOOR       : INT  := 0;      // yangin tahliye kati
    C_LOAD_FULL_KG     : INT  := 630;
    C_LOAD_OVER_KG     : INT  := 693;    // %110 -> asiri yuk

END_VAR
