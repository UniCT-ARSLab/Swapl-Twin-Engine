extends Node3D
class_name Sensor

# Configurazione sensore
@export var ray_length: float = 5.0
@export var ray_count: int = 9  # Numero di raggi nel fascio
@export var spread_angle: float = 30.0  # Angolo di apertura in gradi
@export var debug_color_free: Color = Color.GREEN
@export var debug_color_hit: Color = Color.YELLOW
@export var debug_thickness: float = 3.0

var raycasts: Array[RayCast3D] = []
var min_distance: float = INF
var closest_object: Node3D = null
var is_detecting: bool = false

func _ready():
	create_raycast_fan()

func create_raycast_fan():
	for child in get_children():
		if child is RayCast3D:
			child.queue_free()
	raycasts.clear()
	
	if ray_count == 1:
		_create_single_ray(Vector3.FORWARD)
	else:
		var angle_step = spread_angle / (ray_count - 1)
		var start_angle = -spread_angle / 2.0
		
		for i in range(ray_count):
			var angle = start_angle + (i * angle_step)
			var direction = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(angle))
			_create_single_ray(direction, "Ray_%d" % i)

func _create_single_ray(direction: Vector3, ray_name: String = "RayCenter"):
	var raycast = RayCast3D.new()
	raycast.name = ray_name
	raycast.target_position = direction * ray_length
	raycast.enabled = true
	raycast.debug_shape_custom_color = debug_color_free
	raycast.debug_shape_thickness = debug_thickness
	
	add_child(raycast)
	raycasts.append(raycast)

func _physics_process(_delta):
	update_sensor()

func update_sensor():
	min_distance = INF
	closest_object = null
	is_detecting = false
	
	for ray in raycasts:
		if ray.is_colliding():
			is_detecting = true
			var collision_point = ray.get_collision_point()
			var distance = global_position.distance_to(collision_point)
			
			if distance < min_distance:
				min_distance = distance
				closest_object = ray.get_collider()
			
			ray.debug_shape_custom_color = debug_color_hit
		else:
			ray.debug_shape_custom_color = debug_color_free

func get_detection() -> Dictionary:
	return {
		"is_detecting": is_detecting,
		"distance": min_distance if is_detecting else -1.0,
		"object": closest_object,
		"object_name": closest_object.name if closest_object else ""
	}

func get_min_distance() -> float:
	return min_distance if is_detecting else -1.0

func is_obstacle_detected() -> bool:
	return is_detecting
