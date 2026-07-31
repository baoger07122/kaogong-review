// ===== 考公笔试复盘系统 - 套卷记录页面 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Exams = {
  state: {
    filter: 'all',     // 'month' | '3month' | 'all'
    sort: 'date-desc', // 'date-desc' | 'accuracy-desc' | 'accuracy-asc'
    search: '',
    allExams: []
  },

  async render(params) {
    const container = document.getElementById('page-exams');
    container.innerHTML = '';

    // 页面标题
    const header = document.createElement('div');
    header.className = 'page-header';
    header.innerHTML = `
      <div class="page-header__title">套卷记录</div>
      <div class="page-header__right" id="exam-count">共 0 套</div>
    `;
    container.appendChild(header);

    // 搜索栏
    const searchBar = document.createElement('div');
    searchBar.className = 'search-bar';
    searchBar.innerHTML = `
      <span class="search-bar__icon">🔍</span>
      <input type="text" placeholder="搜索套卷名称..." id="exam-search">
    `;
    container.appendChild(searchBar);

    searchBar.querySelector('input').addEventListener('input', App.Utils.debounce((e) => {
      this.state.search = e.target.value;
      this.refreshList();
    }, 300));

    // 统计概览
    const statsRow = document.createElement('div');
    statsRow.className = 'stats-row';
    statsRow.id = 'exam-stats';
    container.appendChild(statsRow);

    // 筛选与排序
    const filterBar = document.createElement('div');
    filterBar.id = 'exam-filter-bar';
    container.appendChild(filterBar);

    // 列表
    const listArea = document.createElement('div');
    listArea.id = 'exam-list';
    container.appendChild(listArea);

    // 加载数据
    await this.loadData();
    this.renderStats(statsRow);
    this.renderFilters(filterBar);
    this.renderList(listArea);
  },

  async loadData() {
    this.state.allExams = await App.DB.getExams();
  },

  renderStats(container) {
    const exams = this.state.allExams;
    const total = exams.length;
    const avgAccuracy = total > 0
      ? Math.round(exams.reduce((sum, e) => sum + (e.totalAccuracy || 0), 0) / total)
      : 0;
    const thisWeek = exams.filter(e => {
      const d = new Date(e.examDate);
      const now = new Date();
      const weekAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
      return d >= weekAgo;
    }).length;
    const totalTime = exams.reduce((sum, e) => sum + (e.totalTime || 0), 0);

    container.innerHTML = `
      <div class="stat-item">
        <div class="stat-item__value">${total}</div>
        <div class="stat-item__label">总套卷</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value stat-item__value--danger">${avgAccuracy}%</div>
        <div class="stat-item__label">平均正确率</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value">${thisWeek}</div>
        <div class="stat-item__label">本周套卷</div>
      </div>
      <div class="stat-item">
        <div class="stat-item__value">${Math.round(totalTime / 60)}h</div>
        <div class="stat-item__label">累计用时</div>
      </div>
    `;
  },

  renderFilters(container) {
    container.innerHTML = '';

    // 时间范围
    const timeFilter = App.Components.filterTags(
      [{ name: '全部' }, { name: '本月' }, { name: '近三月' }],
      this.state.filter === 'all' ? '全部' : (this.state.filter === 'month' ? '本月' : '近三月'),
      (val) => {
        const map = { '全部': 'all', '本月': 'month', '近三月': '3month' };
        this.state.filter = map[val] || 'all';
        this.refreshList();
      }
    );
    container.appendChild(timeFilter);

    // 排序
    const sortFilter = App.Components.filterTags(
      [{ name: '最新' }, { name: '正确率↑' }, { name: '正确率↓' }],
      this.state.sort === 'date-desc' ? '最新' : (this.state.sort === 'accuracy-desc' ? '正确率↑' : '正确率↓'),
      (val) => {
        const map = { '最新': 'date-desc', '正确率↑': 'accuracy-desc', '正确率↓': 'accuracy-asc' };
        this.state.sort = map[val] || 'date-desc';
        this.refreshList();
      }
    );
    container.appendChild(sortFilter);
  },

  getFilteredExams() {
    let exams = [...this.state.allExams];

    // 搜索过滤
    if (this.state.search) {
      const kw = this.state.search.toLowerCase();
      exams = exams.filter(e => e.name.toLowerCase().includes(kw));
    }

    // 时间过滤
    const now = new Date();
    if (this.state.filter === 'month') {
      const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
      exams = exams.filter(e => new Date(e.examDate) >= monthStart);
    } else if (this.state.filter === '3month') {
      const threeMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 3, 1);
      exams = exams.filter(e => new Date(e.examDate) >= threeMonthsAgo);
    }

    // 排序
    if (this.state.sort === 'accuracy-desc') {
      exams.sort((a, b) => (b.totalAccuracy || 0) - (a.totalAccuracy || 0));
    } else if (this.state.sort === 'accuracy-asc') {
      exams.sort((a, b) => (a.totalAccuracy || 0) - (b.totalAccuracy || 0));
    } else {
      exams.sort((a, b) => new Date(b.examDate) - new Date(a.examDate));
    }

    return exams;
  },

  renderList(container) {
    container.innerHTML = '';

    const exams = this.getFilteredExams();
    const countEl = document.getElementById('exam-count');
    if (countEl) countEl.textContent = '共 ' + exams.length + ' 套';

    if (exams.length === 0) {
      container.appendChild(App.Components.emptyState(
        '📄',
        '还没有套卷记录',
        '每次模考后记录到这里，追踪进步',
        '记录套卷',
        () => App.Router.navigate('exam-form')
      ));
      return;
    }

    // 时间线布局
    const timeline = document.createElement('div');
    timeline.className = 'timeline';

    exams.forEach((exam, idx) => {
      const item = document.createElement('div');
      item.className = 'timeline-item';

      // 时间线圆点
      const dot = document.createElement('div');
      dot.className = 'timeline-dot';
      item.appendChild(dot);

      // 日期标签
      const dateLabel = document.createElement('div');
      dateLabel.style.cssText = 'font-size:var(--font-xs);color:var(--text-tertiary);margin-bottom:8px;';
      dateLabel.textContent = App.Utils.formatDate(exam.examDate);
      item.appendChild(dateLabel);

      // 套卷卡片
      const card = App.Components.examCard(exam, () => {
        App.Router.navigate('exam-detail?id=' + exam.id);
      });
      item.appendChild(card);

      // 左滑操作
      App.Utils.initSwipeable(card, {
        onSwipe: async () => {
          const action = await App.Components.actionSheet([
            { label: '编辑', value: 'edit' },
            { label: '删除', value: 'delete' }
          ], exam.name);

          if (action === 'edit') {
            App.Router.navigate('exam-form?id=' + exam.id);
          } else if (action === 'delete') {
            const confirmed = await App.Components.confirm(
              '删除套卷',
              '确定删除"' + exam.name + '"？\n关联的错题将保留在错题本中。',
              '删除', '取消', true
            );
            if (confirmed) {
              await App.DB.remove('exams', exam.id);
              App.Components.toast('已删除', 'success');
              this.refreshAll();
            }
          }
          App.Utils.resetSwipe(card);
        }
      });

      timeline.appendChild(item);
    });

    container.appendChild(timeline);
  },

  refreshAll() {
    this.loadData().then(() => {
      const statsRow = document.getElementById('exam-stats');
      const filterBar = document.getElementById('exam-filter-bar');
      const listArea = document.getElementById('exam-list');
      if (statsRow) this.renderStats(statsRow);
      if (filterBar) this.renderFilters(filterBar);
      if (listArea) this.renderList(listArea);
    });
  },

  // ===== 套卷详情页 =====
  async renderDetail(params) {
    const container = document.getElementById('page-exam-detail');
    container.innerHTML = '';

    const examId = params.id;
    if (!examId) { App.Router.navigate('exams'); return; }

    const exam = await App.DB.get('exams', examId);
    if (!exam) {
      App.Components.toast('套卷不存在', 'error');
      App.Router.navigate('exams');
      return;
    }

    container.appendChild(App.Components.pageHeader('套卷详情'));

    const content = document.createElement('div');
    content.style.cssText = 'padding:var(--spacing-md) var(--page-padding);padding-bottom:120px;';

    // 基础信息卡片
    const infoCard = document.createElement('div');
    infoCard.className = 'card';
    infoCard.style.margin = '0 0 var(--spacing-md) 0';
    infoCard.innerHTML = `
      <div style="font-size:var(--font-lg);font-weight:700;margin-bottom:8px;">${exam.name}</div>
      <div style="display:grid;grid-template-columns:repeat(2,1fr);gap:8px;font-size:var(--font-sm);">
        <div><span style="color:var(--text-tertiary);">考试日期</span><br>${App.Utils.formatDate(exam.examDate)}</div>
        <div><span style="color:var(--text-tertiary);">总正确率</span><br><strong style="color:var(--color-primary);">${exam.totalAccuracy || 0}%</strong></div>
        <div><span style="color:var(--text-tertiary);">总用时</span><br>${exam.totalTime || 0} 分钟</div>
        ${exam.targetScore ? `<div><span style="color:var(--text-tertiary);">目标分数</span><br>${exam.targetScore}</div>` : ''}
      </div>
    `;
    content.appendChild(infoCard);

    // 科目成绩拆解
    if (exam.subjectScores && exam.subjectScores.length > 0) {
      const scoresTitle = document.createElement('div');
      scoresTitle.style.cssText = 'font-size:var(--font-md);font-weight:600;margin-bottom:var(--spacing-sm);';
      scoresTitle.textContent = '科目成绩拆解';
      content.appendChild(scoresTitle);

      const scoresTable = document.createElement('div');
      scoresTable.style.cssText = 'overflow-x:auto;margin-bottom:var(--spacing-md);-webkit-overflow-scrolling:touch;';

      let tableHtml = '<table style="width:100%;border-collapse:collapse;font-size:var(--font-sm);min-width:400px;">';
      tableHtml += '<thead><tr style="border-bottom:2px solid var(--border-color);">';
      tableHtml += '<th style="text-align:left;padding:8px;">科目</th>';
      tableHtml += '<th style="text-align:center;padding:8px;">正确数</th>';
      tableHtml += '<th style="text-align:center;padding:8px;">正确率</th>';
      tableHtml += '</tr></thead><tbody>';

      exam.subjectScores.forEach(s => {
        const subj = App.Constants.SUBJECTS.find(su => su.name === s.subject);
        const color = subj ? subj.color : '#6B8EAD';
        const pct = s.totalScore ? Math.round((s.score || 0) / s.totalScore * 100) : 0;
        tableHtml += `<tr style="border-bottom:1px solid var(--divider-color);">
          <td style="padding:10px 8px;display:flex;align-items:center;gap:6px;">
            <span style="width:10px;height:10px;border-radius:50%;background:${color};display:inline-block;"></span>
            ${s.subject}
          </td>
          <td style="text-align:center;padding:10px 8px;">${s.score || 0}/${s.totalScore || 0}</td>
          <td style="text-align:center;padding:10px 8px;font-weight:600;color:${pct >= 70 ? 'var(--color-success)' : 'var(--color-danger)'};">${pct}%</td>
        </tr>`;
      });
      tableHtml += '</tbody></table>';
      scoresTable.innerHTML = tableHtml;
      content.appendChild(scoresTable);
    }

    // 关联错题
    if (exam.linkedErrorIds && exam.linkedErrorIds.length > 0) {
      const linkedTitle = document.createElement('div');
      linkedTitle.style.cssText = 'font-size:var(--font-md);font-weight:600;margin-bottom:var(--spacing-sm);';
      linkedTitle.textContent = '关联错题（' + exam.linkedErrorIds.length + '）';
      content.appendChild(linkedTitle);

      for (const errId of exam.linkedErrorIds) {
        try {
          const err = await App.DB.get('errors', errId);
          if (err) {
            const errItem = document.createElement('div');
            errItem.style.cssText = 'padding:10px;margin-bottom:4px;background:var(--bg-tertiary);border-radius:var(--radius-sm);font-size:var(--font-sm);cursor:pointer;display:flex;justify-content:space-between;align-items:center;';
            errItem.innerHTML = `
              <span>${App.Utils.truncate(err.question, 40)}</span>
              <span class="tag tag--${err.status === '已掌握' ? 'success' : 'danger'}">${err.status}</span>
            `;
            errItem.addEventListener('click', () => App.Router.navigate('error-detail?id=' + err.id));
            content.appendChild(errItem);
          }
        } catch (e) {}
      }
    }

    // 复盘笔记
    const reviewTitle = document.createElement('div');
    reviewTitle.style.cssText = 'font-size:var(--font-md);font-weight:600;margin-bottom:var(--spacing-sm);';
    reviewTitle.textContent = '复盘笔记';
    content.appendChild(reviewTitle);

    const reviewNote = document.createElement('div');
    reviewNote.className = 'card';
    reviewNote.style.cssText = 'margin:0;line-height:1.7;min-height:40px;';
    reviewNote.innerHTML = exam.reviewNote
      ? App.Utils.simpleMarkdown(exam.reviewNote)
      : '<span style="color:var(--text-tertiary);">暂无复盘笔记</span>';
    content.appendChild(reviewNote);

    container.appendChild(content);

    // 底部操作
    const bottomActions = document.createElement('div');
    bottomActions.className = 'bottom-actions';
    bottomActions.style.bottom = '0';

    const editBtn = document.createElement('button');
    editBtn.className = 'btn btn--outline';
    editBtn.textContent = '编辑';
    editBtn.addEventListener('click', () => App.Router.navigate('exam-form?id=' + exam.id));
    bottomActions.appendChild(editBtn);

    const deleteBtn = document.createElement('button');
    deleteBtn.className = 'btn btn--danger';
    deleteBtn.textContent = '删除';
    deleteBtn.addEventListener('click', async () => {
      const confirmed = await App.Components.confirm(
        '删除套卷',
        '确定删除该套卷记录？关联的错题将保留在错题本中。',
        '删除', '取消', true
      );
      if (confirmed) {
        await App.DB.remove('exams', exam.id);
        App.Components.toast('已删除', 'success');
        App.Router.navigate('exams');
      }
    });
    bottomActions.appendChild(deleteBtn);

    container.appendChild(bottomActions);
  },

  // ===== 新建/编辑套卷表单 =====
  renderForm(params) {
    const container = document.getElementById('page-exam-form');
    container.innerHTML = '';

    let isEdit = !!params.id;

    let formData = {
      name: '',
      examDate: new Date().toISOString().slice(0, 10),
      subjectScores: [],
      totalAccuracy: '',
      totalTime: '',
      targetScore: '',
      reviewNote: '',
      linkedErrorIds: []
    };

    const loadAndRender = async () => {
      if (isEdit) {
        const exam = await App.DB.get('exams', params.id);
        if (exam) {
          formData = {
            name: exam.name || '',
            examDate: exam.examDate || '',
            subjectScores: exam.subjectScores || [],
            totalAccuracy: exam.totalAccuracy !== undefined ? String(exam.totalAccuracy) : '',
            totalTime: exam.totalTime !== undefined ? String(exam.totalTime) : '',
            targetScore: exam.targetScore !== undefined ? String(exam.targetScore) : '',
            reviewNote: exam.reviewNote || '',
            linkedErrorIds: exam.linkedErrorIds || [],
            id: exam.id
          };
        }
        formData._formId = params.id;
      } else {
        // 新建/续编：仅当 sessionStorage 记录着「同一篇正在录入」的 id 时才续编；否则一律空白。
        const fid = App.Draft.getFormId('exam');
        if (fid) {
          if (App.Draft.formIdIsTemp(fid)) {
            const d = App.Draft.loadForm('exam', fid);
            if (d) Object.assign(formData, d);
            formData._formId = fid;
          } else {
            const exam = await App.DB.get('exams', fid);
            if (exam) {
              isEdit = true;
              formData = {
                name: exam.name || '',
                examDate: exam.examDate || '',
                subjectScores: exam.subjectScores || [],
                totalAccuracy: exam.totalAccuracy !== undefined ? String(exam.totalAccuracy) : '',
                totalTime: exam.totalTime !== undefined ? String(exam.totalTime) : '',
                targetScore: exam.targetScore !== undefined ? String(exam.targetScore) : '',
                reviewNote: exam.reviewNote || '',
                linkedErrorIds: exam.linkedErrorIds || [],
                id: exam.id
              };
              formData._formId = fid;
            }
          }
        }
        if (!formData._formId) {
          formData._formId = App.Draft.newTempId();
          App.Draft.setFormId('exam', formData._formId);
        }
      }
      buildForm();
    };

    const buildForm = () => {
      container.innerHTML = '';

      container.appendChild(App.Components.pageHeader(
        isEdit ? '编辑套卷' : '记录套卷',
        '保存',
        async () => {
          if (!formData.name.trim()) {
            App.Components.toast('请输入套卷名称', 'error');
            return;
          }
          await submitForm();
        }
      ));

      const form = document.createElement('div');
      form.className = 'form-page';

      // 套卷名称
      form.appendChild(App.Components.formInput(
        '套卷名称',
        formData.name,
        '例如：2025国考行测真题',
        (val) => { formData.name = val; },
        'text',
        true
      ));

      // 考试日期
      form.appendChild(App.Components.formInput(
        '考试日期',
        formData.examDate,
        'YYYY-MM-DD',
        (val) => { formData.examDate = val; },
        'date',
        true
      ));

      // 科目成绩
      const scoresGroup = document.createElement('div');
      scoresGroup.className = 'form-group';
      const scoresLabel = document.createElement('label');
      scoresLabel.className = 'form-label';
      scoresLabel.textContent = '科目成绩';
      scoresGroup.appendChild(scoresLabel);

      // 快速添加科目
      const addSubjectRow = document.createElement('div');
      addSubjectRow.style.cssText = 'display:flex;gap:6px;margin-bottom:8px;';

      const subjectSelect = document.createElement('select');
      subjectSelect.className = 'form-select';
      subjectSelect.style.flex = '1';
      subjectSelect.innerHTML = '<option value="">选择科目</option>';
      App.Constants.SUBJECTS.forEach(s => {
        subjectSelect.innerHTML += `<option value="${s.name}">${s.name}</option>`;
      });

      const scoreInput = document.createElement('input');
      scoreInput.className = 'form-input';
      scoreInput.style.width = '60px';
      scoreInput.placeholder = '正确数';
      scoreInput.type = 'number';

      const totalInput = document.createElement('input');
      totalInput.className = 'form-input';
      totalInput.style.width = '60px';
      totalInput.placeholder = '总题数';
      totalInput.type = 'number';

      const addScoreBtn = document.createElement('button');
      addScoreBtn.className = 'btn btn--primary btn--sm';
      addScoreBtn.textContent = '+';
      addScoreBtn.addEventListener('click', () => {
        const subj = subjectSelect.value;
        const score = parseInt(scoreInput.value) || 0;
        const total = parseInt(totalInput.value) || 0;
        if (!subj) { App.Components.toast('请选择科目', 'error'); return; }
        // 替换或添加
        const existingIdx = formData.subjectScores.findIndex(s => s.subject === subj);
        if (existingIdx >= 0) {
          formData.subjectScores[existingIdx] = { subject: subj, score, totalScore: total };
        } else {
          formData.subjectScores.push({ subject: subj, score, totalScore: total });
        }
        subjectSelect.value = '';
        scoreInput.value = '';
        totalInput.value = '';
        buildForm();
      });

      addSubjectRow.appendChild(subjectSelect);
      addSubjectRow.appendChild(scoreInput);
      addSubjectRow.appendChild(totalInput);
      addSubjectRow.appendChild(addScoreBtn);
      scoresGroup.appendChild(addSubjectRow);

      // 已添加的科目列表
      formData.subjectScores.forEach(s => {
        const subj = App.Constants.SUBJECTS.find(su => su.name === s.subject);
        const color = subj ? subj.color : '#6B8EAD';
        const row = document.createElement('div');
        row.style.cssText = 'display:flex;align-items:center;justify-content:space-between;padding:6px 0;font-size:var(--font-sm);';
        row.innerHTML = `
          <span style="display:flex;align-items:center;gap:6px;">
            <span style="width:8px;height:8px;border-radius:50%;background:${color};display:inline-block;"></span>
            ${s.subject}：${s.score}/${s.totalScore}
          </span>
        `;
        const removeBtn = document.createElement('button');
        removeBtn.className = 'btn--text';
        removeBtn.textContent = '移除';
        removeBtn.addEventListener('click', () => {
          formData.subjectScores = formData.subjectScores.filter(ss => ss.subject !== s.subject);
          buildForm();
        });
        row.appendChild(removeBtn);
        scoresGroup.appendChild(row);
      });

      form.appendChild(scoresGroup);

      // 快速录入模式
      const quickRow = document.createElement('div');
      quickRow.style.cssText = 'display:flex;gap:var(--spacing-md);margin-bottom:var(--spacing-md);';
      quickRow.appendChild(App.Components.formInput(
        '总正确率（%）',
        formData.totalAccuracy,
        '例如：72',
        (val) => { formData.totalAccuracy = val; },
        'number'
      ));
      quickRow.appendChild(App.Components.formInput(
        '总用时（分钟）',
        formData.totalTime,
        '例如：120',
        (val) => { formData.totalTime = val; },
        'number'
      ));
      form.appendChild(quickRow);

      form.appendChild(App.Components.formInput(
        '目标分数',
        formData.targetScore,
        '可选',
        (val) => { formData.targetScore = val; },
        'number'
      ));

      // 复盘笔记
      const noteGroup = document.createElement('div');
      noteGroup.className = 'form-group';
      const noteLabel = document.createElement('label');
      noteLabel.className = 'form-label';
      noteLabel.textContent = '复盘笔记';
      noteGroup.appendChild(noteLabel);

      const editor = App.Components.markdownEditor(formData.reviewNote, '记录本次考试的得失...');
      noteGroup.appendChild(editor.element);
      formData._getNote = editor.getContent;
      form.appendChild(noteGroup);

      container.appendChild(form);

      // 草稿自动暂存 + 触发 DB 自动保存
      App.Draft.autoSaveForm('exam', formData._formId, container, function () {
        if (formData._getNote) { try { formData.reviewNote = formData._getNote(); } catch (e) {} }
        debouncedSaveToDB();
        return JSON.parse(JSON.stringify(formData));
      });
    };

    let _examSaveTimer = null, _examSaving = false;
    function debouncedSaveToDB() {
      clearTimeout(_examSaveTimer);
      _examSaveTimer = setTimeout(async () => {
        if (_examSaving) return;
        if (!formData.name.trim()) return;
        _examSaving = true;
        try { await submitFormInternal(); } catch (e) {}
        _examSaving = false;
      }, 2000);
    }

    const submitFormInternal = async () => {
      if (formData._getNote) formData.reviewNote = formData._getNote();
      if (isEdit && formData.id) {
        await App.DB.updateExam({
          id: formData.id, name: formData.name, examDate: formData.examDate,
          subjectScores: formData.subjectScores,
          totalAccuracy: parseInt(formData.totalAccuracy) || 0,
          totalTime: parseInt(formData.totalTime) || 0,
          targetScore: parseInt(formData.targetScore) || 0,
          reviewNote: formData.reviewNote, linkedErrorIds: formData.linkedErrorIds
        });
      } else {
        if (!formData.id) {
          formData.id = await App.DB.addExam({
            name: formData.name || '未命名套卷', examDate: formData.examDate,
            subjectScores: formData.subjectScores,
            totalAccuracy: parseInt(formData.totalAccuracy) || 0,
            totalTime: parseInt(formData.totalTime) || 0,
            targetScore: parseInt(formData.targetScore) || 0,
            reviewNote: formData.reviewNote, linkedErrorIds: []
          });
          isEdit = true;
        } else {
          await App.DB.updateExam({
            id: formData.id, name: formData.name, examDate: formData.examDate,
            subjectScores: formData.subjectScores,
            totalAccuracy: parseInt(formData.totalAccuracy) || 0,
            totalTime: parseInt(formData.totalTime) || 0,
            targetScore: parseInt(formData.targetScore) || 0,
            reviewNote: formData.reviewNote, linkedErrorIds: formData.linkedErrorIds
          });
        }
      }
    };

    const submitForm = async () => {
      clearTimeout(_examSaveTimer);
      if (formData._getNote) formData.reviewNote = formData._getNote();
      if (!formData.name.trim()) { App.Components.toast('请输入套卷名称', 'error'); return; }
      try {
        await submitFormInternal();
        App.Components.toast('已保存 ✓', 'success');
        App.Draft.clearForm('exam');
        App.Router.navigate('exams');
      } catch (e) { App.Components.toast('保存失败', 'error'); }
    };

    loadAndRender();
  }
};
