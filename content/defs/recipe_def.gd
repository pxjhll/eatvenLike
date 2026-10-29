class_name RecipeDef
extends Resource
## 配方：输入物品 → 输出物品。运行时只读。外购箱的配方只有输出。

@export var id: String = ""
## item_id -> 数量
@export var inputs: Dictionary[String, int] = {}
## item_id -> 数量
@export var outputs: Dictionary[String, int] = {}
