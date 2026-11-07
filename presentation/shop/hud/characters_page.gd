extends VBoxContainer
## 角色预览页（HUD 组件）：看着角色的时候店里停下（不改存档里的暂停）。

const CharacterPreview := preload("res://presentation/characters/character_preview.gd")

var preview: VBoxContainer
var freezes_shop := true


func setup(_view: Node2D, _hud: Control) -> void:
	preview = CharacterPreview.new()
	add_child(preview)


func select(id: String) -> void:
	preview.select_character(id)
