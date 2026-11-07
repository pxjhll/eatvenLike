extends "res://tests/test_case.gd"
## 界面快照 ShopView（规格 §6.2.1）：奶茶店整局对旧模拟录下的界面数据（tests/baselines/tea_ui_73b0ae3.json），
## 界面读到的目标、瓶颈提示、机器面板数字（解锁、等级、升级价、售价预览、原料箱）都一样。

const Replay := preload("res://tests/baselines/replay_rules.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")


## 和录基准时同一种记法
static func signature(view: ShopView) -> Dictionary:
	var out := {}
	var g := view.goal()
	out.goal = [g.text, int(g.current), int(g.target), g.long]
	var hint := view.bottleneck()
	out.hint = [hint.get("text", ""), hint.get("fix", ""), hint.get("target", "")]
	for st in view.rules.shop.stations:
		var card := view.station(st.id)
		var row: Array = [card.unlocked, card.level]
		if card.unlocked:
			row.append(int(card.track.cost) if card.has("track") else -1)
			if view.price_preview(st.id).size() > 0:
				var p := view.price_preview(st.id)
				row.append_array([snappedf(p.now, 0.01), snappedf(p.next, 0.01)])
			for m in card.get("materials", []):
				row.append([m.id, int(m.level), int(m.cost), String(m.state).begins_with("box")])
		out[st.id] = row
	return out


static func _same(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _same(a[i], b[i]): return false
		return true
	if (a is float or a is int) and (b is float or b is int): return absf(float(a) - float(b)) < 0.011
	return a == b


func test_tea_snapshot_matches_old_ui_data_through_whole_shop() -> void:
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/tea_73b0ae3.json"))
	var recorded: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/tea_ui_73b0ae3.json"))
	var rules := ShopRules.new(TEA)
	var view := ShopView.new(rules)
	var actions: Array = base.actions
	var next_action := 0
	var reported := 0
	var expected := {}
	var rows: Array = recorded.rows
	for row in rows:
		var tick := int(row[0])
		while rules.clock < (tick + 1) * ShopRules.STEP - 0.0001:
			rules.step(ShopRules.STEP)
			while next_action < actions.size() and float(actions[next_action][0]) <= rules.clock + 0.0001:
				Replay.run_command(rules, actions[next_action][1])
				next_action += 1
		expected.merge(row[1], true)
		var mine := signature(view)
		for key in expected:
			if _same(mine.get(key), expected[key]): continue
			if reported < 8: check(false, "t=%.0f %s 旧 %s 新 %s" % [rules.clock, key, expected[key], mine.get(key)])
			reported += 1
	check(rows.size() > 400, "整局查了 %d 次" % rows.size())
	check_eq(reported, 0, "整局界面数据一致")


func test_buffs_list_timed_modifiers() -> void:
	var rules := ShopRules.new(TEA)
	var view := ShopView.new(rules)
	check_eq(view.buffs().size(), 0, "开局没有进行中加成")
	rules.apply_effect("event", "influencer", SpecEffect.make("flow", "mul", 2.0), 60.0)
	var buffs := view.buffs()
	check_eq(buffs.size(), 1, "一个加成图标")
	check(is_equal_approx(float(buffs[0].left), 60.0), "剩 60 秒")
