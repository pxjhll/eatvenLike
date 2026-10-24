extends Node2D
## 店铺主场景：挂一个 GameSim。表现层只发命令、只读快照。

@onready var sim: GameSim = $GameSim
@onready var hud: ShopHud = $HUD


func _ready() -> void:
	App.open_shop(sim)
	hud.bind(sim)
