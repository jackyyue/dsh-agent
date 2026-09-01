# DSH Agent Key 获取流程重设计 — 实施完成报告

> 完成日期：2026-09-01  
> 实施计划：`docs/superpowers/plans/2026-09-01-dsh-agent-key-flow-redesign.md`  
> 执行方式：doplan（`C:\Users\jack_\.codex\skills\doplan\SKILL.md`）

## 实施内容

### 1. 网站简化 ✅

- 移除多步引导（准备 Key → 下载 → 使用 的三步向导）
- 简化为单页下载入口（标题 + 三要点 + 一个下载按钮 + 系统要求/提示）
- 备份：`download-page/index-old.html`、`download-page/index.html.backup`
- 文件：`download-page/index.html`（4064 bytes），无头 Chrome 渲染确认布局正常、下载链接指向 GitHub Release

### 2. DSH Agent 首屏表单 ✅

- 实现 Key 粘贴表单界面（非聊天窗）
- 包含「打开 DeepSeek 注册页」按钮（新标签页打开、当前页不关）和 Key 密码输入框
- 文件：
  - `packaging/prepack/dsh-home-template/agent-presets-staging/install/web-ui/key-form.html`
  - `packaging/prepack/dsh-home-template/agent-presets-staging/install/web-ui/key-form.css`
  - `packaging/prepack/dsh-home-template/agent-presets-staging/install/web-ui/key-form.js`
- 无头渲染确认表单布局正确

### 3. Key 验证后端 ✅

- 实现 `/api/setup/validate-key` 接口（真实挂载机制，见下方"适配说明"）
- 前端格式校验 + 后端真实 DeepSeek API 最小请求验证
- 验证成功后保存凭据（`credentials.set('DEEPSEEK_API_KEY', key)`，不写明文）
- 文件：`skills/install-agent/api/validate-key.js` + 单元测试 `validate-key.test.js`（6/6 通过）

### 4. 启动路由分流 ✅

- 首次运行（无 `.setup-done` 且无凭据）→ 首页返回 Key 表单
- 已有凭据/已完成 → 渲染 DSH 正常聊天界面
- 文件：
  - `skills/install-agent/check-first-run.js`（首次运行标记检测）
  - `skills/install-agent/index-handler.js`（首页分流）
  - `skills/install-agent/install-web.js`（路由挂载插件）
  - `profiles/web/cordis.yml`（host 组合挂载 install-web 条目）
- SKILL.md 增加「启动流程」章节（首次运行表单 vs 修复模式）

### 5. 用户文档 ✅

- 编写设置指南：`docs/user-guide-key-setup.md`
- README.md 增加「快速开始」段并链接指南

### 6. 打包配置 ✅

- `packaging/prepack/package.json` pkg.assets 显式加入 `web-ui/*`、`web-ui/**/*`、`install-agent/api/*`

### 7. 集成测试 ✅

- 自动化测试脚本：`packaging/test-key-flow.ps1`，本机实跑通过（网站 ✅ 首屏表单 ✅ 资源 ✅ 格式校验 ✅）

## 适配说明（计划文本 vs DSH 真实机制）

计划任务 4/5 把 web 路由（`port/routes/indexHandler`）直接写进 `agent.cordis.yml`，**该写法与 DSH 架构不符**（实测依据）：

1. `agent.cordis.yml` 是 agent-plane（组装工具/提示词），**不承载 web 路由**；web 由 host 组合（`profiles/web/cordis.yml`）提供。
2. `@deepseek-ai/dsh-web-app` 的配置 schema 只有 `openBrowser/printUrl/surfaceContext/trustedHosts`，**没有** `routes`/`indexHandler` 字段。
3. DSH 真实路由机制：插件通过 `ctx.webServer.register({kind, path, handler})` 注册，fallback 座位（SPA）唯一。

**适配结果（保留计划全部产物、挂载方式真实化）**：
- 新增 `install-web` 插件（exact `/` 分流 + `/api/setup/validate-key` + prefix `/ui/` 静态资源），由 host 组合挂载。
- 端口沿用 web 组合现有机制（`--port` 可覆盖）；装机助手独立端口 3081 属"独立程序"架构的下一里程碑，本次在其 web 能力内落地 Key 流程。

## 验收结果（本机隔离）

| 验收项 | 状态 | 证据 |
|---|---|---|
| 网站简化为单页下载 | ✓ | `download-page/index.html` + 无头渲染截图 + 集成测试 [2/6] |
| DSH Agent 首屏显示 Key 表单 | ✓ | 集成测试 [4/6]（`input-api-key`/`btn-open-deepseek` 命中） |
| 表单静态资源可访问 | ✓ | 集成测试 [4b/6] css/js 200 |
| 前端格式校验生效 | ✓ | 集成测试 [5/6]（invalid-key 被拒） |
| 后端验证 API 单元测试 | ✓ | `validate-key.test.js` 6/6 |
| Key 验证成功后切换聊天 | ⊘ 未测（需真实 Key） | 设 `DEEPSEEK_API_KEY_TEST` 后重跑集成测试可覆盖 |
| 用户文档完整 | ✓ | `docs/user-guide-key-setup.md` |
| 集成测试脚本可运行 | ✓ | 本机实跑通过 |

## 变更影响

### 用户侧
- **优点**：下载页一步到位；软件首屏自己引导拿 Key，全程不离开软件
- **缺点**：无（体验优化）

### 开发侧
- **新增文件（10）**：
  - `download-page/index-v2.html`（已并入 index.html）
  - `docs/ui-spec-dsh-agent-key-form.md`
  - `docs/user-guide-key-setup.md`
  - `install/web-ui/key-form.{html,css,js}`
  - `install/skills/install-agent/api/validate-key.js` + `.test.js`
  - `install/skills/install-agent/check-first-run.js`
  - `install/skills/install-agent/index-handler.js`
  - `install/skills/install-agent/install-web.js`
  - `packaging/test-key-flow.ps1`
- **修改文件（5）**：`download-page/index.html`、`agent.cordis.yml` 不动、`profiles/web/cordis.yml`、`SKILL.md`、`packaging/prepack/package.json`、`README.md`

## 已知问题（诚实标注）

1. **未测试项**：真实 DeepSeek API 的 Key 验证（集成测试 SKIP）；Key 验证成功后的"切聊天"路径需真实 Key 覆盖。
2. **README 旧正文未重写**：README 仍保留旧的"引导 Agent / SFX 21.5MB"叙述（doplan 规则：不做计划外改动）；快速开始段已指向新指南。
3. **装机助手独立程序（3081 + 桌面快捷方式）** 属"正确理解"文档里的下一架构里程碑，本次只在其 web 能力内落地 Key 流程，未拆分独立进程。

## 部署检查清单

- [x] pkg 打包配置包含 web-ui 资源
- [x] 本机全新 DSH_HOME 验证通过（首屏表单/静态资源/格式校验）
- [ ] VM 全新系统测试通过（需真实 Key，走 `test-key-flow.ps1 -TestKey <key>` 或人工闭环）
- [ ] 更新 GitHub Release 说明（新 exe 重新打包发布）
- [ ] 更新 dsh-agent.com 网站（新 index.html 已就绪，需 git push）