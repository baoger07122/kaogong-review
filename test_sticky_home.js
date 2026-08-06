/* v8.4.19 首页便签：横向滚动卡片 + 分页指示器 + 置顶排序 专项测试 */
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
    w.document.execCommand = () => true;
    if (!w.Element.prototype.closest) w.Element.prototype.closest = function (s) { return null; };
  }
});
setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  const wait = (ms) => new Promise(r => setTimeout(r, ms));

  // ===== 内存版 DB mock（便签 + 首页依赖的其他数据） =====
  const store = { notes: {}, errors: {}, todos: {}, stickies: {} };
  App.DB.get = async (t, id) => (store[t] && store[t][id]) ? store[t][id] : null;
  App.DB.updateNote = async (n) => { store.notes[n.id] = n; };
  App.DB.getNotes = async () => Object.values(store.notes);
  App.DB.getErrors = async () => Object.values(store.errors);
  App.DB.getStickies = async () => Object.values(store.stickies)
    .sort((a, b) => { if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1; return (b.createdAt || '').localeCompare(a.createdAt || ''); });
  App.DB.addSticky = async (s) => { if (!s.id) s.id = 's' + Math.random().toString(36).slice(2, 8); store.stickies[s.id] = s; return s.id; };
  App.DB.updateSticky = async (s) => { store.stickies[s.id] = s; };
  App.DB.removeSticky = async (id) => { delete store.stickies[id]; };
  // 待办相关（renderHome 可能用到）
  App.DB.getTodos = async () => Object.values(store.todos);
  App.DB.updateTodo = async (t) => { store.todos[t.id] = t; };
  App.DB.getStats = async () => ({ subjectStats: {}, totalErrors: 0, unmasteredErrors: 0 });
  App.DB.getReviewQueue = async () => [];
  App.Router.navigate = (r) => {};
  App.Router.back = () => {};

  const Home = App.Pages.Home;
  const container = doc.getElementById('page-home');
  doc.body.appendChild(container);

  try {
    console.log('[1] 版本号');
    assert(App.VERSION === '8.6.8', 'App.VERSION === 8.6.8（当前 ' + App.VERSION + '）');

    console.log('\n[2] 首页便签：横向滚动容器 + 卡片规格');
    // 5 条便签（1 置顶 + 4 普通）→ 超过一屏，应有分页指示器
    const base = new Date().toISOString();
    store.stickies = {};
    await App.DB.addSticky({ id: 's1', content: '记得复习资料分析比重问题', color: '#FFFBEB', pinned: true, createdAt: base });
    await App.DB.addSticky({ id: 's2', content: '增长率公式整理', color: '#EFF6FF', pinned: false, createdAt: base });
    await App.DB.addSticky({ id: 's3', content: '明天模考时间', color: '#ECFDF5', pinned: false, createdAt: base });
    await App.DB.addSticky({ id: 's4', content: '资料分析比重', color: '#FDF2F8', pinned: false, createdAt: base });
    await App.DB.addSticky({ id: 's5', content: '数量关系', color: '#F5F3FF', pinned: false, createdAt: base });

    await Home.render(container);
    await wait(10);
    const scrollWrap = container.querySelector('.sticky-scroll');
    assert(!!scrollWrap, '首页便签为横向滚动容器 .sticky-scroll');
    assert(win.getComputedStyle(scrollWrap).overflowX === 'auto', '容器 overflow-x: auto（可横滑）');
    const cards = container.querySelectorAll('.sticky-scroll .sticky-card');
    assert(cards.length === 5, '渲染 5 张便签卡片');
    assert(win.getComputedStyle(cards[0]).width === '150px', '卡片固定宽 150px（' + win.getComputedStyle(cards[0]).width + '）');
    assert(cards[0].classList.contains('is-pinned'), '置顶卡片在最前（第一张 is-pinned）');
    assert(cards[0].style.background === 'rgb(255, 251, 235)' || cards[0].style.background === '#FFFBEB', '默认暖白背景');
    const meta = cards[0].querySelector('.sticky-card__meta');
    assert(!!meta && win.getComputedStyle(meta).color === 'rgb(156, 163, 175)', '底部时间 11px 灰（#9CA3AF）');
    assert(!!cards[0].querySelector('.sticky-card__content'), '卡片内容区存在（圆角16px/字号14px由 CSS 变量保证，jsdom 不解析 var() 故不断言值）');

    console.log('\n[3] 分页指示器');
    const dots = container.querySelector('.sticky-dots');
    assert(!!dots, '便签数 > 3 时显示分页指示器');
    assert(dots.children.length === 3, '5 条 → 3 个圆点（每屏约 2 张）');
    assert(dots.children[0].classList.contains('is-active'), '首点默认高亮');

    console.log('\n[4] 空态');
    store.stickies = {};
    await Home.render(container);
    await wait(10);
    const empty = container.querySelector('.sticky-empty');
    assert(!!empty && empty.textContent.indexOf('暂无便签') >= 0, '无便签显示空态占位');
    assert(!container.querySelector('.sticky-dots'), '空态不显示分页指示器');

    console.log('\n[5] 少卡片不显示指示器');
    await App.DB.addSticky({ id: 's6', content: '只有一张', color: '#FFFBEB', pinned: false, createdAt: base });
    await Home.render(container);
    await wait(10);
    assert(!container.querySelector('.sticky-dots'), '卡片 ≤3 张时不显示分页指示器');

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
