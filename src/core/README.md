# 基础层

基础层按依赖顺序由 build.js 拼接：

1. 00-constants.js：科目、模块、考点和应用版本。
2. 01-utils.js：文本、Markdown、公式、日期、主题和通用交互工具。
3. 10-database.js：IndexedDB 初始化、通用读写和领域数据接口。
4. 20-tags.js：考点、错因标签库及历史数据迁移。
5. 30-cloud.js：登录、云端同步队列和数据库写入监听。
6. 40-draft.js：页面草稿和表单草稿。
7. 50-router.js：路由、启动初始化和全局事件。

页面代码依赖这些模块公开的 App.Constants、App.Utils、App.DB、
App.Tags、App.Cloud、App.Draft 和 App.Router 接口。重构基础层时优先
保持这些接口兼容，避免把页面逻辑重新耦合回基础层。
