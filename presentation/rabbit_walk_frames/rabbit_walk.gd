extends Node2D
## Authored directional clips; partial customer sets use the nearest supplied view.

const CLIPS := ["walk_front", "walk_front_right", "walk_right", "walk_back_right", "walk_back", "walk_back_right", "walk_right", "walk_front_right"]
const LABELS := ["正面", "右前", "右侧", "右后", "背面", "左后", "左侧", "左前"]
const SUFFIXES := ["front", "front_right", "right", "back_right", "back", "back_right", "right", "front_right"]
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
var direction := 0
var action := "walk"


func _ready() -> void:
	sprite.play(_clip())
	_sync_flip()


func set_direction(value: int) -> void:
	var phase := get_phase()
	var playing := sprite.is_playing()
	direction = posmod(value, 8)
	sprite.animation = _clip()
	_sync_flip()
	sprite.play()
	seek_phase(phase)
	if not playing:
		sprite.pause()


func set_action(value: String) -> bool:
	if not has_action(value):
		return false
	var phase := get_phase()
	var playing := sprite.is_playing()
	action = value
	sprite.play(_clip())
	_sync_flip()
	seek_phase(phase)
	if not playing:
		sprite.pause()
	return true


func _sync_flip() -> void:
	var source_mirrored: Dictionary = sprite.sprite_frames.get_meta("source_mirrored", {})
	sprite.flip_h = (direction > 4) != bool(source_mirrored.get(str(sprite.animation), false))


func _clip() -> String:
	var name := action + "_" + str(SUFFIXES[direction])
	if sprite.sprite_frames.has_animation(name): return name
	if sprite.sprite_frames.has_animation(action): return action
	# Compare only the authored right-side views, mirroring for left-facing actors.
	var canonical := mini(direction, 8 - direction)
	var best := ""
	var distance := 9
	for index in 5:
		var candidate := action + "_" + str(SUFFIXES[index])
		if sprite.sprite_frames.has_animation(candidate) and absi(index - canonical) < distance:
			best = candidate
			distance = absi(index - canonical)
	return best


func has_action(value: String) -> bool:
	for clip: String in sprite.sprite_frames.get_animation_names():
		if clip == value or clip.begins_with(value + "_"): return true
	return false


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
