# Native 11.23.1 发布批次规格索引

目标版本：11.23.1 / Build 162（2026-11-23，Asia/Shanghai）。核对时远端最新发布为 11.21.2 / Build 161，`native-v11.23.1` 与 `native-v11.22.1` 均无远端标签。

## 本批执行范围

以下八份实现规格是本轮功能依据；不重复纳入其他历史事项：

1. [错题笔记表格线与单元格换行](IMPLEMENTATION_SPEC_INLINE_NOTE_TABLE_PRESENTATION.md)：错题笔记中的横线表格和窄列单元格折行。
2. [待复习词语紧凑网格](IMPLEMENTATION_SPEC_WORD_REVIEW_COMPACT_DUE_GRID.md)：压缩待复习词语卡片间距，保持现有响应式列数。
3. [词语库卡片摘要](IMPLEMENTATION_SPEC_WORD_LIBRARY_CARD_SUMMARY.md)：卡片展示实际释义或辨析摘要，保留旧内容回退及全文搜索。
4. [错题详情菜单去重做项](IMPLEMENTATION_SPEC_ERROR_DETAIL_REDO_MENU.md)：移除重复的重做入口。
5. [首页倒数日删除菜单](IMPLEMENTATION_SPEC_HOME_COUNTDOWN_DELETE_MENU.md)：将删除操作移入编辑菜单并增加确认。
6. [词语复习编辑菜单导航](IMPLEMENTATION_SPEC_WORD_REVIEW_EDITOR_MENU_TRANSITION.md)：编辑跳转延后到关闭菜单后执行，避免覆盖层卡住或闪退。
7. [词语详情阅读排版](IMPLEMENTATION_SPEC_WORD_DETAIL_TYPOGRAPHY.md)：保留正文原字体字重；表格 13 pt、按窄窗可用宽度换行。规格内链接了用户确认的词语详情参照图。
8. [词语复习关联错题与评价返回](IMPLEMENTATION_SPEC_WORD_REVIEW_LINKED_ERROR_NAVIGATION.md)：从同一词条打开关联错题后返回同一词条；评价成功后退出当前详情并前进到下一词，最后一词回到待复习页。

## 整合基线与边界

- 发布分支基线：`3d4605de7ff0d13e998f6cdf68a58ec40625f979`，保留 11.21.2 的原生编译修复、版本清单和交付记录。
- 按顺序整合 `a8a56a8`、`6a6441d`、`646b5ab`、`c832aed`、`41e092d`、`9f8e7be`、`378e082`、`59e328c`。
- 原功能工作树的未提交 `AGENTS.md` 与历史原型保留在原处，不进入发布提交。仅在本批版本准备提交中更新 `native-ios/project.yml`、本规格索引和实现摘要。

## 验收与发布

- 完成本地差异空白检查，并运行发布工作流配置的域行为检查、iPad 设备目标归档、资源／版本校验、IPA 打包与上传。
- 词语摘要和排版回归用例在 `LibraryDraftStoreTests.swift`；按用户要求跳过云端模拟器，因此这些 XCTest 本轮不宣称已运行。需将其列为未验证项。
- 按用户要求跳过云端模拟器。归档成功不等于 iPad 实机验收；关联错题返回同一词条、评价后下一词与末词返回、编辑菜单关闭、倒数日删除确认、表格窄窗折行及待复习卡片布局仍须设备确认。
- 仅在 `native-v11.23.1` 的 Release IPA 确认可下载后报告发布完成。向 `codex/ios-native-rewrite` 推送一次触发唯一自动工作流，不手动重复触发。