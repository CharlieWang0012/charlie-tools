# machine-inventory.ps1
# 產出「這台機器到底有什麼在運作」的快照，寫成 Markdown 放到 GDrive，供跨機器比對。
# 用法（在任一台機器的 PowerShell 執行）：
#   powershell -ExecutionPolicy Bypass -File "G:\我的雲端硬碟\charlie-tools\tools\machine-inventory\inventory.ps1"
# 輸出：G:\我的雲端硬碟\machine-state\<電腦名>-<帳號>.md
#
# 設計原則：
# - 不寫死使用者名，一切走 $env:USERPROFILE，兩台機器跑同一支腳本
# - 憑證只記「有／無」與檔案時間，絕不輸出 token、key、密碼內容
# - 不做 git fetch、不打網路，純本地狀態，跑起來才快
# - 中文不靠 stdout 傳遞（會變亂碼），一律由腳本自己寫檔

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$HomeDir  = $env:USERPROFILE
$DriveRoot = 'G:\我的雲端硬碟'
$OutDir   = Join-Path $DriveRoot 'machine-state'
$OutFile  = Join-Path $OutDir "$($env:COMPUTERNAME)-$($env:USERNAME).md"

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }

$Lines = New-Object System.Collections.Generic.List[string]
function Add-Line($s) { $Lines.Add($s) }
function Add-H($s) { $Lines.Add(''); $Lines.Add("## $s"); $Lines.Add('') }

function Test-Cmd($name) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if ($c) { return $c.Source } else { return $null }
}

function Get-CmdVersion($name, $verArg) {
    $src = Test-Cmd $name
    if (-not $src) { return $null }
    $v = ''
    try { $v = (& $name $verArg 2>$null | Select-Object -First 1) } catch { $v = '(版本取得失敗)' }
    if (-not $v) { $v = '(無版本輸出)' }
    return @{ Source = $src; Version = ("$v").Trim() }
}

function Fmt-Code($arr) {
    $a = @($arr) | Where-Object { $_ -ne $null -and "$_".Trim() -ne '' }
    if (@($a).Count -eq 0) { return '無' }
    $out = @()
    foreach ($x in $a) { $out += ('`' + $x + '`') }
    return ($out -join ', ')
}

# 判斷某個 CLI 是否處於「已登入」狀態（跑真正的狀態指令，比看檔案準）
function Test-CliLogin($cmd, [string[]]$argList, $okPattern) {
    if (-not (Test-Cmd $cmd)) { return '⏭️ CLI 未安裝' }
    $out = ''
    # 狀態訊息常走 stderr，所以要 2>&1；參數必須 splatting，不能整串當一個參數傳
    try { $out = (& $cmd @argList 2>&1 | Out-String) } catch { return '❓ 查詢失敗' }
    if ($out -match $okPattern) { return '✅ 已登入' } else { return '❌ 未登入' }
}

function Test-PathState($path, $label) {
    if (Test-Path $path) {
        $i = Get-Item $path -Force
        $when = $i.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        return "| $label | ✅ 有 | ``$path`` | 更新 $when |"
    } else {
        return "| $label | ❌ 無 | ``$path`` | — |"
    }
}

# ───────────────────────── 標頭 ─────────────────────────
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$os  = (Get-CimInstance Win32_OperatingSystem)
Add-Line "# 機器狀態快照：$($env:COMPUTERNAME) / $($env:USERNAME)"
Add-Line ''
Add-Line "> 由 ``charlie-tools/tools/machine-inventory/inventory.ps1`` 產生於 **$now**"
Add-Line '> 用途：跨機器比對「哪些專案／排程／技能／憑證是活的」。憑證一律只記有無，不含內容。'
Add-Line ''
Add-Line '| 項目 | 值 |'
Add-Line '|---|---|'
Add-Line "| 電腦名 | $($env:COMPUTERNAME) |"
Add-Line "| 帳號 | $($env:USERNAME) |"
Add-Line "| 家目錄 | ``$HomeDir`` |"
Add-Line "| OS | $($os.Caption) $($os.Version) |"
Add-Line "| 記憶體 | $([math]::Round($os.TotalVisibleMemorySize/1MB,1)) GB |"
$gpu = (Get-CimInstance Win32_VideoController | Select-Object -ExpandProperty Name) -join ' / '
Add-Line "| 顯示卡 | $gpu |"

# ───────────────────────── 排程工作 ─────────────────────────
Add-H '⏰ 排程工作（工作排程器，已排除 Microsoft 內建）'
$tasks = @()
try {
    $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }
} catch { Add-Line '(讀取排程失敗)' }

if ($tasks.Count -eq 0) {
    Add-Line '**沒有任何自訂排程工作。**'
} else {
    Add-Line '| 工作 | 狀態 | 觸發 | 執行內容 | 上次執行 | 結果 |'
    Add-Line '|---|---|---|---|---|---|'
    foreach ($t in $tasks) {
        $trig = ''
        foreach ($tr in $t.Triggers) {
            $bits = @()
            if ($tr.StartBoundary) { $bits += ([datetime]$tr.StartBoundary).ToString('HH:mm') }
            $cls = $tr.CimClass.CimClassName -replace 'MSFT_Task', '' -replace 'Trigger', ''
            $bits += $cls
            $trig += ($bits -join ' ') + '; '
        }
        $act = ''
        foreach ($a in $t.Actions) {
            if ($a.Execute) { $act += "$($a.Execute) $($a.Arguments); " }
        }
        $act = $act -replace '\|', '/'
        if ($act.Length -gt 150) { $act = $act.Substring(0,150) + '…' }
        $lastRun = '—'; $lastRes = '—'
        try {
            $info = Get-ScheduledTaskInfo -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction Stop
            if ($info.LastRunTime) { $lastRun = $info.LastRunTime.ToString('MM-dd HH:mm') }
            $lastRes = "$($info.LastTaskResult)"
        } catch {}
        Add-Line "| $($t.TaskPath)$($t.TaskName) | $($t.State) | $($trig.TrimEnd('; ')) | ``$act`` | $lastRun | $lastRes |"
    }
}

Add-Line ''
Add-Line '### 啟動資料夾'
$startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
$sItems = @(Get-ChildItem $startup -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })
if ($sItems.Count -eq 0) {
    Add-Line '**空的。**'
} else {
    foreach ($s in $sItems) { Add-Line "- ``$($s.Name)`` （更新 $($s.LastWriteTime.ToString('yyyy-MM-dd')))" }
}

# ───────────────────────── Claude Code ─────────────────────────
Add-H '🤖 Claude Code'
$claudeJson = Join-Path $HomeDir '.claude.json'
if (Test-Path $claudeJson) {
    try {
        $cj = Get-Content $claudeJson -Raw -Encoding UTF8 | ConvertFrom-Json
        $gm = @()
        if ($cj.mcpServers) { $gm = $cj.mcpServers.PSObject.Properties.Name }
        $gmStr = Fmt-Code $gm
        Add-Line "**全域 MCP servers（$(@($gm).Count)）：** $gmStr"
        Add-Line ''
        Add-Line '**專案層 MCP servers：**'
        $anyProj = $false
        if ($cj.projects) {
            foreach ($p in $cj.projects.PSObject.Properties) {
                $pm = @()
                if ($p.Value.mcpServers) { $pm = $p.Value.mcpServers.PSObject.Properties.Name }
                if (@($pm).Count -gt 0) {
                    $anyProj = $true
                    $pmStr = Fmt-Code $pm
                    Add-Line "- ``$($p.Name)`` → $pmStr"
                }
            }
        }
        if (-not $anyProj) { Add-Line '- 無' }
    } catch { Add-Line '(.claude.json 解析失敗)' }
} else {
    Add-Line '❌ 沒有 ``.claude.json``'
}

Add-Line ''
Add-Line '**Skills（`~/.claude/skills`）：**'
$skills = @(Get-ChildItem (Join-Path $HomeDir '.claude\skills') -Directory -ErrorAction SilentlyContinue)
if ($skills.Count -eq 0) {
    Add-Line '- 無'
} else {
    $skStr = Fmt-Code $skills.Name
    Add-Line "- 共 $($skills.Count) 個：$skStr"
}

Add-Line ''
Add-Line '**Hooks（settings.json / settings.local.json）：**'
foreach ($sf in @('settings.json','settings.local.json')) {
    $sp = Join-Path $HomeDir ".claude\$sf"
    if (Test-Path $sp) {
        try {
            $sj = Get-Content $sp -Raw -Encoding UTF8 | ConvertFrom-Json
            $hk = @()
            if ($sj.hooks) { $hk = $sj.hooks.PSObject.Properties.Name }
            $hkStr = '無 hooks'
            if (@($hk).Count -gt 0) { $hkStr = (@($hk) -join ', ') }
            Add-Line "- ``$sf``：$hkStr"
        } catch { Add-Line "- ``$sf``：解析失敗" }
    } else {
        Add-Line "- ``$sf``：❌ 無"
    }
}

Add-Line ''
Add-Line '**Memory 檔數：**'
Add-Line '（`.claude\projects\<slug>\memory` 通常是 junction 指向 `memory-shared`，所以以 memory-shared 的數字為準）'
foreach ($md in @('.claude\memory-shared')) {
    $mp = Join-Path $HomeDir $md
    if (Test-Path $mp) {
        $cnt = @(Get-ChildItem $mp -Recurse -Filter '*.md' -ErrorAction SilentlyContinue).Count
        Add-Line "- ``$md``：$cnt 個 .md"
    } else {
        Add-Line "- ``$md``：❌ 無"
    }
}
# memory junction 是否接好（換機最常斷的地方）
$projRoot = Join-Path $HomeDir '.claude\projects'
$jOk = @()
if (Test-Path $projRoot) {
    foreach ($pd in @(Get-ChildItem $projRoot -Directory -ErrorAction SilentlyContinue)) {
        $memDir = Join-Path $pd.FullName 'memory'
        if (Test-Path $memDir) {
            $mi = Get-Item $memDir -Force
            $lt = ' 實體資料夾'
            if ($mi.LinkType) { $lt = " $($mi.LinkType) → $($mi.Target -join ',')" }
            $jOk += "$($pd.Name):$lt"
        }
    }
}
if (@($jOk).Count -eq 0) {
    Add-Line '- ⚠️ 沒有任何專案 memory 目錄'
} else {
    foreach ($j in $jOk) { Add-Line "- $j" }
}

# ───────────────────────── 其他 AI agent ─────────────────────────
Add-H '🧩 其他 AI agent 全域設定'
Add-Line '| Agent | 狀態 | 路徑 | 備註 |'
Add-Line '|---|---|---|---|'
Add-Line (Test-PathState (Join-Path $HomeDir '.claude\CLAUDE.md') 'Claude Code 全域')
Add-Line (Test-PathState (Join-Path $HomeDir '.codex\AGENTS.md') 'Codex')
Add-Line (Test-PathState (Join-Path $HomeDir '.config\opencode\opencode.jsonc') 'OpenCode 設定')
Add-Line (Test-PathState (Join-Path $HomeDir '.config\opencode\instructions') 'OpenCode instructions')
Add-Line (Test-PathState (Join-Path $HomeDir '.gemini\AGENTS.md') 'Antigravity')
Add-Line (Test-PathState (Join-Path $DriveRoot 'CLAUDE.md') 'Drive 共用全域')

# ───────────────────────── CLI 工具 ─────────────────────────
Add-H '🛠️ CLI 工具與版本'
$cmds = @(
    @{n='node';       a='--version'},
    @{n='npm';        a='--version'},
    @{n='python';     a='--version'},
    @{n='pip';        a='--version'},
    @{n='uv';         a='--version'},
    @{n='git';        a='--version'},
    @{n='gh';         a='--version'},
    @{n='ffmpeg';     a='-version'},
    @{n='firebase';   a='--version'},
    @{n='gcloud';     a='--version'},
    @{n='chezmoi';    a='--version'},
    @{n='claude';     a='--version'},
    @{n='codex';      a='--version'},
    @{n='opencode';   a='--version'},
    @{n='auto-editor';a='--version'},
    @{n='whisper';    a='--help'},
    @{n='rembg';      a='--version'}
)
Add-Line '| 工具 | 狀態 | 版本 | 路徑 |'
Add-Line '|---|---|---|---|'
foreach ($c in $cmds) {
    $r = Get-CmdVersion $c.n $c.a
    if ($r) {
        $ver = $r.Version
        if ($ver.Length -gt 60) { $ver = $ver.Substring(0,60) + '…' }
        Add-Line "| ``$($c.n)`` | ✅ | $ver | ``$($r.Source)`` |"
    } else {
        Add-Line "| ``$($c.n)`` | ❌ 未安裝 | — | — |"
    }
}

Add-Line ''
Add-Line '**npm 全域套件：**'
$npmRoot = Join-Path $env:APPDATA 'npm\node_modules'
$npmPkgs = @(Get-ChildItem $npmRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne '.bin' })
if ($npmPkgs.Count -eq 0) {
    Add-Line '- 無（或裝在別的 prefix）'
} else {
    foreach ($p in $npmPkgs) {
        if ($p.Name -like '@*') {
            foreach ($sub in @(Get-ChildItem $p.FullName -Directory -ErrorAction SilentlyContinue)) {
                Add-Line "- ``$($p.Name)/$($sub.Name)``"
            }
        } else {
            Add-Line "- ``$($p.Name)``"
        }
    }
}

# ───────────────────────── Python 套件 ─────────────────────────
Add-H '🐍 Python 關鍵套件'
if (Test-Cmd 'python') {
    $watch = @('faster-whisper','openai-whisper','rembg','onnxruntime','openai','anthropic',
               'firebase-admin','google-cloud-firestore','google-generativeai','torch',
               'feedparser','requests','pillow','beautifulsoup4','yt-dlp','auto-editor','pandas','openpyxl')
    $installed = @{}
    try {
        $freeze = & python -m pip list --format=freeze 2>$null
        foreach ($line in $freeze) {
            $parts = $line -split '=='
            if ($parts.Count -ge 2) { $installed[$parts[0].ToLower()] = $parts[1] }
        }
    } catch {}
    Add-Line '| 套件 | 狀態 | 版本 |'
    Add-Line '|---|---|---|'
    foreach ($w in $watch) {
        $k = $w.ToLower()
        if ($installed.ContainsKey($k)) {
            Add-Line "| ``$w`` | ✅ | $($installed[$k]) |"
        } else {
            Add-Line "| ``$w`` | ❌ | — |"
        }
    }
    Add-Line ''
    Add-Line "（全域 pip 套件總數：$($installed.Count)）"
} else {
    Add-Line '❌ 沒有 python'
}

# ───────────────────────── 憑證與登入狀態 ─────────────────────────
Add-H '🔑 憑證／登入狀態（只記有無，不含內容）'
Add-Line '| 憑證 | 狀態 | 路徑 | 備註 |'
Add-Line '|---|---|---|---|'
Add-Line (Test-PathState (Join-Path $env:APPDATA 'configstore\firebase-tools.json') 'Firebase CLI 憑證檔')
Add-Line (Test-PathState (Join-Path $env:APPDATA 'gcloud\application_default_credentials.json') 'gcloud ADC')
Add-Line (Test-PathState (Join-Path $env:APPDATA 'GitHub CLI\hosts.yml') 'GitHub CLI 設定檔')
Add-Line (Test-PathState (Join-Path $HomeDir '.config\chezmoi\chezmoi.toml') 'chezmoi 金鑰檔')
Add-Line (Test-PathState (Join-Path $HomeDir '.claude\.credentials.json') 'Claude Code 登入')
Add-Line ''
Add-Line '**實際登入狀態（跑狀態指令查，比看檔案準——`gh` 的 token 可能存在 keyring）：**'
Add-Line ''
Add-Line '| CLI | 登入狀態 |'
Add-Line '|---|---|'
$ghState = Test-CliLogin 'gh' @('auth','status') 'Logged in to'
$fbState = Test-CliLogin 'firebase' @('login:list') '@'
$clState = Test-CliLogin 'claude' @('--version') 'Claude Code'
Add-Line "| ``gh`` | $ghState |"
Add-Line "| ``firebase`` | $fbState |"
Add-Line "| ``claude`` | $clState |"
Add-Line ''
if ($env:GOOGLE_APPLICATION_CREDENTIALS) {
    Add-Line "**GOOGLE_APPLICATION_CREDENTIALS：** ✅ 有設 → ``$($env:GOOGLE_APPLICATION_CREDENTIALS)``"
} else {
    Add-Line '**GOOGLE_APPLICATION_CREDENTIALS：** ❌ 未設'
}

Add-Line ''
Add-Line '**各專案 .env（只記存在與變數名數量，不記值）：**'
$envFound = $false
foreach ($root in @($DriveRoot, (Join-Path $HomeDir 'dev'))) {
    if (-not (Test-Path $root)) { continue }
    foreach ($d in @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
        $ef = Join-Path $d.FullName '.env'
        if (Test-Path $ef) {
            $envFound = $true
            $keys = @(Get-Content $ef -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\s*[A-Za-z_]' })
            $names = @()
            foreach ($k in $keys) { $names += ($k -split '=')[0].Trim() }
            $nmStr = Fmt-Code $names
            Add-Line "- ``$($d.Name)/.env`` → $(@($names).Count) 個變數：$nmStr"
        }
    }
}
if (-not $envFound) { Add-Line '- 無' }

# ───────────────────────── 專案盤點 ─────────────────────────
Add-H '📁 專案盤點（Drive 根層 + 本機 dev）'
foreach ($root in @($DriveRoot, (Join-Path $HomeDir 'dev'))) {
    Add-Line ''
    Add-Line "### ``$root``"
    if (-not (Test-Path $root)) { Add-Line '❌ 路徑不存在'; continue }
    $dirs = @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) { Add-Line '（空的）'; continue }
    Add-Line ''
    Add-Line '| 資料夾 | git | 分支 | 未 commit | 最後 commit | node_modules |'
    Add-Line '|---|---|---|---|---|---|'
    foreach ($d in $dirs) {
        $isGit = Test-Path (Join-Path $d.FullName '.git')
        $branch = '—'; $dirty = '—'; $last = '—'
        if ($isGit -and (Test-Cmd 'git')) {
            try { $branch = (& git -C $d.FullName rev-parse --abbrev-ref HEAD 2>$null) } catch {}
            try { $dirty = @(& git -C $d.FullName status --porcelain 2>$null).Count } catch {}
            try { $last = (& git -C $d.FullName log -1 --format='%ad %s' --date=short 2>$null) } catch {}
            if ($last -and $last.Length -gt 45) { $last = $last.Substring(0,45) + '…' }
        }
        $nm = ''
        if (Test-Path (Join-Path $d.FullName 'node_modules')) { $nm = '✅' } else { $nm = '—' }
        $g = ''
        if ($isGit) { $g = '✅' } else { $g = '—' }
        Add-Line "| $($d.Name) | $g | $branch | $dirty | $last | $nm |"
    }
}

# ───────────────────────── Junction / 連結 ─────────────────────────
Add-H '🔗 Junction 與符號連結（家目錄）'
$links = @(Get-ChildItem $HomeDir -Force -ErrorAction SilentlyContinue |
           Where-Object { $_.LinkType -in @('Junction','SymbolicLink') })
if ($links.Count -eq 0) {
    Add-Line '無'
} else {
    Add-Line '| 名稱 | 類型 | 指向 |'
    Add-Line '|---|---|---|'
    foreach ($lnk in $links) {
        $tgt = ($lnk.Target -join ', ')
        Add-Line "| ``$($lnk.Name)`` | $($lnk.LinkType) | ``$tgt`` |"
    }
}

# ───────────────────────── 寫檔 ─────────────────────────
$Lines -join "`r`n" | Out-File -FilePath $OutFile -Encoding utf8
Write-Output "OK -> $OutFile"
Write-Output "lines: $($Lines.Count)"
