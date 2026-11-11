class_name SpecFulfillment
extends Resource
## Mode contract: game/rules/shop_spec_validator.gd capabilities(); docs/shop-capabilities.md.
## Unused fields must retain their resource defaults; unsupported combinations are rejected.
## 订单履约（§3.2）：一位顾客从进店到离开。菜谱管“怎么做”，这里管“怎么卖”。

## 附加菜：点主菜的顾客有 addon_chance 的概率顺带一份 addon_dish（煎饼摊 30% 豆浆）
@export var addon_dish: String = ""
@export var addon_chance: float = 0.0
## 多菜订单由一人跟单时，附加菜先做（true）还是后做
@export var addon_first: bool = true
## 堂食/外带判定：seat_first = 有空座先坐下点单，没空座且外带开放 → 外带，否则站队堂食；
## single uses takeaway_only; handoff uses seat_first. share is unsupported.
## serve：seat_wait = 前厅送到座位；self_pickup = 客人在出餐口自取整单再入座。
@export var dine_rule: String = "seat_first"
## 外带开放要哪台机器（封口机）
@export var takeaway_station: String = ""
## 谁接单：front = 前厅员工；follower = 空闲员工领队首、未被认领的顾客，一人到底
## Fixed: single=follower; handoff=front.
@export var taker: String = "front"
## 交接：handoff = 后厨放出餐口、前厅递；single = 一人从收钱跟到递餐；
## serve = 前厅接单分座、后厨按配方合流放出餐口、前厅送到座位，就座且整单送齐才开吃（规格 §10，v1.1 草案）
@export var handoff: String = "handoff"
## 收款时机：on_take（接单收钱）/ on_deliver（交付时）
## single supports both; handoff requires on_deliver.
@export var pay_at: String = "on_deliver"
## 计价取整：dish_tenth_carry = 每道菜价保留 1 位小数、金币取整零头累计；order_round = 整单四舍五入
## Fixed: single=order_round; handoff=dish_tenth_carry.
@export var price_rounding: String = "dish_tenth_carry"
## handoff: after_deliver. single: after_take (take action complete).
## after_pay is only an alias for after_take when pay_at=on_take.
@export var leave_queue: String = "after_deliver"
## 堂食吃多久走在阶段里（seat_seconds）；收钱后去哪等：wait_seats = 先坐等位座，没座站等候区
@export var wait_area: String = ""
## 耐心：mood_seconds = 变脸阈值；leave_after > 0 = 这么久没人认领就走；leave_who = 谁会走
@export var mood_seconds: Array[float] = []
@export var seated_patience: float = 1.0
@export var leave_after: float = 0.0
@export var leave_who: String = "none"
## 新菜上菜单后先按 ramp_start 的权重，来 ramp_orders 位客人后到满权重（外带同理）
@export var ramp_start: float = 1.0
@export var ramp_orders: int = 0
## single: fixed (no interval RNG draw) or exponential. handoff: fixed only.
@export var arrival: String = "fixed"
## 送桌店（handoff = serve）：顾客从柜台走到座位的速度（像素/秒）。其他交接方式不用，保持 0
@export var customer_walk: float = 0.0
## 开张后头几位：开张瞬间来几位、第一位隔几秒
@export var opening_customers: int = 0
@export var first_customer_delay: float = 0.0
