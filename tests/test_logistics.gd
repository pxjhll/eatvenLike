extends "res://tests/test_case.gd"
## 物流：按物品分路的传送带、出口回压、货架库存与预留、原料柜按需轮流出货。

const Cases := preload("res://tests/fixtures/production_cases.gd")


# 一条供料 → 加工 → 货架的链：物料守恒，成品只从加工那一路进货架。
func test_chain_conserves_material() -> void:
	var sim := _chain()
	sim.run_seconds(60.0)
	check(Cases.produced(sim, "dough") > 0, "加工设备真的做出了东西")
	check(sim.production.shelf.get("dough", 0) > 0, "成品送到了货架")
	check_eq(sim.production.shelf.get("flour", 0), 0, "原料不会绕过加工直接上货架")
	_check_conservation(sim, ["flour", "dough"])


# 货架满了，压力一路传回原料柜；腾出货架后整条线恢复。
func test_full_shelf_backpressures_upstream_and_resumes_after_consumption() -> void:
	var sim := _chain(true)
	sim.run_seconds(100.0)
	check_eq(sim.production.shelf.get("dough", 0), 2, "有上限的货架满了")
	check_eq(Cases.state(sim, "prep").outputs.get("dough", 0), 1, "成品堵在加工设备的出口")
	check_eq(Cases.state(sim, "supply").outputs.get("flour", 0), 0, "原料柜看到下游没空位就不再出货")
	var before := JSON.stringify(sim.production.to_dict(), "", false)
	var flour_before := Cases.produced(sim, "flour")
	sim.run_seconds(5.0)
	check_eq(JSON.stringify(sim.production.to_dict(), "", false), before, "堵住的线不移动、不复制物料")
	check_eq(Cases.produced(sim, "flour"), flour_before, "堵住时原料柜不空转出货")
	check(sim.production.reserve(1000000, "dough", 2), "货架上的库存可以预留")
	sim.diagnostics.record(0.0, sim.production.take_reserved(1000000))
	check_eq(sim.production.free_stock("dough"), 0, "取走后货架空了")
	sim.run_seconds(30.0)
	check_eq(sim.production.shelf.get("dough", 0), 2, "取走后货架重新补满")
	check(Cases.produced(sim, "flour") > flour_before, "腾出的空位一路传回原料柜")
	_check_conservation(sim, ["flour", "dough"])


# 预留只占用实际库存，空货架和重叠订单都变不出货来。
func test_empty_and_reserved_inventory_do_not_create_stock() -> void:
	var sim := _chain()
	check(not sim.production.reserve(41, "dough", 1), "空货架不能预留")
	check(sim.production.reservations.is_empty(), "失败的预留不留记录")
	sim.run_seconds(20.0)
	var stock := sim.production.free_stock("dough")
	check(stock > 0, "线上真的供出了库存")
	check(sim.production.reserve(42, "dough", stock), "全部库存可以一次预留")
	check_eq(sim.production.free_stock("dough"), 0, "预留后别的订单看不到")
	check(not sim.production.reserve(43, "dough", 1), "同一份库存不能再预留")
	sim.production.release(42)
	check_eq(sim.production.free_stock("dough"), stock, "取消预留后恢复可用")


# 原料柜（决定⑮）：几个槽轮流出货，每种料走自己那一路；某一路下游满了就只出另一种。
func test_cabinet_rotates_slots_and_skips_a_full_branch() -> void:
	var cabinet := Cases.device("cabinet", StationDef.Mode.SUPPLY, {}, {"leaf": 1, "milk": 1}, 0.5)
	cabinet.output_capacity = 3
	var brew := Cases.device("brew", StationDef.Mode.AUTO, {"leaf": 1}, {"soup": 1}, 0.5)
	var mix := Cases.device("mix", StationDef.Mode.AUTO, {"milk": 1}, {"latte": 1}, 1000000.0)
	mix.input_capacity["milk"] = 2
	var sim := make_sim(Cases.config([cabinet, brew, mix]))
	Cases.lay(sim, {"c": "cabinet", "b": "brew", "m": "mix"}, [["c", "b", "leaf", 2], ["c", "m", "milk", 2], ["b", "shelf", "soup", 2]])
	sim.config.shelf_capacity = 1000
	sim.run_seconds(1.6)
	check_eq(Cases.produced(sim, "leaf"), 2, "前几份轮流出：茶叶")
	check_eq(Cases.produced(sim, "milk"), 1, "前几份轮流出：牛奶")
	sim.run_seconds(60.0)
	# 调奶那一路：入口 2 + 加工中 1，入口满后带上最多再排 2 件就算没空位
	var milk := Cases.produced(sim, "milk")
	check(milk <= 5, "牛奶那一路满了就不再出牛奶：%d" % milk)
	check(Cases.produced(sim, "leaf") > 50, "茶叶那一路照常出货，每 0.5 秒一份")
	check_eq(Cases.state(sim, "c").outputs.get("milk", 0), 0, "满了的那种料不会在出口越堆越多")
	_check_conservation(sim, ["leaf", "milk", "soup"])


# 两路都没需求时原料柜停着，计时器不会攒出一大批。
func test_cabinet_idles_without_demand() -> void:
	var cabinet := Cases.device("cabinet", StationDef.Mode.SUPPLY, {}, {"leaf": 1}, 0.5)
	var sim := make_sim(Cases.config([cabinet]))
	Cases.lay(sim, {"c": "cabinet"}, [])
	sim.run_seconds(30.0)
	check_eq(Cases.produced(sim, "leaf"), 0, "没有带子接着就不出货")
	check(Cases.state(sim, "c").supply_timer <= cabinet.supply_interval + 0.001, "计时器停在一份的时间上")


func _chain(bounded: bool = false) -> GameSim:
	var supply := Cases.device("supply", StationDef.Mode.SUPPLY, {}, {"flour": 1}, 0.2)
	var prep := Cases.device("prep", StationDef.Mode.AUTO, {"flour": 1}, {"dough": 1}, 0.2)
	if bounded:
		supply.output_capacity = 1
		prep.output_capacity = 1
		prep.input_capacity["flour"] = 1
	var cfg := Cases.config([supply, prep])
	cfg.shelf_capacity = 2 if bounded else 10000
	var sim := make_sim(cfg)
	Cases.lay(sim, {"supply": "supply", "prep": "prep"}, [["supply", "prep", "flour", 2], ["prep", "shelf", "dough", 2]])
	return sim


func _check_conservation(sim: GameSim, items: Array) -> void:
	var on_field := sim.production.count_items()
	for item in items:
		check_eq(on_field.get(item, 0), sim.diagnostics.expected_on_field(item), "物料守恒：" + item)
