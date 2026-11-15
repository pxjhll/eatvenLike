# Web 自动部署

线上地址：https://eatvenlike.karaomi.cn

Cloudflare Pages 项目：`eatvenlike`；生产分支：`main`。

每次向 `main` 推送提交（包括合并 PR），Cloudflare 会从该提交自动构建并部署。其他分支不发布到生产环境。无需手动维护 `deploy/web`，也无需向 GitHub 添加 Cloudflare 密钥。

项目构建设置：

- 构建命令：`bash tools/build_web.sh`
- 输出目录：`build/web`
- 根目录：仓库根目录

脚本使用 Godot 4.7 和同版本 Web 导出模板。非 `main` 的 Pages 试玩构建检查店铺配置、场景坐标，并运行三家店的启动、营业和存档测试。`main` 和未指定分支的本地构建运行全量回归。两种构建都校验实际导出的网页包和单文件大小。测试、导出或校验失败会终止部署，原成功版本继续提供服务。

在 Cloudflare 控制台的 Workers & Pages → eatvenlike → Deployments 查看日志和重试失败部署。`/version.json` 记录当前线上构建的分支和完整提交 SHA。原有自定义域名保持不变。
