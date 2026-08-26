# 考公复盘原生 iOS

这是与 Web 版并行的全原生 SwiftUI/UIKit 客户端，不包含 Capacitor 或 WKWebView。

## 当前阶段

- SwiftUI 原生 Tab 和 NavigationStack。
- SwiftData 原始 JSON 兼容存储。
- Web v1 备份 JSON 导入骨架。
- URLSession 云 API 客户端和 Keychain token 存储。
- 第一阶段页面骨架：首页、学习库、复习、套卷、设置。

## 本地生成工程（macOS）

```bash
brew install xcodegen
cd native-ios
xcodegen generate
open KaogongReviewNative.xcodeproj
```

测试版 Bundle ID 是 `com.baoger07122.kaogongreview.nativebeta`，不会覆盖现有 Capacitor App。

