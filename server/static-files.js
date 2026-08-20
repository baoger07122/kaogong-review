function createStaticGuard() {
  return (req, res, next) => {
    const urlPath = req.path.toLowerCase();
    if (
      urlPath.startsWith('/server') ||
      urlPath.startsWith('/.git') ||
      urlPath.startsWith('/node_modules') ||
      urlPath === '/src' || urlPath.startsWith('/src/') ||
      urlPath === '/docs' || urlPath.startsWith('/docs/') ||
      urlPath.startsWith('/test_') || urlPath.startsWith('/_') ||
      urlPath === '/build.js' || urlPath === '/package.json' || urlPath.startsWith('/package-lock') ||
      urlPath === '/render.yaml' ||
      urlPath.includes('.env') ||
      urlPath.endsWith('/server/')
    ) return res.status(404).end();
    next();
  };
}

function createStaticFallback(express, workspace) {
  return express.static(workspace, { index: 'index.html' });
}

module.exports = { createStaticGuard, createStaticFallback };
