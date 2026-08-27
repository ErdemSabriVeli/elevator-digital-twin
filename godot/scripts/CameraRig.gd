class_name CamRig
extends Node3D

## Camera control.
##   Right drag  : orbit
##   Middle drag : pan
##   Wheel       : zoom in / out
##   1 / 2 / 3 / 4 : exterior, in-car, landing, machine room
##   F           : follow the car (toggle)

enum Mode { ORBIT, INTERIOR, LOBBY, MACHINE }

var cam: Camera3D
var mode := Mode.ORBIT
var follow_car := false

var target := Vector3(0, 4.0, 1.0)
var yaw := 38.0
var pitch := -10.0
var dist := 13.0

var car_node: Node3D
var mount_node: Node3D
var lobby_floor := 0
var machine_y := LiftCfg.total_height() - 1.2

var _orbiting := false
var _panning := false
var _smooth := Vector3(0, 4.0, 1.0)
var _look_yaw := 0.0
var _look_pitch := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = 300.0
	add_child(cam)
	cam.current = true


func set_mode(m: int) -> void:
	mode = m
	match mode:
		Mode.INTERIOR:
			_look_yaw = 30.0      # shows the door and the car panel together
			_look_pitch = -6.0
		Mode.LOBBY:
			pass
		Mode.MACHINE:
			# the machine sits at the shaft head: look closely from the open side
			target = Vector3(0, machine_y - 0.05, -0.30)
			yaw = 66.0
			pitch = -7.0
			dist = 2.0
			follow_car = false
		Mode.ORBIT:
			dist = maxf(dist, 8.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = mb.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					dist = maxf(1.5, dist * 0.88)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					dist = minf(60.0, dist * 1.12)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mode == Mode.INTERIOR:
			if _orbiting:
				_look_yaw -= mm.relative.x * 0.25
				_look_pitch = clampf(_look_pitch - mm.relative.y * 0.20, -70.0, 70.0)
		elif _orbiting:
			yaw -= mm.relative.x * 0.30
			pitch = clampf(pitch - mm.relative.y * 0.25, -85.0, 85.0)
		elif _panning:
			var right := cam.global_transform.basis.x
			var up := cam.global_transform.basis.y
			target -= (right * mm.relative.x + up * -mm.relative.y) * dist * 0.0016
			follow_car = false


func _process(delta: float) -> void:
	match mode:
		Mode.INTERIOR:
			if mount_node != null:
				var b := Basis.from_euler(Vector3(deg_to_rad(_look_pitch),
						deg_to_rad(180.0 + _look_yaw), 0))
				cam.global_position = mount_node.global_position
				cam.global_basis = b
			return

		Mode.LOBBY:
			var y := float(lobby_floor) * LiftCfg.M_FLOOR_H
			var p := Vector3(1.8, y + 1.65, LiftCfg.M_SHAFT_D * 0.5 + 3.4)
			cam.global_position = cam.global_position.lerp(p, minf(1.0, delta * 6.0))
			cam.look_at(Vector3(0, y + 1.3, 0))
			return

		_:
			var t := target
			if follow_car and car_node != null:
				t = Vector3(0, car_node.position.y + 1.3, 0.6)
			_smooth = _smooth.lerp(t, minf(1.0, delta * 5.0))
			var basis := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
			cam.global_position = _smooth + basis * Vector3(0, 0, dist)
			cam.look_at(_smooth)


func frame_all() -> void:
	mode = Mode.ORBIT
	follow_car = false
	# Look from the open (right) side of the shaft: car, ropes and counterweight.
	target = Vector3(0, LiftCfg.total_height() * 0.46, 1.0)
	dist = LiftCfg.total_height() * 1.38
	yaw = 68.0
	pitch = -4.0
