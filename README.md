# eatvenLike · 手作奶茶店

当前版本是竖屏奶茶店经营游戏，入口为 `presentation/tea_playtest/tea_playtest.tscn`，使用 Godot 4.6.3。

新店以 50 金币和一名小猫开局，点击展示柜解锁柠檬茶。营业额达标后依次开放红茶、调奶和加料产线；员工负责真实制作、搬运和配送，支持人工/传送带运输及 1/2/4 倍速。设备和配料可升级，菜单内可查看经营任务。

普通招募依次获得浣熊、狐狸和小兔子，可派遣、收回、培养或拖到工位坐班。菜单和员工页均可打开角色动作预览；兔子使用八方向帧动画，支持暂停、逐帧和调速。其他伙伴目前提供站姿。

经营、订单、库存、员工及岗位自动保存到独立的 `user://tea_shop.json`。菜单支持手动保存和重开店铺；重开保留已拥有员工及培养。建造和高级招募暂未开放。

## 运行和验证

```sh
# 首次打开或添加全局脚本后导入资源
godot --headless --path . --import
# 当前店铺的逻辑、存档、美术与字体回归
godot --headless --path . -s tests/run_all.gd
# 启动游戏
godot --path .
```

兔子帧完整性、界面和实际渲染检查见 [验证说明](docs/qa/README.md)。当前流程排查及已知问题见 [2026-11-01 报告](docs/qa/2026-11-01-playthrough/report.md)。

## 目录

| 路径 | 用途 |
| --- | --- |
| `game/tea_playtest/` | 物理生产、经营规则与店铺持久化 |
| `game/app/` | 共享存档入口、原子文件写入与数值序列化 |
| `content/tea/`、`content/defs/`、`content/staff/` | 当前店铺配置和共用资源定义 |
| `presentation/tea_playtest/` | 店铺画面、界面、员工和拖拽操作 |
| `presentation/reference/shop_art.tscn` | 当前店铺的可编辑分层美术场景 |
| `presentation/characters/`、`presentation/rabbit_walk_frames/` | 游戏内角色预览和兔子帧动画 |
| `art/reference/`、`art/rabbit_walk_frames/`、`art/ui/` | 正在使用的美术、动画、图标和字体 |
| `art_src/rabbit_walk_frames/` | 兔子原始帧、时长记录和图集构建工具 |
| `tests/` | 当前版本回归、交互与渲染检查 |
| `tools/` | 字体裁剪和 Web 导出后处理 |
| `docs/` | 当前美术需求、验证记录与清理说明 |

2026-11-01 已将面包店/灰盒旧版、未接入的骨骼动画试验、PSD、生图源文件和历史验证产物归档到仓库外；详见 [清理与恢复说明](docs/cleanup-2026-11-01.md)。旧版入口已移除。当前奶茶店仍使用的早期共用资源定义予以保留。
