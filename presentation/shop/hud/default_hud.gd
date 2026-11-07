extends RefCounted
## 默认的 HUD 装配（规格 §6.2.1）：底部三个页签、各个面板页、顶栏下面的瓶颈提示和加成图标。
## 新玩法要加页签、面板页或小部件，另写一个组件再 register_* 进来，不用改 HUD 核心。

const StationPage := preload("res://presentation/shop/hud/station_page.gd")
const GoalsPage := preload("res://presentation/shop/hud/goals_page.gd")
const StaffPage := preload("res://presentation/shop/hud/staff_page.gd")
const MenuPage := preload("res://presentation/shop/hud/menu_page.gd")
const RestartPage := preload("res://presentation/shop/hud/restart_page.gd")
const CharactersPage := preload("res://presentation/shop/hud/characters_page.gd")
const HintButton := preload("res://presentation/shop/hud/hint_button.gd")
const BuffBar := preload("res://presentation/shop/hud/buff_bar.gd")

## [页签 id, 默认名字, 图标, 打开哪一页]；名字可以用店铺数据的 tab_<id> 覆盖
const TABS := [["shop", "店铺", "shop", "shop"], ["goals", "目标", "goals", "goals"], ["staff", "员工", "staff", "staff"]]


static func install(view: Node2D, hud: Control) -> void:
	var texts: ShopView = view.view
	for row in TABS:
		hud.register_tab(row[0], texts.text("tab_" + row[0], {}, row[1]), row[2], row[3])
	_page(view, hud, "station", StationPage.new(), {"title": "设备", "icon": "hat"})
	_page(view, hud, "goals", GoalsPage.new(), {"title": "目标", "icon": "goals"})
	_page(view, hud, "staff", StaffPage.new(), {"title": "员工", "icon": "staff", "big": true, "bottom": 78.0})
	_page(view, hud, "characters", CharactersPage.new(), {"title": "角色预览", "icon": "hat", "fraction": 0.85})
	_page(view, hud, "menu", MenuPage.new(), {"title": "菜单", "centered": true, "bare": true})
	_page(view, hud, "restart", RestartPage.new(), {"title": "重开店铺", "centered": true, "plaque": true, "bare": true, "no_close": true})
	var hint := HintButton.new()
	hint.setup(view, hud)
	hud.add_widget(hint)
	var buffs := BuffBar.new()
	buffs.setup(view, hud)
	hud.add_widget(buffs)


static func _page(view: Node2D, hud: Control, id: String, node: Control, options: Dictionary) -> void:
	options.title = view.view.text("page_" + id, {}, options.title)
	hud.register_page(id, node, options)
	node.setup(view, hud)
