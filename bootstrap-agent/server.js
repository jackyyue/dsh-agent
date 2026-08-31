'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { exec } = require('node:child_process');
const os = require('node:os');

const PORT = 19999;
const ROOT = __dirname;

// 读取 config.json
let config = null;
try {
  const configText = fs.readFileSync(path.join(ROOT, 'config.json'), 'utf-8').replace(/^\uFEFF/, '');
  config = JSON.parse(configText);
} catch {
  console.error('config.json 不存在或格式无效，请先通过下载页获取配置文件');
  process.exit(1);
}

if (!config.apiKey || typeof config.apiKey !== 'string' || config.apiKey.length === 0) {
  console.error('config.json 缺少 apiKey，请重新配置');
  process.exit(1);
}

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
};

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);

  // API: chat proxy
  if (url.pathname === '/api/chat' && req.method === 'POST') {
    return handleChat(req, res);
  }

  // API: 下载完整版（由 chat.html 触发）
  if (url.pathname === '/api/download' && req.method === 'POST') {
    return handleDownload(req, res);
  }

  // Static files（防目录穿越）
  let filePath = url.pathname === '/' ? '/chat.html' : url.pathname;
  filePath = path.normalize(path.join(ROOT, filePath));
  if (!filePath.startsWith(ROOT)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  const ext = path.extname(filePath);
  const contentType = MIME[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not Found');
      return;
    }
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(data);
  });
});

function handleChat(req, res) {
  let body = '';
  req.on('data', (chunk) => { body += chunk; });
  req.on('end', async () => {
    try {
      const { messages } = JSON.parse(body);
      if (!Array.isArray(messages) || messages.length === 0) {
        res.writeHead(400);
        res.end(JSON.stringify({ error: { message: '消息不能为空' } }));
        return;
      }

      const upstream = await fetch('https://api.deepseek.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${config.apiKey}`,
        },
        body: JSON.stringify({
          model: 'deepseek-chat',
          messages,
          stream: false,
        }),
      });

      const data = await upstream.json();

      // 401/402/403 = key 无效或余额不足，返回友好提示
      if (upstream.status === 401 || upstream.status === 403) {
        res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
        res.end(JSON.stringify({ keyError: true, error: { message: 'API key 无效，请重新配置后重启' } }));
        return;
      }

      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify(data));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: { message: `网络错误：${err.message}` } }));
    }
  });
}

function handleDownload(req, res) {
  const { download } = require('./downloader');
  const FULL_AGENT_URL = 'https://example.com/dg-full-agent.exe'; // TODO: 完整版 Agent 选型后替换
  const destPath = path.join(__dirname, '..', 'full-agent', 'dg-full-agent.exe');

  download(FULL_AGENT_URL, destPath, (p) => {
    // 进度回传（当前为占位 URL，实际下载后这里可推送给前端）
    console.log(`下载进度：${p.percent}%`);
  })
    .then(() => {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: true, message: '下载完成' }));
    })
    .catch((err) => {
      res.writeHead(500, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ ok: false, error: err.message }));
    });
}

// 打开浏览器（跨平台兼容）
function openBrowser(url) {
  const platform = os.platform();
  let command;
  if (platform === 'win32') {
    command = `cmd /c start "" "${url}"`;
  } else if (platform === 'darwin') {
    command = `open "${url}"`;
  } else {
    command = `xdg-open "${url}"`;
  }
  exec(command, (err) => {
    if (err) {
      console.log(`请手动打开浏览器访问：${url}`);
    }
  });
}

server.listen(PORT, () => {
  console.log(`Bootstrap agent running at http://localhost:${PORT}`);
  // 延迟 300ms 再开浏览器，确保服务已就绪
  setTimeout(() => openBrowser(`http://localhost:${PORT}`), 300);
});

// 端口被占用 = 已有实例在运行，直接打开浏览器即可，不崩溃
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.log(`端口 ${PORT} 已被占用，DSH Agent 可能已在运行，直接打开浏览器`);
    openBrowser(`http://localhost:${PORT}`);
    process.exit(0);
  }
  throw err;
});
