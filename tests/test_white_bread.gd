extends "res://tests/test_case.gd"
## 白面包这条线的冒烟回归。


func test_line_sells_white_bread() -> void:
	var sim := make_sim()
	sim.run_seconds(120.0)
	check(sim.diagnostics.sold > 10, "两分钟应卖出十几份白面包，实际 %d" % sim.diagnostics.sold)
	check_eq(sim.economy.revenue, sim.diagnostics.sold * 10, "营业额 = 份数 × 售价")
	check(sim.diagnostics.produced_by_slot.get("oven", 0) > 0, "烤炉有产出")


func test_shop_completes_after_tasks() -> void:
	var sim := make_sim()
	var fired := [0]
	sim.shop_completed.connect(func() -> void: fired[0] += 1)
	sim.run_seconds(600.0)
	check(sim.progress.completed, "卖够 30 份白面包后店铺完成")
	check_eq(fired[0], 1, "shop_completed 只发一次")
	check_eq(SwitchShopCommand.new().validate(sim), "", "完成后可以换店")


func test_parallel_oven_raises_output() -> void:
	var cfg := bakery_copy()
	cfg.starting_gold = 500
	var plain := make_sim(cfg)
	var doubled := make_sim(cfg)
	doubled.submit(ActivateParallelCommand.new("oven_b"))
	plain.run_seconds(300.0)
	doubled.run_seconds(300.0)
	var a: int = plain.diagnostics.item_flow.bread.produced
	var b: int = doubled.diagnostics.item_flow.bread.produced
	check(b > a, "并联烤炉后面包产量变多（%d → %d）" % [a, b])


func test_splitter_alternates() -> void:
	# 两台烤炉改成不需要人、几乎不堵的自动机，分流应严格轮流
	var cfg := _fast_ovens(0.1, 0.1)
	var sim := make_sim(cfg)
	sim.submit(ActivateParallelCommand.new("oven_b"))
	sim.run_seconds(300.0)
	var a: int = sim.diagnostics.produced_by_slot.get("oven", 0)
	var b: int = sim.diagnostics.produced_by_slot.get("oven_b", 0)
	check(a > 20, "烤炉有产出（%d）" % a)
	check(absi(a - b) <= 1, "面团台轮流送，两台烤炉产量相差不超过 1（%d / %d）" % [a, b])


func test_splitter_skips_blocked_lane() -> void:
	# 第二台烤炉极慢，它那一路堵住后面团全部送去第一台
	var cfg := _fast_ovens(0.1, 1000000.0)
	var sim := make_sim(cfg)
	sim.submit(ActivateParallelCommand.new("oven_b"))
	sim.run_seconds(100.0)
	var lane_before := _lane_b_dough(sim)
	var a_before: int = sim.diagnostics.produced_by_slot.get("oven", 0)
	sim.run_seconds(200.0)
	check_eq(_lane_b_dough(sim), lane_before, "堵住的一路不再收面团")
	check(sim.diagnostics.produced_by_slot.get("oven", 0) - a_before > 40, "面团改送第一台，它继续出货")


func _lane_b_dough(sim: GameSim) -> int:
	var n := 0
	for st in sim.production.stations:
		if st.slot_id == "oven_b":
			n += int(st.inputs.get("dough", 0))
	for seg in sim.production.segments:
		if seg.id == "dough_to_oven_b":
			n += seg.items.size()
	return n


func _fast_ovens(cycle_a: float, cycle_b: float) -> ShopConfig:
	var cfg := bakery_copy()
	cfg.starting_gold = 500
	cfg.shelf_capacity = 100000  # 不让备料架反堵回烤炉
	for slot in cfg.slots:
		if slot.id == "oven" or slot.id == "oven_b":
			# 两个机位共用一个 Def，这里给第二台换一份独立的副本
			slot.station = slot.station.duplicate_deep()
			slot.station.mode = StationDef.Mode.AUTO
			slot.station.cycle_seconds = cycle_a if slot.id == "oven" else cycle_b
	return cfg
