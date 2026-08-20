App.Utils = {
  // ===== Markdown 输入归一化（供详情页渲染与编辑器解析共用） =====
  normalizeMarkdownInput(md) {
    if (!md || typeof md !== 'string') return md || '';
    // 1) 统一换行（iOS contenteditable 用 U+2028/U+2029 作为行分隔符，必须一并转换）
    let s = md.replace(/\r\n/g, '\n').replace(/\r/g, '\n').replace(/[\u2028\u2029]/g, '\n');
    // 2) 把 <br> 系列替换为真实换行（编辑器或粘贴可能残留）
    s = s.replace(/<br\s*\/?>/gi, '\n');
    // 3) 解码常见 HTML 数字实体（&#35; -> #，&#10; -> 换行）
    s = s.replace(/&#(\d+);/g, (_, code) => String.fromCharCode(parseInt(code, 10)));
    s = s.replace(/&#[xX]([0-9a-fA-F]+);/g, (_, hex) => String.fromCharCode(parseInt(hex, 16)));
    // 4) 去掉零宽字符与不可见控制符
    // 注意：\xfeff 是 2 位 hex 转义（\xfe=þ + 字面 ff），会误删字母 f！
    // 必须用 \ufeff（4 位 hex，U+FEFF BOM），已与前面重复则只保留一个
    s = s.replace(/[\u200b\u200c\u200d\ufeff\u2060]/g, '');
    // 5) 若行被 <p>/<div> 等块级标签包裹，去掉标签并在边界补换行
    s = s.replace(/<(p|div|section|article|header|footer|main|blockquote|pre)[^>]*>([\s\S]*?)<\/\1\s*>/gi, '\n$2\n');
    // 6) 如果 # 被编码成 &amp;#35;（二次编码），还原
    s = s.replace(/&amp;#35;/g, '#');
    // 7) 把段落化标签后的多余空行合并
    s = s.replace(/\n{3,}/g, '\n\n');
    // 8) 只清理首尾的「换行」，保留行首空格/制表符缩进（trim() 会删掉首行缩进，
    //    导致编辑器第一行缩进保存后重新打开丢失；simpleMarkdown 依赖行首空格渲染缩进）
    return s.replace(/^\n+|\n+$/g, '');
  },

  // ===== ID 生成 =====
  genId(prefix) {
    return (prefix || 'id') + '_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8);
  },

  // ===== 日期格式化 =====
  formatDate(dateStr, format) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return dateStr;
    const pad = (n) => String(n).padStart(2, '0');
    const map = {
      'YYYY': d.getFullYear(),
      'MM': pad(d.getMonth() + 1),
      'DD': pad(d.getDate()),
      'HH': pad(d.getHours()),
      'mm': pad(d.getMinutes()),
      'ss': pad(d.getSeconds())
    };
    return (format || 'YYYY-MM-DD').replace(/YYYY|MM|DD|HH|mm|ss/g, m => map[m]);
  },

  formatDateTime(dateStr) {
    return this.formatDate(dateStr, 'YYYY-MM-DD HH:mm');
  },

  // ===== 相对时间（便签卡片等：今天→HH:mm，昨天→昨天，今年→M月D日，更早→YYYY-MM-DD） =====
  formatRelativeTime(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return dateStr;
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const startOfDay = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    const diffDays = Math.round((startOfDay(now) - startOfDay(d)) / 86400000);
    if (diffDays <= 0) return pad(d.getHours()) + ':' + pad(d.getMinutes());   // 今天
    if (diffDays === 1) return '昨天';
    if (d.getFullYear() === now.getFullYear()) return (d.getMonth() + 1) + '月' + d.getDate() + '日';
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
  },

  // ===== 距上次复习天数 =====
  daysSince(dateStr) {
    if (!dateStr) return 999;
    const d = new Date(dateStr);
    const now = new Date();
    return Math.floor((now - d) / (1000 * 60 * 60 * 24));
  },

  // ===== 深拷贝 =====
  deepClone(obj) {
    if (obj === null || typeof obj !== 'object') return obj;
    if (obj instanceof Date) return new Date(obj);
    if (Array.isArray(obj)) return obj.map(item => this.deepClone(item));
    const cloned = {};
    for (const key in obj) {
      if (obj.hasOwnProperty(key)) {
        cloned[key] = this.deepClone(obj[key]);
      }
    }
    return cloned;
  },

  // ===== 笔记查看层渲染（JSON 块 → HTML；笔记数据 JSON 化后替代 marked/simpleMarkdown） =====
  // 输入：编辑器 getEditorData() 输出的 JSON 块数组（对外格式 {type, content, html, checked, indent, ...}）
  // 输出：HTML 字符串（复用 md-preview-* 样式，与全站其它查看态一致）；公式随块 html 原样输出
  renderBlocks(blocks) {
    if (!Array.isArray(blocks)) return '';
    const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const inline = (b) => b.html ? b.html : esc(b.content || '').replace(/\n/g, '<br>');
    const indentStyle = (b) => b.indent ? ' style="padding-left:' + (b.indent * 24) + 'px;"' : '';
    let out = '';
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i] || {};
      const t = b.type || 'text';
      if (t === 'heading1' || t === 'heading2' || t === 'heading3' || t === 'heading4') {
        const tag = 'h' + (t === 'heading1' ? '1' : t === 'heading2' ? '2' : t === 'heading3' ? '3' : '4');
        out += '<' + tag + ' class="md-preview-' + tag + '"' + indentStyle(b) + '>' + inline(b) + '</' + tag + '>';
      } else if (t === 'bulletList' || t === 'orderedList') {
        const tag = t === 'bulletList' ? 'ul' : 'ol';
        const cls = t === 'bulletList' ? 'md-preview-ul' : 'md-preview-ol';
        out += '<' + tag + ' class="' + cls + '"' + indentStyle(b) + '>';
        while (i < blocks.length && (blocks[i] || {}).type === t) {
          out += '<li>' + inline(blocks[i]) + '</li>';
          i++;
        }
        out += '</' + tag + '>';
        i--;
      } else if (t === 'quote') {
        out += '<blockquote class="md-preview-blockquote"' + indentStyle(b) + '>' + inline(b) + '</blockquote>';
      } else if (t === 'divider') {
        out += '<hr class="md-preview-hr">';
      } else if (t === 'code') {
        out += '<pre class="md-preview-code"><code>' + esc(b.content || '') + '</code></pre>';
      } else if (t === 'todo') {
        out += '<div class="md-preview-todo"' + indentStyle(b) + '><input type="checkbox" ' + (b.checked ? 'checked' : '') + ' disabled>' + inline(b) + '</div>';
      } else if (t === 'callout') {
        out += '<div class="md-preview-callout"' + indentStyle(b) + '>' + esc(b.emoji || '💡') + ' ' + inline(b) + '</div>';
      } else if (t === 'table') {
        const td = b.tableData || [];
        out += '<table class="md-preview-table">';
        (td || []).forEach(r => {
          out += '<tr>' + (r || []).map(c => '<td>' + esc(c) + '</td>').join('') + '</tr>';
        });
        out += '</table>';
      } else if (t === 'image') {
        const img = b.imgData || {};
        out += '<img class="md-preview-img" src="' + esc(img.src || '') + '" alt="' + esc(img.alt || '') + '">';
      } else if (t === 'toggle') {
        out += '<details class="md-preview-toggle"' + indentStyle(b) + '><summary>' + inline(b) + '</summary>'
          + (b.children && b.children.length ? this.renderBlocks(b.children) : '') + '</details>';
      } else {
        // text / 其它默认段落
        out += '<p class="md-preview-p"' + indentStyle(b) + '>' + (inline(b) || '&nbsp;') + '</p>';
      }
    }
    return out;
  },

  // ===== v8.5.5 彻底去块：笔记 content 统一为「完整 HTML 字符串」（所见即所得直存，格式 100% 保真）=====
  // 历史数据三种形态：HTML 字符串（新）、JSON 块数组（v8.4.9~8.5.4）、Markdown 字符串（更早）
  // toNoteHtml(content)：任意形态 → 完整 HTML；已是 HTML 则原样返回（幂等）
  toNoteHtml(content) {
    if (Array.isArray(content)) return this.renderBlocks(content);
    if (typeof content !== 'string') return '';
    const s = content.trim();
    if (!s) return '';
    // 已是编辑器 HTML → 原样返回，不二次转换（幂等，保证编辑产物原样直存）。
    // 不能只判断「第一个标签」：富文本可能以 <strong>/<span>/<mark>/<code> 等行内标签开头，
    // 关联错题等局部表单操作触发重渲染时，旧判断会把它误当成 Markdown，再把标签转义成源码文字。
    // 这里仅识别编辑器允许产生的标签，避免把任意外部 HTML 都当成可渲染内容。
    const editorTags = 'p|h[1-6]|ul|ol|li|blockquote|pre|table|thead|tbody|tr|th|td|details|summary|div|section|figure|hr|br|strong|b|em|i|u|s|del|mark|span|a|img|code|sub|sup|small';
    const hasEditorHtml = new RegExp('<\\/?(?:' + editorTags + ')(?:\\s|/?>)', 'i').test(s);
    if (hasEditorHtml) return s;
    // 旧 Markdown / 纯文本 → 复用 mdToBlocks 解析为块 → renderBlocks 渲染成 HTML
    try {
      const blocks = this.mdToBlocks(s);
      return this.renderBlocks(blocks);
    } catch (e) {
      return '<p>' + String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>') + '</p>';
    }
  },

  // ===== 旧 Markdown 数据懒转换（笔记 JSON 化）：MD 字符串 → JSON 块数组 =====
  mdToBlocks(md) {
    try {
      const holder = document.createElement('div');
      holder.style.display = 'none';
      document.body.appendChild(holder);
      const ed = App.Components.initEditor(holder, { initialData: md || '', dataMode: 'json', onChange: null });
      const data = ed.getEditorData();
      holder.remove();
      // 过滤完全空白的占位块（空/空白内容不应产生空块，查看时显示「暂无内容」）
      return data.filter(b => (b.content || '').trim() || b.html || b.imgData || (b.tableData && b.tableData.length));
    } catch (e) {
      // 转换失败时兜底为单个文本块，保证内容不丢
      return String(md || '').trim() ? [{ type: 'text', content: String(md), html: '' }] : [];
    }
  },

  // ===== JSON 块字数统计（含 toggle children / 表格单元格；供右上角字数标签使用） =====
  countBlocks(blocks) {
    if (!Array.isArray(blocks)) return 0;
    let n = 0;
    const walk = (arr) => {
      (arr || []).forEach(b => {
        if (!b) return;
        n += (b.content || '').length;
        if (b.type === 'table') {
          (b.tableData || []).forEach(r => (r || []).forEach(c => { n += (c || '').length; }));
        }
        if (Array.isArray(b.children)) walk(b.children);
      });
    };
    walk(blocks);
    return n;
  },

  // v8.5.5 彻底去块：HTML 内容字数（去标签统计文字）
  countHtmlText(html) {
    if (typeof html !== 'string') return 0;
    return String(html)
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .trim().length;
  },

  // ===== 简易 Markdown 渲染 =====
  simpleMarkdown(text) {
    if (!text) return '';
    text = this.normalizeMarkdownInput(text);
    const rawLines = text.split('\n');
    const lines = [];
    // 先按代码块保护起来
    let inCode = false, codeBuf = [];
    rawLines.forEach(line => {
      if (inCode) {
        if (line.trim() === '```') {
          lines.push({ type: 'code', content: codeBuf.join('\n') });
          codeBuf = []; inCode = false;
        } else {
          codeBuf.push(line);
        }
      } else if (line.trim() === '```') {
        inCode = true;
      } else {
        lines.push({ type: 'normal', content: line });
      }
    });
    if (inCode) lines.push({ type: 'code', content: codeBuf.join('\n') });

    const out = [];
    let i = 0;
    while (i < lines.length) {
      const line = lines[i];
      if (line.type === 'code') {
        const escaped = this._escapeHtml(line.content);
        out.push('<pre class="md-preview-code"><code>' + escaped + '</code></pre>');
        i++; continue;
      }

      const content = line.content;
      const trimmed = content.trim();
      // 缩进级（每 2 空格 / 1 制表符为一级），渲染时保留左缩进，避免详情页丢失缩进
      const indentRaw = (content.match(/^(?: {2}|\t)+/) || [''])[0];
      const indentLevel = indentRaw ? Math.floor(indentRaw.replace(/\t/g, '  ').length / 2) : 0;
      const indentStyle = indentLevel > 0 ? ' style="padding-left:' + (indentLevel * 24) + 'px;"' : '';

      if (trimmed === '') {
        // 空白行：位于内容之间的渲染为占位（连续空行合并一个），开头/结尾不渲染
        while (i < lines.length && lines[i].type === 'normal' && lines[i].content.trim() === '') i++;
        if (out.length > 0 && i < lines.length) out.push('<div class="md-preview-blank">&nbsp;</div>');
        continue;
      }
      if (trimmed === '---') { out.push('<hr class="md-preview-hr">'); i++; continue; }

      // 块级公式 $$...$$（支持跨行：从 $$ 开头收集到 $$ 结尾）
      if (/^\$\$/.test(trimmed)) {
        let latex = trimmed.replace(/^\$\$/, '');
        let j = i;
        if (/\$\$$/.test(trimmed)) {
          latex = trimmed.replace(/^\$\$/, '').replace(/\$\$$/, '');
        } else {
          j++;
          while (j < lines.length) {
            latex += '\n' + lines[j].content;
            if (/\$\$$/.test(lines[j].content)) { latex = latex.replace(/\$\$$/, ''); break; }
            j++;
          }
        }
        out.push('<div class="mformula mformula--block" data-latex="' + encodeURIComponent(latex) + '">' + this.renderLatex(latex) + '</div>');
        i = j + 1;
        continue;
      }

      // 表格（连续 |...| 行）
      if (/^\s*\|.*\|\s*$/.test(content)) {
        const tableLines = [];
        while (i < lines.length && lines[i].type === 'normal' && /^\s*\|.*\|\s*$/.test(lines[i].content)) {
          tableLines.push(lines[i].content);
          i++;
        }
        out.push(this._renderMarkdownTable(tableLines));
        continue;
      }

      // 标题（兼容行首残留 &amp;#35; 被解码后的 #；兼容「####标题」无空格写法；纯 # 标记无文字的行直接跳过，避免显示裸 "###"）
      const hMatch = trimmed.match(/^(#{1,4})\s*(.*)$/);
      if (hMatch) {
        if (hMatch[2].trim()) {
          const tag = 'h' + hMatch[1].length;
          // 双重前缀兜底：hMatch[2] 若仍以 # 开头（「### ### 标题」），剥掉多余前缀
          const htext = hMatch[2].replace(/^(#{1,4}\s)+/, '');
          out.push('<' + tag + ' class="md-preview-' + tag + '"' + indentStyle + '>' + this._renderInlineMarkdown(htext) + '</' + tag + '>');
        }
        i++; continue;
      }
      if (/^#{1,4}\s*$/.test(trimmed)) { i++; continue; }

      // 无序列表
      if (/^[\-\*]\s+(.*)$/.test(trimmed)) {
        const items = [];
        while (i < lines.length && lines[i].type === 'normal' && /^[\-\*]\s+/.test(lines[i].content.trim())) {
          items.push(lines[i].content.trim().replace(/^[\-\*]\s+/, ''));
          i++;
        }
        out.push('<ul class="md-preview-ul"' + indentStyle + '>' + items.map(it => '<li>' + this._renderInlineMarkdown(it) + '</li>').join('') + '</ul>');
        continue;
      }

      // 有序列表
      if (/^\d+\.\s+(.*)$/.test(trimmed)) {
        const items = [];
        while (i < lines.length && lines[i].type === 'normal' && /^\d+\.\s+/.test(lines[i].content.trim())) {
          items.push(lines[i].content.trim().replace(/^\d+\.\s+/, ''));
          i++;
        }
        out.push('<ol class="md-preview-ol"' + indentStyle + '>' + items.map(it => '<li>' + this._renderInlineMarkdown(it) + '</li>').join('') + '</ol>');
        continue;
      }

      // 引用
      if (/^>\s?(.*)$/.test(trimmed)) {
        const items = [];
        while (i < lines.length && lines[i].type === 'normal' && /^>\s?/.test(lines[i].content.trim())) {
          items.push(lines[i].content.trim().replace(/^>\s?/, ''));
          i++;
        }
        out.push('<blockquote class="md-preview-blockquote"' + indentStyle + '>' + items.map(it => this._renderInlineMarkdown(it)).join('<br>') + '</blockquote>');
        continue;
      }

      // 普通段落（合并连续非空行；块内软换行保留为 <br>，不再被空格吞掉）
      // 关键：遇到新的块级标记（标题/列表/引用/公式/分隔线/表格）立即结束段落，
      // 否则编辑器导出（块间无空行）会把「- 列表项」等吞进段落导致列表不渲染。
      const isNewBlockStart = (line) => {
        const t = line.content.trim();
        if (!t) return true;
        if (/^(#{1,4})\s/.test(t)) return true;
        if (/^[\-\*]\s+/.test(t)) return true;
        if (/^\d+\.\s+/.test(t)) return true;
        if (/^>\s?/.test(t)) return true;
        if (/^\$\$/.test(t)) return true;
        if (t === '---') return true;
        if (/^\s*\|.*\|\s*$/.test(line.content)) return true;
        return false;
      };
      const paraLines = [];
      while (i < lines.length && lines[i].type === 'normal' && lines[i].content.trim() !== '' && !isNewBlockStart(lines[i])) {
        paraLines.push(lines[i].content);
        i++;
      }
      const para = paraLines.join('\n').trim();
      if (para) {
        out.push('<p class="md-preview-p"' + indentStyle + '>' + this._renderInlineMarkdown(para).replace(/\n/g, '<br>') + '</p>');
      }
    }

    return out.join('');
  },

  _escapeHtml(text) {
    if (!text) return '';
    return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  },

  // ===== 轻量 LaTeX 公式渲染（离线可用，零依赖；支持考公常用公式） =====
  // 语法：\frac{分子}{分母}、^上标/_下标（可 {组}）、\sqrt[n]{x}、\alpha 等希腊字母、
  //       \times \div \pm \leq \geq \approx \cdot \sum \int \infty \to 等运算符、\text{中文}
  renderLatex(src) {
    if (!src) return '';
    const GREEK = { alpha: 'α', beta: 'β', gamma: 'γ', delta: 'δ', epsilon: 'ε', zeta: 'ζ', eta: 'η', theta: 'θ', iota: 'ι', kappa: 'κ', lambda: 'λ', mu: 'μ', nu: 'ν', xi: 'ξ', pi: 'π', rho: 'ρ', sigma: 'σ', tau: 'τ', upsilon: 'υ', phi: 'φ', chi: 'χ', psi: 'ψ', omega: 'ω', Gamma: 'Γ', Delta: 'Δ', Theta: 'Θ', Lambda: 'Λ', Xi: 'Ξ', Pi: 'Π', Sigma: 'Σ', Phi: 'Φ', Psi: 'Ψ', Omega: 'Ω' };
    const OPS = { times: '×', div: '÷', pm: '±', mp: '∓', cdot: '·', leq: '≤', geq: '≥', neq: '≠', approx: '≈', sim: '∼', equiv: '≡', in: '∈', notin: '∉', subset: '⊂', supset: '⊃', subseteq: '⊆', supseteq: '⊇', cup: '∪', cap: '∩', sum: '∑', prod: '∏', int: '∫', infty: '∞', partial: '∂', nabla: '∇', forall: '∀', exists: '∃', emptyset: '∅', to: '→', rightarrow: '→', leftarrow: '←', Rightarrow: '⇒', Leftarrow: '⇐', leftrightarrow: '↔', cdots: '⋯', ldots: '…', prime: '′', degree: '°', angle: '∠', perp: '⊥', parallel: '∥', uparrow: '↑', downarrow: '↓', because: '∵', therefore: '∴' };
    const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    let pos = 0;

    function readGroup() {
      pos++;   // 跳过 {
      let out = '';
      while (pos < src.length && src[pos] !== '}') out += readUnit();
      if (pos < src.length) pos++;   // 消费 }
      return out;
    }
    function readUnit() {
      const c = src[pos];
      if (c === '\\') {
        pos++;
        let cmd = '';
        while (pos < src.length && /[a-zA-Z]/.test(src[pos])) { cmd += src[pos]; pos++; }
        const skipWs = () => { while (pos < src.length && /\s/.test(src[pos])) pos++; };
        if (cmd === 'frac') {
          skipWs(); let num = ''; if (src[pos] === '{') num = readGroup();
          skipWs(); let den = ''; if (src[pos] === '{') den = readGroup();
          return '<span class="mf-frac"><span class="mf-num">' + (num || '&nbsp;') + '</span><span class="mf-den">' + (den || '&nbsp;') + '</span></span>';
        }
        if (cmd === 'sqrt') {
          skipWs(); let root = '';
          if (src[pos] === '[') { const end = src.indexOf(']', pos); if (end > -1) { root = src.slice(pos + 1, end); pos = end + 1; } }
          skipWs(); let body = ''; if (src[pos] === '{') body = readGroup();
          return '<span class="mf-sqrt">' + (root ? '<span class="mf-sqrt__root">' + esc(root) + '</span>' : '') + '<span class="mf-sqrt__body">' + (body || '&nbsp;') + '</span></span>';
        }
        if (cmd === 'left' || cmd === 'right') {
          skipWs();
          const ch = src[pos] || ''; pos++;
          const map = { '(': '(', ')': ')', '[': '[', ']': ']', '\\': '|', '.': '' };
          return '<span class="mf-bracket">' + (map[ch] !== undefined ? esc(map[ch]) : '') + '</span>';
        }
        if (cmd === 'text') { skipWs(); if (src[pos] === '{') return '<span class="mf-text">' + readGroup() + '</span>'; return ''; }
        if (cmd === ' ' || cmd === ',') return '<span class="mf-space"></span>';
        if (cmd === 'quad') return '<span class="mf-space mf-space--q"></span>';
        if (GREEK[cmd]) return '<span class="mf-sym">' + GREEK[cmd] + '</span>';
        if (OPS[cmd]) return '<span class="mf-op">' + OPS[cmd] + '</span>';
        if (!cmd && pos < src.length) { const s2 = src[pos]; pos++; return esc(s2); }   // \ 后跟符号（\{ \} \$ \% \#）
        return esc('\\' + cmd);   // 未知命令原样保留
      }
      if (c === '{') return readGroup();
      if (c === '}') { pos++; return ''; }
      if (c === '^' || c === '_') {
        const isSup = c === '^'; pos++;
        let arg = '';
        if (src[pos] === '{') arg = readGroup();
        else if (src[pos] === '\\') arg = readUnit();
        else if (pos < src.length) { arg = esc(src[pos]); pos++; }
        return isSup ? '<sup>' + arg + '</sup>' : '<sub>' + arg + '</sub>';
      }
      if (c === ' ') { pos++; return '<span class="mf-space"></span>'; }
      pos++;
      return esc(c);
    }
    let result = '';
    while (pos < src.length) result += readUnit();
    return result;
  },

  _renderInlineMarkdown(text) {
    if (!text) return '';
    return this._escapeHtml(text)
      // 块级公式 $$...$$
      .replace(/\$\$([\s\S]+?)\$\$/g, (m, latex) => '<div class="mformula mformula--block" data-latex="' + encodeURIComponent(latex) + '">' + this.renderLatex(latex) + '</div>')
      // 行内公式 $...$（至少 2 个字符，避免误伤货币/编号）
      .replace(/\$([^\$\n]{2,})\$/g, (m, latex) => '<span class="mformula" data-latex="' + encodeURIComponent(latex) + '">' + this.renderLatex(latex) + '</span>')
      .replace(/`([^`\n]+)`/g, '<code class="md-preview-code-inline">$1</code>')
      .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1" class="md-preview-img">')
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>')
      .replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/==(.+?)==/g, '<mark class="notion-highlight">$1</mark>')
      .replace(/~~(.+?)~~/g, '<s>$1</s>')
      .replace(/\[u\]([\s\S]*?)\[\/u\]/g, '<u>$1</u>')
      .replace(/\[c=(#[0-9a-fA-F]{3,6}|rgb\([^)]+\))\]([\s\S]*?)\[\/c\]/g, '<span style="color:$1">$2</span>');
  },

  _renderMarkdownTable(lines) {
    if (!lines || lines.length === 0) return '';
    const rows = lines.map(l => l.split('|').map(c => c.trim()).filter(c => c !== ''));
    let bodyStart = 1;
    if (rows.length > 1 && /^:?-+:?$/.test(rows[1][0] || '')) bodyStart = 2;
    const headers = rows[0] || [];
    const body = rows.slice(bodyStart);
    let html = '<table class="md-preview-table">';
    if (headers.length) {
      html += '<thead><tr>' + headers.map(h => '<th>' + this._renderInlineMarkdown(h) + '</th>').join('') + '</tr></thead>';
    }
    if (body.length) {
      html += '<tbody>' + body.map(r => '<tr>' + r.map(c => '<td>' + this._renderInlineMarkdown(c) + '</td>').join('') + '</tr>').join('') + '</tbody>';
    }
    html += '</table>';
    return html;
  },

  // ===== 截断文本 =====
  truncate(text, maxLen) {
    if (!text) return '';
    if (text.length <= maxLen) return text;
    return text.slice(0, maxLen) + '...';
  },

  // ===== 节流 =====
  throttle(fn, delay) {
    let lastTime = 0;
    return function(...args) {
      const now = Date.now();
      if (now - lastTime >= delay) {
        lastTime = now;
        fn.apply(this, args);
      }
    };
  },

  // ===== 防抖 =====
  debounce(fn, delay) {
    let timer = null;
    return function(...args) {
      clearTimeout(timer);
      timer = setTimeout(() => fn.apply(this, args), delay);
    };
  },

  // ===== 列表内容平滑切换（只进不出）：原子替换 + 轻微上移淡入，无空白帧、无退出动画 =====
  transitionSwap(container, buildFn) {
    const token = (container._swapToken || 0) + 1;
    container._swapToken = token;
    const reset = () => {
      if (container._swapToken !== token) return;
      container.style.height = '';
      container.style.overflow = '';
      container.style.animation = '';
      container.style.transition = '';
      container._swapToken = 0;
    };
    const oldH = container.offsetHeight;
    container.style.height = oldH + 'px';
    container.style.overflow = 'hidden';
    // 先渲染到隐藏临时容器（保证布局测量准确），再原子替换
    const tmp = document.createElement('div');
    tmp.style.cssText = 'position:absolute;visibility:hidden;left:-9999px;top:0;';
    container.appendChild(tmp);
    Promise.resolve(buildFn(tmp)).then(() => {
      if (container._swapToken !== token) { tmp.remove(); return; }
      const newH = tmp.offsetHeight;
      const nodes = Array.from(tmp.childNodes);
      container.replaceChildren(...nodes);
      tmp.remove();
      container.style.transition = 'height 0.2s ease';
      container.style.height = newH + 'px';
      container.style.animation = 'listEnter 0.28s ease';
      setTimeout(reset, 300);
    }).catch(() => { tmp.remove(); reset(); });
  },

  // ===== 记住表单上次选择的科目/模块 =====
  rememberSelect: {
    get(kind) {
      try {
        const s = localStorage.getItem('kg_last_' + kind + '_subject');
        if (!s) return null;
        return { subject: s, module: localStorage.getItem('kg_last_' + kind + '_module') || '' };
      } catch (e) { return null; }
    },
    set(kind, subject, module) {
      try {
        localStorage.setItem('kg_last_' + kind + '_subject', subject || '');
        localStorage.setItem('kg_last_' + kind + '_module', module || '');
      } catch (e) {}
    }
  },

  // ===== 主题管理 =====
  Theme: {
    init() {
      const saved = localStorage.getItem('theme');
      if (saved === 'dark') {
        document.documentElement.setAttribute('data-theme', 'dark');
      } else if (saved === 'light') {
        document.documentElement.setAttribute('data-theme', 'light');
      }
      // 否则跟随系统（CSS 自动处理）

      window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (e) => {
        if (!localStorage.getItem('theme')) {
          document.documentElement.removeAttribute('data-theme');
        }
      });
    },

    toggle() {
      const current = document.documentElement.getAttribute('data-theme');
      if (current === 'dark') {
        this.set('light');
      } else {
        this.set('dark');
      }
    },

    set(mode) {
      if (mode === 'auto') {
        document.documentElement.removeAttribute('data-theme');
        localStorage.removeItem('theme');
      } else {
        document.documentElement.setAttribute('data-theme', mode);
        localStorage.setItem('theme', mode);
      }
    },

    get() {
      const saved = localStorage.getItem('theme');
      if (saved) return saved;
      return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    }
  },

  // ===== 左滑手势 =====
  initSwipeable(element, options) {
    let startX = 0, startY = 0, currentX = 0, isSwiping = false;
    const threshold = 60;

    element.addEventListener('touchstart', (e) => {
      startX = e.touches[0].clientX;
      startY = e.touches[0].clientY;
      currentX = startX;
      isSwiping = true;
    }, { passive: true });

    element.addEventListener('touchmove', (e) => {
      if (!isSwiping) return;
      currentX = e.touches[0].clientX;
      const diffX = startX - currentX;
      const diffY = Math.abs(e.touches[0].clientY - startY);

      if (diffX > 10 && diffX > diffY) {
        e.preventDefault();
        element.style.transform = `translateX(-${Math.min(diffX, 150)}px)`;
        element.style.transition = 'none';
      }
    }, { passive: false });

    element.addEventListener('touchend', () => {
      if (!isSwiping) return;
      isSwiping = false;
      const diffX = startX - currentX;
      element.style.transition = 'transform 0.3s ease';
      if (diffX > threshold) {
        element.style.transform = 'translateX(-150px)';
        if (options && options.onSwipe) options.onSwipe();
      } else {
        element.style.transform = 'translateX(0)';
      }
    });
  },

  resetSwipe(element) {
    element.style.transition = 'transform 0.3s ease';
    element.style.transform = 'translateX(0)';
  },

  // ===== 下拉刷新 =====
  initPullToRefresh(container, onRefresh) {
    let startY = 0, pulling = false, pulled = 0;
    const indicator = document.createElement('div');
    indicator.className = 'pull-indicator';
    indicator.innerHTML = '<span class="pull-spinner"></span>';
    container.prepend(indicator);

    container.addEventListener('touchstart', (e) => {
      if (container.scrollTop <= 0) {
        startY = e.touches[0].clientY;
        pulling = true;
        indicator.style.display = 'none';
      }
    }, { passive: true });

    container.addEventListener('touchmove', (e) => {
      if (!pulling) return;
      pulled = e.touches[0].clientY - startY;
      if (pulled > 20) {
        indicator.style.display = 'flex';
        indicator.style.height = Math.min(pulled - 20, 60) + 'px';
        if (pulled > 80) {
          indicator.classList.add('ready');
        }
      }
    }, { passive: true });

    container.addEventListener('touchend', () => {
      if (!pulling) return;
      pulling = false;
      if (pulled > 80) {
        indicator.classList.add('refreshing');
        onRefresh().finally(() => {
          indicator.style.height = '0';
          indicator.classList.remove('ready', 'refreshing');
          setTimeout(() => { indicator.style.display = 'none'; }, 300);
        });
      } else {
        indicator.style.height = '0';
        indicator.classList.remove('ready');
        setTimeout(() => { indicator.style.display = 'none'; }, 300);
      }
    });
  }
};
