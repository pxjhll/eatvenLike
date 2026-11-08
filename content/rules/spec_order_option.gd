class_name SpecOrderOption
extends Resource
## 订单附加选项（§3.2）：机器开了以后，一部分客人的订单多一道工序、多付一点钱（比如要手提袋）。
## 目前一人跟单的店（handoff = single）支持：这道工序插在递餐前，由跟单的员工顺手做。
@export var id: String = ""
@export var display_name: String = ""
## 哪台机器开了才有这个选项；这道工序在哪台机器做
@export var station: String = ""
## 多少比例的客人要（0–1）
@export var share: float = 0.0
## 主菜售价乘多少（附加菜不乘）
@export var price_mult: float = 1.0
## 多出来的那道工序（station 留空 = 用上面的机器）
@export var step: SpecStep
