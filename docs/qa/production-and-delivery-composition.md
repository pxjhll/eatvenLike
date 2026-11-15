# T07 生产依赖与交付组合验收

日期：2026-11-11。基于T06提交7eaab3c；该提交本轮未推送。T07改动保留本地，正式三店尚未迁移。

## 交付能力

ProductionPlan读取原SpecStep输入输出，生成节点、依赖、稳定拓扑顺序、错误和配方签名。运行仍使用unit.done和原goods账本。线性配方、独立分支并行和两路合流共用同一套规则；v1不要求配方数组按拓扑排列。编译校验缺输入、重复生产者、环、工作产量不足、多余未消费工作产物和最终成品数量。来源型原料箱与批量锅沿用现有供给语义。

新增能力通过SpecFulfillment.flow_version=1显式启用，默认0保持旧流程和内容指纹。delivery_batch为item时逐件交付，为order时整单交付；后者要求serve、seat_wait、动作1和运动1。delivery_points按菜指定pickup工位，未映射使用第一处。未开放的取餐点不能收到成品。

BundleDelivery只预留原账本中的真实成品。订单待交付实物全部到达各自取餐点、无人预留且员工容量足够时，才一次预留。BundleActionContext组合move/pickup/transport/drop，依次取不同点的餐，抵达顾客座位后一次提交实物、送达、支付和开吃事实，再广播事件。取消归还每个原ID到各自来源，释放整批预留；重复提交不会重复结账。预留容量固定，途中临时容量加成到期不会丢弃已领取物品。

携带画面复用第一件物品图示与现有数量标记。表现只消费脱离规则的快照；图和交付摘要均可被外部修改而不污染规则。没有新增正式菜品、美术、经济参数或第二套库存。

## 存档兼容

动作游标、实物位置、预留、订单归属和容量共同验证。各拿取、搬运和放下阶段可原样续跑；伪造游标、重复物品、错取餐点或不完整整单均拒绝，加载失败不替换当前状态。

v1新unit记录flow_version与recipe_signature。签名包含成品、原工序顺序、工位、动作及输入输出数量，时长变化不改变工序身份。已有签名与当前图不符、未来unit/bundle版本均保护原文件。缺签名旧unit只在原索引含义保持时补当前签名，不重复生产；首次替换前保留并验证原字节备份。此机制不提供任意工序重排的旧档映射。

## 验证结果

使用Godot4.6.3和隔离APPDATA；证据位于_work/shop_modularity/phase-c/。全量规则仍包含奶茶600秒冻结轨迹、39笔销售、4191条行走采样、84条业务事件及60个精确状态哈希。

| 检查 | 结果 | 日志 |
|---|---|---|
| 生产/整单交付专项 | 20项，0失败 | focused-green.log |
| 全量规则与旧店兼容 | 444项，0失败 | full-green.log |
| 真实角色多点取餐、两件显示和整单事件快照 | 47项，0失败 | flow-final.log |
| T05权威运动显示 | 417项，0失败 | movement.log |
| T06原子动作显示 | 38项，0失败 | actions.log |
| 奶茶/煎饼/小炒原界面 | 84/88/33项，0失败 | tea.log / pancake.log / stirfry.log |
| 三店统一角色尺度 | 76项，0失败 | actors.log |
| 配置与原空间导出 | 4店配置通过，奶茶/煎饼布局一致 | authoring.log / layout.log |

专项覆盖真实并行工序、合流、同一产物分给不同消费者时不抢走已分配输入、多点取餐、缺餐、容量不足、两个员工竞争、加成到期、半程阻路、逐阶段保存、取消物品守恒、重复提交、只读模型、坏档拒绝、未来文件保护和原档备份。关闭取餐点的回归先确认红灯，再补目的地开放检查并转绿。CI已加入整单角色显示入口；远端Godot4.7任务未在本地执行。

26项原有用户文件和7项冻结数据哈希保持不变；没有正式shop.tres或PNG变更。第三店的正式碰撞、角色和节奏迁移仍属于T09，不能据此认定已修复。

## T08接入边界

下一步建立可编辑的工位、柜台、桌椅、入口队列模块与统一空间导出。模块移动应同步占地、员工端口、顾客端口和权限区域；多取餐点使用稳定station ID，对应delivery_points。不改变菜品工序索引、goods身份或动作内核，不在表现层补移动或交付逻辑。

```powershell
$env:APPDATA = 'D:/Tes/eatventure/_work/shop_modularity/phase-c/userdata/recheck'
$engine = 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $engine --headless --path 'D:/Tes/eatventure' -s tests/run_all.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tests/render_flow_composition.gd
```
