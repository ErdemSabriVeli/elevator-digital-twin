# CODESYS Kurulumu — adım adım

CODESYS V3.5 SP17 veya üzeri. Gerçek bir PLC yoksa **CODESYS Control Win V3**
(yazılım PLC) yeterlidir; Godot ile aynı bilgisayarda çalışabilir.

> **Önce yazılım PLC'sini başlatın.** Control Win, CODESYS ile birlikte kurulur
> ama kendiliğinden çalışmaz. Başlat menüsünden **CODESYS Control Win SysTray**
> uygulamasını açın, saat yanındaki simgeye sağ tıklayıp **Start PLC** deyin.
> Çalışmıyorsa cihaz taramasında hiçbir PLC görünmez.

---

## 1. Proje ve cihaz

1. **File → New Project → Standard Project**, ad: `AsansorTwin`.
2. Cihaz: gerçek PLC'niz ya da **CODESYS Control Win V3 x64**.
3. `PLC_PRG` dilini **ST (Structured Text)** seçin.

## 2. POU'ları oluşturma

`codesys/` klasöründeki her dosyayı ilgili nesne tipiyle ekleyin ve içeriğini
yapıştırın. Dosyaların başındaki başlık yorumunu da alabilirsiniz.

| Kaynak dosya | Eklenecek nesne | Nesne adı |
|---|---|---|
| `DUT_Types.st` | **DUT** × 7 (her `TYPE` bloğu ayrı DUT) | `E_LiftState`, `E_Direction`, `E_DoorState`, `E_Fault`, `ST_CallSet`, `ST_LiftInputs`, `ST_LiftOutputs` |
| `GVL_Config.st` | Global Variable List | `GVL_Config` |
| `GVL_IO.st` | Global Variable List | `GVL_IO` |
| `FUN_Bits.st` | **Function** × 2 | `F_GetBit` (BOOL), `F_SetBit` (WORD) |
| `FB_CallRegistry.st` | Function Block | `FB_CallRegistry` |
| `FB_Dispatcher.st` | Function Block | `FB_Dispatcher` |
| `FB_DoorCtrl.st` | Function Block | `FB_DoorCtrl` |
| `FB_Motion.st` | Function Block | `FB_Motion` |
| `FB_Safety.st` | Function Block | `FB_Safety` |
| `FB_LiftCore.st` | Function Block | `FB_LiftCore` |
| `PLC_PRG.st` | Program (mevcut `PLC_PRG`) | `PLC_PRG` |

### Metotlar (bunu atlarsanız proje derlenmez)

Dosyalardaki `METHOD ... END_METHOD` blokları **FB gövdesine yapıştırılmaz**;
FB'ye sağ tık → **Add Object → Method** ile ayrı ayrı eklenir. Metot adını ve
dönüş tipini `METHOD <ad> : <tip>` satırından alın, altındaki `VAR_INPUT`
bloğunu ve gövdeyi yapıştırın. Dönüş tipi yazmayanlar tipsizdir (`VOID`).

| FB | Metotlar (dönüş tipi) |
|---|---|
| `FB_CallRegistry` | `ServeFloor` (—), `CallAbove` (BOOL), `CallBelow` (BOOL) |
| `FB_Dispatcher` | `StopHere` (BOOL), `CallAtFloor` (BOOL), `AnyAbove` (BOOL), `AnyBelow` (BOOL), `NearestAbove` (INT), `NearestBelow` (INT), `FarthestAbove` (INT), `FarthestBelow` (INT), `NearestAny` (INT) |
| `FB_DoorCtrl` | `Reset` (—) |
| `FB_Motion` | `ResetTimeout` (—), `FloorFromPos` (INT), `BrakeMismatch` (BOOL) |
| `FB_Safety` | `OverspeedTrip` (BOOL) |
| `FB_LiftCore` | metot yok |

Toplam **17 metot**. Bu listenin kaynakla uyumlu kaldığını
`godot/tests/st_lint_test.gd` denetler (E maddesi): çağrılan her `fbX.Metot()`
hedef FB'de tanımlı mı diye bakar.

`GVL_Config` niteliksiz (unqualified) kullanılır — sabitlere `C_FLOOR_COUNT` gibi
doğrudan erişilir. Projenizde `{attribute 'qualified_only'}` varsayılan olarak
ekleniyorsa bu satırı silin, yoksa `GVL_Config.C_FLOOR_COUNT` yazmanız gerekir.

## 3. Görev (task) ayarı

**Task Configuration → MainTask**:

- Tip: **Cyclic**
- Aralık: **10 ms** (20 ms de çalışır; Godot tarafı 20 ms'de bir çevrim yapar)
- `PLC_PRG` bu göreve bağlı olmalı.

Kapı ve hareket zamanlayıcıları `TIME` sabitleriyle çalıştığı için tarama süresi
davranışı değiştirmez, yalnızca çözünürlüğü etkiler.

## 4. Modbus TCP Slave Device

1. Cihaz ağacında PLC'ye sağ tık → **Add Device → Fieldbus → Ethernet Adapter → Ethernet**.
2. `Ethernet` düğümüne sağ tık → **Add Device → Modbus → Modbus TCP Slave Device**.
3. **Ethernet** düğümünü aç, **Network interface** olarak Godot'un erişebileceği
   arayüzü seçin (aynı makinede test için `lo`/`127.0.0.1` da olur).
4. **Modbus TCP Slave Device → General** sekmesi:
   - Port: **502**
   - Unit ID: **1**
   - **Holding Registers (%IW)**: en az **16**
   - **Input Registers (%QW)**: en az **16**

### Adresleri eşleme

**Modbus TCP Slave Device → Modbus TCP Slave Device I/O Mapping** sekmesini açın.
Kanalların gerçek başlangıç adreslerini not edin — genelde `%IW0` ve `%QW0` olur ama
projenizde farklı olabilir. `GVL_IO` içindeki iki satırı buna göre düzeltin:

```iecst
g_awMbIn  AT %IW0 : ARRAY[0..15] OF WORD;   // <- gerçek Holding başlangıcı
g_awMbOut AT %QW0 : ARRAY[0..15] OF WORD;   // <- gerçek Input başlangıcı
```

`AT` kullanmak istemezseniz: bu iki satırdan `AT %IW0` / `AT %QW0` ifadelerini silin
ve I/O Mapping sekmesinde her kanalı tek tek `GVL_IO.g_awMbIn[0]` … `[15]` ve
`GVL_IO.g_awMbOut[0]` … `[15]` değişkenlerine bağlayın.

**Always update variables** seçeneğini **Enabled 2 (always in bus cycle task)** yapın;
aksi halde register'lar yalnızca kullanıldıklarında güncellenir.

## 5. Derleme ve indirme

1. **Build → Generate Code** — hata olmamalı.
2. **Online → Login** → indir → **Start**.
3. `GVL_IO` izleme penceresinde `g_stOut.eState` = `LS_INIT` görmelisiniz.
   Godot bağlanana kadar `g_xTwinOnline` FALSE kalır ve asansör hareket etmez —
   bu beklenen davranıştır (bkz. `PLC_PRG.st`, heartbeat gözetimi).

## 6. Godot'u bağlama

Godot'ta HUD → **KONTROL KAYNAGI**:

1. IP kutusuna PLC'nin adresini yazın (aynı makinede `127.0.0.1`).
2. Port `502`.
3. **Baglan** düğmesine basın.

Bağlantı kurulunca sol üstteki satır **"● CODESYS BAGLI … rtt N ms"** olur ve sağdaki
register tablosu canlanır. `F1` tuşu SoftPLC ile CODESYS arasında geçiş yapar; ikisinin
aynı senaryoda aynı davranıp davranmadığını böyle karşılaştırabilirsiniz.

---

## Sorun giderme

| Belirti | Sebep / çözüm |
|---|---|
| "CODESYS YOK … baglaniyor" | PLC çalışmıyor, port kapalı ya da güvenlik duvarı 502'yi engelliyor. Windows Defender'da CODESYS Control için gelen bağlantıya izin verin. |
| Bağlanıyor ama register'lar hep 0 | I/O Mapping'de "Always update variables" kapalı, ya da `%IW/%QW` başlangıç adresleri `GVL_IO` ile uyuşmuyor. |
| Asansör hiç hareket etmiyor, `eFault = 1` | Heartbeat gelmiyor demektir. Godot'un yazdığı register 10 değişiyor mu bakın; yazma (FC16) çalışmıyorsa slave'in Holding Register sayısı 16'dan az olabilir. |
| `eState` sürekli `LS_INIT` | `xHomed` olmamıştır: kabin hiçbir katın door-zone bölgesinde değil. Godot tarafında kabin zemin katta başlar; `FLOOR_ZONE` register'ının 0. biti 1 olmalı. |
| Kabin titriyor / kata oturmuyor | `GVL_Config` ile `Config.gd` arasındaki hız veya kat yüksekliği değerleri farklı. |
| Modbus exception 2 (illegal data address) | Slave'de register sayısı 16'dan az tanımlanmış. |
| Tarama süresi aşımı | `MainTask` aralığını 10 ms'den 20 ms'ye çıkarın. |

## Bağlantıyı kesme testi

Çalışırken PLC'yi durdurun (**Online → Stop**). Godot 1,5 s içinde bağlantıyı kopuk
sayar; `PlcLink.fallback_to_soft` açık olduğu için SoftPLC devreye girer ve HUD
"CODESYS kopuk → SoftPLC yedegi" gösterir. Bu davranışı kapatmak isterseniz
`PlcLink.gd` içinde `fallback_to_soft = false` yapın — o zaman PLC kopunca kabin
komut almadığı için durur.
