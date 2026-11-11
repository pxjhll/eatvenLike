extends RefCounted
## Read-only boundary between authored art and the generic shop presentation.
## Optional visual decoration is not part of the gameplay contract.

const Dining := preload("res://presentation/shop/shop_dining.gd")
const Presentation := preload("res://content/characters/actor_presentation.tres")

static func prepare(shop: SpecShop) -> Dictionary:
	var errors: Array[Dictionary] = []
	if shop == null or shop.scene_path.is_empty() or not ResourceLoader.exists(shop.scene_path):
		_error(errors, "scene_resource", "scene_path", "An existing PackedScene is required.")
		return {"errors": errors, "art": null}
	var resource: Resource = load(shop.scene_path)
	if not resource is PackedScene or not resource.can_instantiate():
		_error(errors, "scene_resource", "scene_path", "An instantiable PackedScene is required.")
		return {"errors": errors, "art": null}
	var art: Node = resource.instantiate()
	errors = validate(shop, art)
	if not errors.is_empty():
		art.free()
		art = null
	return {"errors": errors, "art": art}

static func validate(shop: SpecShop, art: Node) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if shop == null:
		_error(errors, "required", "shop", "Shop data is required.")
		return errors
	for key in Presentation.validate():
		_error(errors, "shared_actor_profile", "actor_presentation." + key, "Shared actor values must be finite positive numbers.")
	if not art is Node2D:
		_error(errors, "scene_root", "scene_path", "Art root must be Node2D.")
		return errors
	if art.transform != Transform2D.IDENTITY:
		_error(errors, "transform", "art.transform", "Art root must use the shared world coordinate system.")
	var root := art.get_node_or_null("Anchors")
	if not root is Node2D:
		_error(errors, "required", "Anchors", "A Node2D Anchors root is required.")
		return errors
	if root.position != Vector2.ZERO:
		_error(errors, "transform", "Anchors.position", "Anchors must be at the world origin.")
	_scan(root, root, errors)
	var size: Variant = root.get_meta("world_size", Vector2(720, 1500))
	if not _positive_vector(size):
		_error(errors, "metadata", "Anchors.world_size", "World size must be a finite positive Vector2.")
	elif shop.layout != null and shop.layout.motion_version==1 and not is_equal_approx(shop.layout.motion_units,Presentation.scene_units(size)):
		_error(errors,"movement_units","layout.motion_units","Movement units must equal native canvas width / shared reference width.")
	var sortable_path: Variant = root.get_meta("sortables", "Sortables")
	if not sortable_path is String or String(sortable_path).is_empty() or not art.get_node_or_null(NodePath(str(sortable_path))) is Node2D:
		_error(errors, "required", "Anchors.sortables", "Sortables must reference a Node2D in this art scene.")
	else:
		var current: Node = art.get_node(NodePath(str(sortable_path)))
		if not current.get_meta("z_by_y", false) is bool:
			_error(errors, "metadata", "Anchors.sortables.z_by_y", "Expected a boolean.")
		while current != art and current != null:
			if current is CanvasItem and current.get_transform() != Transform2D.IDENTITY:
				_error(errors, "transform", "Anchors.sortables", "Actor parent chain must use world coordinates.")
			current = current.get_parent()
	var anchors := ShopAnchors.new(root)
	_points(anchors, "Queue", 1, errors)
	var stage_stations := {}
	for stage in shop.stages:
		if stage == null: continue
		for id in stage.stations: stage_stations[id] = true
	var stations := {}
	for station in shop.stations:
		if station == null: continue
		stations[station.id] = station
		var path := "Stations/" + station.id
		var actionable := stage_stations.has(station.id) or not station.tracks.is_empty() or not station.materials.is_empty()
		# The counter also exposes seats/flyers. Tea intentionally reaches it via its seat chip.
		if station.block == "counter":
			actionable = true
			if anchors.has("Chips/Seats") and shop.seat_groups.any(func(g: SpecSeatGroup) -> bool: return g != null and g.purpose == "dine"):
				actionable = false
		if actionable: _rect(anchors, path + "/Tap", errors)
		if stage_stations.has(station.id): _rect(anchors, path + "/Frame", errors)
		if (station.seatable or station.block == "counter") and shop.staff != null and shop.staff.can_drag:
			_rect(anchors, path + "/Post", errors)
			var found := false
			for name in anchors.children("Drops"):
				if anchors.meta("Drops/" + name, "post", "") == station.id: found = true
			if not found: _error(errors, "required", "Anchors.Drops", "Missing drop region for post " + station.id)
	for id in anchors.children("Stations"):
		if not stations.has(id): _error(errors, "reference", "Anchors.Stations." + id, "Unknown station.")
	for name in anchors.children("Drops"):
		var path := "Drops/" + name
		_rect(anchors, path, errors)
		var post: Variant = anchors.meta(path, "post", "")
		if not post is String or (not String(post).is_empty() and not stations.has(post)):
			_error(errors, "reference", "Anchors." + path + ".post", "Drop post must reference a station.")
	for group in shop.seat_groups:
		if group == null: continue
		var count := group.start
		for index in group.costs.size(): count += group.steps[index] if index < group.steps.size() else group.step
		if group.purpose == "wait":
			for stage in shop.stages:
				if stage != null: count = maxi(count, stage.wait_seats)
		if count > 0: _points(anchors, "Seats/" + group.id, count, errors)
	for connection in shop.connections:
		if connection == null or not connection.enabled: continue
		_rect(anchors, "Connections/" + connection.id + "/Frame", errors)
		_points(anchors, "Connections/" + connection.id + "/Path", 2, errors)
	var dining := art.find_children("*", "Node2D", true, false).any(func(n: Node) -> bool: return n.get_script() == Dining)
	if dining and shop.seat_groups.any(func(g: SpecSeatGroup) -> bool: return g != null and g.purpose == "dine"):
		_points(anchors, "Lanes", 1, errors)
		for path in ["Aisle", "Entrance"]:
			if not anchors.node(path) is Node2D: _error(errors, "required", "Anchors." + path, "Dining routes require this point.")
		# The installed component renders the first dine group, as dine_group()
		# does. Its cup renderer directly indexes table[seat / per_table].
		for group in shop.seat_groups:
			if group == null or group.purpose != "dine": continue
			var capacity := group.start
			if group.steps.is_empty():
				capacity += group.step * group.costs.size()
			else:
				for amount in group.steps: capacity += amount
			var path := "Tables/" + group.id
			var per_table: Variant = anchors.meta(path, "per_table", 2)
			# _scan reports malformed metadata; never convert/divide it first.
			if _positive_number(per_table) and float(per_table) == floorf(float(per_table)):
				_points(anchors, path, ceili(float(capacity) / float(per_table)), errors)
			break
	# Nav is optional for straight layouts. When authored, it must describe the
	# same coordinates the rules use; the runtime must not silently replace data.
	if errors.is_empty() and anchors.has("Nav") and shop.layout != null:
		var exported := anchors.layout(shop.layout)
		for key in ["nav", "cell", "grid_size", "areas", "obstacles", "obstacle_stations", "points", "posts"]:
			if exported.get(key) != shop.layout.get(key):
				_error(errors, "layout_mismatch", "Anchors.Nav." + key, "Art navigation differs from shop.layout." + key)
	return errors

static func _scan(node: Node, root: Node, errors: Array[Dictionary]) -> void:
	var path := "Anchors" if node == root else "Anchors/" + str(root.get_path_to(node))
	if not node is Node2D:
		_error(errors, "anchor_type", path, "Anchor nodes must be Node2D.")
	else:
		if not node.position.is_finite(): _error(errors, "finite", path + ".position", "Coordinates must be finite.")
		if not is_zero_approx(node.rotation) or node.scale != Vector2.ONE or not is_zero_approx(node.skew):
			_error(errors, "transform", path + ".transform", "Anchor readers support translation only.")
		if node is AnchorRect and not _positive_vector(node.size):
			_error(errors, "rectangle", path + ".size", "Interaction rectangles need finite positive size.")
	for key in node.get_meta_list():
		var value: Variant = node.get_meta(key)
		if key in ["customer_height", "staff_height", "customer_speed"]:
			_error(errors, "shared_actor_profile", path + "." + key, "Use the shared actor presentation profile instead of per-shop actor values.")
		elif key == "per_table":
			if not _positive_number(value) or float(value) != floorf(float(value)):
				_error(errors, "metadata", path + "." + key, "Expected a positive integer.")
		elif key in ["width", "cell"]:
			if not _positive_number(value): _error(errors, "metadata", path + "." + key, "Expected a finite positive number.")
		elif key in ["top_margin", "labels_z", "facing"]:
			if not _number(value): _error(errors, "metadata", path + "." + key, "Expected a finite number.")
		elif key in ["point", "sit_offset", "grab_band"]:
			if not value is Vector2 or not value.is_finite(): _error(errors, "metadata", path + "." + key, "Expected a finite Vector2.")
		elif key == "grid_size" and not value is Vector2i:
			_error(errors, "metadata", path + "." + key, "Expected a Vector2i.")
		elif key == "nav" and (not value is String or not value in ["straight", "grid"]):
			_error(errors, "metadata", path + "." + key, "Expected a supported navigation mode.")
		elif key in ["show", "z_by_y"] and not value is bool:
			_error(errors, "metadata", path + "." + key, "Expected a boolean.")
	for child in node.get_children(): _scan(child, root, errors)

static func _points(anchors: ShopAnchors, path: String, count: int, errors: Array[Dictionary]) -> void:
	if anchors.points(path).size() < count:
		_error(errors, "required", "Anchors." + path, "Requires at least %d points." % count)

static func _rect(anchors: ShopAnchors, path: String, errors: Array[Dictionary]) -> void:
	if not anchors.node(path) is AnchorRect or not anchors.rect(path).has_area():
		_error(errors, "required", "Anchors." + path, "A positive AnchorRect is required for this interaction.")

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _positive_number(value: Variant) -> bool:
	return _number(value) and float(value) > 0

static func _positive_vector(value: Variant) -> bool:
	return value is Vector2 and value.is_finite() and value.x > 0 and value.y > 0

static func _error(errors: Array[Dictionary], code: String, path: String, message: String) -> void:
	errors.append({"code": code, "path": path, "message": message})
