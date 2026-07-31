// ===== 考公笔试复盘系统 - 工具函数 =====
window.App = window.App || {};

App.Utils = {
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

  // ===== 简易 Markdown 渲染 =====
  simpleMarkdown(text) {
    if (!text) return '';
    let html = text;

    // 转义 HTML
    html = html.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

    // 代码块
    html = html.replace(/```([\s\S]*?)```/g, '<pre><code>$1</code></pre>');

    // 行内代码
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

    // 标题
    html = html.replace(/^#### (.+)$/gm, '<h4>$1</h4>');
    html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
    html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
    html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');

    // 加粗和斜体
    html = html.replace(/\*\*\*(.+?)\*\*\*/g, '<strong><em>$1</em></strong>');
    html = html.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
    html = html.replace(/\*(.+?)\*/g, '<em>$1</em>');

    // 链接
    html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank">$1</a>');

    // 图片
    html = html.replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1">');

    // 无序列表
    html = html.replace(/^[\-\*] (.+)$/gm, '<li>$1</li>');
    html = html.replace(/(<li>.*<\/li>)/gs, '<ul>$1</ul>');

    // 有序列表
    html = html.replace(/^\d+\. (.+)$/gm, '<li>$1</li>');

    // 引用
    html = html.replace(/^> (.+)$/gm, '<blockquote>$1</blockquote>');

    // 分割线
    html = html.replace(/^---$/gm, '<hr>');

    // 换行
    html = html.replace(/\n\n/g, '</p><p>');
    html = html.replace(/\n/g, '<br>');
    html = '<p>' + html + '</p>';

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
