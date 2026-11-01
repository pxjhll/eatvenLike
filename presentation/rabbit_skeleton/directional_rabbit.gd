extends Node2D
## A thin selector around five authored native skeletal scenes.

const ATTACHMENT := preload("res://presentation/rabbit_skeleton/prop_attachment.gd")
const VIEW_KEYS := ["front", "front_right", "right", "back_right", "back", "back_right", "right", "front_right"]
const VIEW_NAMES := ["正面", "右前", "右侧", "右后", "背面", "左后", "左侧", "左前"]
const GRIP_OFFSETS := {"front":Vector2(-8,7), "front_right":Vector2(-15,3), "right":Vector2(-2,11), "back_right":Vector2(1,7), "back":Vector2(-12,3)}
const SCENES := {
	"front": "res://presentation/rabbit_skeleton/rabbit_front.tscn",
	"front_right": "res://presentation/rabbit_skeleton/rabbit_front_right.tscn",
	"right": "res://presentation/rabbit_skeleton/rabbit_right.tscn",
	"back_right": "res://presentation/rabbit_skeleton/rabbit_back_right.tscn",
	"back": "res://presentation/rabbit_skeleton/rabbit_back.tscn",
}
var direction := 2
var view_key := "right"
var action := "walk"
var phase_time := 0.0
var flexible := true
var rig: Node2D
var player: AnimationPlayer
var attachment: Node2D
var _rigs: Dictionary = {}


func _ready() -> void:
	attachment = ATTACHMENT.new()
	attachment.actor = self
	add_child(attachment)
	set_direction(direction)


func set_direction(index: int) -> void:
	var phase := phase_time / get_cycle_seconds() if player != null else 0.0
	direction = posmod(index, 8)
	view_key = VIEW_KEYS[direction]
	if rig != null:
		rig.visible = false
	if not _rigs.has(view_key):
		var created := (load(SCENES[view_key]) as PackedScene).instantiate()
		add_child(created)
		_rigs[view_key] = created
		for side: String in ["Near", "Far"]:
			var socket := Marker2D.new()
			socket.name = "Grip"
			socket.position = GRIP_OFFSETS[view_key] if side == "Near" else Vector2(6,7)
			# Point the example utensil outwards instead of into the large head.
			socket.rotation = 0.95 if view_key == "back_right" else -0.95
			created.get_node("Skeleton2D/Root/Body/Chest/Arm" + side + "/Arm" + side + "Tip").add_child(socket)
	rig = _rigs[view_key]
	rig.visible = true
	rig.scale = Vector2(-1, 1) if direction > 4 else Vector2.ONE
	player = rig.get_node("AnimationPlayer")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.callback_mode_discrete = AnimationMixer.ANIMATION_CALLBACK_MODE_DISCRETE_FORCE_CONTINUOUS
	phase_time = phase * get_cycle_seconds()
	set_action(action)


func set_action(value: String) -> void:
	if value not in ["walk", "idle"]:
		return
	action = value
	if player != null:
		player.play("walk" if action == "walk" else "RESET")
		player.pause()
		sample_pose(phase_time)


func set_flexible(value: bool) -> void:
	flexible = value
	sample_pose(phase_time)


func sample_pose(time: float) -> void:
	phase_time = clampf(time, 0, get_cycle_seconds())
	if player == null:
		return
	player.seek(phase_time if action == "walk" else 0.0, true)
	if not flexible:
		for side: String in ["Near", "Far"]:
			var ear: Bone2D = rig.get_node("Skeleton2D/Root/Body/Chest/Head/Ear" + side)
			ear.transform = ear.rest
			(ear.get_node("Middle") as Bone2D).rotation = 0.0
			(ear.get_node("Middle/Tip") as Bone2D).rotation = 0.0
	if attachment != null:
		attachment.update_pose()


func set_prop(id: String) -> void:
	if attachment != null:
		attachment.set_prop(id)


func get_hand_socket(side: String = "Near") -> Node2D:
	return rig.get_node("Skeleton2D/Root/Body/Chest/Arm" + side + "/Arm" + side + "Tip/Grip")


func get_cycle_seconds() -> float:
	return player.get_animation("walk").length if player != null else 1.0
