# T05 共用移动与抵达协议 Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans sequentially. 不创建worktree、其他聊天或代理。

**Goal:** 员工和顾客复用规则侧的路径推进与抵达事实，空间权限、脚底占地、阻路等待、暂停和存档可独立验收。

**Architecture:** RuleMovement推进调用方拥有的普通记录；RuleNav为运动协议v1生成考虑权限和脚底占地的路线。顾客运动记录属于ShopRules，ShopView输出脱离状态的快照，ShopPlay只显示该事实。三家正式店暂保留legacy协议，迁移属于T09/T10；没有显式启用新协议的奶茶状态、指纹和事件序列不变。

**Tech Stack:** Godot4.6.3 / GDScript / Resource / PowerShell。

**Spec:** `docs/superpowers/specs/2026-11-11-modular-shop-system.md`。

## Global Constraints

- 基于T04提交8b0d24c继续，保留原有26项用户文件，工作目录D:/Tes/eatventure。
- 使用隔离APPDATA：_work/shop_modularity/phase-b/movement/userdata/<runner>；日志及夹具画面留在_work。
- 不更改原PNG、员工stats、菜单、价格、升级或正式店导航配置。不重录A阶段基线。
- 本轮用户授权提交T04；T05完成后留在工作区，不自动追加提交或推送。
- 空路径表示阻路，不能假装抵达；路线变更后从真实位置重新寻路，不退回直线或瞬移。
- 最小脚底方形包围盒使用全局半径12逻辑单位，保守覆盖圆脚底；原生坐标按layout.motion_units换算。
- v1只支持grid；未知权限没有路径。角色不互相当作静态障碍，动态人群避让不在本任务范围。

## 文件与协议

- `content/rules/spec_layout.gd`增加motion_version（0=legacy，1=新协议）、motion_units（原生单位/逻辑单位）、actor_areas（权限名→Array[Rect2i]）、customer_points（入口/出口/取餐/座位接近点）、customer_queue。
- 端口命名：customer_points的entrance、exit、pickup；seat:<座位组>/<序号>；wait:<等候组>/<序号>。队列数组按队首起排列，超额按末段延长，延长点仍须可走。
- `game/rules/rule_movement.gd`：assign(record, path)、advance(record,distance)->bool、request(record,nav,goal,profile)、tick(record,nav,distance)->bool。记录沿用pos/path/path_index/walking；v1附加motion{version,goal,profile,topology}。advance只推进距离，不启动业务动作。
- `game/rules/rule_nav.gd`：path(from,to,profile="staff")；can_stand(point,profile)；segment_clear(from,to,profile)；topology_key()。legacy仍使用原路线和缓存；v1缓存按权限区分，解锁障碍变化清缓存。
- `game/rules/customer_movement.gd`：sync(rules)、tick(rules,dt)、ready(rules,key)、handoff_sale(rules,order_id,seat)。以业务活跃记录推导目标，保留离店记录直至规则抵达出口。
- ShopRules.movement={version:1,customers:{key:record}}，只在启用v1时序列化；顾客key为guest:<id>/customer:<id>/order:<id>/diner:<seat>。legacy不新增状态键。
- 员工运动通过ShopRules.begin_move/advance_move进入协议，旧路径算法和浮点运算顺序保持一致。初始速度在v1按motion_units换算。
- 新协议顾客逻辑速度取共享actor_presentation.customer_speed=170。到队首才可接单，到顾客取餐端口才可交付，到座位接近点才开始用餐。
- ShopView条件输出movement；ShopPlay使用统一客户快照渲染分支，堂食组件只负责家具和桌上物品。位置和抵达不由GUI的delta决定。
- ShopStateValidator验证版本、形状、有限值、路径索引、目标与终点、状态和权限。旧档无movement时按业务阶段确定起点并重建；员工任务、经营、库存和计时保留。ShopSave在替换旧格式前使用既有备份；未来运动版本保护原文件。
- ShopContentContract在motion_version=0时忽略新增layout字段，保持旧指纹；v1纳入这些字段。

## Task 1：运动内核、空间约束和员工接入

- [x] 写tests/test_shared_movement.gd。空路径示例：

```gdscript
var worker = WorkerState.create(1,"cat","cat",{},Vector2(30,30))
WorkerState.begin_walk(worker,PackedVector2Array(),"walk")
check(not WorkerState.advance_walk(worker,100.0),"no route is not arrival")
check_eq(worker.pos,Vector2(30,30),"blocked keeps actual position")
```

- [x] 运行独立专项入口，确认上述行为失败；新增v1配置存在性断言避免用解析错误当红灯。
- [x] 实现公共距离推进，修改旧空路径单测为等待语义；非空路径运算不变。
- [x] 增加v1布局和导航：同格目标不能丢失起点；路径保留格中心连接；所有端点与线段检查脚底包围盒、权限区域、动态障碍，未知权限返回空。
- [x] 用墙角、窄通道、权限隔离、非中心端点、拓扑变化夹具验证安全路线；坏空间配置由现有validator拒绝。
- [x] 接入三种员工流程，阻路时持有任务和预留等待；障碍变化从原地重寻路，保存/恢复接续一致。

## Task 2：规则顾客与业务抵达

- [x] 写真实规则夹具（采用现有三种业务数据的深拷贝，只替换运动空间）。断言距离足够远时不能先接单；接单后阻住座位不能开始吃；阻住取餐点不能结账/交付；恢复路后可继续。
- [x] 观察红灯后实现顾客sync/tick和三类业务抵达门槛。serve的walk_left仅用于兼容显示，不作为v1抵达依据；handoff堂食计时等待抵达；single付费等位和取餐同样使用规则位置。
- [x] 事件前同步发生变化的运动目标，保证事件回调存档独立续跑；退出记录直到走到出口才删除。
- [x] 使用0.1/0.2/0.4等现有倍速输入，比较相同规则时长后的全状态；暂停和零delta不推进。

## Task 3：快照、旧档和验收

- [x] 快照可修改而不污染规则；同一快照用不同GUI delta绘制位置不变；GUI绘制不修改规则。
- [x] 接入ShopPlay权威分支和堂食纯家具刷新，保留legacy表现供后续迁移。
- [x] 验证新运动状态保存读回、阻路保存、旧档重建、未来版本保护以及原奶茶完整冻结轨迹。旧档的顾客原本没有权威坐标，重建使用阶段端口，不能宣称恢复历史GUI精确像素。
- [x] 运行完整规则、正式三店GUI、三店两种窗口角色尺度、四店契约和布局检查；扫描运行错误和资源泄漏。
- [x] 完成docs/qa/shared-movement.md与docs/shop-onboarding.md接入说明，更新总表状态和T06前置协议。检查用户原有文件哈希、冻结文件哈希和git diff --check。

专项测试使用_work下的临时SceneTree runner，加载tests/test_shared_movement.gd并按现有run_all调用test_*和cleanup；验收时将套件注册tests/run_all.gd。完整运行：Godot --headless --path D:/Tes/eatventure -s tests/run_all.gd。

## 执行结果

T05完成：20项运动专项、406项全量规则、417项快照显示和堂食检查通过。三店界面84/88/33项、三店尺度76项、四店契约与奶茶/煎饼布局一致性通过。26项原有用户文件与7项冻结数据哈希未变；正式店数据和PNG无修改。详见docs/qa/shared-movement.md。T04已提交8b0d24c且未推送，T05留在工作区；下一项T06。
