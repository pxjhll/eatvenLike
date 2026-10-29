extends "res://tests/test_case.gd"
## UI 字体是按仓库文字裁剪的子集（art_src/graybox/subset_font.py）。加了新文案没重新裁剪，界面就会出方框。

const FONT := "res://art/ui/graybox_font.ttf"


func test_content_names_have_glyphs() -> void:
	var font: FontFile = load(FONT)
	var catalog: GameCatalog = load(CATALOG)
	var names := []
	for staff in catalog.staff:
		names.append(staff.display_name)
	for shop in catalog.shops:
		names.append(shop.display_name)
		for item in shop.items:
			names.append(item.display_name)
		for dish in shop.dishes:
			names.append(dish.display_name)
		for slot in shop.slots:
			names.append(slot.station.display_name)
		for stage in shop.progression.stages:
			for task in stage.tasks:
				names.append(task.display_name)
	for name in names:
		check(_missing(font, name).is_empty(), "「%s」缺字：%s" % [name, _missing(font, name)])


func test_script_strings_have_glyphs() -> void:
	# 表现层文案和命令的拒绝理由都会显示在界面上
	var font: FontFile = load(FONT)
	var literal := RegEx.create_from_string("\"([^\"\\\\]*)\"")
	for folder in ["res://presentation", "res://game"]:
		for path in _scripts(folder):
			var source := FileAccess.get_file_as_string(path)
			for line in source.split("\n"):
				if line.strip_edges().begins_with("#"):
					continue
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
