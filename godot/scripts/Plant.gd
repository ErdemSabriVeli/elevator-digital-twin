class_name LiftPlant
extends RefCounted

## Fiziksel tesis modeli (plant) — dijital ikizin "gercek dunya" tarafi.
##
## PLC cikislarini (surucu / kapi komutlari) alir, kabin ve kapi hareketini
## entegre eder, karsiliginda saha sensorlerini (encoder, kat sensoru, limit
## switch, kapi limitleri, kilit kontagi) uretir.
##
## PLC bu modelde HICBIR sey hesaplamaz; PLC sadece kumanda eder.

# --- durum -------------------------------------------------------------------
var pos_mm := 0.0                 # kabin mutlak konumu
var speed_mms := 0.0              # isaretli: + yukari
var accel_mms2 := 0.0             # anlik ivme (S-egrisi profili icin)
var door_pos := 0.0               # 0 = tam kapali, 1 = tam acik
var load_kg := 75

# --- arıza / mod enjeksiyonu (HUD'dan degistirilir) --------------------------
var sw_estop := false
var sw_safety_chain := true       # false = zincir koptu
var sw_governor_ok := true
var sw_drive_fault := false
var sw_fire := false
var sw_inspection := false
var sw_obstruction := false       # foto bariyer surekli kesik
var sw_rope_slip := false         # encoder kaymasi simulasyonu
var sw_brake_stuck := false       # fren mekanik olarak takili kaldi
var sw_overspeed := false         # surucu kacagi -> asiri hiz
var sw_car_jammed := false        # kabin sikisti / halat tamamen kayiyor

const BRAKE_RESPONSE_S := 0.15    # fren bobininin tepki suresi
var _brake_t := 0.0

# --- PLC komutlari (son alinan) ---------------------------------------------
var c_drive_enable := false
var c_run_up := false
var c_run_down := false
var c_brake := false
var c_speed_sp := 0
var c_door_open := false
var c_door_close := false
var c_door_nudge := false

# --- momentary butonlar ------------------------------------------------------
var _pulse := {}                  # anahtar -> kalan sure

# --- olcum / gozlem ----------------------------------------------------------
var brake_engaged := true
var powered := false              # surucu gercekten tork uretiyor mu
var travel_distance_mm := 0.0
var trip_count := 0
var _was_moving := false


func _init() -> void:
	pos_mm = float(LiftCfg.PARK_FLOOR * LiftCfg.FLOOR_HEIGHT_MM)


# =============================================================================
# BUTONLAR
# =============================================================================
func press(key: String) -> void:
	_pulse[key] = LiftCfg.BTN_PULSE_S

func hold(key: String, on: bool) -> void:
	if on:
		_pulse[key] = 0.05      # her karede yenilenir
	else:
		_pulse.erase(key)

func is_pressed(key: String) -> bool:
	return _pulse.has(key)

func _tick_buttons(dt: float) -> void:
	for k in _pulse.keys():
		_pulse[k] -= dt
		if _pulse[k] <= 0.0:
			_pulse.erase(k)


# =============================================================================
# PLC CIKISLARINI UYGULA
# =============================================================================
func apply_outputs(o: PackedInt32Array) -> void:
	if o.size() < LiftIo.REG_COUNT:
		return
	var d := o[LiftIo.OUT_DRIVE_CMD]
	c_drive_enable = LiftIo.get_bit(d, LiftIo.DRV_ENABLE)
	c_run_up = LiftIo.get_bit(d, LiftIo.DRV_UP)
	c_run_down = LiftIo.get_bit(d, LiftIo.DRV_DOWN)
	c_brake = LiftIo.get_bit(d, LiftIo.DRV_BRAKE)
	c_speed_sp = o[LiftIo.OUT_SPEED_SP]

	var dc := o[LiftIo.OUT_DOOR_CMD]
	c_door_open = LiftIo.get_bit(dc, LiftIo.DOOR_OPEN_CMD)
	c_door_close = LiftIo.get_bit(dc, LiftIo.DOOR_CLOSE_CMD)
	c_door_nudge = LiftIo.get_bit(dc, LiftIo.DOOR_NUDGE_CMD)


# =============================================================================
# FIZIK ADIMI
# =============================================================================
func step(dt: float) -> void:
	_tick_buttons(dt)

	# --- surucu -> hedef hiz ---------------------------------------------
	# --- fren: komuta gecikmeli tepki verir (bobin akimi + yay) -------------
	# sw_brake_stuck acikken fren mekanik olarak takili kalir; kumanda cozme
	# emri verse de geri besleme gelmez -> PLC fren arizasi gorur.
	if sw_brake_stuck:
		_brake_t = 0.0
		brake_engaged = true
	elif c_brake != (not brake_engaged):
		_brake_t += dt
		if _brake_t >= BRAKE_RESPONSE_S:
			_brake_t = 0.0
			brake_engaged = not c_brake
	else:
		_brake_t = 0.0

	var v_target := 0.0
	powered = c_drive_enable and not brake_engaged \
			and not sw_estop and sw_safety_chain

	# sw_overspeed: surucu kacagi — gercek hiz referansi asar, regulator
	# devreye girmelidir.
	var v_ref := float(c_speed_sp)
	if sw_overspeed:
		v_ref *= 1.45

	if powered:
		if c_run_up and not c_run_down:
			v_target = v_ref
		elif c_run_down and not c_run_up:
			v_target = -v_ref

	# --- S-egrisi hiz profili (jerk sinirli) --------------------------------
	# Gercek asansor surucusu ivmeyi bir anda uygulamaz; ivmenin degisim hizi
	# (jerk) sinirlidir. Yolcunun "sarsilma" hissetmemesinin sebebi budur ve
	# kalkis/durusun karakteristik yumusakligini bu verir.
	#
	#   a_stop = sqrt(2 * jerk * |hata|)  -> ivmeyi sifira indirmeye yetecek
	#   deger; hedefe yaklasirken ivme kendiliginden geri cekilir, asma olmaz.
	var a_max := LiftCfg.ACCEL_MMS2
	if absf(v_target) < absf(speed_mms):
		a_max = LiftCfg.DECEL_MMS2
	var jerk := LiftCfg.JERK_MMS3

	# Jerk siniri bir KONFOR kisitidir ve yalnizca yolcunun hissettigi
	# hizlarda anlamlidir. Surunme (seviyeleme) hizinda gercek surucu de
	# hizli tepki verir; burada da sinirlamayi gevsetiyoruz, aksi halde
	# kabin kat seviyesini asar ve etrafinda salinir.
	var creep := LiftCfg.V_LEVEL_MMS * 1.3
	if absf(speed_mms) <= creep and absf(v_target) <= creep:
		jerk = LiftCfg.JERK_MMS3 * 8.0

	if not powered:
		# FREN: surtunme elemanidir. Hizi sifira ceker ve orada birakir;
		# kabini ters yone SUREMEZ. Bu yuzden jerk entegratoru burada
		# kullanilmaz (kullanilirsa ivme sifiri asar ve kabin geri gider).
		accel_mms2 = 0.0
		speed_mms = move_toward(speed_mms, 0.0, LiftCfg.DECEL_MMS2 * 3.0 * dt)
	else:
		var v_err := v_target - speed_mms
		var a_cmd := 0.0
		if absf(v_err) > 0.001:
			var a_stop := sqrt(2.0 * jerk * absf(v_err))
			a_cmd = signf(v_err) * minf(a_max, a_stop)
			# Tek adimda hedefi gecirecek ivmeyi komut etme. (Hedefi gectikten
			# sonra ivmeyi sifira ZORLAMAK, jerk sinirini kendi elimizle ihlal
			# etmek olurdu; bunun yerine komutu bastan siniriyoruz.)
			var a_reach := v_err / dt
			if absf(a_cmd) > absf(a_reach):
				a_cmd = a_reach

		accel_mms2 = move_toward(accel_mms2, a_cmd, jerk * dt)
		speed_mms += accel_mms2 * dt

	# --- konum entegrasyonu ------------------------------------------------
	var slip := 1.0
	if sw_car_jammed:
		slip = 0.0                           # kabin ilerlemiyor -> hareket zaman asimi
	elif sw_rope_slip and absf(speed_mms) > 10.0:
		slip = 0.92                          # halat kaymasi -> encoder sapmasi
	var d_mm := speed_mms * dt * slip
	pos_mm += d_mm
	travel_distance_mm += absf(d_mm)

	# --- mekanik siniri (tampon) -------------------------------------------
	var pos_min := -float(LiftCfg.OVERTRAVEL_MM) - 100.0
	var pos_max := float(LiftCfg.TOP_FLOOR * LiftCfg.FLOOR_HEIGHT_MM + LiftCfg.OVERTRAVEL_MM) + 100.0
	if pos_mm <= pos_min:
		pos_mm = pos_min
		speed_mms = 0.0
	elif pos_mm >= pos_max:
		pos_mm = pos_max
		speed_mms = 0.0

	# --- kapi --------------------------------------------------------------
	# Kapi motoru yalnizca kabin neredeyse duruyorken calisir (mekanik kavrama).
	#
	# Gercek kapi operatoru sabit hizla surmez: kapali/acik uclarda yavaslar,
	# ortada hizlanir. Bu hem mekanigi korur hem carpma sesini onler. Hiz
	# carpani konuma bagli bir yarim-sinus zarfiyla modellenir.
	if absf(speed_mms) < 100.0:
		var env: float = 0.35 + 0.65 * sin(PI * clampf(door_pos, 0.0, 1.0))
		if c_door_open:
			door_pos = minf(1.0, door_pos + env * dt / LiftCfg.DOOR_OPEN_TIME)
		elif c_door_close:
			var sp := env * dt / LiftCfg.DOOR_CLOSE_TIME
			if c_door_nudge:
				sp *= LiftCfg.DOOR_NUDGE_SCALE
			door_pos = maxf(0.0, door_pos - sp)

	# --- sefer sayaci ------------------------------------------------------
	var mv := absf(speed_mms) > 5.0
	if _was_moving and not mv:
		trip_count += 1
	_was_moving = mv


# =============================================================================
# SENSORLER -> MODBUS HOLDING REGISTERS
# =============================================================================
func build_registers(heartbeat: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	r.resize(LiftIo.REG_COUNT)

	# --- cagri butonlari ---------------------------------------------------
	var up := 0
	var dn := 0
	var car := 0
	for f in range(LiftCfg.FLOOR_COUNT):
		if is_pressed("hall_up_%d" % f):
			up = LiftIo.set_bit(up, f, true)
		if is_pressed("hall_down_%d" % f):
			dn = LiftIo.set_bit(dn, f, true)
		if is_pressed("car_%d" % f):
			car = LiftIo.set_bit(car, f, true)
	r[LiftIo.IN_HALL_UP] = up
	r[LiftIo.IN_HALL_DOWN] = dn
	r[LiftIo.IN_CAR_CALL] = car

	# --- komut bitleri -----------------------------------------------------
	var overload := load_kg > LiftCfg.LOAD_OVER_KG
	var cmd := 0
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DOOR_OPEN, is_pressed("door_open"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DOOR_CLOSE, is_pressed("door_close"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_ALARM, is_pressed("alarm"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_ESTOP, sw_estop)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_OVERLOAD, overload)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_FIRE, sw_fire)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_INSPECTION, sw_inspection)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_RESET, is_pressed("reset"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_OBSTRUCTION, _obstructed())
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DRIVE_READY, not sw_drive_fault)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_DRIVE_FAULT, sw_drive_fault)
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_INSP_UP, is_pressed("insp_up"))
	cmd = LiftIo.set_bit(cmd, LiftIo.CMD_INSP_DOWN, is_pressed("insp_down"))
	r[LiftIo.IN_CMD] = cmd

	# --- kat (door zone) sensorleri ----------------------------------------
	var zone := 0
	for f in range(LiftCfg.FLOOR_COUNT):
		if absf(pos_mm - f * LiftCfg.FLOOR_HEIGHT_MM) <= LiftCfg.DOOR_ZONE_MM:
			zone = LiftIo.set_bit(zone, f, true)
	r[LiftIo.IN_FLOOR_ZONE] = zone

	# --- limitler ve kilit -------------------------------------------------
	var top_lim := pos_mm >= float(LiftCfg.TOP_FLOOR * LiftCfg.FLOOR_HEIGHT_MM + LiftCfg.OVERTRAVEL_MM)
	var bot_lim := pos_mm <= -float(LiftCfg.OVERTRAVEL_MM)
	var d_open := door_pos >= 0.995
	var d_close := door_pos <= 0.005
	# Kat kapisi kilit zinciri: kapi tam kapali VE kabin bir kat bolgesinde
	# degilse de kilitli sayilir (kapi kuyuda acilamaz).
	var locked := d_close

	var lim := 0
	lim = LiftIo.set_bit(lim, LiftIo.LIM_TOP, top_lim)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_BOTTOM, bot_lim)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_DOOR_OPEN, d_open)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_DOOR_CLOSE, d_close)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_DOOR_LOCK, locked)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_BRAKE_FB, not brake_engaged)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_SAFETY, sw_safety_chain and not sw_estop)
	lim = LiftIo.set_bit(lim, LiftIo.LIM_GOVERNOR, sw_governor_ok)
	r[LiftIo.IN_LIMITS] = lim

	# --- analog ------------------------------------------------------------
	r[LiftIo.IN_POS_MM] = clampi(int(round(pos_mm)), 0, 65535)
	r[LiftIo.IN_SPEED_MMS] = clampi(int(absf(speed_mms)), 0, 65535)
	r[LiftIo.IN_DOOR_PMIL] = clampi(int(door_pos * 1000.0), 0, 1000)
	r[LiftIo.IN_LOAD_KG] = clampi(load_kg, 0, 65535)
	r[LiftIo.IN_HEARTBEAT] = heartbeat & 0x7FFF

	return r


func _obstructed() -> bool:
	# Elle acilan foto bariyer veya "yolcu geciyor" darbesi
	return sw_obstruction or is_pressed("obstruct")


# =============================================================================
# Yardimcilar (gorsel taraf icin)
# =============================================================================
func car_y() -> float:
	return pos_mm * 0.001

func nearest_floor() -> int:
	return clampi(int(round(pos_mm / LiftCfg.FLOOR_HEIGHT_MM)), 0, LiftCfg.TOP_FLOOR)

func counterweight_y() -> float:
	# 1:1 aski: kabin yukari cikarken karsi agirlik asagi iner.
	# Ofset, kabin en ustteyken agirligin kuyu dibi tamponuna oturmayacak
	# sekilde secilir (bkz. tests/geometry_test.gd).
	var top := float(LiftCfg.TOP_FLOOR) * LiftCfg.M_FLOOR_H
	return top - car_y() - 0.10
