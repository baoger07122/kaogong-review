/**
 * 块手柄状态机专项验证（浏览→编辑→选择→菜单 四状态）
 * 运行：node test_handle_state.js
 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  url: 'https://localhost/',
  beforeParse(w) {
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0, removeAllRanges() {}, addRange() {}, getRangeAt() { return { toString: () => '' }; }, isCollapsed: true });
    Object.defineProperty(w, 'innerWidth', { value: 390, writable: true, configurable: true });
    Object.defineProperty(w, 'ontouchstart', { value: null, writable: true, configurable: true });
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
    const ed = App.Components.initEditor(doc.createElement('div'), {
      initialData: [
        { id: 's1', type: 'text', content: '第一块', indent: 0, props: {} },
        { id: 's2', type: 'text', content: '第二块', indent: 0, props: {} },
      ],
      dataMode: 'json',
      onChange: () => {},
    });
    const wrap = doc.createElement('div');
    doc.body.appendChild(wrap);
    wrap.appendChild(ed.element);

    const b0 = wrap.querySelector('.notion-block[data-index="0"]');
    const b1 = wrap.querySelector('.notion-block[data-index="1"]');
    const h0 = b0.querySelector('.notion-block__handle');
    const ed0 = b0.querySelector('.notion-editable');

    // 状态 1：浏览（初始）手柄隐藏
    console.log('\n[1] 状态1 浏览');
    assert(!b0.classList.contains('is-selected'), '初始无选中');
    const csHandle = win.getComputedStyle(h0);
    assert(csHandle.opacity === '0', '手柄默认隐藏 (opacity:0)');

    // 状态 2：聚焦编辑，取消选中、手柄仍隐藏
    console.log('\n[2] 状态2 编辑');
    b0.classList.add('is-selected');   // 先模拟选中
    ed0.focus();
    ed0.dispatchEvent(new win.FocusEvent('focus', { bubbles: true }));
    assert(!b0.classList.contains('is-selected'), '进入编辑取消选中');
    assert(b0.classList.contains('is-editing'), '进入编辑状态类');

    // 状态 3：点击非编辑态的块 → 选中（显示手柄 + 视觉指示）；ESC 退编辑后也能选中
    console.log('\n[3] 状态3 选择（点击非编辑态块 / ESC 后）');
    // 先退出编辑态（模拟光标不闪动）
    ed0.dispatchEvent(new win.FocusEvent('blur', { bubbles: true }));
    b0.classList.remove('is-editing');
    // 方式 A：点击非编辑态的块（块左侧空白区域，非 contenteditable）
    const b0Blank = doc.createElement('div');
    b0.appendChild(b0Blank);
    b0Blank.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    assert(b0.classList.contains('is-selected'), '点击非编辑态块 → 选中');
    const csSel = win.getComputedStyle(b0);
    assert(csSel.backgroundColor === 'rgba(46, 170, 220, 0.05)', '选中时有视觉指示背景 (' + csSel.backgroundColor + ')');
    const selHandle = win.getComputedStyle(h0);
    assert(selHandle.opacity === '1', '选中时手柄显示 (opacity:1)');
    assert(selHandle.pointerEvents === 'auto', '选中时手柄可点击');
    // 方式 B：点击文字区 → 进入编辑态 → 手柄隐藏（光标闪动时隐藏）
    ed0.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    ed0.dispatchEvent(new win.FocusEvent('focus', { bubbles: true }));
    assert(!b0.classList.contains('is-selected'), '点击文字进入编辑 → 取消选中');
    assert(b0.classList.contains('is-editing'), '进入编辑状态类');
    // 退出编辑（blur）后点击块空白 → 再次选中
    ed0.dispatchEvent(new win.FocusEvent('blur', { bubbles: true }));
    b0Blank.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    assert(b0.classList.contains('is-selected'), '退出编辑后点击 → 再次选中');
    b0.classList.remove('is-selected');

    // 状态 4：点击手柄 → 打开菜单
    console.log('\n[4] 状态4 菜单');
    h0.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const menu = doc.querySelector('.notion-handle-menu');
    assert(!!menu, '点击手柄弹出菜单');
    assert(b0.classList.contains('is-selected'), '菜单打开时块保持选中');
    // 再点手柄 → 关闭菜单，回到状态 3
    h0.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(!doc.querySelector('.notion-handle-menu'), '再点手柄关闭菜单');
    assert(b0.classList.contains('is-selected'), '关闭菜单后仍选中（状态3）');

    // ESC 三级：菜单→选中→取消（jsdom activeElement 限制，选中态 ESC 用 document 级监听验证）
    console.log('\n[5] ESC 三级流转');
    // 打开菜单
    h0.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(!!doc.querySelector('.notion-handle-menu'), '菜单重新打开');
    // ESC 1：关菜单
    ed0.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    assert(!doc.querySelector('.notion-handle-menu'), 'ESC 关闭菜单');
    assert(b0.classList.contains('is-selected'), 'ESC 后保持选中');
    // ESC 2：选中态按 ESC → 取消选中（document 级监听，dispatch 到 document）
    doc.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true }));
    assert(!b0.classList.contains('is-selected'), '再次 ESC 取消选中（状态1）');

    // 点击空白处取消选中（空白占位 append 到编辑器 wrapper 内，mousedown 冒泡触发 clearSelected）
    console.log('\n[6] 点击空白/外部');
    b0.classList.add('is-selected');
    assert(b0.classList.contains('is-selected'), '选中状态就绪');
    const blankEl = doc.createElement('div');   // 空白占位（非块内）
    ed.element.appendChild(blankEl);
    blankEl.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    assert(!b0.classList.contains('is-selected'), '点击空白取消选中');

    console.log('\n===== 手柄状态机: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e);
    process.exit(1);
  }
}, 900);
