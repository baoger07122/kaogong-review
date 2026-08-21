// ===== 复习模块 V1：历史错题重新训练 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Review = {
  state: { queue: [], index: 0, result: null, subject: null },
  _escape(value) {
    return String(value == null ? '' : value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  },

  async _loadQueue(subject) {
    const due = await App.DB.getReviewQueue();
    const all = due.length ? due : await App.DB.getErrors();
    return all.filter(e => !subject || e.subject === subject);
  },

  async render(params) {
    params = params || {};
    const container = document.getElementById('page-review');
    container.innerHTML = '';
    if (params.mode === 'session') {
      if (!this.state.queue.length || this.state.subject !== (params.subject || null)) {
        this.state.subject = params.subject || null;
        this.state.queue = await this._loadQueue(this.state.subject);
        this.state.index = 0;
        this.state.result = null;
      }
      this._renderSession(container);
      return;
    }
    this.state.queue = [];
    this.state.result = null;
    await this._renderHome(container);
  },

  async _renderHome(container) {
    const header = document.createElement('div');
    header.className = 'review-header';
    header.innerHTML = '<div class="library-eyebrow">REVIEW MODE</div><h1>今日复习</h1><p>重新抽取历史错题，及时巩固薄弱知识点</p>';
    container.appendChild(header);

    const due = await App.DB.getReviewQueue();
    const all = due.length ? due : await App.DB.getErrors();
    const groups = this._groupBySubject(all);
    const hint = document.createElement('div');
    hint.className = 'review-hint';
    hint.textContent = due.length ? '优先显示超过 3 天未复习的错题' : (all.length ? '当前没有到期错题，先展示全部历史错题' : '还没有可复习的错题');
    container.appendChild(hint);

    const list = document.createElement('div');
    list.className = 'review-subject-list';
    Object.keys(groups).forEach(subject => {
      const cfg = App.Constants.SUBJECTS.find(s => s.name === subject) || { icon: '📚', color: '#0066CC' };
      const card = document.createElement('button');
      card.type = 'button';
      card.className = 'review-subject-card';
      card.innerHTML = '<span class="review-subject-card__icon" style="background:' + this._escape(cfg.color || '#0066CC') + '22">' + this._escape(cfg.icon || '📚') + '</span>' +
        '<span class="review-subject-card__body"><strong>' + this._escape(subject) + '</strong><small>' + groups[subject].length + ' 题待复习</small></span><span class="review-subject-card__arrow">›</span>';
      card.addEventListener('click', () => this._startSession(subject));
      list.appendChild(card);
    });
    if (!Object.keys(groups).length) list.innerHTML = '<div class="review-empty"><span>🎉</span><strong>暂无待复习错题</strong><small>先去学习库新增错题，之后可以在这里重新训练</small></div>';
    container.appendChild(list);

    const start = document.createElement('button');
    start.type = 'button';
    start.className = 'review-start-btn';
    start.textContent = all.length ? '开始全部复习' : '去学习库';
    start.addEventListener('click', () => all.length ? this._startSession(null) : App.Router.navigate('library'));
    container.appendChild(start);
  },

  _groupBySubject(errors) {
    const groups = {};
    (errors || []).forEach(error => {
      const key = error.subject || '未分类';
      if (!groups[key]) groups[key] = [];
      groups[key].push(error);
    });
    return groups;
  },

  async _startSession(subject) {
    this.state.subject = subject || null;
    this.state.queue = await this._loadQueue(this.state.subject);
    this.state.index = 0;
    this.state.result = null;
    App.Router.navigate('review?mode=session' + (subject ? '&subject=' + encodeURIComponent(subject) : ''));
  },

  _renderSession(container) {
    container.innerHTML = '';
    const error = this.state.queue[this.state.index];
    if (!error) {
      container.innerHTML = '<div class="review-finished"><span>✅</span><h1>本轮复习完成</h1><p>这组错题已经重新训练一遍。</p><button type="button" class="review-start-btn">返回复习首页</button></div>';
      container.querySelector('button').addEventListener('click', () => App.Router.navigate('review'));
      return;
    }

    const header = App.Components.pageHeader('第 ' + (this.state.index + 1) + ' / ' + this.state.queue.length + ' 题', '退出', () => App.Router.navigate('review'), { onBack: () => App.Router.navigate('review') });
    const right = header.querySelector('.page-header__right');
    if (right) { right.style.cursor = 'pointer'; right.addEventListener('click', () => App.Router.navigate('review')); }
    container.appendChild(header);

    const content = document.createElement('div');
    content.className = 'review-session';
    content.innerHTML = '<div class="review-session__meta">' + this._escape(error.subject || '未分类') + (error.module ? ' · ' + this._escape(error.module) : '') + '</div>' +
      '<div class="review-session__question">' + this._escape(error.question || '暂无题干') + '</div>';
    const options = document.createElement('div');
    options.className = 'review-options';
    const letters = ['A', 'B', 'C', 'D', 'E', 'F'];
    (error.options || []).filter(Boolean).forEach((option, index) => {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'review-option';
      button.innerHTML = '<b>' + letters[index] + '</b><span>' + this._escape(option) + '</span>';
      button.disabled = !!this.state.result;
      button.addEventListener('click', () => this._answer(error, letters[index]));
      options.appendChild(button);
    });
    content.appendChild(options);
    if (!options.children.length) {
      const noOptions = document.createElement('div');
      noOptions.className = 'review-no-options';
      noOptions.textContent = '这道错题没有可选项，请查看原题后完成复习。';
      content.appendChild(noOptions);
      const mark = document.createElement('button');
      mark.type = 'button';
      mark.className = 'review-next-btn';
      mark.textContent = '标记为已复习';
      mark.disabled = !!this.state.result;
      mark.addEventListener('click', () => this._answer(error, error.correctOption || ''));
      content.appendChild(mark);
    }
    if (this.state.result) {
      const result = document.createElement('div');
      result.className = 'review-result ' + (this.state.result.correct ? 'is-correct' : 'is-wrong');
      result.innerHTML = '<strong>' + (this.state.result.correct ? '回答正确 ✓' : '回答错误') + '</strong><span>正确答案：' + this._escape(error.correctOption || '未记录') + '</span>';
      content.appendChild(result);
      const next = document.createElement('button');
      next.type = 'button';
      next.className = 'review-next-btn';
      next.textContent = this.state.index + 1 >= this.state.queue.length ? '完成本轮' : '下一题';
      next.addEventListener('click', () => { this.state.index++; this.state.result = null; this._renderSession(container); });
      content.appendChild(next);
    }
    container.appendChild(content);
  },

  async _answer(error, selected) {
    const correct = !!error.correctOption && selected === error.correctOption;
    error.userOption = selected;
    error.reviewCount = (error.reviewCount || 0) + 1;
    error.lastReviewDate = new Date().toISOString();
    error.status = correct ? '已掌握' : '未掌握';
    try {
      await App.DB.updateError(error);
      this.state.result = { correct, selected };
      const container = document.getElementById('page-review');
      this._renderSession(container);
    } catch (e) {
      App.Components.toast('复习结果保存失败', 'error');
    }
  }
};
