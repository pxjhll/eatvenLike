class_name SpecGuideStep
extends Resource
## 引导一步（§6.3）：什么时候开始、指哪里、说什么、什么时候结束，全写在数据里；界面的引导播放器只认这些字段。
## 条件是短字符串（多个条件写成数组 = 都要满足；一条里用 & 连起来也是“都要满足”），播放器认识的条件：
##   open / !open                 开张了没有
##   seen:<步骤> / !seen:<步骤>   看过某一步没有
##   page:shop、page:<页>、page:station:<机器>、!page:shop
##   sold:0                       一杯都没卖
##   staff>=opening / staff<opening   上岗人数够不够开张人数（min(2, 名额)）
##   waiting                      名册里有没派出去的人
##   can_hire / !can_hire         现在付得起招人
##   can_staff                    有人可派或者付得起招人
##   stage>=N / stage<N           阶段
##   affordable:<机器>            这台机器现在能解锁
##   box:<物料>                   正在等买这一箱，box_affordable 现在买得起
##   no_box                       没有待买的原料箱
##   kitchen_staff:0 / kitchen_staff>0
##   room / !room                 还有员工名额
##   complete                     完店
##   hired                        比这一步开始时多了人
##   angry:<原因>                 有客人等急了，原因 seats / staff / machine（按这个顺序判断）
## 文案和条件里的 {键} 换成 params 里的值，或播放器算的值：{line} 阶段名、{cost}、{box} 原料箱名、{machine} 原料箱对应的机器、{slow} 拖后腿的机器名。

@export var id: String = ""
## 触发：start = 按顺序看条件；angry = 有客人等急了以后才看（每次等急只看一次）；next = 只由上一步接过来
@export var trigger: String = "start"
## 开始条件（都满足）
@export var when: Array[String] = []
## 满足其中一条就结束（记为看过）
@export var done_when: Array[String] = []
## 满足其中一条就直接记为看过、不弹（读到已经玩过这段的存档）
@export var seen_when: Array[String] = []
## 只在店铺页开始（默认是；开场引导不用）
@export var shop_page_only: bool = true
## 提示：按顺序取第一条满足 if 的：{if: [条件], at: 指向, text: 说的话}
##   at：frame:<机器>（虚线框）、station:<机器>（机器本身，slow = 拖后腿的那台）、area:<锚点>、
##       ui:<界面零件>（tab:staff、hire、deploy、unlock、material:<物料>、chip:seats）
##   go: 页面（先回到这一页）、wait: true（先不显示）、back: true（先退出，下次再提示）、then: 步骤（换成另一步）
##   select_waiting: true（在员工页时选中名册里没派出去的那位）
##   pause: false（不压暗、不停店，只指一下）
@export var cues: Array[Dictionary] = []
## 填进文案和条件的值
@export var params: Dictionary = {}
## 提示气泡上的“跳过”键
@export var skip_label: String = "以后再说"
## 跳过时一起记为看过的步骤
@export var skip_marks: Array[String] = []
## 结束时一起记为看过的步骤
@export var finish_marks: Array[String] = []
## 卡片型（card）：标题、插画、奖牌、几行说明、统计、备注、按钮；card 确认后接着哪一步（next）
@export var style: String = "hint"
@export var title: String = ""
@export var title_size: int = 40
@export var art: String = ""
@export var medal: String = ""
@export var rows: Array = []
## [[图标, 小标题, 值键]]，值键：time 用时、revenue 总营业额
@export var stats: Array = []
@export_multiline var text: String = ""
@export var confirm_label: String = "知道了"
@export var cancel_label: String = ""
## 确认键另外做的事：leave = 打开结店总结去下一家店（去不了时只留取消键当主按钮）
@export var confirm_action: String = ""
@export var next: String = ""
## 说话的角色（默认三花猫店长）
@export var speaker: String = "manager"
