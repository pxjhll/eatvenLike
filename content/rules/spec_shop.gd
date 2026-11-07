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
