# Modbus TCP I/O Haritası

Tek kaynak. Üç yerde birebir aynı olmalıdır:

- `codesys/GVL_IO.st` (başlıktaki tablo) ve `codesys/PLC_PRG.st` (dönüşüm kodu)
- `godot/scripts/IoMap.gd`
- Bu dosya

CODESYS **Modbus TCP Slave Device** eşlemesi:

| Modbus alanı | Fonksiyon kodu | PLC tarafı | Yön |
|---|---|---|---|
| Holding Registers | FC03 oku / FC16 yaz | `%IW` | Godot → PLC |
| Input Registers | FC04 oku | `%QW` | PLC → Godot |

Godot her çevrimde (varsayılan 20 ms) önce FC16 ile 0–10 arası holding register'ları
yazar, ardından FC04 ile 0–15 arası input register'ları okur.

---

## Godot → PLC — Holding Registers (`g_awMbIn`)

| # | Ad | İçerik |
|---|---|---|
| 0 | `HALL_UP` | bit *n* = *n*. kat YUKARI çağrı butonu (momentary) |
| 1 | `HALL_DOWN` | bit *n* = *n*. kat AŞAĞI çağrı butonu |
| 2 | `CAR_CALL` | bit *n* = kabin içi *n*. kat butonu |
| 3 | `CMD` | komut bitleri — aşağıdaki tabloya bak |
| 4 | `FLOOR_ZONE` | bit *n* = kabin *n*. katın door-zone bölgesinde (±60 mm) |
| 5 | `LIMITS` | limit / kilit bitleri — aşağıdaki tabloya bak |
| 6 | `POS_MM` | mutlak encoder konumu [mm], 0–65535 |
| 7 | `SPEED_MMS` | ölçülen kabin hızı (mutlak değer) [mm/s] |
| 8 | `DOOR_PMIL` | kapı konumu 0–1000 (0 = tam kapalı) |
| 9 | `LOAD_KG` | kabin yükü [kg] |
| 10 | `HEARTBEAT` | her çevrim artar; 2 s sabit kalırsa PLC bağlantıyı kopuk sayar |
| 11–15 | — | rezerve |

### `CMD` (register 3) bitleri

| Bit | Anlam | Bit | Anlam |
|---|---|---|---|
| 0 | Kapı-aç butonu | 7 | Arıza reset butonu |
| 1 | Kapı-kapa butonu | 8 | Foto bariyer kesildi |
| 2 | Alarm butonu | 9 | Sürücü hazır |
| 3 | Acil stop | 10 | Sürücü arızası |
| 4 | Aşırı yük | 11 | Revizyon YUKARI |
| 5 | Yangın çağrısı | 12 | Revizyon AŞAĞI |
| 6 | Revizyon modu | | |

### `LIMITS` (register 5) bitleri

| Bit | Anlam | Bit | Anlam |
|---|---|---|---|
| 0 | Üst limit switch | 4 | Kat kapısı kilit zinciri kapalı |
| 1 | Alt limit switch | 5 | Fren geri beslemesi (çözülü) |
| 2 | Kapı tam açık limiti | 6 | Güvenlik zinciri sağlam |
| 3 | Kapı tam kapalı limiti | 7 | Hız regülatörü sağlam |

> Bit 6 ve 7 **sağlamken 1**'dir. Godot bağlantısı koparsa PLC bit 6'yı 0 kabul eder.

---

## PLC → Godot — Input Registers (`g_awMbOut`)

| # | Ad | İçerik |
|---|---|---|
| 0 | `DRIVE_CMD` | b0 enable, b1 yukarı, b2 aşağı, b3 fren-çöz, b4 seviyeleme |
| 1 | `DOOR_CMD` | b0 aç, b1 kapa, b2 nudge (yavaş zorlamalı kapama) |
| 2 | `LAMP_HALL_UP` | bit *n* = *n*. kat yukarı çağrı lambası |
| 3 | `LAMP_HALL_DOWN` | bit *n* = *n*. kat aşağı çağrı lambası |
| 4 | `LAMP_CAR` | bit *n* = kabin içi *n*. kat lambası |
| 5 | `STATUS` | durum bitleri — aşağıdaki tabloya bak |
| 6 | `CUR_FLOOR` | bulunulan kat (0 = zemin) |
| 7 | `TGT_FLOOR` | hedef kat; hedef yoksa 65535 (`-1`) |
| 8 | `DIRECTION` | 0 yok, 1 yukarı, 2 aşağı |
| 9 | `SPEED_SP` | sürücüye verilen hız referansı [mm/s] |
| 10 | `STATE` | ana durum makinesi kodu (aşağıda) |
| 11 | `FAULT` | arıza kodu (aşağıda) |
| 12 | `HEARTBEAT` | PLC canlılık sayacı (100 ms'de bir artar) |
| 13 | `DOOR_TIMER` | kapı bekleme süresinden kalan [ms] |
| 14–15 | — | rezerve |

### `STATUS` (register 5) bitleri

| Bit | Anlam | Bit | Anlam |
|---|---|---|---|
| 0 | Hareket halinde | 6 | Revizyon modu |
| 1 | Kapı tam açık | 7 | Servis dışı |
| 2 | Kapı tam kapalı | 8 | Gong |
| 3 | Aşırı yük lambası | 9 | Ok yukarı |
| 4 | Arıza lambası | 10 | Ok aşağı |
| 5 | Yangın modu | 11 | Kabin aydınlatması |
| — | | 12 | Alarm zili |

---

## Durum kodları (`STATE`)

| Kod | Durum | Kod | Durum |
|---|---|---|---|
| 0 | INIT | 8 | DECEL — yavaşlama |
| 1 | HOMING | 9 | LEVEL — seviyeleme |
| 2 | IDLE — boşta | 10 | ARRIVED — vardı |
| 3 | DOOR_OPENING | 11 | FAULT — arıza |
| 4 | DOOR_OPEN — bekleme | 12 | FIRE — yangın |
| 5 | DOOR_CLOSING | 13 | INSPECTION — revizyon |
| 6 | START — kalkış | 14 | PARK |
| 7 | TRAVEL — seyir | | |

## Arıza kodları (`FAULT`)

| Kod | Sebep | Nasıl temizlenir |
|---|---|---|
| 0 | Arıza yok | — |
| 1 | Güvenlik zinciri açık / regülatör | Zinciri kapat, reset |
| 2 | Kapı zaman aşımı (8 s) | Engeli kaldır, reset |
| 3 | Hareket zaman aşımı (25 s) | Reset |
| 4 | Sürücü hazır değil / sürücü arızası | Sürücüyü düzelt, reset |
| 5 | Uç limit switch'e çarpıldı | Kabini bölgeden çıkar, reset |
| 6 | Encoder ile kat sensörü uyuşmuyor | Konumu düzelt, reset |
| 7 | Hareket halinde kapı kilidi açıldı | Reset |
| 8 | Acil stop | Butonu serbest bırak, reset |
| 9 | Fren geri beslemesi kumandayla uyuşmuyor (1 s) | Freni kurtar, reset |
| 10 | Aşırı hız — regülatör devrede (%115, 0.3 s) | Sürücüyü kontrol et, reset |

Arıza kalıcıdır. Reset yalnızca sebebi ortadan kalkmışsa kabul edilir
(`FB_Safety.st` içindeki reset koşuluna bakınız). Arıza anında bekleyen tüm
çağrılar silinir; kabin door-zone içindeyse kapı yolcu tahliyesi için açılır.
