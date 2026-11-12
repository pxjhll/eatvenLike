extends "res://tests/test_case.gd"
const SHOP: SpecShop = preload("res://content/shops/stirfry/shop.tres")
const FOOD := ["rice","tomato_egg","pepper_pork","kungpao","tomato_rice","pepper_rice","kungpao_rice","egg_fried_rice","yangzhou_rice","soup"]

func test_user_food_resources_drive_scene_items_order_icons_and_ui_icon_paths() -> void:
	var view := ShopView.new(ShopRules.new(SHOP))
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
	var view := ShopView.new(ShopRules.new(shop))
	check_eq(view.item_art(item.id).texture.resource_path,"res://art/ui/icons/tag.svg","missing scene art cannot silently become pearl milk tea")
	if view.has_method("item_icon"):
		check_eq(view.item_icon(item.id).resource_path,"res://art/ui/icons/tag.svg","missing order art uses the same neutral placeholder")
	var actor := preload("res://presentation/shop/shop_actor.gd")
	check_eq(actor.drink_icon(item.id).resource_path,"res://art/ui/icons/tag.svg","standalone actors cannot inject a tea fallback either")
	var tea := ShopView.new(ShopRules.new(load("res://content/shops/tea/shop.tres")))
	check_eq(tea.item_art("lemonade").texture.resource_path,"res://art/reference/fruit_tea.png","explicit legacy tea scene art is preserved")

func test_shared_pot_stock_is_not_rendered_as_a_stack_of_order_dishes() -> void:
	var rules := ShopRules.new(SHOP,42)
	rules.unlock("wok_a")
	var prepared := preload("res://presentation/shop/shop_scene_contract.gd").prepare(SHOP)
	check_eq(prepared.errors,[],"formal scene supplies the same rendering anchors")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.shop = SHOP
	scene.view = ShopView.new(rules)
	scene.anchors = ShopAnchors.new(prepared.art.get_node("Anchors"))
	var frame: Dictionary = scene.view.render_snapshot()
	check(frame.serve.goods.any(func(good: Dictionary) -> bool: return good.owner==-1),"real opening rice stock exists")
	var draws: Array = []
	scene._serve_goods(frame,draws)
	check_eq(draws,[],"shared rice stock stays inside the machine rather than becoming loose bowls")
	var saw_product := false
	for tick in 1800:
		rules.step(0.1)
		frame = scene.view.render_snapshot()
		if not frame.serve.goods.any(func(good: Dictionary) -> bool: return good.owner!=-1 and not String(good.at).contains(":")): continue
		var state := rules.to_dict()
		var own: Dictionary = frame.duplicate(true)
		own.serve.goods = own.serve.goods.filter(func(good: Dictionary) -> bool: return good.owner!=-1)
		var expected: Array = []
		scene._serve_goods(own,expected)
		draws.clear()
		scene._serve_goods(frame,draws)
		check(not expected.is_empty(),"actual products assigned to orders remain visible")
		check_eq(draws,expected,"shared stock never adds duplicate bowls beside real products")
		check_eq(rules.to_dict(),state,"drawing does not delete or consume any real inventory")
		saw_product = true
		break
	check(saw_product,"production reached a real owned item")
	scene.free()
	prepared.art.free()

func test_finished_rice_waits_on_the_plating_surface_and_sorts_with_its_table() -> void:
	var rules := ShopRules.new(SHOP,42)
	rules.unlock("wok_a")
	var prepared := preload("res://presentation/shop/shop_scene_contract.gd").prepare(SHOP)
	check_eq(prepared.errors,[],"plating module is valid")
	var scene: Node2D = load("res://presentation/shop/shop_play.tscn").instantiate()
	scene.shop = SHOP
	scene.view = ShopView.new(rules)
	scene.anchors = ShopAnchors.new(prepared.art.get_node("Anchors"))
	scene._sortables = prepared.art.get_node("Sortables")
	scene._actor_unit_scale = SHOP.layout.motion_units
	check(scene.anchors.has("Stations/plating/Buffer"),"plating owns a product display port distinct from the worker position")
	var found := false
	for tick in 1800:
		rules.step(0.1)
		if not rules.serve.goods.any(func(good: Dictionary) -> bool: return good.at=="plating" and good.item=="tomato_rice"): continue
		var state := rules.to_dict()
		scene._update_cups(scene.view.render_snapshot())
		var sprite: Sprite2D
		for cup: Sprite2D in scene._cups:
			if cup.visible and cup.texture.resource_path=="res://art/stirfry/items/tomato_rice.png": sprite = cup
		check(sprite!=null,"actual completed rice remains visible while awaiting pickup")
		if sprite!=null:
			var bounds: Rect2 = sprite.get_rect()
			var top_left: Vector2 = sprite.position+bounds.position*sprite.scale
			var bottom_right: Vector2 = top_left+bounds.size*sprite.scale
			check(Rect2(760,480,85,80).encloses(Rect2(top_left,bottom_right-top_left)),"finished dish stays inside the clear right-hand tabletop area")
			check(is_equal_approx(sprite.position.y,prepared.art.get_node("Sortables/PlatingTable").position.y+1.0),"dish sorts in front of its host table while its visual stays on the surface")
		check_eq(rules.to_dict(),state,"placement does not move workers or change inventory")
		found = true
		break
	check(found,"real production reached a completed rice bowl at plating")
	scene.free()
	prepared.art.free()
