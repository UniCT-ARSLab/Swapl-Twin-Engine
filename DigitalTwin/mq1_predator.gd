extends RigidBody3D
class_name MQ1Predator

@export_group("Parametri Volo")
@export var cruise_speed: float = 36.0
@export var min_speed: float = 20.0
@export var max_speed: float = 55.0
@export var cruise_altitude: float = 100.0
@export var altitude_tolerance: float = 5.0

@export_group("Parametri Aerodinamici")
@export var lift_coefficient: float = 2.8
@export var drag_coefficient: float = 0.15
@export var wing_area: float = 11.45
@export var air_density: float = 1.225
@export var stall_angle: float = 15.0

@export_group("Parametri Pattugliamento")
@export var patrol_center: Vector3 = Vector3.ZERO
@export var patrol_radius: float = 200.0
@export var patrol_direction: int = 1
@export var bank_angle_max: float = 25.0

@export_group("Controllo Manuale")
@export var manual_turn_speed: float = 1.2
@export var manual_bank_angle: float = 30.0

@export_group("Motore")
@export var thrust_force: float = 450.0
@export var throttle: float = 0.8

var current_speed: float = 0.0
var is_stalling: bool = false
var patrol_angle: float = 0.0
var current_bank: float = 0.0

var is_manual_control: bool = false
var manual_heading: float = 0.0

var telemetry: Dictionary = {}

@export var debug_freeze: bool = false

func _ready() -> void:
	add_to_group("predator")
	mass = 1020.0
	gravity_scale = 0.0

	if debug_freeze:
		freeze = true
		global_position = Vector3(0, 50, 0)
		return

	freeze = false
	patrol_angle = randf_range(0.0, TAU)
	var start_pos = _get_patrol_position(patrol_angle)
	start_pos.y = cruise_altitude
	global_position = start_pos

	var initial_dir = Vector3(cos(patrol_angle), 0, sin(patrol_angle)).normalized()
	linear_velocity = initial_dir * cruise_speed
	manual_heading = patrol_angle

func _physics_process(delta: float) -> void:
	if debug_freeze:
		return

	current_speed = linear_velocity.length()
	_handle_manual_input(delta)

	if is_manual_control:
		_update_manual_flight(delta)
	else:
		_update_patrol(delta)

	_apply_aerodynamics(delta)
	_maintain_altitude(delta)
	_update_visual_rotation(delta)
	_update_telemetry()


func _handle_manual_input(delta: float) -> void:
	var turning = false

	if Input.is_key_pressed(KEY_LEFT):
		manual_heading += manual_turn_speed * delta  
		is_manual_control = true
		turning = true

	if Input.is_key_pressed(KEY_RIGHT):
		manual_heading -= manual_turn_speed * delta 
		is_manual_control = true
		turning = true

	if not turning and is_manual_control:
		is_manual_control = false
		patrol_angle = manual_heading
		print("[MQ-1] Ripresa pattugliamento")


func _update_manual_flight(delta: float) -> void:
	var direction = Vector3(sin(manual_heading), 0, cos(manual_heading)).normalized()
	apply_central_force(direction * thrust_force * throttle)

	if direction.length() > 0.1 and direction.cross(Vector3.UP).length() > 0.01:
		var look_target = global_position + direction
		var t = global_transform.looking_at(look_target, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(t.basis, 0.08)


func _update_patrol(delta: float) -> void:
	var angular_speed = cruise_speed / patrol_radius
	patrol_angle += angular_speed * patrol_direction * delta
	patrol_angle = fmod(patrol_angle, TAU)

	var target_pos = _get_patrol_position(patrol_angle)
	target_pos.y = cruise_altitude

	var direction_flat = Vector3(
		target_pos.x - global_position.x,
		0,
		target_pos.z - global_position.z
	).normalized()

	apply_central_force(direction_flat * thrust_force * throttle)

	if direction_flat.length() > 0.1 and direction_flat.cross(Vector3.UP).length() > 0.01:
		var look_target = global_position + direction_flat
		var t = global_transform.looking_at(look_target, Vector3.UP)
		global_transform.basis = global_transform.basis.slerp(t.basis, 0.05)

	manual_heading = atan2(direction_flat.x, direction_flat.z)

func _get_patrol_position(angle: float) -> Vector3:
	return Vector3(
		patrol_center.x + cos(angle) * patrol_radius,
		cruise_altitude,
		patrol_center.z + sin(angle) * patrol_radius
	)


func _apply_aerodynamics(delta: float) -> void:
	if current_speed < 0.1:
		return

	var velocity_dir = linear_velocity.normalized()
	var lift_force = 0.5 * air_density * pow(current_speed, 2) * wing_area * lift_coefficient

	if current_speed < min_speed:
		is_stalling = true
		lift_force *= current_speed / min_speed
	else:
		is_stalling = false

	apply_central_force(Vector3.UP * lift_force)
	apply_central_force(Vector3.DOWN * mass * 9.81)

	var drag_force = 0.5 * air_density * pow(current_speed, 2) * wing_area * drag_coefficient
	apply_central_force(-velocity_dir * drag_force)

	if current_speed > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

func _maintain_altitude(delta: float) -> void:
	var alt_error = cruise_altitude - global_position.y
	if abs(alt_error) > altitude_tolerance:
		var correction = clamp(alt_error * 50.0, -500.0, 500.0)
		apply_central_force(Vector3.UP * correction)


func _update_visual_rotation(delta: float) -> void:
	var target_bank: float

	if is_manual_control:
		if Input.is_key_pressed(KEY_LEFT):
			target_bank = manual_bank_angle      
		elif Input.is_key_pressed(KEY_RIGHT):
			target_bank = -manual_bank_angle      
		else:
			target_bank = 0.0
	else:
		target_bank = 0.0  

	current_bank = lerp(current_bank, target_bank, delta * 3.0)
	var e = rotation
	e.z = deg_to_rad(-current_bank)
	rotation = e

func _update_telemetry() -> void:
	telemetry = {
		"id": name,
		"type": "MQ-1 Predator",
		"position": {
			"x": snapped(global_position.x, 0.1),
			"y": snapped(global_position.y, 0.1),
			"z": snapped(global_position.z, 0.1)
		},
		"speed_ms": snapped(current_speed, 0.1),
		"speed_kmh": snapped(current_speed * 3.6, 0.1),
		"altitude": snapped(global_position.y, 0.1),
		"heading_deg": snapped(rad_to_deg(manual_heading), 0.1),
		"bank_deg": snapped(current_bank, 0.1),
		"is_stalling": is_stalling,
		"is_manual": is_manual_control,
		"throttle": throttle
	}

func get_telemetry() -> Dictionary:
	return telemetry

func set_patrol_center(new_center: Vector3) -> void:
	patrol_center = new_center

func set_cruise_altitude(new_altitude: float) -> void:
	cruise_altitude = new_altitude

func set_patrol_radius(new_radius: float) -> void:
	patrol_radius = new_radius

func emergency_stop() -> void:
	throttle = 0.0
	linear_velocity = Vector3.ZERO
