/*
 * 考公复盘系统前端入口
 *
 * 运行时仍由 build.js 拼接为一个 index.html，模块按依赖顺序加载。
 * 需要保留未改写的功能：
 *   - src/modules/30-components-preserved.js 中的涂鸦实现
 *   - src/modules/150-speed-preserved.js 中的速算练习实现
 *
 * 基础层位于 src/core/，页面和受保护功能位于 src/modules/；
 * 请按 build.js 中的顺序修改对应模块。
 */
window.App = window.App || {};
