# msi-handover.ps1
# MSI 退役前的交接腳本：把「只存在於 MSI 本機」的東西送上 Drive，讓 Acer 接手。
# 在 MSI 的 PowerShell 執行：
#   powershell -ExecutionPolicy Bypass -File "G:\我的雲端硬碟\charlie-tools\tools\machine-inventory\msi-handover.ps1"
#
# 做三件事：
#   ① Supabase 保活：keepalive 腳本 + MCP 設定（含 token，所以只寫到 Drive，不進 git、不經對話）
#   ② 舊架構 memory：六個專案各自的實體 memory 資料夾整包複製，供 Acer 比對補漏
#   ③ 只在本機的專案：C:\ccwang-aiagent\ 與 dev\ ——先量體積列結構，不直接搬（模型檔可能很大）
#
# ⚠️ 輸出目錄含 Supabase token。它落在你私人 Drive 的 machine-state\ 底下（刻意放在 git repo 外，
#    不會被推上 public GitHub）。Acer 接手完成後可以整個刪掉。

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$HomeDir   = $env:USERPROFILE
$DriveRoot = 'G:\我的雲端硬碟'
$OutDir    = Join-Path $DriveRoot 'machine-state\_msi-transfer'
$Report    = Join-Path $OutDir 'handover-report.md'

New-Item -ItemType Directory -Force $OutDir | Out-Null

$Lines = New-Object System.Collections.Generic.List[string]
function Add-Line($s) { $Lines.Add($s) }

Add-Line "# MSI 交接報告"
Add-Line ''
Add-Line "> 產生於 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')，機器 $($env:COMPUTERNAME) / $($env:USERNAME)"
Add-Line ''

# ─────────────── ① Supabase 保活 ───────────────
Add-Line '## ① Supabase 保活'
Add-Line ''

$keepalive = Join-Path $HomeDir '.claude\supabase-keepalive.js'
if (Test-Path $keepalive) {
    Copy-Item $keepalive (Join-Path $OutDir 'supabase-keepalive.js') -Force
    $kaSize = (Get-Item $keepalive).Length
    Add-Line "- ✅ 已複製 ``supabase-keepalive.js``（$kaSize bytes）"
} else {
    Add-Line "- ❌ 找不到 ``$keepalive``"
}

# MCP 設定：整份 mcpServers 都匯出，方便 Acer 比對還缺哪些
$claudeJson = Join-Path $HomeDir '.claude.json'
if (Test-Path $claudeJson) {
    try {
        $cj = Get-Content $claudeJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cj.mcpServers) {
            $cj.mcpServers | ConvertTo-Json -Depth 10 |
                Out-File (Join-Path $OutDir 'msi-mcpServers.json') -Encoding utf8
            $names = $cj.mcpServers.PSObject.Properties.Name
            Add-Line "- ✅ 已匯出 MCP 設定 ``msi-mcpServers.json``（$(@($names).Count) 個：$(@($names) -join ', ')）"
            Add-Line "  - ⚠️ 這個檔可能含 access token，Acer 接手後請刪除整個 ``_msi-transfer`` 目錄"
        } else {
            Add-Line '- ❌ `.claude.json` 裡沒有 mcpServers'
        }
    } catch {
        Add-Line '- ❌ `.claude.json` 解析失敗'
    }
} else {
    Add-Line "- ❌ 找不到 ``$claudeJson``"
}

# 排程定義也匯出，Acer 照著重建（XML 綁 SID 不能直接匯入，但參數可以照抄）
$taskNames = @('Supabase-KeepAlive','ClaudeDailyReport','ClaudeBirthdayCard','ClaudeDailyReportCatchup')
$taskDir = Join-Path $OutDir 'scheduled-tasks'
New-Item -ItemType Directory -Force $taskDir | Out-Null
Add-Line ''
Add-Line '**排程定義（XML 綁 SID 不能直接匯入，但參數可照抄重建）：**'
foreach ($tn in $taskNames) {
    try {
        $xml = Export-ScheduledTask -TaskName $tn -ErrorAction Stop
        $xml | Out-File (Join-Path $taskDir "$tn.xml") -Encoding utf8
        Add-Line "- ✅ ``$tn.xml``"
    } catch {
        Add-Line "- ⏭️ ``$tn``（這台沒有這個排程）"
    }
}

# 外殼腳本一併備份（兩台版本可能不同）
$scriptsDir = Join-Path $HomeDir '.claude\scripts'
if (Test-Path $scriptsDir) {
    $dst = Join-Path $OutDir 'claude-scripts'
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item (Join-Path $scriptsDir '*') $dst -Recurse -Force
    $n = @(Get-ChildItem $dst -Recurse -File).Count
    Add-Line "- ✅ 已複製 ``~/.claude/scripts/`` 共 $n 個檔（日報／賀卡外殼腳本，供比對版本差異）"
}

# ─────────────── ② 舊架構 memory ───────────────
Add-Line ''
Add-Line '## ② 舊架構 memory（六個專案各自的實體資料夾）'
Add-Line ''

$projRoot = Join-Path $HomeDir '.claude\projects'
$memDst   = Join-Path $OutDir 'msi-memory'
New-Item -ItemType Directory -Force $memDst | Out-Null

$totalMd = 0
if (Test-Path $projRoot) {
    Add-Line '| 專案 slug | 類型 | .md 檔數 |'
    Add-Line '|---|---|---|'
    foreach ($pd in @(Get-ChildItem $projRoot -Directory -ErrorAction SilentlyContinue)) {
        $memDir = Join-Path $pd.FullName 'memory'
        if (-not (Test-Path $memDir)) { continue }
        $mi = Get-Item $memDir -Force
        $kind = '實體資料夾'
        if ($mi.LinkType) { $kind = "$($mi.LinkType)（不複製）" }
        $mds = @(Get-ChildItem $memDir -Recurse -Filter '*.md' -ErrorAction SilentlyContinue)
        Add-Line "| $($pd.Name) | $kind | $($mds.Count) |"
        # 只搬實體資料夾；junction 指向的是同一份東西，複製只會重複
        if (-not $mi.LinkType -and $mds.Count -gt 0) {
            $sub = Join-Path $memDst $pd.Name
            New-Item -ItemType Directory -Force $sub | Out-Null
            foreach ($m in $mds) { Copy-Item $m.FullName $sub -Force }
            $totalMd += $mds.Count
        }
    }
    Add-Line ''
    Add-Line "**已複製 $totalMd 個 .md 到 ``msi-memory\<slug>\``**，供 Acer 比對 `memory-shared` 缺哪些內容。"
} else {
    Add-Line '❌ 找不到 `.claude\projects`'
}

# ─────────────── ③ 只在本機的專案：先量體積 ───────────────
Add-Line ''
Add-Line '## ③ 只在本機的專案（先量體積，不直接搬）'

function Measure-Tree($root, $label) {
    Add-Line ''
    Add-Line "### $label"
    Add-Line "路徑：``$root``"
    if (-not (Test-Path $root)) { Add-Line '❌ 不存在'; return }

    $all = @(Get-ChildItem $root -Recurse -File -Force -ErrorAction SilentlyContinue)
    $sum = 0
    foreach ($f in $all) { $sum += $f.Length }
    Add-Line ''
    Add-Line "**合計：$($all.Count) 檔，$([math]::Round($sum/1MB,1)) MB**"

    # 各子目錄體積
    $subs = @(Get-ChildItem $root -Directory -Force -ErrorAction SilentlyContinue)
    if ($subs.Count -gt 0) {
        Add-Line ''
        Add-Line '| 子目錄 | 檔數 | 大小 (MB) | git |'
        Add-Line '|---|---|---|---|'
        foreach ($s in $subs) {
            $sf = @(Get-ChildItem $s.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
            $ss = 0
            foreach ($f in $sf) { $ss += $f.Length }
            $g = '—'
            if (Test-Path (Join-Path $s.FullName '.git')) { $g = '✅' }
            Add-Line "| $($s.Name) | $($sf.Count) | $([math]::Round($ss/1MB,1)) | $g |"
        }
    }

    # 大檔清單（決定「搬程式碼、模型重下載」的依據）
    $big = @($all | Where-Object { $_.Length -gt 20MB } | Sort-Object Length -Descending | Select-Object -First 15)
    if ($big.Count -gt 0) {
        Add-Line ''
        Add-Line '**> 20 MB 的大檔（建議不搬、重新下載）：**'
        Add-Line ''
        Add-Line '| 檔案 | 大小 (MB) |'
        Add-Line '|---|---|'
        foreach ($b in $big) {
            $rel = $b.FullName.Replace($root, '').TrimStart('\')
            Add-Line "| ``$rel`` | $([math]::Round($b.Length/1MB,1)) |"
        }
    } else {
        Add-Line ''
        Add-Line '（沒有超過 20 MB 的檔案 → 整包搬上 Drive 沒問題）'
    }
}

Measure-Tree 'C:\ccwang-aiagent' 'C:\ccwang-aiagent（含 notype、VoxCPM2）'
Measure-Tree (Join-Path $HomeDir 'dev\2026-crypto-scan') '2026-crypto-scan（MSI 的 dev，無版控）'

# 順便找出其他「無版控又不在 Drive」的本機專案
Add-Line ''
Add-Line '### 其他本機專案（`dev\` 底下）'
$devRoot = Join-Path $HomeDir 'dev'
if (Test-Path $devRoot) {
    Add-Line ''
    Add-Line '| 資料夾 | git | 大小 (MB) | 風險 |'
    Add-Line '|---|---|---|---|'
    foreach ($d in @(Get-ChildItem $devRoot -Directory -ErrorAction SilentlyContinue)) {
        $df = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)
        $ds = 0
        foreach ($f in $df) { $ds += $f.Length }
        $isGit = Test-Path (Join-Path $d.FullName '.git')
        $g = '—'; $risk = '⚠️ 無版控，只在這台'
        if ($isGit) { $g = '✅'; $risk = 'GitHub 有備份' }
        Add-Line "| $($d.Name) | $g | $([math]::Round($ds/1MB,1)) | $risk |"
    }
} else {
    Add-Line '（沒有 `dev\`）'
}

$Lines -join "`r`n" | Out-File -FilePath $Report -Encoding utf8
Write-Output "OK -> $Report"
Write-Output "transfer dir: $OutDir"
