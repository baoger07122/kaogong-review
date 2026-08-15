const puppeteer = require('C:/Users/bao/.workbuddy/binaries/node/workspace/node_modules/puppeteer-core');

(async () => {
  const browser = await puppeteer.launch({
    executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe',
    headless: 'new',
    args: ['--no-sandbox', '--disable-setuid-sandbox', '--window-size=1180,820'],
    defaultViewport: { width: 1180, height: 820 }
  });
  const page = await browser.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()); });

  try {
    await page.goto('http://localhost:4173/', { waitUntil: 'networkidle2', timeout: 30000 });
    console.log('加载完成，标题:', await page.title());

    // 导航到添加错题路由（直接通过 URL hash 或调用 App.Router）
    await page.evaluate(() => { App.Router.navigate('error-form'); });
    await new Promise(r => setTimeout(r, 1200));
    console.log('--- 进入添加错题表单 ---');
    const formTxt = await page.evaluate(() => {
      const c = document.getElementById('page-error-form');
      return c ? c.textContent.slice(0, 200) : '容器不存在';
    });
    console.log('表单文本:', formTxt.slice(0, 150));
    console.log('出现申论表单?', formTxt.includes('题目信息'));

    // 点击「科目」选择条，打开弹窗
    const subjectBarClicked = await page.evaluate(() => {
      const bars = Array.from(document.querySelectorAll('.ef-selectbar'));
      const sb = bars.find(b => b.textContent.includes('科目'));
      if (!sb) return '未找到科目条';
      sb.click();
      return '已点击科目条';
    });
    console.log(subjectBarClicked);
    await new Promise(r => setTimeout(r, 600));

    // 弹窗里点「申论」
    const picked = await page.evaluate(() => {
      const items = Array.from(document.querySelectorAll('.picker-modal__item'));
      const sl = items.find(i => i.textContent.trim() === '申论');
      if (!sl) return '弹窗里没有申论项 items=' + items.map(i=>i.textContent.trim()).join(',');
      sl.click();
      return '已点申论';
    });
    console.log(picked);
    await new Promise(r => setTimeout(r, 600));

    // 点「确定」
    const okClicked = await page.evaluate(() => {
      const ok = document.querySelector('.picker-modal__ok');
      if (!ok) return '无确定按钮';
      ok.click();
      return '已点确定';
    });
    console.log(okClicked);
    await new Promise(r => setTimeout(r, 1000));

    // 检查是否进入申论表单
    const after = await page.evaluate(() => {
      const c = document.getElementById('page-error-form');
      const body = c ? c.innerText : '';
      return {
        hasShenlunTitle: body.includes('添加申论错题'),
        hasModule1: body.includes('题目信息'),
        hasFramework: body.includes('框架对比'),
        hasBias: body.includes('核心思维偏差'),
        hasSaveBtn: body.includes('保存申论错题'),
        snippet: body.replace(/\n/g, ' ').slice(0, 120)
      };
    });
    console.log('--- 跳转结果 ---', JSON.stringify(after, null, 2));
  } catch (e) {
    console.log('测试异常:', e.message);
  }

  console.log('--- 收集到的错误 ---');
  (errors.length ? errors : ['无错误']).forEach(e => console.log(e));

  await browser.close();
})();
