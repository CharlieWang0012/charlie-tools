# msi-bundle-repos.ps1
# 把「只存在於 MSI 本機、GitHub 上沒有」的 repo 打包成 git bundle 放到 Drive，
# 讓 Acer 用已登入的 gh 建 private repo 並推上去（MSI 的 gh 未登入，那台推不動）。
#
# 在 MSI 的 PowerShell 執行：
#   powershell -ExecutionPolicy Bypass -File "G:\我的雲端硬碟\charlie-tools\tools\machine-inventory\msi-bundle-repos.ps1"
#
# 為什麼用 bundle 而不是複製整包：
#   C:\ccwang-aiagent 有 5.3 GB，其中 5 GB 是 VoxCPM2 的 .venv（torch CUDA DLL）。
#   bundle 只含 git 物件（已 commit 的內容），被 .gitignore 排除的 .venv 不會進去，
#   但完整保留所有分支與歷史。
#
# ⚠️ bundle 只含「已 commit」的東西，所以這支腳本額外保存未 commit 的變更：
#     - 已追蹤檔的修改 → uncommitted.patch
#     - 未追蹤的新檔   → untracked\ 目錄（自動跳過被 gitignore 的，才不會把 .venv 撈進來）

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$HomeDir   = $env:USERPROFILE
$DriveRoot = 'G:\我的雲端硬碟'
$OutDir    = Join-Path $DriveRoot 'machine-state\_msi-transfer\repos'
$Report    = Join-Path $OutDir 'bundle-report.md'

New-Item -ItemType Directory -Force $OutDir | Out-Null

$Lines = New-Object System.Collections.Generic.List[string]
function Add-Line($s) { $Lines.Add($s) }

Add-Line '# MSI repo 打包報告'
Add-Line ''
Add-Line "> 產生於 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Add-Line ''

# 要處理的目標：前三個是 git repo，最後一個沒有版控
$targets = @(
    @{ Path = 'C:\ccwang-aiagent\2026_calude_ VoxCPM2'; Name = 'voxcpm2';         Git = $true  },
    @{ Path = 'C:\ccwang-aiagent\notype';               Name = 'notype';          Git = $true  },
    @{ Path = 'C:\ccwang-aiagent\notype-teacher';       Name = 'notype-teacher';  Git = $true  },
    @{ Path = (Join-Path $HomeDir 'dev\2026-crypto-scan'); Name = '2026-crypto-scan'; Git = $false }
)

foreach ($t in $targets) {
    $p = $t.Path
    Add-Line ''
    Add-Line "## $($t.Name)"
    Add-Line ''
    Add-Line "來源：``$p``"
    Add-Line ''

    if (-not (Test-Path $p)) {
        Add-Line '❌ 路徑不存在，跳過'
        continue
    }

    if (-not $t.Git) {
        # 沒有版控：整包複製（只有 13 MB），到 Acer 再 git init
        $dst = Join-Path $OutDir $t.Name
        New-Item -ItemType Directory -Force $dst | Out-Null
        Copy-Item (Join-Path $p '*') $dst -Recurse -Force -ErrorAction SilentlyContinue
        $files = @(Get-ChildItem $dst -Recurse -File -ErrorAction SilentlyContinue)
        $sz = 0
        foreach ($f in $files) { $sz += $f.Length }
        Add-Line "✅ 無版控 → 整包複製 $($files.Count) 檔、$([math]::Round($sz/1MB,1)) MB 到 ``repos\$($t.Name)\``"
        Add-Line ''
        Add-Line '（到 Acer 後 `git init` + 建 private repo + 首次 commit）'
        continue
    }

    if (-not (Test-Path (Join-Path $p '.git'))) {
        Add-Line '⚠️ 標記為 git repo 但找不到 `.git`，改成整包複製'
        continue
    }

    # ── 現況 ──
    $branch = & git -C $p rev-parse --abbrev-ref HEAD 2>$null
    $commits = & git -C $p rev-list --all --count 2>$null
    $remotes = @(& git -C $p remote -v 2>$null)
    $dirty = @(& git -C $p status --porcelain 2>$null)

    Add-Line "- 分支：``$branch``，commit 數：$commits"
    if (@($remotes).Count -eq 0) {
        Add-Line '- remote：**無**（所以 GitHub 上沒有備份）'
    } else {
        Add-Line "- remote：$(@($remotes) -join ' / ')"
    }
    Add-Line "- 未 commit 變更：$(@($dirty).Count) 項"

    # ── 打包 bundle（--all 含所有分支與 tag）──
    $bundle = Join-Path $OutDir "$($t.Name).bundle"
    & git -C $p bundle create "$bundle" --all 2>&1 | Out-Null
    if (Test-Path $bundle) {
        $bs = (Get-Item $bundle).Length
        Add-Line "- ✅ bundle：``$($t.Name).bundle`` $([math]::Round($bs/1MB,1)) MB"
        if ($bs -gt 500MB) {
            Add-Line '  - ⚠️ **bundle 超過 500 MB** → 很可能有大檔被 commit 進歷史（.venv 沒被 gitignore？），到 Acer 要先確認再推 GitHub'
        }
    } else {
        Add-Line '- ❌ bundle 產生失敗'
    }

    # ── 未 commit 的變更也要保住 ──
    if (@($dirty).Count -gt 0) {
        $patch = Join-Path $OutDir "$($t.Name)-uncommitted.patch"
        & git -C $p diff HEAD 2>$null | Out-File $patch -Encoding utf8
        if ((Test-Path $patch) -and (Get-Item $patch).Length -gt 0) {
            Add-Line "- ✅ 已追蹤檔的修改 → ``$($t.Name)-uncommitted.patch``"
        } else {
            Remove-Item $patch -ErrorAction SilentlyContinue
        }

        # 未追蹤的新檔（--exclude-standard 會自動跳過被 gitignore 的，例如 .venv）
        $untracked = @(& git -C $p ls-files --others --exclude-standard 2>$null)
        if (@($untracked).Count -gt 0) {
            $udst = Join-Path $OutDir "$($t.Name)-untracked"
            New-Item -ItemType Directory -Force $udst | Out-Null
            $copied = 0
            foreach ($rel in $untracked) {
                $src = Join-Path $p $rel
                if (-not (Test-Path $src)) { continue }
                $dstFile = Join-Path $udst $rel
                New-Item -ItemType Directory -Force (Split-Path $dstFile -Parent) | Out-Null
                Copy-Item $src $dstFile -Force -ErrorAction SilentlyContinue
                $copied++
            }
            Add-Line "- ✅ 未追蹤新檔 $copied 個 → ``$($t.Name)-untracked\``"
        }
    }
}

Add-Line ''
Add-Line '---'
Add-Line ''
Add-Line '接下來在 Acer：`git clone <bundle>` → 建 private repo → push → 套用 patch 與未追蹤檔。'

$Lines -join "`r`n" | Out-File -FilePath $Report -Encoding utf8
Write-Output "OK -> $Report"
Get-ChildItem $OutDir | ForEach-Object { "  $($_.Name)" }
