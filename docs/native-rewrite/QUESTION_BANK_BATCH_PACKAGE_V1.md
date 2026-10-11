# 批量题库更新包 v1

本文定义 App 批量导出和批量更新共用的文件契约。它是题库内容更新格式，不是全量备份/恢复格式。

## ZIP 布局

```text
manifest.json
papers/0001.json
papers/0002.json
assets/<lowercase-sha256>.png|jpg|jpeg
```

`papers/NNNN.json` 沿用单卷 JSON 的 `format: "kaogong-question-bank"`、`schemaVersion: 1` 和 `paper`、`modules`、`materials`、`questions` 字段。其 `assets` 固定为空数组；图片字节和资源元数据由根清单提供。文件名序号不含用户提供的 ID，避免路径注入。

## 根清单

根清单必需字段：

```json
{
  "format": "kaogong-question-bank-batch",
  "schemaVersion": 1,
  "operation": "update",
  "createdAt": "RFC3339 UTC timestamp",
  "papers": [],
  "assets": [],
  "organization": { "groups": [], "paperOrder": [] }
}
```

- `papers` 必须非空。每项必需 `paperID`、`path`、`sha256`。`path` 必须是唯一、安全的相对路径，且位于 `papers/`；文件内 `paper.id` 必须与 `paperID` 完全相等。SHA-256 针对 JSON 原始 UTF-8 字节。
- `assets` 可为空。每项必需 `id`、`paperID`、`ownerType`、`ownerID`、`role`、`logicalPath`、`entryPath`、`mimeType`、`fileName`、`originalPage`、`sha256`、`byteCount`。没有原始页码时使用空字符串，不省略字段。
- `logicalPath` 是单卷内唯一的 `assets/<fileName>`，被 paper JSON 中材料/题目的 `imageAssetID` 引用。`ownerType` 为 `material`、`question` 或 `option`；选项图的 `ownerID` 是所属 `question.id`。
- `role` 必须使用单卷 v1 的精确值：材料图片为 `共用材料`，题干图片为 `题干整图`，选项图片为 `选项A`、`选项B`、`选项C` 或 `选项D`。导入器不映射或忽略这些用途值。
- `entryPath` 是安全 ZIP 相对路径，固定为 `assets/<sha256>.<ext>`。相同字节可以共用一个 ZIP entry，但每个逻辑 asset 保留独立的 ID、引用和 owner 行。
- v1 图片仅支持 PNG (`image/png`, `.png`) 和 JPEG (`image/jpeg` 或兼容 `image/jpg`, `.jpg`/`.jpeg`)；MIME、扩展名、文件头、SHA-256 和字节数必须相符。HEIC/AVIF 不支持。
- `organization` 必需。`groups` 和 `paperOrder` 均为数组，可以为空。group 项字段为 `id`、`name`、`order`；paperOrder 项为 `paperID`、`groupID`（允许显式 `null`）、`order`。paperOrder 必须恰好枚举本包中每个 paperID 一次；groups 包含这些试卷引用的本机分组。它只作为导出快照，更新时不覆盖本机分组和排序。

## 题目和排序

- `paper.source` 按单卷 v1 必需；`sourcePapers` 可选。二者都不用于匹配更新目标，目标只按精确 `paperID` 确认。
- 模块 `sequence` 是模块顺序权威：值必须唯一，`modules` 数组按它升序排列；允许有间隔，不强制重编号。
- `questions.number` 必须在全卷唯一并连续为 `1...N`，`questions` 数组也按 number 升序。模块切换不重置题号；更改 number 不更改 question ID。
- `paperID`、module/material/question/asset ID 均须非空且按引用闭合。单卷内不同实体不可复用 ID；A-D 选项 ID 仅在题目内命名。数组中的缺失 question ID、跨卷 ID 冲突或不匹配目标属于待确认项，不能按名称/年份/题号猜测。

## 更新和保留策略

更新只精确匹配 paperID/questionID；缺少试卷目标、缺失或冲突 ID 不自动插入/覆盖，预览中标记待确认。被包含的现有题目更新正文、选项、答案、分类、题号、材料引用/内容及图片；新增题目必须在预览显式确认。包外试卷/题目不删除。

允许更新的题库内容字段包括 paper、module、material、question 的来源正文、题干、选项、答案、解析、细分类、模块/材料引用、原始页码、provenance、全卷题号/模块顺序和图片资源。现有记录的难题/复习标记、`knowledgePoints`、`weaknessTags`、作答/错题状态、涂鸦、笔记及自定义分组/试卷排序由本机值优先；更新现有题目时保留这些字段和未知的本机 payload 字段。新题可以从包中带入标记。手工编辑的题干/选项属于可更新内容，预览需提醒可能被覆盖。

导入先校验清单、全部 ID/引用、图片摘要、文件路径和资源，再进入单次数据库事务。图片先写入独立 generation；数据库事务失败时回滚并删除暂存 generation，成功后再清理旧资源。不得留下部分试卷更新。

数据库事务前，App 会把本次将覆盖记录的原始 payload 以 Base64 保存到应用的 `Application Support/QuestionBankBatchBackups/latest-payload-backup.json`，并记录记录 ID、来源包 SHA-256 和 payload SHA-256。备份采用原子文件写入；若备份失败，本次数据库事务不会开始。每次后续批量更新会原子替换这一个“最近一次”快照。该文件只备份数据库 payload，不包含旧图片文件，因此它不是完整应用备份或独立恢复包。

## 兼容策略

独立单卷 JSON v1 和旧版 XLSX ZIP 继续走现有导入流程。批量 ZIP 必须由根 manifest 的 format/schemaVersion 明确识别；缺清单、未知 schemaVersion、路径越界、重复路径/ID、摘要或 MIME 校验不符时整包拒绝，不修改现有数据。未知输入字段可由制作工具保留，但 App v1 不读取其语义。
