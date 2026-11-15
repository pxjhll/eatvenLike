extends "res://tests/test_case.gd"

func test_active_legacy_snapshots_convert_to_one_valid_public_state_without_resetting_progress() -> void:
	for id in ["tea","pancake","stirfry"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+id+".json"))
		for label in fixture.states:
			var old: Dictionary = bytes_to_var(Marshalls.base64_to_raw(fixture.states[label]))
			var shop: SpecShop = load("res://content/shops/"+id+"/shop.tres").copy_for_editing()
			shop.runtime_template = load("res://content/shops/"+id+"/shared_production.tres")
			var owner := ShopRules.new(shop,42)
			var error := owner.load_dict(old,true)
			check_eq(error,"",id+" "+label+" legacy conversion")
			if not error.is_empty(): continue
			var saved := owner.to_dict()
			check_eq(saved.get("version"),2,"old format is actually replaced")
			for key in ["gold","revenue","sold","sold_by_dish","levels","boxes","unlocked","seats","stage_index","completed_at"]:
				check_eq(saved.outer[key],old[key],id+": preserve "+key)
			check_eq(owner.rng.state,old.rng[1],"conversion draws no random choices")
			check_eq(owner.clock,old.clock,"do not restart the simulation clock")
			check_eq(owner.runtime.runner.inventory.audit(),[],"converted physical inventory conserves every item")
			for machine in old.stations:
				var before: Dictionary = old.stations[machine]
				if int(before.processing)<1: continue
				var runs: Array = owner.runtime.runner.machines.snapshot().runs.filter(func(run: Dictionary) -> bool: return run.machine==machine and run.phase not in ["completed","cancelled"])
				check(not runs.is_empty(),id+" "+label+": preserve active machine "+machine)
				if not runs.is_empty(): check_eq(runs[0].remaining,maxf(0.0,float(before.remaining)),"preserve exact remaining automatic work")
			if id=="stirfry":
				var quantities := {}
				for good in old.serve.goods: quantities[good.item] = int(quantities.get(good.item,0))+1
				var actual := {}
				for lot in saved.runtime.runner.inventory.lots: actual[lot.item] = int(actual.get(lot.item,0))+int(lot.count)
				check_eq(actual,quantities,"conversion does not seed extra food or lose any old goods")
			for worker in old.roster:
				check_eq(owner.worker_by_id(worker.id).pos,worker.pos,"do not teleport employees during conversion")
			check_eq(owner.load_dict(saved),"","converted state passes ordinary strict reload")
			owner.run(5.0)
			check_eq(owner.runtime_error,"","converted work actually continues")

func test_each_legacy_format_completes_existing_orders_after_disk_ready_conversion() -> void:
	for id in ["tea","pancake","stirfry"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+id+".json"))
		var old: Dictionary = bytes_to_var(Marshalls.base64_to_raw(fixture.states["899"]))
		var shop: SpecShop = load("res://content/shops/"+id+"/shop.tres")
		var owner := ShopRules.new(shop,42)
		check_eq(owner.load_dict(old,true),"","convert active "+id+" orders")
		owner.runtime.service.arrivals._state.left = 10000.0
		owner.runtime.service.flyers._state.pending = 0
		owner.runtime.service.flyers._state.elapsed = 0.0
		owner.runtime.service.flyers._state.first = false
		var unfinished := []
		for guest in owner.runtime.service.orders.snapshot().guests:
			if guest.state not in ["leaving","gone"]: unfinished.append(int(guest.id))
		for tick in 6000:
			owner.step(0.1)
			if not owner.runtime_error.is_empty(): break
			if unfinished.all(func(guest: int) -> bool: return owner.runtime.service.orders.guest(guest).state=="gone"): break
		check_eq(owner.runtime_error,"",id+": no runtime error during continuation")
		if not unfinished.all(func(guest: int) -> bool: return owner.runtime.service.orders.guest(guest).state=="gone") and OS.has_environment("U06_DEBUG"):
			var trace := FileAccess.open(OS.get_environment("U06_DEBUG")+"/u06-stuck-"+id+".txt",FileAccess.WRITE)
			trace.store_string(var_to_str({"runtime":owner.runtime.snapshot(),"workers":owner.workers}))
		for guest in unfinished:
			check_eq(owner.runtime.service.orders.guest(guest).state,"gone",id+": original customer "+str(guest)+" completes its real lifecycle")
		check_eq(owner.load_dict(owner.to_dict()),"","long legacy continuation remains strictly resumable")
func test_old_action_phase_corpus_restores_every_real_pickup_transport_work_and_delivery_phase() -> void:
	for id in ["tea","pancake","stirfry"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+id+"_phases.json"))
		for label in fixture.states:
			var entry: Dictionary = fixture.states[label]
			var old: Dictionary = bytes_to_var(Marshalls.base64_to_raw(entry.data))
			var owner := ShopRules.new(load("res://content/shops/"+id+"/shop.tres"),42)
			var error := owner.load_dict(old,true)
			check_eq(error,"",id+" "+str(entry.phases)+": phase conversion")
			if not error.is_empty(): continue
			if id=="stirfry":
				for good in old.serve.goods:
					check(owner.runtime.runner.inventory.snapshot().lots.any(func(lot: Dictionary) -> bool: return lot.id==good.id and lot.item==good.item),"preserve stable physical good identity "+str(good.id))
			check_eq(owner.gold,old.gold,"migration preserves already committed payment")
			check_eq(owner.rng.state,old.rng[1],"migration does not resample")
			check_eq(owner.load_dict(owner.to_dict()),"","phase is immediately resumable")
			owner.run(0.5)
			check_eq(owner.runtime_error,"","actual converted phase advances")

func test_legacy_inflight_belts_and_customer_pickup_preserve_physical_goods_and_clocks() -> void:
	for id in ["tea","stirfry"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+id+"_edges.json"))
		for entry in fixture.states.values():
			var old: Dictionary = bytes_to_var(Marshalls.base64_to_raw(entry.data))
			var owner := ShopRules.new(load("res://content/shops/"+id+"/shop.tres"),42)
			var error := owner.load_dict(old,true)
			check_eq(error,"",id+" "+str(entry.phases)+": edge conversion")
			if not error.is_empty(): continue
			if id=="tea":
				var flights: Array = owner.runtime._transports.snapshot().flights
				check_eq(flights.size(),old.belt_items.size(),"preserve all in-flight physical shipments")
				if not flights.is_empty(): check_eq(flights[0].left,old.belt_items[0].duration*(1.0-old.belt_items[0].progress),"exact in-flight remaining duration")
			check_eq(owner.load_dict(owner.to_dict()),"","edge strictly resumes")
			owner.run(5.0)
			check_eq(owner.runtime_error,"","edge continues")
func test_pre_motion_old_saves_adopt_without_replaying_business_and_invalid_old_state_is_atomic() -> void:
	for id in ["tea","pancake","stirfry"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+id+".json"))
		var old: Dictionary = bytes_to_var(Marshalls.base64_to_raw(fixture.states["599"]))
		old.erase("movement")
		for worker in old.roster:
			worker.erase("motion"); worker.erase("action")
		var owner := ShopRules.new(load("res://content/shops/"+id+"/shop.tres"),42)
		check_eq(owner.load_dict(old,true),"","older pre-motion state adopts "+id)
		check_eq(owner.rng.state,old.rng[1],"movement adoption does not reroll business")
		var before := owner.to_dict()
		old.gold = -1.0
		check(not owner.load_dict(old,true).is_empty(),"invalid historical state rejected")
		check_eq(owner.to_dict(),before,"invalid migration leaves the complete live session unchanged")
func test_partially_finished_legacy_manual_stages_keep_their_real_remaining_work() -> void:
	var reference: Script = load("res://tests/fixtures/legacy_shops/reference_rules.gd")
	for id in ["tea","pancake","stirfry"]:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/runtime_legacy/"+id+"_phases.json"))
		for entry in fixture.states.values():
			if not entry.phases.any(func(phase: String) -> bool: return phase.ends_with("/work")): continue
			var old: Dictionary = bytes_to_var(Marshalls.base64_to_raw(entry.data))
			var previous: ShopRules = reference.new(load("res://tests/fixtures/legacy_shops/current/"+id+"/shop.tres"),42)
			check_eq(previous.load_dict(old),"","read historical phase")
			previous.step(0.1)
			old = previous.to_dict()
			var owner := ShopRules.new(load("res://content/shops/"+id+"/shop.tres"),42)
			check_eq(owner.load_dict(old,true),"","convert partially completed "+id+" "+str(entry.phases))
			for worker in old.roster:
				if worker.phase!="work": continue
				var task: Dictionary = owner.runtime.runner.tasks.get(worker.id,{})
				if task.get("kind")!="operate": continue
				var run: Dictionary = owner.runtime.runner.machines.run(task.run)
				var seconds: float = worker.timer if id=="pancake" else worker.action_left
				check(is_equal_approx(run.stage_left/owner.skill(owner.worker_by_id(worker.id)),maxf(0.0,seconds)),id+": retain exact unfinished manual time "+str(entry.phases))
