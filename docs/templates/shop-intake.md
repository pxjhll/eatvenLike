# 新店制作入场表

复制此表到店铺制作目录。参考、分层源稿、批量出图和中间工具放 `_work/<店铺>/`；确认后的运行资源进入 `art/<店铺>/`。制作前阅读 `docs/art/scene-art-production-rules.md`。

## 1. 输入与确认

| 项目 | 填写内容 |
|---|---|
| 店铺稳定ID、显示名、存档文件 | 同ID贯穿SpecShop和campaign；不要借用现有店的存档 |
| 当前批准原画 | `_work/<店铺>/references/` 内的明确文件与版本 |
| 原画世界尺寸 / 单位密度 | 原生宽×高；密度=原生宽/720，员工128、顾客110 |
| FigCraft布局与确认记录 | 分层预览版本、用户确认范围；不把原画确认当作后续拆图验收 |
| 公共模板 | `SpecShop.runtime_template` 指向独立 `SpecShopTemplate`；按能力选择接单、生产、搬运和交付 |
| 新能力 | 已有能力能表达则组合；不能表达时单独列出前置/效果/取消/保存语义 |

## 2. 原画区域→唯一资产

先标原画区域，再去资源库查同物件/镜像物件。同物件只制作一次；重绘按批次同页组织。

| 原画区域 | 唯一资产ID | 已有资源/拟运行路径 | 复用/镜像实例 | 独立的实际用途 | 固定组合范围 | 同页批次 |
|---|---|---|---|---|---|---|
| 双灶主体 | double_stove | 已有资源优先 | 一个主体承载两锅 | 整件家具移动 | 灶台底座保持完整 | 与其他设备同批 |
| 桌面餐品 | dish_bowl | 透明完整餐品 | 多桌复用 | 可搬运、显示出餐状态 | 餐品本体保持完整 | 多种餐品同批 |

固定装满的料架不拆成空架和逐颗食材；组合是否拆分取决于实际功能。人物、预览文字和独立接触阴影不烘进运行图片。旧资源替换保持画布尺寸。每批核对正交投影、俯视角、比例、颜色、描边和完整透明边缘。

## 3. 唯一资产→模块→玩法

| 模块实例ID | 模块类型 | Visual资产及组合 | 主station_id / station_slots | 解锁来源 | 端口与占地 |
|---|---|---|---|---|---|
| Wok | station | 完整双灶+功能锅具 | wok_a / right→wok_b | 主工位及附属位各自阶段 | 主Work、Slots/right/Work、整件Footprint |
| ServiceCounter | counter | 完整柜台、收银物件 | counter / pickup→window | 既有柜台规则 | 员工放餐、顾客取餐分别设点 |
| Table01 | table | 桌子与多把复用椅子 | seat_group、first_seat、容量 | 座位购买规则 | 坐姿Anchors与Nav接近点分开 |

从 `presentation/shop/modules/ShopTemplate.tscn` 开始。模块只支持平移；缩放资产放在Visual内部。一个家具承载多个工位时使用station_slots，不复制主体。固定底座可用FixedVisual，功能物品按解锁显示。已有继承/程序场景可使用完整根Nav而保留图像层级。

## 4. 站点与配方表

| 菜品ID | 原料来源 | 工序station/action | consumes→produces | 并行/合流依赖 | 出餐点 | 交付组合 |
|---|---|---|---|---|---|---|
| 示例主菜 | pantry与rice_cooker | wok_a→plating | 原料→熟料→成品 | 各输入生产完成后才能合流 | window | 与soup组成整单 |
| 示例配菜 | soup_pot | 已有批量锅能力 | 汤料→成品 | 独立支线 | side_window | 同一订单一次结算 |

以 `runtime_template.recipes` 的显式 source/process/transfer 节点、inputs、consumes/produces 和依赖为准，不按图像左右推断工序。线性与合流共用同一图；新店无需再复制旧 `SpecDish.steps`，菜品只保留名称、图标和报价元数据。`fulfillment.handoff` 是旧档身份元数据，不能选择执行器或限制公共组合。缺料、占用、取消和存档都由公共能力负责。

| 配置区 | 必须填写的内容 | 可运行参考 |
|---|---|---|
| places | 真实容器、容量/无限来源/初始量；anchor引用layout，不用工位坐标授权场景散放 | onboarding/table_template.tres |
| machines / restocks | 人工/自动、阶段端口、装卸/搅拌、有限材料与批量配比 | 三家正式shared_production |
| recipes | 显式输入生产者、加工依赖、合流和最终出品；按份保留owner | 两份onboarding模板的盖饭+例汤 |
| service | 接单方式/端口；counter、table或self_pickup；收款与队列策略 | onboarding/table与self_pickup两组合 |
| selection / arrivals | 每个购买阶段的菜单与客流、门槛、抽样时机和附加品 | 六阶段显式selection，不复制顾客循环 |
| dispatch | roles/posts权限、跟单、坐班与assistance等已支持策略 | 三家正式数据；不添加店铺回调 |
| presentation | stock/counters/dining/poses/conveyors显式展示绑定 | 默认库存只显示UI；手持始终来自实际lot |

相对参考路径均在 `content/examples/`；完整能力以编译器和 `docs/shop-capabilities.md` 为准，未知参数直接报配置路径。

前台直售使用同一source/process配方与公共交付，由dispatch权限允许前台处理相关容器和设备；selection.addon.with限制需要例汤的主菜集合。不要复制前台专属执行器。加设备保留已有阶段身份。

每个成品、半成品和原料都填写 `SpecItem.icon`（独立 PNG 或图集区域）；旧 `art` 只用于明确绑定的场景图。逐项检查订单气泡、员工搬运、工位产物、桌面及 HUD；缺图会显示中性占位符。设备面板另填 `SpecStation.icon`，不要借用其他店的图标。

局内节奏分别测开局和正常编制后期，记录首单、出单间隔、缺料、搬运、排队与流失。协助、跟单和兼容批量搬运只通过公共dispatch/transport_batch能力配置，不提高角色基础速度掩盖问题。旧完店目标独立报告，本轮架构验收不重调价格、客流或目标。

## 5. 完整空间表

- 写明网格cell/grid_size、Areas，以及staff/customer权限区域；区域对齐格子。
- 每站配置员工工作/坐班点；顾客另配entrance、exit、pickup和足够的Queue。
- 需要展示时才定义独立显示端口，并在template.presentation中声明用途与host。Buffer、Nav/Work或某个订单拥有物品，都不自动授权摆放库存。餐桌只在实际就座且有餐品时显示。
- 每个座位同时具有原画坐姿点和可达接近点。根Nav可用Customers/Seats/<group>/<n>或Customers/Waiting/<group>/<n>。
- 自取等待点覆盖最大座位容量，脚底半径12逻辑单位。家具Footprints按实际落地占地，不能用人物身体贴边来掩盖不可达。
- `sync_shop_layouts.gd -- --shop=<资源>` 显式导出，随后 `--check`；错误时先修原模块，不在运行中静默改layout。

## 6. 接入验收

1. 从 `content/examples/onboarding/table.tres` 或 `self_pickup.tres` 复制配置；两者共享 `presentation/examples/module_shop.tscn`，保留独立ID和save_file。`content/examples/campaign.tres` 是独立示例关卡，不加入正式关卡表。
2. 新店只改资源、模块绑定和 `content/template_shops.json` 登记；新员工只加全局SpecStaffKind与已有视觉资源映射。不要新增私有脚本。所有正式会话缺runtime_template会在读写玩家档之前拒绝启动。
3. 先跑 `tools/validate_template_shops.gd` 与 `tools/check_template_boundary.py`。前者校验公共能力/员工/场景，后者拦截私有脚本、旧执行器、界面改账本和遗漏模板。
4. 用同一 `tools/check_shops.py` 分别运行 `--profile headless`、`--profile window`、`--profile web`。窗口在Linux用xvfb-run，Windows需可用的图形会话。完整清单包含真实动作轨迹，导入公共脚本本身不算调用证明。
5. `render_template_authoring.gd` 覆盖普通Session启动、真实拿取/放下/加工、合法路径/实际速度、全局人物尺寸、库存与手持一致、召回补偿、磁盘/现场续档以及暂停和1/2/4倍速。查看报告的operations与物理端口proofs，不能只看最终销量。
6. 旧经济/完店门槛仍由 `--profile economy` 执行，保留原check参数与基线。报告与行为验收分开；失败或超时必须如实记录，不能重录旧冻结基线或改门槛以过关。

通用示例在两个履约组合实际完成盖饭两支合流、追加例汤并整单交付；已注册松鼠的员工定义为 `content/characters/staff/squirrel.tres`，无需角色控制分支。原历史教程夹具保留为旧协议回归，不能把它的历史执行器用于新店。
