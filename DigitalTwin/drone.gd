extends RigidBody3D
@onready var L = 0.195
@onready var p1 = Vector3(L,0,L)
@onready var p2 = Vector3(-L,0,L)
@onready var p3 = Vector3(-L,0,-L)
@onready var p4 = Vector3(L,0,-L)
@onready var sensor = $Sensore

var f1 = Vector3(0,0,0)
var f2 = Vector3(0,0,0)
var f3 = Vector3(0,0,0)
var f4 = Vector3(0,0,0)
var alert_seq: int = 0
var is_selected: bool = false

var initial_position
var initial_rotation
var initial_velocity
var initial_angular_velocity
var perform_reset: bool = false

var target_position: Vector3 = Vector3.ZERO
var has_target: bool = false

var vz_controller: PIDController
var z_controller: PIDController
var x_controller: PIDController
var vx_controller: PIDController
var z_controller_horizontal: PIDController
var vz_controller_horizontal: PIDController

var z_target: float = 0.5
var vz_target: float = 0.0

var ws_client: WebSocketPeer = null
var ws_url: String = "ws://127.0.0.1:8081"
var ws_connected: bool = false
var ws_reconnect_timer: float = 0.0
var ws_reconnect_interval: float = 5.0

var collision_alert_threshold: float = 2.0
var last_alert_time: float = 0.0
var alert_cooldown: float = 1.0

func _ready():
	initial_position = global_position
	initial_rotation = global_rotation
	initial_velocity = linear_velocity
	initial_angular_velocity = angular_velocity
	
	vz_controller = PIDController.new(5.0, 10.0, 0.0, 5.0)
	z_controller = PIDController.new(2.0, 0.0, 0.0, 2.0)
	
	x_controller = PIDController.new(0.3, 0.0, 0.1, 0.5)
	vx_controller = PIDController.new(0.5, 0.1, 0.0, 0.5)
	z_controller_horizontal = PIDController.new(0.3, 0.0, 0.1, 0.5)
	vz_controller_horizontal = PIDController.new(0.5, 0.1, 0.0, 0.5)
	
	input_ray_pickable = true
	target_position = global_position
	make_unique_materials()
	
	connect_websocket()

func make_unique_materials():
	for child in get_children():
		if child is MeshInstance3D:
			var mesh = child as MeshInstance3D
			if mesh.get_surface_override_material(0):
				var mat = mesh.get_surface_override_material(0).duplicate()
				mesh.set_surface_override_material(0, mat)
			elif mesh.mesh and mesh.mesh.surface_get_material(0):
				var mat = mesh.mesh.surface_get_material(0).duplicate()
				mesh.set_surface_override_material(0, mat)

func _input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			select_drone()
			print("🚁 Clicked: %s | Altitude: %.2f m" % [get_parent_node_3d().name, global_position.y])

func do_reset():
	perform_reset = true

func reset():
	position = initial_position
	rotation = initial_rotation
	linear_velocity = initial_velocity 
	angular_velocity = initial_angular_velocity
	vz_controller.reset()
	z_controller.reset()

func _physics_process(delta):
	update_websocket(delta)
	
	check_distance_sensor()
	
	if perform_reset:
		reset()
		perform_reset = false
	else:
		var current_y = global_position.y
		var current_vy = linear_velocity.y
		
		vz_target = z_controller.evaluate(delta, z_target - current_y)
		var thrust = vz_controller.evaluate(delta, vz_target - current_vy)
		
		set_forces(thrust, thrust, thrust, thrust)
		
		apply_local_force(f1, p1)
		apply_local_force(f2, p2)
		apply_local_force(f3, p3)
		apply_local_force(f4, p4)
		
		if has_target:
			move_towards_target(delta)
		
		apply_stabilization_and_tilt(delta)

func _get_swapl_drone_identity() -> Dictionary:
	var parent_name = get_parent_node_3d().name
	var drone_name = parent_name
	
	if has_meta("swapl_drone_name"):
		drone_name = str(get_meta("swapl_drone_name"))
	
	if has_meta("swapl_drone_id"):
		return {
			"valid": true,
			"id": int(get_meta("swapl_drone_id")),
			"name": drone_name
		}
	
	if parent_name.begins_with("Drone_"):
		var suffix = parent_name.trim_prefix("Drone_")
		if suffix.is_valid_int():
			return {
				"valid": true,
				"id": int(suffix),
				"name": parent_name
			}
	
	return {
		"valid": false,
		"id": -1,
		"name": drone_name
	}

func connect_websocket():
	"""Connetti al WebSocket server SWAPL"""
	var identity = _get_swapl_drone_identity()
	if not identity.get("valid", false):
		return
	
	if ws_client:
		ws_client = null
	
	ws_client = WebSocketPeer.new()
	var err = ws_client.connect_to_url(ws_url)
	
	if err == OK:
		print(" [%s] Connecting to WebSocket: %s" % [identity.get("name", get_parent_node_3d().name), ws_url])
	else:
		print(" [%s] Failed to connect WebSocket: %d" % [identity.get("name", get_parent_node_3d().name), err])

func update_websocket(delta: float):
	"""Aggiorna lo stato del WebSocket"""
	if not ws_client:
		return
	
	ws_client.poll()
	var state = ws_client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not ws_connected:
			ws_connected = true
			print(" [%s] WebSocket connected!" % get_parent_node_3d().name)
		
		while ws_client.get_available_packet_count() > 0:
			var packet = ws_client.get_packet()
			var message = packet.get_string_from_utf8()
			process_ws_message(message)
	
	elif state == WebSocketPeer.STATE_CLOSED:
		if ws_connected:
			print(" [%s] WebSocket disconnected" % get_parent_node_3d().name)
			ws_connected = false
		
		ws_reconnect_timer += delta
		if ws_reconnect_timer >= ws_reconnect_interval:
			ws_reconnect_timer = 0.0
			connect_websocket()

func process_ws_message(message: String):
	"""Processa un messaggio ricevuto dal WebSocket"""
	var json = JSON.new()
	var error = json.parse(message)
	
	if error == OK:
		var data = json.data
		if data.get('type') == 'collision_response':
			pass  
		elif data.get('type') == 'pong':
			pass 
	else:
		print("⚠️ Invalid JSON from WebSocket: %s" % message)

func send_collision_alert(distance: float, object_name: String):
	"""Invia un alert di collisione via WebSocket"""
	if not ws_connected:
		print("⚠️ [%s] WebSocket not connected, cannot send alert" % get_parent_node_3d().name)
		return
	
	var identity = _get_swapl_drone_identity()
	if not identity.get("valid", false):
		return
	
	var drone_name = identity.get("name", get_parent_node_3d().name)
	alert_seq += 1
	var ts = Time.get_unix_time_from_system() + float(Time.get_ticks_msec() % 1000) / 1000.0
	var alert_data = {
	"type": "collision_alert",
	"seq": alert_seq,
	"ts": Time.get_unix_time_from_system(),  
	"drone": drone_name,
	"drone_id": identity.get("id", -1),
	"distance": snapped(distance, 0.01),
	"object": object_name
	}

	
	var json_string = JSON.stringify(alert_data)
	var err = ws_client.send_text(json_string)
	
	if err == OK:
		print(" [%s] Collision alert sent: distance=%.2fm, object=%s" % 
			[drone_name, distance, object_name])
	else:
		print(" [%s] Failed to send alert: %d" % [drone_name, err])

func check_distance_sensor():
	"""Controlla il sensore e invia alert se necessario"""
	var detection = sensor.get_detection()
	
	if detection.is_detecting:
		var distance = detection.distance
		
		if distance < collision_alert_threshold:
			var current_time = Time.get_ticks_msec() / 1000.0
			if current_time - last_alert_time > alert_cooldown:
				send_collision_alert(distance, detection.object_name)
				last_alert_time = current_time

func move_towards_target(delta: float):
	var error = target_position - global_position
	error.y = 0
	
	var distance = error.length()
	
	if distance < 0.1:
		has_target = false
		print(" %s arrived!" % get_parent_node_3d().name)
		return
	
	var max_speed: float = 2.0
	var acceleration: float = 3.0
	var slowdown_distance: float = 1.0
	
	var speed_factor: float = 1.0
	if distance < slowdown_distance:
		speed_factor = distance / slowdown_distance
	
	var direction = error.normalized()
	var current_vel = Vector3(linear_velocity.x, 0, linear_velocity.z)
	var desired_speed = max_speed * speed_factor
	var desired_velocity = direction * desired_speed
	var velocity_error = desired_velocity - current_vel
	
	var force = velocity_error * acceleration
	
	if force.length() > 5.0:
		force = force.normalized() * 5.0
	
	apply_central_force(force)

func apply_stabilization_and_tilt(delta: float):
	var vel_x = linear_velocity.x
	var vel_z = linear_velocity.z
	var speed = sqrt(vel_x * vel_x + vel_z * vel_z)
	
	var max_tilt: float = 0.2
	var speed_ref: float = 2.5
	
	var target_pitch: float = 0.0
	var target_roll: float = 0.0
	
	if speed > 0.1:
		target_pitch = clamp(vel_z / speed_ref, -1.0, 1.0) * max_tilt
		target_roll = clamp(-vel_x / speed_ref, -1.0, 1.0) * max_tilt
	
	var kp: float = 4.0
	var kd: float = 1.0
	
	var current_pitch = rotation.x
	var current_roll = rotation.z
	
	current_pitch = clamp(current_pitch, -PI/2, PI/2)
	current_roll = clamp(current_roll, -PI/2, PI/2)
	
	var pitch_error = target_pitch - current_pitch
	var roll_error = target_roll - current_roll
	
	var torque_x = pitch_error * kp - angular_velocity.x * kd
	var torque_z = roll_error * kp - angular_velocity.z * kd
	
	torque_x = clamp(torque_x, -5.0, 5.0)
	torque_z = clamp(torque_z, -5.0, 5.0)
	
	apply_torque(Vector3(torque_x, 0, torque_z))
	
	var yaw_brake = -angular_velocity.y * 2.0
	apply_torque(Vector3(0, yaw_brake, 0))
	
	if not has_target:
		var horizontal_vel = Vector3(linear_velocity.x, 0, linear_velocity.z)
		if horizontal_vel.length() > 0.05:
			apply_central_force(-horizontal_vel * 3.0)

func apply_local_force(force: Vector3, pos: Vector3):
	var pos_local = self.transform.basis * pos
	var force_local = self.transform.basis * force
	self.apply_force(force_local, pos_local)

func set_forces(_f1, _f2, _f3, _f4):
	f1 = Vector3(0, _f1, 0)
	f2 = Vector3(0, _f2, 0)
	f3 = Vector3(0, _f3, 0)
	f4 = Vector3(0, _f4, 0)

func get_pose():
	return [global_position, global_rotation]

func get_velocity():
	return [linear_velocity, angular_velocity]

func set_z_target(new_target: float, log_change: bool = true):
	if is_equal_approx(z_target, new_target):
		return
	
	z_target = new_target
	if not log_change:
		return
	print("✈️ Drone: New altitude target set to %.2f m" % new_target)

func highlight_drone():
	var meshes_data: Array = []
	
	for child in get_children():
		if child is MeshInstance3D:
			var mesh = child as MeshInstance3D
			var surface_count = mesh.get_surface_override_material_count()
			
			var original_materials: Array = []
			for i in surface_count:
				original_materials.append(mesh.get_surface_override_material(i))
			
			meshes_data.append({"mesh": mesh, "originals": original_materials, "count": surface_count})
			
			var yellow_mat = StandardMaterial3D.new()
			yellow_mat.albedo_color = Color.YELLOW
			
			for i in surface_count:
				mesh.set_surface_override_material(i, yellow_mat)
	
	await get_tree().create_timer(0.3).timeout
	
	for data in meshes_data:
		for i in data["count"]:
			data["mesh"].set_surface_override_material(i, data["originals"][i])

func select_drone():
	var all_drones = get_tree().get_nodes_in_group("drones")
	for drone in all_drones:
		if drone != self and drone.has_method("deselect"):
			drone.deselect()
	
	is_selected = true
	print("🎯 Selected: %s" % get_parent_node_3d().name)
	highlight_drone()

func deselect():
	is_selected = false

func set_movement_target(pos: Vector3):
	target_position = pos
	target_position.y = z_target
	has_target = true
	print("📍 %s moving to: %s" % [get_parent_node_3d().name, target_position])

func _exit_tree():
	"""Chiudi WebSocket quando il drone viene distrutto"""
	if ws_client and ws_connected:
		ws_client.close()
