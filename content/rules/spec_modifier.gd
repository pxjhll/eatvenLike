class_name SpecModifier
extends Resource
## 加成栈里的一条（§3.13）：来源 + 作用对象 + 乘/加 + 数值 + 到期。

## upgrade / star / event / staff / permanent / city / tune
@export var source: String = ""
@export var source_id: String = ""
@export var effect: SpecEffect
## 持续秒数，0 = 一直有效
@export var duration: float = 0.0
