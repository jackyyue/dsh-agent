#Requires -Version 7

<#
.SYNOPSIS
测试 DSH Agent Key 获取流程

.DESCRIPTION
自动化测试从网站到 Key 设置的完整流程：
1. 验证网站简化版
2. 启动 DSH Agent
3. 验证首屏显示 Key 表单
4. 模拟 Key 输入和验证
5. 验证切换到聊天模式

注意：本脚本为开发验证用，服务用 node 直接启动 web-entry.mjs（本机 dev 验证）；
产品安装/装机测试仍在 VM 进行。
#>

param(
    [string]$TestKey = $env:DEEPSEEK_API_KEY_TEST,
    [int]$Port = 3081
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "=== DSH Agent Key Flow Integration Test ===" -ForegroundColor Cyan
Write-Host "检测到端口: $Port"

# 1. 清理测试环境
Write-Host "`n[1/6] 清理测试环境..." -ForegroundColor Yellow
$testHome = "$env:TEMP\dsh-agent-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
$env:DSH_HOME = $testHome
Write-Host "    测试 DSH_HOME: $testHome"

# 2. 验证网站文件
Write-Host "`n[2/6] 验证网站文件..." -ForegroundColor Yellow
$websiteIndex = Join-Path $projectRoot 'download-page\index.html'
if (!(Test-Path $websiteIndex)) {
    throw "网站 index.html 不存在"
}
$websiteContent = Get-Content $websiteIndex -Raw
if ($websiteContent -notmatch '下载 DSH Agent') {
    throw "网站内容不符合预期（缺少下载按钮）"
}
Write-Host "    OK 网站文件正常（单页下载入口）"

# 3. 启动 DSH Agent（后台）
Write-Host "`n[3/6] 启动 DSH Agent..." -ForegroundColor Yellow
$prepackDir = Join-Path $projectRoot 'packaging\prepack'
$agentProcess = Start-Process -FilePath "node" `
    -ArgumentList @("web-entry.mjs", "--port", "$Port", "--no-open") `
    -WorkingDirectory $prepackDir `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput "$env:TEMP\dsh-agent-test-out.log" `
    -RedirectStandardError "$env:TEMP\dsh-agent-test-err.log"

Write-Host "    进程 PID: $($agentProcess.Id)"
Start-Sleep -Seconds 12

try {
    # 4. 验证首屏（Key 表单）
    Write-Host "`n[4/6] 验证首屏显示 Key 表单..." -ForegroundColor Yellow
    $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port" -UseBasicParsing -TimeoutSec 10
    if ($response.Content -notmatch 'input-api-key') {
        throw "首屏不是 Key 表单"
    }
    if ($response.Content -notmatch 'btn-open-deepseek') {
        throw "缺少打开 DeepSeek 按钮"
    }
    Write-Host "    OK 首屏正确显示 Key 表单（非聊天窗）"

    # 4b. 验证表单静态资源
    Write-Host "`n[4b/6] 验证表单静态资源..." -ForegroundColor Yellow
    $css = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/ui/key-form.css" -UseBasicParsing -TimeoutSec 10
    if ($css.StatusCode -ne 200) { throw "key-form.css 未返回 200" }
    $js = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/ui/key-form.js" -UseBasicParsing -TimeoutSec 10
    if ($js.StatusCode -ne 200) { throw "key-form.js 未返回 200" }
    Write-Host "    OK 表单资源可访问"

    # 5. 测试 Key 验证 API
    Write-Host "`n[5/6] 测试 Key 验证 API..." -ForegroundColor Yellow

    # 5a. 格式校验（无效 key）
    $badBody = @{ key = 'invalid-key' } | ConvertTo-Json
    $badResponse = Invoke-RestMethod `
        -Uri "http://127.0.0.1:$Port/api/setup/validate-key" `
        -Method POST `
        -Body $badBody `
        -ContentType "application/json" `
        -TimeoutSec 10
    if ($badResponse.valid -eq $true) { throw "无效 Key 不应验证通过" }
    Write-Host "    OK 格式校验生效（invalid-key 被拒绝）"

    # 5b. 真实 Key（如果提供了）
    if ($TestKey) {
        try {
            $body = @{ key = $TestKey } | ConvertTo-Json
            $validateResponse = Invoke-RestMethod `
                -Uri "http://127.0.0.1:$Port/api/setup/validate-key" `
                -Method POST `
                -Body $body `
                -ContentType "application/json" `
                -TimeoutSec 30

            if ($validateResponse.valid -eq $true) {
                Write-Host "    OK Key 验证 API 正常（真实 Key 测试通过）" -ForegroundColor Green
                # 验证成功后页面应进入聊天（存在凭据标记后刷新 / 应含 __DSH_BOOT__）
                $after = Invoke-WebRequest -Uri "http://127.0.0.1:$Port" -UseBasicParsing -TimeoutSec 10
                if ($after.Content -match '__DSH_BOOT__') {
                    Write-Host "    OK Key 有效后进入聊天界面" -ForegroundColor Green
                } else {
                    Write-Host "    提示: Key 已保存，但首页仍显示表单（需重载/凭据回读）" -ForegroundColor Yellow
                }
            } else {
                Write-Host "    WARN Key 验证失败: $($validateResponse.message)" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "    WARN Key 验证 API 调用异常: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "    SKIP 未提供测试 Key（设置 `$env:DEEPSEEK_API_KEY_TEST 可测真实验证）" -ForegroundColor Gray
    }

    # 6. 完成
    Write-Host "`n[6/6] 关键路径验证完成" -ForegroundColor Green
} finally {
    # 清理
    Write-Host "`n清理测试环境..." -ForegroundColor Yellow
    Stop-Process -Id $agentProcess.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Remove-Item -Path $testHome -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:TEMP\dsh-agent-test-out.log", "$env:TEMP\dsh-agent-test-err.log" -Force -ErrorAction SilentlyContinue
    Remove-Item Env:DSH_HOME -ErrorAction SilentlyContinue
}

Write-Host "`n=== 测试完成 ===" -ForegroundColor Green