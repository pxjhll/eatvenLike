# Web 自动部署

线上地址：https://eatvenlike.karaomi.cn

Cloudflare Pages 项目：`eatvenlike`；生产分支：`main`。

每次向 `main` 推送提交（包括合并 PR），Cloudflare 会从该提交自动构建并部署。其他分支不发布到生产环境。无需手动维护 `deploy/web`，也无需向 GitHub 添加 Cloudflare 密钥。

项目构建设置：

- 构建命令：`bash tools/build_web.sh`
- 输出目录：`build/web`
- 根目录：仓库根目录

脚本使用 Godot 4.7 和同版本 Web 导出模板。导入后运行全量回归和煎饼摊、奶茶店场景交互测试。导出后用独立测试档分别从 PCK 启动两家店，检查启动错误，再压缩 Web 引擎。任何检查失败都会终止部署，保留上一个成功版本。

在 Cloudflare 控制台的 Workers & Pages → eatvenlike → Deployments 查看日志和重试失败部署。`/version.json` 记录当前线上构建的分支和完整提交 SHA。原有自定义域名保持不变。
