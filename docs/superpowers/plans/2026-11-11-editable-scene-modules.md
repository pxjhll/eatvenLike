# T08 可编辑场景模块与空间导出 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially. 不创建worktree、其他聊天或代理。

**Goal:** 模块拥有本地美术、交互区、操作端口和占地；移动实例时导出同一份规则空间，提供可复制的灰盒ShopTemplate。

**Architecture:** ShopModule是可编辑Node2D；工位、柜台、桌椅、入口队列和空间区域使用固定本地节点约定。ShopAnchors以只读索引合并旧根锚点和模块锚点，坐标统一转换到美术根；不生成第二套场景节点。module_version=1显式开启完整空间导出，沿用SpecLayout和RuleNav。检查失败不写数据、不静默圆整空间或覆盖重复端口。

**Tech Stack:** Godot4.6.3 / GDScript / TSCN / Resource / PowerShell。

**Spec:** docs/superpowers/specs/2026-11-11-modular-shop-system.md；任务总表T08；T05运动、T07多取餐点契约。

## Global Constraints

- 当前分支codex/tea-baseline-shared-staff，HEAD87cb87f已推送；本轮不自动提交或推送。
- 保留26项原有用户文件和7项冻结数据；不改正式shop.tres、PNG、基础属性、价格或配方索引。
- 本轮提供代码和灰盒模块，不重绘/替换正式美术，不接入尚未确认的FigCraft分层稿。
- 所有测试使用_work/shop_modularity/phase-d/userdata下隔离APPDATA；制作中间物和证据不提交。
- 未声明module_version的旧场景保持原锚点和导出行为；模块版本未知、冲突、错引用、非有限或旋转缩放变换明确拒绝。
- 动态编辑发生在制作阶段；运行仍只读取已校验的SpecLayout，不在场景中实时重建业务导航或搬迁已保存角色。

## 文件与节点契约

- presentation/shop/modules/shop_module.gd：@tool Node2D，module_id、module_kind(station/counter/table/entrance/space)、station_id、seat_group、first_seat、table_index、seats_per_table、seat_purpose(dine/wait)。Visual是可替换美术，Local Anchors和Nav只用平移。
- station/counter本地Anchors/Station映射Stations/<station_id>，Anchors/Drop映射Drops/<module_id>并默认绑定station_id；counter的Anchors/Counter映射Counter。Nav/Work与Nav/Post导出员工站位/坐班位。
- table的Anchors/Table映射Tables/<seat_group>/<table_index>，Anchors/Seats/<n>映射Seats/<group>/<first_seat+n>；Nav/Seats/<n>同时导出员工送餐点和顾客接近点。坐姿点和接近点保持分离。
- entrance的Anchors/Entrance、Exit、Queue、Waiting、Lanes、Aisle直接合并；Queue同时导出规则customer_queue。Nav/Customers/<entrance|exit|pickup>导出顾客端口。space可承载全局Chips等原有锚点及区域。
- 通用Nav/Footprints/<n>导出像素占地；工位默认随station解锁，其他模块默认静态，显式metadata/station可覆盖。Nav/Areas/<n>及Nav/Access/<profile>/<n>使用本地像素AnchorRect，转换后必须整格对齐，不四舍五入。
- 根Anchors metadata/module_version=1；根Anchors/Nav metadata含nav/cell/grid_size/motion_version/motion_units/spawn_point/aliases。根Nav沿用Areas/Obstacles/Points/Posts，增加Access和Customers/Points。所有字段由同一导出结果参与比较。
- module_space.gd：collect(root)->{enabled,nodes,metadata,errors}；export_layout(root,base)->{layout,errors}。返回脱离的SpecLayout；失败layout=null。完整字段常量包含现有所有SpecLayout导出字段。
- ShopAnchors.export_layout(base)统一错误结果；layout(base)保留便捷返回值。索引每次读取坐标与子节点顺序，移动模块后不缓存旧坐标。ShopSceneContract合并模块错误并验证完整空间一致性。
- tools/sync_shop_layouts.gd：默认生产campaign；支持--check、--shop=<path>、--campaign=<path>。先检查所有候选，再执行保存；坏资源/错误模块/无效空间非零退出，check不写原文件。

## Task 1：模块锚点与本地坐标

- [x] 写tests/test_scene_modules.gd及_work专项入口；断言新增模块缺失确认红灯。
- [x] 用真实Node2D模块与AnchorRect手工期望：嵌套平移后工位Tap/Buffer/Post、桌椅坐姿点、入口Queue和工位站位随动；同一读取器不能缓存旧坐标。
- [x] 实现ShopModule及ModuleSpace只读索引，接入ShopAnchors；对重复module_id、重复叶端口、未知版本、错ID、变换和不完整模块补红灯并转绿。

## Task 2：完整空间导出与校验

- [x] 写红灯：员工/顾客端口、队列、占地、解锁引用、权限、别名、密度和出生点均参与导出；修改输出不能污染输入；缺端口、越界、非整格、占地内端口和无路拒绝。
- [x] 实现完整版本1空间编译和RuleNav可站立/连通检查；保留旧Nav导出分支。SceneContract用同一结果比较所有字段，导出失败返回结构错误。
- [x] 改造sync工具并运行真实子进程：check检测差异且保留原字节，默认同步写出正确空间，错误候选不写；显式fixture入口不触碰生产campaign。

## Task 3：可编辑模块与灰盒样板

- [x] 制作station.tscn、counter.tscn、table.tscn、entrance_queue.tscn、space.tscn和ShopTemplate.tscn，只使用灰盒多边形与已有资源。保留可替换Visual，不增加正式美术。
- [x] 独立夹具组合完整serve场景和实际员工/顾客；移动工位、柜台、桌椅/入口后重导出，检查交互区与规则端口一致、占地可绕行、销售及存档续跑。
- [x] 专项注册tests/run_all.gd，真实模块显示入口加入CI；运行全部规则、T05–T07显示、三店UI、角色尺度和旧布局检查。
- [x] 更新接入文档、QA记录、任务总表和T09前置边界；确认26/7项哈希不变、无正式资源变化、git diff --check通过，记录证据。不自动提交。

## 完成记录

T08已在本地完成：15项模块/工具专项、20项模块与原表现边界、459项全量规则、25项完整界面和26项真实窗口检查通过。旧店UI、运动/动作/整单显示、尺度和布局回归通过；26项用户文件与7项冻结数据哈希不变。资源导入无错误，未改正式shop.tres或PNG。本轮不自动提交，下一项T09；详见docs/qa/editable-scene-modules.md。
