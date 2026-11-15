extends RefCounted
## Pure eligibility over outer command-owned facts; no copied unlock state.

static func compile(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return _error("invalid requirements")
	var result := {"stations":[],"boxes":[],"levels":{},"stage":0}
	for key in raw:
		if key=="workers": continue
		if not result.has(key): return _error("unsupported requirement: "+str(key))
		result[key] = raw[key]
	for key in ["stations","boxes"]:
		if not result[key] is Array: return _error("invalid requirement identifiers")
		var seen := {}
		for id in result[key]:
			if not id is String or id.is_empty() or seen.has(id): return _error("invalid or repeated requirement identifier")
			seen[id] = true
	if not result.stage is int or result.stage < 0 or not result.levels is Dictionary: return _error("invalid requirement stage or levels")
	for key in result.levels:
		if not key is String or key.is_empty() or not result.levels[key] is int or result.levels[key] < 1: return _error("invalid requirement upgrade level")
	if raw.has("workers"):
		var workers: Variant = raw.workers
		if not workers is Dictionary or workers.size()!=2 or not workers.get("minimum") is int or workers.minimum<1 or not workers.get("exclude_posts") is Array: return _error("invalid worker requirement")
		var seen := {}
		for post in workers.exclude_posts:
			if not post is String or post.is_empty() or seen.has(post): return _error("invalid or repeated excluded worker post")
			seen[post] = true
		result.workers = workers.duplicate(true)
	return {"definition":result.duplicate(true),"error":""}

static func reference_error(definition: Dictionary, owner: RefCounted) -> String:
	for post in definition.get("workers",{}).get("exclude_posts",[]):
		if not owner.shop.layout.posts.has(post): return "requirement references unknown worker post: "+post
	for id in definition.stations:
		if owner.shop.station(id) == null: return "requirement references unknown station: "+id
	for id in definition.boxes:
		if not owner.boxes.has(id): return "requirement references unknown material box: "+id
	for key in definition.levels:
		if owner.track_of(key) == null: return "requirement references unknown upgrade track: "+key
	return ""

static func met(definition: Dictionary, owner: RefCounted) -> bool:
	if definition.has("workers"):
		var count := 0
		for worker in owner.workers:
			if worker.deployed and worker.post not in definition.workers.exclude_posts: count += 1
		if count<int(definition.workers.minimum): return false
	if owner.stage_index < int(definition.stage): return false
	for id in definition.stations:
		if not owner.station_unlocked(id): return false
	for id in definition.boxes:
		if not owner.boxes.get(id,false): return false
	for key in definition.levels:
		if owner.level(key) < int(definition.levels[key]): return false
	return true

static func _error(message: String) -> Dictionary:
	return {"definition":{},"error":message}
