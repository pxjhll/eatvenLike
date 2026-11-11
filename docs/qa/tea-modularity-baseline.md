# 奶茶模块化A阶段：基线与兼容验证

日期：2026-11-11。原实现提交：`9bc1b20364e239e8719e0511be2c1a4d824e3601`。
工作分支：`codex/tea-baseline-shared-staff`。本阶段不提交、不推送。

## 完成范围

- T01：在生产资源改动前冻结奶茶600秒确定性轨迹、六种员工属性、两种窗口的正式场景画面，以及真实ShopSave格式的未开店/营业中合成旧档。
- T02：六种员工逐字段提取为`content/characters/staff/`共享SpecStaffKind；奶茶改为引用。其他店未切换基准。
- T03：读取旧档、续跑60秒、重存与重开一致；独立基础属性刷新保留身份、岗位、进度、加成，并在保存前备份原档。
- 新增显式`SpecShop.copy_for_editing()`，编辑变体时隔离外部Resource；普通运行保持共享定义引用。

## 冻结事实

`tests/baselines/tea_modularity.json`包含60个完整状态hash、84条业务事件记录、39次销售和4191个行走采样。完整状态包括RNG、库存、预留、员工、订单、岗位、计时器和日志。事件payload使用完整Variant字节hash，时刻按JSON发布格式比较，不放宽状态hash或采用浮点容差。

提取前后奶茶内容指纹一致：

- gameplay：`9b85f1ef12e15c5da834ee1edb31eb54d4631ce2913afbc92bce68dac248004d`
- structure：`ccfde4b1e38c590f7a176648bc23fb87760d1b52a3be00b3f3567de54c76c945`

`tests/fixtures/tea_modularity/`中的两个ShopSave文件和续跑摘要来自提取前原实现，不是玩家数据。改造后未重录或覆盖这四份基线/夹具文件，hash留存在本地frozen-manifest.json。

## 本地结果

引擎：Godot `4.6.3.stable.official.7d41c59c4`。

| 检查 | 结果 | 原始日志（_work/shop_modularity/phase-a/下） |
|---|---|---|
| 最终完整规则套件 | 382用例，0失败，退出清洁 | final-rules-clean.log |
| 共享定义、原轨迹、内容刷新、存档专项 | 30用例，0失败 | final-focused.log |
| 奶茶正式界面 | 84检查，0失败，退出清洁 | final-tea-clean.log |
| 煎饼摊正式界面 | 88检查，0失败，退出清洁 | final-pancake-clean.log |
| 第三店正式界面 | 33检查，0失败，退出清洁 | copy-api-lifetime.log（verbose） |
| 店铺数据与场景契约 | 生产三店和面馆夹具，共4店通过 | final-authoring.log |
| 空间导出一致性 | 奶茶、煎饼摊一致；第三店尚无Nav，不由该工具检查 | final-layout.log |

这是A阶段验证，不表示第三店的导航与动作已经修复。Godot4.7的远端CI尚未运行。

## 表现证据

通过正式`shop_play.tscn`与既有TestSession实例化场景，固定推进到12秒，记录720×1280与1280×720画面。采集器与数据在工作区，未修改游戏UI。

- 横屏提取前后整图像素完全相同。
- 竖屏差异仅在底部“店铺”按钮的悬停显示范围(29,1178)–(240,1255)内，角色与场景区域像素一致。
- 角色逻辑高度维持员工128、顾客110；计入原窗口拉伸换算后，两次记录的屏幕包围盒最大差异为0.1281像素。
- 原始截图、画布坐标测量与换算报告均保留在`_work/shop_modularity/phase-a/`，不提交原图或中间图。

## 执行中查明的边界

1. 拉取main后，本地字体导入缓存source_md5仍为旧值，与仓库当前TTF不一致。改造前全测出现两项字体失败；重新导入后，字体专项3用例通过，最终完整套件全部通过。未修改字体源文件。
2. Godot的`duplicate(true)`不复制外部员工Resource，原有店铺变体测试会污染共享属性。已有代码不应静默依赖该默认行为。新`copy_for_editing() -> Resource`使用`duplicate_deep(Resource.DEEP_DUPLICATE_ALL)`，两个编辑变体的测试套件改用该入口。
3. 本地4.6.3中，新增深复制方法若使用SpecShop自类型返回/转换会令依赖脚本退出滞留。对照移除方法后退出清洁；改为原生Resource返回类型后保持隔离语义且所有界面清洁退出。失败、最小对照和修正日志均保留，不把退出码0当作没有运行错误。

## 重复验证

每次运行都使用隔离APPDATA，不使用真实进度：

```powershell
$env:APPDATA = 'D:/Tes/eatventure/_work/shop_modularity/phase-a/session-lifecycle-userdata/recheck'
$engine = 'D:/Godot_v4.6.3-stable_win64/Godot_v4.6.3-stable_win64_console.exe'
& $engine --headless --path 'D:/Tes/eatventure' -s tests/baselines/capture_tea_modularity.gd -- --check
& $engine --headless --path 'D:/Tes/eatventure' -s tests/run_all.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tests/render_shop_tea.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tools/validate_shops.gd
& $engine --headless --path 'D:/Tes/eatventure' -s tools/sync_shop_layouts.gd -- --check
```

基线采集器默认只检查；写入必须显式传`--write-baseline`或`--write-save-fixtures`，且文件已存在时拒绝覆盖。

## 后续入口

T04起开始统一逻辑尺度与表现配置，再接共享运动和动作协议。本阶段不修改煎饼摊/第三店的速度、经济、布局或流水线，也不把“新增全局资源”误报为已完成整个模块化体系。
