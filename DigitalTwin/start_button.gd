extends Button

@onready var robot: Node3D = $"/root/World/Robot"
@onready var drone: RigidBody3D = $"/root/World/Robot/drone"

var is_running: bool = false

func _ready() -> void:
	pressed.connect(on_start)
	text = "Start"

func on_start():
	if not is_running:
		# Avvia il controller
		is_running = true
		text = "Stop"
		print("Controller started - Target altitude: %.2f m" % drone.z_target)
	else:
		# Ferma il controller e resetta
		is_running = false
		text = "Start"
		drone.do_reset()
		print("Controller stopped and reset")
