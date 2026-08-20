// ===== 考公笔试复盘系统 - 云端存储后端 =====
// 应用入口只负责组装基础设施、静态托管和 API 路由；
// 配置、数据库、认证、静态保护和业务路由分别位于 server/ 下的模块。
require('dotenv').config();
const path = require('path');
const express = require('express');
const cors = require('cors');
const {
  PORT,
  CORS_ORIGIN,
  WORKSPACE
} = require('./config');
const apiRouter = require('./routes');
const { createStaticGuard, createStaticFallback } = require('./static-files');

const app = express();
const corsOrigins = CORS_ORIGIN === '*'
  ? true
  : CORS_ORIGIN.split(',').map(origin => origin.trim()).filter(Boolean);

app.use(cors({ origin: corsOrigins, credentials: true }));
app.use(express.json({ limit: '8mb' }));
app.use(createStaticGuard());
app.use(createStaticFallback(express, WORKSPACE));
app.use('/api', apiRouter);

// 兜底：SPA 直接返回首页（避免刷新 404）
app.get('/', (req, res) => {
  res.sendFile(path.join(WORKSPACE, 'index.html'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('[kaogong-cloud-api] listening on :' + PORT + '  CORS=' + CORS_ORIGIN + '  static=' + WORKSPACE);
});

module.exports = app;
