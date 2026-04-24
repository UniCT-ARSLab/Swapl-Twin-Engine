extends Node

var swapl_http_url: String = "http://127.0.0.1:8080/setup"
var setup_done: bool = false

var ws_client: WebSocketPeer
var ws_url: String = "ws://127.0.0.1:9080"
var ws_connected: bool = false
var ws_reconnect_timer: float = 0.0
var ws_reconnect_interval: float = 5.0

var spawner = null

@export var auto_clear_on_disconnect: bool = true  

func _ready():
	print(" SWAPL Connector starting...")
	print(" Auto-clear on disconnect: %s" % auto_clear_on_disconnect)
	
	call_deferred("find_spawner")

	await get_tree().process_frame
	request_setup()

func find_spawner():
	spawner = get_tree().get_first_node_in_group("spawner")
	
	if not spawner:
		spawner = get_node_or_null("/root/World/DroneSpawner")
	
	if spawner:
		print(" Found DroneSpawner!")
	else:
		print(" DroneSpawner NOT found!")

func request_setup():
	"""Richiede setup a SWAPL via HTTP"""
	print(" Requesting setup from SWAPL...")
	
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_setup_received.bind(http_request))
	
	var error = http_request.request(swapl_http_url)
	if error != OK:
		print(" HTTP request failed: %d" % error)

func _on_setup_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http_request: HTTPRequest):
	"""Callback quando riceve risposta da /setup"""
	http_request.queue_free()
	
	if response_code != 200:
		print("❌ HTTP error: %d" % response_code)
		await get_tree().create_timer(5.0).timeout
		request_setup()
		return
	
	var json_string = body.get_string_from_utf8()
	var json = JSON.new()
	var error = json.parse(json_string)
	
	if error != OK:
		print("❌ JSON parse error")
		return
	
	var data = json.data
	var drone_count = data.get("drone_count", 0)
	
	print("✅ Setup received: %d drones" % drone_count)
	
	if spawner and drone_count > 0:
		spawner.clear_all_drones()
		spawner.spawn_drones(drone_count)
		setup_done = true
		
		await get_tree().create_timer(0.5).timeout
		
		connect_websocket()
	else:
		print("❌ Cannot spawn drones")

func connect_websocket():
	"""Connetti a SWAPL WebSocket per ricevere posizioni"""
	print("🔌 Connecting to SWAPL Position Server...")
	
	ws_client = WebSocketPeer.new()
	var err = ws_client.connect_to_url(ws_url)
	
	if err != OK:
		print("❌ WebSocket connect failed: %d" % err)

func _process(delta):
	if not setup_done:
		return
	
	if not ws_client:
		return
	
	ws_client.poll()
	var state = ws_client.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not ws_connected:
			ws_connected = true
			print(" Connected to SWAPL Position Server!")
		
		while ws_client.get_available_packet_count() > 0:
			var packet = ws_client.get_packet()
			var message = packet.get_string_from_utf8()
			process_ws_message(message)
	
	elif state == WebSocketPeer.STATE_CLOSED:
		if ws_connected:
			print(" Disconnected from SWAPL Position Server")
			ws_connected = false
			
			if auto_clear_on_disconnect:
				clear_all_drones()
		
		ws_reconnect_timer += delta
		if ws_reconnect_timer >= ws_reconnect_interval:
			ws_reconnect_timer = 0.0
			connect_websocket()

func process_ws_message(message: String):
	"""Processa messaggi WebSocket (posizioni)"""
	var json = JSON.new()
	if json.parse(message) != OK:
		return
	
	var data = json.data
	
	if data.get("type") == "position_update":
		update_drone_positions(data.get("drones", []))
		var seq = data.get("seq", -1)
		var ts = data.get("ts", null)
		if seq >= 0:
			var ack = {
				"type": "position_ack",
				"seq": seq,
				"ts": ts,
				"ts_recv": Time.get_unix_time_from_system() + float(Time.get_ticks_msec() % 1000) / 1000.0
			}
			ws_client.send_text(JSON.stringify(ack))

func update_drone_positions(drones_data: Array):
	"""Aggiorna le posizioni dei droni"""
	var drones = get_tree().get_nodes_in_group("drones")
	
	for drone_data in drones_data:
		var drone_id = drone_data.get("id", -1)
		var target_x = drone_data.get("x", 0.0)
		var target_z = drone_data.get("z", 0.0)
		
		if drone_id >= 0 and drone_id < drones.size():
			var drone = drones[drone_id]
			var target_altitude = drone.z_target
			if drone_data.has("altitude"):
				var altitude_value = drone_data.get("altitude")
				if altitude_value != null:
					target_altitude = float(altitude_value)
					if drone.has_method("set_z_target"):
						drone.set_z_target(target_altitude, false)
			
			var target_pos = Vector3(target_x, target_altitude, target_z)
			drone.set_movement_target(target_pos)

func clear_all_drones():
	"""Elimina tutti i droni dalla scena"""
	if not spawner:
		return
	
	print(" Auto-clearing drones (SWAPL disconnected)")
	spawner.clear_all_drones()
	setup_done = false

func _exit_tree():
	"""Chiudi WebSocket quando il nodo viene distrutto"""
	if ws_client and ws_connected:
		ws_client.close()
