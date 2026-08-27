extends SceneTree

## ModbusClient protocol test.
##
## A minimal Modbus TCP slave (imitating the CODESYS "Modbus TCP Slave Device")
## is brought up on Godot's own TCPServer; ModbusClient writes to it with FC16
## and reads from it with FC04. Frame building and parsing are verified.
##
## Run with:
##   godot --headless --path <godot folder> --script res://tests/modbus_test.gd

const PORT := 15020

var server := TCPServer.new()
var peer: StreamPeerTCP
var rx := PackedByteArray()

# The register area on the slave side
var holding := PackedInt32Array()      # the master writes  (PLC %IW)
var input_regs := PackedInt32Array()   # the master reads   (PLC %QW)

var failures := 0
var write_count := 0
var read_count := 0
var last_read := PackedInt32Array()   # lambdas cannot write to an outer local, so keep it as a member


func _initialize() -> void:
	print("=== MODBUS TCP PROTOCOL TEST ===\n")

	holding.resize(16)
	input_regs.resize(16)
	# let the slave prepare the fixed values to be read
	for i in 16:
		input_regs[i] = 1000 + i * 7

	var err := server.listen(PORT, "127.0.0.1")
	check("slave listening (port %d)" % PORT, err == OK, "(err=%s)" % error_string(err))
	if err != OK:
		quit(1)
		return

	var client := ModbusClient.new()
	client.open("127.0.0.1", PORT, 1)

	# --- connection ---------------------------------------------------------
	var connected := pump(func(): return client.online, client, 3.0)
	check("master connected", connected)

	# --- FC16: write multiple registers -------------------------------------
	var vals := [0x0021, 0x0004, 0x0008, 0x0200, 0x0010, 0x00D8,
			9600, 1600, 1000, 75, 1234]
	client.queue_write(0, vals)
	var written := pump(func(): return write_count > 0, client, 3.0)
	check("FC16 write response received", written)

	var ok_vals := true
	var detail := ""
	for i in range(vals.size()):
		if holding[i] != vals[i]:
			ok_vals = false
			detail = "(reg%d: expected %d, got %d)" % [i, vals[i], holding[i]]
			break
	check("the 11 written registers reached the slave intact", ok_vals, detail)

	# --- FC04: read input registers -----------------------------------------
	client.queue_read(0, 16, ModbusClient.FC_READ_INPUT)
	var read_ok := pump(func(): return read_count > 0, client, 3.0)
	var got := last_read
	check("FC04 read response received", read_ok)
	check("16 registers returned", got.size() == 16, "(got=%d)" % got.size())

	var ok_read := got.size() == 16
	if ok_read:
		for i in 16:
			if got[i] != input_regs[i]:
				ok_read = false
				detail = "(reg%d: expected %d, got %d)" % [i, input_regs[i], got[i]]
				break
	check("the values read back are correct", ok_read, detail)

	# --- 16-bit boundary values ---------------------------------------------
	client.queue_write(0, [0xFFFF, 0x8000, 0x0001, 0x0000])
	pump(func(): return write_count > 1, client, 3.0)
	check("16-bit boundary values preserved",
			holding[0] == 0xFFFF and holding[1] == 0x8000
			and holding[2] == 1 and holding[3] == 0,
			"(%d %d %d %d)" % [holding[0], holding[1], holding[2], holding[3]])

	# --- statistics ---------------------------------------------------------
	check("tx/rx counters agree", client.stat_tx == client.stat_rx,
			"(tx=%d rx=%d, timeout=%d)" % [client.stat_tx, client.stat_rx, client.stat_timeout])
	check("no timeouts", client.stat_timeout == 0)

	client.close()
	print("\n=== RESULT: %s ===" % ("ALL TESTS PASSED" if failures == 0
			else "%d TESTS FAILED" % failures))
	quit(1 if failures > 0 else 0)


# =============================================================================
## Turns the slave and the master together until the condition is met.
func pump(cond: Callable, client: ModbusClient, timeout: float) -> bool:
	var t := 0.0
	while t < timeout:
		_serve()
		client.poll()
		while true:
			var r = client.pop_response()
			if r == null:
				break
			if r.has("fc") and r.ok:
				if r.fc == ModbusClient.FC_WRITE_MULTI:
					write_count += 1
				elif r.fc == ModbusClient.FC_READ_INPUT or r.fc == ModbusClient.FC_READ_HOLDING:
					read_count += 1
					if r.has("values"):
						last_read = r.values
		if cond.call():
			return true
		OS.delay_msec(4)
		t += 0.004
	return false


## Minimal Modbus TCP slave
func _serve() -> void:
	if peer == null and server.is_connection_available():
		peer = server.take_connection()
		peer.set_no_delay(true)
	if peer == null:
		return

	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return

	var avail := peer.get_available_bytes()
	if avail > 0:
		var res := peer.get_data(avail)
		if res[0] == OK:
			rx.append_array(res[1])

	while rx.size() >= 8:
		var length := (rx[4] << 8) | rx[5]
		var total := 6 + length
		if rx.size() < total:
			return
		var f := rx.slice(0, total)
		rx = rx.slice(total)
		_handle(f)


func _handle(f: PackedByteArray) -> void:
	var tid := (f[0] << 8) | f[1]
	var uid := f[6]
	var fc := f[7]
	var start := (f[8] << 8) | f[9]

	var pdu := PackedByteArray()

	match fc:
		4, 3:   # read input / holding registers
			var qty := (f[10] << 8) | f[11]
			var src := input_regs if fc == 4 else holding
			pdu.append(fc)
			pdu.append(qty * 2)
			for i in range(qty):
				var v: int = src[start + i] if (start + i) < src.size() else 0
				pdu.append((v >> 8) & 0xFF)
				pdu.append(v & 0xFF)

		16:     # write multiple registers
			var qty2 := (f[10] << 8) | f[11]
			for i in range(qty2):
				var hi := f[13 + i * 2]
				var lo := f[14 + i * 2]
				if start + i < holding.size():
					holding[start + i] = (hi << 8) | lo
			pdu.append(fc)
			pdu.append((start >> 8) & 0xFF)
			pdu.append(start & 0xFF)
			pdu.append((qty2 >> 8) & 0xFF)
			pdu.append(qty2 & 0xFF)

		6:      # write single register
			var v2 := (f[10] << 8) | f[11]
			if start < holding.size():
				holding[start] = v2
			pdu.append_array(f.slice(7, 12))

		_:
			pdu.append(fc | 0x80)
			pdu.append(0x01)   # illegal function

	var out := PackedByteArray()
	out.append((tid >> 8) & 0xFF)
	out.append(tid & 0xFF)
	out.append(0)
	out.append(0)
	var ln := pdu.size() + 1
	out.append((ln >> 8) & 0xFF)
	out.append(ln & 0xFF)
	out.append(uid)
	out.append_array(pdu)
	peer.put_data(out)


func check(name: String, ok: bool, detail := "") -> void:
	if ok:
		print("  [ ok  ] %s %s" % [name, detail])
	else:
		failures += 1
		print("  [FAIL ] %s %s" % [name, detail])
