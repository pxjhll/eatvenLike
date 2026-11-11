extends SceneTree
## Empty-shop acceptance: normal money, arrivals, purchases and deployment.
## Independent of the fully-open/two-worker diagnostic in shop_rhythm.gd.
const Replay := preload("res://tests/baselines/replay_rules.gd")
const Content := preload("res://game/rules/shop_content_contract.gd")
const SHOPS := ["tea","pancake","stirfry"]
const TARGETS := {"tea":2133.1,"pancake":1365.1,"stirfry":2760.0}
const AUDIT_SEEDS := {"stirfry":[42,84]}
const TOLERANCE := 0.05
const LIMIT := 5400.0

static func _role(rules: ShopRules, worker: Dictionary) -> String:
	if rules.shop.staff.zones.is_empty(): return "all"
	return "front" if worker.post==rules.counter_id else "kitchen"

static func _busy(rules: ShopRules, worker: Dictionary) -> bool:
	return worker.walking or worker.phase in ["work","pickup","dropoff","wait"] or not worker.job.is_empty() or not rules.serve.jobs.get(str(worker.id),{}).is_empty()

static func _staff_post(rules: ShopRules, loads: Dictionary) -> Dictionary:
	var load_ := 0.0
	for role in loads:
		load_ = maxf(load_,float(loads[role]))
	if load_<=0.7: return {}
	if rules.shop.staff.zones.is_empty():
		return {"post":""} if rules.workers.size()<rules.staff_slots() else {}
	# Same deployment priority as the original tea bot: fill kitchen capacity
	# first, then a free front slot. This also staffs a newly unlocked kitchen
	# that has no employee yet and therefore no measured busy samples.
	if rules.role_room("").is_empty(): return {"post":""}
	return {"post":rules.counter_id} if rules.role_room(rules.counter_id).is_empty() else {}

static func _buy(rules: ShopRules, command: String, actions: Array) -> bool:
	if not Replay.run_command(rules,command).is_empty(): return false
	actions.append([snappedf(rules.clock,0.1),command])
	return true

## One visit each minute, up to six purchases. An idle role cannot hide another
## role's load; hires use actual money and must be deployed into available slots.
static func visit(rules: ShopRules, loads: Dictionary, hand_load: float, actions: Array) -> void:
	var shop := rules.shop
	var hand := ""
	for station in shop.stations:
		if station.block=="hand" and int(station.params.get("users",0))>0: hand = station.id
	if rules.queue_size()<=1: _buy(rules,"flyer",actions)
	for unused in 6:
		var box := rules.pending_box()
		if not box.is_empty() and _buy(rules,"box "+box,actions): continue
		var next := rules.next_unlock()
		if not next.is_empty() and _buy(rules,"unlock "+next,actions): continue
		var room := _staff_post(rules,loads)
		if rules.workers.size()<rules.staff_slots() and not room.is_empty():
			var waiting: Array = rules.roster.filter(func(worker: Dictionary) -> bool: return not worker.deployed)
			if not waiting.is_empty() or _buy(rules,"hire",actions):
				var worker: Dictionary = waiting[0] if not waiting.is_empty() else rules.roster[-1]
				if not worker.deployed:
					var post: String = room.post
					if rules.deploy_worker(worker.id,post).is_empty():
						actions.append([snappedf(rules.clock,0.1),"deploy %d"%worker.id+(" "+post if not post.is_empty() else "")])
				continue
		var options: Array = []
		for station in shop.stations:
			if not station.tracks.is_empty() and rules.station_unlocked(station.id) and rules.upgrade_error(station.id).is_empty(): options.append([rules.upgrade_cost(station.id),"upgrade "+station.id])
			for material in station.materials:
				var key := station.id+"/"+material.id
				if material.track!=null and not material.track.levels.is_empty() and rules.upgrade_error(key).is_empty(): options.append([rules.upgrade_cost(key),"material %s %s"%[station.id,material.id]])
		for track in shop.staff.tracks:
			if rules.upgrade_error("staff/"+track.id).is_empty(): options.append([rules.upgrade_cost("staff/"+track.id),"staff "+track.id])
		if rules.upgrade_error("flyer").is_empty(): options.append([rules.upgrade_cost("flyer"),"flyer_upgrade"])
		if rules.buy_group()!=null and rules.seat_error().is_empty(): options.append([rules.seat_cost(),"seat"])
		if options.is_empty(): break
		options.sort()
		var pick: Array = options[0]
		var preferred := options.filter(func(option: Array) -> bool: return option[1]=="upgrade "+hand)
		var prefer := hand_load>0.7 and not preferred.is_empty()
		if prefer: pick = preferred[0]
		if not next.is_empty() and pick[0]>0.25*rules.next_stage_cost() and not prefer: break
		if not _buy(rules,pick[1],actions): break

static func sample(shop: SpecShop, seconds := LIMIT, seed_ := -1) -> Dictionary:
	var rules := ShopRules.new(shop,shop.random_seed if seed_<0 else seed_)
	var actions: Array = []
	var sales: Array = []
	var stages: Array = []
	var role_ticks := {}
	var role_busy := {}
	var totals := {}
	var hand := ""
	for station in shop.stations:
		if station.block=="hand" and int(station.params.get("users",0))>0: hand = station.id
	var hand_busy := 0
	var samples := 0
	var next_visit := 1.0
	var last_stage := -2
	var listener := func(_event: Dictionary) -> void: sales.append(roundi(rules.clock*10.0))
	rules.events.on("sale",listener)
	while rules.clock<seconds-0.0001 and rules.completed_at<0.0:
		rules.step(0.1)
		if rules.stage_index!=last_stage:
			last_stage = rules.stage_index
			stages.append({"at":snappedf(rules.clock,0.1),"stage":last_stage,"gold":snappedf(rules.gold,0.01),"sold":rules.sold})
		samples += 1
		if not hand.is_empty() and int(rules.stations[hand].get("user",-1))!=-1: hand_busy += 1
		for worker: Dictionary in rules.workers:
			var role := _role(rules,worker)
			role_ticks[role] = int(role_ticks.get(role,0))+1
			if not totals.has(role): totals[role] = {"busy":0,"idle":0}
			if _busy(rules,worker):
				role_busy[role] = int(role_busy.get(role,0))+1
				totals[role].busy += 1
			else: totals[role].idle += 1
		if rules.clock+0.0001<next_visit or rules.completed_at>=0.0: continue
		next_visit += 60.0
		var loads := {}
		for role in role_ticks: loads[role] = float(role_busy.get(role,0))/role_ticks[role]
		visit(rules,loads,float(hand_busy)/maxi(1,samples),actions)
		role_ticks.clear()
		role_busy.clear()
		hand_busy = 0
		samples = 0
	rules.events.off("sale",listener)
	var longest_gap := 0
	for index in range(1,sales.size()): longest_gap = maxi(longest_gap,sales[index]-sales[index-1])
	return {"content":Content.describe(shop),"seed":shop.random_seed if seed_<0 else seed_,
		"completed_at":snappedf(rules.completed_at,0.1),"clock":snappedf(rules.clock,0.1),
		"first_sale_tick":sales[0] if not sales.is_empty() else -1,"maximum_sale_gap_ticks":longest_gap,
		"revenue":rules.revenue,"sold":rules.sold,"lost":rules.lost,"staff":rules.workers.size(),
		"role_ticks":totals,"stages":stages,"actions":actions,
		"restore_error":ShopRules.new(shop).load_dict(rules.to_dict())}

static func target_errors(shops: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for id in shops:
		if not TARGETS.has(id): errors.append("unknown target: "+str(id)); continue
		var at := float(shops[id].get("completed_at",-1))
		if at<=0.0 or absf(at/TARGETS[id]-1.0)>TOLERANCE: errors.append("completion target failed: %s %.1fs vs %.1fs +/-5%%"%[id,at,TARGETS[id]])
	return errors

static func completion_errors(report: Dictionary) -> Array[String]:
	if not report.get("shops") is Dictionary: return ["completion shop reports missing"]
	var errors := target_errors(report.shops)
	var audits: Variant = report.get("audits",{})
	if not audits is Dictionary: return ["secondary seed reports missing"]
	for id in report.shops:
		for seed_ in AUDIT_SEEDS.get(id,[]):
			var rows: Variant = audits.get(id,{})
			var row: Variant = rows.get(str(seed_),{}) if rows is Dictionary else {}
			if not row is Dictionary or row.get("seed")!=seed_:
				errors.append("missing or mislabeled secondary seed: %s %d"%[id,seed_])
				continue
			for error in target_errors({id:row}): errors.append("seed %d: %s"%[seed_,error])
			if not String(row.get("restore_error","")).is_empty(): errors.append("invalid secondary seed state: %s %d"%[id,seed_])
	return errors

func _initialize() -> void:
	var output := ""
	var baseline := ""
	var ids: Array = SHOPS
	var invalid := false
	var seen := {}
	for arg in OS.get_cmdline_user_args():
		var key := arg.get_slice("=",0)
		var value := arg.substr(key.length()+1)
		if seen.has(key) or not arg.contains("=") or value.is_empty(): invalid = true; continue
		seen[key] = true
		match key:
			"--output": output = value
			"--check": baseline = value
			"--shop":
				if value not in SHOPS: invalid = true
				else: ids = [value]
			_: invalid = true
	if not output.is_empty() and (not output.begins_with("res://_work/") or output.contains("..")): invalid = true
	var expected: Variant
	if not baseline.is_empty():
		expected = JSON.parse_string(FileAccess.get_file_as_string(baseline)) if FileAccess.file_exists(baseline) else null
		if not expected is Dictionary or not expected.get("shops") is Dictionary or not expected.get("setup") is Dictionary or not expected.get("audits") is Dictionary: invalid = true
	if invalid:
		print("FAIL progression arguments: --shop=tea|pancake|stirfry --output=res://_work/... --check=<report>")
		quit(1)
		return
	var report := {"version":2,"setup":{"scenario":"empty_shop","bot":"minute_visit_role_load_v1","limit_seconds":LIMIT,"target_tolerance":TOLERANCE,"audit_seeds":AUDIT_SEEDS},"shops":{},"audits":{}}
	var failures: Array[String] = []
	for id in ids:
		var row := sample(load("res://content/shops/%s/shop.tres"%id))
		report.shops[id] = row
		if not row.restore_error.is_empty(): failures.append("invalid final state: "+id)
		print("PROGRESSION %s completed=%.1fs first_sale=%.1fs sold=%d revenue=%d staff=%d"%[id,row.completed_at,row.first_sale_tick/10.0,row.sold,int(row.revenue),row.staff])
		if AUDIT_SEEDS.has(id): report.audits[id] = {}
		for seed_ in AUDIT_SEEDS.get(id,[]):
			var audit := sample(load("res://content/shops/%s/shop.tres"%id),LIMIT,seed_)
			report.audits[id][str(seed_)] = audit
			print("PROGRESSION AUDIT %s seed=%d completed=%.1fs first_sale=%.1fs sold=%d"%[id,seed_,audit.completed_at,audit.first_sale_tick/10.0,audit.sold])
	failures.append_array(completion_errors(report))
	if expected is Dictionary:
		if expected.get("version")!=report.version or expected.get("setup")!=JSON.parse_string(JSON.stringify(report.setup)): failures.append("progression setup differs")
		if ids.size()==SHOPS.size() and expected.get("shops",{}).size()!=SHOPS.size(): failures.append("progression shop set differs")
		for id in ids:
			if expected.get("shops",{}).get(id)!=JSON.parse_string(JSON.stringify(report.shops[id])): failures.append("progression metrics or content differ: "+id)
			if expected.audits.get(id)!=JSON.parse_string(JSON.stringify(report.audits.get(id))): failures.append("secondary seed metrics or content differ: "+id)
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var file := FileAccess.open(output,FileAccess.WRITE)
		if file==null: failures.append("cannot write progression report")
		else:
			file.store_string(JSON.stringify(report,"  ")+"\n")
			file.close()
	for error in failures: print("FAIL ",error)
	print("SHOP PROGRESSION: %d failures"%failures.size())
	quit(1 if not failures.is_empty() else 0)
