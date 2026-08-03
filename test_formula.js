/* Markdown 公式渲染专项测试：renderLatex / 编辑器 / 预览 / 导出还原 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.log('  ✗ ' + msg); }
}

const dom = new JSDOM(html, {
  runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://localhost/',
  beforeParse(w) {
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0, removeAllRanges() {}, addRange() {}, getRangeAt() { return { toString: () => '' }; }, isCollapsed: true });
    w.scrollTo = () => {};
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;

  try {
    // ===== [1] renderLatex 基础语法 =====
    console.log('\n[1] renderLatex 基础');
    const R = (s) => App.Utils.renderLatex(s);
    assert(R('E=mc^2').indexOf('<sup>2</sup>') >= 0, '上标 ^2 渲染 (E=mc^2)');
    assert(R('x_i').indexOf('<sub>i</sub>') >= 0, '下标 _i 渲染');
    assert(R('a^{12}').indexOf('<sup>12</sup>') >= 0, '花括号上标 ^{12}');
    const frac = R('\\frac{1}{2}');
    assert(frac.indexOf('mf-frac') >= 0 && frac.indexOf('mf-num') >= 0 && frac.indexOf('mf-den') >= 0, '分数 \\frac{1}{2} 渲染');
    assert(frac.indexOf('1</span>') >= 0 && frac.indexOf('2</span>') >= 0, '分数分子分母内容');
    assert(R('\\alpha \\beta \\pi').indexOf('α') >= 0 && R('\\alpha \\beta \\pi').indexOf('β') >= 0 && R('\\alpha \\beta \\pi').indexOf('π') >= 0, '希腊字母 \\alpha \\beta \\pi');
    assert(R('a \\times b \\div c').indexOf('×') >= 0 && R('a \\times b \\div c').indexOf('÷') >= 0, '运算符 \\times \\div');
    assert(R('x \\leq y \\geq z \\approx w').indexOf('≤') >= 0 && R('x \\leq y \\geq z \\approx w').indexOf('≥') >= 0 && R('x \\leq y \\geq z \\approx w').indexOf('≈') >= 0, '不等式 \\leq \\geq \\approx');
    assert(R('\\sqrt{x}').indexOf('mf-sqrt') >= 0 && R('\\sqrt{x}').indexOf('x') >= 0, '根号 \\sqrt{x}');
    assert(R('\\sqrt[3]{8}').indexOf('mf-sqrt__root') >= 0, 'n 次根号 \\sqrt[3]{8}');
    assert(R('\\text{增长率} = 5\\%').indexOf('增长率') >= 0, '文本 \\text{}');
    assert(R('\\sum_{i=1}^{n} x_i').indexOf('∑') >= 0 && R('\\sum_{i=1}^{n} x_i').indexOf('<sub>i=1</sub>') >= 0, '求和 \\sum 带上下标');
    assert(R('\\int_{0}^{1} f(x) dx').indexOf('∫') >= 0, '积分 \\int');
    // HTML 转义安全
    assert(R('a < b').indexOf('&lt;') >= 0, '公式内 < 转义安全');

    // ===== [2] 编辑器：公式渲染 =====
    console.log('\n[2] 编辑器公式渲染');
    const ed = App.Components.initEditor(doc.createElement('div'), {
      initialData: '增长量 = 现期量 - 基期量，公式 $x = \\frac{a}{b}$ 与 $$y^2 = c$$',
      onChange: () => {},
    });
    const wrap = doc.createElement('div');
    doc.body.appendChild(wrap);
    wrap.appendChild(ed.element);
    const mformulas = wrap.querySelectorAll('.mformula');
    assert(mformulas.length === 2, '编辑器渲染 2 个公式（1 行内 + 1 块级）');
    const inlineF = wrap.querySelector('.mformula:not(.mformula--block)');
    assert(!!inlineF && inlineF.querySelector('.mf-frac'), '行内公式含分数结构');
    const blockF = wrap.querySelector('.mformula--block');
    assert(!!blockF && blockF.textContent.includes('y') && blockF.textContent.includes('c'), '块级公式渲染');
    assert(blockF.getAttribute('data-latex'), '块级公式保留 data-latex 源码');
    assert(inlineF.getAttribute('contenteditable') === 'false', '编辑器内公式只读 contenteditable=false');

    // ===== [3] 导出还原：Markdown 往返 =====
    console.log('\n[3] Markdown 往返');
    const md = ed.getContent();
    assert(md.includes('$x = \\frac{a}{b}$'), '导出还原行内公式 $x = \\frac{a}{b}$');
    assert(md.includes('$$y^2 = c$$'), '导出还原块级公式 $$y^2 = c$$');
    // 再解析一次（往返不丢）
    const ed2 = App.Components.initEditor(doc.createElement('div'), {
      initialData: md, onChange: () => {},
    });
    const wrap2 = doc.createElement('div');
    doc.body.appendChild(wrap2);
    wrap2.appendChild(ed2.element);
    assert(wrap2.querySelectorAll('.mformula').length === 2, '导出→再解析公式不丢（2 个）');
    const md2 = ed2.getContent();
    assert(md2.includes('$x = \\frac{a}{b}$') && md2.includes('$$y^2 = c$$'), '二次往返仍还原公式');
    // 普通文本不受影响
    assert(md2.includes('增长量 = 现期量 - 基期量'), '普通文本往返完整');

    // ===== [4] 详情页预览（md-preview） =====
    console.log('\n[4] 详情页预览公式');
    const preview = App.Utils._renderMarkdown ? App.Utils._renderMarkdown('速度 $v = \\frac{s}{t}$ 公里/小时') : null;
    if (preview) {
      assert(preview.indexOf('mformula') >= 0, '预览行内公式渲染');
      assert(preview.indexOf('mf-frac') >= 0, '预览公式含分数');
    } else {
      console.log('  - _renderMarkdown 不在 App.Utils（跳过预览断言，静态检查）');
      const src = fs.readFileSync('index.html', 'utf8');
      assert(src.indexOf('_renderMarkdown') >= 0 && src.indexOf('mformula--block') >= 0, '预览含块级公式逻辑');
    }
    // 块级公式预览（静态验证构建产物含 $$ 块级处理）
    const built = fs.readFileSync('index.html', 'utf8');
    assert(built.indexOf('blockFormula') >= 0 || built.indexOf('mformula--block') >= 0, '构建产物含块级公式处理');
    // 行内公式最少 2 字符规则（避免误伤货币）
    const ed3 = App.Components.initEditor(doc.createElement('div'), {
      initialData: '价格 $5 与 $ab$ 对比', onChange: () => {},
    });
    const wrap3 = doc.createElement('div');
    doc.body.appendChild(wrap3);
    wrap3.appendChild(ed3.element);
    assert(wrap3.querySelectorAll('.mformula').length === 1, '货币 $5 不误伤（仅 $ab$ 渲染）');

    console.log('\n===== 公式渲染: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
