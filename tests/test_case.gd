extends RefCounted
## 无插件的最小断言基类。每个 test_ 开头的方法是一个用例。

const BAKERY := "res://content/bakery/bakery.tres"
const CATALOG := "res://content/catalog.tres"

var failures: PackedStringArray = []
var _nodes: Array[Node] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s：期望 %s，实际 %s" % [message, var_to_str(expected), var_to_str(actual)])


## 用面包店配置建一个 GameSim。step 只给步长无关测试用。
func make_sim(config: ShopConfig = null, step: float = GameSim.STEP_SECONDS) -> GameSim:
	var sim := GameSim.new()
	sim.step_seconds = step
	sim.setup(config if config != null else load(BAKERY), roster())
	_nodes.append(sim)
	return sim


func roster() -> Array[StaffDef]:
	var catalog: GameCatalog = load(CATALOG)
	var out: Array[StaffDef] = []
	for d in catalog.staff:
		if d.id in catalog.starting_roster:
			out.append(d)
	return out


## 深拷贝一份面包店配置，测试里改它不影响磁盘上的 .tres
func bakery_copy() -> ShopConfig:
	return load(BAKERY).duplicate_deep(Resource.DEEP_DUPLICATE_ALL)


func state_json(sim: GameSim) -> String:
	return JSON.stringify(sim.to_dict(), "", false, true)


func cleanup() -> void:
	for n in _nodes:
		n.free()
	_nodes.clear()
