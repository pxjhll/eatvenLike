extends SceneTree

func _initialize() -> void:
	var suite = preload("res://tests/test_zz_pace_tmp.gd").new()
	suite.test_pace()
	quit(0)
