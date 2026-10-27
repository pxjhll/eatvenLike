extends RefCounted
## Pure presentation derivation. Never writes into the supplied snapshot or Def.


static func station(row: Dictionary, def: StationDef) -> Dictionary:
	if row.status != StationState.Status.ACTIVE:
		return {"kind": "locked", "text": "待启用", "color": Color("9ca8ab")}
	if def.mode == StationDef.Mode.DISPENSER:
		return {"kind": "service", "text": "现打", "color": Color("6e9988")}
	if def.owner == StationDef.OwnerSystem.FRONT_HALL:
		return {"kind": "service", "text": "销售台", "color": Color("6e9988")}
	var batch := SaveUtil.total(def.recipe.outputs) if def.recipe else 1
	if SaveUtil.total(row.outputs) + batch > def.output_capacity:
		return {"kind": "blocked", "text": "出口堵了", "color": Color("e53935")}
	if row.phase == StationState.Phase.PROCESSING:
		return {"kind": "working", "text": "加工中", "color": Color("6e9988")}
	if row.phase in [StationState.Phase.WAIT_LOAD, StationState.Phase.WAIT_UNLOAD, StationState.Phase.WAIT_WORK]:
		if row.get("staff_working", false):
			var action := "装入中" if row.phase == StationState.Phase.WAIT_LOAD else ("取出中" if row.phase == StationState.Phase.WAIT_UNLOAD else "手工制作")
			return {"kind": "working", "text": action, "color": Color("6e9988")}
		return {"kind": "staff", "text": "等待员工", "color": Color("c39e5c")}
	if def.mode == StationDef.Mode.SUPPLY:
		return {"kind": "working", "text": "供料中", "color": Color("6e9988")}
	return {"kind": "input", "text": "缺原料", "color": Color("9aa6a8")}


static func mode_label(def: StationDef) -> String:
	return ["全自动", "人机配合", "手工作业", "自动供料", "前厅现打"][def.mode]


static func buffers(row: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for side in ["input", "output"]:
		var items: Dictionary = row.inputs if side == "input" else row.outputs
		for item in items:
			if int(items[item]) > 0:
				result.append({"item": item, "count": int(items[item]), "side": side})
	return result
