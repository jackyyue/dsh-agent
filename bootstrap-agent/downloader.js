'use strict';

const https = require('node:https');
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

// TODO: 完整版 Agent 选型后替换为真实下载地址
const FULL_AGENT_URL = 'https://example.com/dg-full-agent.exe';
const DOWNLOAD_DIR = path.join(__dirname, '..', 'full-agent');

function download(url, destPath, onProgress) {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https:') ? https : http;

    const req = protocol.get(url, (response) => {
      // 处理重定向（支持相对地址）
      if (response.statusCode === 301 || response.statusCode === 302 || response.statusCode === 307) {
        if (response.headers.location) {
          response.resume(); // 释放连接
          const next = new URL(response.headers.location, url).href;
          return download(next, destPath, onProgress)
            .then(resolve)
            .catch(reject);
        }
        return reject(new Error(`重定向缺少 Location 头 (HTTP ${response.statusCode})`));
      }

      if (response.statusCode !== 200) {
        response.resume();
        return reject(new Error(`HTTP ${response.statusCode}`));
      }

      const total = parseInt(response.headers['content-length'], 10) || 0;
      let downloaded = 0;

      const file = fs.createWriteStream(destPath);
      response.pipe(file);

      response.on('data', (chunk) => {
        downloaded += chunk.length;
        if (onProgress) {
          const percent = total ? Math.round((downloaded / total) * 100) : 0;
          onProgress({ downloaded, total, percent });
        }
      });

      file.on('finish', () => {
        file.close(() => resolve(destPath));
      });

      file.on('error', (err) => {
        fs.unlink(destPath, () => {});
        reject(err);
      });
    });

    req.on('error', (err) => {
      fs.unlink(destPath, () => {});
      reject(err);
    });

    req.setTimeout(30000, () => {
      req.destroy(new Error('请求超时'));
    });
  });
}

module.exports = { download, FULL_AGENT_URL, DOWNLOAD_DIR };
