# DSH Agent - VM test helper (host-side automated checks + manual VM checklist)
# Run: pwsh packaging/test-vm.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root 'dist\dsh-agent-installer.exe'
$downloadPage = Join-Path $root 'download-page\index.html'
$agentDir = Join-Path $root 'bootstrap-agent'
$PORT = 19999

$pass = 0
$fail = 0
$warn = 0

function Report($label, $ok, $detail = '') {
    $mark = if ($ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("  [{0}] {1} {2}" -f $mark, $label, $detail)
    if ($ok) { $script:pass++ } else { $script:fail++ }
}

Write-Host '===== DSH Agent VM test (host-side) ====='
Write-Host ''

# --- [1] build artifact ---
Write-Host '[1/6] Build artifact'
if (Test-Path $exe) {
    $sizeMB = [math]::Round((Get-Item $exe).Length / 1MB, 1)
    Report "dsh-agent-installer.exe exists" $true "($sizeMB MB)"
    Report "size < 50 MB" ($sizeMB -lt 50) "($sizeMB MB)"
} else {
    Report 'dsh-agent-installer.exe exists' $false
}

# --- [2] download page ---
Write-Host '[2/6] Download page'
if (Test-Path $downloadPage) {
    $html = Get-Content $downloadPage -Raw
    Report 'index.html exists' $true
    Report 'contains verifyKey logic' ($html -match 'verifyKey')
    Report 'contains config.json generation' ($html -match 'config\.json')
    Report 'contains dsh-agent.com link' ($html -match 'dsh-agent\.com')
    Report 'contains release download URL' ($html -match 'releases/latest/download')
} else {
    Report 'index.html exists' $false
}

# --- [3] bootstrap agent files ---
Write-Host '[3/6] Bootstrap agent files'
$agentFiles = @('server.js', 'chat.html', 'downloader.js', 'qrcode.min.js')
foreach ($f in $agentFiles) {
    Report "$f exists" (Test-Path (Join-Path $agentDir $f))
}
if (Test-Path (Join-Path $agentDir 'chat.html')) {
    $chat = Get-Content (Join-Path $agentDir 'chat.html') -Raw
    Report 'chat.html has share overlay' ($chat -match 'share-overlay')
    Report 'chat.html has share entry' ($chat -match 'share-entry')
    Report 'chat.html references qrcode.min.js' ($chat -match 'qrcode\.min\.js')
}
$uninstallBat = Join-Path $root 'packaging\uninstall.bat'
if (Test-Path $uninstallBat) {
    $ub = Get-Content $uninstallBat -Raw
    Report 'uninstall.bat exists' $true
    Report 'uninstall.bat kills port 19999' ($ub -match '19999')
    Report 'uninstall.bat removes install dir' ($ub -match 'Remove-Item')
    Report 'uninstall.bat supports -y' ($ub -match '\-y')
} else {
    Report 'uninstall.bat exists' $false
}

# --- [4] dependencies ---
Write-Host '[4/6] Dependencies'
$nodeCmd = Get-Command node -ErrorAction SilentlyContinue
Report 'node.js available' ($null -ne $nodeCmd)
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
if (-not (Test-Path $sevenZip)) { $sevenZip = 'C:\Program Files (x86)\7-Zip\7z.exe' }
Report '7-Zip available' (Test-Path $sevenZip)

# --- [5] bootstrap agent smoke test ---
Write-Host '[5/6] Bootstrap agent smoke test'
$cfgPath = Join-Path $agentDir 'config.json'
$cfgBackup = $null
if (Test-Path $cfgPath) { $cfgBackup = Get-Content $cfgPath -Raw }
try {
    # write a test config (invalid key; server must still start and serve pages)
    '{"apiKey":"sk-test-invalid-key-for-vm-test","createdAt":"2026-08-31T00:00:00.000Z"}' |
        Out-File -FilePath $cfgPath -Encoding utf8

    $proc = Start-Process -FilePath 'node' -ArgumentList 'server.js' -WorkingDirectory $agentDir -PassThru -WindowStyle Hidden
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $r = Invoke-WebRequest -Uri "http://localhost:$PORT/" -UseBasicParsing -TimeoutSec 2
            if ($r.StatusCode -eq 200) { $ready = $true; break }
        } catch {}
    }
    Report 'server starts and listens' $ready

    if ($ready) {
        try {
            $homeRes = Invoke-WebRequest -Uri "http://localhost:$PORT/" -UseBasicParsing -TimeoutSec 5
            Report 'home page 200' ($homeRes.StatusCode -eq 200) "($($homeRes.StatusCode))"
            Report 'home page contains DSH Agent' ($homeRes.Content -match 'DSH Agent')
        } catch { Report 'home page 200' $false ($_.Exception.Message) }

        try {
            $chat = Invoke-WebRequest -Uri "http://localhost:$PORT/chat.html" -UseBasicParsing -TimeoutSec 5
            Report 'chat.html 200' ($chat.StatusCode -eq 200)
        } catch { Report 'chat.html 200' $false ($_.Exception.Message) }

        try {
            $qr = Invoke-WebRequest -Uri "http://localhost:$PORT/qrcode.min.js" -UseBasicParsing -TimeoutSec 5
            Report 'qrcode.min.js 200' ($qr.StatusCode -eq 200)
        } catch { Report 'qrcode.min.js 200' $false ($_.Exception.Message) }

        try {
            $body = @{ messages = @(@{ role = 'user'; content = 'hi' }) } | ConvertTo-Json -Depth 5
            $api = Invoke-WebRequest -Uri "http://localhost:$PORT/api/chat" -Method POST -Body $body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 20
            $json = $api.Content | ConvertFrom-Json
            Report 'chat API responds' ($null -ne $json) "keyError=$($json.keyError)"
        } catch { Report 'chat API responds' $false ($_.Exception.Message) }

        try {
            $trav = Invoke-WebRequest -Uri "http://localhost:$PORT/../windows/win.ini" -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
            Report 'path traversal blocked' ($trav.StatusCode -in @(403, 404)) "($($trav.StatusCode))"
        } catch { Report 'path traversal blocked' $true '(blocked)' }
    }

    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
} finally {
    if ($cfgBackup -ne $null) {
        Set-Content -Path $cfgPath -Value $cfgBackup -NoNewline
    } else {
        Remove-Item $cfgPath -Force -ErrorAction SilentlyContinue
    }
}

# --- [6] manual VM checklist ---
Write-Host '[6/6] Manual checklist (run inside clean Windows VM)'
$manual = @(
    'a. Boot from Win10 ISO -> install Pro -> create account'
    'b. Copy dsh-agent-installer.exe + index.html into VM'
    'c. Double-click exe -> extracts -> browser opens http://localhost:19999'
    'd. First chat succeeds -> share card pops up with QR code'
    'e. Share card: QR scans to https://dsh-agent.com; copy button works'
    'f. Record SmartScreen behavior'
    'g. Uninstall cleans up'
)
$manual | ForEach-Object { Write-Host ("     $_") }

Write-Host ''
Write-Host "===== RESULT: PASS=$pass FAIL=$fail ====="
if ($fail -gt 0) { exit 1 } else { Write-Host 'ALL HOST-SIDE CHECKS PASSED' }
