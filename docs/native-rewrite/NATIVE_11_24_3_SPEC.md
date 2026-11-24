# 原生 11.24.3 发布批次规格

- 目标版本：11.24.3 / Build 165（2026-11-24，Asia/Shanghai）。
- 发布基线：`codex/ios-native-rewrite` 上的 11.24.2 / Build 164，提交 `957fd26f9e26049bb4371d540cebe9d08fad643b`。
- 本轮代码：只整合申论单题/套卷内单题作答与离线复盘实现，以及正文顶格、答题纸备用格和对照答案显示补充。详细交互以本索引列出的专项规格为准。
- 集成来源：`661a816820afe13fed4ef7ae8800b8872442a74e`，以及其直接后继 `aee2695a2cf24de8d7a399239643c0ddd0d0790e`。发布分支以这两个提交为来源；不发布功能开发分支上的其他历史或未提交文件。

## 本轮范围

1. 单题与套卷内单题共用申论答题、交卷复盘、作答历史、评分、心得、疑惑记录、续写和补录流程。范围和保存边界见 [申论离线复盘规格](IMPLEMENTATION_SPEC_SHENLUN_LOCAL_REVIEW.md) 与 [套卷材料和疑惑规格](IMPLEMENTATION_SPEC_SHENLUN_BATCH_PAPER_AND_DOUBTS.md)。
2. 申论材料粘贴、页面正文宽度和顶格规则见 [粘贴排版规格](IMPLEMENTATION_SPEC_SHENLUN_MATERIAL_FORMAT_ON_PASTE.md) 与 [答题纸范围规格](IMPLEMENTATION_SPEC_SHENLUN_TEXT_PAPER_BOUNDS.md)。
3. 本轮补充正文去自动首行缩进、粘贴段首去空格、按上限增加 100 个备用格、将段首中文/数字编号合排一格、避免段末或换行处句号孤立，以及完成作答后切换格子纸和普通文本。具体验收见 [正文顶格与答题纸备用格规格](IMPLEMENTATION_SPEC_SHENLUN_FLUSH_TEXT_AND_GRID_RESERVE.md)。
4. 工作流在这批申论源文件变更时仅构建并运行 `ShenlunPaperRepositoryTests` 和 `ShenlunWorkspacePaperLayoutTests`，不启用无关模拟器组，不手动派发同一提交。

## 交付验收

- 本地检查 `git diff --check` 与发布工作树的文件范围。
- 发布工作流运行固定领域行为检查、上述两组申论 iPad 模拟器 XCTest、真机目标归档、版本/资源校验及未签名 IPA 上传。
- 红格点击进入编辑并显示输入焦点、完成作答后进入复盘、再次作答时旧作答仍能从历史查看：本轮没有新增 UI 自动化覆盖这些完整导航交互，需在 iPad 实机核验，不将源码或领域测试结果替代交互验收。
- 发布完成条件：`native-v11.24.3` Release 的 IPA 资产存在且可下载；提交 SHA、Workflow run ID 和测试/归档结果写入交付记录。

## 专项规格

- [申论离线复盘](IMPLEMENTATION_SPEC_SHENLUN_LOCAL_REVIEW.md)
- [套卷材料和疑惑](IMPLEMENTATION_SPEC_SHENLUN_BATCH_PAPER_AND_DOUBTS.md)
- [材料粘贴排版](IMPLEMENTATION_SPEC_SHENLUN_MATERIAL_FORMAT_ON_PASTE.md)
- [正文宽度与答题纸边界](IMPLEMENTATION_SPEC_SHENLUN_TEXT_PAPER_BOUNDS.md)
- [正文顶格与答题纸备用格](IMPLEMENTATION_SPEC_SHENLUN_FLUSH_TEXT_AND_GRID_RESERVE.md)
