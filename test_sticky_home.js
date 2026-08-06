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
    assert(App.VERSION === '8.6.12', 'App.VERSION === 8.6.12（当前 ' + App.VERSION + '）');

    console.log('\n[2] 首页便签：纵向瀑布流 + 卡片规格（v8.6.10 替代横向滚动）');
    // 5 条便签（1 置顶 + 4 普通）
    const base = new Date().toISOString();
    store.stickies = {};
    await App.DB.addSticky({ id: 's1', content: '记得复习资料分析比重问题', color: '#FFFBEB', pinned: true, createdAt: base });
    await App.DB.addSticky({ id: 's2', content: '增长率公式整理', color: '#EFF6FF', pinned: false, createdAt: base });
    await App.DB.addSticky({ id: 's3', content: '明天模考时间', color: '#ECFDF5', pinned: false, createdAt: base });
    await App.DB.addSticky({ id: 's4', content: '资料分析比重', color: '#FDF2F8', pinned: false, createdAt: base });
    await App.DB.addSticky({ id: 's5', content: '数量关系', color: '#F5F3FF', pinned: false, createdAt: base });

    await Home.render(container);
    await wait(10);
    const masonry = container.querySelector('.sticky-masonry--home');
    assert(!!masonry, '首页便签为纵向瀑布流容器 .sticky-masonry--home');
    assert(!container.querySelector('.sticky-scroll'), '无横向滚动容器（已改纵向瀑布流）');
    assert(!container.querySelector('.sticky-dots'), '无分页指示器（横向滚动已移除）');
    const cards = container.querySelectorAll('.sticky-masonry--home .sticky-card');
    assert(cards.length === 5, '渲染 5 张便签卡片');
    assert(cards[0].classList.contains('is-pinned'), '置顶卡片在最前（第一张 is-pinned）');
    assert(cards[0].style.background === 'rgb(255, 251, 235)' || cards[0].style.background === '#FFFBEB', '默认暖白背景');
    const meta = cards[0].querySelector('.sticky-card__meta');
    assert(!!meta && win.getComputedStyle(meta).color === 'rgb(156, 163, 175)', '底部时间 11px 灰（#9CA3AF）');
    assert(!!cards[0].querySelector('.sticky-card__content'), '卡片内容区存在（字号 14px = --font-md 与全局一致，jsdom 不解析 var() 故不断言值）');

    console.log('\n[3] 空态');
    store.stickies = {};
    await Home.render(container);
    await wait(10);
    const empty = container.querySelector('.sticky-empty');
    assert(!!empty && empty.textContent.indexOf('暂无便签') >= 0, '无便签显示空态占位');
    assert(!container.querySelector('.sticky-dots'), '空态无分页指示器');

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
