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
