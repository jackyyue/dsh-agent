'use strict';
// 验证 qrcode.min.js 库在 Node 环境下能生成二维码（与 chat.html 相同用法）
const fs = require('fs');
const vm = require('vm');
const path = require('path');

const file = path.join(__dirname, '..', 'qrcode.min.js');
const code = fs.readFileSync(file, 'utf8');

// qrcode.min.js 是 UMD 包装：支持 AMD / CommonJS / 全局。用 CommonJS 沙箱加载
const sandbox = {
  module: { exports: {} },
  exports: {},
  console,
};
vm.createContext(sandbox);
vm.runInContext(code, sandbox);

let qrcode = sandbox.module.exports || sandbox.exports;
if (typeof qrcode !== 'function') {
  // UMD 判定失败时的兜底：直接用字符串截取全局 qrcode
  const code2 = code.replace(/typeof define === "function" && define\.amd/, 'false');
  const sandbox2 = { module: { exports: {} }, exports: {}, console };
  vm.createContext(sandbox2);
  vm.runInContext(code2, sandbox2);
  qrcode = sandbox2.module.exports || sandbox2.exports;
}

if (typeof qrcode !== 'function') {
  console.error('❌ 无法从 UMD 加载 qrcode 库');
  process.exit(1);
}
console.log('✅ 库加载成功 (qrcode 类型: ' + typeof qrcode + ')');

// 与 chat.html 完全相同的调用
const qr = qrcode(0, 'M');
qr.addData('https://dsh-agent.com');
qr.make();
const dataUrl = qr.createDataURL(4, 8);

if (!dataUrl.startsWith('data:image/gif;base64,')) {
  console.error('❌ 二维码 dataURL 前缀异常: ' + dataUrl.slice(0, 40));
  process.exit(1);
}
console.log('✅ 二维码生成成功 (dataURL 长度: ' + dataUrl.length + ')');
console.log('✅ 二维码模块数: ' + qr.getModuleCount() + 'x' + qr.getModuleCount());
console.log('二维码前 60 字符: ' + dataUrl.slice(0, 60) + '...');
console.log('全部通过');
