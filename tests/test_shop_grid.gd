extends "res://tests/test_case.gd"


func _grid() -> ShopGridDef:
	var grid := ShopGridDef.new()
	grid.kitchen_rect = Rect2i(0, 0, 6, 5)
	grid.front_rect = Rect2i(0, 5, 6, 5)
	return grid


func test_grid_uses_both_rooms_and_excludes_outside_cells() -> void:
	var grid := _grid()
	check(grid.contains_cell(Vector2i(0, 0)), "kitchen is part of layout")
	check(grid.contains_cell(Vector2i(5, 9)), "front hall is part of layout")
	check(not grid.contains_cell(Vector2i(6, 0)), "right boundary is exclusive")
	check(not grid.contains_cell(Vector2i(-1, 5)), "negative column is outside")
	grid.front_rect = Rect2i(0, 6, 6, 4)
	check(not grid.contains_cell(Vector2i(2, 5)), "gap between room rectangles is outside")


func test_long_table_occupancy_and_rotated_operation_point() -> void:
	var grid := _grid()
	var cells: Array[Vector2i] = grid.footprint_cells(Vector2i(1, 1), Vector2i(1, 3), 0)
	check_eq(cells.size(), 3, "one-by-three table occupies three cells")
	check(Vector2i(1, 3) in cells, "table extends three rows")
	var turned: Array[Vector2i] = grid.footprint_cells(Vector2i(1, 1), Vector2i(1, 3), 1)
	check_eq(turned.size(), 3, "rotation preserves occupied area")
	check(Vector2i(3, 1) in turned, "clockwise table extends three columns")
	check(not Vector2i(1, 2) in turned, "rotated table does not retain old cells")
	check_eq(grid.rotate_offset(Vector2i(0, 3), Vector2i(1, 3), 1), Vector2i(-1, 0), "external operation point rotates around the same footprint")
	check_eq(grid.rotate_offset(Vector2i(0, 3), Vector2i(1, 3), 4), Vector2i(0, 3), "full rotation returns original point")


func test_placement_rejects_invalid_bounds_walls_and_other_furniture() -> void:
	var grid := _grid()
	grid.blocked_cells = [Vector2i(2, 2)]
	var occupied: Array[Vector2i] = [Vector2i(1, 1)]
	check_eq(grid.placement_error(Vector2i(0, 0), Vector2i.ZERO), "invalid_footprint", "unconfigured footprint cannot be placed")
	check_eq(grid.placement_error(Vector2i(5, 0), Vector2i(2, 1)), "out_of_bounds", "whole footprint must be inside")
	check_eq(grid.placement_error(Vector2i(2, 1), Vector2i(1, 2)), "blocked", "wall blocks furniture")
	check_eq(grid.placement_error(Vector2i(1, 1), Vector2i.ONE, 0, occupied), "occupied", "furniture cannot overlap")
	check_eq(grid.placement_error(Vector2i(5, 0), Vector2i(2, 1), 1), "", "rotation can make a footprint fit")
	check_eq(grid.placement_error(Vector2i(0, 0), Vector2i.ONE, 0, occupied), "", "valid placement accepted")
	check_eq(occupied, [Vector2i(1, 1)], "validation never mutates occupancy")


func test_worker_route_goes_through_door_and_counts_actual_travel() -> void:
	var grid := _grid()
	# Partition across the kitchen, with a door at column 4.
	for x in 6:
		if x != 4:
			grid.blocked_cells.append(Vector2i(x, 4))
	var start := Vector2i(1, 3)
	var finish := Vector2i(1, 5)
	var path: Array[Vector2i] = grid.find_path(start, finish)
	check(not path.is_empty(), "open doorway yields a route")
	if path.is_empty():
		return
	check_eq(path.front(), start, "route starts at the employee")
	check_eq(path.back(), finish, "route reaches the work point")
	check(Vector2i(4, 4) in path, "route passes through the doorway")
	check_eq(path.size() - 1, 8, "actual detour is eight cell edges")
	for i in range(1, path.size()):
		var step: Vector2i = path[i] - path[i - 1]
		check_eq(absi(step.x) + absi(step.y), 1, "no diagonal corner cutting")
	check_eq(grid.travel_seconds(start, finish, 2.0), 4.0, "two cells per second takes four seconds")
	check_eq(grid.find_path(start, finish), path, "route selection is deterministic")


func test_unreachable_tasks_and_blocked_endpoints_have_no_route() -> void:
	var grid := _grid()
	var occupied: Array[Vector2i] = []
	for x in 6:
		occupied.append(Vector2i(x, 4))
	var start := Vector2i(1, 3)
	var finish := Vector2i(1, 5)
	check(grid.find_path(start, finish, occupied).is_empty(), "closed partition makes task unreachable")
	check(is_inf(grid.travel_seconds(start, finish, 2.0, occupied)), "unreachable is not zero travel time")
	check(grid.find_path(Vector2i(1, 4), finish, occupied).is_empty(), "blocked start is invalid")
	check(grid.find_path(start, Vector2i(1, 4), occupied).is_empty(), "blocked target is invalid")
	check_eq(grid.find_path(start, start).size(), 1, "already there has one path point")
	check_eq(grid.travel_seconds(start, start, 2.0), 0.0, "already at work point takes no travel")
	check(is_inf(grid.travel_seconds(start, finish, 0.0)), "invalid walking speed cannot produce an instant arrival")


func test_grid_and_picture_coordinates_are_independent() -> void:
	var grid := _grid()
	var cell := Vector2i(2, 3)
	var origin := Vector2(40, 118)
	check_eq(grid.cell_center(cell, 100.0, origin), Vector2(290, 468), "display scale can be 100 units per cell")
	check_eq(grid.cell_center(cell, 256.0), Vector2(640, 896), "art scale can independently be 256 pixels per cell")
	check_eq(grid.world_to_cell(Vector2(290, 468), 100.0, origin), cell, "display coordinate converts back to the same cell")
	check_eq(grid.world_to_cell(origin - Vector2.ONE, 100.0, origin), Vector2i(-1, -1), "negative coordinates floor instead of truncating")
	check_eq(grid.footprint_cells(Vector2i.ZERO, Vector2i(1, 3)).size(), 3, "texture dimensions never determine occupied cells")
