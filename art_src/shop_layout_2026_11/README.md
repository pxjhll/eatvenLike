# 店铺独立素材（2026-11-02）

成品位于 `art/reference/`。新增桌面配料、柠檬工具与桌椅均为独立透明 PNG；既有 16 张替换图片保留主线原始画布宽高。完整原始尺寸见 `baseline-sizes.json`。

按用户要求，主体素材使用内置 image_gen 按组同页绘制：后厨设备、前厅家具、加料物品、柠檬工具；长桌与柜台另用一张同页修正。用户提出分组前已生成的珍珠罐、茶叶罐沿用。原图与生成提示词保存在 `sources/`、`sheet-*.json` 和 `manifest.json`，可重新拆分导出：

```sh
python tools/export_shop_art.py art_src/shop_layout_2026_11/manifest.json
```

导出仅裁取指定独立区域，以等比例缩放和透明留白放入既有画布，不把杯子、人物或桌面配料合进家具。个别画布允许 `fit_bounds` 修正可见物体比例，同时保持文件像素宽高不变。源素材目录通过 `.gdignore` 排除 Godot 导入，游戏只使用成品。

2026-11-03 修正：煮茶机底座按供电加热工作柜绘制，煮茶锅、调奶机和独立后方连接管与柜体同页生成，见 `sheet-powered-brewing.json`。旧薄木桌已替换；连接管随调奶设备解锁，单独分层置于两台机器后方。

墙面和木质部分仅按参考图调色，不重新生成图片。`palette_sources/` 保留调色前原图；`tools/recolor_shop_art.py` 保留原有尺寸、几何与透明通道，使用确定性的像素变换将奶油墙改为蓝灰墙、降低木色的橙色饱和度。主 manifest 导出后会自动应用同一调色流程，也可单独执行：

```sh
python tools/recolor_shop_art.py
```

锅对应煮茶机 `boil`，参考图上的机器文字不作为游戏功能命名。前厅 `lemon_front` 是柠檬水到柠檬茶的独立手打工位；后厨 `press` 图片保留。
