# charlie-tools — 我的班級工具總專案

## 對話開始時請先讀
進度與最近更動都在 Obsidian：`secondbrain/charlie-tools/工作筆記.md`

## 工作模式
- **加新工具**：對 Claude 說「我想做一個 XXX 工具」→ Claude 會建 `tools/<工具名>/` 子資料夾、引導我跟著 EP10 影片做
- **結束工作**：對 Claude 說「**收工**」→ 自動 commit + push + 更新 Obsidian 工作筆記
- **接續工作**：對 Claude 說「讀工作筆記、告訴我上次做到哪」

## 工作桌 + 三個家
- 📋 GDrive 工作桌：`G:\我的雲端硬碟\charlie-tools\`（自動跨電腦同步）
- 🐙 GitHub repo：`CharlieWang0012/charlie-tools`（公開，網頁的家）
- 📘 Obsidian 駕駛艙：`secondbrain/charlie-tools/工作筆記.md`（想法的家）
- 🔥 Firebase 專案：`my-teaching-tools`（或你建的，資料的家）

## 工具清單
（之後加新工具時會自動更新）
- **座標獵人** `tools/coordinate-hunter/` — 直角座標練習遊戲（11×11 格點、隨機 10 目標、60 秒倒數）。純前端範式 A。
- **生日賀卡 / 教官公仔** `tools/birthday-card/` — 每日星座生日賀卡的固定資產：教官公仔定裝去背檔（深藍/大地色/橘灰hoodie，三表情）＋ `dressup.py` 一鍵自動換裝（綠幕生圖→rembg 去背→切三張）。說「公仔換成XX」即觸發。

## 工作注意事項
- 學生資料一律去識別化（只用座號 + 班級代號）
- commit 訊息要寫清楚做了什麼 + 為什麼
- 收工前說「收工」讓 Claude 同步三方
