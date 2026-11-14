extends RefCounted
const TemplateOuter := preload("res://tests/fixtures/template_outer.gd")
## Explicit installed-material production fixture, not a formal shop entry or
## automatic legacy conversion. Purchasing and service are intentionally absent.
const TEA: SpecShop = preload("res://content/shops/tea/shop.tres")
const Schema := preload("res://content/rules/spec_shop_template.gd")

static func owner() -> ShopRules:
	var shop: SpecShop = TEA.copy_for_editing()
	var rules := TemplateOuter.owner(shop,42)
	for station in shop.stations: rules.unlocked[station.id] = true
	rules.nav.set_open(rules.unlocked)
	return rules

static func definition() -> Resource:
	var template := Schema.new()
	var pot := TEA.station("boil")
	var mix := TEA.station("mix")
	var step: SpecStep
	for candidate in TEA.dish("plain_milk_tea").steps:
		if candidate.station == mix.id: step = candidate
	template.places = {"supply":{"port":TEA.layout.points.supply,"infinite":["tea_leaf"]},
		"boil_in":{"port":TEA.layout.points.boil,"capacity":12},"boil_out":{"port":TEA.layout.points.boil,"capacity":12},
		"mix_in":{"port":TEA.layout.points.mix,"capacity":6,"infinite":["milk"]},"mix_out":{"port":TEA.layout.points.mix,"capacity":6}}
	template.machines = {"boil":{"input":"boil_in","output":"boil_out","profile":{
		"load_seconds":pot.params.load_seconds,"unload_seconds":TEA.dispatch.hop_seconds,
		"stir_points":pot.params.stir_points.duplicate(),"stir_seconds":pot.params.stir_seconds}},
		"mix":{"input":"mix_in","output":"mix_out","profile":{"manual":false}}}
	template.restocks = {"tea":{"machine":"boil","consumes":{"tea_leaf":1},"produces":{"tea":1},"sources":{"tea_leaf":"supply"},
		"seconds":pot.params.cook_seconds,"fetch_seconds":TEA.station("supply").params.fetch_seconds,"fetch_timing_target":"supply",
		"stock_limit":12,"policy":{"mode":"demand","base":1,"per_waiting":1},"batch":{"target":"boil","base":3,"max":12}}}
	template.recipes = {"milk_tea":{"nodes":[
		{"id":"tea","capability":"source","place":"boil_out","item":"tea","seconds":TEA.dispatch.hop_seconds},
		{"id":"mix","capability":"process","machine":"mix","seconds":mix.params.seconds,
			"consumes":step.consumes.duplicate(),"produces":step.produces.duplicate(),"inputs":{"tea":"tea","milk":{"capability":"integrated"}}}],
		"output":{"node":"mix","item":"plain_milk_tea","count":1}}}
	return template
