extends Node2D
## Fixed props use actor-local positions; hand tools use the actual bone transform.

const CUP := preload("res://art/reference/cream_tea.png")
const SPOON := preload("res://art/rabbit_walk/props/spoon.svg")
const CUP_CENTERS := [Vector2(0, -85), Vector2(62, -88), Vector2(67, -85), Vector2(58, -88), Vector2(0, -85), Vector2(-58, -88), Vector2(-67, -85), Vector2(-62, -88)]
var actor: Node2D
var prop_id := "none"
var sprite := Sprite2D.new()


func _ready() -> void:
	add_child(sprite)
	update_pose()


func set_prop(id: String) -> void:
	if id not in ["none", "cup", "spoon"]:
		return
	prop_id = id
	update_pose()


func update_pose() -> void:
	sprite.visible = prop_id != "none"
	if prop_id == "none" or actor.rig == null:
		return
	sprite.centered = false
	if prop_id == "cup":
		sprite.texture = CUP
		sprite.offset = -CUP.get_size() / 2.0
		sprite.transform = Transform2D(0, CUP_CENTERS[actor.direction])
		sprite.scale = Vector2.ONE * 100.0 / CUP.get_height()
		sprite.z_index = -1 if actor.direction in [3, 4, 5] else 8
	else:
		sprite.texture = SPOON
		sprite.offset = Vector2(-26, -104)
		var hand: Node2D = actor.get_hand_socket()
		sprite.transform = global_transform.affine_inverse() * hand.global_transform
		sprite.scale *= 84.0 / SPOON.get_height()
		# Draw the handle under the near palm, while preserving the bone's mirror.
		sprite.z_index = 8
