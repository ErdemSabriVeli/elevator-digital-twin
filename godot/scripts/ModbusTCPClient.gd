class_name ModbusClient
extends RefCounted

## Minimal non-blocking Modbus TCP master.
## Supported function codes:
##   FC03  Read Holding Registers
##   FC04  Read Input Registers
##   FC06  Write Single Register
##   FC16  Write Multiple Registers
##
## Usage:
##   var c := ModbusClient.new()
##   c.open("127.0.0.1", 502)
##   ... every frame:  c.poll()
##   c.queue_write(0, values)     # FC16
##   c.queue_read(0, 16, 4)       # FC04
##   while true: var r = c.pop_response(); if r == null: break; ...

signal state_changed(online: bool)

const FC_READ_HOLDING  := 3
const FC_READ_INPUT    := 4
const FC_WRITE_SINGLE  := 6
const FC_WRITE_MULTI   := 16

const RESP_TIMEOUT_MS  := 1500
const RECONNECT_MS     := 2000
const MAX_QUEUE        := 8

var host := "127.0.0.1"
var port := 502
var unit_id := 1

var online := false
var last_error := ""
var stat_tx := 0
var stat_rx := 0
var stat_timeout := 0
var rtt_ms := 0

var _sock := StreamPeerTCP.new()
var _rx := PackedByteArray()
var _queue: Array = []          # pending requests
var _inflight = null            # sent, awaiting a response
var _sent_at := 0
var _next_try := 0
var _tid := 0
var _responses: Array = []
var _want_open := false


func open(p_host: String, p_port: int, p_unit: int = 1) -> void:
	host = p_host
	port = p_port
	unit_id = p_unit
	_want_open = true
	_next_try = 0
	_reconnect()


func close() -> void:
	_want_open = false
	_sock.disconnect_from_host()
	_set_online(false)
	_queue.clear()
	_inflight = null
	_rx.clear()


func queue_read(start: int, count: int, fc: int = FC_READ_INPUT) -> void:
	if _queue.size() >= MAX_QUEUE:
		return
	_queue.append({ "fc": fc, "start": start, "count": count })


func queue_write(start: int, values: Array) -> void:
	if _queue.size() >= MAX_QUEUE:
		return
	_queue.append({ "fc": FC_WRITE_MULTI, "start": start, "values": values.duplicate() })


func pending() -> int:
	return _queue.size() + (1 if _inflight != null else 0)


func pop_response():
	if _responses.is_empty():
		return null
	return _responses.pop_front()


# =============================================================================
func poll() -> void:
	if not _want_open:
		return

	_sock.poll()
	var st := _sock.get_status()

	match st:
		StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR:
			_set_online(false)
			var now := Time.get_ticks_msec()
			if now >= _next_try:
				_next_try = now + RECONNECT_MS
				_reconnect()

		StreamPeerTCP.STATUS_CONNECTING:
			_set_online(false)

		StreamPeerTCP.STATUS_CONNECTED:
			if not online:
				_sock.set_no_delay(true)
				_rx.clear()
				_inflight = null
				_set_online(true)
			_receive()
			_check_timeout()
			_send_next()


# =============================================================================
func _reconnect() -> void:
	_sock = StreamPeerTCP.new()
	var err := _sock.connect_to_host(host, port)
	if err != OK:
		last_error = "connect_to_host: %s" % error_string(err)


func _set_online(v: bool) -> void:
	if v != online:
		online = v
		if not v:
			_inflight = null
			_rx.clear()
		state_changed.emit(v)


func _send_next() -> void:
	if _inflight != null or _queue.is_empty():
		return

	var req = _queue.pop_front()
	_tid = (_tid + 1) & 0xFFFF

	var pdu := PackedByteArray()
	match req.fc:
		FC_READ_HOLDING, FC_READ_INPUT:
			pdu.append(req.fc)
			pdu.append((req.start >> 8) & 0xFF)
			pdu.append(req.start & 0xFF)
			pdu.append((req.count >> 8) & 0xFF)
			pdu.append(req.count & 0xFF)

		FC_WRITE_MULTI:
			var n: int = req.values.size()
			pdu.append(req.fc)
			pdu.append((req.start >> 8) & 0xFF)
			pdu.append(req.start & 0xFF)
			pdu.append((n >> 8) & 0xFF)
			pdu.append(n & 0xFF)
			pdu.append(n * 2)
			for v in req.values:
				var w: int = int(v) & 0xFFFF
				pdu.append((w >> 8) & 0xFF)
				pdu.append(w & 0xFF)

		FC_WRITE_SINGLE:
			pdu.append(req.fc)
			pdu.append((req.start >> 8) & 0xFF)
			pdu.append(req.start & 0xFF)
			var v0: int = int(req.values[0]) & 0xFFFF
			pdu.append((v0 >> 8) & 0xFF)
			pdu.append(v0 & 0xFF)
		_:
			return

	# MBAP header
	var frame := PackedByteArray()
	frame.append((_tid >> 8) & 0xFF)
	frame.append(_tid & 0xFF)
	frame.append(0)                       # protocol id hi
	frame.append(0)                       # protocol id lo
	var length := pdu.size() + 1
	frame.append((length >> 8) & 0xFF)
	frame.append(length & 0xFF)
	frame.append(unit_id)
	frame.append_array(pdu)

	var err := _sock.put_data(frame)
	if err != OK:
		last_error = "put_data: %s" % error_string(err)
		_set_online(false)
		return

	req["tid"] = _tid
	_inflight = req
	_sent_at = Time.get_ticks_msec()
	stat_tx += 1


func _receive() -> void:
	var avail := _sock.get_available_bytes()
	if avail > 0:
		var res := _sock.get_data(avail)
		if res[0] == OK:
			_rx.append_array(res[1])

	while _rx.size() >= 8:
		var length := (_rx[4] << 8) | _rx[5]
		var total := 6 + length
		if _rx.size() < total:
			return
		var frame := _rx.slice(0, total)
		_rx = _rx.slice(total)
		_handle_frame(frame)


func _handle_frame(f: PackedByteArray) -> void:
	var tid := (f[0] << 8) | f[1]
	var fc := f[7]
	stat_rx += 1

	if _inflight == null or _inflight.tid != tid:
		return   # late / mismatched response

	var req = _inflight
	_inflight = null
	rtt_ms = Time.get_ticks_msec() - _sent_at

	# Exception response
	if (fc & 0x80) != 0:
		last_error = "Modbus exception fc=%d code=%d" % [fc & 0x7F, f[8] if f.size() > 8 else -1]
		_responses.append({ "ok": false, "fc": fc & 0x7F, "error": last_error })
		return

	match fc:
		FC_READ_HOLDING, FC_READ_INPUT:
			var bc := f[8]
			var vals := PackedInt32Array()
			var i := 9
			while i + 1 < 9 + bc:
				vals.append((f[i] << 8) | f[i + 1])
				i += 2
			_responses.append({
				"ok": true, "fc": fc, "start": req.start, "values": vals
			})

		FC_WRITE_MULTI, FC_WRITE_SINGLE:
			_responses.append({ "ok": true, "fc": fc, "start": req.start })


func _check_timeout() -> void:
	if _inflight == null:
		return
	if Time.get_ticks_msec() - _sent_at > RESP_TIMEOUT_MS:
		stat_timeout += 1
		last_error = "response timeout (fc=%d)" % _inflight.fc
		_inflight = null
		_sock.disconnect_from_host()
		_set_online(false)
		_next_try = Time.get_ticks_msec() + RECONNECT_MS
