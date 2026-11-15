extends RefCounted
## Shared upgrade folding; queries never replay one-shot effects.

const SET_KINDS := ["batch", "process_slots", "capacity", "flyer_customers", "flyer_cooldown"]
const ADD_KINDS := ["carry", "staff_slot", "seats"]


static func refresh_track(mods: RuleModifiers, st: SpecStation, t: SpecUpgradeTrack, key: String, level: int, default_target: String) -> void:
	## 重算后放回原来的位置：升级条目不挪到栈尾，奇遇等后加的 set 照样盖过升级
	var at: int = mods.entries.size()
	for index in mods.entries.size():
		if mods.entries[index].source == "upgrade" and mods.entries[index].source_id == key:
			at = index
			break
	mods.remove("upgrade", key)
	var kept: int = mods.entries.size()
	var groups := {}
	var effects: Array[SpecEffect] = []
	effects.append_array(t.base_effects)
	for index in mini(level - 1, t.levels.size()): effects.append_array(t.levels[index].effects)
	for e in effects:
		if e.one_shot() or e.kind == "open_flavor": continue
		var dishes: Array = e.dishes
		if dishes.is_empty() and e.kind == "price" and st != null: dishes = st.price_dishes
		var target: String = e.target if not e.target.is_empty() else ("" if e.kind == "price" else default_target)
		var group_key := "%s|%s|%s|%s" % [e.kind, target, ",".join(dishes), e.price_part]
		if not groups.has(group_key):
			groups[group_key] = {"kind": e.kind, "target": target, "dishes": dishes, "part": e.price_part,
				"value": 0.0 if e.kind in SET_KINDS or e.kind in ADD_KINDS else 1.0, "set": false}
		var g: Dictionary = groups[group_key]
		match e.op:
			"set":
				g.value = e.value
				g.set = true
			"add": g.value += e.value
			_: g.value *= e.value
	for g in groups.values():
		var op := "mul"
		if g.kind in SET_KINDS: op = "set"
		elif g.kind in ADD_KINDS: op = "add"
		mods.add("upgrade", key, g.kind, op, g.value, g.target, g.dishes, g.part)
	var added: Array = mods.entries.slice(kept)
	mods.entries = mods.entries.slice(0, at) + added + mods.entries.slice(at, kept)


static func track_of(shop: SpecShop, key: String) -> SpecUpgradeTrack:
	if key == "flyer": return shop.flyer.track
	if key.begins_with("staff/"):
		for t in shop.staff.tracks:
			if "staff/" + t.id == key: return t
		return null
	var parts := key.split("/")
	var st := shop.station(parts[0])
	if st == null: return null
	if parts.size() == 1: return st.track("level") if not st.tracks.is_empty() else null
	var m := st.material(parts[1])
	return m.track if m != null else null


static func refresh_key(shop: SpecShop, levels: Dictionary, mods: RuleModifiers, key: String) -> void:
	var t := track_of(shop, key)
	if key.begins_with("staff/"): refresh_track(mods, null, t, key, int(levels[key]) + 1, key.get_slice("/", 1))
	elif key == "flyer": refresh_track(mods, null, t, key, levels[key], "")
	else:
		var st := shop.station(key.get_slice("/", 0))
		refresh_track(mods, st, t, key, levels[key], st.id)
