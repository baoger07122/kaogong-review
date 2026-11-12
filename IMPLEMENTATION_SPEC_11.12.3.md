# 11.12.3 发布后修复实现规格

本轮基线为 iPad 原生版 11.12.2（build 141，代码提交 `cd4e93aa`）；开工时发布分支头为交付清单提交 `d2603d7`。本轮仅处理下列两项，目标版本为 11.12.3 / build 142。

## 1. 修复错题详情的关联词语摘要

**入口和现象。** 学习库 → 错题详情 →「关联词语库」。例如 2021 国考第 27 题关联「简单｜机械」后，条目标题下显示 `[[NATIVE_TABLE:…]]` 等编码内容。错题编辑页的「关联词语库」已选条目使用同一摘要来源，也要一并修复。

**源码依据。** 详情 `LibraryRecordDetailView.comparisonBlock` 与编辑页 `LibraryRecordEditorSections.linkedWordSection` 展示 `LibraryRecordSnapshot.summary`。当前词语摘要从旧字段挑选，并直接作为文字显示；原生表格、图片、公式附件标记因此泄漏到界面。可安全处理的正文已在 `wordCardBody` 中，经 `LibraryComparisonDocumentProjection.wordContent` 从单条释义、当前比较文档或旧记录投影取得。通用 `plainText` 不负责附件标记。错题笔记是下方独立的 `LibraryInlineNoteView`，不属于本项。

**实现规格。**

- 详情和编辑两个关联行继续使用 `LibraryRecordSnapshot.summary`，其词语摘要改为从快照 `wordCardBody` 提取。单条词语取释义；组辨析取 `comparisonDocument`，旧记录在尚无新正文键时取兼容投影；显式存在但内容为空的新正文键生成空摘要。
- 用 `LibraryWordCardPreviewText` 的有界富文本解析与附件转换。表格转为可读单元格文字，图片／公式显示简短名称，无法解码或无效的附件显示既有可读占位或忽略。归并换行和连续空白，再按 Swift `Character` 截取 120 个字符；只有超过 120 个字符才追加省略号。转换后才截取。
- 空摘要不显示副标题。详情保持标题 13 pt Medium、摘要 11 pt 次级色、最多两行；编辑保持标题 12.5 pt Medium、摘要 10.5 pt 次级色、最多一行。标题、箭头、选择关联和打开词语详情继续使用原行为。
- 仅修复列表摘要。完整词语富文本、表格和加粗仍由原详情／编辑链路处理。摘要继续使用当前解析器的输入扫描和附件尺寸上限，不在关联行加载完整富文本视图。任何无法解析的输入都回退为可读占位或空摘要，不显示原始附件编码。

**验收。**

1. 将含两个 GPT 粘贴表格的「简单｜机械」关联到错题；检查详情和错题编辑页摘要均为可读文本。打开词语详情检查两个表格、局部加粗和内容顺序。
2. 覆盖单条释义、旧组辨析、新组正文明确清空、仅表格正文、图片、公式、非法／未闭合附件标记；两个入口只显示正文摘要或可读占位。空摘要只显示标题。返回后可继续编辑并保存错题笔记。
3. 源码／构建检查与实际 iPad 交互分别记录；不把编译通过当成交互验证。

## 2. 修复言语理解错误类型目录点按无响应

**入口和实机结果。** 设置 → 言语理解错误类型管理。11.12.2 页面显示模块名称和箭头，但用户点按后仍留在当前页。上次发布只确认代码进入 IPA；本项按用户此次截图和设备操作重新纳入。

**源码依据。** `LibraryErrorTypeModulesView` 通过 `SettingsView` 回调到 `RootTabView.openVerbalErrorModule`；该函数只在 `settingsPath.last == .errorTypes(.verbalReasoning)` 时追加二级路由，否则静默返回。源码确认存在静默退出路径；实际点按时回调与路径值没有日志，设备上具体中断位置仍待核实。

**实现规格。**

- 保留设置首页进入目录的 `SettingsRoute.errorTypes(.verbalReasoning)`。目录每行改为原生 `NavigationLink`，目的地直接构造 `LibraryErrorTypeManagerView(subject: .verbalReasoning, module: module)`，并应用 `secondaryPageTabBarHidden()`。旧通用入口传 `nil`。使用当前设置导航栈和系统返回手势。
- 移除 `RootTabView.openVerbalErrorModule`、回调传递、`SettingsRoute.verbalErrorTypes(module:)` 及对应目的地注册。模块目录不再依赖手动检查／追加 `settingsPath`。
- 保留系统 `List` 和模块次序。每行文字左对齐、14 pt Regular、系统主文字色、至少 44 pt 高；使用系统箭头和按压态，行内空白可点。每行只含一个导航操作并保留无障碍标识。只有存在旧通用类型时，才在目录末尾显示该入口。
- 管理页继续按模块标题显示；新增、改名、排序、删除和模块隔离沿用现有仓储。空模块仍能进入并新增。旧通用项仍可管理现有记录。

**验收。** 从设置首页进入目录，点击逻辑填空文字、中心理解空白区域、词句理解的箭头，逐项确认进入正确模块；返回逐级回目录和设置首页。检查空模块新增、已有模块改名／排序／重开保存、模块隔离和旧通用入口。把目录实际点击进入管理页单独标为 iPad 实机待验收；编译和归档只计入构建结果。
