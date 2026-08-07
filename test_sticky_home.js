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
    assert(App.VERSION === '8.6.32', 'App.VERSION === 8.6.32（当前 ' + App.VERSION + '）');

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

    console.log('\n[4] v8.6.17 便签待办：方框勾选/划线/完成后后移');
    // 直接渲染 stickyCard：1 未完成 + 1 普通行 + 1 已完成
    const sc4 = App.Components.stickyCard({ id: 't1', content: '[ ] 未完成事项\n普通文本行\n[x] 已完成事项', color: '#FFFBEB', pinned: false }, { onRefresh: () => {} });
    const cbs4 = sc4.querySelectorAll('input[type=checkbox][data-raw]');
    assert(cbs4.length === 2, '待办行渲染为 2 个 checkbox');
    assert(cbs4[0].checked === false && cbs4[1].checked === true, '未完成/已完成勾选状态正确');
    const labels4 = sc4.querySelectorAll('.sticky-task');
    assert(labels4[0].textContent.includes('未完成事项') && labels4[1].textContent.includes('已完成事项'), '已完成待办显示在末尾（后移）');
    assert(labels4[1].classList.contains('sticky-task--done'), '已完成项划线样式（sticky-task--done）');
    assert(sc4.textContent.includes('普通文本行'), '普通文本行正常显示');
    // 勾选交互：勾选 → content 变 [x] + 更新 DB（jsdom 用显式 change 事件模拟，真机 click 自动触发）
    cbs4[0].checked = true;
    cbs4[0].dispatchEvent(new win.Event('change', { bubbles: true }));
    await wait(20);
    assert(store.stickies.t1 && store.stickies.t1.content.includes('[x] 未完成事项'), '勾选后存储更新为 [x]（划线+后移触发 onRefresh 重渲染）');
    // 编辑弹层有待办按钮
    App.Components.stickySheet({ title: '新增便签', onSave: async () => {} });
    await wait(30);
    const modal4 = doc.getElementById('modal-container');
    const taskBtn4 = modal4.querySelector('.sticky-sheet__taskbtn');
    assert(!!taskBtn4 && taskBtn4.textContent === '▢', '便签编辑弹层有「▢ 待办」按钮');

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
