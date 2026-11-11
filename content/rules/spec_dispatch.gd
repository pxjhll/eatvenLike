class_name SpecDispatch
extends Resource
## 0 preserves legacy execution. 1 uses composable actions with shared movement.
@export var action_version: int = 0
## Mode contract: game/rules/shop_spec_validator.gd capabilities(); docs/shop-capabilities.md.
## Handoff uses scored dispatch; single follows one order. Unused fields retain defaults.
## 员工调度打分表（§3.6）。分数 = 基础分 + 等待加成（有上限）+ 缺口加成 − 路程。

## Handoff: follow / follow_step / chore / load / load_short / pot_short_bonus
## / serve / stir / topping / to_process / to_rack. Single requires an empty dictionary.
@export var base_scores: Dictionary[String, float] = {}
## 等待加成：每秒加多少、上限
@export var wait_bonus_per_second: float = 0.0
@export var wait_bonus_cap: float = 0.0
## Reserved in both modes: retain zero. Actual shortage scoring uses base_scores.pot_short_bonus.
@export var shortage_bonus: float = 0.0
@export var shortage_per: float = 0.0
@export var shortage_cap: float = 0.0
## 路程扣分：每像素 / 每秒路程扣多少
@export var travel_penalty: float = 0.0
## Fixed mode policy: handoff merges to worker carry; single uses fixed with merge_cap=1.
@export var merge: String = "carry"
@export var merge_cap: int = 1
## 从工序链上已有的现成物品那一步接着做
## Configurable only in handoff; single retains true as an unused default.
@export var resume_from_stock: bool = true
## 在批量锅前等产物时可以接这台锅的杂活
## Fixed true in both modes; false is unsupported.
@export var help_while_waiting: bool = true
## 杂活排在领新单之前（煎饼摊）
## Configurable only in single; handoff retains false.
@export var chores_first: bool = false
## 不在岗的流动员工让出坐班机器那一段（奶茶店：加料段有人坐班时流动员工不碰）
## Fixed true; false does not select an alternative dispatch policy.
@export var leave_seated_segments: bool = true
## 打分 = (基础分 + 每秒能做几份 × throughput_weight − 路程秒 × travel_penalty) × (1 − 疲劳 × fatigue_weight)
@export var throughput_weight: float = 0.0
@export var fatigue_weight: float = 0.0
## 疲劳：干活每秒涨 fatigue_gain，空闲每秒回 fatigue_recover（0–1）
@export var fatigue_gain: float = 0.0
@export var fatigue_recover: float = 0.0
## 搬一趟（拿 + 放）各要几秒手上功夫（不算走路）
@export var hop_seconds: float = 0.0
## 手上的单这么久推不动就放手（秒）
@export var ticket_give_up: float = 0.0
