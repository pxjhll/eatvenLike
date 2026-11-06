extends RefCounted
## Shared artwork and code-drawn warm outlined icons for the reference UI.
## Simple geometry is rasterized at 4x once and cached; no screenshot skins.

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
static var _cache: Dictionary = {}


static func texture(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key] as Texture2D
	var result: Texture2D
	if key == "staff":
		result = face("cat")
	elif ART.has(key):
		result = load(ART[key]) as Texture2D
	elif key.begins_with("drink_") and ResourceLoader.exists("res://art/ui/" + key + ".png"):
		result = load("res://art/ui/" + key + ".png") as Texture2D
	else:
		var body := _geometry(key)
		if not body.is_empty():
			var img := Image.new()
			var error := img.load_svg_from_string(_svg(body), 4.0)
			if error == OK:
				result = ImageTexture.create_from_image(img)
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


static func _svg(body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><defs><linearGradient id="cream" x2="0" y2="1"><stop stop-color="#fff9e9"/><stop offset="1" stop-color="#f0cda1"/></linearGradient><linearGradient id="wood" x2="0" y2="1"><stop stop-color="#efb574"/><stop offset="1" stop-color="#cb7937"/></linearGradient><linearGradient id="gold" x2="0" y2="1"><stop stop-color="#ffe398"/><stop offset="1" stop-color="#f4a52f"/></linearGradient><linearGradient id="red" x2="0" y2="1"><stop stop-color="#ffb29c"/><stop offset="1" stop-color="#cf6153"/></linearGradient><linearGradient id="glass" x2="1" y2="1"><stop stop-color="#e6f7fc"/><stop offset="1" stop-color="#91b8c7"/></linearGradient></defs><g stroke="#59321c" stroke-width="3.2" stroke-linejoin="round" stroke-linecap="round">' + body + '</g></svg>'


static func _geometry(key: String) -> String:
	match key:
		"goals":
			return '<rect x="13" y="12" width="39" height="47" rx="5" fill="#d28a45"/><rect x="17" y="16" width="31" height="39" rx="2" fill="url(#cream)" stroke="#995e2b" stroke-width="1.6"/><path d="M26 13V9a6 6 0 0 1 12 0v4h5v8H21v-8Z" fill="#a67850"/><path d="M30 9h4" stroke="#fff0d3" stroke-width="2"/><path d="M23 30h10m-10 9h10m-10 9h10" stroke="#c4935f" stroke-width="2"/><path d="m37 29 2 3 5-6m-7 12 2 3 5-6m-7 12 2 3 5-6" fill="none" stroke-width="2.2"/>'
		"hat":
			return '<path d="M15 39C4 38 4 22 15 21c1-12 16-15 23-7 10-5 20 3 18 13 7 9-1 16-10 13l-1 14H18Z" fill="url(#cream)"/><path d="m18 41 1 9c9 3 17 3 26 0l1-10M22 30l2 11m17-13-2 14m-8-17v18" stroke="#dab38b" stroke-width="2.5" fill="none"/>'
		"pause":
			return '<path d="m15 19 17-12 17 12" fill="none"/><circle cx="32" cy="8" r="3" fill="url(#gold)"/><rect x="7" y="19" width="50" height="36" rx="3" fill="url(#wood)"/><path d="M11 24h42M12 49h40" stroke="#ffcc8c" stroke-width="2"/><path d="M27 29v15m10-15v15" stroke-width="5"/>'
		"pause_bars":
			return '<rect x="19" y="14" width="9" height="37" rx="2" fill="#825131" stroke-width="1.5"/><rect x="37" y="14" width="9" height="37" rx="2" fill="#825131" stroke-width="1.5"/>'
		"save":
			return '<path d="M12 8h33l10 10v36a3 3 0 0 1-3 3H12a3 3 0 0 1-3-3V11a3 3 0 0 1 3-3Z" fill="#778295"/><path d="M18 9h25v18H18Z" fill="#d7d8d7"/><path d="M34 12h6v12h-6Z" fill="#4b505d" stroke-width="1.5"/><rect x="17" y="35" width="31" height="20" rx="2" fill="url(#cream)" stroke-width="2"/><path d="M22 42h21m-21 6h21" stroke="#dbb38c" stroke-width="2"/><path d="M13 12v39" stroke="#b9c6d6" stroke-width="2"/>'
		"glass":
			return '<rect x="10" y="9" width="44" height="40" rx="3" fill="url(#glass)"/><path d="m13 34 22-22h10L14 44m13 1 23-23" fill="#effbfc" stroke="none" opacity=".65"/><path d="M9 38h6v17H9Zm40 0h6v17h-6Z" fill="url(#wood)"/><rect x="5" y="52" width="15" height="6" rx="1" fill="url(#wood)"/><rect x="44" y="52" width="15" height="6" rx="1" fill="url(#wood)"/>'
		"trash":
			return '<path d="m24 13 1-5h15l1 5" fill="url(#red)"/><path d="m13 20 4 35q0 4 5 4h21q4 0 4-4l4-35" fill="url(#red)"/><rect x="9" y="14" width="46" height="8" rx="4" fill="url(#red)"/><path d="M24 29v20m9-20v20m9-20v20" stroke="#803d2b" stroke-width="3"/><path d="m18 26 2 24" stroke="#ffc6ac" stroke-width="2"/>'
		"selected_check":
			return '<circle cx="32" cy="32" r="27" fill="url(#gold)" stroke="#a8641b" stroke-width="3"/><circle cx="32" cy="30" r="23" fill="none" stroke="#ffe9a8" stroke-width="2"/><path d="m18 31 10 10 19-21" fill="none" stroke="#fff9e9" stroke-width="7"/>'
		"check":
			return '<path d="m13 33 13 13 26-29" fill="none" stroke="#416d39" stroke-width="8"/><path d="m14 30 12 12 25-28" fill="none" stroke="#7eaf4d" stroke-width="5"/>'
		"lock":
			return '<path d="M20 28V18a12 12 0 0 1 24 0v10" fill="none" stroke="#866044" stroke-width="6"/><path d="M21 25v-7a11 11 0 0 1 22 0v7" fill="none" stroke="#efd3a8" stroke-width="2"/><rect x="12" y="26" width="40" height="31" rx="6" fill="url(#gold)"/><circle cx="32" cy="38" r="4" fill="#825431" stroke="none"/><path d="M32 40v7" stroke="#825431" stroke-width="4"/>'
		"clock":
			return '<circle cx="32" cy="33" r="24" fill="url(#gold)"/><circle cx="32" cy="32" r="19" fill="url(#cream)" stroke="#aa713e" stroke-width="2"/><path d="M32 18v15l10 5" fill="none"/><circle cx="32" cy="32" r="2" fill="#754223" stroke="none"/><path d="M15 14 11 10m38 4 4-4" stroke="#bf8649" stroke-width="5"/>'
		"record":
			return '<rect x="7" y="16" width="35" height="33" rx="5" fill="url(#cream)"/><path d="m42 26 13-7v27l-13-7Z" fill="url(#cream)"/><path d="M12 21h24v21" stroke="#fffaf1" stroke-width="2" fill="none"/>'
		"export":
			return '<path d="M18 31h-6v22h41V31h-6" fill="url(#cream)"/><path d="M32 39V8M20 20 32 8l12 12" fill="none" stroke-width="4"/>'
		"tag":
			return '<path d="M13 30 35 8h19v19L31 51a5 5 0 0 1-7 0L13 40a7 7 0 0 1 0-10Z" fill="url(#cream)"/><circle cx="45" cy="17" r="3" fill="#b17c4c" stroke-width="2"/><path d="m17 33 21-21" stroke="#fffaf0" stroke-width="2"/>'
		"previous":
			return '<path d="M15 15v35" stroke-width="6"/><path d="M47 14 23 32l24 18Z" fill="#825131" stroke-width="1.5"/>'
		"next":
			return '<path d="M49 15v35" stroke-width="6"/><path d="m17 14 24 18-24 18Z" fill="#825131" stroke-width="1.5"/>'
		"play":
			return '<path d="m22 13 28 19-28 19Z" fill="#825131" stroke-width="2"/>'
		"arrow_right":
			return '<path d="m25 14 18 18-18 18" fill="none" stroke-width="5"/>'
		"arrow_left":
			return '<path d="M39 14 21 32l18 18" fill="none" stroke-width="5"/>'
		"arrow_up", "expand":
			return '<path d="m15 41 17-18 17 18" fill="none" stroke-width="5"/>'
		"arrow_down", "collapse":
			return '<path d="m15 23 17 18 17-18" fill="none" stroke-width="5"/>'
		"close":
			return '<path d="m18 18 28 28m0-28L18 46" fill="none" stroke-width="5"/>'
	return ""
