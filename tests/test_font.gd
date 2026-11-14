extends "res://tests/test_case.gd"
## UI 字体是按仓库文字裁剪的子集（tools/subset_font.py）。加了新文案没重新裁剪，界面就会出方框。

const FONT := "res://art/ui/graybox_font.ttf"

func test_public_onboarding_and_global_employee_text_has_glyphs() -> void:
	var font: FontFile = load(FONT)
	var campaign: SpecCampaign = load("res://content/examples/campaign.tres")
	var names: Array = []
	for city in campaign.cities:
		names.append(city.display_name)
		for entry in city.shops:
			names.append(entry.display_name)
			var shop: SpecShop = load(entry.shop_path)
			names.append(shop.display_name)
			for kind in shop.staff.kinds: names.append_array([kind.display_name,kind.role,kind.description])
	for text in names: check(_missing(font,text).is_empty(),"onboarding text missing glyphs: "+_missing(font,text))

func test_third_shop_fixture_text_has_glyphs() -> void:
	var font: FontFile = load(FONT)
	var literal := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	for path in ["res://tests/fixtures/noodle/shop.tres", "res://tests/fixtures/noodle/shop_scene.tscn", "res://tests/fixtures/noodle/campaign.tres"]:
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("["): continue
			for match_ in literal.search_all(line):
				var text: String = match_.get_string(1)
				check(_missing(font, text).is_empty(), "%s missing glyphs: %s" % [path, _missing(font, text)])


func test_content_names_have_glyphs() -> void:
	var font: FontFile = load(FONT)
	var names: Array = preload("res://presentation/characters/character_library.gd").NAMES.values()
	var campaign: SpecCampaign = load("res://content/campaign/campaign.tres")
	for city in campaign.cities:
		for entry in city.shops:
			names.append(entry.display_name)
			if entry.shop_path.is_empty(): continue
			var shop: SpecShop = load(entry.shop_path)
			names.append(shop.display_name)
			for list in [shop.items, shop.dishes, shop.stations, shop.staff.kinds, shop.connections]:
				for thing in list: names.append(thing.display_name)
			for st in shop.stations:
				for m in st.materials: names.append(m.display_name)
				for t in st.tracks: names.append(t.display_name)
			for stage in shop.stages:
				for task in stage.tasks: names.append(task.display_name)
	for name in names:
		check(_missing(font, name).is_empty(), "「%s」缺字：%s" % [name, _missing(font, name)])


func test_script_strings_have_glyphs() -> void:
	# 表现层文案和命令的拒绝理由都会显示在界面上
	var default_font: FontFile = load(FONT)
	var literal := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	for folder in ["res://presentation", "res://game", "res://content/ui"]:
		for path in _scripts(folder):
			var font: FontFile = default_font
			var source := FileAccess.get_file_as_string(path)
			# Pancake labels are explicitly drawn with their own eight-glyph subset.
			var label_font: FontFile = null
			if source.contains('path="res://art/pancake/labels_font.otf"'):
				label_font = load("res://art/pancake/labels_font.otf")
			for line in source.split("\n"):
				# Editor-only group names/descriptions do not use the game's subset UI font.
				if line.strip_edges().begins_with("#") or line.strip_edges().begins_with("metadata/") or ".set_meta(" in line or line.begins_with("[node ") or "DisplayServer.window_set_title(" in line:
					continue
				font = label_font if label_font != null and line.begins_with("text = ") else default_font
				for m in literal.search_all(line):
					var missing := _missing(font, m.get_string(1))
					check(missing.is_empty(), "%s 的「%s」缺字：%s" % [path.get_file(), m.get_string(1), missing])


func _missing(font: FontFile, text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 32 and not font.has_char(c) and not char(c) in out:
			out += char(c)
	return out


func _scripts(folder: String) -> Array:
	var out := []
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			out.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		out.append_array(_scripts(folder.path_join(sub)))
	return out
