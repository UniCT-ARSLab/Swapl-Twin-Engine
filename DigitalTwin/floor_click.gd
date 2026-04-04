extends StaticBody3D

func _ready():
	input_ray_pickable = true

func _input_event(camera: Node, event: InputEvent, event_position: Vector3, normal: Vector3, shape_idx: int):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var drones = get_tree().get_nodes_in_group("drones")
			for drone in drones:
				if drone.is_selected:
					drone.set_movement_target(event_position)
					print("📍 Floor clicked at: %s" % event_position)
					break
