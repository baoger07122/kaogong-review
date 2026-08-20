/*
 * 考公复盘系统前端入口
 *
 * 运行时仍由 build.js 拼接为一个 index.html，模块按依赖顺序加载。
 * 需要保留未改写的功能：
 *   - src/components/01-sketch-preserved.js 中的涂鸦实现
 *   - src/modules/150-speed-preserved.js 中的速算练习实现
 *
 * 基础层位于 src/core/，组件位于 src/components/，页面位于 src/pages/，启动入口位于 src/bootstrap/；
 * 样式按级联顺序位于 src/styles/，src/styles.css 仅保留清单说明；
 * 受保护的速算功能仍位于 src/modules/；
 * 请按 build.js 中的顺序修改对应模块。
 */
window.App = window.App || {};
