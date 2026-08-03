/* 速算练习专项测试：题型生成器 / 首页 / 练习 / 结果 / 历史 */
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
    w.confirm = () => true;
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  const SC = App.Pages.SpeedCalc;
  if (!SC) { console.error('SpeedCalc 未定义'); process.exit(1); }

  try {
    // ===== [1] 题型生成器：12 种题型答案正确性 =====
    console.log('\n[1] 题型生成器');
    const typeKeys = Object.keys(SC.TYPES);
    assert(typeKeys.length === 12, '12 种题型 (' + typeKeys.length + ')');
    // 每种生成 30 题并校验（用 eval 校验普通四则；特殊题型单独校验）
    const evalSafe = (expr) => {
      // 提取数字和运算符（题型表达式可控，仅四则）
      return Function('"use strict"; return (' + expr.replace(/[×÷≈]/g, (m) => ({ '×': '*', '÷': '/', '≈': '' }[m])) + ');')();
    };
    let allOk = true;
    typeKeys.forEach(key => {
      for (let i = 0; i < 30; i++) {
        const q = SC.TYPES[key].gen();
        if (typeof q.answer !== 'number' || !isFinite(q.answer)) { allOk = false; console.log('    ✗ ' + key + ' 答案非数字: ' + q.expr); break; }
        if (key === 'base') { if (q.answer <= 0) { allOk = false; console.log('    ✗ base 答案 <=0'); } }
        else if (key === 'growth') { if (q.answer <= 0) { allOk = false; console.log('    ✗ growth 答案 <=0'); } }
        else if (key === 'mulEst') {
          const m = q.expr.match(/(\d+)\s*[×]\s*(\d+)/);
          const ans = Math.round(parseInt(m[1]) / 10) * 10 * (Math.round(parseInt(m[2]) / 10) * 10);
          if (q.answer !== ans) { allOk = false; console.log('    ✗ mulEst: ' + q.expr + ' 期望 ' + ans + ' 实际 ' + q.answer); break; }
        }
        else {
          const got = Math.round(evalSafe(q.expr));
          if (got !== q.answer) { allOk = false; console.log('    ✗ ' + key + ': ' + q.expr + ' 期望 ' + got + ' 实际 ' + q.answer); break; }
        }
      }
    });
    assert(allOk, '12 种题型 × 30 题答案全部正确');

    // ===== [2] 首页渲染：题型网格 / 模式 / 按钮 =====
    console.log('\n[2] 速算练习首页');
    const page = doc.getElementById('page-speed-calc');
    SC.state.view = 'home'; SC.state.type = null; SC.state.mode = 'train';
    await SC.render({});
    const typeItems = page.querySelectorAll('.sc-type-item');
    assert(typeItems.length === 12, '题型网格 12 项 (' + typeItems.length + ')');
    const names = Array.from(typeItems).map(x => x.textContent);
    assert(names.includes('三位数加法') && names.includes('求增长量') && names.includes('两位数乘两位数'), '题型包含关键项');
    // 2 列网格
    const gridStyle = win.getComputedStyle(page.querySelector('.sc-type-grid')).gridTemplateColumns;
    assert(gridStyle.split(' ').length >= 2, '2 列网格布局 (' + gridStyle + ')');
    assert(page.querySelectorAll('.sc-mode-opt').length === 2, '模式选项 2 个');
    assert(!!page.querySelector('.sc-btn--primary') && page.querySelector('.sc-btn--primary').textContent === '开始练习', '「开始练习」主按钮');
    assert(!!page.querySelector('.sc-btn--outline') && page.querySelector('.sc-btn--outline').textContent === '历史记录', '「历史记录」次按钮');
    // 选中交互
    typeItems[0].dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(typeItems[0].classList.contains('selected'), '题型点击后选中');
    assert(SC.state.type === typeKeys[0], 'state.type 更新');
    page.querySelector('.sc-mode-opt[data-mode="race"]').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(SC.state.mode === 'race', '模式切换为竞速');
    assert(page.querySelector('.sc-mode-opt[data-mode="race"]').classList.contains('selected'), '竞速选项高亮');

    // ===== [3] 开始练习：竞速模式 =====
    console.log('\n[3] 竞速模式练习');
    page.querySelector('.sc-btn--primary').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(SC.state.view === 'practice', '进入练习视图');
    assert(SC.state.questions.length === 10, '生成 10 题');
    assert(page.querySelector('.sc-progress').textContent.includes('第 1/10 题'), '进度显示「第 1/10 题」');
    assert(!!page.querySelector('.sc-timer'), '计时器存在');
    assert(page.querySelector('.sc-practice__expr').textContent.trim() !== '', '题目展示');
    // 竞速：输入答案提交 → 直接下一题（无反馈）
    const input = page.querySelector('.sc-practice__input');
    input.value = String(SC.state.questions[0].answer + 1);   // 故意答错
    page.querySelector('.sc-submit-btn').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(SC.state.idx === 1, '竞速提交后直接下一题 (idx=1)');
    assert(SC.state.questions[0].correct === false, '第 1 题记录为错误');
    // 第 2 题答对（注意 render 重建后需重新获取 input）
    const inputRace2 = page.querySelector('.sc-practice__input');
    inputRace2.value = String(SC.state.questions[1].answer);
    page.querySelector('.sc-submit-btn').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(SC.state.questions[1].correct === true, '第 2 题记录为正确');

    // ===== [4] 训练模式：逐题反馈 =====
    console.log('\n[4] 训练模式反馈');
    SC.state.mode = 'train';
    SC.state.view = 'practice';
    SC.state.idx = 0;
    SC.state.questions = [SC.TYPES.add3.gen()];
    await SC.render({});
    const input2 = page.querySelector('.sc-practice__input');
    input2.value = String(SC.state.questions[0].answer + 5);   // 答错
    page.querySelector('.sc-submit-btn').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const fb = page.querySelector('.sc-fb--no');
    assert(!!fb && fb.textContent.includes(String(SC.state.questions[0].answer)), '训练模式显示正确答案 (✗ 正确答案：X)');
    assert(input2.disabled === true, '提交后输入框禁用');
    assert(!!page.querySelector('.sc-next-btn'), '「下一题」按钮出现');

    // ===== [5] 完成练习：结果页 + 历史存储 =====
    console.log('\n[5] 结果页与历史存储');
    // 构造一组完成数据直接走 finish
    SC.state.view = 'practice';
    SC.state.type = 'add3';
    SC.state.mode = 'race';
    SC.state.questions = [];
    for (let i = 0; i < 10; i++) { const q = SC.TYPES.add3.gen(); q.user = q.answer; q.correct = true; SC.state.questions.push(q); }
    SC.state.questions[0].user = SC.state.questions[0].answer + 1; SC.state.questions[0].correct = false;
    SC.finish();
    assert(SC.state.view === 'result', '完成后进入结果页');
    assert(page.querySelector('.sc-result-score').textContent.includes('90'), '正确率 90%');
    assert(page.querySelectorAll('.sc-result-row').length === 10, '结果页 10 行明细');
    assert(page.querySelector('.sc-result-row__mark.ok') && page.querySelector('.sc-result-row__mark.no'), '对错标记 ✓/✗');
    const hist = SC.loadHistory();
    assert(hist.length === 1 && hist[0].type === '三位数加法' && hist[0].correctCount === 9, '历史已存储（1 条，9/10）');
    assert(!!hist[0].id && typeof hist[0].duration === 'number', '记录含 id/时长');
    // 再练一次
    page.querySelector('.sc-btn--primary').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(SC.state.view === 'practice', '「再练一次」重新开始');
    SC.show('home');

    // ===== [6] 历史记录页：展示 + 删除 =====
    console.log('\n[6] 历史记录');
    // 加第二条（不同题型）
    const list2 = SC.loadHistory();
    list2.unshift({ id: 'x2', type: '两位数乘两位数', mode: '训练模式', date: new Date().toISOString(), correctCount: 5, totalCount: 10, duration: 30 });
    SC.saveHistory(list2);
    SC.show('history');
    const rows = page.querySelectorAll('.sc-hist-row');
    assert(rows.length === 2, '历史列表 2 条');
    assert(rows[0].textContent.includes('两位数乘两位数') && rows[0].textContent.includes('训练模式'), '最新记录在前（倒序）');
    assert(rows[0].textContent.includes('5/10'), '记录显示正确率 5/10');
    assert(!!page.querySelector('.sc-hist-del'), '每条记录带删除按钮');
    // 删除
    rows[0].querySelector('.sc-hist-del').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const afterDel = SC.loadHistory();
    assert(afterDel.length === 1 && afterDel[0].type === '三位数加法', '删除后剩 1 条');
    assert(page.querySelectorAll('.sc-hist-row').length === 1, '删除后列表刷新为 1 行');

    // ===== [7] 首页五个入口 =====
    console.log('\n[7] 首页入口');
    const home = doc.getElementById('page-home');
    // 直接静态断言构建产物（jsdom 无 IndexedDB 无法渲染 Home）
    assert(html.includes("label: '速算练习'"), '入口含「速算练习」');
    assert(!html.includes("label: '错题收藏'"), '入口不含「错题收藏」');

    console.log('\n===== 速算练习: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
