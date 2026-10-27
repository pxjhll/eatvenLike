extends RefCounted
## Asset identities belong here, never in simulation dispatch.

## 灰盒阶段借用旧面包店的图，正式美术到了再换
const MACHINE_PATHS := {
	"supply_cabinet": "mach_flour_bin", "tea_brewer": "mach_oven", "milk_station": "mach_dough_table",
	"topping_station": "mach_slicer", "lemonade_stand": "mach_rack", "counter": "mach_counter",
}
const ITEM_PATHS := {"tea_leaf": "item_flour", "milk": "item_dough", "tea_soup": "item_bread"}
const ICONS := ["coin", "goal", "belt", "oven", "slicer", "delete", "hire", "hint", "reset", "upgrade", "lock", "rotate", "close", "assign", "save", "debug"]
static var _textures := {}


static func texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]


static func machine(def: StationDef) -> Texture2D:
	var fallback := "mach_counter" if def.owner == StationDef.OwnerSystem.FRONT_HALL else "mach_dough_table"
	return texture("res://art/machine/" + MACHINE_PATHS.get(def.id, fallback) + ".png")


static func item(id: String) -> Texture2D:
	if id == "lemonade":
		return texture("res://art/item/tea_lemonade.svg")
	if id == "pearl_milk_tea" or id == "milk_tea":
		return texture("res://art/item/tea_milk_tea.svg")
	return texture("res://art/item/" + ITEM_PATHS.get(id, "item_bread") + ".png")


static func character(id: String) -> Texture2D:
	return texture("res://art/char/char_" + (id if id in ["rabbit", "bear", "cat"] else "customer") + ".png")


static func icon(id: String) -> AtlasTexture:
	var index := maxi(0, ICONS.find(id))
	var atlas := AtlasTexture.new()
	atlas.atlas = texture("res://art/ui/ui_icons.png")
	atlas.region = Rect2((index % 4) * 64, (index / 4) * 64, 64, 64)
	return atlas
