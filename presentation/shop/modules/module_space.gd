extends RefCounted
## Read-only projection of local module anchors into the existing anchor API.
const Module := preload("res://presentation/shop/modules/shop_module.gd")
const Layout := preload("res://presentation/shop/modules/module_layout.gd")

static func error(errors: Array, code: String, path: String, message: String) -> void:
	errors.append({"code":code,"path":path,"message":message})

static func offset(node: Node, art: Node) -> Vector2:
	var result := Vector2.ZERO
	var current := node
	while current!=null and current!=art:
		if current is Node2D: result += current.position
		current = current.get_parent()
	return result

static func _shape(node: Node, errors: Array) -> void:
	if not node is Node2D:
		error(errors,"module_anchor",str(node.name),"Module anchors must be Node2D.")
	else:
		if not node.position.is_finite() or node.scale!=Vector2.ONE or not is_zero_approx(node.rotation) or not is_zero_approx(node.skew):
			error(errors,"module_transform",str(node.name),"Module coordinates support finite translation only.")
		if node is AnchorRect and (not node.size.is_finite() or node.size.x<=0 or node.size.y<=0):
			error(errors,"module_rectangle",str(node.name),"A finite positive rectangle is required.")
	for child in node.get_children(): _shape(child,errors)

static func _tree(result: Dictionary, node: Node, path: String) -> void:
	if result.nodes.has(path):
		var previous: Node = result.nodes[path]
		if node.get_child_count()==0 or previous.get_child_count()==0 or node is AnchorRect or previous is AnchorRect:
			error(result.errors,"module_collision",path,"Anchor binding is already owned by another source.")
		else:
			for key in node.get_meta_list():
				if not previous.has_meta(key) or previous.get_meta(key)!=node.get_meta(key): error(result.errors,"module_collision",path+"."+key,"Shared group metadata must agree.")
	else: result.nodes[path] = node
	for child in node.get_children(): _tree(result,child,String(child.name) if path=="." else path+"/"+String(child.name))

static func _bind(result: Dictionary, module: Node, local: String, target: String) -> void:
	var node := module.get_node_or_null(NodePath(local))
	if node!=null: _tree(result,node,target)

static func _metadata(result: Dictionary, path: String, key: String, value: Variant) -> void:
	if not result.metadata.has(path): result.metadata[path] = {}
	var source: Node = result.nodes.get(path)
	if (source!=null and source.has_meta(key) and source.get_meta(key)!=value) or (result.metadata[path].has(key) and result.metadata[path][key]!=value):
		error(result.errors,"module_collision",path+"."+key,"Shared group metadata must agree.")
	else: result.metadata[path][key] = value

static func _id(value: String) -> bool:
	return not value.is_empty() and value.is_valid_identifier()

static func _required(module: Node, paths: Array, errors: Array) -> void:
	for path: String in paths:
		if not module.get_node_or_null(NodePath(path)) is Node2D: error(errors,"module_required",str(module.name)+"/"+path,"Module port or visual container is missing.")

static func _modules(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child.get_script()==Module: out.append(child)
		_modules(child,out)

static func collect(root: Node) -> Dictionary:
	var result := {"enabled":false,"nodes":{},"metadata":{},"modules":[],"errors":[]}
	if root==null: return result
	var art := root.get_parent()
	if art==null: return result
	_modules(art,result.modules)
	var version: Variant = root.get_meta("module_version",0)
	result.enabled = version==1 and version is int
	if not result.enabled:
		if root.has_meta("module_version") or not result.modules.is_empty(): error(result.errors,"module_version","Anchors.module_version","Editable modules require supported integer module_version=1.")
		return result
	_tree(result,root,".")
	_shape(root,result.errors)
	if not art is Node2D or art.transform!=Transform2D.IDENTITY or root.position!=Vector2.ZERO: error(result.errors,"module_transform","Anchors","Art and anchor roots must use world coordinates.")
	var ids := {}
	for module in result.modules:
		var id: String = module.module_id
		if not _id(id) or ids.has(id): error(result.errors,"module_id",str(module.name),"A unique identifier is required for each module.")
		ids[id] = true
		var current: Node = module
		while current!=null and current!=art:
			if current.get_script()==Module and current!=module: error(result.errors,"module_nesting",id,"Modules cannot contain other modules.")
			if not current is Node2D or not current.position.is_finite() or current.scale!=Vector2.ONE or not is_zero_approx(current.rotation) or not is_zero_approx(current.skew): error(result.errors,"module_transform",id,"Module parent chain supports finite translation only.")
			current = current.get_parent()
		_required(module,["Visual","Anchors","Nav"],result.errors)
		for path in ["Anchors","Nav"]:
			var local: Node = module.get_node_or_null(path)
			if local!=null: _shape(local,result.errors)
		match module.module_kind:
			"station","counter":
				if not _id(module.station_id): error(result.errors,"module_station",id,"Station binding must be a stable identifier.")
				_required(module,["Anchors/Station/Tap","Anchors/Station/Frame","Nav/Work"],result.errors)
				_bind(result,module,"Anchors/Station","Stations/"+module.station_id)
				_bind(result,module,"Anchors/Drop","Drops/"+id)
				if module.has_node("Anchors/Drop"): result.metadata["Drops/"+id] = {"post":module.station_id}
				if module.module_kind=="counter": _bind(result,module,"Anchors/Counter","Counter")
			"table":
				if not _id(module.seat_group) or module.first_seat<0 or module.table_index<0 or module.seat_purpose not in ["dine","wait"]: error(result.errors,"module_seats",id,"Seat group, indices and purpose must be valid.")
				_required(module,["Anchors/Table","Anchors/Seats","Nav/Seats"],result.errors)
				if module.seats_per_table<=0 or module.first_seat%maxi(1,module.seats_per_table)!=0 or module.table_index!=module.first_seat/maxi(1,module.seats_per_table): error(result.errors,"module_seats",id,"Table index and seat range must agree with seats_per_table.")
				_metadata(result,"Tables/"+module.seat_group,"per_table",module.seats_per_table)
				_bind(result,module,"Anchors/Table","Tables/%s/%d"%[module.seat_group,module.table_index])
				var seats: Node = module.get_node_or_null("Anchors/Seats")
				if seats!=null:
					if seats.get_child_count()==0: error(result.errors,"module_seats",id,"A table needs at least one seat.")
					if seats.get_child_count()>module.seats_per_table: error(result.errors,"module_seats",id,"Seat count exceeds declared table capacity.")
					for key in seats.get_meta_list(): _metadata(result,"Seats/"+module.seat_group,key,seats.get_meta(key))
					for index in seats.get_child_count():
						_required(module,["Anchors/Seats/%d"%index,"Nav/Seats/%d"%index],result.errors)
						_bind(result,module,"Anchors/Seats/%d"%index,"Seats/%s/%d"%[module.seat_group,module.first_seat+index])
			"entrance","space":
				var local: Node = module.get_node_or_null("Anchors")
				if local!=null:
					for child in local.get_children(): _tree(result,child,String(child.name))
			_ : error(result.errors,"module_kind",id,"Unknown module kind.")
	return result

static func export_layout(root: Node, base: SpecLayout) -> Dictionary:
	var scan := collect(root)
	if not scan.errors.is_empty(): return {"layout":null,"errors":scan.errors}
	return Layout.compile(root,base,scan)
