extends "res://tests/test_case.gd"
const TemplateOuter := preload("res://tests/fixtures/template_outer.gd")
const SHOP: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const FOOD := ["rice","tomato_egg","pepper_pork","kungpao","tomato_rice","pepper_rice","kungpao_rice","egg_fried_rice","yangzhou_rice","soup"]

func test_user_food_resources_drive_scene_items_order_icons_and_ui_icon_paths() -> void:
	var view := ShopView.new(TemplateOuter.owner(SHOP))
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.shop = SHOP
	scene.view = view
	check(view.has_method("item_icon"),"scene and HUD share the same data-driven item icon resolver")
	for id in FOOD:
		var expected := "res://art/stirfry/items/%s.png"%id
		check_eq(view.item_art(id).texture.resource_path,expected,"scene uses the user's actual "+id+" sprite")
		check_eq(scene._order_icon(id).resource_path,expected,"customer bubble uses the same "+id+" sprite")
		check_eq(view.icon_of(id),expected,"recipe/UI uses the actual "+id+" image instead of a tea icon name")
	scene.free()

func test_missing_art_has_a_neutral_placeholder_and_preserves_explicit_tea_art() -> void:
	var shop := SHOP.copy_for_editing()
	var item := SpecItem.new()
	item.id = "unconfigured_food"
	item.display_name = "尚未接图"
	shop.items.append(item)
	var view := ShopView.new(TemplateOuter.owner(shop))
	check_eq(view.item_art(item.id).texture.resource_path,"res://art/ui/icons/tag.svg","missing scene art cannot silently become pearl milk tea")
	if view.has_method("item_icon"):
		check_eq(view.item_icon(item.id).resource_path,"res://art/ui/icons/tag.svg","missing order art uses the same neutral placeholder")
	var actor := preload("res://presentation/shop/shop_actor.gd")
	check_eq(actor.drink_icon(item.id).resource_path,"res://art/ui/icons/tag.svg","standalone actors cannot inject a tea fallback either")
	var tea := ShopView.new(TemplateOuter.owner(load("res://content/shops/tea/shop.tres")))
	check_eq(tea.item_art("lemonade").texture.resource_path,"res://art/reference/fruit_tea.png","explicit legacy tea scene art is preserved")

func _public_scene() -> Dictionary:
	var owner := TemplateOuter.owner(SHOP.copy_for_editing(),42)
	owner.gold = 1000000.0
	for stage in SHOP.stages.size(): check_eq(owner.unlock(SHOP.sold_at(stage)),"","actual outer purchases")
	var runtime: RefCounted = load("res://game/rules/template/runtime.gd").new(owner,load("res://content/shops/stirfry/shared_production.tres"))
	check_eq(runtime.last_error,"","common actual production and presentation")
	var prepared := preload("res://presentation/shop/shop_scene_contract.gd").prepare(SHOP)
	check_eq(prepared.errors,[],"same authored scene ports")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.shop = SHOP
	scene.view = ShopView.new(owner)
	scene.anchors = ShopAnchors.new(prepared.art.get_node("Anchors"))
	scene._sortables = prepared.art.get_node("Sortables")
	scene._actor_unit_scale = SHOP.layout.motion_units
	check_eq(scene.bind_runtime(runtime),"","bind explicit display ports")
	return {"runtime":runtime,"scene":scene,"art":prepared.art}

func test_shared_pot_stock_remains_ui_inventory_without_loose_scene_dishes() -> void:
	var fixture := _public_scene()
	var runtime: RefCounted = fixture.runtime
	var frame: Dictionary = fixture.scene.view.render_snapshot()
	check(runtime.runner.inventory.quantity("rice_cooker:out","rice")>0,"real opening rice stock exists")
	check_eq(frame.draws,[],"shared stock is not a display declaration")
	check_eq(fixture.scene.view.machine_status("rice_cooker").output,runtime.runner.inventory.quantity("rice_cooker:out"),"UI reads the same physical pot stock")
	var before: Dictionary = runtime.snapshot()
	fixture.scene._update_cups(frame)
	check_eq(runtime.snapshot(),before,"drawing cannot consume or move inventory")
	check(fixture.scene._cups.filter(func(sprite: Sprite2D) -> bool: return sprite.visible).is_empty(),"no shared bowl stack")
	fixture.scene.free(); fixture.art.free()

func test_finished_rice_waits_in_ui_inventory_without_an_automatic_plating_sprite() -> void:
	var fixture := _public_scene()
	var runtime: RefCounted = fixture.runtime
	var unit: int = runtime.request_production("tomato_rice").id
	for tick in 2200:
		check_eq(runtime.step(0.1),"","actual rice-and-topping production")
		if runtime.production_output(unit).complete: break
	check(runtime.production_output(unit).complete,"real merge reached its finished output")
	var frame: Dictionary = fixture.scene.view.render_snapshot()
	check_eq(frame.stock["plating:out"].items.tomato_rice.count,1,"actual owned meal remains in the common ledger")
	check_eq(fixture.scene.view.machine_status("plating").output,1,"machine UI records the completed meal")
	var before: Dictionary = runtime.snapshot()
	fixture.scene._update_cups(frame)
	check(fixture.scene._cups.filter(func(sprite: Sprite2D) -> bool: return sprite.visible).is_empty(),"a Buffer anchor cannot implicitly turn stock into a scene sprite")
	check_eq(runtime.snapshot(),before,"hiding unconfigured stock does not delete the real product")
	fixture.scene.free(); fixture.art.free()
