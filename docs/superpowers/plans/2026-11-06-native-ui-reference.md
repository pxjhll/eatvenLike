# 原生 UI 效果图还原实施计划

**Goal:** 在 Godot 正式奶茶店 UI 还原用户 13 张效果图的暖纸底板、厚边按钮、导航、卡片和弹层，复用已有角色/设备/金币/饮品，复杂奖章和喇叭采用独立透明位图。

**Architecture:** 在现有 HUD 布局、信号和模拟器上实现共享的代码绘制 StyleBox；原生样式包含圆角、外框、内亮边、渐变和底部厚度。语义图标与复杂位图集中映射，不引入截图底板。局部引导、角色预览、调参统一到相同皮肤。

**Tech Stack:** Godot 4.6、GDScript、StyleBox/StyleBoxFlat、Control、现有 SpriteFrames、独立 PNG。

**Spec:** `_work/pancake_stall/UI图片/ui_review_2026_11_06/analysis/原生绘制与资源复用分析.md`，以及原 ZIP 内 13 张 PNG。原图为视觉基准，已获准复用现有角色造型与设备；不更改经济规则或存档。

## Constraints

- 在 `D:/Tes/eatventure` 当前分支基础上新建 `codex/native-ui-reference-20261106`；不切旧工作区，不创建额外 worktree。
- 保留主线主入口、煎饼美术、存档、信号、购买校验与员工拖拽。本次接入奶茶店 UI；同步 main 后保留其默认煎饼摊入口。预览/测试使用注入模拟器和独立 APPDATA。
- 以 Godot 真实渲染对照效果图，不能用完整截图作为 UI，也不能以测试通过代替视觉检查。
- 原稿与现有资源外形不同的角色按已确认方案复用；任何剩余视觉差异如实记录。

## Tasks

- [x] 1. 保存 13 屏基线与组件取样，验证现有 UI 测试；新增渲染/交互检查，覆盖新皮肤状态、三列员工布局、长文本和新图标映射，确认旧 UI 的预期差异。
- [x] 2. 实现共享原生纸面/木色/按钮/卡片/进度样式与简单图标。用真实渲染验证按钮状态、圆角、渐变与缩放，不读取底板位图。
- [x] 3. 接入 HUD 顶栏、导航、目标/员工/菜单/确认页，保留现有节点路径、购买和拖拽；设备页引用已有设备/原料/椅子纹理并补齐插画位置。
- [x] 4. 引导、完成、角色预览与调参接入共享样式；奖章与喇叭保留独立 PNG，角色方向缩略图从实际动画帧获得。
- [x] 5. 原生导出 13 屏与对照图，修正文字溢出、遮挡、输入阻挡和尺寸差异；运行经营/存档/字体回归与 HUD/设备/角色/调参实际交互验证。
- [x] 6. 检查 diff、素材来源、无新增底板截图、分支与工作区状态，记录结果和尚存差异，保留在新分支待审阅。

## Verification commands

使用本机可用 Godot console；运行前将 APPDATA 指向项目 `output/native-ui-test-user/`。

```powershell
godot --headless --path . --import
godot --headless --path . -s tests/run_all.gd
godot --headless --path . -s tests/render_shop_ui.gd
godot --headless --path . -s tests/render_tea_business.gd
godot --headless --path . -s tests/render_tuning.gd
godot --path . --rendering-method gl_compatibility --audio-driver Dummy -s tests/render_native_ui.gd
```

每一步遇到实测失败先定位根因；只围绕本次 UI 修改。测试和对照渲染的数据由测试脚本创建，不重写正式业务规则。

## 实施记录

实现与回归结果见 `docs/qa/native-ui-reference-2026-11-06.md`。13 屏运行截图及原图并排预览位于 `output/native-ui/`。上述勾选表示实现及复核步骤已经执行，不表示原稿的字体、手绘边缘和细微纹理已经达到逐像素一致。分支保留待查看。
