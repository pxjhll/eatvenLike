extends Node2D
## Draws the actual animated Bone2Ds; no substitute animation or fake diagram.

var skeleton: Skeleton2D


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if skeleton == null:
		return
	for index in skeleton.get_bone_count():
		var bone := skeleton.get_bone(index)
		var point := to_local(bone.global_position)
		var ear := "Ear" in str(bone.get_path())
		var tint := Color("c27e48") if ear else Color("327e71")
		if bone.get_parent() is Bone2D:
			var parent := to_local((bone.get_parent() as Bone2D).global_position)
			draw_line(parent, point, tint, 2.5, true)
		draw_circle(point, 4.1, Color("fffaf0"))
		draw_arc(point, 4.1, 0, TAU, 20, tint, 1.6, true)
