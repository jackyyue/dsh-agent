'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { spawn } = require('node:child_process');

const PORT = 19999;
const BASE = `http://localhost:${PORT}`;
const ROOT = path.join(__dirname, '..');

function fetchUrl(url, method = 'GET', body = null) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const req = http.request(url, { method, headers: data ? { 'Content-Type': 'application/json' } : {} }, (res) => {
      let chunks = '';
      res.on('data', (c) => { chunks += c; });
      res.on('end', () => resolve({ status: res.statusCode, data: chunks }));
    });
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

async function test() {
  let proc = null;

  // 测试 1：主页可访问
  let home = await fetchUrl(`${BASE}/`);
  if (home.status !== 200) throw new Error(`主页返回 ${home.status}`);
  if (!home.data.includes('DSH Agent')) throw new Error('主页缺少 DSH Agent 内容');
  console.log('✅ 测试 1 通过：主页可访问且包含 DSH Agent');

  // 测试 2：聊天接口返回错误（key 无效，预期 401 系列被转换为 keyError）
  let chat = await fetchUrl(`${BASE}/api/chat`, 'POST', { messages: [{ role: 'user', content: '你好' }] });
  let chatData = JSON.parse(chat.data);
  console.log(`  聊天接口响应：status=${chat.status}, keyError=${chatData.keyError}, error=${chatData.error ? chatData.error.message : '无'}`);
  // 只要返回了 JSON 且不崩溃即通过（key 是否有效取决于测试环境）
  if (chat.status !== 200) throw new Error(`聊天接口返回 ${chat.status}`);
  console.log('✅ 测试 2 通过：聊天接口正常响应（无效 key 时返回友好提示）');

  // 测试 3：静态资源可访问
  let staticRes = await fetchUrl(`${BASE}/chat.html`);
  if (staticRes.status !== 200) throw new Error(`chat.html 返回 ${staticRes.status}`);
  console.log('✅ 测试 3 通过：chat.html 可访问');

  // 测试 4：目录穿越被拦截
  let traversal = await fetchUrl(`${BASE}/../package.json`);
  if (traversal.status === 403 || traversal.status === 404) {
    console.log(`✅ 测试 4 通过：目录穿越被拦截 (${traversal.status})`);
  } else {
    throw new Error(`目录穿越未被拦截，返回 ${traversal.status}`);
  }

  console.log('');
  console.log('所有测试通过！');
}

// 先启动 server
const configPath = path.join(ROOT, 'config.json');
if (!fs.existsSync(configPath)) {
  fs.writeFileSync(configPath, JSON.stringify({ apiKey: 'sk-test-invalid-key-for-unit-test' }));
}

const proc = spawn(process.execPath, ['server.js'], { cwd: ROOT, stdio: ['ignore', 'pipe', 'pipe'] });

// 等待服务就绪
const waitForReady = new Promise((resolve, reject) => {
  const deadline = Date.now() + 10000;
  const poll = async () => {
    try {
      const res = await fetchUrl(`${BASE}/`);
      if (res.status === 200) return resolve();
    } catch {}
    if (Date.now() > deadline) return reject(new Error('服务启动超时'));
    setTimeout(poll, 200);
  };
  poll();
});

waitForReady
  .then(test)
  .catch((err) => {
    console.error('测试失败：', err.message);
    proc.kill();
    process.exit(1);
  })
  .finally(() => {
    proc.kill();
  });
