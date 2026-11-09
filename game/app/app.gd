extends Node
## The production assembly boundary. Autoload construction performs no file IO.

const Profile := preload("res://game/app/profile.gd")
const Session := preload("res://game/app/shop_session.gd")

var _profile: RefCounted
var profile: RefCounted:
	get:
		if _profile == null: _profile = Profile.new()
		return _profile
	set(value):
		_profile = value


func create_session() -> RefCounted:
	var session := Session.new(profile, ShopSave.new(Session.shop_for(profile)))
	session.guide_enabled = true
	session.persist_tuning = true
	session.recording_enabled = true
	session.tuning_path = Session.TUNING_PATH
	session.recording_path = Session.RECORDING_PATH
	return session
