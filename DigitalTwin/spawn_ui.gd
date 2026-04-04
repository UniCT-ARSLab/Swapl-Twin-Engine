extends VBoxContainer

@onready var label_count: Label = $LabelCount
@onready var spin_box: SpinBox = $SpinBoxCount
@onready var btn_spawn: Button = $ButtonSpawn
@onready var btn_clear: Button = $ButtonClear

var spawner: DroneSpawner

func _ready():
	# Connetti segnali
	btn_spawn.pressed.connect(on_spawn_pressed)
	btn_clear.pressed.connect(on_clear_pressed)
	
	# Setup UI
	btn_spawn.text = "Spawn Drones"
	btn_clear.text = "Clear All"
	label_count.text = "Active Drones: 0"
	
	# Trova o crea lo spawner DOPO che la scena è pronta
	call_deferred("setup_spawner")  # ← USA CALL_DEFERRED!

func setup_spawner():
	spawner = get_node_or_null("/root/World/DroneSpawner")
	if not spawner:
		spawner = DroneSpawner.new()
		spawner.name = "DroneSpawner"
		get_node("/root/World").add_child(spawner)
	print("✅ Spawner ready!")

func on_spawn_pressed():
	if spawner:
		var count = int(spin_box.value)
		spawner.spawn_drones(count)
		update_label()

func on_clear_pressed():
	if spawner:
		spawner.clear_all_drones()
		update_label()

func update_label():
	if spawner:
		label_count.text = "Active Drones: %d" % spawner.get_drone_count()

func _process(_delta):
	update_label()
