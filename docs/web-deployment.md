# Web 自动部署

线上地址：https://eatvenlike.karaomi.cn

Cloudflare Pages 项目：`eatvenlike`；生产分支：`main`。

每次向 `main` 推送提交（包括合并 PR），Cloudflare 会从该提交自动构建并部署。其他分支不发布到生产环境。无需手动维护 `deploy/web`，也无需向 GitHub 添加 Cloudflare 密钥。

项目构建设置：

- 构建命令：`bash tools/build_web.sh`
- 输出目录：`build/web`
- 根目录：仓库根目录

脚本使用 Godot 4.7 和同版本 Web 导出模板，先导入资源并运行全量、商店 UI 和营业交互回归，再导出并压缩 Web 引擎。测试、导出或单文件大小校验失败会终止部署；失败构建不会替换上一个成功版本。

在 Cloudflare 控制台的 Workers & Pages → eatvenlike → Deployments 查看日志和重试失败部署。`/version.json` 记录当前线上构建的分支和完整提交 SHA。原有自定义域名保持不变。

片头使用浏览器原生 MP4 播放；`tools/prepare_web_export.py` 会把 `art/opening/intro.mp4` 和 `web/opening_video.js` 复制到导出目录，注入播放器脚本。发布时必须保留 `opening.mp4`、`opening_video.js`，不能只复制 Godot 的四个导出文件。Web PCK 排除 Windows 用的 OGV 和原生末帧，Windows 导出排除网页 MP4 和网页末帧。

欢迎图的第一次真实点击同时用于解锁游戏背景音乐。片头本身没有音轨；背景音乐复用 ShopAudio，遵循音乐开关，进店后同曲目不重播。资源与视频出错时可从末帧继续进入营业。

欢迎图现在同时作为网页最初的加载页：`welcome.png`、`loading_screen.css` 和 `loading_screen.js` 在引擎加载前显示，真实下载进度覆盖原图中的按钮。MP4 会与引擎/PCK 同时预加载，资源与启动场景都准备好后，再揭示同图的 Godot 欢迎按钮；点击后才播放片头和音乐，不会再次要求点击欢迎页。部署必须包含这三个新增独立文件。引擎下载失败会保留欢迎图并提供刷新按钮；片头单独下载失败仍允许进入原有回退流程。
