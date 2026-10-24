class_name SimCommand
extends RefCounted
## 跨系统命令：Validate All → Commit All。
## validate 只读，任一失败整条命令拒绝、不改任何状态；
## 进入 commit 后不允许业务失败，前提都已在 validate 检查，commit 里只用 assert 兜底。


## 返回空字符串表示通过，否则是拒绝原因
func validate(_sim: GameSim) -> String:
	return ""


func commit(_sim: GameSim) -> void:
	pass
