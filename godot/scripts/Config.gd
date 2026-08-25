class_name LiftCfg
extends RefCounted

## Tesis parametreleri.
##
## UST BOLUM (PLC ile ORTAK): codesys/GVL_Config.st dosyasindaki degerlerle
## birebir ayni olmak zorunda. Birini degistirirseniz digerini de degistirin,
## yoksa dijital ikiz gercek PLC'den farkli davranir.
##
## ALT BOLUM: sadece 3D/fizik tarafini ilgilendirir, PLC'de karsiligi yoktur.

# =============================================================================
# PLC ILE ORTAK  (GVL_Config.st)
# =============================================================================
const FLOOR_COUNT        := 6         # 0 = zemin ... 5 = en ust kat
const TOP_FLOOR          := 5
const FLOOR_HEIGHT_MM    := 3200
const DOOR_ZONE_MM       := 60
const LEVEL_TOL_MM       := 8
const OVERTRAVEL_MM      := 400

const V_RATED_MMS        := 1600
const V_LEVEL_MMS        := 150
const V_INSPECT_MMS      := 300
const DECEL_DIST_MM      := 2000

const T_DOOR_DWELL       := 4.0       # s
const T_DOOR_DWELL_HALL  := 3.0
const T_DOOR_MOVE_MAX    := 8.0
const T_TRAVEL_MAX       := 25.0
const T_NUDGE            := 15.0
const T_GONG             := 0.6
const T_PARK             := 30.0
const T_BRAKE            := 0.3
const T_START_DELAY      := 0.2
const T_ALARM            := 2.0       # alarm zili basildiktan sonra calma suresi
const T_BRAKE_FB         := 1.0       # fren geri besleme denetim suresi
const T_OVERSPEED        := 0.3       # asiri hiz onaylama suresi
const V_OVERSPEED_MMS    := 1840      # regulator devreye girme hizi (%115)

const PARK_FLOOR         := 0
const FIRE_FLOOR         := 0
const LOAD_FULL_KG       := 630
const LOAD_OVER_KG       := 693

# =============================================================================
# SADECE SIMULASYON (plant modeli)
# =============================================================================
const ACCEL_MMS2         := 900.0     # surucu ivme limiti
const DECEL_MMS2         := 1100.0
const JERK_MMS3          := 1300.0    # ivmenin degisim hizi (S-egrisi yumusakligi)
const DOOR_OPEN_TIME     := 2.0       # tam acilma suresi [s]
const DOOR_CLOSE_TIME    := 2.4
const DOOR_NUDGE_SCALE   := 0.45      # nudge modunda hiz carpani
const BTN_PULSE_S        := 0.25      # momentary buton darbe suresi
const ENC_NOISE_MM       := 0.0       # istenirse encoder gurultusu

# =============================================================================
# 3D GEOMETRI  [metre]
# =============================================================================
const M_FLOOR_H     := 3.2            # = FLOOR_HEIGHT_MM / 1000
const M_SHAFT_W     := 2.50           # kuyu ic genislik (X)
const M_SHAFT_D     := 2.30           # kuyu ic derinlik  (Z)
const M_WALL_T      := 0.16
const M_PIT_DEPTH   := 1.40
# Kuyu basligi: tahrik makinesi + saptirma makarasi + kabin ustu koruma
# korkulugu icin siginma boslugu. Gercek MRL asansorlerde 4-5 m tipiktir.
const M_HEADROOM    := 5.00

const M_CAR_W       := 2.00
const M_CAR_D       := 1.70
const M_CAR_H       := 2.30
const M_CAR_FLOOR_T := 0.10

const M_DOOR_W      := 1.00           # toplam kapi acikligi
const M_DOOR_H      := 2.10
const M_DOOR_T      := 0.05

const M_HALL_W      := 5.00           # kat holu genisligi
const M_HALL_D      := 4.00           # kat holu derinligi (+Z yonu)
const M_SLAB_T      := 0.28

const M_CWT_W       := 1.10           # karsi agirlik genisligi (X)
const M_CWT_D       := 0.22           # kalinligi (Z)
const M_CWT_H       := 1.60
const M_CWT_Z       := -1.02          # kuyunun arka duvari ile kabin arasinda

# --- Askı sistemi (1:1 roping, saptırma makaralı) ---------------------------
const M_ROPE_R      := 0.008          # çelik halat yarıçapı (~16 mm çap)
const ROPE_COUNT    := 5              # paralel halat adedi
const ROPE_PITCH    := 0.036          # halatlar arası mesafe (kanal aralığı)
const M_SHEAVE_R    := 0.32           # tahrik kasnağı yarıçapı
const M_DEFLECT_R   := 0.19           # saptırma makarası yarıçapı
const M_DEFLECT_DY  := 0.30           # saptırma makarasının kasnağa göre altı
const M_CARTOP_RAIL := 0.75           # kabin üstü koruma korkuluğu yüksekliği

# Halat hatları:  kabin z = 0 (kabin merkezinin üstü),
# karşı ağırlık z = M_CWT_Z.  Tahrik kasnağı bu ikisini 2R ile ayırır.
const M_ROPE_Z_CAR  := 0.0
const M_GOV_ROPE_Z  := -0.55          # regülatör halatı kuyunun arka köşesinde
const M_GOV_R       := 0.17           # regülatör kasnağı yarıçapı

# Kat yuksekligi -> dunya Y (kabin taban seviyesi)
static func floor_y(f: int) -> float:
	return float(f) * M_FLOOR_H

static func mm_to_m(mm: float) -> float:
	return mm * 0.001

static func total_height() -> float:
	return float(TOP_FLOOR) * M_FLOOR_H + M_HEADROOM
