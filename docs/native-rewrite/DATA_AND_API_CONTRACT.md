# 数据、备份与云 API 冻结合同

## 兼容原则

原生层使用“集合名 + 记录 id + 原始 JSON”作为权威兼容格式。Typed Swift 模型只作为读取视图；任何未知字段都必须跟随原始 JSON 保存和再次导出。

时间字段继续使用 ISO 8601 字符串。ID 保持现有前缀和字符串形式，不重新编号。

## 本地集合

| 备份字段 | 本地集合 | 云端集合 | 说明 |
|---|---|---|---|
| `errors` | `errors` | `errors` | 普通错题和申论错题 |
| `notes` | `notes` | `notes` | 笔记，正文目前主要为 HTML 字符串 |
| `exams` | `exams` | `exams` | 套卷及科目成绩 |
| `todos` | `todos` | `todos` | 首页待办 |
| `subjectReviews` | `subject_reviews` | `subject_reviews` | 科目复盘任务 |
| `words` | `words` | `words` | 词语、辨析和辨析组 |
| `stickies` | `stickies` | 当前未上云 | 全局/模块便签 |
| `keyvalue` | `keyvalue` | 独立 keyvalue API | 标签、设置和辅助数据 |

`stickies` 当前未包含在 Web 云同步 `COLLS/ALLOWED` 中，这是基线事实，不应在未设计冲突策略前擅自声称已云同步。

## 备份 JSON v1

顶层结构：

```json
{
  "version": 1,
  "app": "kaogong-review",
  "exportedAt": "ISO-8601",
  "errors": [],
  "notes": [],
  "exams": [],
  "todos": [],
  "subjectReviews": [],
  "keyvalue": [],
  "words": [],
  "stickies": [],
  "countdown": [],
  "noteTypes": null
}
```

兼容要求：

- `app` 在旧文件中可能缺失。
- `countdown` 在旧文件中可能缺失；缺失时导入不得清空现有倒数日。
- `keyvalue` 的本地备份形式是 `{key,value}` 数组；云端 `/api/export` 返回对象，原生导入器两种都要支持。
- `noteTypes` 是模块标签配置，必须原样保留。
- `auto_backup_*` key 不得再次嵌套进入新备份。
- 任一集合类型错误时拒绝整次导入，不执行部分覆盖。

## 已知记录字段

### errors

通用字段包括：`id`、`subject`、`module`、`knowledgePoint`、`knowledgePoints`、`errorCause`、`pitfall`、`images`、历史 `image`、`question`、`options`、`correctOption`、`userOption`、`accuracy`、`note`、`questionSource`、`status`、`sourceExamId`、`compareGroups`、`reviewCount`、`lastReviewDate`、`createdAt`、`updatedAt`、涂鸦/手写字段。

申论扩展包括：`isShenlun`、`score`、`totalScore`、`source`、`myFramework`、`stdFramework`、`paragraph`、`bias`、`wrongList`、`missedList`；不能因为普通错题模型不存在这些字段而丢弃。

### notes

`id`、`subject`、`module`、`knowledgePoint`、`type`、`title`、`content`、`linkedErrors`、`linkedReviews`、`updatedAt`、涂鸦字段。`content` 可能是 HTML、旧 Markdown 或旧 JSON 块数组。

### stickies

`id`、`content`、`tag`、`color`、`pinned`、`subject`、`module`、`createdAt`、`updatedAt`。排序以 `pinned` 优先，再按 `createdAt` 倒序；修改不改变创建时间。

### exams

`id`、套卷名称/来源、`examDate`、总分/得分、`totalAccuracy`、`totalTime`、`subjectScores`、`linkedErrorIds`、`updatedAt`。具体旧字段必须通过原始 JSON 保留。

### todos

`id`、`text`、`type`、`completed`、`status`、`createdAt`、`updatedAt`、`completedAt`。

### subject_reviews

`id`、`subject`、任务文本、`reviewNote`、`createdAt`、`updatedAt`。

### words

`id`、`category`、`subject`、`module`、`name`、`meaning`、`pinyin`、`groupId`、`sentiment`、辨析组词项、关联错题、`createdAt`、`updatedAt`。

## 云 API v1（保持现状）

基础地址：`https://kaogong-review.onrender.com/api`

| 方法 | 路径 | 认证 | 作用 |
|---|---|---|---|
| POST | `/auth/register` | 否 | 注册并返回 token/email |
| POST | `/auth/login` | 否 | 登录并返回 token/email |
| GET | `/health` | 否 | 健康检查 |
| GET | `/export` | Bearer | 导出所有允许集合和 keyvalue |
| POST | `/import` | Bearer | 事务性整库替换 |
| GET | `/keyvalue/:key` | Bearer | 读取键值 |
| PUT | `/keyvalue/:key` | Bearer | 写入键值 |
| GET | `/:coll` | Bearer | 获取集合全部记录 |
| POST | `/:coll` | Bearer | 新增/覆盖记录 |
| PUT | `/:coll/:id` | Bearer | 新增/覆盖指定记录 |
| DELETE | `/:coll/:id` | Bearer | 删除指定记录 |

云端允许集合固定为：`errors`、`notes`、`exams`、`todos`、`subject_reviews`、`words`。

认证头：`Authorization: Bearer <JWT>`。原生 token 必须存 Keychain，不能写进仓库或普通 UserDefaults。

## 同步语义

1. 本地写入成功后排队上传。
2. 用户手动“立即同步”时先上传本地，再拉取云端。
3. 拉取仅插入云端新增，或以 `updatedAt/createdAt` 较新者覆盖。
4. 云端没有的记录不能自动删除本地。
5. 服务不可达时保留 token 和本地数据，稍后重试。

