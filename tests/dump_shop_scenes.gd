extends SceneTree
## 导出后场景树核对：把每家店的原画场景摊开，按行写出所有节点路径。
## 用法：godot --headless [--path . | --main-pack index.pck] -s <本文件绝对路径> -- <输出文件>
## 工程里跑一次、导出包里跑一次，两份结果必须一模一样。
## 起因：Godot 4.7 导出时把文本场景转成二进制，会丢掉“挂在实例场景子节点下面的新节点”
## （煎饼摊的 Sortables 挂在 Stall/SceneClip 下，线上网页版因此启动就崩）。

const SHOPS_DIR := "res://content/shops"


func _initialize() -> void:
	var out_path := ""
	for arg in OS.get_cmdline_user_args(): out_path = arg
	var lines: PackedStringArray = []
	var failed := false
	for dir_name in DirAccess.get_directories_at(SHOPS_DIR):
		var shop_path := "%s/%s/shop.tres" % [SHOPS_DIR, dir_name]
		if not ResourceLoader.exists(shop_path): continue
		var shop: Resource = load(shop_path)
		var scene_path := String(shop.get("scene_path"))
		# 还没有美术场景的原型店没有场景可核对
		if scene_path.is_empty(): continue
		var art: Node = load(scene_path).instantiate()
		var anchors := art.get_node_or_null("Anchors")
		var sortables := String(anchors.get_meta("sortables", "Sortables")) if anchors else "Sortables"
		if art.get_node_or_null(sortables) == null:
			printerr("%s: 找不到 sortables 节点 %s" % [scene_path, sortables])
			failed = true
		var paths: PackedStringArray = []
		for node in art.find_children("*", "", true, false):
			paths.append("%s %s %s" % [scene_path, art.get_path_to(node), node.get_class()])
		paths.sort()
		lines.append_array(paths)
		art.free()
	if out_path != "":
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		file.store_string("\n".join(lines) + "\n")
	print("shop scene nodes: %d" % lines.size())
	quit(1 if failed or lines.is_empty() else 0)
