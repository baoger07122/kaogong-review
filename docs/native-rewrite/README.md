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
