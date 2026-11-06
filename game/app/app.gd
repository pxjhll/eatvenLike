extends Node
## Shared persistence: the cross-shop profile (trophies, perks, which shop is open) and the tea shop save.
## Each shop scene owns its simulation.

var art_shop_save := preload("res://game/tea_playtest/tea_shop_save.gd").new()
var profile := preload("res://game/app/profile.gd").new()
