class_name AudioRig
extends Node3D

## Asansor sesleri — tamami calisma aninda sentezlenir (harici ses dosyasi yok).
##
## Kaynaklar konumludur (AudioStreamPlayer3D):
##   - tahrik makinesi ugultusu  : kuyunun tepesinde, hiza gore perde/ses degisir
##   - kapi motoru               : kabinle birlikte hareket eder
##   - gong / alarm / fren       : kabinde
##
## Sesler PLC cikislarindan surulur; yani duydugunuz sey kumandanin gercek
## durumudur, animasyon suslemesi degil.

const RATE := 22050

var machine: AudioStreamPlayer3D      # surekli dongu, hiza gore modulasyon
var door: AudioStreamPlayer3D         # kapi hareket ederken dongu
var chime: AudioStreamPlayer3D        # varis gongu (tek atim)
var alarm: AudioStreamPlayer3D        # alarm zili (dongu)
var click: AudioStreamPlayer3D        # fren tutma/cozme tiki

var _prev_brake := false
var _prev_gong := false
var _prev_alarm := false


func build(car_node: Node3D, machine_pos: Vector3) -> void:
	machine = _mk(self, _hum(), machine_pos, -14.0, 22.0)
	machine.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	machine.stream.loop_end = machine.stream.data.size() / 2 - 1
	machine.play()
	machine.volume_db = -80.0

	door = _mk(car_node, _door_motor(), Vector3(0, 1.0, 1.0), -18.0, 12.0)
	door.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	door.stream.loop_end = door.stream.data.size() / 2 - 1
	door.play()
	door.volume_db = -80.0

	chime = _mk(car_node, _chime(), Vector3(0, 2.2, 0), -6.0, 16.0)
	alarm = _mk(car_node, _bell(), Vector3(0, 1.6, 0.8), -10.0, 16.0)
	alarm.stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	alarm.stream.loop_end = alarm.stream.data.size() / 2 - 1
	click = _mk(car_node, _click(), Vector3(0, 2.4, 0), -8.0, 14.0)


func _mk(parent: Node3D, stream: AudioStreamWAV, pos: Vector3,
		vol_db: float, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.position = pos
	p.volume_db = vol_db
	p.max_distance = max_dist
	p.unit_size = 4.0
	parent.add_child(p)
	return p


# =============================================================================
# CANLI GUNCELLEME
# =============================================================================
func update(plant: LiftPlant, status: int, delta: float) -> void:
	var spd := absf(plant.speed_mms)

	# --- makine ugultusu: hiz arttikca perde ve ses yukselir ---------------
	if spd > 5.0 and plant.powered:
		var f := clampf(spd / float(LiftCfg.V_RATED_MMS), 0.0, 1.3)
		machine.pitch_scale = 0.55 + 0.75 * f
		machine.volume_db = lerpf(machine.volume_db, -26.0 + 14.0 * f,
				minf(1.0, delta * 8.0))
	else:
		machine.volume_db = lerpf(machine.volume_db, -80.0, minf(1.0, delta * 6.0))

	# --- kapi motoru --------------------------------------------------------
	var door_moving: bool = (plant.c_door_open or plant.c_door_close) \
			and plant.door_pos > 0.001 and plant.door_pos < 0.999
	door.volume_db = lerpf(door.volume_db, -22.0 if door_moving else -80.0,
			minf(1.0, delta * 14.0))

	# --- gong (yukselen kenar) ---------------------------------------------
	var g := LiftIo.get_bit(status, LiftIo.ST_GONG)
	if g and not _prev_gong:
		chime.play()
	_prev_gong = g

	# --- alarm zili ---------------------------------------------------------
	var a := LiftIo.get_bit(status, LiftIo.ST_ALARM)
	if a and not _prev_alarm:
		alarm.play()
	elif not a and _prev_alarm:
		alarm.stop()
	_prev_alarm = a

	# --- fren tiki (durum degisiminde) --------------------------------------
	if plant.brake_engaged != _prev_brake:
		click.play()
		_prev_brake = plant.brake_engaged


# =============================================================================
# SENTEZ
# =============================================================================
static func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


## Dislisiz makine ugultusu: dusuk temel + harmonikler + hafif gurultu
static func _hum() -> AudioStreamWAV:
	var n := RATE / 2                      # 0.5 s dongu
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	# dongunun kusursuz kapanmasi icin frekanslar tam periyot sayisi olmali
	for i in n:
		var ph := TAU * float(i) / float(n)
		var v := 0.55 * sin(ph * 24.0)        # ~48 Hz temel
		v += 0.28 * sin(ph * 48.0)            # 2. harmonik
		v += 0.14 * sin(ph * 72.0)            # 3. harmonik
		v += 0.07 * sin(ph * 145.0)           # surucu anahtarlama tinisi
		v += rng.randf_range(-0.05, 0.05)     # yatak/hava gurultusu
		s[i] = v * 0.5
	return _wav(s)


## Kapi operatoru: kayis + redüktor sesi
static func _door_motor() -> AudioStreamWAV:
	var n := RATE / 2
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	var lp := 0.0
	for i in n:
		var ph := TAU * float(i) / float(n)
		# alcak gecirgen suzulmus gurultu (surtunme) + hafif tonal bilesen
		lp = lp * 0.86 + rng.randf_range(-1.0, 1.0) * 0.14
		var v := lp * 0.8 + 0.18 * sin(ph * 96.0) + 0.10 * sin(ph * 192.0)
		s[i] = v * 0.45
	return _wav(s)


## Varis gongu: iki notali, sonumlenen (gercek asansor chime'i)
static func _chime() -> AudioStreamWAV:
	var dur := 1.1
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var f1 := 880.0        # A5
	var f2 := 660.0        # E5
	var split := int(n * 0.34)
	for i in n:
		var t := float(i) / float(RATE)
		var v := 0.0
		# birinci nota
		var e1: float = exp(-t * 4.2)
		v += e1 * (sin(TAU * f1 * t) + 0.35 * sin(TAU * f1 * 2.0 * t))
		# ikinci nota (gecikmeli)
		if i > split:
			var t2 := float(i - split) / float(RATE)
			var e2: float = exp(-t2 * 3.6)
			v += e2 * (sin(TAU * f2 * t2) + 0.30 * sin(TAU * f2 * 2.0 * t2))
		s[i] = v * 0.30
	return _wav(s)


## Alarm zili: kesikli calan tiz ton
static func _bell() -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / float(RATE)
		# 0.25 s acik / 0.25 s kapali
		var gate := 1.0 if fmod(t, 0.5) < 0.25 else 0.0
		var v := sin(TAU * 900.0 * t) + 0.4 * sin(TAU * 1800.0 * t)
		s[i] = v * gate * 0.22
	return _wav(s)


## Fren tiki: kisa, sert gurultu atimi
static func _click() -> AudioStreamWAV:
	var n := int(RATE * 0.07)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in n:
		var t := float(i) / float(RATE)
		var e: float = exp(-t * 90.0)
		s[i] = (rng.randf_range(-1.0, 1.0) * 0.6 + sin(TAU * 180.0 * t) * 0.4) * e * 0.5
	return _wav(s)
