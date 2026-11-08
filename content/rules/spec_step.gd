class_name SpecStep
extends Resource
## 工序链的一步（§3.1）：在哪台机器、做什么动作、几秒、消耗什么、产出什么。

@export var station: String = ""
## 动作外观 / 种类：take（接单）、fetch（拿原料）、pour、grill、crisp、top、pack、hand（递餐）、boil、mix、seal……
@export var action: String = ""
## 人工秒数（机器自己计时的部分写在机器参数里）
@export var seconds: float = 0.0
@export var consumes: Dictionary[String, int] = {}
@export var produces: Dictionary[String, int] = {}
## 面板 / 头顶显示的文字
@export var label: String = ""
## 这一步的秒数乘的系数（加料 = 料的份数）
@export var repeat: int = 1
## true = 这一步的秒数不受机器升级影响（同一台机器上的快动作，比如鏊子旁边打面糊）
@export var fixed: bool = false
## 手上的东西放进机器里做（比如面粉倒进鏊子打糊）：做这一步时员工手上不画东西
@export var into_machine: bool = false
## 手上的东西先放到台面上再做（比如在柜台上卷饼）：做这一步时东西画在台面上（场景里 Stations/<台子>/Put 点），做完再拿起来
@export var put_down: bool = false
