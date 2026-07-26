# machine-inventory — 跨機器狀態盤點

換主力機之後最麻煩的不是搬檔案，是**搞不清楚哪些東西在哪台才活著**。
chezmoi 已經幫我同步「設定檔」（四個 agent 的全域檔、skills、memory-shared），
但有三類東西**永遠同步不了**，只能逐台補：

1. **憑證登入態** — Firebase CLI、gcloud ADC、gh（token 在 keyring）
2. **排程工作** — 工作排程器的 XML 綁 SID，換機必須重建
3. **環境安裝** — Python 套件（faster-whisper／rembg／firebase-admin）、ffmpeg、auto-editor、VoxCPM2

這支腳本就是把「這台機器到底有什麼在運作」拍成一張快照，兩台各跑一次，再讓 Claude 比對缺口。

## 怎麼用

在**每一台**機器的 PowerShell 執行同一支腳本（不寫死使用者名，走 `$env:USERPROFILE`）：

```bash
powershell -ExecutionPolicy Bypass -File "G:\我的雲端硬碟\charlie-tools\tools\machine-inventory\inventory.ps1"
```

輸出：`G:\我的雲端硬碟\machine-state\<電腦名>-<帳號>.md`（在 Drive 上，自動跨機同步）

跑完之後，對 Claude 說：

> **比對機器狀態**

Claude 會讀 `machine-state\` 底下所有快照，列出「A 有 B 沒有」的缺口清單並排優先序。

## 快照收集了什麼

| 區塊 | 內容 |
|---|---|
| 機器身份 | 電腦名／帳號／OS／記憶體／顯示卡 |
| ⏰ 排程工作 | 自訂排程（排除 Microsoft 內建）＋觸發時間＋執行內容＋**上次結果代碼**＋啟動資料夾 |
| 🤖 Claude Code | 全域／專案層 MCP servers、skills 清單、hooks、memory 檔數與 junction 是否接好 |
| 🧩 其他 AI agent | Codex／OpenCode／Antigravity／Drive 共用全域檔是否存在＋更新時間 |
| 🛠️ CLI 工具 | 17 個常用 CLI 的有無、版本、路徑＋npm 全域套件 |
| 🐍 Python 套件 | 18 個關鍵套件的有無與版本 |
| 🔑 憑證 | 憑證檔有無＋**實際跑狀態指令**確認登入（比看檔案準）＋各專案 `.env` 變數名 |
| 📁 專案盤點 | Drive 根層與本機 `dev\` 每個資料夾：是否 git repo／分支／未 commit 數／最後 commit／有無 node_modules |
| 🔗 Junction | 家目錄的 junction 與指向（vault、memory 最常斷在這） |

**安全**：憑證一律只記「有／無」與檔案時間，`.env` 只記變數**名稱**不記值。輸出目錄 `machine-state\` 刻意放在 charlie-tools repo **外面**，不會被推上 public GitHub。

## 維護時的坑（都踩過了）

- **腳本檔必須存成 UTF-8 with BOM。** Windows PowerShell 5.1 讀無 BOM 的 UTF-8 會把中文當 Big5，直接爆一堆 ParserError。用其他工具改完檔一定要重新加 BOM。
- **PowerShell 變數不分大小寫。** 累積器原本叫 `$L`，被 `foreach ($l in $links)` 整個蓋成 DirectoryInfo，結果前面收集的 188 行全部丟掉、只寫出一行路徑。所以累積器叫 `$Lines`、迴圈變數叫 `$lnk`。
- **PS 5.1 的字串內插 `$( )` 裡不能再用同型引號**（`"...$(... "..." ...)"` 會 parse error）。要嘛先算成變數，要嘛用 `Fmt-Code` 這種 helper。
- **`gh auth status` 的參數要 splatting**（`@('auth','status')`），整串當一個參數傳會失敗，然後誤報「未登入」。而且它的輸出走 stderr，要 `2>&1`。
- **`gh` 的 token 存在 Windows keyring，不在 `hosts.yml`**；`hosts.yml` 也不在 `~/.config/gh`，而在 `%APPDATA%\GitHub CLI\`。判斷登入一律跑 `gh auth status`，別看檔案。
- **`.claude\projects\<slug>\memory` 是 junction 指向 `memory-shared`**，`Get-ChildItem -Recurse` 不會跟進去，會誤報 0 個。以 `memory-shared` 的數字為準。
- 刻意**不做 `git fetch`**、不打網路，純本地狀態，所以跑完只要十幾秒。
