class_name SwitchShopCommand
extends SimCommand
## 换店。校验在店内（ShopProgress 确认店铺已完成），执行在 App 层：
## 写入纪录 → 存档 → 丢弃旧 GameSim → 用下一家 ShopConfig 新建。


func validate(sim: GameSim) -> String:
	return "" if sim.progress.completed else "店铺还没完成"


func commit(_sim: GameSim) -> void:
	assert(false, "SwitchShop 由 App.switch_shop() 执行，不进 GameSim 命令队列")
