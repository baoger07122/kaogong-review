/**
 * iPad 横屏居中对齐 + 分屏自适应专项验证
 * 验证：
 *  1. 工具栏 left:50% + translateX(-50%) 居中定位 + width: min(680px, calc(100%-32px))
 *  2. page-header 有 inner 容器（内容限宽居中）
 *  3. iPad 分屏检测（width < 1024 → body.ipad-split）
 * 运行：node test_ipad_layout.js
 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
let _vvHeight = 1024, _vvListeners = {};
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  url: 'https://localhost/',
  beforeParse(w) {
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0, removeAllRanges() {}, addRange() {}, getRangeAt() { return { toString: () => '' }; }, isCollapsed: true });
    Object.defineProperty(w, 'innerWidth', { value: 1366, writable: true, configurable: true });
    Object.defineProperty(w, 'innerHeight', { value: 1024, writable: true, configurable: true });
    Object.defineProperty(w, 'ontouchstart', { value: null, writable: true, configurable: true });
    // jsdom 的 screen 为只读 0，检测代码有兜底（w<1024），无需 mock
    Object.defineProperty(w, 'navigator', { value: { userAgent: 'Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15', platform: 'MacIntel', maxTouchPoints: 5 }, configurable: true });
    const vv = {
      get height() { return _vvHeight; },
      get offsetTop() { return 0; },
      addEventListener(type, cb) { (_vvListeners[type] = _vvListeners[type] || []).push(cb); },
      removeEventListener() {},
    };
    Object.defineProperty(w, 'visualViewport', { value: vv, configurable: true });
  },
});

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.error('  ✗ ' + msg); }
}

setTimeout(() => {
  const win = dom.window, doc = win.document;
  const App = win.App;
  try {
    // 1. 工具栏居中定位
    console.log('\n[1] 工具栏居中（iPad 横屏 1024px）');
    const ed = App.Components.initEditor(doc.createElement('div'), { initialData: '# 标题', onChange: () => {} });
    const wrap = doc.createElement('div');
    doc.body.appendChild(wrap);
    wrap.appendChild(ed.element);
    const tb = doc.querySelector('.notion-mobile-toolbar');
    assert(!!tb, '工具栏挂载');
    const cs = win.getComputedStyle(tb);
    assert(cs.left === '50%', 'left: 50% (' + cs.left + ')');
    assert(cs.transform.indexOf('translateX(-50%)') >= 0 || cs.transform.indexOf('matrix') >= 0, 'transform 含居中 (' + cs.transform + ')');
    assert(cs.width.indexOf('min(680px') >= 0 || cs.width === '680px', 'width: min(680px, calc(100%-32px)) (' + cs.width + ')');
    assert(cs.bottom === '66px', 'bottom 悬浮导航上方 66px (' + cs.bottom + ')');

    // 2. page-header inner 容器
    console.log('\n[2] 页头内容限宽居中');
    const header = App.Components.pageHeader('测试标题');
    doc.body.appendChild(header);
    const inner = header.querySelector('.page-header__inner');
    assert(!!inner, 'pageHeader 生成 inner 容器');
    if (inner) {
      assert(inner.querySelector('.page-header__back'), '返回按钮在 inner 内');
      assert(inner.querySelector('.page-header__title'), '标题在 inner 内');
      const innerCs = win.getComputedStyle(inner);
      assert(innerCs.maxWidth.indexOf('720px') >= 0 || innerCs.maxWidth.indexOf('var(--content-max-width') >= 0, 'inner 限宽 720px (' + innerCs.maxWidth + ')');
    }

    // 3. iPad 分屏检测（screen 固定 1366×1024，innerWidth 变化模拟分屏）
    console.log('\n[3] iPad 分屏检测');
    assert(doc.body.classList.contains('ipad-split') === false, 'iPad 全屏 1366px 不加 ipad-split');
    // 模拟 50/50 分屏：宽度变 678
    Object.defineProperty(win, 'innerWidth', { value: 678, writable: true, configurable: true });
    win.dispatchEvent(new win.Event('resize'));
    setTimeout(() => {
      assert(doc.body.classList.contains('ipad-split'), '分屏 678px 加 ipad-split 类');
      // Slide Over：变 400
      Object.defineProperty(win, 'innerWidth', { value: 400, writable: true, configurable: true });
      win.dispatchEvent(new win.Event('resize'));
      setTimeout(() => {
        assert(doc.body.classList.contains('ipad-split'), 'Slide Over 400px 加 ipad-split 类');
        // 返回按钮分屏时 margin-left 生效（通过 CSS 类，内联无——静态断言类存在即可，样式由 CSS 控制）
        // 还原全屏
        Object.defineProperty(win, 'innerWidth', { value: 1366, writable: true, configurable: true });
        win.dispatchEvent(new win.Event('resize'));
        setTimeout(() => {
          assert(!doc.body.classList.contains('ipad-split'), '恢复 1366px 移除 ipad-split');
          console.log('\n===== iPad 布局: ' + pass + ' 通过, ' + fail + ' 失败 =====');
          process.exit(fail > 0 ? 1 : 0);
        }, 160);   // 等防抖 100ms + 余量
      }, 160);
    }, 160);
  } catch (e) {
    console.error('测试异常:', e);
    process.exit(1);
  }
}, 900);
