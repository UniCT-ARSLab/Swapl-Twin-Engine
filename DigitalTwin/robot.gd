extends Node3D

var drone 
#@onready var label_x: Label = $"../Label_X"
#@onready var label_y: Label = $"../Label_Y"
#@onready var label_z: Label = $"../Label_Z"

func _ready():
	drone = get_node("drone")
	

func _process(delta: float) -> void:
	var pose = drone.get_pose()
	var vel = drone.get_velocity()
	var pos = pose[0]
	var att = pose[1]
	var lin_vel = vel[0]
	
	# Update labels
	#label_x.text = "X : %.3f" % [pos.z]
	#label_y.text = "Y : %.3f" % [pos.x]
	#label_z.text = "Z : %.3f (target: %.3f)" % [pos.y, drone.z_target]
	
	# Optional: publish to DDS for monitoring
	DDS.publish("X", DDS.DDS_TYPE_FLOAT, pos.z)
	DDS.publish("Y", DDS.DDS_TYPE_FLOAT, pos.x)
	DDS.publish("Z", DDS.DDS_TYPE_FLOAT, pos.y)
	DDS.publish("VZ", DDS.DDS_TYPE_FLOAT, lin_vel.y)
	
