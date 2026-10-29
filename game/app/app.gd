extends Node
## 唯一的 Autoload：持有跨店的 Profile，负责存读档和换店。不参与店内任何规则。

const CATALOG_PATH := "res://content/catalog.tres"
## 自动存档间隔（占位）
const AUTOSAVE_SECONDS := 30.0

var catalog: GameCatalog
var profile: Profile
var save_service := SaveService.new()
## Art-shop career is independent of the legacy shop/profile save.
var art_shop_save := preload("res://game/tea_playtest/tea_shop_save.gd").new()
var sim: GameSim

## 读档得到、还没交给 GameSim 的店内状态
var _pending_shop_state := {}
var _autosave_timer := 0.0


func _ready() -> void:
	catalog = load(CATALOG_PATH)
	var data := save_service.load_data()
	if data.has("profile"):
		profile = Profile.from_dict(data.profile)
		_pending_shop_state = data.get("shop", {})
	else:
		profile = Profile.create(catalog)


func current_config() -> ShopConfig:
	return catalog.shops[profile.current_shop]


func roster_defs() -> Array[StaffDef]:
	var out: Array[StaffDef] = []
	for d in catalog.staff:
		if d.id in profile.roster:
			out.append(d)
	return out


## 店铺场景就绪时调用：按当前店配置初始化 GameSim，有中途存档就读回去
func open_shop(game_sim: GameSim) -> void:
	sim = game_sim
	sim.setup(current_config(), roster_defs())
	if not _pending_shop_state.is_empty() and String(_pending_shop_state.get("shop_id", "")) == sim.config.id:
		sim.load_dict(_pending_shop_state)
	_pending_shop_state = {}
	_autosave_timer = 0.0


func save_now() -> Error:
	var data := {"profile": profile.to_dict()}
	if sim != null and sim.config != null:
		data.shop = sim.to_dict()
	var err := save_service.save(data)
	if err != OK:
		push_warning("存档失败：%s" % error_string(err))
	return err


## SwitchShop：写入纪录 → 存档 → 丢弃旧 GameSim → 用下一家 ShopConfig 新建。返回空字符串表示成功。
func switch_shop() -> String:
	var reason := SwitchShopCommand.new().validate(sim)
	if reason != "":
		return reason
	if profile.current_shop + 1 >= catalog.shops.size():
		return "已经是最后一家店"
	profile.record_shop(sim.config.id, sim.economy.revenue, sim.elapsed_seconds())
	profile.current_shop += 1
	sim = null
	save_now()
	get_tree().reload_current_scene()
	return ""


func _process(delta: float) -> void:
	if sim == null:
		return
	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_SECONDS:
		_autosave_timer = 0.0
		save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if sim != null:
			save_now()
