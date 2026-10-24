# eatvenLike

Godot 4.7（GDScript）工程。结构按 Notion「Architecture Contract v1.1｜Godot 版」搭建，玩法以 02 和单店节奏页为准。

这一版是**白面包单店模拟 + 2D 3/4 灰盒现场**：能看到物料输送、员工装卸/服务、备料库存和顾客排队。点击工位可升级或启用并联，顶部可以调岗和存档，列表图标可展开原有调试 HUD。新手引导、移动端手感和正式美术仍待后续制作。

灰盒资源包含六类工位、兔子/小熊/小猫三套动画、顾客、四种物料及 UI 图标；当前店铺仍只有白面包，切片机与小猫资源不会自动变成已解锁内容。独立打开 `presentation/graybox/asset_gallery.tscn` 可查看资源。

源图、PNG 和动画帧信息见 `art/graybox_manifest.json`；生成方式与授权见 `art/CREDITS.md`。渲染与输入验收记录见 [docs/qa/README.md](docs/qa/README.md)。

## 跑起来

```sh
# 第一次（或新增 class_name 之后）先导入，生成全局类缓存
godot --headless --path . --import

# 无头回归测试（不装插件），失败时退出码为 1
godot --headless --path . -s tests/run_all.gd

# 打开游戏
godot --path .
```

## 白面包这条线

面粉箱（外购，每 3 秒 1 份）→ 传送带 → 面团台（自动，2 秒）→ 传送带 → 烤炉（员工装入 0.8 秒 → 烘烤 4 秒 → 员工取出 0.8 秒）→ 传送带 → 备料架 → 前厅柜台（员工服务 1.5 秒，售价 10）。
烤炉旁有一个并联槽（120 金启用），面团台到两台烤炉默认轮流送、跳过堵住的一路。顾客约每 4 秒一位，等 18 秒没人接待就走。任务：白面包卖出 30 份，完成后可以换店。

所有数字都在 `content/` 的 .tres 里（占位值），直接在 Godot 里编辑。

## 目录

| 路径 | 内容 |
| --- | --- |
| `game/app/` | `app.gd`（唯一 Autoload，换店、存读档）、`profile.gd`、`save_service.gd` |
| `game/sim/` | `game_sim.gd`（Node，固定步长 0.1 秒，tick 顺序和中转）、`snapshot.gd`、`save_util.gd` |
| `game/sim/commands/` | 7 条命令，每条一个文件（validate + commit） |
| `game/production/` | 后厨工位、传送带、备料架与预留 |
| `game/workforce/` | 员工、请求认领、人工进度、效率倍率（唯一一处） |
| `game/front_hall/` | 顾客、订单、前厅工位 |
| `game/economy/` | 金币、累计营业额、已结算 saleId |
| `game/progress/` | 已解锁菜品、任务、店铺完成度 |
| `game/diagnostics/` | 只读统计 |
| `content/defs/` | Resource 类（只读 Def） |
| `content/bakery/`、`content/staff/`、`content/catalog.tres` | 面包店与员工数据 |
| `presentation/` | `shop.tscn`、graybox 只读表现层、操作界面与可折叠调试 HUD |
| `tests/` | `run_all.gd` + 回归用例（契约第 6 节 10 条不变量各一个） |
| `art/{env,char,machine,belt,item,ui,fx}` | 原创灰盒 PNG、动画表、字体与资源清单；传送带和反馈图形由表现层绘制 |
| `art_src/graybox/` | 原创 SVG、源图生成脚本、Godot PNG 导出脚本 |

## 相对契约 v1.1 的补充

- Def 多了 4 个类：`SlotDef`（机位：工位 Def + 是否 LOCKED + 并联槽 + 网格坐标）、`ConnectionDef`（允许的连接与长度）、`ShopStageDef`（解锁表一行）、`GameCatalog`（店铺顺序和员工）。
- 备料架作为连接终点，id 固定为 `shelf`。
- `SetConnection` 带一个 `connected` 参数，接上或断开；断开后线上物料原地不动，可用 `ClearItems` 清理。
- 为满足不变量 9（步长无关），每 tick 在第 4 步新请求提出后再派一次工，人工和机器完成时把本 tick 剩下的时间接着用。步长 0.05 和 0.1 之间产量相差不到 1 件；步长放到 0.2 时，因为传送带交付等仍有一个 tick 的交接，十分钟大约少 2 个面包。
- 存档：Godot 的浮点文本解析不能逐位还原，存档里的 float 编成 8 字节十六进制；JSON 不排序键（字典顺序也是状态）。这样才能做到不变量 10 的「完全一致」。
- 顾客只在还没人接待时会因耐心耗尽离开，所以目前不需要 Workforce 中途释放请求。
