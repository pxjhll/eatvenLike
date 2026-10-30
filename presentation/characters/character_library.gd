extends RefCounted
## Shared visual data. Only actions actually present in resources are advertised.

const IDS := ["cat", "raccoon", "fox", "rabbit"]
const NAMES := {"cat": "小猫", "raccoon": "浣熊", "fox": "狐狸", "rabbit": "小兔子"}
const ACTION_NAMES := {"walk": "走路", "idle": "待机", "work": "操作", "carry": "搬运", "pose": "站姿"}
const RABBIT_FRAMES := preload("res://art/rabbit_walk_frames/rabbit_walk_frames.tres")
const RABBIT_SCENE := preload("res://presentation/rabbit_walk_frames/rabbit_walk.tscn")
const DIRECTION_SUFFIXES := ["_front_right", "_back_right", "_front", "_right", "_back"]


static func portrait(art: String) -> Texture2D:
	if art == "rabbit":
		return RABBIT_FRAMES.get_frame_texture("walk_front", 0)
	if art in IDS:
		return load("res://art/reference/" + art + ".png")
	return null


static func actions(art: String) -> Array:
	if art != "rabbit":
		return [{"id": "pose", "label": "站姿", "type": "static", "directional": false}] if art in IDS else []
	var names: Array[String] = []
	for animation: String in RABBIT_FRAMES.get_animation_names():
		var matched := false
		for suffix: String in DIRECTION_SUFFIXES:
			if animation.ends_with(suffix):
				var action := animation.trim_suffix(suffix)
				if action not in names:
					names.append(action)
				matched = true
				break
		if not matched and animation != "default" and animation not in names:
			names.append(animation)
	var result: Array = []
	for action in names:
		result.append({"id": action, "label": ACTION_NAMES.get(action, action), "type": "frames", "directional": RABBIT_FRAMES.has_animation(action + "_front")})
	return result
