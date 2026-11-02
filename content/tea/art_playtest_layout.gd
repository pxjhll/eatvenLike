extends RefCounted
## Navigation and display anchors share world coordinates; furniture images remain independent.

const CELL := 20.0
const WORLD_SIZE := Vector2(720, 1500)
const DINING_TABLES := [Vector2(145, 1060), Vector2(575, 1060), Vector2(145, 1270), Vector2(575, 1270)]
const DINING_SEATS := [Vector2(57, 1072), Vector2(233, 1072), Vector2(487, 1072), Vector2(663, 1072), Vector2(57, 1282), Vector2(233, 1282), Vector2(487, 1282), Vector2(663, 1282)]
const POINTS := {
	"supply": Vector2(190, 310), "boil": Vector2(350, 330),
	"mix": Vector2(470, 410), "topping": Vector2(190, 490),
	"seal": Vector2(530, 430), "shelf": Vector2(470, 670),
	"counter": Vector2(410, 750), "belt_in": Vector2(410, 390),
	"lemonade": Vector2(250, 750), "lemon_front": Vector2(330, 750),
	# Standing spot at the press table (right wall, between the sealer and the shelf).
	"press": Vector2(540, 490),
	"seal_belt": Vector2(530, 430),
}
const STATION_ART := {
	"supply": "Sortables/IngredientTable", "boil": "Sortables/MachineTable/PearlPot",
	"mix": "Sortables/MachineTable/Brewer", "topping": "Sortables/PrepBench",
	"seal": "Sortables/Sealer", "shelf": "Sortables/Rack", "counter": "Sortables/Checkout",
	"press": "Sortables/PressTable",
	"lemon_front": "Sortables/Checkout/FrontLemon", "lemonade": "Sortables/DisplayCase",
}
## A seated operator and a mobile courier use different physical interaction points.
## The counter post is front-of-house: that employee only serves customers.
const POST_POINTS := {"boil": Vector2(270, 330), "topping": Vector2(190, 410), "counter": Vector2(410, 750)}
const POST_RECTS := {"boil": Rect2(241, 114, 176, 176), "topping": Rect2(20, 246, 128, 350), "counter": Rect2(285, 720, 395, 160)}
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
	_grid.front_rect = Rect2i(2, 35, 32, 36)
	var obstacles := [
		Rect2(6, 253, 153, 354), # long preparation bench
		Rect2(228, 251, 304, 69), # machine support table, clear of the header
		Rect2(11, 218, 249, 89), # ingredient table
		Rect2(364, 290, 306, 90), # horizontal conveyor base
		Rect2(575, 362, 88, 206), # vertical conveyor base
		Rect2(560, 415, 130, 120), # press table
		Rect2(500, 565, 205, 148), # shelf
		Rect2(-30, 650, 260, 68), # low partition, with real doorway
		Rect2(500, 650, 234, 68),
		Rect2(16, 790, 664, 110), # checkout, staff work from its back edge
		Rect2(45, 740, 180, 140), # lemonade dispenser and its separate table
	]
	for seat_table in DINING_TABLES:
		obstacles.append(Rect2(seat_table - Vector2(110, 68), Vector2(220, 120)))
	for y in 75:
		for x in 36:
			var cell := Vector2i(x, y)
			var center := _grid.cell_center(cell, CELL)
			for box in obstacles:
				if box.has_point(center):
					_grid.blocked_cells.append(cell)
					break
	return _grid


static func queue_point(index: int) -> Vector2:
	return Vector2(310 + (index % 2) * 100, 945 + (index / 2) * 100)


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
