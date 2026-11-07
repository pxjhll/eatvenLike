class_name SpecEvent
extends Resource
## 奇遇（§3.13，预留，规则层还不播放）：投资人、网红、店长回访……

@export var id: String = ""
@export var display_name: String = ""
## 触发：听哪个广播、基础概率（实际概率经加成栈 event_chance，幸运值叠在这里）、冷却
@export var trigger: String = ""
@export var condition: Dictionary = {}
@export var chance: float = 0.0
@export var cooldown: float = 0.0
## 只触发一次（店长带新员工回来）
@export var once: bool = false
## 玩家选项：空 = 直接生效；否则 [{"label": "接受", "cost": 0}, {"label": "拒绝"}]
@export var choices: Array[Dictionary] = []
@export var effects: Array[SpecEffect] = []
@export var duration: float = 0.0
@export var speaker: String = ""
@export_multiline var card_text: String = ""
