extends RefCounted
## Shared visual data. Only actions actually present in resources are advertised.

const STAFF_IDS := ["cat", "raccoon", "fox", "rabbit", "gray_cat", "bear"]
const CUSTOMER_IDS := ["squirrel", "dog", "sheep", "hamster"]
const IDS := STAFF_IDS + CUSTOMER_IDS
## 所有店共用的人物比例，用一只杯子的高度当尺子（照奶茶店：杯 52、员工 128、客人 110）。
## 新场景量出自己杯子的高度再乘这两个数，人物和物件的比例就和奶茶店一致。
const STAFF_PER_CUP := 128.0 / 52.0
const CUSTOMER_PER_CUP := 110.0 / 52.0
const NAMES := {"cat": "小猫", "raccoon": "浣熊", "fox": "狐狸", "rabbit": "小兔子", "gray_cat": "小灰猫", "bear": "小熊", "squirrel": "小松鼠", "dog": "小狗", "sheep": "小羊", "hamster": "仓鼠"}
const ACTION_NAMES := {"walk": "走路", "idle": "待机", "sit": "坐姿", "work": "操作", "carry": "搬运", "pose": "站姿"}
const RABBIT_FRAMES := preload("res://art/rabbit_work_actions/rabbit_work_actions_frames.tres")
const RABBIT_SCENE := preload("res://presentation/rabbit_walk_frames/rabbit_walk.tscn")
const GRAY_CAT_FRAMES := preload("res://art/gray_cat_work_actions/gray_cat_work_actions_frames.tres")
const GRAY_CAT_SCENE := preload("res://presentation/gray_cat_walk_frames/gray_cat_walk.tscn")
const FRAME_ASSETS := {"rabbit": RABBIT_FRAMES, "gray_cat": GRAY_CAT_FRAMES,
	"bear": preload("res://art/bear_actions/bear_actions_frames.tres"),
	"squirrel": preload("res://art/squirrel_actions/squirrel_actions_frames.tres"),
	"dog": preload("res://art/dog_actions/dog_actions_frames.tres"),
	"sheep": preload("res://art/sheep_actions/sheep_actions_frames.tres"),
	"hamster": preload("res://art/hamster_actions/hamster_actions_frames.tres")}
const FRAME_SCENES := {"rabbit": RABBIT_SCENE, "gray_cat": GRAY_CAT_SCENE,
	"bear": preload("res://presentation/characters/bear.tscn"),
	"squirrel": preload("res://presentation/characters/squirrel.tscn"),
	"dog": preload("res://presentation/characters/dog.tscn"),
	"sheep": preload("res://presentation/characters/sheep.tscn"),
	"hamster": preload("res://presentation/characters/hamster.tscn")}
const DIRECTION_SUFFIXES := ["_front_right", "_back_right", "_front", "_right", "_back"]


static func portrait(art: String) -> Texture2D:
	if art in FRAME_ASSETS:
		var frames: SpriteFrames = FRAME_ASSETS[art]
		return frames.get_frame_texture("walk_front" if frames.has_animation("walk_front") else "walk_right", 0)
	if art in IDS:
		return load("res://art/reference/" + art + ".png")
	return null


static func actions(art: String) -> Array:
	if art not in FRAME_ASSETS:
		return [{"id": "pose", "label": "站姿", "type": "static", "directional": false}] if art in IDS else []
	var frames: SpriteFrames = FRAME_ASSETS[art]
	var names: Array[String] = []
	for animation: String in frames.get_animation_names():
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
	# Keep walking selected on opening the existing preview.
	names.sort_custom(func(a: String, b: String) -> bool: return a == "walk" if a == "walk" or b == "walk" else a < b)
	for action in names:
		var views: Array[String] = []
		for suffix: String in DIRECTION_SUFFIXES:
			if frames.has_animation(action + suffix): views.append(suffix)
		var label: String = "组装" if art == "rabbit" and action == "work" else ACTION_NAMES.get(action, action)
		result.append({"id": action, "label": label, "type": "frames", "directional": not views.is_empty(), "view_count": views.size()})
	return result


static func frame_height(art: String) -> float:
	return 228.0 if art == "rabbit" else 222.0 if art == "hamster" else 240.0


static func walk_speed(art: String) -> float:
	return 88.0 if art == "bear" else 112.0 if art == "gray_cat" else 104.0


static func customer_art(id: int) -> String:
	return CUSTOMER_IDS[posmod(id - 1, CUSTOMER_IDS.size())]
