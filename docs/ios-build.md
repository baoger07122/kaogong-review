# iOS Capacitor 构建说明

## 当前方案

- App 使用 Capacitor iOS 外壳。
- 页面在线时从 `https://kaogong-review.onrender.com/` 加载。
- `www/index.html` 是 IPA 内置的备用页面，由 `npm run build` 自动生成。
- 当前只接入 Haptics；本阶段不加入通知插件。
- IPA 工作流只生成未签名包，不保存 Apple 证书或 provisioning profile。

## GitHub Actions

工作流文件：`.github/workflows/ios-unsigned.yml`

工作流使用 GitHub macOS Runner、Node.js 22 和 Xcode。没有提交 `ios/` 工程时，工作流会自动执行 `npx cap add ios`；存在工程时则复用已有工程。之后执行 `npx cap sync ios`、`xcodebuild build`，最后把 `App.app` 打包成：

```text
kaogong-review-X.Y.Z-unsigned.ipa
```

工作流只在 Capacitor 配置、依赖、构建脚本或全局触感入口变化时自动运行，也可以在 GitHub Actions 页面手动运行。普通网页功能修改继续由 Render 部署并通过网页热更新生效。

## 自签安装

下载 GitHub Actions 的 Artifact 后，用自己的自签工具处理未签名 IPA。证书、私钥和 provisioning profile 不要提交到仓库，也不要写入工作流文件。

## 原生与网页更新边界

- HTML、CSS、JavaScript 和业务逻辑：更新 Render，不需要重装 IPA。
- Capacitor 插件、Info.plist、App 图标、Bundle ID 和 Swift 原生代码：重新运行 IPA 工作流并重新自签。

