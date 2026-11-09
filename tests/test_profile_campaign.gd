extends "res://tests/test_case.gd"

const Profile := preload("res://game/app/profile.gd")
const NOODLE: SpecCampaign = preload("res://tests/fixtures/noodle/campaign.tres")

var paths: Array[String] = []


func _path(label: String) -> String:
	var result := "user://profile-campaign-%d-%d-%s.json" % [OS.get_process_id(), Time.get_ticks_usec(), label]
	paths.append(result)
	return result


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func cleanup() -> void:
	for path in paths:
		for suffix in ["", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)


func _profile(path: String, campaign: SpecCampaign) -> RefCounted:
	return Profile.new(path, campaign)


func _entry(id: String, path: String = "") -> SpecCampaignShop:
	var entry := SpecCampaignShop.new()
	entry.id = id
	entry.shop_path = path
	return entry


func _sequence() -> SpecCampaign:
	var campaign := SpecCampaign.new()
	var first := SpecCity.new()
	first.id = "test_first"
	first.shops.assign([
		_entry("planned_before"),
		_entry("noodle", "res://tests/fixtures/noodle/shop.tres"),
		_entry("planned_between"),
	])
	var second := SpecCity.new()
	second.id = "test_second"
	second.shops.assign([
		_entry("tea", "res://content/shops/tea/shop.tres"),
		_entry("planned_after"),
	])
	campaign.cities.assign([first, second])
	return campaign


func test_fixture_profile_select_reload_reset_and_default_separation() -> void:
	var path := _path("durable")
	var profile := _profile(path, NOODLE)
	check_eq(profile.load_error, OK, "fixture profile starts normally")
	check_eq(profile.campaign, NOODLE, "profile exposes the injected campaign")
	check_eq(profile.available_shops(), ["noodle"], "only fixture shop is selectable")
	check_eq(profile.shop, "noodle", "fixture initial shop comes from its campaign")
	check_eq(profile.city, "test_noodle", "fixture initial city comes from its campaign")
	check_eq(profile.select_shop("noodle"), OK, "fixture shop can be selected and committed")
	var reloaded := _profile(path, NOODLE)
	check_eq(reloaded.to_dict(), profile.to_dict(), "real profile reload preserves durable fixture state")
	check_eq(reloaded.finish_shop({"shop": "noodle", "seconds": 12.5}), OK, "fixture completion commits")
	check_eq(_profile(path, NOODLE).records, [{"shop": "noodle", "seconds": 12.5}], "fixture record is durable")
	check_eq(reloaded.reset_all(), OK, "reset uses fixture defaults")
	check_eq(_profile(path, NOODLE).records, [], "fixture reset is durable")
	check_eq(_profile(path, NOODLE).shop, "noodle", "fixture reset keeps fixture shop")
	check_eq(_profile(path, NOODLE).city, "test_noodle", "fixture reset keeps fixture city")
	check_eq(Profile.shops(), ["pancake", "tea"], "production shop list stays unchanged")
	var default_profile := Profile.new(_path("production"))
	check_eq(default_profile.available_shops(), ["pancake", "tea"], "default profile retains production campaign")
	check_eq(default_profile.shop, "pancake", "default profile starts at production first shop")
	check_eq(default_profile.city, "north", "default profile starts at production first city")
	check_eq(default_profile.select_shop("noodle"), ERR_INVALID_PARAMETER, "fixture shop stays outside production")


func test_instance_sequence_filters_unimplemented_entries_and_commits_next_shop() -> void:
	var campaign := _sequence()
	var profile := _profile(_path("sequence"), campaign)
	check_eq(profile.available_shops(), ["noodle", "tea"], "unimplemented entries do not appear in selectable list")
	check_eq(profile.next_shop("noodle"), "tea", "next shop skips planned entries across cities")
	check_eq(profile.next_shop("planned_before"), "noodle", "implemented successor follows planned current entry")
	check_eq(profile.next_shop("tea"), "", "planned trailing entries cannot become next shop")
	check_eq(profile.next_shop("unknown"), "", "unknown shop cannot advance")
	var before: Dictionary = profile.to_dict()
	check_eq(profile.select_shop("planned_between"), ERR_INVALID_PARAMETER, "unimplemented entry is rejected")
	check_eq(profile.to_dict(), before, "rejected selection preserves profile memory")
	check(not FileAccess.file_exists(profile.path), "rejected selection creates no profile")
	check_eq(profile.finish_shop({"shop": "noodle"}), OK, "finish follows custom sequence")
	var reloaded := _profile(profile.path, campaign)
	check_eq(reloaded.shop, "tea", "custom next shop is durable")
	check(reloaded.fresh_shop, "custom next shop retains fresh marker")
	check_eq(reloaded.acknowledge_fresh_shop(), OK, "custom fresh marker can commit")
	check(not _profile(profile.path, campaign).fresh_shop, "custom acknowledgement is durable")
	check_eq(reloaded.reset_all(), OK, "custom sequence resets successfully")
	check_eq(_profile(profile.path, campaign).shop, "noodle", "reset skips initial unimplemented entry")


func test_invalid_campaigns_fail_before_read_or_write() -> void:
	var empty_city := SpecCity.new()
	empty_city.id = "empty"
	var no_shops := SpecCampaign.new()
	no_shops.cities.assign([empty_city])
	var null_city := SpecCampaign.new()
	null_city.cities.assign([null])
	var null_entry := _sequence()
	null_entry.cities[0].shops.append(null)
	var empty_id := _sequence()
	empty_id.cities[0].shops[1].id = ""
	var duplicate_id := _sequence()
	duplicate_id.cities[1].shops[0].id = "noodle"
	var unimplemented := SpecCampaign.new()
	var planned_city := SpecCity.new()
	planned_city.id = "planned"
	planned_city.shops.assign([_entry("planned")])
	unimplemented.cities.assign([planned_city])
	for campaign in [null, SpecCampaign.new(), no_shops, null_city, null_entry, empty_id, duplicate_id, unimplemented]:
		for existing in [false, true]:
			var path := _path("invalid")
			var original := '{"version":99,"shop":"noodle"}'
			if existing: _write(path, original)
			var profile := _profile(path, campaign)
			check_eq(profile.load_error, ERR_INVALID_DATA, "invalid campaign fails before reading future profile")
			check(not profile.last_error.is_empty(), "invalid campaign explains its failure")
			check_eq(profile.available_shops(), [], "invalid campaign exposes no playable shop")
			check_eq(profile.next_shop("noodle"), "", "invalid campaign cannot navigate")
			var before: Dictionary = profile.to_dict()
			for operation in ["save", "reset_all", "acknowledge_fresh_shop", "load_profile", "check_writable"]:
				check_eq(profile.call(operation), ERR_INVALID_DATA, "invalid campaign blocks " + operation)
			check(profile.select_shop("noodle") != OK, "invalid campaign blocks select")
			check(profile.finish_shop({"shop": "noodle"}) != OK, "invalid campaign blocks finish")
			check_eq(profile.to_dict(), before, "invalid campaign operations preserve memory")
			if existing:
				check_eq(FileAccess.get_file_as_string(path), original, "invalid campaign preserves original bytes")
			else:
				check(not FileAccess.file_exists(path), "invalid campaign creates no file")


func test_custom_campaign_guards_future_corrupt_and_external_replacements() -> void:
	for text in ['{"version":99,"shop":"noodle"}', '{broken', '{"version":1,"shop":"pancake"}', '{"version":1,"records":{}}']:
		for replacement in [false, true]:
			var path := _path("guard")
			var profile: RefCounted
			if replacement:
				profile = _profile(path, NOODLE)
				check_eq(profile.save(), OK, "custom profile saved before external replacement")
				_write(path, text)
			else:
				_write(path, text)
				profile = _profile(path, NOODLE)
			var before: Dictionary = profile.to_dict()
			check(profile.save() != OK, "custom invalid file blocks save")
			check(profile.reset_all() != OK, "custom invalid file blocks reset")
			check(profile.select_shop("noodle") != OK, "custom invalid file blocks selection")
			check(profile.finish_shop({"shop": "noodle"}) != OK, "custom invalid file blocks completion")
			check(profile.acknowledge_fresh_shop() != OK, "custom invalid file blocks acknowledgement")
			check_eq(profile.to_dict(), before, "custom write guards preserve memory")
			check_eq(FileAccess.get_file_as_string(path), text, "custom write guards preserve original bytes")
	var legacy_path := _path("legacy")
	_write(legacy_path, '{"shop":"noodle","trophies":7,"records":[{"seconds":1.25}]}')
	var legacy := _profile(legacy_path, NOODLE)
	check_eq(legacy.load_error, OK, "custom campaign accepts legacy v1 profile")
	check_eq(legacy.save(), OK, "custom legacy profile commits current representation")
	check_eq(_profile(legacy_path, NOODLE).trophies, 7, "custom legacy trophies stay durable")
