extends "res://tests/test_case.gd"
## 界面快照 ShopView（规格 §6.2.1）：奶茶店整局逐帧对旧模拟，界面读到的目标、瓶颈提示、机器面板数字都一样。
## 旧模拟删除时（第 5 个 PR）把对比改成存下来的基准。

const TeaSim := preload("res://game/tea_playtest/tea_shop_sim.gd")
const Replay := preload("res://tests/baselines/replay_rules.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")


func _differences(old, view: ShopView) -> Array:
	var out: Array = []
	var g := view.goal()
	var og: Dictionary = old.goal_progress()
	if [g.text, int(g.current), int(g.target), g.long] != [og.text, int(og.current), int(og.target), old.current_goal()]:
		out.append("目标 旧 %s / %s 新 %s / %s" % [og, old.current_goal(), [g.text, g.current, g.target], g.long])
	var hint := view.bottleneck()
	var oh: Dictionary = old._bottleneck()
	if [hint.get("text", ""), hint.get("fix", ""), hint.get("target", "")] != [oh.get("text", ""), oh.get("fix", ""), oh.get("target", "")]:
		out.append("瓶颈 旧 %s 新 %s" % [oh, hint])
	for st in TEA.stations:
		var info: Dictionary = old.station_info(st.id)
		var card := view.station(st.id)
		if [card.unlocked, card.level] != [info.unlocked, info.level]:
			out.append("%s 解锁/等级 旧 %s 新 %s" % [st.id, [info.unlocked, info.level], [card.unlocked, card.level]])
			continue
		if not card.unlocked: continue
		if card.has("track") and int(card.track.cost) != int(info.upgrade_cost):
			out.append("%s 升级价 旧 %d 新 %d" % [st.id, info.upgrade_cost, card.track.cost])
		if not info.price.is_empty():
			var p := view.price_preview(st.id)
			if not (is_equal_approx(p.now, info.price.now) and is_equal_approx(p.next, info.price.next)):
				out.append("%s 售价预览 旧 %s 新 %s" % [st.id, info.price, p])
		for row in info.materials:
			var mine: Array = card.get("materials", []).filter(func(m: Dictionary) -> bool: return m.id == row.id)
			var boxed: bool = row.get("box", false) and not row.box_unlocked
			var want: int = row.box_cost if boxed else row.upgrade_cost
			if mine.is_empty() or int(mine[0].level) != int(row.level) or int(mine[0].cost) != want \
					or String(mine[0].state).begins_with("box") != boxed:
				out.append("%s/%s 物料 旧 %s 新 %s" % [st.id, row.id, [row.level, row.upgrade_cost], mine])
	return out


func test_tea_snapshot_matches_old_ui_data_through_whole_shop() -> void:
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/baselines/tea_73b0ae3.json"))
	var old = TeaSim.new()
	var rules := ShopRules.new(TEA)
	var view := ShopView.new(rules)
	var actions: Array = base.actions
	var next_action := 0
	var reported := 0
	var checked := 0
	for tick in int(base.minutes * 600):
		old.advance(0.1)
		rules.step(0.1)
		while next_action < actions.size() and float(actions[next_action][0]) <= rules.clock + 0.0001:
			var command: String = actions[next_action][1]
			_old(old, command)
			Replay.run_command(rules, command)
			next_action += 1
		if tick % 50 != 0: continue
		checked += 1
		for line in _differences(old, view):
			if reported < 8: check(false, "t=%.0f %s" % [rules.clock, line])
			reported += 1
	check(checked > 400, "整局查了 %d 次" % checked)
	check_eq(reported, 0, "整局界面数据一致")


func _old(sim, command: String) -> void:
	var parts := command.split(" ")
	match parts[0]:
		"unlock": sim.unlock_station(parts[1])
		"box": sim.unlock_box(parts[1])
		"hire": sim.hire()
		"deploy": sim.deploy_worker(int(parts[1]))
		"upgrade": sim.upgrade_station(parts[1])
		"material": sim.upgrade_material(parts[1], parts[2])
		"staff": sim.buy_staff_upgrade(parts[1])
		"seat": sim.buy_seat()
		"flyer_upgrade": sim.upgrade_flyers()
		"flyer": sim.buy_flyers()


func test_buffs_list_timed_modifiers() -> void:
	var rules := ShopRules.new(TEA)
	var view := ShopView.new(rules)
	check_eq(view.buffs().size(), 0, "开局没有进行中加成")
	rules.apply_effect("event", "influencer", SpecEffect.make("flow", "mul", 2.0), 60.0)
	var buffs := view.buffs()
	check_eq(buffs.size(), 1, "一个加成图标")
	check(is_equal_approx(float(buffs[0].left), 60.0), "剩 60 秒")
