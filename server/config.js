const path = require('path');

const PORT = parseInt(process.env.PORT || '3000', 10);
const JWT_SECRET = process.env.JWT_SECRET || 'CHANGE_ME_TO_A_LONG_RANDOM_STRING';
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';
const DB_PATH = process.env.DB_PATH || path.join(__dirname, 'data.sqlite');
const WORKSPACE = path.join(__dirname, '..');

const ALLOWED = new Set(['errors', 'notes', 'exams', 'todos', 'subject_reviews', 'words']);
const RESERVED = new Set(['auth', 'health', 'export', 'import', 'keyvalue']);

function genId(prefix) {
  return prefix + '_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
}

module.exports = {
  PORT,
  JWT_SECRET,
  CORS_ORIGIN,
  DB_PATH,
  WORKSPACE,
  ALLOWED,
  RESERVED,
  genId
};
