class_name SpecConnection
extends Resource
## 连接（§3.7）：可购买的传送带段。

@export var id: String = ""
@export var display_name: String = ""
@export var from: String = ""
@export var to: String = ""
@export var cost: int = 0
@export var stage: int = 0
## 每份在带上走多少秒；每隔多少秒往带上放一份
@export var seconds: float = 3.0
@export var interval: float = 1.5
## 这家店现在是否开放购买
@export var enabled: bool = true
