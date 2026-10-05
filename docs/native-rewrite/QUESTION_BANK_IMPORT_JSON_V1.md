# 真题库单文件 JSON 导入合同 v1

本合同描述原生 iPad 真题库导入器接受的单文件格式。它不是应用备份格式，也不包含考试成绩、学习记录或其他应用数据。

## 顶层结构

JSON 顶层必须是对象，必需字段如下：

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| `format` | string | 固定为 `kaogong-question-bank` |
| `schemaVersion` | integer | 当前固定为 `1`；其他版本拒绝导入 |
| `paper` | object | 一个 `QuestionBankPaper` |
| `modules` | array | `QuestionBankModule` 列表 |
| `materials` | array | `QuestionBankMaterial` 列表 |
| `questions` | array | `QuestionBankQuestion` 列表 |
| `assets` | array | 真题图片资源列表，见下文 |

应用备份 JSON 缺少固定 `format` 标识，真题导入器会拒绝它；不会调用应用备份导入器，也不会把备份内容当作真题记录。

## 记录字段

实体字段名和 JSON 类型与原生 Codable 模型一致。必需字段不得省略，字符串不得用 `null` 代替；所有 ID 按原样保留，不重建、不改写。试卷、模块、材料、题目、图片资源的实体 ID 必须非空，并在这些实体集合间唯一。

- `paper`：`id: string`、`title: string`、`year: integer`、`examType: string`、`volume: string`、`source: string`、`importVersion: string`。
- 每条 `modules`：`id: string`、`paperID: string`、`sequence: integer`、`title: string`、`instruction: string`、`originalPage: string`。
- 每条 `materials`：`id: string`、`paperID: string`、`moduleID: string`、`type: string`、`text: string`、`imageAssetID: string`、`applicableQuestions: string`、`originalPage: string`。
- 每条 `questions`：`id: string`、`paperID: string`、`moduleID: string`、`number: integer`、`subject: string`、`type: string`、`materialID: string`、`stem: string`、`stemImageAssetID: string`、`options: array`、`answer: string`、`explanation: string`、`originalPage: string`。
- 每条 `options`：`id: string`、`text: string`、`imageAssetID: string`。选项 ID 属于每道题自己的命名空间，每题严格按 `A`、`B`、`C`、`D` 排列；不同题目之间可以重复这四个字母。图选项仍使用这三个原字段，不把图片字节放进题目记录。

## 图片资产字段与字节

每条 `assets` 保留 `QuestionBankAsset` 的元数据字段，并在同一个对象增加两个传输字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 稳定图片资源 ID |
| `paperID` | string | 所属试卷 ID |
| `ownerType` | string | `material`、`question` 或 `option` |
| `ownerID` | string | 材料 ID 或题目 ID |
| `role` | string | 用途，如 `题干整图`、`选项A`、`共用材料` |
| `path` | string | 稳定引用，格式为 `assets/文件名`；同一 JSON 内必须唯一 |
| `mimeType` | string | 目前支持与 PNG/JPEG 文件字节相符的 `image/png`、`image/jpeg` 或 `image/jpg` |
| `fileName` | string | 原始文件名，需与 `path` 中的文件名相同 |
| `originalPage` | string | 原始页码 |
| `dataBase64` | string | 图片原始字节的纯 Base64；不得添加 `data:` 前缀或换行 |
| `sha256` | string | 对解码后的原始图片字节计算的 SHA-256 十六进制摘要，不对 Base64 文本求摘要 |

导入器校验 Base64、SHA-256、MIME 与文件签名、路径、ID、所属关系和题目引用。验证通过后，`dataBase64` 解码到应用原有的本地图片文件路径；Base64 不写入题目列表记录或持久化的 `QuestionBankAsset` payload。图片字节只在生成并提交图片文件时使用，列表模型仍只持有既有稳定 ID 与本地资源路径。

## 文件及图片上限

- 单个 JSON 文件最多 64 MiB（以磁盘上的 UTF-8 JSON 字节数计算）。
- 单张解码后的图片最多 16 MiB。
- 一份真题包内所有解码图片合计最多 48 MiB。
- 超限、损坏或摘要不匹配的图片会以题号或图片名报告；导入不会压缩、重采样或重编码原图。制包时应拆分文件，而不是降低图表或题图清晰度。

## 关联和兼容性

试卷、模块、材料、题目、选项和资产必须保留原始稳定 ID；`paperID`、`moduleID`、`materialID`、`ownerID` 及图片资源 ID 必须形成闭合关联。每道题的 A–D 选项 ID 在题内唯一，不与其它实体 ID 做全局比较。每个资产路径唯一且只允许 `assets/文件名`，`fileName` 必须与路径末段相同；不得包含目录跳转。重复试卷仍由原预览界面提示；确认前不写入。

同一解析和严格校验结果进入现有导入预览、重复检测及原子事务提交。JSON 与旧版 ZIP 走相同预览和 commit；ZIP 中的工作簿及图片目录合同保持兼容。已核对的数据关系继续作为验证要求：Q71 的整图挂在题干，Q111–115 共用原材料，Q114 保留四张选项图片。

## 最小示例

示例省略了实际图片字节；正式文件中的字段都必须完整，图片 Base64 与摘要占位文本也必须替换为真实值：

```json
{
  "format": "kaogong-question-bank",
  "schemaVersion": 1,
  "paper": {
    "id": "paper-2019-city",
    "title": "2019年某地真题",
    "year": 2019,
    "examType": "行测",
    "volume": "",
    "source": "",
    "importVersion": "1"
  },
  "modules": [
    {
      "id": "module-2019-1",
      "paperID": "paper-2019-city",
      "sequence": 1,
      "title": "资料分析",
      "instruction": "根据资料回答问题",
      "originalPage": "16"
    }
  ],
  "materials": [],
  "questions": [
    {
      "id": "q-2019-071",
      "paperID": "paper-2019-city",
      "moduleID": "module-2019-1",
      "number": 71,
      "subject": "资料分析",
      "type": "单选题",
      "materialID": "",
      "stem": "根据整图资料判断下列说法正确的是：",
      "stemImageAssetID": "q-2019-071-full-figure",
      "options": [
        { "id": "A", "text": "A", "imageAssetID": "" },
        { "id": "B", "text": "B", "imageAssetID": "" },
        { "id": "C", "text": "C", "imageAssetID": "" },
        { "id": "D", "text": "D", "imageAssetID": "" }
      ],
      "answer": "A",
      "explanation": "",
      "originalPage": "16"
    }
  ],
  "assets": [
    {
      "id": "q-2019-071-full-figure",
      "paperID": "paper-2019-city",
      "ownerType": "question",
      "ownerID": "q-2019-071",
      "role": "题干整图",
      "path": "assets/q071-diagram.png",
      "mimeType": "image/png",
      "fileName": "q071-diagram.png",
      "originalPage": "16",
      "dataBase64": "<原始 PNG 字节的纯 Base64>",
      "sha256": "<原始 PNG 字节的 64 位 SHA-256 十六进制摘要>"
    }
  ]
}
```
