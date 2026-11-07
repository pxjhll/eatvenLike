extends Node
## Shared persistence: the cross-shop profile (trophies, perks, which shop is open).
## Each shop scene saves its own file through ShopSave.

var profile := preload("res://game/app/profile.gd").new()
