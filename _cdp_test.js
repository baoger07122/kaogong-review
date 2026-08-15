// 用 CDP 直连系统 Chrome，真实测试本地预览的申论跳转
const { spawn } = require('child_process');
const WebSocket = require('C:/Users/bao/.workbuddy/binaries/node/workspace/node_modules/ws');
const http = require('http');

const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const DEBUG_PORT = 9239;

function getJson(url) {
  return new Promise((resolve, reject) => {
    http.get(url, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        const trimmed = d.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          try { resolve(JSON.parse(trimmed)); } catch (e) { reject(e); }
        } else { reject(new Error('非JSON: ' + trimmed.slice(0, 80))); }
      });
    }).on('error', reject);
  });
}

(async () => {
  // 启动 Chrome 直接打开预览页
  const chromeProc = spawn(CHROME, [
    '--headless=new', '--disable-gpu', '--no-sandbox',
    '--remote-debugging-port=' + DEBUG_PORT,
    '--remote-allow-origins=*',
    '--window-size=1180,820',
    'http://localhost:4173/'
  ], { stdio: ['ignore', 'ignore', 'ignore'] });

  // 等待 CDP 就绪
  let list;
  for (let i = 0; i < 50; i++) {
    try { list = await getJson(`http://127.0.0.1:${DEBUG_PORT}/json/list`); break; }
    catch (e) { await new Promise(r => setTimeout(r, 300)); }
  }
  if (!list) { console.log('CDP 未就绪'); chromeProc.kill(); return; }

  // 找到预览页 tab（type=page 且 url 含 4173）
  const page = list.find(t => t.type === 'page' && t.url.includes('4173')) || list.find(t => t.type === 'page');
  if (!page) { console.log('无页面tab', JSON.stringify(list)); chromeProc.kill(); return; }
  const ws = new WebSocket(page.webSocketDebuggerUrl);

  let msgId = 0;
  const pending = {};
  const consoleErrors = [];
  const pageErrors = [];

  function send(method, params) {
    return new Promise((resolve) => {
      const id = ++msgId;
      pending[id] = resolve;
      ws.send(JSON.stringify({ id, method, params: params || {} }));
    });
  }

  ws.on('message', data => {
    const msg = JSON.parse(data);
    if (msg.id && pending[msg.id]) { pending[msg.id](msg.result); delete pending[msg.id]; }
    if (msg.method === 'Runtime.consoleAPICalled' && msg.params.type === 'error') {
      const t = (msg.params.args || []).map(a => a.value || a.description || '').join(' ');
      consoleErrors.push('CONSOLE: ' + t);
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      pageErrors.push('EXCEPTION: ' + (d && d.text) + ' | ' + (d && d.exception ? d.exception.description : ''));
    }
  });
  await new Promise(r => ws.on('open', r));

  await send('Runtime.enable');
  await send('Page.enable');
  await new Promise(r => setTimeout(r, 3500));

  async function ev(expr) {
    try {
      const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
      return r && r.result ? r.result.value : undefined;
    } catch (e) { return 'EV_ERR:' + e.message; }
  }

  console.log('标题:', await ev('document.title'));

  await ev("App.Router.navigate('error-form')");
  await new Promise(r => setTimeout(r, 1500));
  console.log('[检查] 进入添加错题:', await ev("(function(){var c=document.getElementById('page-error-form');return c?c.innerText.replace(/\\s+/g,' ').slice(0,60):'无容器'})()"));

  await ev("(function(){var b=Array.from(document.querySelectorAll('.ef-selectbar')).find(x=>x.textContent.includes('科目'));if(b){b.click();return '点开科目'}return '未找到科目条'})()");
  await new Promise(r => setTimeout(r, 600));
  console.log('[检查] 弹窗:', await ev("(function(){var p=document.querySelector('.picker-modal');return p?('有弹窗,选项='+Array.from(p.querySelectorAll('.picker-modal__item')).map(i=>i.textContent.trim()).join(',')):'无弹窗'})()"));

  await ev("(function(){var it=Array.from(document.querySelectorAll('.picker-modal__item')).find(i=>i.textContent.trim()==='申论');if(it){it.click();return '点申论'}return '无申论'})()");
  await new Promise(r => setTimeout(r, 300));
  await ev("(function(){var ok=document.querySelector('.picker-modal__ok');if(ok){ok.click();return '确定'}return '无确定'})()");
  await new Promise(r => setTimeout(r, 1200));

  const after = await ev(`(function(){var c=document.getElementById('page-error-form');var t=c?c.innerText:'无容器';return {hasShenlunTitle:t.includes('添加申论错题')||t.includes('编辑申论错题'),hasFramework:t.includes('框架对比'),hasBias:t.includes('核心思维偏差'),hasSave:t.includes('保存申论错题'),snippet:t.replace(/\\s+/g,' ').slice(0,80)}})()`);
  console.log('=== 跳转结果 ===', JSON.stringify(after));

  console.log('--- 控制台错误 ---'); console.log(consoleErrors.length ? consoleErrors : ['无']);
  console.log('--- 页面异常 ---'); console.log(pageErrors.length ? pageErrors : ['无']);

  ws.close(); chromeProc.kill(); process.exit(0);
})().catch(e => { console.log('失败:', e.message); process.exit(1); });
