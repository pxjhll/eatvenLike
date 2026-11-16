# Opening Video Implementation Plan

> **For agentic workers:** Execute inline in the user-requested existing branch; do not create another worktree or ask again for implementation approval. Use executing-plans and test-driven-development, then verification-before-completion.

**Goal:** 接入双端欢迎图、点击解锁音乐、片头播放、末帧冻结及开始营业。

**Architecture:** `presentation/opening/opening.gd` 管理启动状态；`opening_video.gd` 适配原生 VideoStreamPlayer 与网页 JS 播放器。音乐复用 ShopAudio；正式进店才创建原有 ShopPlay。

**Tech Stack:** Godot 4.6+ GDScript、浏览器 HTMLVideoElement、Python 标准库导出工具。

**Spec:** `docs/superpowers/specs/2026-11-16-opening-video-design.md`

## Global Constraints

- 当前 `codex/opening-video` 分支直接接入；不改变营业模拟、已有存档和音乐偏好。
- 网页与 Windows 都支持；无视频原音；欢迎图保留现有文字。
- 每次启动一次；视频结束显示最后一帧并等候真实按钮。
- 运行资源进 Git，源稿、探针和测试输出留在 `_work`。

## Task 1: 启动状态与跨页面音乐

**Files:** `tests/render_opening.gd`, `tests/fixtures/opening_video_stub.gd`, `presentation/opening/opening.gd`, `presentation/opening/opening.tscn`, `presentation/audio/shop_audio.gd`, `game/app/app.gd`。

- [x] 用脚本加载启动场景并断言资源存在，运行看到预期失败。
- [x] 写行为断言：welcome→playing→ready→entering，重复请求各只生效一次，欢迎不初始化 App.profile，不启动 ShopPlay。
- [x] 写音频断言：`play_music(track: AudioStream)` 不订阅规则事件，同一曲目进店保持播放位置，音乐关闭保持无声。
- [x] 实现单一启动场景，媒体节点允许测试注入；公开 `shop_requested` 信号及 `change_scene_on_start` 与现有场景测试约定一致。
- [x] 运行 `godot --headless --path . -s tests/render_opening.gd`，确认 0 failures。

## Task 2: 双端媒体、资源和导出

**Files:** `presentation/opening/opening_video.gd`, `web/opening_video.js`, `art/opening/`, `tools/prepare_web_export.py`, `export_presets.cfg`, `project.godot`。

- [x] 实现 `play(frame: Control)`、`stop()` 与 `started`、`finished`、`failed` 三个信号；原生加载 OGV，网页调用注入的 JS 播放器。
- [x] 将确认的欢迎 PNG、无声 OGV/MP4 和精确末帧纳入正式资源；复用现有金色 UI 样式制作真实按钮。
- [x] JS 播放器随 canvas 等比居中适配、播放完成保留画面直到 Godot 接管、失败通知、不拦截启动 UI、移除事件及 DOM。
- [x] 网页导出排除 OGV 和 MP4；prepare 工具把 MP4、JS 复制为独立文件并注入脚本，验证缺失资源明确失败。
- [x] 切换 `run/main_scene` 到启动场景；更新 README 和部署说明。

## Task 3: 验收

**Files:** `tests/shop_acceptance.json`, `tests/test_prepare_web_export.py`, 以上实现文件。

- [x] 将启动测试纳入统一 manifest；Python 端验证真实临时 Web 导出目录准备、复制资源及重复执行保护。
- [x] 运行 `tools/check_shops.py --profile headless`，检查实际报告而非只看进程退出码。
- [x] 导出 Web release，跑现有 PCK 大小与场景一致性检查；浏览器按实际按钮验证完整流程及视口适配。
- [x] Windows 窗口验证实际 OGV 播放和最后画面；检查正式存档不被测试改动。
- [x] 自查 diff、运行 `git diff --check`，汇报已验证范围与限制；不自行推送或合并。
