(*
    ============================================================================
    GVL_IO   —   Modbus TCP Slave Device register alani
    Application > Add Object > Global Variable List  adiyla: GVL_IO
    ----------------------------------------------------------------------------
    CODESYS "Modbus TCP Slave Device" mantigi:
       Holding Registers  -> PLC girisi  (%IW)  : Godot yazar, PLC okur
       Input Registers    -> PLC cikisi  (%QW)  : PLC yazar, Godot okur

    ONEMLI: Asagidaki %IW0 / %QW0 baslangic adresleri sizin projenizde farkli
    olabilir. Cihaz agacinda "Modbus_TCP_Slave_Device > Modbus TCP Slave Device
    I/O Mapping" sekmesini acip gercek baslangic adresini gorun ve buradaki
    AT ifadelerini ona gore duzeltin.

    Alternatif (AT kullanmak istemezseniz): AT ifadelerini silin, dizileri
    normal degisken birakin ve I/O Mapping sekmesinde her kanali tek tek
    GVL_IO.g_awMbIn[x] / g_awMbOut[x] degiskenine baglayin.
    ============================================================================
*)
VAR_GLOBAL

    // Godot -> PLC  (Holding Registers, master write)
    g_awMbIn  AT %IW0 : ARRAY[0..15] OF WORD;

    // PLC -> Godot  (Input Registers, master read)
    g_awMbOut AT %QW0 : ARRAY[0..15] OF WORD;

    // Uygulama katmani (PRG_ModbusIO tarafindan doldurulur / okunur)
    g_stIn  : ST_LiftInputs;
    g_stOut : ST_LiftOutputs;

    // Baglanti gozetimi
    g_xTwinOnline   : BOOL;        // Godot heartbeat degisiyor mu
    g_iTwinHbLast   : INT;
    g_tTwinLostTime : TIME;

END_VAR


(*
    ============================================================================
    REGISTER HARITASI  (docs/io-map.md ile ayni)
    ----------------------------------------------------------------------------
    Godot -> PLC   g_awMbIn[n]    (Holding Register n)
      0  HALL_UP        bit n = n. kat YUKARI cagri butonu
      1  HALL_DOWN      bit n = n. kat ASAGI cagri butonu
      2  CAR_CALL       bit n = kabin ici n. kat butonu
      3  CMD_BITS       0 kapi-ac btn      1 kapi-kapa btn   2 alarm
                        3 acil stop        4 asiri yuk       5 yangin cagrisi
                        6 revizyon         7 hata reset      8 foto bariyer
                        9 surucu hazir    10 surucu ariza   11 revizyon YUKARI
                       12 revizyon ASAGI
      4  FLOOR_ZONE     bit n = kabin n. katin door-zone bolgesinde
      5  LIMIT_BITS     0 ust limit        1 alt limit       2 kapi acik limit
                        3 kapi kapali lim. 4 kapi kilidi     5 fren geri bes.
                        6 guvenlik zinciri 7 hiz regulatoru
      6  CAR_POS_MM     mutlak konum [mm]  (0..65535)
      7  CAR_SPEED_MMS  gercek hiz [mm/s]
      8  DOOR_POS_PMIL  kapi konumu 0..1000
      9  LOAD_KG        kabin yuku [kg]
     10  TWIN_HB        Godot heartbeat (her cevrim +1)
     11..15  rezerve

    PLC -> Godot   g_awMbOut[n]   (Input Register n)
      0  DRIVE_CMD      0 enable  1 yukari  2 asagi  3 fren-coz  4 seviyeleme
      1  DOOR_CMD       0 ac      1 kapa    2 nudge
      2  LAMP_HALL_UP   bit n
      3  LAMP_HALL_DOWN bit n
      4  LAMP_CAR       bit n
      5  STATUS_BITS    0 hareket  1 kapi acik  2 kapi kapali  3 asiri yuk
                        4 ariza    5 yangin     6 revizyon     7 servis disi
                        8 gong     9 ok-yukari 10 ok-asagi    11 kabin lambasi
                       12 alarm zili
      6  CURRENT_FLOOR
      7  TARGET_FLOOR
      8  DIRECTION      0 yok 1 yukari 2 asagi
      9  SPEED_SP_MMS   hiz referansi [mm/s]
     10  STATE_CODE     E_LiftState
     11  FAULT_CODE     E_Fault
     12  PLC_HB         PLC heartbeat
     13  DOOR_TIMER_MS  kapi bekleme kalan sure [ms]
     14..15  rezerve
    ============================================================================
*)
