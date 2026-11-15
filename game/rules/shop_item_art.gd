extends RefCounted
## One resolver for carried goods, table items and order/UI icons.
const PLACEHOLDER := "res://art/ui/icons/tag.svg"

static func find_item(shop: SpecShop, id: String) -> SpecItem:
	var dish := shop.dish(id)
	var key := dish.item if dish != null and not dish.item.is_empty() else id
	for item in shop.items:
		if item.id == key: return item
	return null

static func appearance(shop: SpecShop, id: String) -> Dictionary:
	var item := find_item(shop, id)
	var look := {"art": "", "tint": Color.WHITE}
	if item != null:
		look = {"art": item.art, "tint": item.tint, "texture": item.icon}
	look.texture = texture_from_look(look)
	return look

static func texture_from_look(look: Dictionary) -> Texture2D:
	var art := String(look.get("art", ""))
	var path := "res://art/reference/%s.png" % art
	if not art.is_empty() and ResourceLoader.exists(path): return load(path)
	var texture: Texture2D = look.get("texture", null)
	return texture if texture != null else load(PLACEHOLDER)

static func icon(shop: SpecShop, id: String) -> Texture2D:
	var item := find_item(shop, id)
	if item != null and item.icon != null: return item.icon
	var path := "res://art/ui/drink_%s.png" % id
	if item != null and ResourceLoader.exists(path): return load(path)
	return appearance(shop, id).texture

static func legacy_icon(id: String) -> Texture2D:
	var path := "res://art/ui/drink_%s.png" % id
	return load(path if ResourceLoader.exists(path) else PLACEHOLDER)
