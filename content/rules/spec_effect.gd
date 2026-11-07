class_name SpecEffect
extends Resource
## 一条效果（规格 §3.4 / §3.13）。升级的一级、奇遇、员工培养、永久加成都用同一套效果。
## 持续类效果落到加成栈里；一次性效果（grant_gold / customer_wave / unlock_*）执行一次就结束。

## 效果种类（有限枚举，规则层只认这些）：
## speed          机器干活快：秒数 ÷ 值（op=mul 连乘，op=set 直接设成这一级的倍率）
## duration       秒数直接乘值（煎饼摊旧数据 ×0.86/级）
## price          售价倍率；dishes 为空 = 这台机器管的全部菜；price_part 只乘某一部分价格
## batch          批量锅每锅份数（set）
## process_slots  出餐口加工位（set）
## open_flavor    开放加料台的某个口味（target = 物料 id）
## flow           客流倍率
## seats          座位组加座位（target = 座位组 id，add）
## flyer_customers / flyer_cooldown   传单一波人数 / 冷却秒数（set）
## walk / work / carry                员工走路 / 手速 / 搬运（target = 员工区域或员工 id）
## staff_slot     某区域员工上限 +1（target = 区域）
## event_chance   奇遇触发概率倍率（幸运值走这里）
## patience       顾客耐心倍率
## grant_gold     一次性：给金币
## customer_wave  一次性：来一波客人（value = 人数）
## unlock_staff_kind  一次性：开放一个员工种类（target = 种类 id）
## unlock_recipe  一次性：开放一道菜（target = 菜品 id）
## shop_news      一次性：新店消息（target = 关卡表里的店铺 id）
const KINDS := ["speed", "duration", "price", "batch", "process_slots", "open_flavor", "flow", "seats",
	"flyer_customers", "flyer_cooldown", "walk", "work", "carry", "staff_slot", "event_chance", "patience",
	"grant_gold", "customer_wave", "unlock_staff_kind", "unlock_recipe", "shop_news"]
const ONE_SHOT := ["grant_gold", "customer_wave", "unlock_staff_kind", "unlock_recipe", "shop_news"]

@export var kind: String = ""
## 作用对象：机器 id、物料 id、区域、员工 id、座位组 id；空 = 效果所在的那台机器 / 全店
@export var target: String = ""
## price：只作用在这些菜上；空 = 机器的默认菜品范围
@export var dishes: Array[String] = []
## price：只乘菜价里的这一部分（DishSpec.price_parts 的键）；空 = 整道菜
@export var price_part: String = ""
## mul = 乘到当前值上；add = 加；set = 这一级起直接等于 value
@export var op: String = "mul"
@export var value: float = 1.0


static func make(effect_kind: String, effect_op: String, effect_value: float, effect_target := "") -> SpecEffect:
	var effect := SpecEffect.new()
	effect.kind = effect_kind
	effect.op = effect_op
	effect.value = effect_value
	effect.target = effect_target
	return effect


func one_shot() -> bool:
	return kind in ONE_SHOT
