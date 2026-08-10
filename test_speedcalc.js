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
    assert(App.VERSION === '8.6.41', 'App.VERSION === 8.6.41（当前 ' + App.VERSION + '）');

    console.log('\n[2] 题型生成器（13 种 = 基础计算 10 + 资料分析 3；含 1 个 ▼ 占位）');
    const typeKeys = Object.keys(SC.TYPES);
    assert(typeKeys.length === 13, '13 种题型（' + typeKeys.length + '）');
    let noGen = typeKeys.filter(k => !SC.TYPES[k].gen);
    assert(noGen.length === 1 && noGen[0] === 'dataReal', '仅资料分析实战为 ▼ 占位（无生成器）');
    let noStd = typeKeys.filter(k => SC.TYPES[k].gen && (!SC.TYPES[k].s || !SC.TYPES[k].s.excellent));
    assert(noStd.length === 0, '全部可做题型带评级秒数 s:{excellent,good,pass}');
    let genOk = true;
    typeKeys.forEach(key => {
      if (!SC.TYPES[key].gen) return;
      for (let i = 0; i < 20; i++) {
        const q = SC.TYPES[key].gen();
        if (typeof q.answer !== 'number' || isNaN(q.answer)) { genOk = false; console.log('  bad gen ' + key + ': ' + JSON.stringify(q)); break; }
      }
    });
    assert(genOk, '12 种可做题型各生成 20 题答案均为数字');
    assert(SC.TYPES.addsub2.name === '两位数加减' && SC.TYPES.spDen.name === '特殊分母练习' && SC.TYPES.est05.name === '零五十估算练习' && SC.TYPES.base.name === '基期练习' && SC.TYPES.growth.name === '增量练习', '关键题型存在（两位数加减/特殊分母/零五十估算/基期/增量）');

    console.log('\n[3] 设置持久化（kg_speed_settings）');
    win.localStorage.removeItem(SC.SETTINGS_KEY);
    const d = SC.loadSettings();
    assert(d.confirmAuto === true && d.questionCount === 10 && d.mode === 'train', '默认设置：确定ON/10题/训练');
    // v8.6.36 言语理解模块调整为 7 个题型
    const yanyu36 = App.Constants.MODULES['言语理解'];
    assert(Array.isArray(yanyu36) && yanyu36.length === 7 && yanyu36[0] === '逻辑填空' && yanyu36[1] === '中心理解' && yanyu36[2] === '标题填入' && yanyu36[3] === '接语选择' && yanyu36[4] === '语句填入' && yanyu36[5] === '语句排序' && yanyu36[6] === '细节判断题', '言语理解 7 题型（逻辑填空/中心理解/标题填入/接语选择/语句填入/语句排序/细节判断题）');
    assert(Array.isArray(App.Constants.KNOWLEDGE_POINTS['中心理解']) && App.Constants.KNOWLEDGE_POINTS['中心理解'].length >= 3, '新题型中心理解带考点');
    assert(Array.isArray(App.Constants.KNOWLEDGE_POINTS['细节判断题']), '新题型细节判断题带考点');
    const built36 = fs.readFileSync('index.html', 'utf8');
    assert(!built36.includes('片段阅读') && !built36.includes('语句表达'), '旧模块名（片段阅读/语句表达）已移除');
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
    assert(home.querySelectorAll('.sc-module-card').length === 2, '2 个模块卡片（基础计算/资料分析）');
    assert(home.querySelectorAll('.sc-module-tag').length === 14, '标签云共 14 个（基础 10 + 自定义练习 + 资料 3）');
    assert(!!home.querySelector('.sc-module-icon') && home.querySelectorAll('.sc-module-count').length === 2, '模块头含图标方块与 N/N 可练习计数');
    const builtSc = fs.readFileSync('index.html', 'utf8');
    assert(builtSc.includes('.page-header') && builtSc.includes('padding-top: var(--top-buffer)'), 'v8.6.31 顶栏并入 page-header（安全区 padding-top 由 page-header 承担）');
    assert(home.querySelectorAll('.sc-opt-btn').length === 2, '题量/模式居中按钮（点击弹小窗）');
    assert(home.querySelector('.sc-opt-btn').textContent.includes('题量'), '题量按钮显示当前题量');
    // v8.6.32 最上行「是否需要确定」开关
    const confirmRow32 = home.querySelector('.sc-confirm-row');
    assert(!!confirmRow32 && confirmRow32.textContent.includes('是否需要确定'), '最上行「是否需要确定」开关存在');
    const csw = home.querySelector('.sc-confirm-row__switch');
    assert(csw.classList.contains('on'), '默认打开（=是）');
    csw.click();
    await wait(20);
    assert(!csw.classList.contains('on') && SC.loadSettings().confirmAuto === false, '点击关闭（=否）并持久化');
    csw.click();
    await wait(20);
    assert(SC.loadSettings().confirmAuto === true, '再点恢复开启');
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
    // v8.6.40 评级标准移到输入区下方（answer 之后；compareDocumentPosition FOLLOWING=4）
    const ansEl40 = home.querySelector('.sc-practice__answer');
    assert(!!std && !!ansEl40 && (ansEl40.compareDocumentPosition(std) & 4) !== 0, 'v8.6.40 评级标准显示在输入区下方');
    assert(!!home.querySelector('.sc-rating-line'), 'v8.6.40 评分行存在');
    assert(SC.TYPES.div3x1.s.pass === 38 && SC.TYPES.div3x1.s.good === 30 && SC.TYPES.div3x1.s.excellent === 24, 'v8.6.40 div3x1 评级标准（合格38/良好30/优秀24）');
    assert(!!home.querySelector('.sc-practice__expr'), '大题目展示');
    assert(home.querySelectorAll('.sc-numpad--v2 .sc-numpad__btn').length === 15, '屏幕键盘 15 键（3×4 数字 + C/⌫/✓）');
    // v8.6.38 键盘布局与动画
    assert(!!home.querySelector('.sc-numpad__kb') && !!home.querySelector('.sc-numpad__func'), 'v8.6.38 键盘分左右（数字网格 + 功能列）');
    assert(home.querySelectorAll('.sc-numpad__func .sc-numpad__btn').length === 3, '功能列 3 键（C/⌫/✓）');
    assert(!!home.querySelector('.sc-numpad__btn--confirm.tall'), '✓ 提交键双倍高（tall）');
    assert(home.querySelectorAll('.sc-numpad__grid .sc-numpad__btn').length === 12, '数字区 12 键（含 +/-）');
    assert(!!Array.from(home.querySelectorAll('.sc-numpad__grid .sc-numpad__btn')).find(b => b.textContent === '+/-'), '+/- 正负切换键存在');
    const built38 = fs.readFileSync('index.html', 'utf8');
    assert(built38.includes('#059669') && built38.includes('cubic-bezier(0.34, 1.56, 0.64, 1)'), 'v8.6.38 功能键深绿 + 按压弹簧回弹');
    assert(built38.includes('scFlashOk') && built38.includes('scAnsPop') && built38.includes('scNumPop') && built38.includes('scExprIn'), 'v8.6.38 动画（正确闪烁/输入弹入/统计跳动/题目淡入）');
    assert(built38.includes('_tapHaptic') && built38.includes('AudioContext') && built38.includes('navigator.vibrate'), 'v8.6.39 iOS 触觉（Web Audio 低频脉冲 + Android vibrate）');
    assert(built38.includes('translateY(1px)'), 'v8.6.39 按压增加位移（增强按下感）');
    assert(!home.querySelector('input[type=text], input[type=number]'), '无系统输入框（强制屏幕键盘）');
    // v8.6.32 键盘调节开关
    const adjBtn32 = home.querySelector('.sc-numpad__adjbtn');
    assert(!!adjBtn32 && adjBtn32.textContent === '调节', '键盘底部「调节」开关存在');
    assert(Array.from(home.querySelectorAll('.sc-numpad__adjbtn')).some(b => b.textContent === '重开'), 'v8.6.38 重开按钮移至键盘底部');
    adjBtn32.click();
    await wait(20);
    const adjPanel32 = home.querySelector('.sc-keyboard-adj');
    assert(!!adjPanel32 && adjPanel32.querySelectorAll('input[type=range]').length === 2, '调节面板含高度/宽度 2 个滑条');
    home.querySelector('.sc-keyboard-adj__close').click();
    await wait(20);
    assert(!home.querySelector('.sc-keyboard-adj'), '收起按钮关闭调节面板');
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
    await wait(80);
    // v8.6.23 提交后立即下一题（confirmAuto ON 位数匹配自动提交 → 立即进入下一题）
    assert(/^2\/10$/.test(home.querySelector('.sc-statusbar__pos').textContent), '输入答案位数匹配自动提交并立即进入下一题（2/10）');
    assert(!home.querySelector('.sc-fb'), '不显示正确答案/每题用时反馈（小对错 toast 提示）');
    // confirmAuto OFF：手动点确定 → 立即下一题
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { confirmAuto: false, questionCount: 3, mode: 'train', selectedType: SC.state.type })));
    SC.startPractice();
    await wait(50);
    const q1b = SC.state.questions[0];
    inputKey(String(q1b.answer));
    await wait(30);
    assert(home.querySelector('.sc-practice__answer').textContent === String(q1b.answer), 'confirmAuto OFF：输入后答案保留不自动提交');
    home.querySelector('.sc-numpad__btn--confirm').click();
    await wait(80);
    assert(/^2\/3$/.test(home.querySelector('.sc-statusbar__pos').textContent), 'confirmAuto OFF：点确定立即进入下一题（2/3）');

    console.log('\n[7] confirmAuto 自动提交（位数匹配）');
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { confirmAuto: true, questionCount: 2, mode: 'train', selectedType: SC.state.type })));
    SC.startPractice();
    await wait(50);
    const ans1 = String(SC.state.questions[0].answer);
    inputKey(ans1);
    await wait(80);
    assert(SC.state.questions[0].correct === true, 'confirmAuto ON：答案位数匹配自动提交（correct=true）');

    console.log('\n[8] 完成 → 结果页（v8.6.25 摘要/5列表格/三按钮）+ kg_speed_records');
    SC.state.idx = SC.state.questions.length - 1;
    SC.state.questions.forEach((qq, qi) => { qq.user = qq.answer; qq.correct = qi > 0; qq.timeUsed = 1.2; });  // 第 0 题留错
    SC.next();
    await wait(80);
    assert(SC.state.view === 'result', '全部完成后进入结果页');
    const summary = home.querySelector('.sc-result-summary');
    assert(!!summary && /本次练习用时:\d+:\d{2} 加油/.test(summary.textContent), '摘要区显示「本次练习用时:M:SS 加油」');
    const rtHead = home.querySelectorAll('.sc-result-table__head .sc-rt-col');
    assert(rtHead.length === 5, '结果表格 5 列表头（#/题目/正确答案/你的答案/用时）');
    const rtRows = home.querySelectorAll('.sc-result-table__row');
    assert(rtRows.length === 2 && rtRows[1].textContent.includes('✓') && rtRows[0].textContent.includes('✗'), '数据行渲染（正确 ✓ 蓝 / 错误 ✗ 红）');
    assert(rtRows[0].textContent.includes('= ' + SC.state.questions[0].answer), '正确答案格式「= 数字」');
    assert(rtRows[0].textContent.includes('1.2s'), '每题用时显示（1.2s）');
    const rfoot = home.querySelectorAll('.sc-result-footbtn');
    assert(rfoot.length === 3 && rfoot[0].textContent === '重来' && rfoot[1].textContent === '复练' && rfoot[2].textContent === '返回', '底部三按钮（重来/复练/返回）');
    // 复练：错题重新组卷进入做题页
    rfoot[1].click();
    await wait(80);
    assert(SC.state.view === 'practice' && SC.state.questions.length === 1, '复练：仅错题重新组卷（1 题）进做题页');
    const recs = JSON.parse(win.localStorage.getItem(SC.RECORDS_KEY)) || [];
    assert(recs.length >= 1 && recs[0].type && recs[0].count === 2 && typeof recs[0].totalTime === 'number' && Array.isArray(recs[0].details), '历史记录已存 kg_speed_records');

    console.log('\n[9] 历史页渲染');
    SC.state.view = 'history';
    await SC.render({});
    await wait(50);
    assert(home.querySelectorAll('.sc-hist-row').length >= 1, '历史页显示记录行');

    console.log('\n[10] v8.6.24 自定义练习（整合进基础模块，弹小窗选择）');
    // 回到题型选择页，点击基础模块的「自定义练习」标签 → 弹出小窗
    SC.state.view = 'home';
    SC.state.type = null;
    await SC.render({});
    await wait(50);
    const customTag = Array.from(home.querySelectorAll('.sc-module-tag')).find(t => t.textContent.includes('自定义练习'));
    assert(!!customTag, '基础模块内含「自定义练习」标签（带 ▼）');
    customTag.click();
    await wait(50);
    const pickGrid = doc.querySelector('.sc-custom-grid');
    assert(!!pickGrid && pickGrid.querySelectorAll('.sc-custom-cell').length === 11, '点击后弹出小窗（11 个自定义题型多选）');
    const builtV27 = fs.readFileSync('index.html', 'utf8');
    assert(builtV27.includes('max-height: 94vh') && builtV27.includes('min-height: 70vh'), 'v8.6.34 弹窗高度下限 70vh（内容少时不再过矮）');
    assert(builtV27.includes('#page-speed-calc') && builtV27.includes('max-width: 430px') && builtV27.includes('margin: 0 auto'), 'v8.6.35 速算页限宽 430px 居中（iPad 横屏不再全宽铺满）');
    assert(builtV27.includes('退出练习') && builtV27.includes("'继续'"), 'v8.6.27 做题页退出按钮两选项（退出/继续）');
    assert(builtV27.includes('.page-header__back') && !builtV27.includes('.sc-topbar__back {'), 'v8.6.31 速算顶栏并入 page-header 体系（返回键/位置/颜色/大小与错题本完全一致）');
    assert(builtV27.includes('pageHeader(title, rightText, onRightClick, opts)') && builtV27.includes('opts.rightHtml'), 'v8.6.31 pageHeader 支持 onBack/rightHtml 扩展');
    assert(!!doc.querySelector('.sc-picker-title') && doc.querySelector('.sc-picker-title').textContent.includes('自定义练习'), 'Sheet 标题「自定义练习·选择题型（可多选）」');
    assert(!!doc.querySelector('.sc-picker-feattitle') && !!doc.querySelector('.sc-custom-feat-types'), '弹窗含数据特征（固定首位/随机范围）');
    assert(!!doc.querySelector('.sc-picker-histtitle'), '弹窗含最近使用区域');
    assert(!!doc.querySelector('.sc-picker-foot') && doc.querySelectorAll('.sc-picker-foot .sc-custom-footbtn').length === 2, '底部固定栏（取消/确定）');
    // v8.6.33 第一项/第二项 双配置 tab
    const tabs33 = doc.querySelectorAll('.sc-picker-tab');
    assert(tabs33.length === 2 && tabs33[0].textContent.includes('第一项') && tabs33[1].textContent.includes('第二项'), '最上部「第一项/第二项」双配置 tab');
    assert(tabs33[0].classList.contains('selected'), '默认编辑第一项');
    // 第一项选 2 个题型 → 切到第二项（空）→ 选 1 个 → 切回第一项验证保存
    const pcells = pickGrid.querySelectorAll('.sc-custom-cell');
    pcells[0].click();
    pcells[1].click();
    await wait(20);
    assert(pickGrid.querySelectorAll('.sc-custom-cell.selected').length === 2, '小窗内可多选（2 个）');
    assert(doc.querySelectorAll('.sc-picker-selrow .sc-custom-selpill').length === 2, '已选标签行实时显示 2 个 pill');
    // 点 X 移除一个 → 联动
    doc.querySelector('.sc-picker-selrow .sc-custom-selx').click();
    await wait(20);
    assert(doc.querySelectorAll('.sc-picker-selrow .sc-custom-selpill').length === 1 && pickGrid.querySelectorAll('.sc-custom-cell.selected').length === 1, '点 X 移除 → 标签与网格联动');
    // 切到第二项
    tabs33[1].click();
    await wait(20);
    assert(doc.querySelector('.sc-picker-tab.selected').textContent.includes('第二项'), '切换到第二项');
    assert(doc.querySelectorAll('.sc-picker-selrow .sc-custom-selpill').length === 0, '第二项初始为空（无已选 pill）');
    doc.querySelectorAll('.sc-custom-cell')[2].click();
    await wait(20);
    assert(doc.querySelectorAll('.sc-picker-selrow .sc-custom-selpill').length === 1, '第二项选 1 个题型');
    // 切回第一项 → 保存恢复
    doc.querySelector('.sc-picker-tab').click();
    await wait(20);
    assert(doc.querySelectorAll('.sc-picker-selrow .sc-custom-selpill').length === 1 && SC.state.custom.items.item1.types.length === 1, '切回第一项配置保留（1 个题型）');
    doc.querySelector('.sc-picker-foot .sc-custom-footbtn--ok').click();
    await wait(50);
    assert(SC.state.type === 'custom', '确定后题型标记为 custom（不进入新页面）');
    assert(SC.state.custom.items.item1.types.length === 1 && SC.state.custom.items.item2.types.length === 1, '双项配置已保存（第一项 1 + 第二项 1）');
    assert(home.querySelectorAll('.sc-module-tag.selected').length === 1 && home.querySelector('.sc-module-tag.selected').textContent.includes('自定义练习'), '自定义练习标签高亮');
    // 开始练习 → 双项交替生成
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { questionCount: 5, mode: 'train', selectedType: '' })));
    home.querySelector('.sc-start-btn-v2').click();
    await wait(100);
    assert(SC.state.view === 'practice' && SC.state.questions.length === 5, '开始练习生成自定义题目（5 题）');
    const presets = JSON.parse(win.localStorage.getItem(SC.CUSTOM_KEY) || '{}');
    assert(!!presets.lastUsed && Array.isArray(presets.history) && presets.history.length >= 1, '配置与历史已保存 kg_speed_custom_presets');
    assert(Array.isArray(presets.lastUsed.item2Types) && presets.lastUsed.item2Types.length === 1, 'lastUsed 含第二项配置（item2Types）');
    assert(SC.state.type === 'custom', '自定义练习做题页 type=custom（标题/评级已适配）');
    // v8.6.32 固定首位 9：题目所有数字首位均 9（纯四则，跳过语义题型）
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { questionCount: 5, mode: 'train', selectedType: '' })));
    SC.state.custom.items.item1.types = ['addsub2c'];
    SC.state.custom.items.item1.featureType = 'fixedFirst';
    SC.state.custom.items.item1.fixedNum = 9;
    SC.state.custom.items.item2.types = [];
    SC.startPractice();
    await wait(80);
    const allFixed = SC.state.questions.every(q => {
      const nums = String(q.expr).match(/\d+/g) || [];
      return nums.length > 0 && nums.every(n => n.charAt(0) === '9');
    });
    assert(allFixed, '固定首位 9 应用到题目所有数字（v8.6.32 增强）');

    console.log('\n[11] v8.6.40 三位数除一位数评级（38/30/24 + 误差 ±3% + 每题评分）');
    const lastToastText = () => {
      const ts = doc.querySelectorAll('.toast');
      return ts.length ? (ts[ts.length - 1].textContent || '') : '';
    };
    SC.state.view = 'practice';
    SC.state.type = 'div3x1';
    SC.state.questions = [{ expr: '81 ÷ 3', answer: 27, user: '', correct: null, timeUsed: 0 }];
    SC.state.idx = 0;
    await SC.render({});
    await wait(60);
    const std40 = home.querySelector('.sc-standard');
    assert(!!std40 && std40.textContent.includes('误差 ±3%'), 'div3x1 评级行显示「误差 ±3%」');
    // 提交（模拟 20s 用时）→ 优秀（toast 反馈；render 后设输入与 qStart）
    SC.state.currentInput = '27';
    SC.state.qStart = Date.now() - 20000;
    home.querySelector('.sc-numpad__btn--confirm').click();
    await wait(80);
    assert(lastToastText().includes('优秀'), 'v8.6.40 每题评分（20s → 优秀）');
    // 35s → 合格
    SC.state.view = 'practice';
    SC.state.questions = [{ expr: '81 ÷ 3', answer: 27, user: '', correct: null, timeUsed: 0 }];
    SC.state.idx = 0;
    await SC.render({});
    await wait(60);
    SC.state.currentInput = '27';
    SC.state.qStart = Date.now() - 35000;
    home.querySelector('.sc-numpad__btn--confirm').click();
    await wait(80);
    assert(lastToastText().includes('合格'), 'v8.6.40 每题评分（35s → 合格）');
    // 50s → 加油
    SC.state.view = 'practice';
    SC.state.questions = [{ expr: '81 ÷ 3', answer: 27, user: '', correct: null, timeUsed: 0 }];
    SC.state.idx = 0;
    await SC.render({});
    await wait(60);
    SC.state.currentInput = '27';
    SC.state.qStart = Date.now() - 50000;
    home.querySelector('.sc-numpad__btn--confirm').click();
    await wait(80);
    assert(lastToastText().includes('加油'), 'v8.6.40 每题评分（50s → 加油）');

    console.log('\n[12] v8.6.41 涂鸦笔优化（柔和/调灰/大圆点修复）');
    const built41 = fs.readFileSync('index.html', 'utf8');
    assert(built41.includes('globalAlpha = 0.16') && built41.includes('SEG = 14'), 'v8.6.41 双描边柔和（半透明粗晕 + 细线，SEG 14）');
    assert(built41.includes("v:3.0}") && built41.includes("v:4.5}") && built41.includes("v:6.5}"), 'v8.6.41 笔档位拉开（细3/中4.5/粗6.5）');
    assert(built41.includes("v:'#4d4d4d'"), 'v8.6.41 默认笔色调灰（#4d4d4d）');
    assert(built41.includes('currentPenSize * 0.4') && built41.includes('dist > 4'), 'v8.6.41 收尾压细 + 短笔/tap 不画（大圆点修复）');

    console.log('\n===== 速算专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
