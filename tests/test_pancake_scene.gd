extends "res://tests/test_case.gd"
## Catches preview leaks, layout drift, duplicate sprites and incorrect opening/unlock visibility.

const SCENE := "res://presentation/pancake/pancake_art.tscn"

func _art() -> Node2D:
	check(ResourceLoader.exists(SCENE), "approved pancake artwork has a runnable engine scene")
	if not ResourceLoader.exists(SCENE): return null
	var art: Node2D = load(SCENE).instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(art)
	return art

func test_preview_actors_and_actor_shadows_are_excluded() -> void:
	var art := _art()
	if art == null: return
	for id in [29, 30, 38, 39, 44, 45, 58, 59, 60, 61, 78, 79, 80, 81, 82, 150, 151, 85, 87]:
		check(art.source_node(id) == null, "excluded preview/reference node %d" % id)
	for id in [140, 144, 145, 146, 147, 148, 133, 168]:
		var layer: Node2D = art.source_node(id)
		check(layer != null and not layer is Sprite2D, "text/shadow %d is code drawn" % id)
	art.free()

func test_shared_art_and_mirror_preserve_approved_geometry() -> void:
	var art := _art()
	if art == null: return
	for ids in [[14, 16, 41], [18, 20], [50, 51, 52], [53, 54, 55, 57], [66, 69, 73], [71, 72]]:
		for id in ids:
			check(art.source_node(id).texture == art.source_node(ids[0]).texture, "one resource for identical art %d" % id)
	var fryer: Sprite2D = art.source_node(32)
	check(fryer.global_position.distance_to(Vector2(88.5, 411)) < 0.001, "approved fryer anchor")
	check((fryer.texture.get_size() * fryer.scale).distance_to(Vector2(162, 151)) < 0.001, "approved fryer dimensions")
	var pipe: Sprite2D = art.source_node(22)
	check(pipe.global_transform.x.x < 0 and pipe.global_position.distance_to(Vector2(610, 215)) < 0.001, "pipe retains the author's mirror and anchor")
	art.free()

func test_opening_retains_fixed_decor_but_hides_function_groups() -> void:
	var art := _art()
	if art == null: return
	art.show_complete_layout()
	art.reset_layout()
	for id in [162, 62, 75, 83]:
		check(art.source_node(id).is_visible_in_tree(), "opening fixed group %d" % id)
	for id in [21, 26, 31, 34, 40, 46, 161, 166, 163, 164, 165]:
		check(not art.source_node(id).is_visible_in_tree(), "functional group %d requires state" % id)
	check(art.source_node(137).visible, "fixed table shadow is present at opening")
	check(not art.source_node(140).visible, "flour label is hidden with ingredient group")
	check(not art.source_node(143).visible, "counter shadow is hidden with the counter")
	art.free()

func test_function_labels_and_shadows_follow_owners() -> void:
	var art := _art()
	if art == null: return
	art.reset_layout()
	check(art.set_station_unlocked("raw_ingredients", true), "known group can be opened")
	check(art.source_node(26).visible and art.source_node(140).visible, "flour label follows raw ingredients")
	art.set_station_unlocked("raw_ingredients", false)
	check(not art.source_node(140).visible, "flour label vanishes when its owner closes")
	art.set_station_unlocked("front_counter", true)
	check(art.source_node(143).visible and not art.source_node(145).visible, "counter shadow opens independently of rack labels")
	art.set_station_unlocked("rack", true)
	check(art.source_node(145).visible, "rack label opens with rack")
	art.set_station_unlocked("front_counter", false)
	check(not art.source_node(145).visible and not art.source_node(143).visible, "nested labels and shadows obey ancestor state")
	check(not art.set_station_unlocked("not_a_station", true), "unknown keys do not open other groups")
	art.free()

func test_cushions_unlock_in_three_stages_with_matching_shadows() -> void:
	var art := _art()
	if art == null: return
	art.reset_layout()
	for row in [[0, 0], [1, 2], [2, 5], [3, 9], [-1, 0], [99, 9]]:
		art.set_cushion_stage(row[0])
		var cushions := 0
		var shadows := 0
		for id in range(66, 75):
			if art.source_node(id).is_visible_in_tree(): cushions += 1
		for id in range(152, 161):
			if art.source_node(id).visible: shadows += 1
		check_eq(cushions, row[1], "cumulative cushions at stage %d" % row[0])
		check_eq(shadows, row[1], "shadows follow available cushions at stage %d" % row[0])
	art.free()


func _play(store_path := "") -> Node2D:
	var play: Node2D = load("res://presentation/pancake/pancake_play.tscn").instantiate()
	play.store = null if store_path.is_empty() else preload("res://game/pancake/pancake_save.gd").new(store_path)
	play.profile = preload("res://game/app/profile.gd").new("user://test_profile_pancake.json")
	play.profile.reset_all()
	(Engine.get_main_loop() as SceneTree).root.add_child(play)
	return play


func test_play_scene_builds_and_unlocks_art() -> void:
	var play := _play()
	var art: Node2D = play.art
	check(art.source_node(34).visible, "打包台开局可见")
	check(not art.source_node(161).visible, "豆浆机开之前隐藏")
	check(play._frames["soy_milk"].visible, "豆浆机位置显示解锁虚线框")
	play._try_unlock("soy_milk")
	check(art.source_node(161).visible, "开放后显示豆浆机")
	check(not play._frames["soy_milk"].visible and play._frames["rear_equipment"].visible, "虚线框移到下一台")
	play.sim.run(40.0)
	play._sync_actors()
	check(play._staff_actors.size() == 1, "员工画在场景里")
	play.free()


func test_characters_match_tea_shop_scale_and_sort_by_feet() -> void:
	var play := _play()
	var Characters := preload("res://presentation/characters/character_library.gd")
	var cup: Sprite2D = play.art.source_node(play.RULER_CUP)
	var cup_height: float = (play.art.global_transform.affine_inverse() * cup.global_transform * cup.get_rect()).size.y
	check(absf(play._staff_height / cup_height - 128.0 / 52.0) < 0.01, "员工和杯子的比例同奶茶店")
	check(absf(play._customer_height / cup_height - 110.0 / 52.0) < 0.01, "客人和杯子的比例同奶茶店")
	play._try_unlock("soy_milk")
	play.sim.next_customer = 0.0
	play.sim.run(3.0)
	play._sync_actors()
	var counter_z: int = play.art.source_node(46).z_index
	var staff: Node2D = play._staff_actors.values()[0]
	check(staff.z_index < counter_z, "柜台后面的员工画在柜台下面")
	check(play.art.source_node(161).z_index >= counter_z, "豆浆机跟柜台一起挡住员工")
	for c in play._customer_actors.values():
		check(c.z_index > counter_z, "柜台前的客人画在柜台上面")
	check(play._frames["rear_equipment"].z_index > 1678, "解锁框在所有人物上面")
	play.free()


func test_guide_follows_opening_steps() -> void:
	var play := _play()
	var guide: Control = play.guide
	guide.refresh(0.0)
	check_eq(guide.active, "welcome", "先出欢迎卡")
	check(guide.freezes(), "欢迎卡暂停营业")
	guide._confirm()
	check_eq(guide.active, "open", "然后指向豆浆机")
	check(guide._hole.encloses(play.frame_screen_rect("soy_milk")), "洞套住豆浆机的虚线框")
	play._try_unlock("soy_milk")
	guide.refresh(0.0)
	check_eq(guide.active, "first_sale", "开张后等第一单")
	check(not guide.freezes(), "等第一单时照常营业")
	play.sim.run(40.0)
	guide.refresh(0.0)
	play.sim.gold = 200
	play._try_unlock("rear_equipment")
	guide.refresh(0.0)
	check_eq(guide.active, "hire", "开鏊子后提示招第二个人")
	play.sim.hire()
	guide.refresh(0.0)
	check_eq(guide.active, "done", "招到人后出完成卡")
	guide._confirm()
	check_eq(guide.active, "", "引导结束")
	play.free()


func test_save_restores_progress_and_seen_guides() -> void:
	var path := "user://test_pancake_save.json"
	DirAccess.remove_absolute(path)
	var play := _play(path)
	play.guide._confirm()
	play.sim.gold = 500
	play._try_unlock("soy_milk")
	play._try_unlock("rear_equipment")
	play.sim.hire()
	play.sim.upgrade("rear_equipment")
	play.save_now()
	play.free()
	var again := _play(path)
	check(again.sim.unlocked.get("rear_equipment", false), "读档后鏊子还开着")
	check_eq(again.sim.staff.size(), 2, "读档后员工人数")
	check_eq(int(again.sim.levels.rear_equipment), 2, "读档后升级等级")
	check(again.guide.seen.has("welcome"), "看过的引导不再出")
	check(again.art.source_node(21).visible, "读档后画面跟着开")
	again.free()
	DirAccess.remove_absolute(path)


func test_finishing_the_shop_opens_summary_and_moves_profile_to_tea() -> void:
	var play := _play()
	var sim: PancakeSim = play.sim
	sim.gold = 99999
	for key in ["soy_milk", "rear_equipment", "fryer", "topping"]: sim.unlock(key)
	for i in 5: sim.upgrade("topping")
	for t in sim.cfg.tasks:
		if t.has("dish"): sim.sold[t.dish] = int(t.count)
	sim.step(0.1)
	check(sim.completed_at > 0.0, "任务全部完成就算完店")
	play._refresh_hud()
	check(play._finish.visible, "顶栏出现结店按钮")
	play.open_summary()
	check(play._summary.visible and play._summary_text.text.contains("评分"), "结店总结有评分")
	play._leave_pressed()
	check(play._leave_armed, "第一下只提示不保留")
	var record: Dictionary = sim.summary()
	play.profile.finish_shop(record)
	check_eq(play.profile.shop, "tea", "结店后下一家是奶茶店")
	check(play.profile.fresh_shop, "奶茶店要从空店开始")
	check_eq(play.profile.records.size(), 1, "留一行结店纪录")
	play.profile.reset_all()
	play.free()
