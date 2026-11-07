class_name SpecGuideStep
extends Resource
## 引导一步（§6.3）。触发 = 事件总线上的某个广播 + 条件；说话角色默认三花猫店长。

@export var id: String = ""
## 触发：事件名（start / unlocked / sale / stage / staff_short …）
@export var trigger: String = ""
## 触发条件参数，如 {"station": "soy_milk"}
@export var condition: Dictionary = {}
## 指向：机器 id 或界面按钮 id（ui:hire）
@export var point_at: String = ""
@export_multiline var text: String = ""
@export var pause: bool = false
@export var speaker: String = "manager"
## 卡片型（欢迎卡、完成卡）还是手指提示
@export var style: String = "hint"
