extends "res://tests/test_case.gd"

const Recorder := preload("res://presentation/shop/shop_recorder.gd")
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const TestSession := preload("res://tests/shop_test_session.gd")
const Profile := preload("res://game/app/profile.gd")
var paths: Array[String] = []

func path(label: String) -> String:
	var result := "user://scene-session-%d-%d-%s" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	paths.append(result)
	return result

func cleanup() -> void:
	for file in paths:
		if FileAccess.file_exists(file): DirAccess.remove_absolute(file)

func test_disabled_recorder_cannot_read_clear_or_export() -> void:
	var file_path := path("record.txt")
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string("private sentinel\n")
	file.close()
	var recorder := Recorder.new()
	recorder.file_path = file_path
	recorder.enabled = false
	recorder.setup(ShopRules.new(TEA))
	check_eq(recorder.text(), "", "disabled recorder cannot read existing records")
	check_eq(recorder.line_count(), 0, "disabled recorder hides record count")
	recorder.clear()
	check_eq(FileAccess.get_file_as_string(file_path) if FileAccess.file_exists(file_path) else "", "private sentinel\n", "disabled clear preserves existing bytes")
	# Only exercise export after the read barrier exists, avoiding a desktop file manager in RED.
	if recorder.text().is_empty():
		check_eq(recorder.export_file(), "还没有录制内容", "disabled export does not export existing records")

func test_scene_and_services_expose_explicit_configuration() -> void:
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	check(scene.get_property_list().any(func(p: Dictionary) -> bool: return p.name == "session"), "scene exposes explicit session")
	check(scene.save_now(false) != OK, "scene without a session rejects save before startup")
	scene.free()
	var tuning: Control = load("res://presentation/shop/shop_tuning.gd").new()
	check(tuning.get_property_list().any(func(p: Dictionary) -> bool: return p.name == "file_path"), "tuning accepts isolated destination")
	tuning.free()
	var guide: Control = load("res://presentation/shop/guide_player.gd").new()
	check(guide.has_method("restart"), "guide offers one transient reset")
	guide.free()

func test_factory_defaults_and_reused_namespace_preserve_profile_intent() -> void:
	var prefix := path("factory")
	for suffix in ["-profile.json", "-shop.json", "-tuning.cfg", "-playlog.txt"]: paths.append(prefix + suffix)
	var session := TestSession.make(TEA, prefix)
	check_eq(session.profile.shop, "tea", "new isolated profile selects requested shop")
	check(not session.guide_enabled and not session.recording_enabled and not session.persist_tuning, "test services default off independently")
	check(session.tuning_path != "user://tuning.cfg" and session.recording_path != "user://playlog.txt", "destinations are isolated even when disabled")
	check_eq(session.profile.select_shop("pancake"), OK, "fixture changes its own campaign intent")
	var reopened := TestSession.make(TEA, prefix)
	check_eq(reopened.profile.shop, "pancake", "namespace reuse never resets persisted intent")
	var supplied := TestSession.make(TEA, prefix, ShopRules.new(TEA), session.store, session.profile)
	check(supplied.profile == session.profile and supplied.store == session.store, "factory retains supplied dependencies")
	check_eq(supplied.profile.shop, "pancake", "supplied profile is not repaired or rewritten")
