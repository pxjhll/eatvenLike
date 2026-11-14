# T06 可组合原子动作 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially. 不创建worktree、其他聊天或代理。

**Goal:** 提供可保存、可等待、可取消的动作生命周期，组合现有移动/拿取/操作/搬运/放下/等待能力，并用真实业务验证物品与预留守恒。

**Architecture:** RuleActions推进调用方拥有的顺序动作记录，不解释脚本或生产图。ActionContext提供明确的预留、前置条件、开始、推进、提交和取消接口，状态只保存数据。ServeActionContext把现有job映射成动作，复用RuleMovement和ServeFlow的实物/工序提交；legacy不启用新执行器，奶茶完整轨迹必须保持一致。

**Tech Stack:** Godot4.6.3 / GDScript / Dictionary / Resource / PowerShell。

**Spec:** docs/superpowers/specs/2026-11-11-modular-shop-system.md。

## Global Constraints

- 从已推送7581f15继续，工作目录D:/Tes/eatventure；保留26项原有用户文件，不自动提交T06。
- 所有运行设置隔离APPDATA到_work/shop_modularity/phase-b/actions/userdata/<runner>。
- 不改正式店数据、PNG、员工属性、菜单和经济数值；不重录A阶段基线。
- T07负责生产依赖与交付组合。本任务只提供顺序动作和真实业务适配，不创建通用脚本语言、条件表达式、分支调度器或新正式菜品。
- 运动仍调用ShopRules.begin_move/advance_move。空路径等待，动作不能靠时间推测抵达。
- 库存、订单和预留保留唯一所有者。动作lease只引用已有业务预留，不复制库存账本。
- 内核每tick最多提交一个动作，开始下一步时不再消耗该tick时间；零时长动作也不能重复执行或无限循环。

## 接口与文件

- 新增game/rules/rule_actions.gd：KINDS=[move,pickup,operate,transport,drop,wait]；start(worker,steps,context)->String；tick(worker,dt,context)->bool；cancel(worker,context)->bool；validate(program)->String。
- worker.action={version:1,steps:Array,index:int,status:String,reason:String,started:bool,lease:Dictionary}。status为ready/running/blocked/completed/cancelled。步骤为{kind:String,target:String,seconds:float,label:String,data:Dictionary}，每个字段普通数据；未知kind、非有限时间和对象值拒绝。
- 新增game/rules/action_context.gd：reserve(worker,steps)->Dictionary返回{error,lease}；ready(worker,step)->String返回空串或阻塞原因；enter(worker,step)->void；advance(worker,step,dt)->bool；commit(worker,step)->void；cancel(worker,lease)->void。预留失败必须原子；ready在开始和每tick执行；commit在ready成功后必须是可完成的规则事务。业务final commit释放原预留；取消只补偿未完成业务。
- RuleActions提交前先推进游标，防止同步事件存档重放同一效果。commit后检查当前worker.action是否仍为原记录，回调替换/取消任务后不进入旧计划下一步。
- 新增game/rules/serve_action_context.gd：现有take/work/home/搬运job编译为原子动作。移动→操作、移动→拿取→搬运→放下；独立wait能力由上下文解释显式条件键，内核不解释条件。
- SpecDispatch.action_version=0为兼容；1首轮接入serve且要求motion_version=1。其他业务仍复用既有WorkerState计时能力；新执行器适配范围显式校验，不假称已迁移三店。v0指纹忽略新增未启用字段，v1纳入指纹。
- ServeFlow._work/_claim/_idle仅在显式启用时使用执行器；提取_pick_good复用原取料效果；_end移除完成动作；cancel复用原取消并移除动作。legacy的非空路径、时间边界、提交事件顺序不变。
- 新增game/rules/action_validator.gd：验证版本、步骤、游标、状态与真实job/携带物的对应关系。活动记录必须绑定当前员工及job；已取消/完成记录不能当成活动job。旧档启用后缺少action时，从原job.stage、路径、剩余action_left重建，不能重新拿取或重置计时。
- ShopSave对未来action版本保护文件；第一次替换缺少动作字段的活动旧档使用现有pre-content备份。新字段只在启用时出现，不改奶茶旧状态形状。
- ShopView输出脱离的动作进度摘要；表现只读已有worker.phase、walking和carry，不执行规则提交。

## Task 1：生命周期与最小真实上下文夹具

- [x] 写tests/test_actor_actions.gd和tests/fixtures/action_context.gd。夹具拥有真实简单库存、携带与工位预留，复用T05移动；禁止用mock调用次数替代物品结果。
- [x] 缺模块时使用存在性断言红灯；测试前置未满足不计时、恢复后开始、一次提交、取消补偿一次，以及计划/状态可独立保存。

```gdscript
var error = actions.start(worker,[step("pickup"),step("transport"),step("drop")],context)
check_eq(error,"","plan accepted")
context.available = false
actions.tick(worker,0.1,context)
check_eq(context.stock,1,"blocked pickup does not consume inventory")
```

- [x] 实现RuleActions与ActionContext。验证计划先于预留；host/context不进入保存状态。无效dt不推进；每tick最多提交一次；回调替换计划有身份检查。
- [x] 测试六种动作的实际结果、缺料等待、取消前后物品总量、完成后再次tick/取消，以及大dt不会跳过动作。

## Task 2：真实serve适配与兼容

- [x] 使用movement_shop的深拷贝显式启用动作版本，先观察真实任务出现缺失动作的红灯。
- [x] 编译既有job并接入上下文：移动仍由T05负责；操作时长在进入时按现有数值计算；拿取/放下复用实物提交；取消复用原预留释放。
- [x] 保留旧库存提交所有者；只提取所需最小函数。旧serve计时使用WorkerState.tick_handoff_action，保持原浮点边界。
- [x] 测试真实开店销售、阻路、缺料、坐班/流动、取消在拿取前/拿取后、物品身份与预留守恒。动作不能越过客户抵达前置。
- [x] 为配置能力、原奶茶指纹与原轨迹运行专项；不在正式店打开action_version。

## Task 3：保存、事件和验收

- [x] 完整动作快照读回续跑一致；覆盖move/pickup/transport/drop/operate与阻塞状态。修改读模型不能污染动作。
- [x] 旧活动档缺action时按阶段重建：已拿取不重拿、剩余工时不归零、实际位置不变。未来版本拒绝覆盖且旧文件有备份。
- [x] 业务事件回调中可保存合法动作状态；完成游标先提交，取消/换岗回调不能启动旧计划后继。
- [x] 注册规则套件；运行全量规则、T05运动显示、原三店GUI、角色尺度、四店配置与布局。扫描运行错误和退出泄漏。
- [x] 更新docs/qa/composable-actor-actions.md、接入说明、总表和T07前置接口；核对26项用户文件与7项冻结数据哈希。

专项入口放_work，沿用run_all的test_*、cleanup和ErrorCounter规则。通过后本阶段留在工作区；已发布T04/T05不回退或重写。

## 执行结果

T06完成：18项动作专项、424项规则、38项真实角色动作显示通过；T05运动显示417项、三店界面84/88/33项、角色尺度76项、四店契约及两店布局检查通过。26项原有用户文件与7项冻结数据哈希不变，无正式店数据或PNG变更。T05提交7581f15已推送，T06留在工作区；下一项T07。详见docs/qa/composable-actor-actions.md。
