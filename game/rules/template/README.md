# 公共店铺能力核心（迁移中）

本目录属于 `2026-11-12-unified-shop-template-design.md` 的实施。正式三店尚未切换；不能将这些模块的测试通过等同于正式店行为已经统一。

## 唯一所有权

| 模块 | 所有权 |
|---|---|
| `inventory.gd` | 物品lot、预留claim、归属与守恒；库存汇总由查询派生 |
| `bundle_transfers.gd` | 引用普通搬运claim，原子预留/交付/返还整组；不保存第二份数量 |
| `machines.gd` | 机器阶段和时钟；加工扣料与产出委托库存事务 |
| `capability_runner.gd` / `action_context.gd` | 员工请求、动作程序和调用公共移动；不持有第二份库存 |
| `compiler.gd` | 严格编译配置，生成无脚本回调的定义 |
| `runtime.gd` | 生产份数、依赖完成事实、公共生产/服务推进入口及恢复 |
| `restock.gd` | 共享补货的批次引用和请求；不独立搬运或修改库存 |
| `orders.gd` | 排队、订单明细、生产绑定、交付凭据、付款、座位租约、用餐和离店事实；钱与销量仍使用公共RuleSales |
| `customers.gd` | 顾客位置、路径和真实抵达；不含三种经营模式的分支 |
| `service.gd` / `service_policy.gd` | 编译并组合接单、生产请求、备餐、携带、送达、座位、用餐和真实离店；只保存履约引用和顾客动作时钟 |
| `view_frame.gd` | 从权威状态生成只读UI/手持/显式展示数据 |

当前生产运行器的owner提供名册、导航、共享属性与修正器接口。受控测试使用既有ShopRules提供这些接口，新核心不读取它的旧库存/serve业务账本。正式切换时要移除旧账本与执行路径，不能长期并行保存两份权威状态。

## 库存契约

```text
reserve → 原库存保持，来源和目标被预留，手持为空
pickup  → 到位动作完成后进入手持，来源空间保留用于取消返还
drop    → 到位动作完成后进入目标，手持与返还空间释放
cancel  → 释放预留；已拿实物回到原位置/归属；无限源领用销账
```

- `reserve_transfer(worker,...)`与`reserve_actor_transfer("customer:<id>",...)`使用同一个实现。员工ID与顾客ID有不同命名空间。
- `hand:<staff id>`、`hand@customer:<id>`是受管理容器，不能通过seed、普通搬运或加工伪造/转移手持。
- 已拿材料继续由原claim占用，不能同时交给另一个任务加工。
- `reserve_operation/complete_operation`原子处理多输入配方。设备内建无限原料也走同一事务，既不生成散落物品，也不虚构员工取料。
- 所有视图默认不画等待库存。`stock_showcase`必须声明展示端口；顾客手持使用同一携带者投影。
- `reserve_bundle(actor,entries,capacity)`整组精确预留；缺一件或容量不足不留半份预留。员工逐站`pickup_bundle_part`，顾客同点`pickup_bundle`；全部拿齐才可整组`drop_bundle`。子claim不能绕过整组生命周期；中途取消一次性归还已取物并释放未取物。
- `CapabilityRunner.transfer_bundle`通过真实RuleActions逐站取货再统一交付；每站可声明`pickup_seconds`，员工手速统一应用。`interact(...,"admit",guest)`通过公共移动/操作计时产生一次完成或取消结果，不接收店铺脚本回调。

## 模板结构

`SpecShopTemplate`声明`places/machines/recipes/restocks/service/hop_seconds`。配方的source/process节点以显式生产者绑定输入；同一编译器处理线性和合流。机器profile声明人工加工、装卸、搅拌和槽位，不提供任意回调。未知能力、无效数量、缺端口、循环和产量不足都会报错。

规则时长复用`RuleNumbers.capability_seconds`：机器修正与工序fixed数据决定基础工时，员工实际手速由人工阶段应用。自动锅和人工机器不能各自另算升级效果。

## 公共服务配置（受控模板已接通）

`service`为空的模板只运行生产；声明后由同一个`Runtime.step`组合整个服务周期：

```gdscript
service = {
    "menu": {"dish_id": "recipe_id"},
    "admission": "employee", "admission_port": "front", "admission_seconds": 0.6,
    "admission_roles": ["staff"],
    "delivery": "self_pickup", "pickup": "pass", "customer_capacity": 2,
    "delivery_roles": ["staff"],
    "seats": {"seat:dine/0": "table_staff_port"}, "eat_seconds": 3.0,
    "orders": {"pay_at": "on_deliver", "queue_release": "after_take"}
}
```

- 菜单引用现有菜品价格接口和模板配方；报价在真正接单时获取。当前服务配方每份最终出品数量必须为1；机器内部仍可批量加工。不能静默把多件出品算成一件销售。
- `automatic/employee`只决定是否由员工在接单端口完成工时。顾客必须实际抵达队首，取消员工接单不能创建订单或收费。
- `counter`声明`handoff_port`，顾客到达`pickup`后员工可分批交付；最后一份交付后按订单策略结算。`table`使用具名座位和员工桌边端口，必须等顾客真正就座。
- `self_pickup`由员工备齐取餐点库存，顾客实际到位并完成取货工时后整单拿起，携带到具名座位/出口再放下。顾客携餐时不再为同一订单重复备货；取餐点已有的成品可以直接使用，无需虚构员工搬运。
- 座位目前从接单持有至顾客真正离店，满座会保留顾客在队列等候。用餐结束逐生产份数通过公共加工事务消耗食物，保留可恢复的消耗凭据。
- 员工资格与实际移动使用同一`access_profile`；未配置角色名单时可由所有部署员工承担相应服务任务。完整岗位亲和、连续工位持有和全生产调度资格仍待补齐。
- 当前通过`Runtime.arrive([{dish,qty},...])`显式输入客流；固定/随机到店时钟、菜单抽取和正式升级门槛尚未组合进来。

## 保存边界

快照包含无对象引用的状态；恢复先验证全部候选再采用。生产图、机器、库存、员工动作、路径、权限、补货引用和交付凭据各有交叉校验。

服务快照同时交叉校验生产份数绑定、接单员工租约、履约整组、顾客手持、目标与座位、用餐消耗凭据和动态顾客容器。接单、生产、员工取货、顾客携带、用餐五个阶段的恢复与连续运行对照一致。失败采用不修改原员工或服务。

这是开发期的新内部格式，尚未写入正式玩家存档。正式ShopSave仍需旧三种模式的转换、原字节备份、全局财务/名册整合和内容采用。公共钱包仍只由外层持有一次，服务快照不复制钱包；测试明确独立恢复外层财务后再恢复服务，不能将其当成已完成玩家存档迁移。

## 后续接入要求

- 顾客routing/座位/用餐/离店已在公共服务组合中接通；正式三店仍需接入这一条运行路径，并补齐客流和制作门槛，不能恢复三个顾客控制器。
- 员工派活还需完整区域资格、订单跟随、连续工序占用与跨份数的兼容搬运合并。
- 自取必须调用公共携带与交付操作；不能将顾客当员工或直接把物品改到餐桌。
- 正式场景、旧档、内容刷新与高负载经营回放验收之前，本目录不代表可交付的全店迁移。
