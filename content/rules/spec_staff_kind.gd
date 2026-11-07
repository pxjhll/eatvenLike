class_name SpecStaffKind
extends Resource
## 一种员工（小动物）：基础属性表（§3.13）。实际值 = 基础值经加成栈。

@export var id: String = ""
@export var display_name: String = ""
## 属性表：walk（像素/秒）、work（手速倍率）、carry（一次搬几份），以后加 luck（幸运值）、熟练度、特长……
@export var stats: Dictionary[String, float] = {}
## 界面：类型（速度型）、一句介绍
@export var role: String = ""
@export var description: String = ""
