# 11.20.1 编译修正规格：按科目返回考点目录键

## 涉及入口与现状

题库「标签管理 → 考点」读取和保存各行测科目的考点目录时，会调用 `VerbalReasoningKnowledgePointRepository.recordID(for:)`。现有 `switch` 的「言语理解」分支计算了目录键，但没有把它作为函数结果返回；真机归档因此在该文件编译失败。

## 目标行为与实现落点

为所有科目返回目录键：言语理解沿用 `verbal_reasoning_knowledge_points_by_type`，资料分析、判断推理、常识判断沿用各自既有键，其他科目继续返回编码后的隔离键。给四个明确科目分支补齐显式返回，保留所有键值和分支行为；不改 UI、记录格式或迁移数据。修改位置：`native-ios/Sources/Features/Home/VerbalReasoningKnowledgePointRepository.swift` 的 `recordID(for:)`。

## 边界与验收步骤

1. 对照源码确认五类分支都返回非空字符串，言语理解仍为原有键，其余键与本轮提交前一致。
2. 检查补丁只增加缺失的返回语句及本规格文件，不改其他科目的目录键或历史数据。
3. 推送修正后跟踪新 GitHub Actions：领域行为检查通过、模拟器测试按工作流范围判定，真机目标归档成功，IPA 打包并出现在 `native-v11.20.1` Release 且可下载。
