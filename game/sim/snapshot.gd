class_name SimSnapshot
extends RefCounted
## 每 tick 重新生成的只读快照。表现层拿到的是副本，改它不影响模拟。


static func build(sim: GameSim) -> Dictionary:
	return {
		"tick": sim.tick,
		"time": sim.elapsed_seconds(),
		"gold": sim.economy.gold,
		"revenue": sim.economy.revenue,
		"production": sim.production.to_dict(),
		"front_hall": sim.front_hall.to_dict(),
		"workforce": sim.workforce.to_dict(),
		"progress": sim.progress.to_dict(),
		"tasks": _tasks(sim),
	}


## 已解锁阶段的任务与进度（派生状态，不回写）
static func _tasks(sim: GameSim) -> Array:
	var out := []
	var stages := sim.config.progression.stages
	for i in sim.progress.stage_index + 1:
		for task in stages[i].tasks:
			out.append({"id": task.id, "name": task.display_name, "progress": sim.progress.task_progress(task)})
	return out
