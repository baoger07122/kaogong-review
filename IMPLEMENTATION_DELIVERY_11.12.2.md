# 11.12.2 实现交付记录

## 版本和基线

- 基线分支头：`cdcdfdd226874739fef92cdccb6ee57acee585b3`（远端 `codex/ios-native-rewrite`）。
- 应用版本：11.12.2；构建号：141。
- 旧的 11.11.3 模块错误类型补丁已由基线包含，本轮没有重复套用或回退到旧版本。

## 本轮实现范围

1. 实体键盘在文本输入边界切换相邻字段，并保留输入法、选区和字段内方向键行为。
2. 学习库和详情页的看题／刷题按钮调整为规定的单字圆形控件。
3. 错因编辑区按实际文本高度增长，并保留换行条目。
4. 考点标签逐项纵向排列；长标签在单个标签框内折行，瀑布流估高按实际前缀宽度测量。
5. 涂鸦画布几何回报绑定题目、宿主、打开序号、加载版本和分栏状态，过期回报不放行触摸。
6. 四类词语记录统一为富文本正文；旧辨析字段投影后只在显式保存时写入新正文键，隐藏字段继续保留。
7. 言语理解错误类型目录用整行按钮进入同一设置导航栈中的模块管理页。

## 检查与待验证项

- `git diff --check`：通过；有 CRLF 转换提示，无空白错误。
- 本机没有 Xcode、`xcodebuild` 或 `swiftc`，本地未编译 iOS 目标。
- 首次工作流 `43152930376` 在归档编译处失败：`NativeRichTextEditor.swift` 调用参数顺序错误。已在 `cd4e93aa97dd222b9f2126495fe5c03cc30fcb07` 修正并重建；未重跑失败提交。
- 成功工作流：[43153826644](https://github.com/baoger07122/kaogong-review/actions/runs/43153826644)，提交 `cd4e93aa97dd222b9f2126495fe5c03cc30fcb07`。版本校验、原生领域检查、应用编译、真机目标归档、IPA 打包与上传均通过。
- 模拟器步骤按推送工作流配置跳过；没有完成真机交互验收，因此键盘、涂鸦、详情导航及排版行为仍待设备逐项确认。

## 发布资产

- Release：[`native-v11.12.2`](https://github.com/baoger07122/kaogong-review/releases/tag/native-v11.12.2)，发布标签指向代码提交 `cd4e93aa97dd222b9f2126495fe5c03cc30fcb07`。
- IPA：`kaogong-review-native-11.12.2-unsigned.ipa`，GitHub 资产状态 `uploaded`，大小 5,027,857 字节。
- `downloads/native/latest.json` 已更新为 11.12.2 / build 141；工作流随后产生仅更新清单的提交 `a04d5cdbf50a8bd3daafd7c49ccf27c1f4712762`。
- 固定下载入口：[GitHub Releases](https://github.com/baoger07122/kaogong-review/releases)。
