# DSH Agent

开箱即用的 AI Agent 分发渠道：让用户**扫码 → 注册 → 下载 → 双击 → 对话**，零术语、零命令行、零配置。

## 这是什么

DSH Agent 是一个「引导 Agent」：一个极小的自解压程序，双击后自动启动本地对话服务，浏览器即开即聊。它负责把零基础用户领进 AI Agent 世界，后续可后台升级为完整版 Agent。

- **引导 Agent**：`bootstrap-agent/`（Node.js v22，仅内置模块，零依赖）
- **下载页**：`download-page/`（静态 HTML，可部署到 GitHub Pages / 任意静态托管）
- **打包**：`packaging/build.ps1`（7-Zip SFX 自解压，产物 < 50MB）

## 快速开始

### 构建安装包

```powershell
# 1. 安装 7-Zip（https://www.7-zip.org/）
# 2. 运行打包脚本
pwsh packaging/build.ps1
# 产物：dist/dsh-agent-installer.exe（约 21.5MB）
```

### 本地运行引导 Agent

```powershell
# 准备配置（key 由下载页引导用户注册 DeepSeek 获取）
# {"apiKey":"sk-...","createdAt":"..."} → bootstrap-agent/config.json

cd bootstrap-agent
node server.js
# 浏览器自动打开 http://localhost:19999
```

### 运行测试

```powershell
node bootstrap-agent/test/server.test.js
```

## 使用流程

```
用户扫码 → 打开下载页 → 引导注册 DeepSeek 拿 key
→ 粘贴 key → 下载 exe（21.5MB）→ 双击 → 浏览器对话
```

## 技术栈

- Node.js v22（仅内置模块，零 npm 依赖）
- 原生 HTML/CSS/JS（无框架）
- 7-Zip SFX 自解压
- DeepSeek API

## 开源协议

[MIT](LICENSE)

> 本仓库只包含可开源的产品代码。下载页/市场运营等自运营资产不在此仓库内。
