extends RefCounted
## Neutral compatibility and UI catalog; validity always comes from status.code.

const TEMPLATES := {
	"ok": "", "unknown_command": "未知操作", "invalid_argument": "无效参数",
	"session_unavailable": "当前无法操作",
	"unknown_station": "未知设备", "station_already_unlocked": "设备已经解锁",
	"station_not_unlockable": "这台设备不能单独解锁", "shop_not_open": "请先开张",
	"stage_required": "请先解锁{stage_name}", "insufficient_gold": "金币不足，需要 {required}",
	"unknown_box": "未知原料箱", "box_already_unlocked": "原料箱已经解锁",
	"station_required": "请先解锁设备", "box_required": "请先解锁原料箱",
	"station_level_required": "设备需升到 Lv{required_level}", "no_upgrade": "无需升级", "max_level": "已满级",
	"seats_full": "座位已满", "seat_stage_required": "下一阶段开放更多座位",
	"flyer_active": "传单正在起效，还有 {seconds} 秒", "flyer_cooldown": "传单还要等 {seconds} 秒才能再发",
	"hire_exhausted": "没有可招的人了", "staff_full": "人手已满", "front_full": "前台最多 {count} 位",
	"kitchen_full": "后厨最多 {count} 位员工", "unknown_worker": "未拥有这位员工",
	"not_seatable": "这里不能坐班", "post_occupied": "岗位已有员工", "reassignment_disabled": "这家店不能调岗",
	"invalid_post": "无效岗位", "position_unreachable": "无法放置在这里", "worker_already_waiting": "员工已在待派遣名册",
	"event_missing": "现在没有卡片", "invalid_event_choice": "没有这一项",
	"unknown_connection": "未知传送带", "connection_already_built": "这里已经装了传送带", "ui_drop_rejected": "无法放置在这里",
}

static func format(status: Dictionary, shop: SpecShop = null, overrides: Dictionary = {}) -> String:
	var code: String = status.get("code", "invalid_argument")
	var params: Dictionary = status.get("params", {}).duplicate(true)
	var template: String = overrides.get(code, TEMPLATES.get(code, "无效参数"))
	if not overrides.has(code):
		if code == "post_occupied" and params.get("command") == "deploy_worker": template = "这里已经有人了"
		if code == "station_required" and params.get("command") == "unlock_box": template = "请先解锁{station_name}"
	if shop != null:
		if params.has("station"):
			var station := shop.station(params.station)
			params.station_name = station.display_name if station != null else params.station
		if params.has("stage"):
			var index := int(params.stage)
			params.stage_name = shop.stages[index].display_name if index >= 0 and index < shop.stages.size() else str(index)
	if not params.has("station_name"): params.station_name = params.get("station", "")
	if not params.has("stage_name"): params.stage_name = str(params.get("stage", ""))
	return template.format(params)
