extends RefCounted
## 跨文件进度提交顺序。店铺删除只是提交后的清理，不能触发重复结店。

var last_error := ""

func finish_shop(profile: RefCounted, store: ShopSave, record: Dictionary) -> Error:
	last_error = ""
	if profile == null: return _fail(ERR_INVALID_PARAMETER, "无法读取跨店进度。")
	var error: Error = profile.finish_shop(record)
	if error != OK: return _fail(error, profile.last_error)
	if store != null: store.delete()
	return OK

func jump_shop(profile: RefCounted, store: ShopSave, rules: ShopRules, target: String, speed := 1.0, guides: Array = []) -> Error:
	last_error = ""
	if profile == null or store == null: return _fail(ERR_UNAVAILABLE, "跳店前需要成功保存当前店铺。")
	var error := store.save_game(rules, speed, guides)
	if error != OK: return _fail(error, store.last_error)
	error = profile.select_shop(target)
	if error != OK: return _fail(error, profile.last_error)
	return OK

func initialize_fresh(profile: RefCounted, store: ShopSave) -> Dictionary:
	last_error = ""
	if profile == null or store == null or not profile.fresh_shop or profile.shop != store.shop.id:
		return {"error": _fail(ERR_INVALID_PARAMETER, "新店开店标记无效。")}
	var guard: Error = profile.check_writable()
	if guard != OK: return {"error": _fail(guard, profile.last_error)}
	var rules := ShopRules.new(store.shop)
	# fresh_shop 是持久化意图。先写空店，再确认；任一步失败都不允许营业。
	var error := store.save_game(rules, 1.0, [])
	if error != OK: return {"error": _fail(error, store.last_error)}
	error = profile.acknowledge_fresh_shop()
	if error != OK: return {"error": _fail(error, profile.last_error)}
	return {"error": OK, "rules": rules}

func _fail(error: Error, message: String) -> Error:
	last_error = message if not message.is_empty() else "进度保存失败，请检查空间或权限后重试。"
	return error
