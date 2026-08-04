/* 底部导航固定 + 待办排版修复 专项验证 */
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
    w.innerWidth = 390;
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;

  try {
    console.log('[1] 底部导航栏固定（问题1）');
    const css = Array.from(doc.styleSheets[0].cssRules || []).map(r => r.cssText).join('\n');
    // #bottom-nav 规则
    const navRule = css.split('\n').find(l => l.startsWith('#bottom-nav')) || '';
    const navBlock = css.match(/#bottom-nav \{[\s\S]*?\}/);
    assert(!!navBlock, '存在 #bottom-nav 规则');
    if (navBlock) {
      const b = navBlock[0];
      assert(b.includes('position: fixed') || b.includes('position:fixed'), 'position: fixed');
      assert(b.includes('bottom: 0'), 'bottom: 0');
      assert(b.includes('z-index: 9999'), 'z-index 高（9999）');
      assert(b.includes('translateZ(0)'), 'translateZ(0) 防 iOS 橡皮筋顶起');
      assert(b.includes('safe-bottom') || b.includes('safe-area-inset'), '底部安全区适配');
    }
    // 页面底部留白（防内容被遮挡）
    const pageRule = css.match(/\.page \{[\s\S]*?\}/);
    assert(!!pageRule && pageRule[0].includes('padding-bottom'), '.page 底部留白（防导航遮挡）');

    console.log('\n[2] 待办文字竖排防御（问题2）');
    const todoContent = css.match(/\.todo-content \{[\s\S]*?\}/);
    assert(!!todoContent, '.todo-content 规则存在');
    if (todoContent) {
      const t = todoContent[0];
      assert(t.includes('flex: 1'), 'flex: 1 占满剩余空间');
      assert(t.includes('min-width: 0'), 'min-width: 0 关键防压缩');
      assert(t.includes('overflow: hidden'), 'overflow: hidden 防溢出');
    }
    const todoTitle = css.match(/\.todo-title \{[\s\S]*?\}/);
    assert(!!todoTitle, '.todo-title 规则存在');
    if (todoTitle) {
      const t = todoTitle[0];
      assert(t.includes('word-break: break-word'), 'word-break: break-word 长词换行');
      assert(t.includes('white-space: normal'), 'white-space: normal 不强制不换行');
      assert(t.includes('writing-mode: horizontal-tb'), 'writing-mode: horizontal-tb 禁止竖排');
    }
    const todoNote = css.match(/\.todo-note \{[\s\S]*?\}/);
    assert(!!todoNote && todoNote[0].includes('writing-mode: horizontal-tb'), '.todo-note 也防竖排');
    const todoCheckbox = css.match(/\.todo-checkbox \{[\s\S]*?\}/);
    assert(!!todoCheckbox && todoCheckbox[0].includes('flex-shrink: 0'), '复选框禁压缩');

    console.log('\n[3] 待办标题含换行时渲染为多行（不竖排）');
    // 渲染一个含 \n 的待办，验证 title 使用 textContent（换行符按 white-space 处理）
    const holder = doc.createElement('div');
    doc.body.appendChild(holder);
    // 直接验证 CSS 计算值：white-space normal 时 \n 不强制换行、非竖排
    const probe = doc.createElement('div');
    probe.className = 'todo-title';
    probe.textContent = '速算\n1. 三位数÷一位数\n2. 五位数÷三位数';
    doc.body.appendChild(probe);
    const cs = win.getComputedStyle(probe);
    assert(cs.whiteSpace === 'normal', '标题 white-space: normal');
    assert(cs.writingMode === 'horizontal-tb', '标题 writing-mode: horizontal-tb');

    console.log('\n[4] viewport 含 viewport-fit=cover');
    const vp = doc.querySelector('meta[name="viewport"]');
    assert(!!vp && (vp.content || '').includes('viewport-fit=cover'), 'viewport-fit=cover 已设置');

    console.log('\n===== 导航固定+待办排版专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
