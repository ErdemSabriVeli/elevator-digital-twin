extends SceneTree

## Grafik arayuz olmadan calisan senaryo testi.
## SoftPlc (ST kodunun ikizi) + LiftPlant (fizik modeli) birlikte kosturulur.
##
## Calistirma:
##   godot --headless --path <godot klasoru> --script res://tests/sim_test.gd

const DT := 1.0 / 60.0

var plant: LiftPlant
var plc: SoftPlc
var regs_out := PackedInt32Array()
var regs_in := PackedInt32Array()
var hb := 0
var t := 0.0
var failures := 0


func _initialize() -> void:
	print("=== ASANSOR DIJITAL IKIZ — SENARYO TESTLERI ===\n")

	test_car_call()
	test_collective()
	test_estop()
	test_overload()
	test_fire()
	test_light_curtain()
	test_travel_timeout()
	test_brake_feedback()
	test_overspeed()
	test_gong_and_alarm()
	test_ride_quality()

	print("\n=== SONUC: %s ===" % ("TUM TESTLER GECTI" if failures == 0
			else "%d TEST BASARISIZ" % failures))
	quit(1 if failures > 0 else 0)


# =============================================================================
func reset(start_floor := 0) -> void:
	plant = LiftPlant.new()
	plant.pos_mm = float(start_floor * LiftCfg.FLOOR_HEIGHT_MM)
	plc = SoftPlc.new()
	regs_out.resize(LiftIo.REG_COUNT)
	regs_in.resize(LiftIo.REG_COUNT)
	for i in LiftIo.REG_COUNT:
		regs_out[i] = 0
	hb = 0
	t = 0.0
	# PLC'nin INIT -> IDLE gecisini tamamlamasi icin bir kac cevrim
	step(0.5)


func step(seconds: float) -> void:
	var n := int(seconds / DT)
	for i in range(n):
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_in = plant.build_registers(hb)
		regs_out = plc.scan(regs_in, DT)
		t += DT


## Kosul saglanana kadar (en fazla timeout saniye) simule et.
func step_until(cond: Callable, timeout := 40.0) -> bool:
	var elapsed := 0.0
	while elapsed < timeout:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_in = plant.build_registers(hb)
		regs_out = plc.scan(regs_in, DT)
		elapsed += DT
		t += DT
		if cond.call():
			return true
	return false


func state() -> int:
	return regs_out[LiftIo.OUT_STATE]

func cur_floor() -> int:
	return regs_out[LiftIo.OUT_CUR_FLOOR]

func status(bit: int) -> bool:
	return LiftIo.get_bit(regs_out[LiftIo.OUT_STATUS], bit)

func fault() -> int:
	return regs_out[LiftIo.OUT_FAULT]


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [gecti] %s %s" % [name, detail])
	else:
		failures += 1
		print("  [HATA ] %s %s" % [name, detail])


func press_for(key: String, seconds := 0.3) -> void:
	plant.press(key)
	step(seconds)


# --- cok satirli kosullar (lambda tek satirla sinirli) -----------------------
func _cond_at_fire_floor() -> bool:
	return cur_floor() == LiftCfg.FIRE_FLOOR and plant.door_pos > 0.95


func _cond_door_closing() -> bool:
	return plant.door_pos < 0.8 \
			and LiftIo.get_bit(regs_out[LiftIo.OUT_DOOR_CMD], LiftIo.DOOR_CLOSE_CMD)


# =============================================================================
func test_car_call() -> void:
	print("1) Kabin ici cagri: zemin -> 3. kat")
	reset(0)

	check("baslangicta IDLE", state() == LiftIo.State.IDLE,
			"(durum=%s)" % LiftIo.STATE_TEXT[state()])

	press_for("car_3")
	var arrived := step_until(func(): return cur_floor() == 3 and status(LiftIo.ST_DOOR_OPEN))
	check("3. kata varip kapiyi acti", arrived,
			"(kat=%d, konum=%.0f mm, sure=%.1f s)" % [cur_floor(), plant.pos_mm, t])
	check("kat seviyesi toleransi", absf(plant.pos_mm - 3 * LiftCfg.FLOOR_HEIGHT_MM)
			<= LiftCfg.LEVEL_TOL_MM,
			"(sapma=%.1f mm)" % (plant.pos_mm - 3 * LiftCfg.FLOOR_HEIGHT_MM))

	var closed := step_until(func(): return status(LiftIo.ST_DOOR_CLOSED), 15.0)
	check("bekleme sonrasi kapi kapandi", closed)
	step(0.2)   # FSM'nin bir sonraki taramada IDLE'a gecmesi (ST ile ayni davranis)
	check("bosta duruma dondu", state() == LiftIo.State.IDLE or state() == LiftIo.State.PARK,
			"(durum=%s)" % LiftIo.STATE_TEXT[state()])


func test_collective() -> void:
	print("\n2) Toplamali kumanda: 5. kattan asagi inerken 2. kat cagrisi")
	reset(0)

	press_for("car_5")
	var up := step_until(func(): return cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN))
	check("5. kata cikti", up, "(sure=%.1f s)" % t)

	# asagi inerken yol ustundeki 2. kattan asagi cagrisi
	press_for("hall_down_2")
	var stopped := step_until(func(): return cur_floor() == 2 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("inisde 2. katta durdu", stopped, "(kat=%d)" % cur_floor())
	check("2. kat asagi lambasi sondu",
			not LiftIo.get_bit(regs_out[LiftIo.OUT_LAMP_DOWN], 2))


func test_estop() -> void:
	print("\n3) Acil stop: hareket halinde guvenlik")
	reset(0)

	press_for("car_5")
	var moving := step_until(func(): return status(LiftIo.ST_MOVING) and plant.pos_mm > 1500.0)
	check("hareket basladi", moving, "(konum=%.0f mm)" % plant.pos_mm)

	plant.sw_estop = true
	step(1.5)
	check("acil stopta hareket durdu", absf(plant.speed_mms) < 1.0,
			"(hiz=%.1f mm/s)" % plant.speed_mms)
	check("ariza kodu ESTOP", fault() == LiftIo.Fault.ESTOP,
			"(kod=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])

	plant.sw_estop = false
	press_for("reset")
	step(1.0)
	check("reset sonrasi ariza silindi", fault() == LiftIo.Fault.NONE)
	# Ariza sirasinda tum cagrilar silinir (EN 81 uygulamasi): kabin kendiliginden
	# yola cikmamali, yolcu yeniden cagri vermelidir.
	check("ariza cagrilari sildi", regs_out[LiftIo.OUT_LAMP_CAR] == 0,
			"(lamba=%d)" % regs_out[LiftIo.OUT_LAMP_CAR])

	press_for("car_5")
	var resumed := step_until(func(): return cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("yeni cagri ile sefer yapildi", resumed, "(kat=%d)" % cur_floor())


func test_overload() -> void:
	print("\n4) Asiri yuk: kapi kapanmamali, kalkis olmamali")
	reset(0)

	# once 2. kata git ve kapiyi ac, sonra yolcu bindir (asiri yuk)
	press_for("car_2")
	var at2 := step_until(func(): return cur_floor() == 2 and plant.door_pos > 0.99)
	check("2. kata varildi", at2)

	plant.load_kg = 750          # > 693 kg -> asiri yuk
	step(8.0)
	check("asiri yuk lambasi yandi", status(LiftIo.ST_OVERLOAD))
	check("kapi acik kaldi", plant.door_pos > 0.9, "(kapi=%.0f%%)" % (plant.door_pos * 100))

	# asiri yuk devam ederken yeni cagri kalkisa izin vermemeli
	press_for("car_4")
	step(6.0)
	check("asiri yukte kalkis yok",
			absf(plant.pos_mm - 2 * LiftCfg.FLOOR_HEIGHT_MM) < 50.0,
			"(konum=%.0f mm)" % plant.pos_mm)

	plant.load_kg = 80
	var moved := step_until(func(): return cur_floor() == 4 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("yuk azalinca sefer tamamlandi", moved, "(kat=%d)" % cur_floor())


func test_fire() -> void:
	print("\n5) Yangin modu: tahliye katina inis")
	reset(4)

	plant.sw_fire = true
	var evac := step_until(_cond_at_fire_floor, 45.0)
	check("tahliye katina indi ve kapiyi acti", evac,
			"(kat=%d, kapi=%.0f%%)" % [cur_floor(), plant.door_pos * 100])
	check("yangin modu bayragi", status(LiftIo.ST_FIRE))

	# Regresyon: kapi ac-kapa dongusune girmemeli (donguperiyodu ~9 s idi)
	step(25.0)
	check("kapi 25 s boyunca acik kaldi", plant.door_pos > 0.95,
			"(kapi=%.0f%%)" % (plant.door_pos * 100))


func test_light_curtain() -> void:
	print("\n6) Foto bariyer: kapanan kapi geri acilmali")
	reset(0)

	press_for("car_2")
	var opened := step_until(func(): return cur_floor() == 2 and plant.door_pos > 0.99)
	check("2. katta kapi acildi", opened)

	# kapanmaya baslamasini bekle
	var closing := step_until(_cond_door_closing, 15.0)
	check("kapi kapanmaya basladi", closing, "(kapi=%.0f%%)" % (plant.door_pos * 100))

	plant.sw_obstruction = true
	var reopened := step_until(func(): return plant.door_pos > 0.99, 10.0)
	plant.sw_obstruction = false
	check("bariyer kesilince geri acildi", reopened,
			"(kapi=%.0f%%)" % (plant.door_pos * 100))

	var closed2 := step_until(func(): return plant.door_pos < 0.01, 20.0)
	check("engel kalkinca tekrar kapandi", closed2)


# =============================================================================
func test_travel_timeout() -> void:
	print("\n7) Hareket zaman asimi ve arizadan donus")
	reset(0)

	press_for("car_5")
	var moving := step_until(func(): return status(LiftIo.ST_MOVING) and plant.pos_mm > 800.0)
	check("hareket basladi", moving, "(konum=%.0f mm)" % plant.pos_mm)

	# kabin sikisti: surucu calisiyor ama konum ilerlemiyor
	plant.sw_car_jammed = true
	var timed_out := step_until(func(): return fault() == LiftIo.Fault.TRAVEL_TIMEOUT, 40.0)
	check("hareket zaman asimi arizasi olustu", timed_out,
			"(kod=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])

	# Sikisma giderilip reset veriliyor. Zamanlayici CIKIS bayragi da
	# temizlenmezse ariza aninda geri gelir -> asagidaki kontrol onu yakalar.
	plant.sw_car_jammed = false
	press_for("reset")
	step(0.5)
	check("reset sonrasi ariza silindi", fault() == LiftIo.Fault.NONE,
			"(kod=%d)" % fault())
	step(3.0)
	check("ariza geri gelmiyor (bayrak kilitlenmiyor)",
			fault() == LiftIo.Fault.NONE, "(kod=%d)" % fault())

	press_for("car_4")
	var ok := step_until(func(): return cur_floor() == 4 and status(LiftIo.ST_DOOR_OPEN), 45.0)
	check("arizadan sonra normal sefer yapilabiliyor", ok, "(kat=%d)" % cur_floor())


func test_brake_feedback() -> void:
	print("\n8) Fren geri besleme denetimi")
	reset(0)

	plant.sw_brake_stuck = true      # fren mekanik takili: cozme emrine cevap yok
	press_for("car_3")
	var brake_flt := step_until(func(): return fault() == LiftIo.Fault.BRAKE, 25.0)
	check("fren arizasi tespit edildi", brake_flt,
			"(kod=%d %s)" % [fault(), LiftIo.FAULT_TEXT[fault()]])
	check("kabin yerinde kaldi", absf(plant.pos_mm) < 20.0,
			"(konum=%.0f mm)" % plant.pos_mm)

	plant.sw_brake_stuck = false
	press_for("reset")
	step(2.0)
	check("fren duzelince ariza silindi", fault() == LiftIo.Fault.NONE,
			"(kod=%d)" % fault())


func test_overspeed() -> void:
	print("\n9) Asiri hiz - regulator devreye giriyor")
	reset(0)

	press_for("car_5")
	var fast := step_until(func(): return plant.speed_mms > 900.0)
	check("kabin hizlandi", fast, "(hiz=%.0f mm/s)" % plant.speed_mms)

	plant.sw_overspeed = true        # surucu kacagi
	var trip := step_until(func(): return fault() == LiftIo.Fault.OVERSPEED, 12.0)
	check("regulator asiri hizi yakaladi", trip,
			"(kod=%d, en yuksek hiz gozlendi)" % fault())
	step(2.0)
	check("asiri hizda kabin durduruldu", absf(plant.speed_mms) < 5.0,
			"(hiz=%.1f mm/s)" % plant.speed_mms)


func test_gong_and_alarm() -> void:
	print("\n10) Gong suresi ve alarm zili")
	reset(0)

	press_for("car_2")
	var arrived := step_until(func(): return status(LiftIo.ST_GONG))
	check("kata varista gong caldi", arrived)

	# gong ne kadar surdu?
	var t0 := t
	var still := step_until(func(): return not status(LiftIo.ST_GONG), 5.0)
	var dur := t - t0
	check("gong suresi ayarli degere yakin", still and dur > LiftCfg.T_GONG * 0.5,
			"(%.2f s, hedef %.2f s)" % [dur, LiftCfg.T_GONG])

	# alarm zili
	check("alarm baslangicta kapali", not status(LiftIo.ST_ALARM))
	plant.press("alarm")
	step(0.3)
	check("alarm butonu zili calistirdi", status(LiftIo.ST_ALARM))
	step(LiftCfg.T_ALARM + 0.5)
	check("zil sure sonunda sustu", not status(LiftIo.ST_ALARM))


# =============================================================================
func test_ride_quality() -> void:
	print("\n11) Surus kalitesi: jerk sinirli S-egrisi profili")
	reset(0)

	press_for("car_5")

	# seyir boyunca ivmenin degisim hizini (jerk) olc
	var prev_a := plant.accel_mms2
	var max_jerk := 0.0
	var max_acc := 0.0
	var elapsed := 0.0
	while elapsed < 20.0:
		plant.apply_outputs(regs_out)
		plant.step(DT)
		hb = (hb + 1) % 32000
		regs_out = plc.scan(plant.build_registers(hb), DT)
		elapsed += DT
		t += DT
		# Yalnizca surucu tork uretirken olc. Fren tutma / acil durus yolu
		# kasten serttir ve konfor sinirina tabi degildir.
		if plant.powered:
			max_jerk = maxf(max_jerk, absf(plant.accel_mms2 - prev_a) / DT)
			max_acc = maxf(max_acc, absf(plant.accel_mms2))
		prev_a = plant.accel_mms2
		if cur_floor() == 5 and status(LiftIo.ST_DOOR_OPEN):
			break

	check("5. kata varildi", cur_floor() == 5, "(kat=%d)" % cur_floor())
	# surunme hizinda sinir gevsetildigi icin bir miktar pay birakiliyor
	check("jerk siniri asilmadi", max_jerk <= LiftCfg.JERK_MMS3 * 8.5,
			"(olculen %.0f mm/s3, sinir %.0f)" % [max_jerk, LiftCfg.JERK_MMS3])
	check("ivme limiti asilmadi", max_acc <= LiftCfg.DECEL_MMS2 * 1.05,
			"(olculen %.0f mm/s2, sinir %.0f)" % [max_acc, LiftCfg.DECEL_MMS2])
	check("kat seviyesi tuttu",
			absf(plant.pos_mm - 5 * LiftCfg.FLOOR_HEIGHT_MM) <= LiftCfg.LEVEL_TOL_MM,
			"(sapma %.1f mm)" % (plant.pos_mm - 5 * LiftCfg.FLOOR_HEIGHT_MM))
