(*
    ============================================================================
    DUT_Types.st   —   Asansor Digital Twin / Veri tipleri
    CODESYS 3.5 SP17+  |  Structured Text
    ----------------------------------------------------------------------------
    NOT: Bu dosyadaki her TYPE blogu, CODESYS projesinde AYRI bir DUT nesnesi
         olarak olusturulmalidir (Application > Add Object > DUT).
    NOT: Buradaki sayisal degerler Godot tarafinda scripts/IoMap.gd ve
         scripts/Config.gd icinde birebir ayni tanimlanmistir. Birini
         degistirirseniz digerini de degistirin.
    ============================================================================
*)

// ---------------------------------------------------------------------------
// Ana durum makinesi durumlari  (Godot: IoMap.State)
// ---------------------------------------------------------------------------
TYPE E_LiftState :
(
    LS_INIT         := 0,   // guc geldi, henuz konum bilinmiyor
    LS_HOMING       := 1,   // referans kata inis
    LS_IDLE         := 2,   // bosta, cagri bekliyor
    LS_DOOR_OPENING := 3,
    LS_DOOR_OPEN    := 4,   // bekleme suresi (dwell) sayiyor
    LS_DOOR_CLOSING := 5,
    LS_START        := 6,   // fren cozme + surucu enable
    LS_TRAVEL       := 7,   // nominal hizda seyir
    LS_DECEL        := 8,   // yavaslama rampasi
    LS_LEVEL        := 9,   // kat seviyeleme (surunme hizi)
    LS_ARRIVED      := 10,  // durdu, fren tuttu
    LS_FAULT        := 11,
    LS_FIRE         := 12,  // yangin senaryosu
    LS_INSPECTION   := 13,  // revizyon (kabin ustu kumanda)
    LS_PARK         := 14   // park katina donus
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// Yon  (Godot: IoMap.DIR_*)
// ---------------------------------------------------------------------------
TYPE E_Direction :
(
    DIR_NONE := 0,
    DIR_UP   := 1,
    DIR_DOWN := 2
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// Kapi alt durum makinesi
// ---------------------------------------------------------------------------
TYPE E_DoorState :
(
    DS_CLOSED  := 0,
    DS_OPENING := 1,
    DS_OPEN    := 2,
    DS_CLOSING := 3,
    DS_REOPEN  := 4,   // foto bariyer kesildi, geri ac
    DS_FAULT   := 5
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// Hata kodlari  (Godot: IoMap.FAULT_TEXT)
// ---------------------------------------------------------------------------
TYPE E_Fault :
(
    FLT_NONE          := 0,
    FLT_SAFETY_CHAIN  := 1,   // guvenlik devresi acik
    FLT_DOOR_TIMEOUT  := 2,   // kapi verilen surede kapanmadi/acilmadi
    FLT_TRAVEL_TIMEOUT:= 3,   // kat arasi sure asildi
    FLT_DRIVE         := 4,   // surucu hazir degil / surucu arizasi
    FLT_LIMIT         := 5,   // ucdaki limit switch'e carpildi
    FLT_ENCODER       := 6,   // encoder ile kat sensoru uyusmuyor
    FLT_LOCK_LOST     := 7,   // hareket sirasinda kapi kilidi acildi
    FLT_ESTOP         := 8,   // acil stop butonu
    FLT_BRAKE         := 9,   // fren geri beslemesi kumandayla uyusmuyor
    FLT_OVERSPEED     := 10   // hiz regulatoru devreye girdi
) INT;
END_TYPE


// ---------------------------------------------------------------------------
// Cagri kayit kumesi — dispatcher bu yapinin uzerinde calisir
// ---------------------------------------------------------------------------
TYPE ST_CallSet :
STRUCT
    axUp   : ARRAY[0..15] OF BOOL;   // kat holu YUKARI cagrilari
    axDown : ARRAY[0..15] OF BOOL;   // kat holu ASAGI cagrilari
    axCar  : ARRAY[0..15] OF BOOL;   // kabin ici kat butonlari
END_STRUCT
END_TYPE


// ---------------------------------------------------------------------------
// Sahadan gelen sinyaller  (Godot fizik modeli uretir -> Modbus -> buraya)
// ---------------------------------------------------------------------------
TYPE ST_LiftInputs :
STRUCT
    // Butonlar (momentary)
    stCalls        : ST_CallSet;
    xDoorOpenBtn   : BOOL;
    xDoorCloseBtn  : BOOL;
    xAlarmBtn      : BOOL;
    xFaultReset    : BOOL;

    // Kuyu / kabin sensorleri
    axFloorZone    : ARRAY[0..15] OF BOOL;  // kat seviye (door zone) bayragi
    diPosMM        : DINT;                  // mutlak encoder konumu [mm]
    iActSpeedMMS   : INT;                   // gercek hiz [mm/s]
    iDoorPosPmil   : INT;                   // kapi konumu 0..1000 (0=kapali)
    iLoadKg        : INT;

    // Guvenlik zinciri ve limitler
    xTopLimit      : BOOL;
    xBotLimit      : BOOL;
    xDoorOpenLimit : BOOL;
    xDoorCloseLimit: BOOL;
    xDoorLocked    : BOOL;   // kat kapisi kilit kontagi zinciri
    xBrakeFb       : BOOL;   // fren geri bildirimi
    xSafetyChain   : BOOL;   // TRUE = zincir saglam
    xGovernorOk    : BOOL;   // hiz regulatoru saglam

    // Mod secicileri
    xEStop         : BOOL;
    xOverload      : BOOL;
    xObstruction   : BOOL;   // foto bariyer kesildi
    xFireCall      : BOOL;
    xInspection    : BOOL;
    xInspUp        : BOOL;
    xInspDown      : BOOL;
    xDriveReady    : BOOL;
    xDriveFault    : BOOL;
END_STRUCT
END_TYPE


// ---------------------------------------------------------------------------
// PLC cikislari  (Modbus -> Godot fizik modeli + gorsel)
// ---------------------------------------------------------------------------
TYPE ST_LiftOutputs :
STRUCT
    // Surucu
    xDriveEnable  : BOOL;
    xRunUp        : BOOL;
    xRunDown      : BOOL;
    xBrakeRelease : BOOL;
    xLeveling     : BOOL;
    iSpeedSpMMS   : INT;

    // Kapi
    xDoorOpen     : BOOL;
    xDoorClose    : BOOL;
    xDoorNudge    : BOOL;   // yavas zorlamali kapama

    // Lambalar
    axLampUp      : ARRAY[0..15] OF BOOL;
    axLampDown    : ARRAY[0..15] OF BOOL;
    axLampCar     : ARRAY[0..15] OF BOOL;

    // Gosterge / durum
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
    xAlarm        : BOOL;   // alarm zili (kabin alarm butonu)
    xCabinLight   : BOOL;
    iDoorTimerMs  : INT;    // kalan bekleme suresi [ms]
    iHeartbeat    : INT;
END_STRUCT
END_TYPE
