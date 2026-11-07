extends SceneTree
## 把每家店美术场景里的走位锚点（Anchors/Nav：可走区域、障碍、站位、岗位）写回 shop.tres 的 layout（规格 §6.1）。
## 店铺数据（数值、菜谱、文案）直接在 Godot 里编辑 content/shops/<店>/shop.tres；只有挪了美术、改了走位时才跑这个：
##   godot --headless --path . -s tools/sync_shop_layouts.gd
## 加 -- --check 只检查不写，有不一致就退出码 1（CI 用）。

const CAMPAIGN := "res://content/campaign/campaign.tres"


func _initialize() -> void:
	var check := "--check" in OS.get_cmdline_user_args()
	var campaign: SpecCampaign = load(CAMPAIGN)
	var failed := false
	for city in campaign.cities:
		for entry in city.shops:
			if entry.shop_path.is_empty(): continue
			var shop: SpecShop = load(entry.shop_path)
			var synced := synced_layout(shop)
			if synced == null: continue
			var same := _same(synced, shop.layout)
			if check:
				print("%s %s" % ["一致" if same else "不一致", entry.shop_path])
				failed = failed or not same
				continue
			if same:
				print("不用改 " + entry.shop_path)
				continue
			shop.layout = synced
			var error := ResourceSaver.save(shop, entry.shop_path)
			print("%s %s" % ["写出" if error == OK else "失败", entry.shop_path])
			failed = failed or error != OK
	quit(1 if failed else 0)


## 场景里没有 Anchors/Nav 的店（直线走）返回 null，不动它的 layout
static func synced_layout(shop: SpecShop) -> SpecLayout:
	if shop.scene_path.is_empty(): return null
	var art: Node = load(shop.scene_path).instantiate()
	var anchors := ShopAnchors.new(art.get_node_or_null("Anchors"))
	var layout: SpecLayout = anchors.layout(shop.layout) if anchors.has("Nav") else null
	art.free()
	return layout


static func _same(a: SpecLayout, b: SpecLayout) -> bool:
	for key in ["nav", "cell", "grid_size", "areas", "obstacles", "points", "posts", "aliases", "spawn_point"]:
		if var_to_str(a.get(key)) != var_to_str(b.get(key)): return false
	return true
