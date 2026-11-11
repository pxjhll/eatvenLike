# 新店制作入场表

复制此表到店铺制作目录。参考、分层源稿、批量出图和中间工具放 `_work/<店铺>/`；确认后的运行资源进入 `art/<店铺>/`。制作前阅读 `docs/art/scene-art-production-rules.md`。

## 1. 输入与确认

| 项目 | 填写内容 |
|---|---|
| 店铺稳定ID、显示名、存档文件 | 同ID贯穿SpecShop和campaign；不要借用现有店的存档 |
| 当前批准原画 | `_work/<店铺>/references/` 内的明确文件与版本 |
| 原画世界尺寸 / 单位密度 | 原生宽×高；密度=原生宽/720，员工128、顾客110 |
| FigCraft布局与确认记录 | 分层预览版本、用户确认范围；不把原画确认当作后续拆图验收 |
| 业务模式 | handoff / single / serve；选择已有策略及其支持范围 |
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

以SpecStep实际输入输出为准，不按图像的左右顺序推断工序。多路生产和整单交付只在serve的flow1中启用；single/handoff保留各自业务策略。动作1必须配运动1。缺料、工位占用、取消和存档由既有业务能力负责，不在场景脚本里另建库存或移动角色。

## 5. 完整空间表

- 写明网格cell/grid_size、Areas，以及staff/customer权限区域；区域对齐格子。
- 每站配置员工工作/坐班点；顾客另配entrance、exit、pickup和足够的Queue。
- 每个座位同时具有原画坐姿点和可达接近点。根Nav可用Customers/Seats/<group>/<n>或Customers/Waiting/<group>/<n>。
- 自取等待点覆盖最大座位容量，脚底半径12逻辑单位。家具Footprints按实际落地占地，不能用人物身体贴边来掩盖不可达。
- `sync_shop_layouts.gd -- --shop=<资源>` 显式导出，随后 `--check`；错误时先修原模块，不在运行中静默改layout。

## 6. 接入验收

1. 独立SpecShop、场景和campaign先验证，再决定正式campaign接入。
2. 复用全局员工资源；店铺只选择名册、岗位、招募顺序和培养倍率。
3. 跑 `tools/check_shops.py` 的headless及web档；查看每项日志和summary.json。
4. 真窗口检查角色尺度、路径、遮挡、坐姿、携物、操作和所有声明交付。
5. 使用原档/新档验证保存、重开、取消补偿与未来版本保护；不能以清档代替迁移。
6. 节奏报告写明种子、员工数、解锁条件、首单和销售间隔。不能只以“能卖出”判定经营节奏合格。

可直接加载的示例是 `tests/fixtures/onboarding/shop.tres` 和独立campaign；只依赖已有模块/动画/配方，不依赖生成器。第三店的真实美术映射见 `docs/art/stirfry-module-map.md`。
