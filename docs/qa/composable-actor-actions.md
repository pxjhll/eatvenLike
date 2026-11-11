# T06 可组合原子动作验收

日期：2026-11-11。基于已提交并推送的7581f15（T05）；远端同时包含8b0d24c（T04）。T06按本轮用户指令单独提交，本次不推送。

## 已交付

RuleActions提供move、pickup、operate、transport、drop、wait六种动作的顺序生命周期。动作记录包含版本、步骤、游标、运行状态、阻塞原因、是否已开始和业务lease引用，全部是普通数据。定义先校验，再申请业务预留；前置条件在进入和每tick检查，条件不满足时保留进度，不消耗工时或实物。每tick最多提交一个动作，下一步可以进入但不再消耗同一tick的时间。

ActionContext明确reserve、ready、enter、advance、commit、cancel六个边界。reserve失败必须原子；ready只读前置条件；enter设置本动作表现和计时；advance推进原运动或剩余工时；commit完成已经检查的业务事务；cancel补偿尚未完成的业务。终结提交负责释放业务预留。上下文和Callable不进入存档。

提交效果前先推进游标，使同步事件中的存档不会重放同一提交。提交后检查动作记录身份；回调取消或换任务后不能进入旧计划下一步。取消先移除活动动作再交给业务释放预留；重复取消或完成后取消无效，不会把已送达的物品再放回原料处。回调换任务必须使用业务取消接口释放原lease，不能直接覆盖记录并期待内核猜测库存补偿。

真实serve适配复用原job和实物账本：移动→操作，或移动→拿取→搬运→放下；归岗只需移动。移动仍调用T05的begin_move/advance_move，取料复用原实物身份与归属提交，操作时长在进入时按原规则计算，放下和结算继续由ServeFlow负责。无路时保留手中同一件实物；缺输入时暂停同一工位操作。可在拿取和搬运间插入wait，保存后继续，不重拿。

等待支持有限的显式条件键；当前serve上下文支持纯时长等待和station_unlocked，未创建条件脚本、生产图解释器或分支调度器。T07继续复用已有consumes/produces依赖组织流程，本阶段不增加正式例汤、新设备或菜单。

## 兼容和接入范围

SpecDispatch.action_version默认0，保持旧执行方式。版本1首轮适配serve，且必须同时使用motion_version=1；single/handoff启用1会在配置边界明确拒绝。三家正式店均未开启新执行器，员工数值、PNG和正式店数据未改；不能把本阶段报告为三店已完成动作迁移。旧serve计时提取到已有WorkerState公共计时函数，奶茶原完整状态/事件轨迹与内容指纹仍通过。

action_version=0时内容指纹忽略新增字段，避免默认值导致旧店刷新。启用后，旧活动档按job.stage、原路径和action_left重建动作，不重新预留、取料或重置工时。第一次替换缺动作的旧文件前复制并验证pre-content原档；未来动作版本在读取阶段保护文件，拒绝覆盖。

ActionValidator验证版本、步骤、状态、游标、业务绑定、真实phase和携带状态。实际携带物必须与游标前已提交的pickup/drop对应，因此不能伪造游标跳过取料。wait可以插入既有动作间，但不能改变原job预留的取放效果。ShopView输出深拷贝actions摘要与worker动作记录，角色继续只读取规则快照。

## 验证结果

引擎Godot4.6.3；所有运行使用隔离APPDATA。日志位于_work/shop_modularity/phase-b/actions/。

| 检查 | 结果 | 日志 |
|---|---|---|
| 动作专项 | 18项，0失败 | focused-final.log |
| 全量规则，含奶茶冻结轨迹、内容和旧档 | 424项，0失败 | full-final.log |
| 真实角色六类动作显示、携带物、暂停快照及销售 | 38项，0失败 | actor-gui.log |
| T05三类业务权威运动显示 | 417项，0失败 | movement.log |
| 原奶茶/煎饼/小炒界面 | 84/88/33项，0失败 | tea.log / pancake.log / stirfry.log |
| 三店两种窗口统一角色尺度 | 76项，0失败 | actors.log |
| 生产三店和面馆夹具配置 | 4店通过 | authoring.log |
| 原场景空间导出 | 奶茶、煎饼一致 | layout.log |

专项包括真实库存夹具的六类动作与预留；缺料/阻路；拿取前后取消；零时长、大dt、暂停和现有倍速；普通与旧阶段存档；未来文件保护和原字节备份；事件快照；等待插入；游标与物品身份一致性。各新增行为先以针对性红灯确认缺口，再实施修复。CI新增动作显示检查；本地未运行远端Godot4.7 CI。

## T07可依赖的接口

RuleActions.start(worker,steps,context)、tick(worker,dt,context)、cancel(worker,context)、validate(program)。步骤形状见tests/test_actor_actions.gd的_plan；真实业务适配见serve_action_context.gd。新增顺序组合使用现有能力即可，新增能力需实现上下文、声明兼容版本并补充状态与物品守恒验证，不按店铺ID分支。

```powershell
$env:APPDATA = 'D:/Tes/eatventure/_work/shop_modularity/phase-b/actions/userdata/recheck'
$engine = 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $engine --headless --path 'D:/Tes/eatventure' -s tests/run_all.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tests/render_actor_actions.gd
```
