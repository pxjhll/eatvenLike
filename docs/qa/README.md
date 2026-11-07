# 当前版本验证

使用 Godot 4.7。先导入资源，再运行测试；测试用独立的测试存档（`user://shop-*-<进程号>.json`），不碰玩家存档。CI 跑的完整清单见 `.github/workflows/tests.yml`。

```sh
godot --headless --path . --import
godot --headless --path . -s tests/run_all.gd                 # 规则、数据、存档、整店基准回放、字体
godot --headless --path . -s tools/sync_shop_layouts.gd -- --check   # 店铺数据里的走位和美术锚点一致
godot --headless --path . -s tests/render_shop_tea.gd         # 奶茶店真实点按：开店、面板、存读档、菜单、重开、调参
godot --headless --path . -s tests/render_shop_pancake.gd     # 煎饼摊：引导、原画、结店去下一家
godot --headless --path . -s tests/render_shop_guide.gd       # 奶茶店引导
godot --headless --path . -s tests/render_shop_extend.gd      # HUD 扩展点、鼠标与触屏员工拖放
godot --headless --path . -s tests/render_work_actions.gd     # 角色动作在店里
```

`run_all.gd` 包括：两家店在通用规则层上的行为用例（`test_tea_rules`、`test_pancake_rules`）、第三家测试店（`test_noodle_shop`）、整店基准回放和干净检查（`test_shop_rules`）、界面数据基准（`test_shop_view`）、店铺数据（`test_shop_specs`）、存档（`test_shop_save`）、美术与字体。

实际画面与截图检查使用 `--rendering-method gl_compatibility --audio-driver Dummy` 代替 `--headless`；独立帧动画预览可运行 `tests/render_rabbit_frame_atlas.gd`。

历史 QA 保存在迁移前的提交中。

- [2026-11-01 试玩报告、截图、日志和复现脚本](https://github.com/pxjhll/eatvenLike/tree/26013a213e6b577443917687873e663ea8fbcc1d/docs/qa/2026-11-01-playthrough)
- [2026-11-06 原生 UI 对照报告与截图](https://github.com/pxjhll/eatvenLike/tree/26013a213e6b577443917687873e663ea8fbcc1d/docs/qa/native-ui-reference-2026-11-06.md)及[当时的对照图工具](https://github.com/pxjhll/eatvenLike/tree/26013a213e6b577443917687873e663ea8fbcc1d/tools/build_native_ui_review.py)
