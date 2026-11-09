extends RefCounted
## Explicit isolated dependencies. Reusing a namespace reopens only that fixture.

const Profile := preload("res://game/app/profile.gd")

static func make(spec: SpecShop, namespace_: String, rules: ShopRules = null, store: ShopSave = null, profile: RefCounted = null, campaign: SpecCampaign = Profile.CAMPAIGN) -> RefCounted:
	assert(not namespace_.strip_edges().is_empty(), "Test session needs an isolated namespace_")
	var prefix := namespace_ if namespace_.begins_with("user://") or namespace_.is_absolute_path() else "user://session-tests/" + namespace_
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(prefix.get_base_dir()))
	if profile == null:
		var profile_path := prefix + "-profile.json"
		var existed := FileAccess.file_exists(profile_path)
		profile = Profile.new(profile_path, campaign)
		if not existed:
			var result: Error = profile.select_shop(spec.id)
			assert(result == OK, "Cannot initialize isolated profile")
	if store == null: store = ShopSave.new(spec, prefix + "-shop.json")
	var session: RefCounted = load("res://game/app/shop_session.gd").new(profile, store, rules)
	session.guide_enabled = false
	session.persist_tuning = false
	session.recording_enabled = false
	session.tuning_path = prefix + "-tuning.cfg"
	session.recording_path = prefix + "-playlog.txt"
	return session
