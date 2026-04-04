extends Node3D
class_name DroneSpawner

var drone_scene: PackedScene
var active_drones: Array = []  
var spawn_spacing: float = 2.0

func _ready():
	drone_scene = preload("res://robot.tscn")

func spawn_drones(count: int):
	print("🚁 Spawning %d droni..." % count)
	
	var grid_size: int = int(ceil(sqrt(count)))
	
	for i in count:
		var row: int = i / grid_size
		var col: int = i % grid_size
		var pos = Vector3(col * spawn_spacing, 0.1, row * spawn_spacing)
		
		var drone = drone_scene.instantiate()
		drone.global_position = pos
		drone.name = "Drone_%d" % i
		
		add_child(drone)
		active_drones.append(drone)
		
		var actual_drone = drone.get_node("drone")  
		if actual_drone:
			actual_drone.add_to_group("drones")
		
		print("   %s spawned at %s" % [drone.name, pos])
	
	print(" Total active drones: %d" % active_drones.size())

func clear_all_drones():
	print(" Clearing all drones...")
	
	for drone in active_drones:
		if is_instance_valid(drone):
			drone.queue_free()
	
	active_drones.clear()
	print(" All drones cleared")

func get_drone_count() -> int:
	return active_drones.size()
