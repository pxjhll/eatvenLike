extends "res://tests/test_case.gd"
## 后厨人工：一人一岗（决定⑫），只做自己工位上的活，效率倍率只乘一次。

const Cases := preload("res://tests/fixtures/production_cases.gd")


# 没人站在工位上，人工设备不动；派人上岗后才开始做。
func test_manual_waits_for_staff_then_runs_after_assignment() -> void:
	var sim := _make(1.0, false)
	Cases.state(sim, "prep").inputs["flour"] = 4
	sim.run_seconds(6.0)
	check_eq(Cases.produced(sim, "dough"), 0, "没人上岗就做不出来")
	check_eq(Cases.state(sim, "prep").inputs["flour"], 4, "等人时不消耗原料")
	sim.submit(AssignStaffCommand.new("operator", "prep"))
	sim.run_seconds(10.0)
	check(Cases.produced(sim, "dough") > 0, "上岗后开始做")


# 效率倍率只乘一次。
func test_manual_uses_staff_efficiency_once() -> void:
	var normal := _make(1.0)
	var fast := _make(2.0)
	for sim in [normal, fast]:
		Cases.state(sim, "prep").inputs["flour"] = 4
		sim.run_seconds(4.0)
	check_eq(Cases.produced(normal, "dough"), 1, "1 倍速 4 秒做完一份 4 秒的活")
	check_eq(Cases.produced(fast, "dough"), 2, "2 倍速 4 秒做完两份")


# 做到一半调岗：手上这一份照常做完，之后只接新工位的活，不再回来。
func test_reassignment_finishes_the_current_step_then_stops() -> void:
	var sim := _make(1.0)
	var prep := Cases.state(sim, "prep")
	prep.inputs["flour"] = 4
	sim.run_seconds(1.0)
	var worker := sim.workforce.staff[0]
	check(worker.request_id != -1, "人工步骤正在做")
	var request_id := worker.request_id
	sim.submit(AssignStaffCommand.new("operator", "other"))
	sim.run_seconds(2.0)
	check_eq(worker.post, "other", "岗位立即换到新工位（后厨不走路）")
	check_eq(worker.request_id, request_id, "手上这一份还在做")
	check_eq(Cases.produced(sim, "dough"), 0, "不会提前做完")
	sim.run_seconds(1.0)
	check_eq(Cases.produced(sim, "dough"), 1, "4 秒时做完原来那一份")
	sim.run_seconds(8.0)
	check_eq(Cases.produced(sim, "dough"), 1, "之后不再接原工位的活")
	check_eq(prep.inputs["flour"], 3, "只消耗了一份原料")


# 一台设备只能站一个人；不要员工的设备不能上岗。
func test_one_worker_per_kitchen_device() -> void:
	var sim := _make(1.0)
	sim.workforce.staff.append(StaffState.create("helper", "operator"))
	check_eq(AssignStaffCommand.new("helper", "prep").validate(sim), "这个工位满了", "人工设备一台一人")
	check_eq(AssignStaffCommand.new("helper", "auto").validate(sim), "这个工位不要员工", "全自动设备不配人")
	check_eq(AssignStaffCommand.new("helper", "other").validate(sim), "", "空着的人工设备可以上岗")


func _make(efficiency: float, posted: bool = true) -> GameSim:
	var prep := Cases.device("prep_def", StationDef.Mode.MANUAL, {"flour": 1}, {"dough": 1}, 4.0)
	var auto := Cases.device("auto_def", StationDef.Mode.AUTO, {"dough": 1}, {"bread": 1}, 4.0)
	var sim := GameSim.new()
	sim.setup(Cases.config([prep, auto]), [Cases.worker(efficiency)])
	_nodes.append(sim)
	Cases.lay(sim, {"prep": "prep_def", "other": "prep_def", "auto": "auto_def"}, [])
	if posted:
		sim.workforce.assign_post("operator", "prep", "kitchen")
	return sim
