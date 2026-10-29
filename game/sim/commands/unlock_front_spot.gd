class_name UnlockFrontSpotCommand
extends SimCommand
## 解锁前厅固定位点（点一下价格牌）。后厨设备不走这条命令，在布局模式里买。

var spot_id: String


func _init(spot_id_: String) -> void:
	spot_id = spot_id_


func validate(sim: GameSim) -> String:
	if not sim.front_hall.has_spot(spot_id):
		return "没有这个前厅位点"
	var reason := sim.front_hall.validate_unlock(spot_id)
	if reason != "":
		return reason
	if sim.progress.stage_index < sim.front_hall.spot_def(spot_id).stage:
		return "这个位点还没开放"
	if not sim.economy.can_spend(sim.front_hall.spot_def(spot_id).unlock_cost):
		return "金币不足"
	return ""


func commit(sim: GameSim) -> void:
	sim.economy.spend(sim.front_hall.spot_def(spot_id).unlock_cost)
	sim.front_hall.commit_unlock(spot_id)
	sim.push_events([{"type": "front_spot_unlocked", "spot": spot_id}])
