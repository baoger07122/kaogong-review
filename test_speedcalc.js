/* v8.6.20 速算 v2 专项测试：25 题型(19+6)+评级 / 模块卡片标签云 / pill / 禁用态 / 做题页评级 / 记录 */
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
  const wait = (ms) => new Promise(r => setTimeout(r, ms));

  try {
    console.log('[1] 版本号');
    assert(App.VERSION === '8.6.22', 'App.VERSION === 8.6.22（当前 ' + App.VERSION + '）');

    console.log('\n[2] 题型生成器（25 种 = 基础计算 19 + 资料分析 6，全部可练习 + 评级）');
    const typeKeys = Object.keys(SC.TYPES);
    assert(typeKeys.length === 25, '25 种题型（' + typeKeys.length + '）');
    let noGen = typeKeys.filter(k => !SC.TYPES[k].gen);
    assert(noGen.length === 0, '全部题型有生成器（无占位）');
    let noStd = typeKeys.filter(k => !SC.TYPES[k].s || !SC.TYPES[k].s.excellent);
    assert(noStd.length === 0, '全部题型带评级秒数 s:{excellent,good,pass}');
    const checkQ = (expr) => {
      const e = String(expr).replace(/[×÷≈\s=，。、（）%]/g, (m) => ({ '×': '*', '÷': '/', '≈': '', '=': '', ' ': '', '，': '', '。': '', '、': '', '（': '', '）': '', '%': '' }[m]));
      if (!e || !/^[0-9+\-*/.]+$/.test(e)) return null;
      try { return Function('"use strict"; return (' + e + ');')(); } catch (err) { return null; }
    };
    let genOk = true;
    Object.keys(SC.TYPES).forEach(key => {
      for (let i = 0; i < 20; i++) {
        const q = SC.TYPES[key].gen();
        if (typeof q.answer !== 'number' || isNaN(q.answer)) { genOk = false; console.log('  bad gen ' + key + ': ' + JSON.stringify(q)); break; }
      }
    });
    assert(genOk, '25 种题型各生成 20 题答案均为数字');
    assert(SC.TYPES.addsub2.name === '两位数加减' && SC.TYPES.estBase.name === '估算前期量' && SC.TYPES.pctFrac.name === '百化分计算', '关键题型存在（两位数加减/估算前期量/百化分）');

    console.log('\n[3] 设置持久化（kg_speed_settings）');
    win.localStorage.removeItem(SC.SETTINGS_KEY);
    const d = SC.loadSettings();
    assert(d.confirmAuto === true && d.questionCount === 10 && d.mode === 'train', '默认设置：确定ON/10题/训练');
    d.questionCount = 15;
    SC.saveSettings(d);
    assert(SC.loadSettings().questionCount === 15, '修改设置后持久化生效');

    console.log('\n[4] 首页渲染（模块卡片/标签云/pill/禁用态）');
    const home = doc.getElementById('page-speed-calc');
    SC.state.view = 'home';
    SC.state.type = null;
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { selectedType: '' })));
    await SC.render({});
    await wait(50);
    assert(home.querySelectorAll('.sc-module-card:not(.sc-custom-entry)').length === 2, '2 个模块卡片（基础计算/资料分析-增长相关）');
    assert(!!home.querySelector('.sc-custom-entry'), 'v8.6.22 自定义练习入口卡片存在');
    assert(home.querySelectorAll('.sc-module-tag').length === 25, '标签云共 25 个标签');
    assert(!!home.querySelector('.sc-module-icon') && home.querySelectorAll('.sc-module-card:not(.sc-custom-entry) .sc-module-count').length === 2, '模块头含图标方块与 N/N 可练习计数');
    const builtSc = fs.readFileSync('index.html', 'utf8');
    assert(builtSc.includes('padding: var(--top-buffer) 16px 12px'), 'v8.6.21 顶栏补安全区（返回按钮不被状态栏/分屏遮挡）');
    assert(home.querySelectorAll('.sc-pill').length >= 7, '题量 pill(5) + 模式 pill(2)');
    const startBtn = home.querySelector('.sc-start-btn-v2');
    assert(!!startBtn && startBtn.classList.contains('disabled'), '未选题型时开始按钮为禁用态（disabled）');
    // 点击标签 → 单选高亮 + 开始按钮启用
    const tag0 = home.querySelector('.sc-module-tag');
    tag0.click();
    await wait(20);
    assert(home.querySelectorAll('.sc-module-tag.selected').length === 1, '标签全局单选（仅 1 个选中）');
    assert(!startBtn.classList.contains('disabled') && startBtn.textContent === '开始练习', '选题后开始按钮启用');
    assert(SC.state.type !== null, '选中题型已记录');

    console.log('\n[5] 做题页（状态栏/题型评级/强制键盘）');
    SC.startPractice();
    await wait(50);
    const pos = home.querySelector('.sc-statusbar__pos');
    assert(!!pos && /1\/10/.test(pos.textContent), '状态栏显示 1/10');
    assert(!!home.querySelector('.sc-statusbar__pen') && !!home.querySelector('#sc-timer'), '状态栏有笔图标与计时器');
    const std = home.querySelector('.sc-standard');
    const selS = SC.TYPES[SC.state.type].s;
    assert(!!std && std.textContent.includes('合格: ' + selS.pass + 's'), '评级按题型显示（合格: ' + selS.pass + 's）');
    assert(!!home.querySelector('.sc-practice__expr'), '大题目展示');
    assert(home.querySelectorAll('.sc-numpad--v2 .sc-numpad__btn').length === 15, '屏幕键盘 15 键');
    assert(!home.querySelector('input[type=text], input[type=number]'), '无系统输入框（强制屏幕键盘）');
    // 计时格式 M:SS:d
    const t0 = home.querySelector('#sc-timer');
    assert(/^\d+:\d{2}\.\d$/.test(t0.textContent), '计时格式 M:SS:d（' + t0.textContent + '）');

    console.log('\n[6] 键盘输入 + 训练模式反馈 + 1.2s 自动下一题');
    const inputKey = (digits) => {
      Array.from(String(digits)).forEach(ch => {
        const b = Array.from(home.querySelectorAll('.sc-numpad__btn')).find(x => x.textContent === ch);
        if (b) b.click();
      });
    };
    const q0 = SC.state.questions[0];
    const ansStr = String(q0.answer);
    inputKey(ansStr);
    await wait(30);
    assert(home.querySelector('.sc-practice__answer').textContent === ansStr, '点击数字键拼接答案显示');
    home.querySelector('.sc-numpad__btn--confirm').click();
    await wait(60);
    assert(!!home.querySelector('.sc-fb'), '训练模式提交后显示反馈 ✓/✗');
    await wait(1500);
    assert(/^2\/10$/.test(home.querySelector('.sc-statusbar__pos').textContent), '1.2s 后自动进入下一题（2/10）');

    console.log('\n[7] confirmAuto 自动提交（位数匹配）');
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { confirmAuto: true, questionCount: 2, mode: 'train', selectedType: SC.state.type })));
    SC.startPractice();
    await wait(50);
    const ans1 = String(SC.state.questions[0].answer);
    inputKey(ans1);
    await wait(80);
    assert(SC.state.questions[0].correct === true, 'confirmAuto ON：答案位数匹配自动提交（correct=true）');

    console.log('\n[8] 完成 → 结果页 + kg_speed_records');
    SC.state.idx = SC.state.questions.length - 1;
    SC.state.questions.forEach(qq => { qq.user = qq.answer; qq.correct = true; });
    SC.next();
    await wait(80);
    assert(SC.state.view === 'result', '全部完成后进入结果页');
    const recs = JSON.parse(win.localStorage.getItem(SC.RECORDS_KEY)) || [];
    assert(recs.length >= 1 && recs[0].type && recs[0].count === 2 && typeof recs[0].totalTime === 'number' && Array.isArray(recs[0].details), '历史记录已存 kg_speed_records');

    console.log('\n[9] 历史页渲染');
    SC.state.view = 'history';
    await SC.render({});
    await wait(50);
    assert(home.querySelectorAll('.sc-hist-row').length >= 1, '历史页显示记录行');

    console.log('\n[10] v8.6.22 自定义练习配置页');
    // 进入自定义页
    SC.state.view = 'custom';
    SC.resetCustomState();
    await SC.render({});
    await wait(50);
    assert(home.querySelectorAll('.sc-custom-swcell').length === 6, '顶部 6 个设置开关（确定/键盘/顺序/夜间/否/速记）');
    assert(home.querySelectorAll('.sc-custom-cell').length === 11, '11 个自定义题型（3 列网格）');
    assert(home.querySelector('.sc-custom-selhint') && home.querySelector('.sc-custom-selhint').textContent.includes('请下方选择题型'), '空状态提示「请下方选择题型」');
    assert(!!home.querySelector('.sc-custom-feat-type'), '数据特征（固定首位/随机范围）');
    assert(home.querySelectorAll('.sc-custom-num').length === 9, '固定首位 1-9 数字网格');
    assert(!!home.querySelector('.sc-custom-footbtn--ok') && home.querySelector('.sc-custom-footbtn--ok').classList.contains('disabled'), '未选题型时确定按钮禁用');
    // 选 2 个题型 → 已选标签联动 + 确定启用
    const cells = home.querySelectorAll('.sc-custom-cell');
    cells[0].click();
    cells[1].click();
    await wait(20);
    assert(home.querySelectorAll('.sc-custom-selpill').length === 2, '选中 2 个题型 → 已选标签行 2 个 pill');
    assert(!home.querySelector('.sc-custom-footbtn--ok').classList.contains('disabled'), '已选题型确定按钮启用');
    // 移除一个（点 X）→ 联动取消
    home.querySelector('.sc-custom-selx').click();
    await wait(20);
    assert(home.querySelectorAll('.sc-custom-selpill').length === 1 && home.querySelectorAll('.sc-custom-cell.selected').length === 1, '点 X 移除题型 → 已选 pill 与网格联动');
    // 固定首位数字单选
    const nums = home.querySelectorAll('.sc-custom-num');
    nums[8].click();
    await wait(20);
    assert(home.querySelectorAll('.sc-custom-num.selected').length === 1 && SC.state.custom.fixedNum === 9, '固定首位数字单选（9）');
    // 确定 → 生成题目进做题页 + 保存 kg_speed_custom_presets
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { questionCount: 5, mode: 'train' })));
    SC.state.custom.types = ['addsub2c'];
    home.querySelector('.sc-custom-footbtn--ok').click();
    await wait(100);
    assert(SC.state.view === 'practice' && SC.state.questions.length === 5, '点确定生成题目进入做题页（5 题）');
    const presets = JSON.parse(win.localStorage.getItem(SC.CUSTOM_KEY) || '{}');
    assert(!!presets.lastUsed && Array.isArray(presets.history) && presets.history.length >= 1, '配置与历史已保存 kg_speed_custom_presets');
    assert(presets.history[0].number === 9 && presets.history[0].featureType === 'fixedFirst', '历史含固定首位 9 与特征类型');
    // 固定首位应用：题目主数字以 9 开头
    const qFirst = SC.state.questions[0];
    assert(/^9\d*/.test(qFirst.expr), '固定首位 9 已应用到题目（' + qFirst.expr + '）');

    console.log('\n===== 速算专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
