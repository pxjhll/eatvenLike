extends "res://tests/test_case.gd"
## Frozen v0 business regression; formal v1 coverage: test_first_shops_migration.
## 奶茶店玩法跑在通用规则层上（旧 tea_shop_sim / tea_playtest_sim 的行为用例搬过来）：开店顺序、原料箱、招人和名册、
## 前台后厨分工、后厨名额、坐班与调岗、收回员工时放下手上的东西、各台升级效果、售价和星级、小数售价累计、
## 顾客不走只变脸、队伍上限、堂食和外带、封口位与外带架、传送带、传单、跟单与合单、手打柠檬茶、瓶颈提示、星级任务完店。
## 整店节奏由 test_shop_rules 的整店回放对照基准，界面数字由 test_shop_view 对照基准。

const TEA: SpecShop = preload("res://tests/fixtures/legacy_shops/tea.tres")
const LINES := ["boil", "seal", "mix", "press", "topping"]


func _open() -> ShopRules:
	var rules := ShopRules.new(TEA)
	check_eq(rules.unlock("lemonade"), "", "柠檬水台开张")
	return rules


## 所有线都开、加料台升到四种口味都有、后厨两人上岗（旧测试的 opened()）
func _opened() -> ShopRules:
	var rules := _open()
	rules.gold = 20000.0
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	rules.unlock("seal")
	rules.unlock("mix")
	rules.unlock_box("milk")
	rules.unlock("press")
	rules.unlock("topping")
	for i in 3: rules.upgrade("topping")
	rules.hire()
	rules.hire()
	for worker in rules.roster:
		if not worker.deployed: rules.deploy_worker(worker.id)
	return rules


## 东西不会凭空变多变少：库存、预留都不为负，货架计数和各口味加起来一样，不超过容量
func _sane(rules: ShopRules, label: String) -> bool:
	var ok := true
	for id in rules.stations:
		var s: Dictionary = rules.stations[id]
		for side in ["input", "output", "reserved_out"]:
			for item in s[side]:
				if int(s[side][item]) < 0:
					check(false, "%s：%s.%s.%s = %d" % [label, id, side, item, s[side][item]])
					ok = false
		if int(s.reserved_in) < 0 or int(s.processing) < 0:
			check(false, "%s：%s 预留 / 在做为负" % [label, id])
			ok = false
	var total := 0
	for dish in rules.shelf_stock:
		total += int(rules.shelf_stock[dish])
		if int(rules.shelf_stock[dish]) < 0: ok = false
	if total != rules.shelf_count or rules.shelf_reserved_in < 0 or rules.shelf_reserved_out < 0:
		check(false, "%s：货架 %d 件、各口味加起来 %d、预留 %d/%d" % [label, rules.shelf_count, total, rules.shelf_reserved_in, rules.shelf_reserved_out])
		ok = false
	for worker in rules.workers:
		if int(worker.carry_count) < 0 or (int(worker.carry_count) > 0 and String(worker.carry_item).is_empty()):
			check(false, "%s：员工 %d 手上 %s×%d" % [label, worker.id, worker.carry_item, worker.carry_count])
			ok = false
	return ok


func _run_sane(rules: ShopRules, seconds: float, label: String) -> bool:
	var steps := int(seconds / ShopRules.STEP)
	for i in steps:
		rules.step(ShopRules.STEP)
		if i % 50 == 0 and not _sane(rules, label): return false
	return _sane(rules, label)


func _kitchen_worker(rules: ShopRules) -> Dictionary:
	for worker in rules.workers:
		if worker.post != "counter": return worker
	return {}


# ---------- 开店顺序和原料箱 ----------

func test_opening_order_and_boxes() -> void:
	var rules := ShopRules.new(TEA)
	check_eq(int(rules.gold), 50, "开局 50 金币")
	rules.run(20.0)
	check_eq(rules.sold, 0, "没开张不会凭空有收入")
	var before := rules.to_dict()
	check(rules.unlock("boil") != "", "煮茶机要先开柠檬水台")
	check_eq(rules.to_dict(), before, "开不了的时候什么都不变")
	check_eq(rules.unlock("lemonade"), "", "柠檬水台开张")
	check_eq(int(rules.gold), 40, "开张花 10")
	rules.run(80.0)
	check(rules.revenue > 0 and rules.gold > 40, "员工卖出柠檬水")
	check(rules.unlock("mix") != "", "调奶台要等红茶线")
	check(rules.station_unlocked("supply"), "原料柜开局就在")
	rules.gold = float(rules.next_stage_cost())
	check_eq(rules.unlock("boil"), "", "先开煮茶机")
	check(not rules.station_unlocked("seal") and not rules.station_unlocked("mix"), "煮茶机单独开")
	check_eq(int(rules.gold), 0, "按阶段价格收钱")
	check_eq(rules.pending_box(), "tea_leaf", "接着要买茶叶箱")
	check(not rules.dish_open("black_tea"), "没有茶叶箱不卖红茶")
	check(rules.unlock_box("tea_leaf") != "", "茶叶箱要花钱")
	rules.gold = 20.0
	check_eq(rules.unlock_box("tea_leaf"), "", "买茶叶箱")
	check(rules.dish_open("black_tea", false) and rules.pending_box().is_empty(), "有了茶叶箱就能做红茶")
	check(not rules.dish_open("black_tea"), "后厨没人的时候不点红茶")
	check(rules.unlock_box("milk") != "", "牛奶箱要等调奶台")
	rules.gold = 10000.0
	check(rules.unlock("mix") != "", "调奶台要等封口机")
	check_eq(rules.unlock("seal"), "", "封口机单独开")
	check_eq(rules.unlock("mix"), "", "调奶台单独开")
	check_eq(rules.stage_index, 3, "到了奶茶阶段")
	check(not rules.dish_open("plain_milk_tea", false) and rules.pending_box() == "milk", "原味奶茶等牛奶箱")
	check_eq(rules.unlock_box("milk"), "", "买牛奶箱")
	check(rules.dish_open("plain_milk_tea", false), "原味奶茶上架")


func test_black_tea_sells_before_the_milk_machine() -> void:
	var rules := _open()
	rules.gold = 1000.0
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	check_eq(rules.hire(), "", "招一个后厨")
	check_eq(rules.deploy_worker(2), "", "后厨上岗")
	for i in 3000:
		rules.step(0.1)
		if int(rules.sold_by_dish.black_tea) >= 3: break
	check(int(rules.sold_by_dish.black_tea) >= 3, "煮好的红茶上架卖给客人")
	check_eq(int(rules.sold_by_dish.plain_milk_tea), 0, "没有调奶台不卖奶茶")
	check(_sane(rules, "红茶阶段"), "红茶阶段库存对得上")


func test_milk_teas_need_the_whole_chain_before_they_go_on_the_menu() -> void:
	var rules := _open()
	rules.gold = 100000.0
	check_eq(rules.menu(), ["lemonade"] as Array[String], "开张只卖柠檬水")
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	rules.hire()
	rules.deploy_worker(2)
	check("black_tea" in rules.menu() and not "plain_milk_tea" in rules.menu(), "红茶上菜单，奶茶还没有")
	rules.unlock("seal")
	rules.unlock("mix")
	check(not "plain_milk_tea" in rules.menu(), "没买牛奶箱不卖奶茶")
	rules.unlock_box("milk")
	check("plain_milk_tea" in rules.menu(), "整条线齐了才卖原味奶茶")
	check(not "pearl_milk_tea" in rules.menu(), "加料台没开不卖珍珠奶茶")


# ---------- 招人、名册、名额 ----------

func test_hire_order_prices_and_roster_without_limit() -> void:
	var rules := ShopRules.new(TEA)
	rules.gold = 180.0
	for expected in [[35, "raccoon", 2], [60, "fox", 3]]:
		check_eq(rules.hire_cost(), expected[0], "招人价格按顺序涨")
		var before := rules.gold
		check_eq(rules.hire(), "", "招到 " + expected[1])
		check(is_equal_approx(rules.gold, before - expected[0]), "招人扣全价")
		check_eq(rules.worker_by_id(expected[2]).kind, expected[1], "名册 id 固定")
	check_eq(rules.hire_cost(), 85, "第四位 85")
	check_eq(rules.next_hire_kind(), "rabbit", "第四位是小兔子")
	rules.gold = 84.0
	var before := rules.to_dict()
	check(rules.hire() != "", "钱不够招不了")
	check_eq(rules.to_dict(), before, "招不了的时候什么都不变")
	rules.gold = 85.0
	check_eq(rules.hire(), "", "招到小兔子")
	check_eq(rules.workers.size(), 1, "招来的人先进名册")
	var rabbit := rules.worker_by_id(4)
	check_eq(rabbit.kind, "rabbit", "4 号是小兔子")
	check_eq(rabbit.name, "小兔子", "小兔子的名字")
	check_eq(rabbit.source, "招募", "来源记成招募")
	check_eq(rules.hire_cost(), 110, "名册不设上限，第五位更贵")
	check_eq(rules.next_hire_kind(), "gray_cat", "接着是小灰猫")
	rules.gold = 110.0
	rules.hire()
	check_eq(rules.next_hire_kind(), "bear", "然后是小熊")
	rules.gold = 135.0
	rules.hire()
	check_eq(rules.worker_by_id(6).kind, "bear", "小熊 6 号")
	rules.gold = 160.0
	check_eq(rules.hire(), "", "六种都有以后从头再来")
	check_eq(rules.worker_by_id(7).kind, "cat", "重复的种类拿新 id")
	check_eq(rules.next_hire_kind(), "raccoon", "重复也按顺序")
	var copy := ShopRules.new(TEA)
	check_eq(copy.load_dict(rules.to_dict()), "", "有重复种类的名册能存能读")


func test_kitchen_slots_grow_with_each_production_line() -> void:
	var rules := ShopRules.new(TEA)
	rules.gold = 100000.0
	for unused in 7: rules.hire()
	check_eq(rules.staff_slots(), 1, "柠檬水阶段只有前台一人")
	check_eq(rules.workers[0].post, "counter", "开局的人在柜台")
	var before := rules.to_dict()
	check(rules.deploy_worker(2) != "", "没有后厨线不能派后厨")
	check_eq(rules.to_dict(), before, "派不了的时候什么都不变")
	check_eq(rules.unlock("lemonade"), "", "开张")
	var next_id := 2
	var added_by_line := {"boil": 1, "seal": 0, "mix": 1, "press": 0, "topping": 3}
	for line in LINES:
		var slots := rules.kitchen_slots()
		check_eq(rules.unlock(line), "", "开 " + line)
		check_eq(rules.kitchen_slots(), slots + int(added_by_line[line]), "%s 加 %d 个后厨名额" % [line, added_by_line[line]])
		for unused in int(added_by_line[line]):
			check_eq(rules.deploy_worker(next_id), "", "新名额派一个人")
			next_id += 1
		check(rules.deploy_worker(next_id) != "", "名额满了派不进去")
	check_eq(rules.kitchen_staff(), 5, "后厨最多 5 人")
	check_eq(rules.role_room(""), "后厨最多 5 位员工", "满了的提示")
	check(_run_sane(rules, 60.0, "五人后厨"), "五人后厨库存对得上")
	rules.reset()
	check_eq(rules.workers.size(), 1, "重开只剩开局的人")
	check_eq(rules.staff_slots(), 1, "重开回到开局名额")


func test_front_and_kitchen_staff_have_their_own_duties_and_upgrades() -> void:
	var rules := _opened()
	var front: Dictionary = rules.workers.filter(func(w: Dictionary) -> bool: return w.post == "counter")[0]
	var kitchen := _kitchen_worker(rules)
	var walk_front := rules.walk_speed(front)
	var walk_kitchen := rules.walk_speed(kitchen)
	var gold := rules.gold
	var cost := rules.upgrade_cost("staff/front")
	check_eq(rules.upgrade("staff/front"), "", "前台升级能买")
	check(is_equal_approx(rules.gold, gold - cost), "按标价扣钱")
	check(rules.walk_speed(front) >= walk_front and is_equal_approx(rules.walk_speed(kitchen), walk_kitchen), "前台升级不影响后厨")
	var front_slots := rules.front_slots()
	while rules.upgrade_cost("staff/front") >= 0 and rules.upgrade_error("staff/front") == "": check_eq(rules.upgrade("staff/front"), "", "前台升级一项")
	check(rules.front_slots() > front_slots, "前台升级里有加前台名额")
	check(rules.upgrade("staff/front") != "", "买完了不能再买")
	var carry := rules.carry(kitchen)
	while rules.upgrade_cost("staff/kitchen") >= 0 and rules.upgrade_error("staff/kitchen") == "": rules.upgrade("staff/kitchen")
	check(rules.carry(kitchen) > carry, "后厨升级加每趟搬运量")
	rules.gold = 1000.0
	rules.hire()
	var extra: Dictionary = rules.roster.back()
	check_eq(rules.place_worker(extra.id, "counter"), "", "第二位前台去柜台")
	check_eq(rules.workers.filter(func(w: Dictionary) -> bool: return w.post == "counter").size(), 2, "两人在前台")
	var copy := ShopRules.new(TEA)
	check_eq(copy.load_dict(rules.to_dict()), "", "前台后厨升级能存")
	check_eq(copy.levels["staff/front"], rules.levels["staff/front"], "前台升级读回来")
	check_eq(copy.levels["staff/kitchen"], rules.levels["staff/kitchen"], "后厨升级读回来")
	var wrong := 0
	for tick in 3000:
		rules.step(0.1)
		for worker in rules.workers:
			if worker.job.is_empty(): continue
			if worker.post == "counter" and worker.job.kind != "serve": wrong += 1
			if worker.post != "counter" and worker.job.kind == "serve": wrong += 1
	check_eq(wrong, 0, "前台只接待递杯，后厨从不接待")
	check(_sane(rules, "前后分工"), "分工以后库存对得上")


func test_recall_busy_worker_and_reset_send_hired_staff_away() -> void:
	var rules := ShopRules.new(TEA)
	rules.gold = 500.0
	check_eq(rules.hire(), "", "招人")
	check(rules.deploy_worker(2).contains("后厨"), "没有煮茶机不能派后厨")
	rules.unlock("lemonade")
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	check_eq(rules.deploy_worker(2), "", "名册里的人派到后厨")
	var worker := rules.worker_by_id(2)
	check(is_same(worker, rules.workers[1]), "上岗的就是名册里那一份")
	for tick in 600:
		rules.step(0.1)
		if worker.carry_count > 0: break
	check(worker.carry_count > 0, "后厨员工搬东西")
	check_eq(rules.recall_worker(2), "", "忙着的人也能收回")
	check(worker.carry_count == 0 and worker.job.is_empty(), "收回时放下手上的东西")
	check(_sane(rules, "收回"), "收回以后库存和预留对得上")
	rules.reset()
	check_eq(rules.roster.size(), 1, "重开时招来的人离开（员工不跨店）")
	check_eq(int(rules.gold), 50, "重开回到开局金币")
	check_eq(rules.workers[0].post, "counter", "开局的人在柜台")


func test_cancelled_jobs_release_reservations_at_every_phase() -> void:
	var rules := _opened()
	rules.send_flyers()
	var phases := {}
	for tick in 4000:
		rules.step(0.1)
		if tick % 7 != 0: continue
		var worker := _kitchen_worker(rules)
		if worker.is_empty() or worker.job.is_empty(): continue
		var key := "%s/%s" % [worker.job.kind, worker.phase]
		if phases.has(key): continue
		phases[key] = true
		var id: int = worker.id
		check_eq(rules.recall_worker(id), "", "收回正在 %s 的人" % key)
		if not _sane(rules, "收回 " + key): return
		check_eq(rules.deploy_worker(id), "", "再派回去")
	check(phases.size() >= 4, "收回时碰到了 %d 种活：%s" % [phases.size(), phases.keys()])
	check(_run_sane(rules, 120.0, "收回以后接着做"), "收回过的店接着做下去库存对得上")
	check(rules.sold > 20, "收回过的人照样卖货")


# ---------- 坐班和调岗 ----------

func test_post_assignment_release_and_invalid_drops() -> void:
	var rules := _opened()
	var worker := _kitchen_worker(rules)
	check_eq(rules.place_worker(worker.id, "boil"), "", "派到煮茶机坐班")
	check(worker.post == "boil" and worker.pos == rules.nav.post("boil"), "人马上到岗位上")
	var before := rules.to_dict()
	var other: Dictionary = rules.workers.filter(func(w: Dictionary) -> bool: return w.post != "counter" and w.id != worker.id)[0]
	check(rules.place_worker(other.id, "boil") != "", "有人的岗位不能再放人")
	check(rules.place_worker(other.id, "nowhere") != "", "不存在的岗位")
	check(rules.place_worker(other.id, "", Vector2(-50, -50)) != "", "墙外的空地放不了")
	check_eq(rules.to_dict(), before, "放不了的时候什么都不变")
	check_eq(rules.place_worker(worker.id, "", rules.nav.point("counter")), "", "拖回空地就是流动")
	check_eq(worker.post, "", "流动员工没有岗位")
	var fresh := _open()
	fresh.gold = 1000.0
	fresh.unlock("boil")
	fresh.hire()
	check(fresh.place_worker(2, "topping") != "", "没解锁的机器不能坐班")


func test_seated_brewer_runs_its_pot_while_followers_carry_the_tea() -> void:
	var rules := _opened()
	var brewer := _kitchen_worker(rules)
	check_eq(rules.place_worker(brewer.id, "boil"), "", "派一人坐煮茶机")
	rules.send_flyers()
	var others_at_pot := 0
	var brewer_left := false
	for tick in 3000:
		rules.step(0.1)
		if brewer.post != "boil": brewer_left = true
		for worker in rules.workers:
			if worker.id == brewer.id or worker.job.is_empty(): continue
			if worker.job.kind in ["pot_start", "stir"] and worker.job.src == "boil": others_at_pot += 1
	check(not brewer_left, "坐班的人一直守着煮茶机")
	check_eq(others_at_pot, 0, "装料、搅拌都由坐班的人做")
	check(int(rules.sold_by_dish.plain_milk_tea) + int(rules.sold_by_dish.black_tea) > 0, "别人把茶端走卖掉")
	check(_sane(rules, "坐班煮茶"), "坐班煮茶库存对得上")


func test_seating_every_kitchen_hand_warns_nobody_carries() -> void:
	var rules := _opened()
	check(not rules.no_kitchen_carrier(), "有流动的后厨就不提示")
	var kitchen: Array = rules.workers.filter(func(w: Dictionary) -> bool: return w.post != "counter")
	rules.place_worker(kitchen[0].id, "boil")
	rules.place_worker(kitchen[1].id, "topping")
	check(rules.no_kitchen_carrier(), "后厨全坐班，没人搬东西")


func test_brewer_pauses_for_stirring() -> void:
	var rules := _opened()
	var stirred := false
	for tick in 3000:
		rules.step(0.1)
		for worker in rules.workers:
			if not worker.job.is_empty() and worker.job.kind == "stir": stirred = true
		if stirred: break
	check(stirred, "煮茶中途要人搅拌")


# ---------- 升级效果、售价、星级 ----------

func test_brewer_levels_brew_more_tea_per_minute() -> void:
	var rules := _opened()
	rules.gold = 100000.0
	var batches: Array = []
	var rates: Array = []
	for lv in range(1, 9):
		batches.append(rules.pot_batch("boil"))
		rates.append(rules.pot_batch("boil") / rules.pot_seconds("boil"))
		if lv < 8: check_eq(rules.upgrade("boil"), "", "煮茶机升到 Lv%d" % (lv + 1))
	check_eq(batches, [2, 3, 3, 4, 4, 5, 6, 6], "一锅从 2 杯涨到 6 杯")
	for lv in range(1, 8): check(rates[lv] > rates[lv - 1], "Lv%d 每分钟煮得更多" % (lv + 1))
	check(rules.upgrade("boil") != "", "煮茶机最高 Lv8")


func test_sealer_levels_speed_up_and_a_star_adds_a_slot() -> void:
	var rules := _opened()
	rules.gold = 100000.0
	check_eq(rules.process_slots("seal"), 1, "封口机开局一个位")
	var before := rules.machine_seconds("seal")
	for lv in range(1, 6):
		check_eq(rules.upgrade("seal"), "", "封口机升到 Lv%d" % (lv + 1))
		check(rules.machine_seconds("seal") < before, "每级封得更快")
		before = rules.machine_seconds("seal")
		if lv + 1 == 5: check_eq(rules.process_slots("seal"), 2, "Lv5 星级加第二个封口位")
	check_eq(rules.stars("seal"), 1, "Lv6 一颗星")
	check(rules.upgrade("seal") != "", "封口机最高 Lv6")


func test_ingredient_upgrades_raise_prices_not_speed() -> void:
	var rules := _opened()
	rules.gold = 100000.0
	var mix := rules.machine_seconds("mix")
	var milk_tea := rules.dish_price("plain_milk_tea")
	var black := rules.dish_price("black_tea")
	check_eq(rules.upgrade("supply/tea_leaf"), "", "茶叶升级")
	check(rules.dish_price("black_tea") > black and rules.dish_price("plain_milk_tea") > milk_tea, "茶叶让红茶和奶茶都涨价")
	var after_leaf := rules.dish_price("black_tea")
	check_eq(rules.upgrade("supply/milk"), "", "牛奶升级")
	check(rules.dish_price("plain_milk_tea") > milk_tea and is_equal_approx(rules.dish_price("black_tea"), after_leaf), "牛奶只让奶茶涨价")
	check(is_equal_approx(rules.machine_seconds("mix"), mix), "原料升级不改调奶时间")
	var pearl := rules.dish_price("pearl_milk_tea")
	var coconut := rules.dish_price("coconut_milk_tea")
	check_eq(rules.upgrade("topping/pearl"), "", "珍珠升级")
	check(rules.dish_price("pearl_milk_tea") > pearl and is_equal_approx(rules.dish_price("coconut_milk_tea"), coconut), "珍珠只让珍珠奶茶涨价")
	var before := rules.to_dict()
	check(rules.upgrade("bad/milk") != "", "不存在的升级")
	check_eq(rules.to_dict(), before, "升级不了的时候什么都不变")


func test_price_levels_multiply_and_stars_jump() -> void:
	var rules := _opened()
	rules.gold = 100000.0
	var base := rules.dish_price("plain_milk_tea")
	var prices: Array = [base]
	for lv in range(2, 8):
		check_eq(rules.upgrade("mix"), "", "调奶台升到 Lv%d" % lv)
		prices.append(rules.dish_price("plain_milk_tea"))
	check_eq(rules.stars("mix"), 2, "Lv7 两颗星")
	check(rules.upgrade("mix") != "", "调奶台最高 Lv7")
	var step: float = prices[1] / prices[0]
	check(prices[3] / prices[2] > step * 1.1, "Lv4 星级多涨一截")
	check(prices[6] / prices[5] > step * 1.1, "Lv7 星级多涨一截")
	for i in range(1, prices.size()): check(prices[i] > prices[i - 1], "每级都涨价")
	var pour := rules.machine_seconds("lemonade")
	var last := rules.dish_price("lemonade")
	for lv in range(2, 6):
		check_eq(rules.upgrade("lemonade"), "", "柠檬水台升到 Lv%d" % lv)
		check(rules.dish_price("lemonade") > last, "Lv%d 柠檬水更贵（12.6 和 13.2 不能都算 13）" % lv)
		last = rules.dish_price("lemonade")
	check(rules.upgrade("lemonade") != "", "柠檬水台最高 Lv5")
	check(is_equal_approx(rules.machine_seconds("lemonade"), pour), "柠檬水台升级只涨价，不加速")


func test_sales_carry_the_tenths_of_a_price() -> void:
	var rules := _opened()
	check_eq(rules.upgrade("lemonade"), "", "柠檬水台 Lv2")
	check(absf(rules.dish_price("lemonade") - 12.6) < 0.001, "Lv2 柠檬水 12.6")
	var gold := rules.gold
	for unused in 5: rules._record_sale({"item": "lemonade", "count": 1, "order_id": -1, "src": "lemonade", "dst": "counter", "takeaway": true})
	check_eq(int(rules.gold - gold), 63, "五杯 12.6 一共 63，零头累计不丢")


func test_every_price_level_adds_gold() -> void:
	for id in ["lemonade", "mix", "press", "topping"]:
		var rules := _opened()
		rules.gold = 100000.0
		var dishes: Array = TEA.dishes.filter(func(d: SpecDish) -> bool: return d.steps.any(func(s: SpecStep) -> bool: return s.station == id))
		while rules.upgrade_cost(id) >= 0 and rules.upgrade_error(id) == "":
			var before: Array = dishes.map(func(d: SpecDish) -> float: return rules.dish_price(d.id))
			check_eq(rules.upgrade(id), "", "%s 升到 Lv%d" % [id, rules.level(id) + 1])
			var after: Array = dishes.map(func(d: SpecDish) -> float: return rules.dish_price(d.id))
			var gained := false
			for i in before.size(): gained = gained or after[i] > before[i]
			var opens := TEA.station(id).block == "topping"
			check(gained or opens, "%s Lv%d 让这台的菜更值钱或开新口味" % [id, rules.level(id)])


func test_price_preview_matches_the_price_after_upgrading() -> void:
	var rules := _opened()
	rules.gold = 100000.0
	var view := ShopView.new(rules)
	for id in ["lemonade", "mix", "press"]:
		var p := view.price_preview(id)
		rules.upgrade(id)
		check(absf(view.price_preview(id).now - p.next) < 0.001, "%s 预览的下一级价格就是升完的价格" % id)


# ---------- 顾客 ----------

func test_customers_never_leave_they_get_impatient_then_angry() -> void:
	var rules := _open()
	rules.recall_worker(1)
	rules.run(60.0)
	check(not rules.orders.is_empty(), "没人接待，客人排着")
	check_eq(rules.lost, 0, "客人不走")
	var moods: Array = rules.orders.map(func(o: Dictionary) -> int: return rules.order_mood(o))
	check(moods.max() == 2, "等太久的客人生气")
	var fresh := {"id": 99, "wait": 0.0, "seat": -1}
	var waited := {"id": 98, "wait": 20.0, "seat": -1}
	check_eq(rules.order_mood(fresh), 0, "刚来的客人不急")
	check_eq(rules.order_mood(waited), 1, "等了 20 秒的客人急了")


func test_customer_queue_uses_the_stage_capacity() -> void:
	var rules := _open()
	rules.recall_worker(1)
	rules.run(200.0)
	check_eq(rules.queue_size(), rules.queue_capacity(), "没人接待时队伍排到上限")
	check_eq(rules.queue_capacity(), TEA.stages[0].queue_capacity + rules.seated_orders(), "上限 = 阶段站位 + 坐着等的人")
	rules.gold = 1000.0
	var before := rules.queue_capacity()
	rules.unlock("boil")
	check_eq(rules.queue_capacity() - before, TEA.stages[1].queue_capacity - TEA.stages[0].queue_capacity, "开煮茶机以后站位变多")


func test_dine_in_needs_a_seat_and_takeaway_goes_through_the_sealer() -> void:
	var rules := _open()
	rules.gold = 100000.0
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	rules.run(120.0)
	check(rules.orders.all(func(o: Dictionary) -> bool: return not o.takeaway), "没有封口机的时候没有外带")
	rules.unlock("seal")
	rules.recall_worker(1)
	rules.run(200.0)
	var seated: Array = rules.orders.filter(func(o: Dictionary) -> bool: return int(o.seat) >= 0)
	var takeaway: Array = rules.orders.filter(func(o: Dictionary) -> bool: return o.takeaway)
	check(seated.size() <= rules.seat_total(), "有座才坐下（%d 座 %d 人）" % [rules.seat_total(), seated.size()])
	check(not takeaway.is_empty(), "座满了的客人外带")
	check(takeaway.all(func(o: Dictionary) -> bool: return int(o.seat) < 0), "外带的不占座")
	var seats := rules.seat_total()
	check_eq(rules.buy_seat(), "", "买座位")
	check(rules.seat_total() > seats, "座位变多")


func test_seated_customers_eat_in_the_seat_they_kept() -> void:
	var rules := _opened()
	rules.send_flyers()
	var checked := 0
	var kept := {}
	for tick in 3000:
		rules.step(0.1)
		for order in rules.orders:
			if int(order.seat) >= 0: kept[order.id] = int(order.seat)
		for diner in rules.diners:
			checked += 1
		if checked > 50: break
	check(checked > 0, "有客人坐下吃")
	var seats: Array = rules.diners.map(func(d: Dictionary) -> int: return int(d.seat))
	var unique := {}
	for s in seats: unique[s] = true
	check_eq(unique.size(), seats.size(), "每个座位只坐一个人")
	check(seats.all(func(s: int) -> bool: return s >= 0 and s < rules.seat_total()), "坐在真的座位上")


func test_dine_in_customers_sit_shorter_early_and_longer_later() -> void:
	var rules := _open()
	var early := rules.seat_seconds()
	rules.gold = 100000.0
	for id in LINES: rules.unlock(id)
	check(rules.seat_seconds() > early, "后面的阶段堂食坐得更久（%.0f → %.0f 秒）" % [early, rules.seat_seconds()])


func test_flyers_bring_customers_and_have_a_cooldown() -> void:
	var rules := _open()
	var count := rules.flyer_customers()
	check(count > 0, "传单带客人来")
	var gold := rules.gold
	var interval := rules._order_interval()
	check_eq(rules.send_flyers(), "", "发传单")
	check(is_equal_approx(rules.gold, gold), "传单免费")
	check(is_equal_approx(rules._order_interval(), interval), "传单不改平常的来客间隔")
	check(rules.send_flyers() != "", "传单起效时不能再发")
	rules.orders.clear()
	var got := 0
	for i in int(TEA.flyer.wave_seconds / ShopRules.STEP) + 5:
		rules._flyer_entry_wave()
		# 马上接走，不让队伍上限挡住传单客
		got += rules.orders.size()
		rules.orders.clear()
	check_eq(got, count, "一波来的正好是传单上的人数")
	check_eq(rules.flyer_pending, 0, "没人还在外面等")
	rules.flyer_wait = 5.0
	check(rules.flyer_error() != "", "传单在冷却")
	rules.run(5.5)
	check_eq(rules.flyer_error(), "", "冷却完可以再发")
	rules.gold = 100000.0
	var wait := rules.flyer_cooldown()
	check_eq(rules.upgrade("flyer"), "", "传单升级")
	check(rules.flyer_customers() > count or rules.flyer_cooldown() < wait, "升级后的传单带更多人或冷却更短")
	rules.send_flyers()
	var copy := ShopRules.new(TEA)
	check_eq(copy.load_dict(rules.to_dict()), "", "传单起效中能存能读")
	check_eq(copy.flyer_pending, rules.flyer_pending, "读档后还要来的传单客还在")
	check(is_equal_approx(copy.flyer_wait, rules.flyer_wait), "读档后冷却还在")


func test_new_dishes_ease_in_over_a_dozen_customers() -> void:
	var rules := _open()
	rules.gold = 1000.0
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	rules.hire()
	rules.deploy_worker(2)
	var first: float = rules.order_weights().get("black_tea", 0.0)
	rules.run(300.0)
	var later: float = rules.order_weights().get("black_tea", 0.0)
	check(first > 0.0 and later > first, "新菜一开始点得少，过十来位客人才到正常比例（%.2f → %.2f）" % [first, later])


func test_kitchen_drinks_wait_for_a_kitchen_hand_so_lemonade_keeps_selling() -> void:
	var rules := _open()
	rules.gold = 1000.0
	rules.unlock("boil")
	rules.unlock_box("tea_leaf")
	check(not "black_tea" in rules.order_weights(), "后厨没人的时候客人不点红茶")
	rules.run(120.0)
	check(int(rules.sold_by_dish.lemonade) > 0 and int(rules.sold_by_dish.black_tea) == 0, "柠檬水照卖")


# ---------- 出餐口、外带架、传送带 ----------

func test_shelf_capacity_is_per_dish_and_counts_reserved_slots() -> void:
	var rules := _opened()
	check(rules.shelf_capacity() > 0, "出餐口有容量")
	check(_run_sane(rules, 300.0, "出餐口"), "出餐口计数和预留对得上")
	check(rules.shelf_count + rules.shelf_reserved_in <= rules.shelf_capacity(), "放上去的和预留的不超过容量")


func test_sealed_takeaway_cups_go_to_the_rack_and_the_front_never_enters_the_kitchen() -> void:
	var rules := _opened()
	rules.orders = [{"id": rules._next_order, "dish": "plain_milk_tea", "wait": 0.0, "reserved": false, "takeaway": true, "seat": -1}]
	var wanted: int = rules._next_order
	rules._next_order += 1
	var front_sources := {}
	var racked := false
	for tick in 1500:
		rules.step(0.1)
		for worker in rules.workers:
			if worker.job.is_empty(): continue
			if worker.post == "counter": front_sources[worker.job.src] = true
			elif worker.job.dst == "rack": racked = true
		if not rules.orders.any(func(o: Dictionary) -> bool: return o.id == wanted): break
	check(racked, "后厨把封好的外带杯送到外带架")
	check(not rules.orders.any(func(o: Dictionary) -> bool: return o.id == wanted), "外带客人拿到了")
	check(not front_sources.has("seal") and not front_sources.has("boil"), "前台从不进后厨拿东西：%s" % [front_sources.keys()])
	check(front_sources.has("rack"), "前台在外带架取外带杯")
	check(_sane(rules, "外带架"), "外带架库存对得上")


func test_lemonade_to_go_is_handed_over_without_the_sealer() -> void:
	var lemonade := TEA.dish("lemonade")
	check(not lemonade.takeaway_process, "柠檬水外带不封口")
	check(not TEA.dish("lemon_tea").takeaway_process, "柠檬茶外带不封口")
	check(TEA.dish("plain_milk_tea").takeaway_process, "奶茶外带要封口")


func test_belt_segments_are_bought_and_move_goods_without_staff() -> void:
	var rules := _opened()
	rules.gold = 100000.0
	var rows := rules.connection_rows()
	check(not rows.is_empty(), "有可以买的传送带")
	var first: Dictionary = rows[0]
	check_eq(rules.buy_connection(first.id), "", "买第一段传送带")
	check(rules.buy_connection(first.id) != "", "同一段不能买两次")
	var moved := false
	for tick in 3000:
		rules.step(0.1)
		if not rules.belt_items.is_empty(): moved = true
		if moved: break
	check(moved, "传送带上有东西在走")
	check(_run_sane(rules, 120.0, "传送带"), "传送带库存对得上")


# ---------- 跟单、合单、手打台、加料 ----------

func test_kitchen_staff_follow_an_order_from_the_pot_to_the_shelf() -> void:
	var rules := _opened()
	for worker in rules.workers.duplicate():
		if worker.post != "counter" and worker.id != _kitchen_worker(rules).id: rules.recall_worker(worker.id)
	var cook := _kitchen_worker(rules)
	var srcs := {}
	for tick in 3000:
		rules.step(0.1)
		if not cook.job.is_empty(): srcs[cook.job.src] = true
		if int(rules.sold_by_dish.plain_milk_tea) + int(rules.sold_by_dish.pearl_milk_tea) > 0: break
	check(srcs.has("boil") and srcs.has("mix"), "一个后厨跟着单从煮茶走到调奶：%s" % [srcs.keys()])


func test_orders_next_to_each_other_for_the_same_drink_share_one_follower() -> void:
	var rules := _opened()
	rules.gold = 100000.0
	while rules.upgrade_cost("staff/kitchen") >= 0 and rules.upgrade_error("staff/kitchen") == "": rules.upgrade("staff/kitchen")
	var shared := false
	rules.send_flyers()
	for tick in 4000:
		rules.step(0.1)
		for worker in rules.workers:
			if worker.post != "counter" and int(worker.carry_count) > 1: shared = true
		if shared: break
	check(shared, "相邻的同一种单一起做，一趟端多杯")


func test_cups_left_at_the_topping_machine_are_picked_up_later() -> void:
	var rules := _opened()
	rules.send_flyers()
	check(_run_sane(rules, 600.0, "加料"), "加料台的杯子都有人接着端走")
	for flavor in ["pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]:
		check(int(rules.sold_by_dish[flavor]) > 0, "卖出 " + flavor)


func test_lemon_tea_is_pressed_at_the_front_from_a_lemonade() -> void:
	var rules := _opened()
	check(rules.dish_open("lemon_tea", false), "开了手打台就卖柠檬茶")
	rules.orders = [{"id": 900, "dish": "lemon_tea", "wait": 0.0, "reserved": false, "takeaway": true, "seat": -1},
		{"id": 901, "dish": "lemon_tea", "wait": 0.0, "reserved": false, "takeaway": false, "seat": -1}]
	rules._next_order = 902
	var makers := {}
	for tick in 600:
		rules.step(0.1)
		for worker in rules.workers:
			if not worker.job.is_empty() and worker.job.item == "lemon_tea": makers[worker.post] = true
		check_eq(int(rules.stations.seal.input.lemon_tea) + int(rules.stations.seal.output.lemon_tea), 0, "外带柠檬茶不封口")
		if int(rules.sold_by_dish.lemon_tea) >= 2: break
	check_eq(int(rules.sold_by_dish.lemon_tea), 2, "两杯柠檬茶都送到")
	check_eq(makers.keys(), ["counter"], "只有前台做柠檬茶")
	var price := rules.dish_price("lemon_tea")
	rules.upgrade("lemonade")
	check(is_equal_approx(rules.dish_price("lemon_tea"), price), "柠檬水台升级不改柠檬茶的价")
	var view := ShopView.new(rules)
	check(view.price_preview("press").next > view.price_preview("press").now, "手打台升级让柠檬茶更贵")
	check(_sane(rules, "柠檬茶"), "柠檬茶库存对得上")


func test_full_other_flavors_do_not_block_the_requested_flavor() -> void:
	var rules := _opened()
	var cap := int(TEA.station("topping").params.flavor_cap)
	for flavor in ["coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]: rules.stations.topping.output[flavor] = cap
	rules.send_flyers()
	for tick in 3000:
		rules.step(0.1)
		if int(rules.sold_by_dish.pearl_milk_tea) > 0: break
	check(int(rules.sold_by_dish.pearl_milk_tea) > 0, "别的口味占满了，珍珠照样能做")


# ---------- 瓶颈、任务、完店 ----------

func test_a_jammed_line_names_its_bottleneck() -> void:
	var rules := _open()
	var view := ShopView.new(rules)
	rules.gold = 100000.0
	rules.hire()
	for line in ["boil", "seal", "mix"]: rules.unlock(line)
	for material in ["tea_leaf", "milk"]: rules.unlock_box(material)
	rules.deploy_worker(2)
	check(view.bottleneck().is_empty(), "线顺的时候没有提示")
	var hint: Dictionary = {}
	for tick in 3000:
		rules.step(0.1)
		hint = view.bottleneck()
		if not hint.is_empty(): break
	check(not hint.is_empty(), "堵了一阵就有瓶颈提示")
	check(String(hint.get("text", "")).contains("升级") or String(hint.get("text", "")).contains("派") or String(hint.get("text", "")).contains("招"), "提示说了该做什么：%s" % hint.get("text", ""))
	rules.orders.clear()
	rules.step(0.2)
	check(view.bottleneck().is_empty(), "队伍有空位了提示就收起")


func test_star_tasks_finish_the_shop() -> void:
	var rules := _opened()
	check(rules.task_rows().size() >= 10, "任务都列出来（含星级任务）")
	check(not rules.shop_complete(), "还没完店")
	rules.gold = 10000000.0
	for key in ["lemonade", "boil", "seal", "mix", "press", "topping"]:
		while rules.upgrade_cost(key) >= 0 and rules.upgrade_error(key) == "": rules.upgrade(key)
	for dish in rules.sold_by_dish: rules.sold_by_dish[dish] = 100
	rules.sold = 1000
	rules.step(0.1)
	check(rules.shop_complete(), "任务全做完、菜单全开就完店")


# ---------- 存档 ----------

func test_flavors_conserved_and_mid_shop_resume_is_identical() -> void:
	var rules := _opened()
	var resumed := ShopRules.new(TEA)
	for tick in 9000:
		rules.step(0.1)
		if tick % 100 == 0 and not _sane(rules, "整局"): return
		if tick == 831:
			check_eq(resumed.load_dict(rules.to_dict()), "", "中途存档能读")
			check_eq(resumed.to_dict(), rules.to_dict(), "读回来一模一样")
		if tick > 831:
			resumed.step(0.1)
			if tick % 300 == 0 and resumed.to_dict() != rules.to_dict():
				check(false, "读档以后接着跑（含随机数和在做的活）一模一样")
				return
	for dish in ["plain_milk_tea", "pearl_milk_tea", "coconut_milk_tea", "redbean_milk_tea", "taro_milk_tea"]:
		check(int(rules.sold_by_dish[dish]) > 0, "卖出 " + dish)


func test_malformed_load_does_not_touch_the_live_shop() -> void:
	var rules := _opened()
	rules.run(30.0)
	var before := rules.to_dict()
	var malformed := before.duplicate(true)
	malformed.stations = "坏掉的"
	check(rules.load_dict(malformed) != "", "坏存档读不进来")
	check_eq(rules.to_dict(), before, "读坏存档不会改到正在玩的店")
	var missing := before.duplicate(true)
	missing.erase("gold")
	check(rules.load_dict(missing) != "", "缺字段的存档读不进来")
	check_eq(rules.to_dict(), before, "缺字段也不改店")


func test_saves_follow_the_shop_data_when_machines_are_added_or_removed() -> void:
	var rules := _opened()
	rules.run(30.0)
	var data := rules.to_dict()
	# 存档时店里还没有手打台（数据里后来加的），却有一台现在已经删掉的机器
	for key in ["unlocked", "levels", "stations"]:
		data[key].erase("press")
		data[key]["old_machine"] = data[key]["boil"]
	var copy := ShopRules.new(TEA)
	check_eq(copy.load_dict(data), "", "旧存档照样能读")
	check(not copy.station_unlocked("press") and copy.level("press") == 1, "新加的机器用开局默认值")
	check(not copy.unlocked.has("old_machine") and not copy.stations.has("old_machine"), "删掉的机器不留在店里")
	check(copy.station_unlocked("boil") and copy.level("boil") == rules.level("boil"), "其他机器照旧")
	check(_run_sane(copy, 60.0, "补默认值以后"), "补了默认值的店接着做库存对得上")
