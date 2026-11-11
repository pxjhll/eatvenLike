# 店铺与员工模块化任务总表

> 后续执行采用 superpowers:executing-plans 按任务顺序推进。本表只安排依赖、交付和验收，不授权创建其他聊天或启动并行代理。

**Goal:** 以奶茶店为基准，建立能复用、组合和扩展的店铺与员工制作体系。

**Architecture:** 从现有实现提取公共定义、运动、动作和场景模块；业务策略与生产依赖通过数据组合这些能力。使用现有内容校验、空间导出与存档机制逐步迁移三家店。

**Tech Stack:** Godot 4 / GDScript / Resource / TSCN / FigCraft / PowerShell。

**Spec:** `docs/superpowers/specs/2026-11-11-modular-shop-system.md`。

## Global Constraints

- 当前仓库D:/Tes/eatventure，基线9bc1b20；执行开始时重查HEAD、分支和本地改动，不能自动重置到该提交。
- 保留用户已有改动；制作源稿与运行证据留在_work。此任务安排不创建worktree、其他聊天或代理。
- 奶茶店是基础表现和行为蓝本；未经对应能力任务验收，不将新实现切到所有店。
- 美术工作先读docs/art/scene-art-production-rules.md；视觉确认与规则验收分开。
- 测试显式设置隔离APPDATA，禁止读取或改写真实玩家进度。
- 不把例汤、合流夹具扩展成正式新菜单。公共系统不按店铺ID分支。
- 不用提高基础走速来达到关卡总时长；经济节奏在角色统一后单独标定。
- 每项交付包含实现、针对性验证、兼容证据和必要说明；公共接口变更先同步到依赖任务计划。

## 顺序与状态

状态：T01–T03已完成，见docs/qa/tea-modularity-baseline.md。T04已完成，见docs/qa/shared-actor-presentation.md。T05公共能力与三类业务夹具已完成，见docs/qa/shared-movement.md；T06生命周期与首个真实业务适配已完成，见docs/qa/composable-actor-actions.md。T07生产依赖与整单交付能力已完成，见docs/qa/production-and-delivery-composition.md。T08模块、完整空间导出与灰盒样板已在本地完成，见docs/qa/editable-scene-modules.md。正式店启用仍按T09/T10迁移。T09–T12尚未开始。

| 阶段 | 任务 | 优先级 | 依赖 | 交付与独立验收 |
|---|---|---|---|---|
| A 奶茶基准 | T01 冻结奶茶行为与表现基线 | P0 | 无 | 角色表、确定性规则轨迹、真实界面截图、存档样本；必须有销售与行走样本 |
| A 奶茶基准 | T02 提取奶茶员工共享定义 | P0 | T01 | 六种员工使用共享SpecStaffKind资源，奶茶改为引用；原行为、内容指纹保持一致 |
| A 奶茶基准 | T03 验证定义提取的存档兼容 | P0 | T02 | 老奶茶档加载/继续/重存一致，属性刷新不丢升级、岗位或进度；不先迁移其他店 |
| B 公共行为 | T04 统一逻辑尺度与角色表现配置 | P0 | T01,T02 | 统一员工128/顾客110和镜头尺度；角色在同视口跨店大小一致，原PNG尺寸不变 |
| B 公共行为 | T05 共用移动与抵达协议 | P0 | T03,T04 | 员工和顾客消费同一导航事实；客区/后厨权限、半径避障、无路等待；各倍速与暂停一致 |
| B 公共行为 | T06 提取可组合原子动作 | P0 | T05 | 移动/拿取/操作/搬运/放下/等待等动作有前置、完成、取消、预留和保存协议；奶茶旧流程保持稳定 |
| C 流程扩展 | T07 整理生产依赖与交付组合 | P1 | T06 | 复用现有输入输出依赖；线性、多路合流、多物品交付夹具通过；旧流程不启用新能力时行为不变 |
| D 场景模块 | T08 建立可编辑场景模块与空间导出 | P0 | T04,T05,T06 | 工位、柜台、桌椅、入口队列模块；占地与端口随模块移动，校验与导出一致 |
| E 店铺迁移 | T09 第三店作为完整接入样板 | P0 | T03,T07,T08 | 接回全局角色和公共行为，补通道/端口/占地；复现的穿物、提前接单消失，旧档可延续 |
| E 店铺迁移 | T10 迁移煎饼摊并完成三店基准一致性 | P1 | T09 | 尺寸与初始属性统一，保留其业务配置；记录有意改变的经营节奏和更新后的回归基准 |
| F 制作工具 | T11 固化原画接入和新增员工模板 | P1 | T08,T09 | 资产/模块/玩法映射表、原画拆分规范、角色动作映射、制作说明；用演示店/员工证明只增配置可接入 |
| F 交付门槛 | T12 加入统一验收、CI与节奏报告 | P1 | T07,T10,T11 | 三店与扩展夹具共同验收；路径覆盖、动作抵达、保存恢复、同视口尺寸、经营指标均有证据 |

执行主线：T01 → T02 → T03 → T04 → T05 → T06 → T07 → T08 → T09 → T10 → T11 → T12。表中依赖是最低前置条件，当前按主线顺序执行，不安排多人同时修改共享运行文件。

## 文件与责任边界

| 任务 | 主要现有文件 | 新增交付的责任 |
|---|---|---|
| T01 | tests/test_tea_rules.gd、tests/render_shop_tea.gd、tests/test_content_save.gd | 奶茶专用冻结轨迹和基线清单 |
| T02 | content/shops/tea/shop.tres、content/rules/spec_staff_kind.gd | content/characters/staff/六个共享资源；只提取定义 |
| T03 | game/rules/shop_save.gd、shop_content_contract.gd、shop_rules.gd | 测试已有兼容机制；确有缺口才修改对应最小边界 |
| T04 | presentation/characters/character_library.gd、presentation/shop/shop_actor.gd、shop_play.gd | 全局表现配置与逻辑尺度换算；店铺不能私配基础值 |
| T05 | game/rules/rule_nav.gd、rule_grid.gd、worker_state.gd、serve_flow.gd；presentation/shop/shop_play.gd、shop_dining.gd | 公共移动状态、路径与抵达快照，取消视图独立业务运动 |
| T06 | game/rules/shop_rules.gd、serve_flow.gd、worker_state.gd | 明确动作生命周期接口；业务决定动作组合，不操作表现节点 |
| T07 | content/rules/spec_step.gd、game/rules/serve_flow.gd、fulfillment_plan.gd、inventory相关模块 | 稳定的依赖与交付组合契约，不重复造现有依赖系统 |
| T08 | presentation/shop/shop_anchors.gd、shop_scene_contract.gd、tools/sync_shop_layouts.gd | presentation/shop/modules/及ShopTemplate；每模块拥有本地端口与占地 |
| T09,T10 | 三店shop.tres、艺术TSCN、tools/build_stirfry_shop.gd | 店铺只引用能力和模块；生成工具遵守相同定义来源 |
| T11 | docs/art/scene-art-production-rules.md、docs/shop-onboarding.md | 新增店铺/员工说明、模块映射清单、演示夹具；源稿在_work |
| T12 | tools/validate_shops.gd、tests/run_all.gd、.github/workflows/tests.yml | 统一制作门槛与三店回归、经营节奏报告 |

## 阶段出口

- [x] A完成：奶茶既有体验被冻结，共享员工定义替换未改变奶茶结果；旧档仍能继续。
- [x] B公共能力完成：共享尺寸、规则运动和动作生命周期可组合，新协议画面不独立判断到达；正式店迁移在E阶段完成。
- [ ] C完成：新能力夹具只增加数据或实现新增能力；未启用它的旧流程无变化。
- [ ] D完成：移动工位实例时占地、端口、交互区一并移动；界面可显示空间错误。
- [ ] E完成：第三店和煎饼摊引用统一底座，旧档迁移受控，行为调整记录清楚。
- [ ] F完成：拿到原画能按规范列清资产与模块；新增普通员工和演示店无需改公共控制代码。

## 范围控制

T01–T03的详细步骤位于 `2026-11-11-tea-baseline-and-shared-staff.md`。后续每阶段单独形成执行计划，依据已交付接口确定精确签名、资源结构和状态版本，不能把本表的责任划分当作已经实现的API。

T07选择真实业务的最小扩展夹具，覆盖组合与合流的兼容契约；生产菜单、关卡扩容和新员工美术不在本轮架构改造范围。T12先输出经济影响，未经对应任务授权不为恢复旧完店分钟数擅自改变价格和奖励。

## 当前待办

- [x] T01：原奶茶基线与合成旧档已冻结。
- [x] T02：六种共享员工资源已提取，奶茶内容与轨迹不变。
- [x] T03：旧档加载/续跑/重存与基础属性刷新验证完成，A阶段交付。

下一个待执行任务：T09，第三店完整接入样板。T06提交7eaab3c、T07提交87cb87f均已按授权推送；T08保留在工作区，未自动提交。

- [x] T04：共享角色表现配置、原生单位换算、三店同视口角色尺度及原奶茶画面对照通过。
- [x] T05：运动协议v1、规则顾客、权限/脚底占地、阻路恢复、存档与纯快照显示通过；保留legacy正式店供后续迁移。
- [x] T06：六类原子动作、生命周期与业务lease、真实serve适配、等待插入、取消及旧档/事件快照通过；首轮新执行器不开放给single/handoff。
- [x] T07：原输入输出依赖图、乱序并行合流、多取餐点整单预留/交付/取消、版本保护及旧档备份通过；444项规则、47项交付角色显示验证通过，正式店未启用。
- [x] T08：五类可编辑模块、ShopTemplate、只读锚点投影与完整空间导出完成；459项规则、25项完整界面、26项真实窗口检查通过，正式店布局未改。

T06接口前置：员工使用ShopRules.begin_move(worker,goal,phase)和advance_move(worker,dt)，客户抵达使用CustomerMovement.ready(rules,key)。空路径始终表示请求待完成；取消必须清理motion。动作组合消费这些事实，不另算走路时间或直接移动表现节点。v1的角色区域和顾客端口见2026-11-11-shared-movement.md。

T07接口前置：RuleActions.start/tick/cancel/validate，ActionContext.reserve/ready/enter/advance/commit/cancel；现有ServeFlow仍是实物和订单唯一所有者。先复用consumes/produces、unit和goods依赖，不另建库存账本。当前顺序步骤是数据，不支持条件脚本或分支解释器；新交付组合需明确自己的业务预留与取消边界。

T08接口前置：ProductionPlan.compile只读取配方；flow_version=1按原工序索引保存签名。模块以稳定station ID导出端口和占地，delivery_points引用pickup工位。须同时导出员工/顾客端口和权限区域，保持T05坐标单位与角色脚底半径；表现模块移动不改变配方索引、实物账本或动作提交方式。

T09接口前置：模块根module_id/station_id及本地Anchors/Nav映射见presentation/shop/modules/README.md；Anchors.module_version=1与运动1完整空间显式导出，不能只开启flag。ShopAnchors.export_layout返回{layout,errors}，错误时layout=null；sync工具通过--shop/--campaign指定目标，--check不写。当前样板桌椅预留整套占地，不能把未显示椅子当作可走区域。正式第三店使用当前已接入美术，未确认的FigCraft分层稿不直接替换；须验证角色全局定义、端口/权限、旧档迁移与真实节奏，不能仅复制灰盒布局。
