# Demo Senaryoları

Sunumda ya da doğrulamada elle denenecek senaryolar. Her biri hem SoftPLC hem
CODESYS modunda aynı sonucu vermelidir — `F1` ile mod değiştirip tekrarlayın.

---

## 1. Temel sefer ve seviyeleme

1. Kamera: `1` (dış görünüm), ardından `F` (kabini takip).
2. Kabin içi panelden **4**'e bas.
3. İzlenecekler:
   - `STATE` sırası: `KAPI KAPANIYOR → KALKIS → SEYIR → YAVASLAMA → SEVIYELEME → VARDI`
   - `SPEED_SP` 1600 mm/s'ye çıkar, 1400 mm kala düşmeye başlar, door-zone'da 150 mm/s olur.
   - Durunca `Konum` satırındaki sapma ±8 mm içindedir.
   - Karşı ağırlık ters yönde hareket eder, kasnak döner.

## 2. Toplamalı kumanda

1. Kabin zemin kattayken **5**'e bas.
2. Kabin yukarı çıkarken **3. kat → yukarı** çağrısı ver.
3. Kabin 3'te durur, kapıyı açar, sonra 5'e devam eder — ters yön çağrısı olsaydı
   (3. kat aşağı) durmazdı, önce 5'i tamamlardı.

## 3. Foto bariyer

1. Bir kata git, kapı açılsın.
2. Kapı kapanmaya başlarken **"Yolcu gecti (darbe)"** düğmesine bas.
3. Kapı tam açığa döner, bekleme süresi yeniden başlar.
4. **"Foto bariyer surekli kesik"** anahtarını 15 s açık tut → **nudge** devreye girer,
   kapı yavaşça kapanmaya çalışır (`DOOR_CMD` bit 2 = 1).

## 4. Aşırı yük

1. Kata var, kapı açılsın.
2. Yük kaydırıcısını **750 kg**'a çek (sınır 693 kg).
3. `ASIRI YUK` lambası yanar, kapı kapanmaz, yeni çağrı verseniz de kalkış olmaz.
4. Yükü düşür → sefer kaldığı yerden devam eder.

## 5. Acil stop ve arıza reseti

1. Kabin hareket halindeyken `E` tuşuna bas.
2. Kabin durur, `ARIZA 8: Acil stop`, gösterge yanıp söner, çağrılar silinir.
3. `E` ile bırak, `R` ile reset → arıza temizlenir, kabin `INIT → IDLE`'a döner.
4. Yeni çağrı vermeden hareket etmemesi doğrudur (arızada çağrılar silinir).

**Reset reddi:** Acil stop basılıyken `R`'ye basın — arıza temizlenmez.
`FB_Safety.st` reset koşulu sebebin ortadan kalkmasını şart koşar.

## 6. Güvenlik zinciri

1. **"Guvenlik zinciri KOPUK"** anahtarını aç.
2. `ARIZA 1`, kabin durur, kabin aydınlatması söner.
3. Kapat + reset → normale döner.

## 7. Yangın senaryosu

1. Kabini üst katlardan birine gönder.
2. **"Yangin modu"** anahtarını aç.
3. Tüm çağrılar silinir, kabin zemin kata iner, kapı açılır ve **açık kalır**.
4. Kat göstergeleri `F` gösterir. Anahtarı kapatınca normal servise döner.

## 8. Revizyon (kabin üstü kumanda)

1. **"Revizyon modu"** anahtarını aç → gösterge `R`, çağrılar kabul edilmez.
2. `PgUp` / `PgDn` tuşlarını basılı tut → kabin 300 mm/s ile hareket eder,
   bıraktığınızda anında durur.
3. Anahtarı kapat → `INIT` üzerinden normal servise döner.

## 9. Bağlantı kopması (yalnızca CODESYS modunda)

1. CODESYS'te **Online → Stop**.
2. Godot 1,5 s içinde kopukluğu görür; HUD "CODESYS kopuk → SoftPLC yedegi" gösterir
   ve simülasyon kesintisiz devam eder.
3. **Start** → tekrar gerçek PLC devralır.

Ters yön: Godot'u kapatın, CODESYS izleme penceresinde `g_xTwinOnline` 2 s sonra
FALSE olur, `g_stIn.xSafetyChain` FALSE'a zorlanır ve asansör hareket etmez.

## 10. Encoder kayması

1. **"Halat kaymasi (encoder)"** anahtarını aç, birkaç sefer yaptır.
2. Encoder konumu ile kat sensörü uyuşmayınca `ARIZA 6` oluşur.
   Bu, kat sensörü ile mutlak konum arasındaki çapraz kontrolün çalıştığını gösterir.

---

## Otomatik koşum

Yukarıdaki senaryoların çoğu regresyon testi olarak da yazılmıştır:

```bash
godot --headless --path godot --script res://tests/sim_test.gd
```

Kontrol mantığında bir değişiklik yaptıktan sonra bu testi çalıştırın; ST tarafında
yaptığınız her değişikliği `SoftPlc.gd` içinde de yapmayı unutmayın.
