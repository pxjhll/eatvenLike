# 店铺配置契约与完整接入验证

用户已批准将配置校验和完整新店接入测试作为一批独立 PR。D:/Tes/eatventure 当前分支 codex/shop-contracts 从 PR66 的8bbc03d开始；新 PR base 为 codex/session-lifecycle。PR64/65/66 尚未合并，不创建 worktree，不合并或修改 main。

## 目标与边界

支持的配置必须有真实行为，不支持的字段/组合必须在开始读写存档及营业前明确拒绝。第三家面馆仍是测试 fixture，不进入正式 campaign，也不改变 export_presets 对 tests 的排除规则，但必须能运行完整通用场景、交互、存档和恢复。

采用纯规则配置验证器、独立表现契约和真实第三店回归。仅保留文档会继续让错误配置进入运行；整体实现全部预留策略会扩大范围。本批只补 single 的 fixed 来客分支，保持已有 exponential 公式/随机调用顺序；handoff 仍只支持 fixed，并明确拒绝未支持策略。内容版本迁移、全面状态对象化、错误码改造和履约引擎拆分不在本批。

保持两家上线店及面馆的经济、时间、随机序列和营业基准。可以规范化此前不生效的配置声明、修改测试 fixture 显示文字；不得为让检查通过而改变有效规则或重录基准。

## 1. 纯配置验证与能力矩阵

新增 game/rules/shop_spec_validator.gd，无 class_name、无 UI/文件写入/ShopRules 实例依赖。公开静态 validate(shop:SpecShop,campaign:SpecCampaign=null)->Array[Dictionary]，每条错误含 code/path/message；summary(errors:Array)->String 提供可读汇总；capabilities(mode:String)->Dictionary 为支持表的单一机器可读来源。错误路径应指出字段与索引，不能用 GDScript 运行时错误替代验证。

验证必需资源与非空集合、同命名空间唯一 ID、资源空项、实际数字的有限性/范围、站点 block/params、菜谱工序与物品/机器引用、升级效果与目标、阶段菜单/任务/员工槽、员工种类/招募/区域、座位组、传单、连接、布局点/别名/障碍与寻路基础形状、订单选项、奇遇与引导的必要结构和引用。开放文本/条件字典按其定义允许扩展，不把任意元数据当作未知参数错误。所有实际读取的必需嵌套资源应先验证再访问，允许合法零值和现有兼容数据；不能硬编码店名/机器名/菜名。

Fulfillment/Dispatch 的每个导出字段应在矩阵中明确：支持、模式固定政策、或仅允许默认值的预留字段。实现者先核对全部实际消费者（包括 f/d 别名），不能仅按字段直接搜索判断支持。至少遵循以下已确认契约：

- single: taker=follower、dine_rule=takeaway_only、price_rounding=order_round、wait_area=wait_seats、leave_who=queued_unclaimed；pay_at 支持 on_take/on_deliver；队伍实际在 take 完成时离开，使用准确的 leave_queue=after_take 声明。after_pay 仅在 on_take 下可作为同义值；不能允许 on_deliver+after_pay 假称付款后离队。
- handoff: taker=front、dine_rule=seat_first、pay_at=on_deliver、price_rounding=dish_tenth_carry、leave_queue=after_deliver、arrival=fixed。未实现的 share/takeaway_only 等组合明确拒绝。
- single 的 arrival=fixed 与 exponential 均实际生效；fixed 不抽取到达间隔随机数。已上线 single 数据使用 exponential，公式和随机抽取位置保持原样。handoff 的既有 fixed 调度不改。
- 仅 handoff 消费的 ramp/开张人数、单人模式的 first_customer_delay/离队耐心等按真实模式约束；两模式共有的 mood/addon 等需依据实际消费者判定，避免误拒有效数据。
- dispatch 中 base_scores/等待加分/吞吐/路程/疲劳/搬运/工单放弃等用于 handoff，chores_first 用于 single。merge 是当前模式固定的 carry 或 fixed(1)，help_while_waiting 等固定政策不应假称可自由切换。shortage_* 等未消费字段仅允许默认值。

整理现有无效声明：Tea 中未消费的 shortage_per/shortage_cap 回到默认；single 店未消费的 base_scores、Pancake resume_from_stock/leave_seated_segments 等回到中性默认，single leave_queue 改为 after_take。只改变无效/误导声明，不改有效经济/调度值。最终矩阵需逐字段以代码证据校对，文档准确解释预留/固定模式政策。

ShopSession.start 在任何 ShopSave.load/save/fresh 初始化前调用规则验证器，失败保留 Profile/原店档，不隔离或覆盖因配置不合法而无法解释的旧档。纯 ShopRules API 不被改成抛异常；运行时入口与独立校验工具负责阻止错误配置进入正常游戏。

## 2. 可注入关卡表

第三店不能依赖直接篡改 Profile.shop 或假的 Profile。Profile 构造函数增加可选 campaign 参数，默认仍为原 CAMPAIGN；公开实例 campaign 和 available_shops()，内部的默认城市、选店、next_shop、版本/候选验证使用这个实例关卡表。保留 Profile.shops() 静态默认关卡 API，JSON 表达及版本保护不变。无效注入关卡表应明确失败，不能触发空数组下标或写盘。

Session.shop_for(profile,target_id:String="") 根据实例 campaign 解析数据；默认空 target 表示当前店。场景下一店/调参跳店也从实例 Profile 读取，不再绑定全局 campaign。测试面馆提供独立 tests/fixtures/noodle/campaign.tres，与默认生产关卡完全隔离。实际 Profile 保存/重读必须传回同一测试关卡表，证明第三店可持久化而不绕过校验。

## 3. 表现与启动契约

新增 presentation/shop/shop_scene_contract.gd，无 class_name。validate(shop:SpecShop,art:Node)->Array[Dictionary] 只读验证；prepare(shop:SpecShop)->Dictionary 返回 {errors,art}，安全检查资源是否存在/是否 PackedScene/是否 Node2D、实例结构和元数据，失败自行释放候选。

验证 Anchors、有效 sortables、有限正世界尺寸/比例/坐标，以及通用表现实际消费的站点区域、必须可操作机器的 Tap/Frame、岗位/拖拽、排队/入口/出口、座位、连接与路径等。仅将无法安全工作或使声明功能不可达的缺失锚点作为错误；代码明确有安全回退的可选锚点保持可选。锚点只支持平移的路径不得偷偷忽略不支持的旋转/缩放。没有 UI 特殊分支或硬编码第三店 ID。

Scene._ready 先做只读规则和表现预检、准备一份候选 art，然后才允许 session.start 读取/隔离/保存。成功采用同一实例，不重复构造；失败释放候选并显示可重试的错误，不营业、不自动存档，保留已有文件。配置修复后 retry 能重新校验。App.create_session 对无法解析的 shop 也不得在 ShopSave 构造中先发生 nil 错误。

## 4. 第三店完整回归

为已有 noodle 规则数据补独立的灰盒 shop_scene.tscn 与所需锚点，不借用两家上线美术场景。其场景与布局可相互核对。使用独立测试 campaign 和真实 Profile/ShopSave/Session，覆盖从冷启动、点按开张/站点/员工页、至少一种升级、真实卖出、不同菜品、保存/关闭/重进、速度与引导状态恢复、重开清理到后续正常营业；证明默认 campaign/正式 Profile 不变，测试面馆仍不上线。

面馆原显示文字有12个当前字库未包含的汉字。测试 fixture 使用 ASCII 显示文案/标签/场景文字，保持所有业务 ID、秒数、价格、任务数值不变，不替换/扩充生产字体。原规则测试用稳定 action/station 判断工序，不依赖本地化 label；新 fixture 文案加入字体检查。第三店完整交互不要求新增一款上线美术。

新增数据检查 CLI 验证默认 campaign 所有已实现店以及第三 fixture，CI 有独立且限时的配置/第三店场景步骤。配置错误测试应断言字段路径、零 runtime errors、原文件字节与 Profile/规则未提前变化；用真实启动路径验证缺资源/重复 ID/坏引用/非法数值/不支持组合/坏锚点等。

## 验收与发布

采用先 RED 后 GREEN 与独立任务审查、整分支审查。完整148基线测试及新增配置/关卡/表现测试、旧布局/营业基准、五个 GUI/音频、startup retry、session lifecycle、work actions 与第三店回归必须通过。新 single fixed/exponential 行为测试含精确存读档继续，已有两店基准不能重录。

每次本机引擎运行设置 APPDATA=D:/Tes/eatventure-analysis/shop-contracts-userdata/session-lifecycle-userdata/<runner>，既隔离真实用户文件又满足原生命周期哨兵防护；CLI/测试默认使用显式临时依赖。使用本机 Godot4.6.3 和项目 Godot4.7 CI。完成后创建依赖 PR66 的独立 PR，不自动合并；记录真实用户文件哈希不变。
