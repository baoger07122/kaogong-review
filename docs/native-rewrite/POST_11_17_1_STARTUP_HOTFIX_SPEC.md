# 11.17.1 启动闪退热修规格

- 基准为 11.17.1（150），发布源码 `62dfbd724275a6627b9ebcae231ee69d8d8d6a53`。用户反馈安装新版后点击图标即闪退。2026-11-17 09:51:27 的同版 `.ips` 显示从进程启动到中止约 0.54 秒，主线程 `EXC_CRASH / SIGABRT`。栈从 SwiftUI 的 `PlatformViewRepresentableAdaptor.sizeThatFits` 经应用二进制偏移 `801560` 和 `804380`、UIKit 的 `layoutBelowIfNeeded` 再进入 SwiftUI 的 `UIHostingContentView.layoutSubviews`，最后在 `AttributeGraph` 中因图更新前置条件失败而中止。设备日志未含这两个应用帧的符号名。
- 对比 11.14.3，数据库模型、应用入口、根导航和归档工作流没有变更。首页「今日待办」的 `HomeTodoCollection` 与崩溃栈的调用形态相符。11.17.1 在 SwiftUI 请求尺寸时改写 UIKit 集合的 bounds、手动调用 compositional layout 的 `prepare()` 并同步调用 `layoutIfNeeded()`，可能重入内部 SwiftUI 列表项的布局。更新数据时也会同步强制布局，且新高度在布局回调内同步失效。首页在有待办时立即挂载此集合。Apple 定义由集合视图在正常布局周期调用准备方法。
- 尺寸查询只读按可用宽度缓存的正高度，首次布局或数据换代时按原每行 52 pt 的预留高度返回。由集合视图自己的布局周期测量，在完成后合并并异步通知外层重新取尺寸。刷新待办时使旧测量失效并请求正常布局。处理首次宽度未知、无事项、窄窗口切换和名单内容变化。无需迁移本地数据或调整签名、应用 ID、列表颜色、字号、滚动及手势。
- 验收为同一版本先做 iOS 真机目标编译归档和 IPA 下载验证，然后在 iPad 上分别用空库、已有普通待办、循环待办的本地库冷启动至首页。再次打开、修改带备注的事项、旋转或分屏后待办应可见，左滑操作可用。手势和冷启动仍待实机。若无待办也闪退，优先用同一版本的 `.ips` 区分签名、启动数据库及其他崩溃路径。

## 交付记录

- 热修执行中。构建运行 ID、IPA 下载核验和 iPad 待测事项在发布确认后补记。

[Apple UICollectionViewLayout.prepare()](https://developer.apple.com/documentation/uikit/uicollectionviewlayout/prepare())
