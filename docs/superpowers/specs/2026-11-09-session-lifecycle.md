# 显式会话与统一重开

用户已批准下一批“会话管理与统一重开”，并明确重开后立即营业，保留已看引导和调参设置。本批在 D:/Tes/eatventure 当前 checkout 实施，分支 codex/session-lifecycle 基于 PR65 的06f6355。PR64/65 未合并，因此新 PR 以 codex/progress-safety 为 base；不创建 worktree，不合并已有 PR，不修改 main。

## 范围与选择

采用独立 ShopSession 对象承接已有 ProgressService 和显式依赖。只给场景增加若干可选参数仍会留下隐式的 App/Profile 和持久化默认值；整体搬迁规则/UI 则超出本批。独立会话对象使生产和测试使用同一执行路径，并把文件目的地和功能开关集中在应用层。

保留经济、关卡、正常存档格式、精确回放、PR65 的候选提交/未来版本保护/损坏隔离和初始化重试。配置能力矩阵、内容版本政策、履约引擎拆分、命令错误码与全面状态对象化不在本批。

## 会话契约

新增无 class_name 的 game/app/shop_session.gd，构造参数显式提供 Profile、ShopSave 和可选 ShopRules；不得在对象内部读取 App 或创建默认用户文件。字段独立控制 guide_enabled、persist_tuning、recording_enabled、tuning_path、recording_path、speed、guides_seen。默认持久化关闭；启用对应服务时要求非空目的地，不能回落到生产文件。

公开 start()->Error、restart()->Error、save(guides:Array=[])->Error、finish(record:Dictionary)->Error、jump(target:String,guides:Array=[])->Error，last_error 和 transition_committed。start 幂等；已有 rules 不重新读店档。加载时继承速度和已看引导；fresh 初始化及 Profile 读写保护继续调用 ProgressService。损坏 ShopSave 的安全新规则/告警行为保持既有语义。finish/jump 仅成功后标记已提交；之后禁止保存、重开和重复前进。restart 只重置已启动、未离开的当前店规则，不修改跨店 Profile，不自动写盘；成功后发 restarted 信号。

App 延迟创建默认 Profile，提供 create_session() 作为唯一正常生产组装入口：按 Profile 当前店铺选数据/ShopSave，明确开启引导、调参持久化、录制及原有 user:// 路径。这样测试启动引擎也不会仅因 autoload 创建就读真实 Profile。

场景允许显式 session，未配置时通过 App.create_session() 启动正常生产。旧 rules/store/profile 字段保留为 UI 读取别名，不再用其是否为空推断引导、调参或录制；若外部只注入这些依赖而无 session，应明确拒绝，不能悄悄绑定 App。所有仓库内场景测试迁移到统一测试工厂。

## 稳定事件总线

ShopRules.reset 保持 events 对象身份，清空日志/时钟而保留外部订阅。内部 _on_broadcast 只能注册一次；RuleEvents.on 对同事件同 Callable 幂等，off 仍可解除订阅。成功 load_dict 也保留 live bus，只有在候选完整恢复成功后采用其日志/时钟，不带入临时对象的内部监听。拒绝恢复仍不改变任何 live 对象或订阅。不得为重开通知向营业日志加入新记录；会话的 restarted 信号单独表达生命周期。

## 重开顺序

重开由当前会话及场景的一条公开路径协调：先取消拖拽，重置规则（paused=false），清除旧弹窗/选择/动画/提示/调参遮罩和自动存档计时，重置引导的 active、计时、客诉等临时字段但保留 seen，然后开始新的录制采样区间并回到店铺页、刷新画面，最后通过现有安全保存入口存档。保留调参倍率、播放速度及引导启用设置。已看引导继续保留，未看引导可按新规则重新判断。旧事件/总结弹窗和动作回调不得在新一局执行；音频仍连接同一事件源，每个事件只能触发一次。

## 持久化边界与测试默认隔离

调参面板新增可注入文件路径，持久化与引导开关独立。Recorder 使用显式目的地；disabled 模式的读、计数、清空、导出也不能读写生产文件。界面上“这里不保存”保持准确。

tests/shop_test_session.gd 统一组装独立 Profile、店档、调参和录制目的地，支持提供已有规则、故障 Store/Profile 和显式开关。路径必须是调用者独立 namespace 或 PID/ticks 唯一路径；重新开同一测试会话时仅复用它自己的 namespace。生产配置不因测试手工创建了临时店档而被读取。迁移所有 shop_play 场景测试，包括已有故障保护、人物动作演示、引导、读档和两店 GUI。仅有真实 rules、store 注入而缺少 session 的测试需明确验证拒绝行为。

所有本机 Godot 运行仍额外设置 APPDATA=D:/Tes/eatventure-analysis/session-lifecycle-userdata 作为防御措施，测试不能依赖环境中已有 Profile/tuning/playlog。本批不更改真实用户文件，记录运行前后文件哈希。

## 验收

先写失败回归，再实现。测试覆盖：事件对象和外部订阅跨重复 reset/成功 load 保持、内部广播不重复、非法 load 完全原子；session 各开关独立、无隐式 App 回落、start 重试不重复；临时店档加载时不读生产 Profile/tuning、不写生产录制；录制禁用时所有文件操作无副作用；暂停重开恢复营业、已看引导/调参/速度保留，弹窗/拖拽/旧客诉状态清除，录制采样与自动保存计时重置；PR65 原故障测试继续通过。

完整规则套件、布局/营业基准、五个现有 GUI/音频脚本与 startup retry 必须通过。新增真实场景生命周期回归纳入有时间限制的 CI。使用本机 Godot4.6.3 与项目 Godot4.7 CI，独立任务及整分支审查后推送、创建依赖 PR65 的独立 PR，不自动合并。
