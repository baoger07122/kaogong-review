# kaogong-review 原生 iOS 重写

## 冻结基线

- Web 版本：`8.25.3`
- Git 提交：`be387f17424e948b730feb25ac298ce5136ba433`
- Git 标签：`web-baseline-v8.25.3`
- 原生分支：`codex/ios-native-rewrite`
- 原生测试 Bundle ID：`com.baoger07122.kaogongreview.nativebeta`

原生测试版使用独立 Bundle ID，避免覆盖当前仍在使用的 Capacitor 版本。正式切换时再改回正式 Bundle ID。

## 原生版本号规则

- 格式：`月.日.当天原生迭代次数`，例如 `8.26.4`。
- 原生版本独立计数，不与仍在维护的 Web 版本共用当天次数。
- 同一天每生成一个新的可测试原生 IPA，末位递增一次。
- 跨天后的第一个原生 IPA 从 `.1` 开始。
- 修改 `native-ios/**` 后必须同步修改 `MARKETING_VERSION`、构建号和设置页展示版本。
- 构建失败且没有发布 IPA时可沿用该版本号继续修复；一旦 IPA 已发布，后续原生代码修改必须使用新版本。
- 纯文档、验收记录和说明文字修改不升级 App 版本，也不重复构建 IPA。
- 云端构建按 `Asia/Shanghai` 日期自动校验版本号，防止漏改或沿用已经发布的版本。

## iPad 设计预览与截图验收规则

原生 UI 不采用“改一次样式、安装一次 IPA”的低效流程。视觉调整统一分为三层：

1. **设计图确认**：先输出候选布局图片，只确认结构、密度、尺寸、颜色和选中状态；不修改正式 App 代码，不升级版本。
2. **SwiftUI 真实截图确认**：设计通过后实现代码，由 macOS/Xcode 使用 iPad 模拟器或固定 SwiftUI 视口输出截图；这张图代表真实代码渲染，不需要安装 IPA。
3. **真机 IPA 验收**：模拟器截图通过后才生成 IPA，真机重点验证动画手感、震动、键盘、安全区、分屏、旋转、Apple Pencil、性能和数据保存。

每个主要页面至少检查以下视口：

- iPad 横屏全屏。
- iPad 横屏约半屏宽度（主要使用场景）。
- 半屏宽度附近的较窄和较宽边界，防止拖动分屏分隔线时布局突然错乱。

实现要求：

- 使用 SwiftUI 自适应布局和尺寸断点，不按截图像素硬编码页面。
- 设计稿和实现截图使用同一组点尺寸、字体层级、安全区和内容数据。
- 模拟器型号应尽量与用户实际 iPad 型号一致；实际型号未确认前，半屏截图只作为基准预览，不能冒充真机精确尺寸。
- 每轮截图明确标注设备型号、方向、视口宽高、系统版本、页面状态和对应 Git 提交。
- 视觉差异在截图阶段返工；只有截图确认后才发布新的测试 IPA。

### Swift Playgrounds iCloud 预览

- 仓库内预览源：`native-preview/KaogongNativePreview.swiftpm/`。
- Windows iCloud 同步目标：`C:\Users\bao\iCloudDrive\iCloud~com~apple~Playgrounds\KaogongNativePreview.swiftpm`。
- 预览项目只使用模拟数据，不读取正式 App 数据库或登录凭证。
- 视觉方案更新先同步到该固定项目；用户在 iPad Swift Playgrounds 中重新打开即可查看。
- 预览编号独立于正式 App 版本；只有方案确认并进入 `native-ios/**` 后才升级原生 App 版本和构建 IPA。

## 不可变边界

1. 正式 iOS App 的页面和业务交互全部使用 SwiftUI/UIKit。
2. 不在正式 App 中嵌入现有 Web 页面或 Web 编辑器。
3. 涂鸦使用 PencilKit；富文本使用 TextKit/UIKit；速算使用 SwiftUI；思维导图使用 SwiftUI Canvas/Core Graphics。
4. Web `main` 独立运行，本分支不得修改、覆盖或强推 Web `main`。
5. 现有备份 JSON、记录字段和云端 API 必须保持可读兼容。
6. 未识别的旧字段必须原样保留，不能因为原生模型尚未使用就丢弃。
7. 每个阶段必须更新验收矩阵并生成可安装的未签名 IPA。

## 阶段顺序

1. 冻结功能、交互、数据、备份与 API。
2. 原生工程、导航、首页、学习库骨架。
3. 错题、笔记、便签、标签。
4. 复习、套卷、学习统计。
5. TextKit 原生富文本编辑器。
6. PencilKit 原生涂鸦。
7. SwiftUI 原生速算。
8. 原生思维导图。
9. 数据迁移、备份、云同步完整闭环。
10. 按验收矩阵全量对照。

## 文档

- `NATIVE_REWRITE_MASTER_PLAN.md`：完整阶段计划、三层验收勾选表和用户签收记录。
- `FEATURE_ACCEPTANCE.md`：页面、功能和交互验收合同。
- `DATA_AND_API_CONTRACT.md`：本地数据、备份 JSON 与云 API 合同。
- `MIGRATION_PLAN.md`：旧数据迁移、回滚和正式切换方案。
