# 当前版本验证

使用 Godot 4.6.3。先导入资源，再运行测试；经营测试使用独立测试存档。需要完整启动游戏的检查应设置独立 APPDATA，避免接触玩家存档。

```sh
godot --headless --path . --import
godot --headless --path . -s tests/run_all.gd
godot --headless --path . -s tests/test_rabbit_frame_atlas.gd
godot --headless --path . -s tests/test_rabbit_game_visuals.gd
godot --headless --path . -s tests/render_shop_ui.gd
godot --headless --path . -s tests/render_tea_business.gd
godot --headless --path . -s tests/render_counter_tap.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_staff_posts.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_rabbit_game_integration.gd
```

`run_all.gd` 只加载当前奶茶店的经营、存档、派遣、生产、美术与字体套件。兔子独立入口额外检查原帧像素、动作时长、八方向和游戏内角色显示。

实际画面与截图检查使用 `--rendering-method gl_compatibility --audio-driver Dummy` 代替 `--headless`；独立帧动画预览可运行 `tests/render_rabbit_frame_atlas.gd`。员工拖拽和游戏内兔子接入检查会等待绘制回调，必须在真实渲染模式运行。

生成的根目录截图、GIF 和日志已加入 `.gitignore`，不再积累到提交中。2026-11-01 的完整流程排查及问题证据保留在 [本次报告](2026-11-01-playthrough/report.md)，该报告描述清理前的测试覆盖，旧版测试和骨骼试验现已归档。清理后的验证见 [清理说明](../cleanup-2026-11-01.md)。
