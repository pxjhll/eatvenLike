extends Resource
## Shared tea-scale presentation. Scene coordinates remain authored pixels;
## a single unit conversion applies to the whole actor and its attached props.

@export var reference_width: float = 720.0
@export var minimum_visible_height: float = 1100.0
@export var staff_height: float = 128.0
@export var customer_height: float = 110.0
@export var customer_speed: float = 170.0

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	for key in ["reference_width","minimum_visible_height","staff_height","customer_height","customer_speed"]:
		if not _positive(get(key)): errors.append(key)
	return errors

func scene_units(world_size: Vector2) -> float:
	if not _size_valid(world_size) or not _positive(reference_width): return 0.0
	return world_size.x / reference_width

func fit(view_size: Vector2, world_size: Vector2, ui_width: float = 720.0) -> Dictionary:
	if not validate().is_empty() or not _size_valid(view_size) or not _size_valid(world_size) or not _positive(ui_width):
		return {}
	var units := scene_units(world_size)
	var reference_zoom := minf(view_size.x / reference_width, view_size.y / minimum_visible_height)
	return {"unit_scale":units,"world_factor":reference_zoom/units,"ui_factor":reference_zoom*(reference_width/ui_width)}

func _size_valid(size: Vector2) -> bool:
	return size.is_finite() and size.x > 0.0 and size.y > 0.0

func _positive(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) > 0.0
