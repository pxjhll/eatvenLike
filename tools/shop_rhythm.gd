extends SceneTree
## Deterministic diagnostics, not an economy tuner. Never writes production data.
const SHOPS := ["tea","pancake","stirfry"]
const Content := preload("res://game/rules/shop_content_contract.gd")
const STEP := 0.1

static func sample(shop: SpecShop, seconds: float, seed_: int) -> Dictionary:
	var rules := ShopRules.new(shop,seed_)
	rules.gold = 1000000.0
	for unused in shop.stages.size()+1:
		var next := rules.next_unlock()
		if next.is_empty(): break
		rules.unlock(next)
	for unused in 10:
		var box := rules.pending_box()
		if box.is_empty(): break
		rules.unlock_box(box)
	while rules.workers.size()<2:
		if not rules.hire().is_empty(): break
		for worker: Dictionary in rules.roster:
			if not worker.deployed: rules.deploy_worker(worker.id)
	var ticks := roundi(seconds/STEP)
	var result := {"content":Content.describe(shop),"ticks":ticks,"staff":rules.workers.size(),"sold":0,"revenue":0,"lost":0,"orders_done":-1,
		"sale_events":0,"first_sale_tick":-1,"sale_gap_ticks":{"median":-1,"p90":-1,"maximum":-1},"minutes":[],
		"worker_ticks":{"walking":0,"operating":0,"waiting":0,"idle":0},"blocked_ticks":{},"queue_full_ticks":0,
		"illegal_footprints":0,"overspeed_samples":0,"restore_error":""}
	var sale_ticks: Array[int] = []
	var listener := func(_event: Dictionary) -> void: sale_ticks.append(roundi(rules.clock/STEP))
	rules.events.on("sale",listener)
	for tick in ticks:
		var positions := {}
		for worker: Dictionary in rules.workers: positions[worker.id] = {"pos":worker.pos,"speed":rules.walk_speed(worker)}
		rules.step(STEP)
		if rules.queue_size()>=rules.queue_capacity(): result.queue_full_ticks += 1
		for worker: Dictionary in rules.workers:
			var category := "idle"
			var action: Dictionary = worker.get("action",{})
			if action.get("status","")=="blocked":
				category = "waiting"
				var reason := str(action.reason)
				result.blocked_ticks[reason] = int(result.blocked_ticks.get(reason,0))+1
			elif worker.walking: category = "walking"
			elif worker.phase in ["work","pickup","dropoff"]: category = "operating"
			elif worker.phase=="wait": category = "waiting"
			result.worker_ticks[category] += 1
			if not rules.nav.can_stand(worker.pos,"staff"): result.illegal_footprints += 1
			if positions.has(worker.id):
				var allowed: float = maxf(positions[worker.id].speed,rules.walk_speed(worker))*STEP+0.01
				if Vector2(positions[worker.id].pos).distance_to(worker.pos)>allowed: result.overspeed_samples += 1
		for row: Dictionary in (rules.runtime.service.customers.snapshot().customers if rules.runtime!=null else rules.movement.customers.values()):
			if not rules.nav.can_stand(row.pos,"customer"): result.illegal_footprints += 1
		if (tick+1)%600==0:
			result.minutes.append({"tick":tick+1,"sold":rules.sold,"revenue":rules.revenue,"lost":rules.lost,"queue":rules.queue_size()})
	rules.events.off("sale",listener)
	result.sold = rules.sold
	result.revenue = rules.revenue
	result.lost = rules.lost
	result.orders_done = rules.runtime.service.orders.snapshot().orders.filter(func(order: Dictionary) -> bool: return order.state=="delivered").size() if rules.runtime!=null else -1
	result.sale_events = sale_ticks.size()
	if not sale_ticks.is_empty(): result.first_sale_tick = sale_ticks[0]
	var gaps: Array[int] = []
	for index in range(1,sale_ticks.size()): gaps.append(sale_ticks[index]-sale_ticks[index-1])
	gaps.sort()
	if not gaps.is_empty(): result.sale_gap_ticks = {"median":gaps[(gaps.size()-1)/2],"p90":gaps[ceili(gaps.size()*0.9)-1],"maximum":gaps[-1]}
	result.restore_error = ShopRules.new(shop,seed_).load_dict(rules.to_dict())
	return result

static func compare(actual: Dictionary, expected: Dictionary) -> Array[String]:
	# Godot JSON parses numbers as floats; compare the same persisted data shape.
	actual = JSON.parse_string(JSON.stringify(actual))
	expected = JSON.parse_string(JSON.stringify(expected))
	var errors: Array[String] = []
	if actual.get("version")!=expected.get("version"): errors.append("report version differs")
	if actual.get("setup")!=expected.get("setup"): errors.append("simulation setup differs")
	if not actual.get("shops") is Dictionary or not expected.get("shops") is Dictionary:
		errors.append("shop reports missing")
		return errors
	var actual_ids: Array = actual.shops.keys()
	var expected_ids: Array = expected.shops.keys()
	actual_ids.sort()
	expected_ids.sort()
	if actual_ids!=expected_ids: errors.append("shop set differs")
	for id in expected.shops:
		if not actual.shops.has(id): continue
		if actual.shops[id]!=expected.shops[id]: errors.append("metrics or content differ: "+str(id))
	return errors

func _initialize() -> void:
	var seconds := 600.0
	var seed_ := 42
	var output := ""
	var baseline := ""
	var invalid := false
	var seen := {}
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=",0)
		var value := arg.substr(key.length()+1)
		if seen.has(key) or not arg.contains("="): invalid = true; continue
		seen[key] = true
		match key:
			"--seconds":
				if not value.is_valid_float(): invalid = true
				else: seconds = value.to_float()
			"--seed":
				if not value.is_valid_int(): invalid = true
				else: seed_ = value.to_int()
			"--output": output = value
			"--check": baseline = value
			_: invalid = true
	if not is_finite(seconds) or seconds<=0 or seconds>3600 or seed_<0 or seed_>2147483647: invalid = true
	if not output.is_empty() and not (output.begins_with("user://") or output.begins_with("res://_work/")) : invalid = true
	if output.contains("..") or (seen.has("--output") and output.is_empty()) or (seen.has("--check") and baseline.is_empty()): invalid = true
	var expected: Variant
	if not baseline.is_empty():
		if not FileAccess.file_exists(baseline): invalid = true
		else:
			expected = JSON.parse_string(FileAccess.get_file_as_string(baseline))
			if not expected is Dictionary: invalid = true
	if invalid:
		print("FAIL rhythm arguments: --seconds=(0,3600], --seed=[0,2147483647], --output=user:// or res://_work/, --check=<baseline>")
		quit(1)
		return
	var report := {"version":1,"setup":{"seed":seed_,"seconds":seconds,"staff_target":2,"scenario":"all_unlocked"},"shops":{}}
	var failures: Array[String] = []
	for id in SHOPS:
		var row := sample(load("res://content/shops/%s/shop.tres"%id),seconds,seed_)
		report.shops[id] = row
		if row.staff!=2 or row.illegal_footprints>0 or row.overspeed_samples>0 or not row.restore_error.is_empty(): failures.append("physical or restore gate: "+id)
		if seconds>=120 and row.sale_events<1: failures.append("no actual sales: "+id)
		print("RHYTHM %s sold=%d revenue=%d lost=%d staff=%d"%[id,row.sold,int(row.revenue),row.lost,row.staff])
	if not baseline.is_empty(): failures.append_array(compare(report,expected))
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null: failures.append("cannot write report")
		else:
			file.store_string(JSON.stringify(report,"  ")+"\n")
			file.close()
	for error in failures: print("FAIL ",error)
	print("SHOP RHYTHM: %d failures"%failures.size())
	quit(1 if not failures.is_empty() else 0)
