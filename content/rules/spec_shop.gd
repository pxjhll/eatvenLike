class_name SpecShop
extends Resource
## 一家店的全部数据（§4）。规则层只读它，代码里不出现任何店铺、机器、菜品的名字。

@export var id: String = ""
@export var display_name: String = ""
@export var start_gold: int = 0
@export var random_seed: int = 0
@export var items: Array[SpecItem] = []
@export var dishes: Array[SpecDish] = []
@export var stations: Array[SpecStation] = []
@export var stages: Array[SpecStage] = []
@export var fulfillment: SpecFulfillment
@export var dispatch: SpecDispatch
@export var flyer: SpecFlyer
@export var seat_groups: Array[SpecSeatGroup] = []
@export var staff: SpecStaffRules
@export var connections: Array[SpecConnection] = []
## 订单附加选项（要手提袋之类）
@export var order_options: Array[SpecOrderOption] = []
@export var goals: SpecGoalRules
## 走位：站位、坐班位、可走区域（规则层寻路用）
@export var layout: SpecLayout
@export var guide: Array[SpecGuideStep] = []
## 这家店自带的奇遇（预留）
@export var events: Array[SpecEvent] = []
## 客流：每多开一个口味（第一个之外）客流 ×(1 + flavor_flow)；机器等级加客流 level_flow
@export var flavor_flow: float = 0.0
@export var level_flow: float = 0.0
## 美术场景、存档文件名
@export_file("*.tscn") var scene_path: String = ""
@export var background_music: AudioStream
@export var save_file: String = ""
## 人物大小按哪个锚点量
@export var scale_anchor: String = ""


func station(station_id: String) -> SpecStation:
	for s in stations:
		if s.id == station_id: return s
	return null


func dish(dish_id: String) -> SpecDish:
	for d in dishes:
		if d.id == dish_id: return d
	return null


func stage_of(station_id: String) -> int:
	for index in stages.size():
		if station_id in stages[index].stations: return index
	return -1


## 这一阶段在哪台机器上买：开机器的阶段是它的第一台机器，配方阶段是卖配方的那台
func sold_at(index: int) -> String:
	var stage := stages[index]
	return stage.stations[0] if not stage.stations.is_empty() else stage.recipe_at


## 配方阶段：在这台机器上卖、菜是 dish_id 的阶段序号；dish_id 留空 = 这台机器上的所有配方阶段
func recipe_stages(station_id: String) -> Array[int]:
	var out: Array[int] = []
	for index in stages.size():
		if stages[index].stations.is_empty() and stages[index].recipe_at == station_id: out.append(index)
	return out


## 这道菜要靠哪个配方阶段才上菜单（-1 = 不靠配方）
func recipe_stage_of(dish_id: String) -> int:
	for index in stages.size():
		if stages[index].stations.is_empty() and not stages[index].recipe_at.is_empty() and stages[index].dish == dish_id: return index
	return -1
