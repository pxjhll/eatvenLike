extends RefCounted
## Complete v1 spatial export. No business state, art mutation or resource writes.
const FIELDS := ["nav","cell","grid_size","areas","obstacles","obstacle_stations","points","posts","aliases","spawn_point","motion_version","motion_units","actor_areas","customer_points","customer_queue"]

static func _error(errors: Array, path: String, message: String) -> void:
	errors.append({"code":"module_layout","path":path,"message":message})

static func _offset(node: Node, art: Node) -> Vector2:
	var at := Vector2.ZERO
	while node!=null and node!=art:
		if node is Node2D: at += node.position
		node = node.get_parent()
	return at

static func _rect(node: Node, art: Node, errors: Array) -> Rect2:
	if not node is AnchorRect:
		_error(errors,str(node.name),"Spatial rectangles require AnchorRect.")
		return Rect2()
	return Rect2(_offset(node,art),node.size)

static func _grid(rect: Rect2, data: SpecLayout, errors: Array) -> Rect2i:
	for number in [rect.position.x,rect.position.y,rect.size.x,rect.size.y]:
		if not is_equal_approx(number/data.cell,roundf(number/data.cell)): _error(errors,"Nav.Areas","Grid regions must align exactly to cell boundaries after translation.")
	var box := Rect2i(Vector2i((rect.position/data.cell).round()),Vector2i((rect.size/data.cell).round()))
	if box.size.x<=0 or box.size.y<=0 or not Rect2i(Vector2i.ZERO,data.grid_size).encloses(box): _error(errors,"Nav.Areas","Regions must have positive size inside the grid.")
	return box

static func _put(out: Dictionary, key: String, at: Vector2, errors: Array) -> void:
	if out.has(key): _error(errors,key,"Spatial port has more than one owner.")
	else: out[key] = at

static func _children(node: Node, path: String) -> Array:
	var group := node.get_node_or_null(NodePath(path))
	return group.get_children() if group!=null else []

static func _regions(nav: Node, art: Node, data: SpecLayout, errors: Array) -> void:
	for node in _children(nav,"Areas"): data.areas.append(_grid(_rect(node,art,errors),data,errors))
	for profile in _children(nav,"Access"):
		var name := String(profile.name)
		if not data.actor_areas.has(name): data.actor_areas[name] = []
		for node in profile.get_children(): data.actor_areas[name].append(_grid(_rect(node,art,errors),data,errors))

static func _footprints(nav: Node, path: String, station: String, art: Node, data: SpecLayout, errors: Array) -> void:
	var bounds := Rect2(Vector2.ZERO,Vector2(data.grid_size)*data.cell)
	for node in _children(nav,path):
		var box := _rect(node,art,errors)
		if not bounds.encloses(box): _error(errors,path,"Footprint is outside the grid.")
		var gate: Variant = node.get_meta("station",station)
		if not gate is String: _error(errors,path,"Footprint station binding must be text."); continue
		data.obstacles.append(box)
		data.obstacle_stations.append(gate)

static func _points(nav: Node, path: String, out: Dictionary, art: Node, errors: Array) -> void:
	for node in _children(nav,path):
		if node is Node2D: _put(out,String(node.name),_offset(node,art),errors)
		else: _error(errors,path,"Ports must be Node2D.")

static func _geometry(data: SpecLayout, errors: Array) -> void:
	for profile in ["staff","customer"]:
		if not data.actor_areas.has(profile) or data.actor_areas[profile].is_empty(): _error(errors,"Nav.Access."+profile,"An explicit permission area is required.")
	for key in ["entrance","exit","pickup"]:
		if not data.customer_points.has(key): _error(errors,"Nav.Customers."+key,"Customer port is missing.")
	if data.customer_queue.is_empty(): _error(errors,"Queue","An explicit customer queue is required.")
	if not data.points.has(data.spawn_point): _error(errors,"Nav.spawn_point","Spawn point must exist.")
	for key in data.aliases:
		if not data.points.has(data.aliases[key]): _error(errors,"Nav.aliases."+key,"Alias target must exist.")
	if data.areas.is_empty(): _error(errors,"Nav.Areas","A walkable area is required.")
	if not errors.is_empty(): return
	var nav := RuleNav.new(data)
	var opened := {}
	for station in data.obstacle_stations:
		if not station.is_empty(): opened[station] = true
	nav.set_open(opened)
	var start: Vector2 = data.points[data.spawn_point]
	for ports in [data.points,data.posts]:
		for key in ports:
			if not nav.can_stand(ports[key],"staff") or nav.path(start,ports[key],"staff").is_empty(): _error(errors,"Nav.Points."+key,"Staff port must be clear and reachable with all footprints active.")
	var entrance: Vector2 = data.customer_points.entrance
	var customer: Array = data.customer_points.values()+data.customer_queue
	for at: Vector2 in customer:
		if not nav.can_stand(at,"customer") or nav.path(entrance,at,"customer").is_empty(): _error(errors,"Nav.Customers","Customer port must be clear and reachable within customer access.")

static func compile(root: Node, base: SpecLayout, scan: Dictionary) -> Dictionary:
	var errors: Array = []
	var nav: Node = root.get_node_or_null("Nav")
	if not scan.enabled or nav==null or base==null: return {"layout":null,"errors":[{"code":"module_layout","path":"Nav","message":"Module scenes require explicit Nav and a base layout."}]}
	var data: SpecLayout = base.duplicate(true)
	var cell: Variant = nav.get_meta("cell",0)
	var grid: Variant = nav.get_meta("grid_size",Vector2i.ZERO)
	var units: Variant = nav.get_meta("motion_units",0)
	var world: Variant = root.get_meta("world_size",Vector2(720,1200))
	if not (cell is float or cell is int) or not is_finite(float(cell)) or float(cell)<=0: _error(errors,"Nav.cell","Finite positive cell size is required.")
	if not grid is Vector2i or grid.x<=0 or grid.y<=0: _error(errors,"Nav.grid_size","Positive integer grid dimensions are required.")
	if not (units is float or units is int) or not is_finite(float(units)) or float(units)<=0: _error(errors,"Nav.motion_units","Finite positive density is required.")
	if not world is Vector2 or not world.is_finite() or world.x<=0 or world.y<=0: _error(errors,"Anchors.world_size","Finite positive world size is required.")
	if nav.get_meta("nav","")!="grid" or nav.get_meta("motion_version",0)!=1: _error(errors,"Nav.motion_version","Module scenes require grid navigation and motion version 1.")
	var aliases: Variant = nav.get_meta("aliases",{})
	var spawn: Variant = nav.get_meta("spawn_point","counter")
	if not aliases is Dictionary or not spawn is String: _error(errors,"Nav.aliases","Aliases must be a text map and spawn point must be text.")
	elif aliases.keys().any(func(key: Variant) -> bool: return not key is String or not aliases[key] is String): _error(errors,"Nav.aliases","Alias keys and values must be text.")
	if not errors.is_empty(): return {"layout":null,"errors":errors}
	if not is_equal_approx(float(units),world.x/720.0): _error(errors,"Nav.motion_units","Density must equal native width / 720.")
	data.nav = "grid"
	data.motion_version = 1
	data.motion_units = float(units)
	data.cell = float(cell)
	data.grid_size = grid
	data.spawn_point = spawn
	data.aliases.clear()
	for key in aliases: data.aliases[key] = aliases[key]
	for key in ["areas","obstacles","obstacle_stations","points","posts","actor_areas","customer_points","customer_queue"]: data.get(key).clear()
	var art := root.get_parent()
	_regions(nav,art,data,errors)
	_footprints(nav,"Obstacles","",art,data,errors)
	_points(nav,"Points",data.points,art,errors)
	_points(nav,"Posts",data.posts,art,errors)
	_points(nav,"Customers/Points",data.customer_points,art,errors)
	for module in scan.modules:
		var local: Node = module.get_node_or_null("Nav")
		if local==null: continue
		_regions(local,art,data,errors)
		_footprints(local,"Footprints",module.station_id if module.module_kind in ["station","counter"] else "",art,data,errors)
		_points(local,"Points",data.points,art,errors)
		_points(local,"Posts",data.posts,art,errors)
		_points(local,"Customers",data.customer_points,art,errors)
		if module.module_kind in ["station","counter"]:
			for pair in [["Work",data.points],["Post",data.posts]]:
				var node: Node = local.get_node_or_null(NodePath(pair[0]))
				if node is Node2D: _put(pair[1],module.station_id,_offset(node,art),errors)
		elif module.module_kind=="table":
			for node in _children(local,"Seats"):
				if not String(node.name).is_valid_int() or int(String(node.name))<0: _error(errors,module.module_id,"Seat ports require nonnegative numeric names."); continue
				var key := "%s/%d"%[module.seat_group,module.first_seat+int(String(node.name))]
				_put(data.points,key,_offset(node,art),errors)
				_put(data.customer_points,("wait:" if module.seat_purpose=="wait" else "seat:")+key,_offset(node,art),errors)
	var queue: Array = []
	for path: String in scan.nodes:
		if path.begins_with("Queue/") and path.count("/")==1:
			if not path.get_file().is_valid_int() or int(path.get_file())<0: _error(errors,"Queue","Queue points require nonnegative numeric names.")
			else: queue.append(path)
	queue.sort_custom(func(a: String,b: String) -> bool: return int(a.get_file())<int(b.get_file()))
	for index in queue.size():
		var path: String = queue[index]
		if path.get_file()!=str(index): _error(errors,"Queue","Queue points must be contiguous from zero.")
		data.customer_queue.append(_offset(scan.nodes[path],art))
	_geometry(data,errors)
	return {"layout":data if errors.is_empty() else null,"errors":errors}
