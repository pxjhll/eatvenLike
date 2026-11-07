class_name SpecItem
extends Resource
## 物品：原料、中间品、成品（§3.1）。

@export var id: String = ""
@export var display_name: String = ""
@export var icon: Texture2D
## 画在场景里用哪张图（art/reference/<art>.png）、染什么色
@export var art: String = ""
@export var tint: Color = Color.WHITE
