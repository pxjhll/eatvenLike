class_name StaffDef
extends Resource
## 员工（动物）定义。运行时只读。

@export var id: String = ""
@export var display_name: String = ""
## 工作区 -> 效率倍率，没写的工作区按 1.0
@export var zone_efficiency: Dictionary[String, float] = {}
