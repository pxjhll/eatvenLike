extends RefCounted
## 无插件的最小断言基类。每个 test_ 开头的方法是一个用例。

const TEA := "res://content/tea/tea.tres"
const CATALOG := "res://content/catalog.tres"

var failures: PackedStringArray = []
var _nodes: Array[Node] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, var_to_str(expected), var_to_str(actual)])


## 用奶茶店配置建一个 GameSim。step 只给步长无关测试用。
func make_sim(config: ShopConfig = null, step: float = GameSim.STEP_SECONDS) -> GameSim:
	var sim := GameSim.new()
	sim.step_seconds = step
	sim.setup(config if config != null else load(TEA), roster())
	_nodes.append(sim)
	return sim


func roster() -> Array[StaffDef]:
	var catalog: GameCatalog = load(CATALOG)
	var out: Array[StaffDef] = []
	for d in catalog.staff:
		if d.id in catalog.starting_roster:
			out.append(d)
	return out


## 深拷贝一份奶茶店配置，测试里改它不影响磁盘上的 .tres
func tea_copy() -> ShopConfig:
	return load(TEA).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)


## 奶茶店副本：奶茶阶段一开局就开放、金币管够，用来直接测后厨
func kitchen_copy(gold: int = 2000) -> ShopConfig:
	var cfg := tea_copy()
	cfg.starting_gold = gold
	cfg.progression.stages[1].revenue_threshold = 0
	return cfg


func hire(sim: GameSim) -> String:
	var command := HireStaffCommand.new()
	sim.submit(command)
	sim.step()
	return command.staff_id


## 开场：点开柠檬水台和柜台，招一个人拖到柜台。返回服务员 id
func open_front(sim: GameSim) -> String:
	sim.submit(UnlockFrontSpotCommand.new("lemonade_stand"))
	sim.submit(UnlockFrontSpotCommand.new("counter"))
	sim.step()
	var server := hire(sim)
	sim.submit(AssignStaffCommand.new(server, "counter"))
	sim.step()
	return server


## 进布局模式 → 一键部署 → 确认，回到经营模式。返回 ConfirmLayout 新建的设备 id
func deploy(sim: GameSim) -> Array[String]:
	sim.submit(EnterLayoutCommand.new())
	sim.submit(AutoDeployCommand.new())
	var confirm := ConfirmLayoutCommand.new()
	sim.submit(confirm)
	sim.step()
	check_eq(sim.mode, GameSim.Mode.BUSINESS, "确认后回到经营模式")
	return confirm.added


## 这个设备定义在生效布局里的实例 id
func device_of(sim: GameSim, def_id: String) -> String:
	for d in sim.layout.devices:
		if d.def == def_id:
			return d.id
	return ""


## 开好前厅、按推荐位摆好后厨、招人上调奶台：一家能卖奶茶的店。返回 {"server", "cook"}
func running_tea(cfg: ShopConfig = null, step: float = GameSim.STEP_SECONDS) -> GameSim:
	var sim := make_sim(cfg if cfg != null else kitchen_copy(), step)
	open_front(sim)
	deploy(sim)
	var cook := hire(sim)
	sim.submit(AssignStaffCommand.new(cook, device_of(sim, "milk_station")))
	sim.step()
	return sim


func state_json(sim: GameSim) -> String:
	return JSON.stringify(sim.to_dict(), "", false, true)


func cleanup() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()
