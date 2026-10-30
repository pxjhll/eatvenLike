extends Node2D
## Five exact frame clips, eight facing directions, no skeletal dependency.

const CLIPS := ["walk_front", "walk_front_right", "walk_right", "walk_back_right", "walk_back", "walk_back_right", "walk_right", "walk_front_right"]
const LABELS := ["正面", "右前", "右侧", "右后", "背面", "左后", "左侧", "左前"]
const SUFFIXES := ["front", "front_right", "right", "back_right", "back", "back_right", "right", "front_right"]
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var direction := 0
var action := "walk"


func _ready() -> void:
	sprite.play(_clip())


func set_direction(value: int) -> void:
	var phase := get_phase()
	var playing := sprite.is_playing()
	direction = posmod(value, 8)
	sprite.animation = _clip()
	sprite.flip_h = direction > 4
	sprite.play()
	seek_phase(phase)
	if not playing:
		sprite.pause()


func set_action(value: String) -> bool:
	var frames := sprite.sprite_frames
	if not frames.has_animation(value) and not frames.has_animation(value + "_front"):
		return false
	var phase := get_phase()
	var playing := sprite.is_playing()
	action = value
	sprite.play(_clip())
	seek_phase(phase)
	if not playing:
		sprite.pause()
	return true


func _clip() -> String:
	var name := action + "_" + str(SUFFIXES[direction])
	return name if sprite.sprite_frames.has_animation(name) else action


func pause() -> void:
	sprite.pause()


func play() -> void:
	sprite.play()


func set_speed(value: float) -> void:
	sprite.speed_scale = clampf(value, 0.1, 4.0)


func get_cycle_seconds() -> float:
	var total := 0.0
	var frames := sprite.sprite_frames
	for index in frames.get_frame_count(sprite.animation):
		total += frames.get_frame_duration(sprite.animation, index)
	return total / frames.get_animation_speed(sprite.animation)


func get_phase() -> float:
	var frames := sprite.sprite_frames
	var total := 0.0
	var elapsed := 0.0
	for index in frames.get_frame_count(sprite.animation):
		var duration := frames.get_frame_duration(sprite.animation, index)
		total += duration
		if index < sprite.frame:
			elapsed += duration
		elif index == sprite.frame:
			elapsed += duration * sprite.frame_progress
	return elapsed / total if total > 0 else 0.0


func seek_phase(value: float) -> void:
	var phase := clampf(value, 0.0, 0.999999)
	var frames := sprite.sprite_frames
	var target := phase * get_cycle_seconds() * frames.get_animation_speed(sprite.animation)
	for index in frames.get_frame_count(sprite.animation):
		var duration := frames.get_frame_duration(sprite.animation, index)
		if target < duration:
			sprite.set_frame_and_progress(index, target / duration)
			return
		target -= duration
