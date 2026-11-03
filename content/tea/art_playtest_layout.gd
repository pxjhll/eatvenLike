extends RefCounted
## Navigation and display anchors share world coordinates; furniture images remain independent.

const CELL := 20.0
const WORLD_SIZE := Vector2(720, 1500)
## The dining room sits DINING_SHIFT lower than the FigCraft source so two queue rows fit in front of the counter.
const DINING_SHIFT := 90.0
const DINING_TABLES := [Vector2(191, 1151.5), Vector2(530, 1151.5), Vector2(192, 1348.5), Vector2(528, 1348.5)]
const DINING_SEATS := [Vector2(85, 1143.083333), Vector2(296, 1143.083333), Vector2(424, 1143.083333), Vector2(635, 1143.083333), Vector2(86, 1340.083333), Vector2(297, 1340.083333), Vector2(422, 1340.083333), Vector2(633, 1340.083333)]
## Customers come in at the bottom, walk up the aisle between the tables and queue in front of the counter.
const ENTRANCE := Vector2(360, 1540)
## Customers are drawn at the size they had before the FigCraft layout.
const CUSTOMER_HEIGHT := 110.0
const AISLE_X := 360.0
## Walkways just above each row of chairs: in front of the counter queue, and between the two rows.
const DINING_LANES := [1045.0, 1226.0]
const QUEUE_ROWS := [925.0, 1012.0]
const POINTS := {
	"supply": Vector2(210, 310), "boil": Vector2(350, 330),
	"mix": Vector2(480, 330), "topping": Vector2(190, 490),
	"seal": Vector2(530, 430), "shelf": Vector2(490, 630),
	"counter": Vector2(410, 730), "belt_in": Vector2(530, 430),
	"lemonade": Vector2(190, 650),
	# Lemon tea is hand-pressed at the front, beside the ice box on the counter.
	"press": Vector2(315, 690),
	# The packing station at the right end of the counter, behind the bag.
	"pack": Vector2(620, 730),
	"seal_belt": Vector2(530, 430),
}
const STATION_ART := {
	"supply": "Sortables/IngredientTable", "boil": "Sortables/MachineTable/PearlPot",
	"mix": "Sortables/MachineTable/Brewer", "topping": "Sortables/PrepBench",
	"seal": "Sortables/Sealer", "shelf": "Sortables/Rack", "counter": "Sortables/Checkout",
	"press": "Sortables/Checkout/FrontLemon", "lemonade": "Sortables/DisplayCase",
}
## A seated operator and a mobile courier use different physical interaction points.
## The counter post is front-of-house: that employee only serves customers.
const POST_POINTS := {"boil": Vector2(270, 330), "topping": Vector2(190, 410), "counter": Vector2(410, 730)}
const POST_RECTS := {"boil": Rect2(291, 117, 143, 110), "topping": Rect2(20, 269, 128, 350), "counter": Rect2(32, 709, 656, 148)}
const FRONT_WORK_RECTS := [Rect2(31, 595, 123, 184), Rect2(189, 656, 113, 141)]
const AUTOMATIC_RECTS := [Rect2(440, 79, 110, 155), Rect2(548, 198, 145, 200)]
static var _grid: ShopGridDef
static var _paths := {}


static func drop_target(point: Vector2) -> Dictionary:
	for rect in FRONT_WORK_RECTS:
		if rect.has_point(point):
			return {"kind": "post", "post": "counter", "point": POST_POINTS.counter}
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
		Rect2(23, 269, 122, 348), # approved long preparation bench
		Rect2(267, 235, 290, 70), # powered cabinet
		Rect2(22, 220, 235, 75), # ingredient table
		Rect2(590, 367, 72, 213), # remaining vertical conveyor
		Rect2(560, 205, 132, 185), # sealing machine
		Rect2(522, 530, 178, 154), # shelf
		Rect2(32, 595, 122, 185), # lemonade dispenser
		Rect2(32, 709, 291, 148), # deeper left counter block
		Rect2(323, 752, 365, 105), # checkout wing and its open staff recess
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


## Two rows of four in front of the counter, the first customer at the register.
static func queue_point(index: int) -> Vector2:
	return Vector2(530 - (index % 4) * 105, QUEUE_ROWS[mini(index / 4, QUEUE_ROWS.size() - 1)])


## Where a seated customer sits (the chair's seat, a little above its floor anchor).
static func seat_point(seat: int) -> Vector2:
	return DINING_SEATS[seat] + Vector2(0, -12)


## From the queue to a chair: along the lane above the chair's row, via the aisle for the back row.
static func seat_path(from: Vector2, seat: int) -> PackedVector2Array:
	var lane: float = DINING_LANES[0 if seat < 4 else 1]
	var target := seat_point(seat)
	var points := PackedVector2Array([Vector2(from.x, DINING_LANES[0])])
	if seat >= 4:
		points.append(Vector2(AISLE_X, DINING_LANES[0]))
		points.append(Vector2(AISLE_X, lane))
	points.append(Vector2(target.x, lane))
	points.append(target)
	return points


## From a chair (or the queue) out through the aisle and the door at the bottom.
static func exit_path(from: Vector2, seat := -1) -> PackedVector2Array:
	var lane: float = DINING_LANES[0] if seat < 4 else DINING_LANES[1]
	return PackedVector2Array([Vector2(from.x, lane), Vector2(AISLE_X, lane), ENTRANCE])


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
		return PackedVector2Array([Vector2(400, 320), Vector2(610, 320)]) # legacy route, no horizontal furniture
	return PackedVector2Array([Vector2(626, 391), Vector2(626, 512), Vector2(608, 574)])
