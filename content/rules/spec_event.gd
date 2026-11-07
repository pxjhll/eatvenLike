class_name SpecEvent
extends Resource
## 奇遇（§3.13）：投资人、网红、店长回访……规则层 ShopRules 按 trigger 广播掷概率，有 choices 的进卡片队列。
## trigger 可用：tick_second、tick_minute、sale、unlocked、upgraded、hired、stage、completed……（事件总线上的任何广播）
## condition：min_stage（阶段至少）、open（已开张）；其他键 = 广播数据里的同名字段要等于这个值

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
## 卡片和顶栏加成用的图标键
@export var icon: String = ""
