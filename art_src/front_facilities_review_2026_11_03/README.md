# 前厅设施美术与场景接入

本轮已替换图片并调整场景美术节点，没有继续修改游戏运行逻辑。

- `front-facilities-sheet.png`：三件图素同页生成，保持原画风格和正交视角。
- `takeaway_bag.png`：200×240；独立纸袋，两处共用同一份图片，分别摆在左侧台面和右侧红色底座上。
- `checkout_terminal.png`：335×245；低矮收银设备，替换 `art/reference/register.png`，保持原图片尺寸。
- `packing_base.png`：200×200；独立空红色底座，替换 `art/reference/counter_red_device.png`，保持原图片尺寸。
- 场景：`presentation/reference/shop_art.tscn`。
- 整场景预览：`docs/qa/shop-layout-overview.png`；另有 portrait、small、wide、glass 预览。

生成提示词、参考图和拆分坐标见 `generation.json`，使用内置 image_gen 生成，图片保留透明通道。

接入后执行现有场景预览检查，结果为 `SHOP LAYOUT: 0 failures`。与本轮接入前的校验值相比，66 个 `.gd` / `.py` 文件均未变化；早前已有的代码改动仍予保留。
