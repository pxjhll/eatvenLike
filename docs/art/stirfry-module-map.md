# 原画接入映射示例：小炒饭馆

本表对照已接入的正式场景 `presentation/shops/stirfry/stirfry_art.tscn`，不是新制作或新布局确认。批准参考保存在 `_work/stirfry/references/user_uploads/stirfry-approved-concept-2026-11-10.png`。新增制作仍按场景美术规则先查库、同页批量、FigCraft确认。

| 原画区域 / 实例 | 唯一运行资产（art/stirfry/scene/） | 模块与玩法绑定 | 拆分/复用理由 |
|---|---|---|---|
| 厨房地面、客区木地面 | kitchen_floor_r00_c00、wood_floor_r00_c00 | Environment，Space/Nav区域 | 固定环境开局存在；不把地面归为可购买工位 |
| 后墙与装满的墙架 | back_wall_r00_c00、stocked_wall_shelf | Environment | 装满墙架保持完整，不拆逐件备料 |
| 电饭锅与底座 | rice_cooker、support_stand | RiceCookerStand→rice_cooker | 工作锅可按状态显示，固定底座保留 |
| 双灶主体 | double_stove | Wok→wok_a；right槽→wok_b | 一件完整家具承载两工位，主体只引用一次 |
| 两口功能锅 | wok_tomato_egg、wok_meat_vegetables | Wok/Visual及Slots/right | 与各工位解锁/工作相关，不拆逐颗食材 |
| 完整例汤台 | complete_soup_station | SoupStation→soup_pot | 以实际批量锅能力接入，保持整组设计 |
| 备料台 | prep_table、rice_sack、complete_chopping_board、complete_produce_group | PrepTable→pantry | 可独立摆放的完整桌面物件与桌子分离，组内不细拆 |
| 装满的原料架 | loaded_ingredient_rack | 固定原料陈设 | 满架完整复用，不生成空架和每颗原料 |
| 盛盘工作台 | plating_supply_group | PlatingTable→plating | 功能组合按工作实际粒度组织 |
| 前柜台与取餐口 | service_counter、register、wood_tray | ServiceCounter→counter；pickup槽→window | 一个柜台承载接单/取餐，不复制主体；员工和顾客端口独立 |
| 八张餐桌、重复椅子 | dining_table、dining_chair | Table01…Table08→dine组、各座位范围 | 相同/镜像资产复用，移动整桌带动坐姿点与接近点 |
| 门柱、门口植物与脚垫 | entrance_post、entrance_plant、entrance_mat | Environment和EntranceModule | 两侧相同门柱共用资源；入口/队列是规则端口，不烘入图像 |

资产路径均加 `.png`。完整蒸笼台 `complete_steamer_station.png` 也是已有运行资产；其显示、解锁和站点映射以正式场景/SpecShop为准，不因这张示例表推导新菜单。

Wok、柜台等模块的 Anchors 管交互区，Nav 管Work/Post、Slots和Footprints。桌椅Anchors管原画坐姿，Nav管真实接近点。Space限定员工/顾客权限；EntranceModule提供入口、出口和连续队列。导出时合并成完整SpecLayout，运行层读取该数据而不按Sprite位置猜路线。

原画→资产清单→模块表→SpecShop配方/策略→完整空间导出→真实会话验收，各环节使用稳定ID互相对应。机器配方的输入输出关系独立于美术拆图，不能把视觉上相邻的物件自动当成同一工序。
