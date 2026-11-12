class_name SpecStaffRules
extends Resource
## 员工规则（§3.5）。

@export var kinds: Array[SpecStaffKind] = []
## 已下架种类 → 当前种类。保留旧定义供存档校验；只允许直接替换到未下架种类。
@export var retired_kinds: Dictionary[String, String] = {}
## 开局员工（种类 id 列表），第一位坐在哪
@export var starting: Array[String] = []
@export var starting_post: String = ""
## 每位开局员工各自的岗位（和 starting 一一对应；空字符串 = 流动）。没写就都用 starting_post
@export var starting_posts: Array[String] = []
## 这家店起始可招募的种类（店长回访等效果往里加，§6.3）
@export var hire_pool: Array[String] = []
## 招人顺序：fewest = 名册里最少的种类优先，同数按 hire_pool 顺序；cycle = 按 hire_order 轮流
@export var hire_rule: String = "fewest"
@export var hire_order: Array[String] = []
## 招人价格：列表（第 n 次招人），或公式 base + step × (名册人数 - 1)
@export var hire_costs: Array[int] = []
@export var hire_cost_base: int = 0
@export var hire_cost_step: int = 0
## 分区：zones 为空 = 不分区；各区上限在阶段里
@export var zones: Array[String] = []
## 前厅区额外上限（买“多一个前台位”）
@export var front_base_slots: int = 1
@export var can_drag: bool = false
## 前台 / 后厨升级轨（每级效果 walk / work / carry / staff_slot）
@export var tracks: Array[SpecUpgradeTrack] = []
## 员工没有可做的事时去哪
@export var home_anchor: String = ""
