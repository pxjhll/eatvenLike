extends "res://tests/test_case.gd"
const TEA = preload("res://content/shops/tea/shop.tres")
const PANCAKE = preload("res://content/shops/pancake/shop.tres")

func test_numeric_refresh() -> void:
	for original in [TEA, PANCAKE]:
		var old := ShopRules.new(original)
		old.unlock(old.next_unlock())
		old.run(12.0)
		var saved := old.to_dict()
		var updated: SpecShop = original.duplicate(true)
		updated.staff.kinds[0].stats["speed"] = 19.0
		updated.stations[0].params["capacity"] = 81
		var resumed := ShopRules.new(updated)
		var result: Variant = resumed.callv("load_dict", [saved, true])
		check_eq(result, "", "numeric refresh accepted")
		check_eq(resumed.roster[0].stats, updated.staff.kinds[0].stats, "current worker stats")
		check_eq(resumed.stations[updated.stations[0].id].capacity, 81, "current capacity")


const CONTRACT = preload("res://game/rules/shop_content_contract.gd")
func test_fingerprints() -> void:
	var base := CONTRACT.describe(TEA)
	check_eq(base.gameplay.length(), 64, "sha256")
	var copy: SpecShop = TEA.duplicate(true)
	check_eq(CONTRACT.describe(copy), base, "deep copy stable")
	copy.display_name = "Presentation"
	copy.scene_path = "res://another.tscn"
	copy.stations[0].params["load_label"] = "Presentation"
	check_eq(CONTRACT.describe(copy), base, "presentation ignored")
	copy.staff.kinds[0].stats["new_stat"] = 7.0
	copy.stations[0].params["capacity"] = 81
	var changed := CONTRACT.describe(copy)
	check(changed.gameplay != base.gameplay, "numeric gameplay changes")
	check_eq(changed.structure, base.structure, "numeric topology stable")
	copy.layout.points[copy.layout.points.keys()[0]] += Vector2(1, 0)
	check(CONTRACT.describe(copy).structure != base.structure, "geometry structural")
	copy = TEA.duplicate(true)
	copy.stations[0].block = "different"
	check(CONTRACT.describe(copy).structure != base.structure, "block structural")
	copy = TEA.duplicate(true)
	copy.stages.reverse()
	check(CONTRACT.describe(copy).structure != base.structure, "stage order structural")

func test_refresh_preserves_progress_effects_and_aliases() -> void:
	for original in [TEA, PANCAKE]:
		var old := ShopRules.new(original)
		old.unlock(old.next_unlock())
		old.run(25.0)
		# Capture during recorded manual work rather than relying on a fixed frame.
		var active := false
		for unused in 2000:
			for worker in old.workers:
				if float(worker.action_left) > 0.0 or float(worker.timer) > 0.0: active = true
			if active: break
			old.step(0.1)
		check(active, "active recorded work captured")
		old.mods.add("event", "finite", "batch", "set", 91, old.pots[0], [], "", 12.0)
		old.mods.add("event", "permanent", "batch", "set", 93.0, old.pots[0])
		old.mods.add("event", "last_finite", "batch", "set", 97.0, old.pots[0], [], "", 2.0)
		var saved := old.to_dict()
		var updated: SpecShop = original.duplicate(true)
		updated.staff.kinds[0].stats["work"] = 19.0
		for station in updated.stations:
			for track in station.tracks:
				for effect in track.base_effects: effect.value += 2.0
		var resumed := ShopRules.new(updated)
		var bus := resumed.events
		check_eq(resumed.load_dict(saved, true), "", "refresh succeeds")
		check(resumed.events == bus, "bus retained")
		var result := resumed.to_dict()
		for key in saved:
			if key in ["mods", "roster"]: continue
			check_eq(result[key], saved[key], "recorded progress: " + key)
		for i in saved.roster.size():
			var worker: Dictionary = result.roster[i].duplicate(true)
			worker.stats = saved.roster[i].stats
			check_eq(worker, saved.roster[i], "worker job/timers retained")
		check_eq(resumed.pot_batch(resumed.pots[0]), 97, "finite set wins")
		var retained := resumed.mods.entries.duplicate(true)
		resumed.mods.tick(2.1)
		check_eq(resumed.pot_batch(resumed.pots[0]), 93, "permanent set wins after finite expiration")
		resumed.mods.entries = retained
		resumed.workers[0].fatigue = 0.23
		check_eq(resumed.roster[0].fatigue, 0.23, "worker shares roster dictionary")
		var once := resumed.to_dict()
		check_eq(resumed.load_dict(once, true), "", "repeat succeeds")
		check_eq(resumed.to_dict(), once, "repeat idempotent")

func test_new_removed_sources_and_one_shot() -> void:
	var before: SpecShop = TEA.duplicate(true)
	var station: SpecStation
	for entry in before.stations:
		if not entry.tracks.is_empty():
			station = entry
			break
	station.tracks[0].base_effects.clear()
	var old := ShopRules.new(before)
	old.mods.add("event", "finite", "batch", "set", 71, station.id, [], "", 9.0)
	var saved := old.to_dict()
	var after: SpecShop = before.duplicate(true)
	var target := after.station(station.id)
	var batch := SpecEffect.new()
	batch.kind = "batch"
	batch.op = "set"
	batch.value = 42
	target.tracks[0].base_effects.append(batch)
	var reward := SpecEffect.new()
	reward.kind = "grant_gold"
	reward.value = 999999
	target.tracks[0].base_effects.append(reward)
	var resumed := ShopRules.new(after)
	check_eq(resumed.load_dict(saved, true), "", "new source refresh")
	check_eq(resumed.mods.value("batch", 1, station.id), 71, "new upgrade precedes finite event")
	check_eq(resumed.gold, saved.gold, "one-shot never replayed")
	var restored := resumed.to_dict()
	var event_entries: Array = restored.mods.filter(func(e: Dictionary) -> bool: return e.source != "upgrade")
	check_eq(event_entries, saved.mods.filter(func(e: Dictionary) -> bool: return e.source != "upgrade"), "event duration preserved")
	target.tracks[0].base_effects.clear()
	var removed := ShopRules.new(after)
	check_eq(removed.load_dict(restored, true), "", "removed source refresh")
	check_eq(removed.mods.entries.filter(func(e: Dictionary) -> bool: return e.source == "upgrade" and e.source_id == station.id).size(), 0, "removed upgrade gone")

func test_contract_identity_and_canonical_dictionary() -> void:
	var before: SpecShop = TEA.duplicate(true)
	var base := CONTRACT.describe(before)
	var after: SpecShop = before.duplicate(true)
	var keys: Array = after.layout.points.keys()
	keys.reverse()
	after.layout.points.clear()
	for key in keys: after.layout.points[key] = before.layout.points[key]
	check_eq(CONTRACT.describe(after), base, "dictionary insertion ignored")
	after.start_gold += 1
	check_eq(CONTRACT.describe(after).structure, base.structure, "prices rebalance")
	after = before.duplicate(true)
	after.dispatch.travel_penalty += 0.000000000001
	check(CONTRACT.describe(after).gameplay != base.gameplay, "nearby double differs")
	after = before.duplicate(true)
	after.fulfillment.handoff = "single"
	check(CONTRACT.describe(after).structure != base.structure, "mode structural")
	after = before.duplicate(true)
	after.dishes[0].steps[0].produces["label"] = 1
	check(CONTRACT.describe(after).structure != base.structure, "storage identity named label retained")
	after = before.duplicate(true)
	after.dishes[0].steps[0].repeat += 1
	check(CONTRACT.describe(after).structure != base.structure, "recipe repeat structural")
	for entry in after.stations:
		if entry.materials.is_empty(): continue
		after = before.duplicate(true)
		after.station(entry.id).materials[0].item += "_different"
		check(CONTRACT.describe(after).structure != base.structure, "material identity structural")
		break
	after = before.duplicate(true)
	for entry in after.stations:
		if entry.tracks.is_empty(): continue
		entry.tracks[0].levels.append(SpecUpgradeLevel.new())
		check(CONTRACT.describe(after).structure != base.structure, "track max structural")
		break

func test_active_automatic_duration_survives_refresh() -> void:
	var fixture = preload("res://tests/test_tea_rules.gd").new()
	var old: ShopRules = fixture._opened()
	var active_id := ""
	for unused in 20000:
		old.step(0.1)
		for id in old.stations:
			if old.stations[id].processing > 0 and old.stations[id].duration > 0.0 and old.stations[id].remaining > 0.0:
				active_id = id
				break
		if not active_id.is_empty(): break
	check(not active_id.is_empty(), "real automatic processing captured")
	if active_id.is_empty(): return
	var saved := old.to_dict()
	var updated: SpecShop = TEA.duplicate(true)
	updated.station(active_id).params["process_seconds"] = 987.0
	var resumed := ShopRules.new(updated)
	check_eq(resumed.load_dict(saved, true), "", "active automatic refresh")
	check_eq(resumed.stations[active_id], saved.stations[active_id], "recorded automatic timing and stock exact")
	resumed.step(0.1)
	check(resumed.stations[active_id].remaining <= saved.stations[active_id].remaining, "recorded automatic work advances")

func test_connection_stage_binding_is_structural() -> void:
	var before: SpecShop = TEA.duplicate(true)
	check(not before.connections.is_empty(), "connection fixture populated")
	if before.connections.is_empty(): return
	var after: SpecShop = before.duplicate(true)
	after.connections[0].stage += 1
	var old := CONTRACT.describe(before)
	var changed := CONTRACT.describe(after)
	check(changed.gameplay != old.gameplay, "connection stage affects gameplay")
	check(changed.structure != old.structure, "connection stage is progression structure")

func test_staff_role_and_station_unit_are_presentation() -> void:
	var before: SpecShop = TEA.duplicate(true)
	var base := CONTRACT.describe(before)
	var after: SpecShop = before.duplicate(true)
	after.staff.kinds[0].role = "New role caption"
	check_eq(CONTRACT.describe(after), base, "staff role caption ignored")
	after = before.duplicate(true)
	after.stations[0].params["unit"] = "New quantity caption"
	check_eq(CONTRACT.describe(after), base, "station quantity caption ignored")

func test_numeric_topology_boundary_predicates() -> void:
	var before: SpecShop = TEA.duplicate(true)
	var material_station: SpecStation
	for station in before.stations:
		if not station.materials.is_empty():
			material_station = station
			break
	check(material_station != null, "material fixture")
	if material_station == null: return
	material_station.materials[0].box_cost = 1
	var base := CONTRACT.describe(before)
	var after: SpecShop = before.duplicate(true)
	after.station(material_station.id).materials[0].box_cost = 2
	check_eq(CONTRACT.describe(after).structure, base.structure, "box price magnitude rebalanceable")
	after.station(material_station.id).materials[0].box_cost = 0
	check(CONTRACT.describe(after).structure != base.structure, "box existence structural")
	before = TEA.duplicate(true)
	var pickup: SpecStation
	for station in before.stations:
		if station.block == "pickup": pickup = station
	check(pickup != null, "pickup fixture")
	if pickup == null: return
	pickup.params.erase("process_seconds")
	base = CONTRACT.describe(before)
	after = before.duplicate(true)
	after.station(pickup.id).params["process_seconds"] = 1.0
	check(CONTRACT.describe(after).structure != base.structure, "pickup process role presence structural")
	base = CONTRACT.describe(after)
	after.station(pickup.id).params["process_seconds"] = 2.0
	check_eq(CONTRACT.describe(after).structure, base.structure, "pickup duration magnitude rebalanceable")
	before = PANCAKE.duplicate(true)
	var hand: SpecStation
	for station in before.stations:
		if station.block == "hand": hand = station
	check(hand != null, "hand fixture")
	if hand == null: return
	hand.params["users"] = 1
	base = CONTRACT.describe(before)
	after = before.duplicate(true)
	after.station(hand.id).params["users"] = 2
	check_eq(CONTRACT.describe(after).structure, base.structure, "positive hand users magnitude rebalanceable")
	after.station(hand.id).params["users"] = 0
	check(CONTRACT.describe(after).structure != base.structure, "hand locking predicate structural")
