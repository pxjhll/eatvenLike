# 小兔子骨骼预览分支验证 — 2026-11-01

分支：`codex/rabbit-skeletal-preview`。基于最新 `origin/main` 的 `31f0db1`，包含原工作分支之后的17个main提交。本分支新增独立骨骼预览和美术源文件，保留main的游戏入口、玩法和帧动画流程。

## 入口和美术工程

- Godot打开 `presentation/rabbit_skeleton/preview.tscn`，按F6运行当前场景。
- 右前视角的可编辑骨架场景为 `presentation/rabbit_skeleton/rabbit_front_right.tscn`，选中AnimationPlayer后查看walk动画。
- `art_src/rabbit_skeleton/photoshop/` 包含五视角PSD及PhotoCraft工程；`rabbit_parts_with_bones`版本的每个视角组顶部有独立骨骼参考智能对象。
- PSD修改需要重新导出对应PNG到 `art/rabbit_skeleton/complete/<方向>/` 才会更新Godot显示。
- 初期旧版试作保存在 `presentation/rabbit_walk/`，当前有效入口为 `presentation/rabbit_skeleton/preview.tscn`。

## 本次验证

本机实际执行环境：Godot 4.6.1 stable，Windows。真实窗口检查使用OpenGL Compatibility和NVIDIA RTX 3060。

- 最新main基线：`tests/run_all.gd`，159个用例，0个失败。
- 加入骨骼预览后的整体验证：`tests/run_all.gd`，159个用例，0个失败。
- 独立检查：`test_rabbit_walk.gd`、`test_rabbit_directions.gd`、`test_skeletal_character_preview.gd`、`test_source_skeletal_rabbit.gd`、`test_rabbit_frame_atlas.gd`、`test_rabbit_game_visuals.gd`，全部退出码0、0失败。
- 实际窗口输入与渲染：`tests/render_source_skeletal_rabbit.gd`，0失败，覆盖暂停、转向、骨骼显示、共享动作、物品挂点和大图/游戏尺寸同步。
- Godot资源导入完成，没有脚本解析或资源加载失败。
- `git diff --cached --check`通过。

完整回归结束时仍有main基线同样出现的存档失败测试警告和退出资源清理提示；本次没有新增对应失败。
