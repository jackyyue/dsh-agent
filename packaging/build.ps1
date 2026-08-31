Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$bootstrapDir = Join-Path $root 'bootstrap-agent'
$nodeDir = Join-Path $root 'packaging\node-portable'
$outputDir = Join-Path $root 'dist'
$outputExe = Join-Path $outputDir 'dsh-agent-installer.exe'

# 1. 准备输出目录
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# 2. 准备便携 Node.js
$nodeZip = Join-Path $root 'packaging\node-v22.22.0-win-x64.zip'
if (-not (Test-Path $nodeZip)) {
    Write-Host "下载便携 Node.js..."
    Invoke-WebRequest -Uri 'https://nodejs.org/dist/v22.22.0/node-v22.22.0-win-x64.zip' -OutFile $nodeZip
}
if (-not (Test-Path $nodeDir)) {
    Expand-Archive -Path $nodeZip -DestinationPath $nodeDir
}

# 3. 创建临时打包目录
$tempDir = Join-Path $env:TEMP "dsh-agent-installer-build"
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# 4. 复制文件（便携 Node 只需 node.exe 和 core 必要文件）
Write-Host "复制 Node.js 运行时..."
Copy-Item -Recurse "$nodeDir\*" "$tempDir\node\" -Force
Write-Host "复制引导 Agent..."
Copy-Item -Recurse "$bootstrapDir\*" "$tempDir\agent\" -Force
# config.json 由下载页在运行时覆盖，默认放一个空配置
'{"apiKey":""}' | Out-File -FilePath "$tempDir\agent\config.json" -Encoding utf8

# 5. 创建 start.vbs（隐藏窗口启动 Node.js）
# 注意：VBScript 中 %~dp0 不可用，使用 WScript.ScriptFullName 推导路径
$startVbs = @"
Set WshShell = CreateObject("WScript.Shell")
Dim base
base = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
WshShell.Run Chr(34) & base & "node\node.exe" & Chr(34) & " " & Chr(34) & base & "agent\server.js" & Chr(34), 0, False
"@
$startVbs | Out-File -FilePath "$tempDir\start.vbs" -Encoding ascii

# 5.1 复制 uninstall.bat 到安装根目录（与 start.vbs 同级，用户可双击卸载）
Copy-Item -Path (Join-Path $PSScriptRoot 'uninstall.bat') -Destination "$tempDir\uninstall.bat" -Force

# 6. 打包为 7-Zip SFX
$sevenZip = "C:\Program Files\7-Zip\7z.exe"
if (-not (Test-Path $sevenZip)) {
    $sevenZip = "C:\Program Files (x86)\7-Zip\7z.exe"
}
if (-not (Test-Path $sevenZip)) {
    throw "7-Zip not found. Install from https://www.7-zip.org/"
}

# 先打包为 7z
Write-Host "打包为 7z..."
$archive = Join-Path $outputDir 'dsh-agent-installer.7z'
& $sevenZip a -mx9 $archive "$tempDir\*" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7-Zip 打包失败 (exit $LASTEXITCODE)" }

# 生成 SFX
$sfxModule = Join-Path $env:ProgramFiles '7-Zip\7z.sfx'
if (-not (Test-Path $sfxModule)) {
    $sfxModule = Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.sfx'
}
$sfxConfig = Join-Path $PSScriptRoot 'sfx-config.txt'

Write-Host "生成自解压 exe..."
cmd /c "copy /b `"$sfxModule`" + `"$sfxConfig`" + `"$archive`" `"$outputExe`""
if ($LASTEXITCODE -ne 0) { throw "SFX 生成失败" }

# 7. 清理
Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
Remove-Item $archive -ErrorAction SilentlyContinue

$sizeMB = [math]::Round((Get-Item $outputExe).Length / 1MB, 1)
Write-Host ""
Write-Host "构建完成：$outputExe"
Write-Host "大小：$sizeMB MB"
if ($sizeMB -gt 50) {
    Write-Host "⚠️  超过 50 MB，需优化！"
} else {
    Write-Host "✅ 符合 < 50 MB 要求"
}
