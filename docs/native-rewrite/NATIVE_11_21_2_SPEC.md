# Native 11.21.2 发布批次规格索引

目标版本：11.21.2 / Build 161（2026-11-21，Asia/Shanghai）。

## 本批执行范围

以下八份已确认实现规格是本批的功能依据；只纳入本轮明确提交的内容：

1. [统一涂鸦工具栏与退出反馈](IMPLEMENTATION_SPEC_SHARED_DOODLE_TOOLBAR.md)：统一原生涂鸦工具集合及退出按钮反馈。
2. [错题详情立即打开](IMPLEMENTATION_SPEC_DETAIL_IMMEDIATE_OPEN.md)：先用预热快照进入详情，并保留详情编辑后的稳定返回流程。
3. [标签长按管理与编辑返回稳定性](IMPLEMENTATION_SPEC_TAG_PICKER_AND_DETAIL_RETURN.md)：支持错题标签长按管理，编辑返回时保持详情内容一致。
4. [图形推理新增题的默认选项](IMPLEMENTATION_SPEC_GRAPH_REASONING_OPTION_DEFAULTS.md)：为新建图形推理题提供可编辑的 A–D 选项默认值。
5. [题型与待办的原生拖动排序](IMPLEMENTATION_SPEC_NATIVE_REORDER_CONTROLS.md)：题型管理和每日待办管理使用原生拖动排序。
6. [图形推理闪卡紧凑布局与涂鸦](IMPLEMENTATION_SPEC_GRAPH_FLASHCARD_DOODLE.md)：紧凑呈现题干、选项及翻面内容，并支持题图涂鸦；原型见 [graph-flashcard-stem-above.png](prototypes/graph-flashcard-stem-above.png)。
7. [考点通用分组与按当前组新增](IMPLEMENTATION_SPEC_KNOWLEDGE_POINT_GENERAL_GROUP.md)：选择器和管理页使用「通用」及当前分组筛选，并在当前组直接新增考点。
8. [仅为平面图形预填题干](IMPLEMENTATION_SPEC_GRAPH_REASONING_STEM_DEFAULT.md)：新建图推题仅在题型为「平面图形」时预填可编辑题干；原先对整个图推模块的预填由最终提交收窄。

## 整合基线与边界

- 发布分支基线为 `9c79bf293e3b8ef645362ca99063461fbe3f6747`，保留 11.21.1 的编译修复和自动交付记录。
- 按顺序整合功能提交 `63e8caf`、`036280e`、`ab48473`、`d300abc`、`6595ef9`、`2d8ab4a`、`483ce3b`、`1f86c58`、`9ee262d`。最后的 `9ee262d` 将题干预填限制为「平面图形」。
- 仅修改本批版本号、规格索引和交付摘要；保留原功能工作树里的未提交 `AGENTS.md` 与历史原型，不纳入发布提交。

## 验收与发布

- 完成本地补丁空白检查；依据既有交接记录，功能提交已通过语法树差异检查。
- 运行发布工作流中的域行为检查，其中包含 `LibraryKnowledgePointPolicyBehavior.swift` 的新增分组用例；执行 iPad 设备目标归档、资源与版本检查、IPA 打包和 Release 上传。
- 按用户要求跳过云端模拟器。工作流通过不能代替 iPad 实机交互验收；每份规格列出的触摸、拖动、导航和窄屏场景仍需在设备确认。
- 确认 `native-v11.21.2` 的 IPA 资产可下载后，才记为发布完成。推送发布分支一次，由 push 自动触发唯一工作流运行，不再手动触发。