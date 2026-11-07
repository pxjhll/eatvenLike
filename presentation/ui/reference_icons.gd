extends RefCounted
## Shared artwork and warm outlined icons for the reference UI.
## Simple icons are standalone SVG files in art/ui/icons/ (imported at 4x), so an
## artist can redraw or replace any of them without touching code.

const CharacterLibrary = preload("res://presentation/characters/character_library.gd")
const ART := {
	"coin": "res://art/ui/coin.png",
	"shop": "res://art/reference/register.png",
	"shelf": "res://art/reference/rack.png",
	"seat": "res://art/reference/dining_chair_left.png",
	"boil": "res://art/reference/pearl_pot.png",
	"mix": "res://art/reference/brewer.png",
	"seal": "res://art/reference/sealer.png",
	"tea_leaf": "res://art/reference/tea_tin.png",
	"milk": "res://art/reference/milk_bottle.png",
	"lemonade": "res://art/ui/drink_lemonade.png",
	"bubble": "res://art/ui/bubble.png",
	"medal": "res://art/ui/reference/completion_medal.png",
	"flyer": "res://art/ui/reference/megaphone.png",
	"megaphone": "res://art/ui/reference/megaphone.png",
}
const ICON_DIR := "res://art/ui/icons/"
## Old names that share one icon file.
const ALIASES := {"expand": "arrow_up", "collapse": "arrow_down"}
static var _cache: Dictionary = {}


static func texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key] as Texture2D
	var result: Texture2D
	if key.begins_with("res://"):
		# 店铺数据直接给图（比如店铺美术图集里的一块）
		result = load(key) as Texture2D if ResourceLoader.exists(key) else null
	elif key == "staff":
		result = face("cat")
	elif ART.has(key):
		result = load(ART[key]) as Texture2D
	elif key.begins_with("drink_") and ResourceLoader.exists("res://art/ui/" + key + ".png"):
		result = load("res://art/ui/" + key + ".png") as Texture2D
	else:
		var path: String = ICON_DIR + String(ALIASES.get(key, key)) + ".svg"
		if ResourceLoader.exists(path):
			result = load(path) as Texture2D
	if result != null:
		_cache[key] = result
	return result


static func portrait(art: String) -> Texture2D:
	return CharacterLibrary.portrait(art)


static func face(art: String) -> Texture2D:
	var key := "face/" + art
	if _cache.has(key):
		return _cache[key] as Texture2D
	var source := portrait(art)
	if source == null:
		return null
	# Keep the actual game cat, including the chef hat and original painted face.
	# Atlas crop retains source pixels, without introducing a second cat.
	if art == "cat":
		var cropped := AtlasTexture.new()
		cropped.atlas = source
		cropped.region = Rect2(38, 3, 249, 252)
		_cache[key] = cropped
	else:
		_cache[key] = source
	return _cache[key] as Texture2D

