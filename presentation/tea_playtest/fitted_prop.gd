extends Sprite2D
## Independent props keep their native proportions, whatever their exported canvas size.
@export_file("*.png") var asset_path := ""
@export var display_width := 60.0

func _ready() -> void:
	if not asset_path.is_empty() and ResourceLoader.exists(asset_path):
		texture = load(asset_path)
	if texture == null: return
	scale = Vector2.ONE * display_width / texture.get_width()
	centered = false
	offset = Vector2(-texture.get_width() / 2.0, -texture.get_height())
