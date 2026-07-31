/**
 * 考公笔试复盘系统 - 前端打包脚本（零依赖，仅用 Node 内置模块）
 * 从 src/ 源码生成 index.html：
 *   src/index.template.html  —— 页面骨架（含 <!--BUILD_CSS--> / <!--BUILD_JS--> 占位符）
 *   src/styles.css            —— 全部 CSS（唯一真源）
 *   src/app.js               —— 全部 JS（唯一真源）
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
const js = fs.readFileSync(path.join(root, 'src', 'app.js'), 'utf8');
const template = fs.readFileSync(path.join(root, 'src', 'index.template.html'), 'utf8');

const out = template
  .replace('<!--BUILD_CSS-->', '<style>' + css + '</style>')
  .replace('<!--BUILD_JS-->', '<script>' + js + '</script>');

fs.writeFileSync(path.join(root, 'index.html'), out);
console.log('✓ 已生成 index.html (' + (out.length / 1024).toFixed(0) + ' KB)');
