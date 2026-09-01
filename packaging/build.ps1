# build.ps1 — 构建"预打包 DSH"分发 exe（阶段 2.5）
# 输入：packaging/prepack/（node_modules + dsh-home，含装机 preset）
# 输出：dist/dsh-agent-installer.exe（7-Zip SFX 自解压）
#
# 打包结构（解压后）：
#   <安装目录>/
#     node/node.exe              ← 便携 Node 运行时（单文件）
#     app/                       ← DSH 内核
#       node_modules/            ← 完整依赖（已 npm 装好）
#       dsh-home/                ← 隔离 DSH_HOME（profiles + 装机 preset）
#     start-agent.ps1            ← 启动器（探测端口 → 用 DSH_HOME 拉起 dsh web）
#     start.vbs                  ← 隐藏窗口调用 start-agent.ps1
#     uninstall.bat              ← 卸载
#
# 关键点：
# 1. dsh-home/profiles/node_modules 是 junction 且指向本机构建机路径，
#    打包时 EXCLUDE——用户机器首次启动时 DSH 自动 heal 重建（已验证）。
# 2. 装机 preset 已随 dsh-home/.agent-presets/install 进包，web profile 的
#    cordis.patch.yml 已把默认 preset 设为 install。
# 3. 本脚本仅构建，不运行安装；安装/装机测试一律在 VM 执行。

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$prepackDir = Join-Path $root 'packaging\prepack'
$nodeExe = Join-Path $root 'packaging\node-portable\node-v22.22.0-win-x64\node.exe'
$outputDir = Join-Path $root 'dist'
$outputExe = Join-Path $outputDir 'dsh-agent-installer.exe'
$tempDir = Join-Path $env:TEMP "dsh-agent-installer-build"

# 前置检查
if (-not (Test-Path (Join-Path $prepackDir 'node_modules\@deepseek-ai\dsh'))) { throw "prepack 缺少 DSH 内核: $prepackDir" }
if (-not (Test-Path (Join-Path $prepackDir 'dsh-home\.agent-presets\install\agent.cordis.yml'))) { throw "prepack 缺少装机 preset" }
if (-not (Test-Path $nodeExe)) { throw "便携 Node 缺失: $nodeExe" }

Write-Host '===== DSH Agent 预打包构建 ====='
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# 1. 便携 Node（单文件）
Write-Host '[1/5] 复制便携 Node...'
New-Item -ItemType Directory -Path "$tempDir\node" -Force | Out-Null
Copy-Item $nodeExe "$tempDir\node\node.exe" -Force

# 2. DSH 内核
Write-Host '[2/5] 复制 DSH 内核（node_modules + dsh-home，排除 junction 与运行残留）...'
New-Item -ItemType Directory -Path "$tempDir\app" -Force | Out-Null
# node_modules 全量（real files）
robocopy "$prepackDir\node_modules" "$tempDir\app\node_modules" /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy node_modules 失败 (exit $LASTEXITCODE)" }
# dsh-home：排除 profiles/node_modules（junction，指向构建机路径；目标机自愈重建）
#          排除 storages（运行残留 workspace.json；首次启动重建）
robocopy "$prepackDir\dsh-home" "$tempDir\app\dsh-home" /E /XD "$prepackDir\dsh-home\profiles\node_modules" "$prepackDir\dsh-home\storages" /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy dsh-home 失败 (exit $LASTEXITCODE)" }

# 3. 启动器
Write-Host '[3/5] 生成启动器...'
$startAgent = @'
# start-agent.ps1 — 启动 DSH Web（预打包版）
# 1) 探测可用端口（3080 优先，被占用则顺延）
# 2) 设置 DSH_HOME 指向 <安装目录>\app\dsh-home
# 3) 用便携 node 拉起 dsh web，日志写入 startup.log
$ErrorActionPreference = 'Continue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$node  = Join-Path $base 'node\node.exe'
$bin   = Join-Path $base 'app\node_modules\@deepseek-ai\dsh\lib\bin.js'
$home  = Join-Path $base 'app\dsh-home'
$log   = Join-Path $base 'startup.log'

$env:DSH_HOME = $home
$env:DSH_TELEMETRY_DISABLED = '1'

# 找空闲端口：从 3080 开始顺延
$port = 3080
for ($attempt = 0; $attempt -lt 10; $attempt++) {
    $busy = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if (-not $busy) { break }
    $port++
}
if ($attempt -ge 10) { $port = 3080 }

# 日志头
"$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') start dsh web on port $port" | Out-File $log -Encoding utf8

# 启动 dsh web（隐藏窗口，不待其退出）
$args = @($bin, 'web', '--port', "$port", '--no-open')
$p = Start-Process -FilePath $node -ArgumentList $args -WorkingDirectory $base -WindowStyle Hidden -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err" -PassThru
"pid=$($p.Id)" | Out-File $log -Append -Encoding utf8

# 等待端口就绪后打开浏览器（最多 30 秒）
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 1
    $ready = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    if ($ready) { break }
}
Start-Sleep -Seconds 2
if (Test-Path "$log.err") {
    $err = Get-Content "$log.err" -Raw -ErrorAction SilentlyContinue
    if ($err -match 'EADDRINUSE|listen') { "real-port-busy=1" | Out-File $log -Append -Encoding utf8 }
}
# 打开浏览器指向 Web UI
Start-Process "http://127.0.0.1:$port"
'@
$startAgent | Out-File "$tempDir\start-agent.ps1" -Encoding utf8

# start.vbs：隐藏窗口调用 start-agent.ps1（无控制台闪烁）
$startVbs = @'
Set WshShell = CreateObject("WScript.Shell")
base = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & base & "start-agent.ps1"""
WshShell.Run cmd, 0, False
'@
$startVbs | Out-File "$tempDir\start.vbs" -Encoding ascii

# 4. 卸载器（端口改为 DSH web 段：3080-3089）
Write-Host '[4/5] 复制卸载器...'
$uninstall = Get-Content (Join-Path $PSScriptRoot 'uninstall.bat') -Raw
$uninstall = $uninstall -replace 'port 19999\)', 'port 3080-3089)' -replace 'findstr :19999', 'findstr /r ":308[0-9]"'
$uninstall | Out-File "$tempDir\uninstall.bat" -Encoding ascii

# 5. 打包 7-Zip SFX
Write-Host '[5/5] 打包 7-Zip SFX...'
$sevenZip = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $sevenZip)) { $sevenZip = "C:\Program Files (x86)\7-Zip\7z.exe" }
if (-not (Test-Path $sevenZip)) { throw "7-Zip not found" }

$archive = Join-Path $outputDir 'dsh-agent-installer.7z'
& $sevenZip a -mx9 -bso0 -bsp0 $archive "$tempDir\*"
if ($LASTEXITCODE -ne 0) { throw "7-Zip 打包失败 (exit $LASTEXITCODE)" }

$sfxModule = Join-Path $env:ProgramFiles '7-Zip\7z.sfx'
if (-not (Test-Path $sfxModule)) { $sfxModule = Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.sfx' }
$sfxConfig = Join-Path $PSScriptRoot 'sfx-config.txt'
cmd /c "copy /b `"$sfxModule`" + `"$sfxConfig`" + `"$archive`" `"$outputExe`"" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "SFX 生成失败" }

# 清理
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
Remove-Item $archive -ErrorAction SilentlyContinue

$sizeMB = [math]::Round((Get-Item $outputExe).Length / 1MB, 1)
Write-Host ""
Write-Host "构建完成：$outputExe"
Write-Host "大小：$sizeMB MB"
Write-Host "（注：预打包方案以体积换零风险，50MB 上限已不适用）"