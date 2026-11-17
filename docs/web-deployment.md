# Web 自动部署

线上地址：https://eatvenlike.karaomi.cn

Cloudflare Pages 项目：`eatvenlike`；生产分支：`main`。

每次向 `main` 推送提交（包括合并 PR），Cloudflare 会从该提交自动构建并部署。其他分支不发布到生产环境。无需手动维护 `deploy/web`，也无需向 GitHub 添加 Cloudflare 密钥。

项目构建设置：

- 构建命令：`bash tools/build_web.sh`
- 输出目录：`build/web`
- 根目录：仓库根目录

脚本使用 Godot 4.7 和同版本 Web 导出模板。非 `main` 的 Pages 试玩构建检查店铺配置、场景坐标，并运行三家店的启动、营业、存档和画面显示测试。`main` 和未指定分支的本地构建运行全量回归。两种构建都校验实际导出的网页包和单文件大小。测试、导出或校验失败会终止部署，原成功版本继续提供服务。

在 Cloudflare 控制台的 Workers & Pages → eatvenlike → Deployments 查看日志和重试失败部署。`/version.json` 记录当前线上构建的分支和完整提交 SHA。原有自定义域名保持不变。

片头使用浏览器原生 MP4 播放；`tools/prepare_web_export.py` 会把 `art/opening/intro.mp4` 和 `web/opening_video.js` 复制到导出目录，注入播放器脚本。发布时必须保留 `opening.mp4`、`opening_video.js`，不能只复制 Godot 的四个导出文件。Web PCK 排除 Windows 用的 OGV 和原生末帧，Windows 导出排除网页 MP4 和网页末帧。

欢迎图的第一次真实点击会播放带原声音轨的片头视频。片头遵循音乐开关，局内背景音乐在进入店铺后由 ShopAudio 播放。资源与视频出错时可从末帧继续进入营业。

网页最初的加载页使用用户提供的 `loading.gif` 背景动画；部署时必须包含 `loading.gif`、`loading-font.ttf`、`loading_screen.css` 和 `loading_screen.js`。页面中间的真实百分比和“美味正在准备中…”、底部“小厨师们正在赶来，马上开饭！”圆角框由代码绘制。MP4 与引擎/PCK 同时预加载。Godot 就绪后最多再等片头下载 3 秒。片头准备好时，100% 后点击底部按钮播放片头和音乐。下载失败或超时时，点击后显示末帧和“开始营业”按钮。

Godot 使用 GIF 同源七帧图集与 `presentation/opening/loading_view.gd`，保持原动画像素、帧序和节奏；`loading-font.ttf` 保证网页与原生字形一致。GIF 和旧静态欢迎图不打入 PCK。引擎下载失败会保留加载图并提供刷新按钮；片头单独下载失败仍允许进入末帧回退流程。
