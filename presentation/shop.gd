extends Node2D
## 店铺主场景：挂一个 GameSim。表现层只发命令、只读快照。

@onready var sim: GameSim = $GameSim
@onready var hud: ShopHud = $HUD
@onready var world: Node2D = $World
@onready var controls: CanvasLayer = $Controls

var _art_preview: Node2D


func _ready() -> void:
	App.open_shop(sim)
	hud.bind(sim)
	hud.visible = false
	world.bind(sim)
	controls.bind(sim, world, hud)


func open_art_preview() -> void:
	if is_instance_valid(_art_preview):
		return
	var was_paused := sim.paused
	var had_hud := hud.visible
	var had_world := world.visible
	var had_controls := controls.visible
	var world_mode := world.process_mode
	var controls_mode := controls.process_mode
	var hud_mode := hud.process_mode
	sim.paused = true
	# Visibility does not disable _input/_unhandled_input on the hidden game.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	controls.process_mode = Node.PROCESS_MODE_DISABLED
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	world.visible = false
	controls.visible = false
	hud.visible = false
	_art_preview = load("res://presentation/reference/art_preview.tscn").instantiate()
	_art_preview.z_index = 50
	_art_preview.closed.connect(func() -> void:
		sim.paused = was_paused
		world.process_mode = world_mode
		controls.process_mode = controls_mode
		hud.process_mode = hud_mode
		world.visible = had_world
		controls.visible = had_controls
		hud.visible = had_hud
		_art_preview = null)
	add_child(_art_preview)
