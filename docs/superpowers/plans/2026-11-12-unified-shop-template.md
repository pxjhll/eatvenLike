# 统一店铺模板实施计划

> **For agentic workers:** 使用 superpowers:executing-plans 在当前会话顺序执行。用户约束优先：不启动代理、不创建其他聊天或worktree。每个任务按失败用例、最小实现、回归和证据推进，不自动提交或推送。

**Goal:** 三家正式店、制作示例与扩展夹具通过公共能力组合运行，基础行为以奶茶店为准。

**Architecture:** 保留角色、运动、动作、场景、命令和数值底座；先建立权威库存事务，再统一机器、生产、派活、顾客、快照与存档。迁移开发期新核心与旧实现隔离对照；最终正式入口移除经营模式分流。

**Tech Stack:** Godot 4 / GDScript / Resource / TSCN / PowerShell / Python标准库。

**Spec:** `docs/superpowers/specs/2026-11-12-unified-shop-template-design.md`。

## Global Constraints

- 当前目录 `D:/Tes/eatventure`，当前分支 `codex/tea-baseline-shared-staff`；不重置已有改动。
- 原26个用户文件、5个奶茶冻结文件、10张用户餐品PNG保持不变。开工时41份hash存于 `_work/unified_shop_template_20261112/preserved-files.json`。
- 先局内行为，后经济标定；不为通过测试删除旧完店门槛，不改原冻结文件。
- 验证设置隔离APPDATA；生命周期目录包含 `session-lifecycle-userdata`。
- 每阶段通过不代表正式三店已经迁移。状态报告同时列出新核心是否接入正式路径。

## 执行命令

```powershell
$env:APPDATA='D:/Tes/eatventure/_work/unified_shop_template_20261112/session-lifecycle-userdata'
$engine='D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $engine --headless --path D:/Tes/eatventure -s tests/run_suite.gd -- tests/test_template_inventory.gd
& $engine --headless --path D:/Tes/eatventure -s tests/run_all.gd
python tools/check_shops.py --help
```

针对性入口统一收集Godot运行错误，错误也计为失败，不能只依赖断言或退出码。

## U01 / U02：公共库存与操作契约

**Files:** 新建 `game/rules/template/inventory.gd`、`tests/test_template_inventory.gd`、`tests/run_suite.gd`；接入 `tests/run_all.gd`。

**Interfaces:** `Inventory`持有唯一lot/claim状态；`configure(place,capacity,infinite_items)`声明容器，`seed`记录初始/外部产物，`reserve_transfer`按员工容量和预留规划搬运，`pickup/drop/cancel`提交操作，`reserve_operation/complete_operation`原子处理配方，`quantity/claim/snapshot/restore/audit`供运行器和视图使用。返回结果统一带`error`，事务失败保持状态不变。

- [x] 失败用例：同一操作在三个不同容器/归属配置下保持相同的预留、手持、投料结果；拿取前手持量0、完成后2、放下后0。
- [x] 失败用例：来源和目标不能超额预留，员工capacity=2时不能搬3件，已被订单占用的材料不能借给另一订单。
- [x] 失败用例：取消预留不造物；取消已拿物归还来源，保留返还容量；无限源取消销账；重复提交/取消不能复制物品。
- [x] 失败用例：多输入操作缺一项就不能预留；完成时输入一次性消耗、输出一次性生成；加工取消不丢料。
- [x] 失败用例：中途保存/恢复后相同操作只提交一次；破坏数量、归属、预留和身份的状态恢复被拒绝，原运行状态不变。
- [x] 实现上述共同操作；不为每种经营模式增加后端。不添加第二份库存统计账本，UI汇总由lot查询派生。
- [x] 跑新专项与原规则套件；保存日志并标明此时是否已接入正式店。

## U03：机器时钟与生产依赖

**Files:** 新建 `game/rules/template/machines.gd`、`tests/test_template_machines.gd`；扩展 `game/rules/production_plan.gd`。

**Interfaces:** `Machines.start(inventory,request)`预留输入和输出空间；`advance(dt)`只推进计时；人工事件和自动事件都经库存事务完成。统一状态暴露`phase/duration/remaining/input/processing/output/occupant`。编译输入仍为`SpecStep.consumes/produces`。

- [ ] 人工、自动、批量、中途搅拌、人工装卸、封装和多输入合流写独立失败用例。
- [ ] 相同机器条件下暂停不推进；阻塞不产出；员工离岗和取消遵守相同释放规则；恢复不重复投料。
- [ ] 扩展现有编译器覆盖已有全部设备；缺输入、重复生产者、循环、错误能力/端口明确报错。
- [ ] 完成统一机器快照和专项回归，保留旧实现作为隔离对照。

## U04：模板编译、派活、顾客和履约

**Files:** 新建 `content/rules/spec_shop_template.gd`、`game/rules/template/compiler.gd`、`game/rules/template/runtime.gd`、`game/rules/template/dispatch.gd`、`game/rules/template/orders.gd`、`game/rules/template/action_context.gd` 与对应专项。

**Interfaces:** `Compiler.compile(shop)`返回`definition/errors`；`Runtime`持有统一库存、机器、顾客、订单和任务状态；`Runtime.step(rules,dt)`是唯一推进入口。`Dispatch`产生/排序标准能力任务；`ActionContext`将标准任务交给既有`RuleActions`，所有业务副作用调用公共事务。

- [ ] 先用三个最小模板证明共用同一运行入口和操作；再覆盖现有设备与真实配方。
- [ ] 订单归属、连续工作、坐班、区域协作和等待协助以数据策略组合；不能复制三套派活器。
- [ ] 公共顾客/订单状态覆盖固定与随机客流、耐心、离队、自取、柜台交付、送桌、附加品、整单齐备和付款；只引用既有公共数值和结算计算。
- [ ] 例汤和两线合流夹具各在两个模板组合复用，并证明未启用时旧能力不变化。
- [ ] 校验未使用字段、缺能力、缺端口和无路；失败不回退旧经营循环。

## U05：统一快照和显示

**Files:** `game/rules/shop_view.gd`、`presentation/shop/shop_actor.gd`、`presentation/shop/shop_play.gd`、`game/rules/customer_movement.gd`、`tests/test_stirfry_item_presentation.gd` 和三店界面测试。

- [ ] 正式场景用真实规则状态验证：预留无手持、拿取后显示、投料后清除、机器库存UI正确。
- [ ] 替换“成品必须摆在装盘台上”的旧断言，增加库存等待不生成散落图标的检查。
- [ ] 货架、传送带、台面加工、用餐显示需要显式公共展示能力；同一快照驱动显示与UI，不按经营模式遍历物品。
- [ ] 顾客运动消费统一顾客状态；移除正式运动同步里的三种模式分支。
- [ ] 三店同视口、真实场景、暂停倍速和Web导出检查通过。

## U06：旧状态转换、正式切换、清理旧执行路径

**Files:** `game/rules/shop_rules.gd`、`game/rules/shop_save.gd`、`game/rules/shop_state_validator.gd`、`game/rules/shop_content_contract.gd`、`game/rules/template/legacy_adoption.gd`、正式店/制作示例Resource和迁移测试。

- [ ] 为新运行状态建立版本；逐一测试旧三种模式在取料前后、运输、投料、加工和交付时的转换。
- [ ] 保留ID、现金、升级、库存、归属、订单、岗位、预留、剩余时间和随机状态；验证原字节备份失败时不覆盖原档。
- [ ] 正式资源写出显式模板能力配置；三家店和示例都接入`Runtime.step`。
- [ ] 删除正式可达的旧tick/context/库存副作用分流。旧参考代码仅能用于历史夹具对照。
- [ ] 公共事件回调里存档/召回/读档时事务仍一次性提交；旧档完整会话验收通过。

## U07：制作门禁和总验收

**Files:** `tools/check_shops.py`、`tests/shop_acceptance.json`、制作模板、`docs/shop-capabilities.md` 与新QA报告。

- [ ] 新店与新员工只增加配置和资源即可运行；新增公共能力在两个组合复用。
- [ ] 静态引用门禁检查绕过入口；运行轨迹证明真实调用共同操作。不能以导入公共脚本代替调用证明。
- [ ] 完整规则、场景、窗口、存档、布局、Web清单通过；完店旧门槛单独报告。
- [ ] 对照41份保护hash；列出仍未完成项。全部阶段有证据后才报告“所有行为模板化”。

## 执行状态

2026-11-12：设计已获用户确认，保护清单已记录。公共库存事务、机器生命周期、真实员工动作执行、只读表现帧、模板编译、生产依赖运行器和共享补货已实现。本批增加整组搬运、公共接单动作、座位/用餐/离店事实，并由同一个Runtime组合完整公共服务周期；柜台、自取、送桌由严格配置选择公共能力。新增核心专项现107项（本批32项）全部通过；完整规则回归622项0失败，Web检查通过且source_drift为空，保护文件41/41一致。三种受控服务配置分别持续运行600秒并在300秒恢复，库存与机器审计0失败。证据见 `docs/qa/unified-shop-template.md`。

阶段边界：U01/U02的基础契约与核心已完成首批实现；U03的时钟和事务已接通；U04目前覆盖显式线性/合流生产图、共享补货和公共顾客服务闭环；U05目前覆盖公共帧，不是正式界面切换；U06目前覆盖新核心自身的保存恢复，包含生产和服务交叉验证。固定/随机客流、完整岗位策略、正式配方/旧档转换、正式三店切换与旧循环清理、完整制作门禁均未完成。正式店仍使用原运行路径，不能报告全店已统一。

### 下一批的接口约束

- `Runtime`已创建/推进公共生产与可选Service，Service组合Orders/Customers和公共搬运能力。后续把固定/随机客流、菜单抽取、岗位策略和正式升级条件接入同一入口，不能添加按旧模式选择的三个顾客控制器。
- `Orders`的请求行是`dish/recipe/item/qty`，生产绑定是`unit/qty/delivered`。交付必须由库存中`dropped`状态、目标`guest:<id>`、物品及绑定生产份数共同证明；新履约不能直接设置`delivered`或自行加钱。
- `CapabilityRunner`现执行员工`transfer/operate/bundle/interact`，只允许公共`admit`交互目的，不接收回调。公共整组库存能力引用普通transfer claim；员工逐站取主餐和配餐后交付、顾客同点整单取货都已接通。`hand:<staff id>`和`hand@customer:<id>`是受管理容器；不能通过seed、普通搬运或加工绕过手持租约，也不能将顾客伪装成员工。
- 当前新运行快照覆盖生产、机器、库存、动作、补货和公共服务（订单、顾客、座位、用餐、携带引用）。五阶段续档已与连续运行比较一致；公共金币/升级/名册仍由现有外层持有，测试明确先独立恢复外层财务。正式存档切换必须将它们按所有权整合为一份状态，不重存两份权威数据，也不能直接把新快照塞进旧版本结构。
- 正式切换除了`_tick`，还必须核查菜单、队列、岗位、顾客目标、进度、取消、界面和保存的全部调用路径。不能保留某个新入口内部继续委托旧循环。
- 正式奶茶/煎饼的隐式配方需要显式转换：锅的共享补货、设备内建原料、同设备连续步骤、收尾交接、外带封装和装袋选项都要有公共能力映射。不能为让编译通过丢掉原配方要求。
- 新模板资源接入`SpecShop`时必须同步内容指纹投影：旧模板为空时不改变历史指纹；新模板的工序数量/依赖/输入输出进入结构签名，时长等可刷新项单独处理。不能让未知Resource类型被现有`TYPES`过滤成null，也不能把新配方中的数量全当作可忽略数值。
- 模板内容采用要保留在途动作与剩余工时；不能以正常同版本严格恢复代替内容迁移。新顾客/携带者状态要由订单和履约交叉校验后才能进入正式存档。
