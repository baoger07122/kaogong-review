# 11.12.3 实现交付记录

## 版本和基线

- 基线：11.12.2 / build 141，代码提交 `cd4e93aa97dd222b9f2126495fe5c03cc30fcb07`。
- 开工时远端发布分支：`codex/ios-native-rewrite`，清单头 `d2603d7aa246ca20b49d6546f3c292633d7c1ab1`；工作区干净。
- 本轮目标版本：11.12.3 / build 142。

## 实现范围

1. 详情和编辑页的关联词语摘要统一由词语正文安全转换，支持附件占位、空正文、空白合并和 120 个 Swift 字符截断。
2. 言语理解错误类型模块目录直接链接到模块管理目的地，移除静默退出的回调／手动路由链。

## 检查和发布

- 代码提交：`158d808ff14d11aebd0aba24d1b1da97dca513fb`。
- GitHub Actions：run `43172992443`，结果成功；原生领域检查、真机目标归档、IPA 打包和上传均通过。
- 模拟器步骤跳过。模块目录点击和关联词语全文显示尚未进行 iPad 实机验收。
- Release：[`native-v11.12.3`](https://github.com/baoger07122/kaogong-review/releases/tag/native-v11.12.3)。IPA 资产已上传；下载地址返回 HTTP 200，资产大小 5,027,292 字节。
- `downloads/native/latest.json` 已指向 11.12.3 / build 142。
