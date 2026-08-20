/**
 * 考公笔试复盘系统 - 前端打包脚本（零依赖，仅用 Node 内置模块）
 * 从 src/ 源码生成 index.html：
 *   src/index.template.html  —— 页面骨架（含 <!--BUILD_CSS--> / <!--BUILD_JS--> 占位符）
 *   src/styles.css            —— 全部 CSS（唯一真源）
 *   src/app.js + src/core/ + src/components/ + src/pages/ + src/bootstrap/ + src/modules/
 *   —— 按依赖顺序组织的 JS 源码
 * 用法：node build.js   （生成与当前功能完全一致的 index.html）
 *
 * 重要说明：本项目用 window.App 在全局挂载方法，供页面按钮调用。
 * 代码压缩工具（terser 等）会把这些“看似没被读取”的全局方法误判为死代码、
 * 整段删除，导致应用跑不起来。因此本脚本只做“源码 → 单文件”的忠实拼接，
 * 不做任何会改变代码语义的压缩/改名。
 */
const fs = require('fs');
const path = require('path');
const root = process.cwd();

const css = fs.readFileSync(path.join(root, 'src', 'styles.css'), 'utf8');
// 显式声明依赖顺序，避免文件名排序或新增模块导致初始化顺序变化。
// src/core/ 是基础层；src/components/ 是 UI 组件层；src/pages/ 是页面层；
// src/bootstrap/ 是全局启动入口。
// 01-sketch-preserved 与 150-speed-preserved 是受保护模块：
// 涂鸦和速算逻辑保持原样，只参与拼接，不在本次重构中改写。
const JS_MODULES = [
  'src/app.js',
  'src/core/00-constants.js',
  'src/core/01-utils.js',
  'src/core/10-database.js',
  'src/core/20-tags.js',
  'src/components/00-shell.js',
  'src/components/01-sketch-preserved.js',
  'src/components/10-feedback-tags.js',
  'src/components/20-editors.js',
  'src/components/30-sheets-cards.js',
  'src/components/40-picker-modal.js',
  'src/core/30-cloud.js',
  'src/core/40-draft.js',
  'src/core/50-router.js',
  'src/core/60-note-types.js',
  'src/pages/00-home.js',
  'src/pages/10-errors.js',
  'src/pages/20-notes.js',
  'src/pages/30-stickies.js',
  'src/pages/31-study-stats.js',
  'src/pages/40-exams.js',
  'src/pages/50-workspace.js',
  'src/pages/60-settings.js',
  'src/pages/61-kp-manage.js',
  'src/pages/62-worddb.js',
  'src/bootstrap/00-editor-entry.js',
  'src/modules/150-speed-preserved.js'
];
const js = JS_MODULES
  .map(file => fs.readFileSync(path.join(root, file), 'utf8'))
  .join('\n\n');
const template = fs.readFileSync(path.join(root, 'src', 'index.template.html'), 'utf8');

// 注意：必须用「函数替换」而非字符串替换——JS/CSS 源码里的 '$'（如公式渲染的 '$...$'）
// 若作为字符串 replace 的替换串，会触发 $' / $& / $` 等特殊模式，把内容替换成 </body></html> 等，
// 导致产物语法错误。函数 replacer 不做任何 $ 处理，原样拼接。
const out = template
  .replace('<!--BUILD_CSS-->', () => '<style>' + css + '</style>')
  .replace('<!--BUILD_JS-->', () => '<script>' + js + '</script>');

fs.writeFileSync(path.join(root, 'index.html'), out);
console.log('✓ 已生成 index.html (' + (out.length / 1024).toFixed(0) + ' KB)');
