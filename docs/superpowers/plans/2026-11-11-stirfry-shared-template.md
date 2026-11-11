# T09 第三店共享模板接入 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially. 不创建worktree、其他聊天或代理。

**Goal:** 将正式小炒饭馆接入奶茶共享员工、权威移动与动作，补齐可编辑模块/占地/权限；原经营进度和合法订单可迁移，实际到位后才能操作。

**Architecture:** 保留当前正式美术的图像、位置和外观，用既有模块持有各功能组合的局部端口。双灶、柜台使用一个家具模块的附属station_slots；不复制共用家具。Self-pickup沿用原业务策略，增加显式pickup:<n>顾客等待端口，避免固定散布点落到餐桌内。新店启用motion_version=1、action_version=1，flow_version保持0，不改变正式菜单或引入整单员工配送。

**Tech Stack:** Godot4.6.3 / GDScript / TSCN / Resource / PowerShell。

**Spec:** docs/superpowers/specs/2026-11-11-modular-shop-system.md；总表T09及T08前置接口。

## Global Constraints

- 当前分支codex/tea-baseline-shared-staff。T08已提交b108937，本轮不推送、不自动再提交T09。
- 保留26项用户原文件；奶茶与煎饼正式资源、奶茶冻结基线不改。第三店shop.tres与正式scene为本阶段明确迁移范围，保留原始配置作旧档fixture。
- 不替换PNG、不接入未确认FigCraft分层。家具位置与Visual世界变换保持现状，只重组编辑层级；身体占地与操作/接近端口允许明确校准。
- 全部运行显式隔离APPDATA到_work/shop_modularity/phase-e/userdata；截图和工具留_work，不读真实存档。
- 奶茶已有员工直接引用共享资源；dog采用奶茶均衡档112/1/2，sheep采用力量档88/1/3，登记为独立全局定义，保留两种角色，不按查找失败回退。
- 不为恢复旧完店分钟数提高基础速度、价格或奖励。新旧经济节奏差异以报告列出。
- 不改变已存在v1存档的位置语义。旧直线档首次采用网格时允许显式一次性重定位原非法坐标，并留原字节备份；业务身份、库存、预留、工序、计时不清空。

## Task 1：冻结与模块多工位边界

- [x] 冻结原第三店定义至tests/fixtures/stirfry_modularity/legacy_shop.tres；采集实际旧任务各阶段/顾客状态与节奏，不重录奶茶。
- [x] tests/test_stirfry_migration.gd写正式共享属性/flag红灯和双灶模块红灯。station_slots:Dictionary[String,String]绑定本地槽位到其他station ID；Slot局部Anchors/Slots/<key>、SlotDrops/<key>、Nav/Slots/<key>/Work/Post、Visual/Slots/<key>。
- [x] ModuleSpace/ModuleLayout/SceneContract扩展附属端口、解锁显示和引用检查；主工位与槽位共同持有一个完整家具，不创建嵌套模块或重复占地。
- [x] 新增Nav/Customers/Pickup（根）或Nav/Pickup（模块）的连续编号端口导出customer_points[pickup:<n>]。CustomerMovement优先显式点，未配置的旧夹具保持原散布；导出验证可达性，正式self-pickup覆盖最大16座等待。

## Task 2：正式数据与可编辑空间

- [x] 把gray_cat/cat/rabbit/bear改为已有共享Resource，新增dog/sheep全局Resource。开启motion/action1，保留self_pickup、flow0、配方、价格、奖励及员工招募顺序。
- [x] 正式scene内工位、双灶、柜台与桌椅改为模块，本地Visual保留世界外观；固定环境归空间模块，补占地、员工放餐点、顾客取餐/队列/座位接近点与坐姿点。
- [x] 原画宽887，motion_units=887/720；cell20。员工staff合法区、customer客区、厨房及右侧员工通道显式标定；前厅/后厨任务分工沿用公共角色规则，避免换岗后困在旧分区。外墙、柜台、设备、桌椅和门口实体不能作为直线通道。
- [x] 用显式--shop导出正式layout，校验全部建成后各端口。对比Visual节点原世界变换/贴图与只看美术截图，确认不借迁移改画面布局。

## Task 3：旧档采用与行为回归

- [x] 写真实旧档红灯：go_from/pick/go_to/drop/work/home、顾客排队/取餐/入座/吃饭状态；升级、名册、库存、预留、单位进度不丢失，未来协议保护原文件。
- [x] 实现通用movement_adoption.gd，只作用于无movement的旧serve档采用运动1：按业务目标重建移动；非法旧坐标选择最近合法站点，已在手工动作中的员工放到对应新端口，保留剩余工时；不在日常tick传送。
- [x] 恢复CustomerMovement与RuleActions后再校验生成状态；ShopSave首次覆盖保留验证过的原字节备份。重复保存/读回继续精确一致，不重复预留、生产或结算。
- [x] 原第三店legacy语义测试继续针对冻结旧配置，正式场景与共享行为用新专项验证；不删除原库存/事件边界断言。
- [x] 新正式店真实界面覆盖物理抵达、不可穿物、角色同视口尺度、暂停/倍速、所有菜品销售、存档重开与购买解锁。记录和旧版的节奏差异，保持奶茶基线完整。
- [x] 全量规则、模块/运动/动作/流程显示、三店UI、旧配置及布局导出通过；核对26项用户文件和除已授权第三店外6项冻结数据，更新QA/接入指南/任务总表。不自动提交。

## 完成记录

T08已提交b108937，未推送。T09本地完成：10项专项、469项规则、166项真实旧档会话、167项实际窗口检查通过；原美术59个组件匹配、像素差异0。14个原状态采用与备份保护通过，双人600秒的有意节奏差异已记录；26项用户文件和其余6项冻结数据不变。T09不自动提交，下一项T10。详见docs/qa/stirfry-shared-template.md。
