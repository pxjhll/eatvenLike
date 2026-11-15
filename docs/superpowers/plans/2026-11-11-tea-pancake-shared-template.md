# T10 前两店共享行为迁移 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially. 不创建worktree、其他聊天或代理。

**Goal:** 奶茶handoff与煎饼single接入相同运动和动作底座，保留原业务/美术及可延续旧档，三店共享角色基础定义。

**Architecture:** HandoffActionContext持有原job库存预留并组合move/pickup/transport/drop或move/operate；SingleActionContext按原order/step/chore组合移动与当前效果，缺料暂停或切换既有煮料杂活。原业务函数仍拥有库存、支付和工序推进。原场景可编辑Anchors/Nav采用完整空间导出，不为迁移重新制作美术或复制视觉组件。原奶茶精确轨迹继续通过独立冻结定义重放，正式新行为单独验收。

**Tech Stack:** Godot4.6.3 / GDScript / Resource / TSCN / PowerShell。

**Spec:** docs/superpowers/specs/2026-11-11-modular-shop-system.md；任务总表T10；T09接口边界。

## Global Constraints

- 当前分支codex/tea-baseline-shared-staff，HEAD b108937；T09已有改动保留，本轮不提交、不推送。
- 保留26项用户原文件，不改PNG、原画、价格、奖励、菜单和配方索引，不以提速恢复旧完店分钟数。
- tests/baselines/tea_modularity.json、原capture源稿及tea_modularity三个存档夹具共5项原字节不改；复制原奶茶/煎饼定义供legacy规则和精确轨迹使用。
- 全部引擎运行显式隔离APPDATA到_work/shop_modularity/phase-f/userdata，源场景备份、截图与临时工具只在_work。
- 原hand-off/single flag0不经过新上下文，保留原浮点计时和事件顺序。新flag1结果必须可独立校验、保存与取消，不给动作内核增加配方语言。
- 三店共享员工128/顾客110、逻辑顾客速度170；已有同种员工直接引用全局定义。奶茶基准属性不改，煎饼改为rabbit104/1/2、gray_cat112/1/2、bear88/1/3。

## Task 1：冻结原流程与动作适配

- [x] tests/fixtures/legacy_shops/保留原两店资源及奶茶捕获器副本；原冻结文件保持不变。采集真实handoff各阶段、single步骤与煮料杂活状态。
- [x] tests/test_first_shops_migration.gd先确认两类新动作不存在的红灯；用受控几何覆盖搬运/操作、single收钱/主菜/加餐/递餐与load/unload杂活。
- [x] 实现handoff_action_context.gd：lease绑定原job，进入时使用原时长函数，原库存只预留/拿取/投递一次；完成清任务后再广播结算。
- [x] 实现single_action_context.gd：lease绑定order/step/chore；到位后才开始原手工操作；锅内取料只扣一次，取消未完成取料返还，已完成步骤保留。缺料时可暂停原步骤执行原煮料/出锅杂活，随后继续。
- [x] ActionValidator分派三个业务上下文；校验游标、物品/预留、真实phase和单工位占用。配置只在motion1时允许single/handoff动作1，未知版本拒绝。

## Task 2：正式数据与完整空间

- [x] 根Nav支持Customers/Seats/<group>/<n>、Customers/Waiting/<group>/<n>导出顾客端口，已有旧锚点与图片保持原层级。
- [x] 两店开启module_version1、motion1/action1；奶茶密度1，煎饼937/720。显式员工区/客区、入口/出口/排队/取餐/座位接近点，检查半径12逻辑单位。
- [x] 校准原来的贴边或场外端口、家具脚底占地；仅改变规则/接近坐标，坐姿和图像世界外观保留。员工不跨柜台，顾客不能进入后厨。
- [x] 煎饼接共享员工；single接单/递餐时顾客必须走到对应柜台端口，完成后携餐离开。奶茶保留原库存、加工、封口和传送带业务。

## Task 3：旧档、回归和交付

- [x] 扩展MovementAdoption到handoff/single，仅首次采用旧协议时映射当前业务目标和非法旧坐标；恢复原动作进度、已扣原料和杂活占用，不重新扣款或取料。
- [x] ShopSave识别两类旧活动动作需要备份；迁移失败与未来协议保护原文件。普通新协议读档不重定位，取消/召回保留single已付订单及已完成步骤，重新上岗可继续。
- [x] 历史规则/经济用例显式引用冻结资源，原奶茶60个状态哈希/84事件/39销售不放宽；正式新流程有独立速度、到位、阻路、暂停/倍速、存档、取消与销售回归。
- [x] 原界面与三店统一尺度、T05–T09专项、配置及完整布局导出通过；记录原/新节奏与同画面美术对比，不改经济来恢复旧指标。
- [x] 更新QA、接入说明、总表和T11边界；核查原有26文件、5项冻结数据及原两店资源副本，git diff --check。本轮不自动提交。
