extends HSlider

@onready var drone: RigidBody3D = $"/root/World/Robot/drone"
@onready var label: Label = $"../LabelTarget"

func _ready() -> void:
	value_changed.connect(on_value_changed)
	# Imposta il valore iniziale
	value = 0.5
	label.text = "Target Altitude: %.2f m" % value

func on_value_changed(new_value: float):
	if drone:
		drone.set_z_target(new_value)
		#label.text = "Target Altitude: %.2f m" % new_value
		#print("🎯 New target altitude: %.2f m" % new_value)
