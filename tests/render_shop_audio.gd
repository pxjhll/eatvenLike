extends SceneTree
## Audio integration through the generic shop scene, including replacement of its event bus.

const SHOP := "res://presentation/shop/shop_play.tscn"
const FIRST: SpecShop = preload("res://content/shops/pancake/shop.tres")
const SECOND: SpecShop = preload("res://content/shops/tea/shop.tres")

var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)


func _open(spec: SpecShop) -> Node2D:
	var scene: Node2D = load(SHOP).instantiate()
	scene.rules = ShopRules.new(spec)
	root.add_child(scene)
	scene.set_process(false)
	return scene


func _run() -> void:
	create_timer(15.0).timeout.connect(func() -> void: quit(1))
	var audio := root.get_node_or_null("ShopAudio")
	_check(audio != null, "ShopAudio is registered")
	if audio == null:
		quit(1)
		return
	audio.music_enabled = true
	audio.effects_enabled = true
	var scene := _open(FIRST)
	var music := audio.get_node("Music") as AudioStreamPlayer
	var sale := audio.get_node("sale") as AudioStreamPlayer
	var tap := audio.get_node("tap") as AudioStreamPlayer
	var unlock := audio.get_node("unlock") as AudioStreamPlayer
	_check(not music.playing, "Headless starts silent")
	scene.ui.popups.push({"id": "audio_welcome", "title": "Test"})
	audio.set_process_input(true)
	var gesture := InputEventScreenTouch.new()
	gesture.pressed = false
	root.push_input(gesture)
	_check(not scene.ui.popups.has_card(), "First touch dismisses the opening popup")
	_check(tap.playing, "Opening popup produces a tap on the first gesture")
	_check(music.playing and music.stream == FIRST.get("background_music"), "First gesture starts the first shop's configured music")
	_check(music.stream is AudioStreamOggVorbis and music.stream.loop, "Configured music loops")
	var previous: RuleEvents = scene.rules.events
	previous.emit("sale")
	_check(sale.playing, "A sale reaches the audio service through RuleEvents")
	sale.stop()
	previous.emit("sale")
	_check(not sale.playing, "Repeated sale is throttled")
	scene.restart()
	_check(scene.rules.events != previous, "Restart replaces RuleEvents")
	previous.emit("sale")
	_check(not sale.playing, "Old rules bus is disconnected after restart")
	scene.rules.events.emit("sale")
	_check(sale.playing, "Restarted rules still trigger sale audio")
	scene.station_action("unlock", scene.shop.goals.opening_station)
	_check(unlock.playing, "Successful station action plays through the unlock event")
	unlock.stop()
	scene.station_action("unlock", scene.shop.goals.opening_station)
	_check(not unlock.playing, "Rejected station action is silent")

	scene.ui.menu_button.pressed.emit()
	_check(tap.playing and scene.ui.page == "menu", "HUD menu click plays a tap")
	var settings: Control = scene.ui.page_node("menu").get_node_or_null("AudioControls")
	_check(settings != null and settings.get_child_count() == 2, "Menu contains the two audio controls")
	tap.stop()
	scene.ui.popups.push({"id": "audio_test", "title": "Test"})
	scene.ui.popups.button(0).pressed.emit()
	_check(tap.playing and not scene.ui.popups.has_card(), "Popup button plays a tap once at its shared entry")
	previous = scene.rules.events
	scene.free()

	scene = _open(SECOND)
	_check(music.playing and music.stream == SECOND.get("background_music"), "Next shop selects its own configured music")
	previous.emit("sale")
	_check(not sale.playing, "Closed shop's event bus is disconnected")
	scene.rules.events.emit("sale")
	_check(sale.playing, "Next shop receives rule sounds")
	# Let the Dummy mixer process playback before stopping the scene.
	await create_timer(0.5).timeout
	scene.free()
	_check(not music.playing and not sale.playing, "Leaving the scene stops shop audio")
	await create_timer(0.5).timeout
	print("SHOP AUDIO: %d failures" % failures)
	quit(failures)
