class_name PlcLink
extends RefCounted

## Control layer selector:
##   Mode.SOFT    -> SoftPlc (the GDScript twin of the ST code, runs in Godot)
##   Mode.MODBUS  -> a real CODESYS PLC over Modbus TCP
##
## Both modes use the SAME register interface; the scene side does not know
## which one is running. F1 switches between them at run time.

signal mode_changed(mode: int)

enum Mode { SOFT, MODBUS }

var mode := Mode.SOFT
var soft := SoftPlc.new()
var mb := ModbusClient.new()

var host := "127.0.0.1"
var port := 502
var unit_id := 1

## Should SoftPlc take over when Modbus drops? (handy for demos)
var fallback_to_soft := true
var using_fallback := false

var out_regs := PackedInt32Array()
var in_regs := PackedInt32Array()
var heartbeat := 0

var _hb_acc := 0.0
var _scan_acc := 0.0
var scan_period := 0.02          # target PLC scan interval (MODBUS mode)
var last_exchange_ms := 0


func _init() -> void:
	out_regs.resize(LiftIo.REG_COUNT)
	in_regs.resize(LiftIo.REG_COUNT)


func set_mode(m: int) -> void:
	if m == mode:
		return
	mode = m
	using_fallback = false
	if mode == Mode.MODBUS:
		mb.open(host, port, unit_id)
	else:
		mb.close()
	mode_changed.emit(mode)


func online() -> bool:
	return mode == Mode.SOFT or mb.online


func status_text() -> String:
	if mode == Mode.SOFT:
		return "SoftPLC (ST twin)"
	if mb.online:
		return "CODESYS %s:%d  rtt %d ms" % [host, port, mb.rtt_ms]
	if using_fallback:
		return "CODESYS offline -> SoftPLC fallback"
	return "CODESYS %s:%d connecting..." % [host, port]


# =============================================================================
## One exchange: send the inputs, read back the outputs.
func exchange(regs_in: PackedInt32Array, dt: float) -> PackedInt32Array:
	in_regs = regs_in

	_hb_acc += dt
	while _hb_acc >= 0.05:
		_hb_acc -= 0.05
		heartbeat = (heartbeat + 1) % 32000

	if mode == Mode.SOFT:
		out_regs = soft.scan(regs_in, dt)
		return out_regs

	# --- MODBUS -------------------------------------------------------------
	mb.poll()

	_scan_acc += dt
	if mb.online and _scan_acc >= scan_period and mb.pending() == 0:
		_scan_acc = 0.0
		var w: Array = []
		for i in range(LiftIo.IN_HEARTBEAT + 1):
			w.append(regs_in[i])
		mb.queue_write(0, w)
		mb.queue_read(0, LiftIo.REG_COUNT, ModbusClient.FC_READ_INPUT)

	while true:
		var resp = mb.pop_response()
		if resp == null:
			break
		if resp.ok and resp.has("values"):
			var v: PackedInt32Array = resp.values
			for i in range(mini(v.size(), LiftIo.REG_COUNT)):
				out_regs[i] = v[i]
			last_exchange_ms = Time.get_ticks_msec()

	# --- fallback: let SoftPlc carry on when the link is down ---------------------------
	if not mb.online and fallback_to_soft:
		using_fallback = true
		out_regs = soft.scan(regs_in, dt)
	elif mb.online:
		using_fallback = false

	return out_regs


func close() -> void:
	mb.close()
