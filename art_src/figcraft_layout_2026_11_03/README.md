# FigCraft 布局还原（2026-11-03）

`tea-shop-layout2.figcraft` 是用户修改后的原文件副本，`reference.png` 是 FigCraft 原生渲染。`placement.json` 保存从该文件读取的 44 张独立图片及 1 个箭头的世界坐标、显示尺寸、源纹理、分组和解锁规则。画布为 720×1500，原 PNG 文件及像素尺寸保持不变。

场景使用原来的游戏节点路径。图片独立保持遮挡排序，通过 `layout_group` / `unlock_rule` 元数据按 FigCraft 分组统一显示，避免把「基础物品」等跨越前后景的大组当成单一遮挡物。桌椅由现有堂食展示器构建，坐标与文件一致。

后续排序修正：手打钢杯位于冰盒后面，冰盒遮住重叠处的杯底；不移动或缩放物件。修正存入 `placement.json` 的 `draw_before`，重新应用布局也会保留。

| FigCraft 分组 | 出现条件 |
| --- | --- |
| 基础构建、基础物品、货架 | 开局可见，重置后仍可见 |
| 原料箱（茶叶罐、奶罐） | 首次购买原料箱后整组出现 |
| 柠檬水机 | `lemonade` |
| 柠檬茶手打台（捣棒、钢杯、冰盒） | `lemon_front` |
| 煮茶机 | `boil` |
| 调奶机（机器、连接管） | `mix` |
| 加料台（桌子及全部桌上物件） | `topping` |
| 封口机、传送带、箭头、右侧打包袋和红色底座 | `seal` |

左侧纸袋、收银设备、电磁柜和原料承重桌归属于基础物品，不随相邻设备消失。保留现有购买座位的功能容量，开局即可看到全部桌椅。横向传送带已按用户文件移除；箭头保留文件中的旋转及其位于传送带后方的层级。

场景还原不会删除原游戏的最终 `press` 阶段：继续提供解锁、点击与指引入口，但不添加已删除的后厨手打桌图像。未修改价格、配方、模拟逻辑或存档格式。工作点、碰撞与点击范围已对齐新布局；镜头增加顶部留白，防止调奶机被 HUD 遮挡，场景世界坐标不变。

重新应用图片位置（需 Pillow）：

```powershell
python tools/apply_figcraft_shop_layout.py
```

[原布局校验脚本](https://github.com/pxjhll/eatvenLike/tree/26013a213e6b577443917687873e663ea8fbcc1d/tests/render_figcraft_layout.gd)对应迁移前的场景。当前项目可运行 `godot --headless --path . -s tools/sync_shop_layouts.gd -- --check` 核对通用店铺布局。

专门检查包含 44 张图片坐标、尺寸、纹理、13 个分组在开局/逐步解锁/重置后的可见性，以及最终阶段的真实 UI 解锁和指引。全套 112 个回归用例、原生布局和员工拖拽检查均通过。预览位于 `docs/qa/figcraft-restored-layout.png`、`figcraft-opening.png`、`figcraft-fully-unlocked.png`。
