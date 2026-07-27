# msi-bundle-exam-folders.ps1
# 把 C:\2026opencode 底下兩個無版控、只存在 MSI 本機的考古題資料夾
# 打包送上 Drive，讓 Acer 補進 GitHub 備份。
#
# 背景：這兩個資料夾很小（7.75MB / 107KB），2026-07-27 從 opencode 桌面版
# 專案清單挖出來的，跟今天發現的 notype／2026-crypto-scan 是同一種風險——
# 無版控、單機獨存，MSI 退役或硬碟壞了就沒了。
#
# 在 MSI 的 PowerShell 執行：
#   powershell -ExecutionPolicy Bypass -File "G:\我的雲端硬碟\charlie-tools\tools\machine-inventory\msi-bundle-exam-folders.ps1"

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

$OutDir = 'G:\我的雲端硬碟\machine-state\_msi-transfer\exam-folders'
New-Item -ItemType Directory -Force $OutDir | Out-Null

$targets = @(
    @{ Path = 'C:\2026opencode\國中教育會考數學科歷屆試題'; Name = '國中教育會考數學科歷屆試題' },
    @{ Path = 'C:\2026opencode\郵局歷屆試題';               Name = '郵局歷屆試題' }
)

foreach ($t in $targets) {
    if (-not (Test-Path $t.Path)) {
        Write-Output "跳過（不存在）: $($t.Name)"
        continue
    }
    $dst = Join-Path $OutDir $t.Name
    New-Item -ItemType Directory -Force $dst | Out-Null
    Copy-Item (Join-Path $t.Path '*') $dst -Recurse -Force -ErrorAction SilentlyContinue
    $files = @(Get-ChildItem $dst -Recurse -File -ErrorAction SilentlyContinue)
    $sz = 0
    foreach ($f in $files) { $sz += $f.Length }
    Write-Output "已複製: $($t.Name) — $($files.Count) 檔，$([math]::Round($sz/1MB,2)) MB"
}

Write-Output ""
Write-Output "OK -> $OutDir"
