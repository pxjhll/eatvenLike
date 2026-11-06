extends Node2D
## Independent scene reconstruction review. Does not load or modify gameplay saves.

const SOURCE_SIZE := Vector2(937, 1678)

func _ready() -> void:
	DisplayServer.window_set_title("煎饼摊 · v04 场景还原")
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var viewport := get_viewport_rect().size
	var ratio := minf(viewport.x / SOURCE_SIZE.x, viewport.y / SOURCE_SIZE.y)
	$PancakeArt.scale = Vector2.ONE * ratio
	$PancakeArt.position = (viewport - SOURCE_SIZE * ratio) * 0.5
