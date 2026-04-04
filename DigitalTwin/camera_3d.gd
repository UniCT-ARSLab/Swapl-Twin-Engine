extends Camera3D

# =============================================
# Camera libera con modalità follow (tasto P)
# =============================================

# Velocità di movimento
@export var speed: float = 5.0
@export var sprint_multiplier: float = 2.0
# Sensibilità mouse
@export var mouse_sensitivity: float = 0.002

# Follow settings
@export_group("Follow Settings")
@export var follow_distance: float = 7.0    # distanza dietro il drone
@export var follow_height: float = 14.0       # altezza sopra il drone
@export var follow_smoothness: float = 5.0   # fluidità inseguimento

# Rotazione camera
var rotation_x: float = 0.0
var rotation_y: float = 0.0

# Follow mode
var is_following: bool = false
var follow_target: Node3D = null

# Salva posizione/rotazione libera per ripristinarla
var saved_position: Vector3
var saved_rotation_x: float
var saved_rotation_y: float

# =============================================
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# =============================================
func _input(event):
	# --- Tasto P: toggle follow mode ---
	if event is InputEventKey and event.pressed and event.keycode == KEY_P:
		_toggle_follow()
		return

	# --- Mouse: solo se NON si sta seguendo il drone ---
	if not is_following:
		if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			rotation_y -= event.relative.x * mouse_sensitivity
			rotation_x -= event.relative.y * mouse_sensitivity
			rotation_x = clamp(rotation_x, -PI/2, PI/2)
			rotation.x = rotation_x
			rotation.y = rotation_y

	# ESC per liberare il mouse
	if Input.is_key_pressed(KEY_ESCAPE):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# =============================================
func _process(delta):
	# Ricattura il mouse se si clicca
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
	and Input.get_mouse_mode() == Input.MOUSE_MODE_VISIBLE:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# --- FOLLOW MODE ---
	if is_following:
		if follow_target:
			_update_follow(delta)
		return  # in follow mode WASD disabilitato

	# --- CAMERA LIBERA: WASD ---
	var input_dir = Vector3.ZERO

	if Input.is_key_pressed(KEY_W): input_dir.z -= 1
	if Input.is_key_pressed(KEY_S): input_dir.z += 1
	if Input.is_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_key_pressed(KEY_D): input_dir.x += 1
	if Input.is_key_pressed(KEY_E): input_dir.y += 1
	if Input.is_key_pressed(KEY_Q): input_dir.y -= 1

	input_dir = input_dir.normalized()

	var current_speed = speed
	if Input.is_key_pressed(KEY_SHIFT):
		current_speed *= sprint_multiplier

	translate(input_dir * current_speed * delta)

# =============================================
func _toggle_follow() -> void:
	if not is_following:
		# Cerca il Predator nel gruppo
		follow_target = get_tree().get_first_node_in_group("predator")
		if not follow_target:
			push_warning("[Camera] Predator non trovato! Assicurati che il nodo sia nel gruppo 'predator'")
			return

		# Salva stato corrente per ripristinarlo dopo
		saved_position  = global_position
		saved_rotation_x = rotation_x
		saved_rotation_y = rotation_y

		is_following = true
		print("[Camera] ▶ Follow mode ON — premi P per tornare alla camera libera")
	else:
		# Ripristina camera libera
		is_following    = false
		follow_target   = null
		global_position = saved_position
		rotation_x      = saved_rotation_x
		rotation_y      = saved_rotation_y
		rotation.x      = rotation_x
		rotation.y      = rotation_y
		print("[Camera] ■ Follow mode OFF — camera libera ripristinata")

# =============================================
func _update_follow(delta: float) -> void:
	# Direzione frontale del drone
	var forward = follow_target.global_transform.basis.z.normalized()

	# Posizione desiderata: dietro e sopra il drone
	var desired_pos = follow_target.global_position \
		- forward * follow_distance \
		+ Vector3.UP * follow_height

	# Interpolazione fluida
	global_position = global_position.lerp(desired_pos, follow_smoothness * delta)

	# Guarda verso il drone (leggermente sopra il centro)
	look_at(follow_target.global_position + Vector3.UP * 2.0, Vector3.UP)
