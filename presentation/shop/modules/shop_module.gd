@tool
extends Node2D
## Editable assembly. Visual children may change; ports and footprints stay local.
@export var module_id: String = ""
@export_enum("station", "counter", "table", "entrance", "space") var module_kind: String = "station"
@export var station_id: String = ""
@export var seat_group: String = "dine"
@export var first_seat: int = 0
@export var table_index: int = 0
@export_range(1, 16) var seats_per_table: int = 2
@export_enum("dine", "wait") var seat_purpose: String = "dine"

func refresh_visual(view: ShopView) -> void:
	var visual := get_node_or_null("Visual") as Node2D
	if visual==null: return
	if module_kind in ["station","counter"]: visual.visible = view.art_visible(station_id)
	elif module_kind=="table":
		var count := view.seat_count(seat_group)
		var seats := visual.get_node_or_null("Seats")
		if seats!=null:
			for child in seats.get_children():
				if child is CanvasItem and String(child.name).is_valid_int(): child.visible = first_seat+int(String(child.name))<count
