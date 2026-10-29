extends RefCounted
## Navigation subcells for the existing reference scene; this never edits the art.

const CELL := 20.0
const POINTS := {
	"supply": Vector2(190, 310), "boil": Vector2(350, 330),
	"mix": Vector2(470, 410), "topping": Vector2(190, 490),
	"seal": Vector2(530, 430), "shelf": Vector2(470, 670),
	"counter": Vector2(410, 930), "belt_in": Vector2(410, 390),
	"seal_belt": Vector2(530, 430),
}
const STATION_ART := {
	"supply": "Sortables/IngredientTable", "boil": "Sortables/MachineTable/PearlPot",
	"mix": "Sortables/MachineTable/Brewer", "topping": "Sortables/PrepBench",
	"seal": "Sortables/Sealer", "shelf": "Sortables/Rack", "counter": "Sortables/Checkout",
}
## A seated operator and a mobile courier use different physical interaction points.
const POST_POINTS := {"boil": Vector2(270, 330), "topping": Vector2(190, 410)}
const POST_RECTS := {"boil": Rect2(241, 114, 176, 176), "topping": Rect2(20, 246, 128, 350)}
const AUTOMATIC_RECTS := [Rect2(418, 115, 100, 165), Rect2(547, 195, 126, 200)]
static var _grid: ShopGridDef
static var _paths := {}


static func drop_target(point: Vector2) -> Dictionary:
	for post in POST_RECTS:
		if POST_RECTS[post].has_point(point) or point.distance_to(POST_POINTS[post]) < 30:
			return {"kind": "post", "post": post, "point": POST_POINTS[post]}
	for rect in AUTOMATIC_RECTS:
		if rect.has_point(point):
			return {"kind": "invalid", "reason": "automatic_station"}
	var map := grid()
	var cell := map.world_to_cell(point, CELL)
	if map.contains_cell(cell) and not cell in map.blocked_cells:
		if path(map.cell_center(cell, CELL), POINTS.counter).is_empty():
			return {"kind": "invalid", "reason": "unreachable"}
		return {"kind": "mobile", "post": "", "point": map.cell_center(cell, CELL)}
	return {"kind": "invalid", "reason": "blocked_ground"}


static func grid() -> ShopGridDef:
	if _grid != null:
		return _grid
	_grid = ShopGridDef.new()
	_grid.kitchen_rect = Rect2i(2, 13, 32, 22)
	_grid.front_rect = Rect2i(2, 35, 32, 25)
	var obstacles := [
		Rect2(6, 253, 153, 354), # long preparation bench
		Rect2(228, 233, 304, 69), # machine support table
		Rect2(11, 218, 249, 89), # ingredient table
		Rect2(364, 290, 306, 90), # horizontal conveyor base
		Rect2(575, 362, 88, 206), # vertical conveyor base
		Rect2(500, 565, 205, 148), # shelf
		Rect2(-30, 690, 260, 176), # partition, with real doorway
		Rect2(474, 690, 260, 176),
		Rect2(16, 944, 664, 136), # checkout
		Rect2(20, 864, 294, 190), # glass display
	]
	for y in 60:
		for x in 36:
			var cell := Vector2i(x, y)
			var center := _grid.cell_center(cell, CELL)
			for box in obstacles:
				if box.has_point(center):
					_grid.blocked_cells.append(cell)
					break
	return _grid


static func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var map := grid()
	var start := map.world_to_cell(from, CELL)
	var finish := map.world_to_cell(to, CELL)
	var key := "%s>%s" % [start, finish]
	if not _paths.has(key):
		var points := PackedVector2Array()
		for cell in map.find_path(start, finish):
			points.append(map.cell_center(cell, CELL))
		_paths[key] = points
	var route: PackedVector2Array = _paths[key].duplicate()
	if not route.is_empty():
		route[0] = from
		route[route.size() - 1] = to
	return route


static func belt_path(route: String) -> PackedVector2Array:
	if route == "topping_to_seal":
		return PackedVector2Array([Vector2(400, 320), Vector2(610, 320)])
	return PackedVector2Array([Vector2(620, 400), Vector2(620, 550), Vector2(556, 580)])
