extends Node3D

## ELEVATOR DIGITAL TWIN — main scene
##
## The cycle (every physics frame):
##   1. Apply the PLC outputs to the plant   (drive / door commands)
##   2. Physics step                         (car and door motion)
##   3. Write the sensors into registers     (encoder, floor sensor, limits)
##   4. Send to the PLC, read the outputs    (SoftPLC or CODESYS/Modbus TCP)
##   5. Update the 3D scene and the HUD

var plant := LiftPlant.new()
var link := PlcLink.new()

var shaft: ShaftRig
var car: CarRig
var cam: CamRig
var hud: LiftHud
var audio: AudioRig

var regs_in := PackedInt32Array()
var regs_out := PackedInt32Array()

var _gong_t := 0.0
var _blink := 0.0

# --- profiling counters (--profile) -----------------------------------------
var _prof_on := false
var _prof_plant := 0
var _prof_plc := 0
var _prof_vis := 0
var _prof_hud := 0
var _prof_frames := 0


func _ready() -> void:
	regs_in.resize(LiftIo.REG_COUNT)
	regs_out.resize(LiftIo.REG_COUNT)

	_setup_environment()

	shaft = ShaftRig.new()
	shaft.name = "Shaft"
	add_child(shaft)
	shaft.build(_on_button)

	car = CarRig.new()
	car.name = "Car"
	add_child(car)
	car.build(_on_button)
	car.position.y = plant.car_y()

	cam = CamRig.new()
	cam.name = "CameraRig"
	add_child(cam)
	cam.car_node = car
	cam.mount_node = car.interior_cam_mount
	cam.machine_y = shaft.sheave_y
	cam.frame_all()

	audio = AudioRig.new()
	audio.name = "Audio"
	add_child(audio)
	audio.build(car, Vector3(0, shaft.sheave_y, -0.3))

	hud = LiftHud.new()
	add_child(hud)
	hud.btn_pressed.connect(_on_button)
	hud.sw_toggled.connect(_on_switch)
	hud.plc_mode_requested.connect(func(m): link.set_mode(m))
	hud.connect_requested.connect(func(h, p):
		link.host = h
		link.port = p
		link.set_mode(PlcLink.Mode.MODBUS)
		link.mb.open(h, p, link.unit_id))
	hud.load_changed.connect(func(kg): plant.load_kg = kg)
	hud.gear_release_requested.connect(func(): plant.release_safety_gear())
	hud.cam_requested.connect(func(m): cam.set_mode(m))
	hud.lobby_floor_changed.connect(func(f):
		cam.lobby_floor = f
		cam.set_mode(CamRig.Mode.LOBBY))

	print("[DigitalTwin] ready — running on the SoftPLC. ",
		"To connect CODESYS use HUD > CONTROL SOURCE > CODESYS.")

	# --- command line options ----------------------------------------------
	#   godot --path godot -- --plc modbus --host 192.168.1.10 --port 502
	var uargs := OS.get_cmdline_user_args()
	var i := uargs.find("--host")
	if i >= 0 and i + 1 < uargs.size():
		link.host = uargs[i + 1]
	i = uargs.find("--port")
	if i >= 0 and i + 1 < uargs.size():
		link.port = int(uargs[i + 1])
	i = uargs.find("--unit")
	if i >= 0 and i + 1 < uargs.size():
		link.unit_id = int(uargs[i + 1])
	i = uargs.find("--plc")
	if i >= 0 and i + 1 < uargs.size() and uargs[i + 1] == "modbus":
		link.set_mode(PlcLink.Mode.MODBUS)

	# Performance profiling:  godot --path godot -- --profile [seconds]
	if uargs.has("--profile"):
		var pi := uargs.find("--profile")
		var secs := 8.0
		if uargs.size() > pi + 1 and uargs[pi + 1].is_valid_float():
			secs = float(uargs[pi + 1])
		_profile_run(secs)

	# Automatic screenshot mode:  godot --path godot -- --shot <folder>
	if uargs.has("--shot"):
		var si := uargs.find("--shot")
		var dir := uargs[si + 1] if uargs.size() > si + 1 else "user://"
		_shot_sequence(dir)


# =============================================================================
func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.33, 0.47, 0.70)
	psm.sky_horizon_color = Color(0.74, 0.80, 0.87)
	psm.ground_bottom_color = Color(0.26, 0.27, 0.29)
	psm.ground_horizon_color = Color(0.52, 0.53, 0.55)
	psm.sun_angle_max = 12.0
	sky.sky_material = psm
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Sky ambient casts a blue tint indoors; blend it with a neutral grey.
	env.ambient_light_color = Color(0.86, 0.85, 0.83)
	env.ambient_light_sky_contribution = 0.45
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.95
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.10
	env.ssao_enabled = true
	env.ssao_intensity = 1.5
	# screen-space reflections for the stainless and mirror surfaces
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.fog_enabled = false

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -128, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.96, 0.90)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 42.0   # building is 21 m; a tight range = sharper shadows, fewer draw calls
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 62, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.75, 0.82, 1.0)
	fill.shadow_enabled = false
	add_child(fill)


# =============================================================================
func _physics_process(delta: float) -> void:
	if hud == null:
		return

	var t0 := 0
	if _prof_on:
		t0 = Time.get_ticks_usec()

	# 1) PLC outputs -> plant
	plant.apply_outputs(regs_out)

	# 2) physics
	plant.step(delta)

	# 3) sensors -> registers
	regs_in = plant.build_registers(link.heartbeat)

	var t1 := 0
	if _prof_on:
		t1 = Time.get_ticks_usec()

	# 4) PLC scan (SoftPLC or CODESYS)
	regs_out = link.exchange(regs_in, delta)

	var t2 := 0
	if _prof_on:
		t2 = Time.get_ticks_usec()

	# 5) visuals
	_update_visuals(delta)

	var t3 := 0
	if _prof_on:
		t3 = Time.get_ticks_usec()

	hud.update_view(plant, link, regs_in, regs_out, delta)

	if _prof_on:
		var t4 := Time.get_ticks_usec()
		_prof_plant += t1 - t0
		_prof_plc += t2 - t1
		_prof_vis += t3 - t2
		_prof_hud += t4 - t3
		_prof_frames += 1


func _update_visuals(delta: float) -> void:
	_blink += delta

	# --- car and doors ------------------------------------------------------
	car.position.y = plant.car_y()
	car.set_door(plant.door_pos)

	var zone_floor := -1
	for f in range(LiftCfg.FLOOR_COUNT):
		if absf(plant.pos_mm - f * LiftCfg.FLOOR_HEIGHT_MM) <= LiftCfg.DOOR_ZONE_MM * 4:
			zone_floor = f
			break
	for f in range(LiftCfg.FLOOR_COUNT):
		shaft.set_landing_door(f, plant.door_pos if f == zone_floor else 0.0)

	# --- ropes, counterweight, traction machine -----------------------------
	shaft.update_ropes(plant.car_y(), plant.counterweight_y())
	shaft.spin_sheave(plant.speed_mms, delta)
	shaft.set_brake(plant.c_brake)

	# --- lamps --------------------------------------------------------------
	var lu: int = regs_out[LiftIo.OUT_LAMP_UP]
	var ld: int = regs_out[LiftIo.OUT_LAMP_DOWN]
	var lc: int = regs_out[LiftIo.OUT_LAMP_CAR]
	for f in range(LiftCfg.FLOOR_COUNT):
		if shaft.hall_up[f] != null:
			shaft.hall_up[f].set_lit(LiftIo.get_bit(lu, f))
		if shaft.hall_down[f] != null:
			shaft.hall_down[f].set_lit(LiftIo.get_bit(ld, f))
		if f < car.floor_buttons.size():
			car.floor_buttons[f].set_lit(LiftIo.get_bit(lc, f))

	# --- indicators ---------------------------------------------------------
	var status: int = regs_out[LiftIo.OUT_STATUS]
	var cur: int = regs_out[LiftIo.OUT_CUR_FLOOR]
	var up_arrow := LiftIo.get_bit(status, LiftIo.ST_ARROW_UP)
	var dn_arrow := LiftIo.get_bit(status, LiftIo.ST_ARROW_DOWN)
	var moving := LiftIo.get_bit(status, LiftIo.ST_MOVING)

	var arrow := LiftIo.DIR_NONE
	if up_arrow:
		arrow = LiftIo.DIR_UP
	elif dn_arrow:
		arrow = LiftIo.DIR_DOWN

	var txt := LiftIo.floor_name(cur)

	if LiftIo.get_bit(status, LiftIo.ST_FAULT):
		# the indicator blinks on a fault
		txt = "-" if fmod(_blink, 1.0) < 0.5 else " "
		arrow = LiftIo.DIR_NONE
	elif LiftIo.get_bit(status, LiftIo.ST_RESCUE):
		txt = "E"
	elif LiftIo.get_bit(status, LiftIo.ST_FIRE):
		txt = "F"
	elif LiftIo.get_bit(status, LiftIo.ST_INSPECTION):
		txt = "R"

	for f in range(LiftCfg.FLOOR_COUNT):
		shaft.set_display(f, txt, arrow)
	car.set_display(txt, arrow)

	# --- car interior -------------------------------------------------------
	car.set_light(LiftIo.get_bit(status, LiftIo.ST_CABIN_LIGHT))
	car.set_overload(LiftIo.get_bit(status, LiftIo.ST_OVERLOAD))
	car.btn_alarm.set_lit(LiftIo.get_bit(status, LiftIo.ST_ALARM))
	car.set_load_text("%d kg / %d kg" % [plant.load_kg, LiftCfg.LOAD_FULL_KG])

	audio.update(plant, status, delta)

	# --- control panel LEDs -------------------------------------------------
	shaft.set_panel_leds([
		plant.c_drive_enable,
		moving,
		LiftIo.get_bit(status, LiftIo.ST_DOOR_OPEN),
		LiftIo.get_bit(status, LiftIo.ST_FAULT),
		link.online(),
		fmod(_blink, 1.0) < 0.5,
	])


# =============================================================================
func _on_button(key: String) -> void:
	plant.press(key)


func _on_switch(name: String, v: bool) -> void:
	match name:
		"estop": plant.sw_estop = v
		"safety": plant.sw_safety_chain = not v
		"drive": plant.sw_drive_fault = v
		"fire": plant.sw_fire = v
		"inspection": plant.sw_inspection = v
		"obstruction": plant.sw_obstruction = v
		"slip": plant.sw_rope_slip = v
		"brake": plant.sw_brake_stuck = v
		"overspeed": plant.sw_overspeed = v
		"jam": plant.sw_car_jammed = v
		"nocomp": plant.sw_no_load_comp = v
		"runaway": plant.sw_severe_runaway = v
		"mains": plant.sw_mains_fail = v


# =============================================================================
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_F1:
			link.set_mode(PlcLink.Mode.MODBUS if link.mode == PlcLink.Mode.SOFT
					else PlcLink.Mode.SOFT)
		KEY_F2:
			hud.toggle_visible()
		KEY_1:
			cam.set_mode(CamRig.Mode.ORBIT)
		KEY_2:
			cam.set_mode(CamRig.Mode.INTERIOR)
		KEY_3:
			cam.set_mode(CamRig.Mode.LOBBY)
		KEY_4:
			cam.set_mode(CamRig.Mode.MACHINE)
		KEY_F:
			cam.follow_car = not cam.follow_car
			cam.set_mode(CamRig.Mode.ORBIT)
		KEY_E:
			plant.sw_estop = not plant.sw_estop
			hud.set_switch("estop", plant.sw_estop)
		KEY_R:
			plant.press("reset")
		KEY_O:
			plant.press("door_open")
		KEY_C:
			plant.press("door_close")
		KEY_HOME:
			cam.frame_all()
		KEY_F12:
			_save_shot("user://elevator_%d.png" % Time.get_ticks_msec())


func _process(delta: float) -> void:
	# hold-to-run control in inspection mode
	if plant.sw_inspection:
		plant.hold("insp_up", Input.is_key_pressed(KEY_PAGEUP))
		plant.hold("insp_down", Input.is_key_pressed(KEY_PAGEDOWN))


func _exit_tree() -> void:
	link.close()


# =============================================================================
# Performance profiling (--profile)
# =============================================================================
func _profile_run(secs: float) -> void:
	# keep the elevator busy while measuring: start one trip
	plant.press("car_5")
	await get_tree().create_timer(1.0).timeout
	_prof_on = true

	var samples := 0
	var fps_sum := 0.0
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var draw_max := 0
	var prim_max := 0

	while Time.get_ticks_msec() < t_end:
		await get_tree().create_timer(0.25).timeout
		fps_sum += Performance.get_monitor(Performance.TIME_FPS)
		draw_max = maxi(draw_max,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		prim_max = maxi(prim_max,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		samples += 1

	print("\n===== PERFORMANCE PROFILE =====")
	print("Average FPS        : %.1f" % (fps_sum / maxf(1.0, float(samples))))
	print("Frame time (process): %.2f ms" % (Performance.get_monitor(
			Performance.TIME_PROCESS) * 1000.0))
	print("Frame time (physics): %.2f ms" % (Performance.get_monitor(
			Performance.TIME_PHYSICS_PROCESS) * 1000.0))
	print("Draw calls    (peak): %d" % draw_max)
	print("Primitives    (peak): %d" % prim_max)
	print("Objects            : %d" % int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	print("Nodes              : %d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print("Resources          : %d" % int(Performance.get_monitor(
			Performance.OBJECT_RESOURCE_COUNT)))
	print("Video memory       : %.1f MB" % (Performance.get_monitor(
			Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))

	var n := maxi(1, _prof_frames)
	print("--- _physics_process breakdown (%d frames) ---" % n)
	print("  plant model      : %6.3f ms" % (_prof_plant / float(n) / 1000.0))
	print("  PLC scan         : %6.3f ms" % (_prof_plc / float(n) / 1000.0))
	print("  3D update        : %6.3f ms" % (_prof_vis / float(n) / 1000.0))
	print("  HUD update       : %6.3f ms" % (_prof_hud / float(n) / 1000.0))
	print("  TOTAL (script)   : %6.3f ms" %
			((_prof_plant + _prof_plc + _prof_vis + _prof_hud) / float(n) / 1000.0))
	print("==============================")
	get_tree().quit()


# =============================================================================
# Screenshot (F12 or --shot)
# =============================================================================
func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[DigitalTwin] screenshot: ", ProjectSettings.globalize_path(path))


func _shot_sequence(dir: String) -> void:
	await get_tree().create_timer(1.2).timeout

	cam.frame_all()
	await get_tree().create_timer(1.0).timeout
	await _save_shot(dir.path_join("01-overview.png"))

	# call floor 3 and catch it while moving
	plant.press("car_3")
	cam.follow_car = true
	await get_tree().create_timer(4.0).timeout
	await _save_shot(dir.path_join("02-travelling.png"))

	# door open on arrival
	await get_tree().create_timer(4.0).timeout
	cam.set_mode(CamRig.Mode.LOBBY)
	cam.lobby_floor = 3
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("03-landing.png"))

	cam.set_mode(CamRig.Mode.INTERIOR)
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("04-car-interior.png"))

	cam.set_mode(CamRig.Mode.MACHINE)
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("05-machine-stopped.png"))

	# same machine with the car travelling: brake released, sheave turning
	plant.press("car_0")
	await get_tree().create_timer(4.5).timeout
	await _save_shot(dir.path_join("09-machine-running.png"))

	# let the car reach the ground floor and stop (framing drifts while moving)
	await get_tree().create_timer(9.0).timeout

	# car top: rope hitch + spring set + guard rail
	cam.target = Vector3(0, car.global_position.y + LiftCfg.M_CAR_H + 0.35, 0.0)
	cam.dist = 3.3
	cam.yaw = 74.0
	cam.pitch = -24.0
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("10-car-top.png"))

	# rope hitch close-up (plate + compression springs + sockets)
	cam.target = Vector3(0, car.global_position.y + LiftCfg.M_CAR_H + 0.28, 0.0)
	cam.dist = 1.55
	cam.yaw = 62.0
	cam.pitch = -14.0
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("12-rope-hitch.png"))

	# the counterweight is now at the shaft head, the car does not block it
	cam.target = Vector3(0, plant.counterweight_y() + 0.25, LiftCfg.M_CWT_Z)
	cam.dist = 2.2
	cam.yaw = 88.0
	cam.pitch = 1.0
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("11-counterweight.png"))

	# COP close-up (button and indicator check) — register a call so the
	# button halo shows lit
	plant.press("car_5")
	cam.set_mode(CamRig.Mode.ORBIT)
	cam.follow_car = false
	cam.target = car.global_position + Vector3(LiftCfg.M_CAR_W * 0.5 - 0.05, 1.45, 0.51)
	cam.dist = 0.62
	cam.yaw = -74.0
	cam.pitch = -2.0
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("06-cop.png"))

	# landing indicator and call button close-up
	cam.target = Vector3(0.25, car.global_position.y + LiftCfg.M_DOOR_H + 0.18,
			LiftCfg.M_SHAFT_D * 0.5 + 0.2)
	cam.dist = 1.5
	cam.yaw = 14.0
	cam.pitch = -3.0
	await get_tree().create_timer(1.5).timeout
	await _save_shot(dir.path_join("07-landing-indicator.png"))

	# looking into the car from the door: mirror, floor and ceiling together
	cam.target = Vector3(0, car.global_position.y + 1.15, -0.1)
	cam.dist = 3.4
	cam.yaw = 2.0
	cam.pitch = -4.0
	plant.press("door_open")
	await get_tree().create_timer(3.0).timeout
	plant.press("door_open")
	await get_tree().create_timer(0.6).timeout
	await _save_shot(dir.path_join("08-car-overview.png"))

	get_tree().quit()
