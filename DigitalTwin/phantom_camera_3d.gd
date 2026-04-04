extends PhantomCamera3D

# Velocità di movimento
@export var move_speed := 10.0
@export var sprint_multiplier := 2.0
@export var mouse_sensitivity := 0.002

# Rotazione
var yaw := 0.0
var pitch := 0.0

func _ready():
	super._ready()
	set_priority(10)
	
	# IMPORTANTE: Imposta Follow e Look At su NONE
	follow_mode = FollowMode.NONE
	look_at_mode = LookAtMode.NONE
	
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("PhantomCamera3D script loaded! Position: ", global_position)

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -PI/2, PI/2)
		
		rotation.y = yaw
		rotation.x = pitch
	
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta):
	# Usa _physics_process invece di _process per evitare conflitti
	var input_dir := Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W):
		input_dir -= global_transform.basis.z
	if Input.is_key_pressed(KEY_S):
		input_dir += global_transform.basis.z
	if Input.is_key_pressed(KEY_A):
		input_dir -= global_transform.basis.x
	if Input.is_key_pressed(KEY_D):
		input_dir += global_transform.basis.x
	
	if Input.is_key_pressed(KEY_SPACE):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_SHIFT):
		input_dir.y -= 1
	
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		var current_speed = move_speed
		
		if Input.is_key_pressed(KEY_CTRL):
			current_speed *= sprint_multiplier
		
		global_position += input_dir * current_speed * delta
		print("Moving to: ", global_position)
