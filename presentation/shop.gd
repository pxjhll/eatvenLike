extends Node2D
## 店铺主场景：挂一个 GameSim。表现层只发命令、只读快照。

@onready var sim: GameSim = $GameSim
@onready var hud: ShopHud = $HUD
@onready var world: Node2D = $World
@onready var controls: CanvasLayer = $Controls


func _ready() -> void:
	App.open_shop(sim)
	hud.bind(sim)
	hud.visible = false
	world.bind(sim)
	controls.bind(sim, world, hud)
