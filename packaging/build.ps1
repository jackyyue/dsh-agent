# build.ps1 — 构建"预打包 DSH"单文件分发 exe（阶段 2.6，pkg --sea 正式路线）
# 输入：packaging/prepack/（node_modules 完整依赖 + dsh-home-template 初始模板 + web-entry.mjs）
# 输出：dist/dsh-agent.exe（单文件，VFS 内直接跑，零解压）
#
# 架构（2026-09-01 定案）：
#   - 单文件 exe = 完整 DSH 内核（node_modules 进 VFS，只读）+ dsh-home 初始模板
#   - DSH_HOME 外部可写：默认 %LOCALAPPDATA%\DSH-Agent\home（首次运行从 VFS 模板复制）
#   - 首次运行：装机 Agent（默认 preset=install）引导收 key / 选目录 / 自检
#   - 根治 SFX 时代的两个坑：3 万小文件解压（Defender 卡死）、vbs→ps1→node 长启动链
#
# 参考官方：deepseek-harness/scripts/build-exe-for-python-sdk.ts（pkg --sea 路线）
# 构建仅在本机执行打包动作；解压/安装/装机测试一律在 VM 进行（2026-09-01 规则）

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$prepackDir = Join-Path $root 'packaging\prepack'
$outputDir = Join-Path $root 'dist'
$outputExe = Join-Path $outputDir 'dsh-agent.exe'
$pkgSpec = '@yao-pkg/pkg@6.21.0'
$target = 'node22-win-x64'

# 前置检查
if (-not (Test-Path (Join-Path $prepackDir 'node_modules\@deepseek-ai\dsh'))) { throw "prepack 缺少 DSH 内核: $prepackDir" }
if (-not (Test-Path (Join-Path $prepackDir 'web-entry.mjs'))) { throw "prepack 缺少入口 web-entry.mjs" }
if (-not (Test-Path (Join-Path $prepackDir 'dsh-home-template\agent-presets-staging\install\agent.cordis.yml'))) { throw "prepack 缺少装机 preset 模板（agent-presets-staging）" }

Write-Host '===== DSH Agent 单文件构建（pkg --sea）====='
Write-Host "目标: $target"

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# 1. 校验模板（必须排除 junction 与运行残留）
$stray = Get-ChildItem (Join-Path $prepackDir 'dsh-home-template') -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.LinkType -or $_.Attributes -match 'ReparsePoint' }
if ($stray) { throw "dsh-home-template 含符号链接/junction，禁止打包: $($stray.FullName -join ', ')" }
if (Test-Path (Join-Path $prepackDir 'dsh-home-template\storages')) { throw "dsh-home-template 不应含 storages 运行残留" }

# 2. pkg --sea 打包（走本地代理；pnpm dlx 拉 pkg 缓存后复用）
Write-Host '[1/1] 运行 pkg --sea...'
$env:HTTP_PROXY = 'http://127.0.0.1:18001'
$env:HTTPS_PROXY = 'http://127.0.0.1:18001'
$env:NO_PROXY = 'localhost,127.0.0.1'
Push-Location $prepackDir
try {
    & pnpm dlx $pkgSpec . --sea --targets $target --output $outputExe 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "pkg --sea 打包失败 (exit $LASTEXITCODE)" }
} finally {
    Pop-Location
}

if (-not (Test-Path $outputExe)) { throw "产物缺失: $outputExe" }

$sizeMB = [math]::Round((Get-Item $outputExe).Length / 1MB, 1)
Write-Host ""
Write-Host "构建完成：$outputExe"
Write-Host "大小：$sizeMB MB（单文件，免解压）"
Write-Host "提示：本机只构建不运行；首次运行/装机测试在 VM 进行"