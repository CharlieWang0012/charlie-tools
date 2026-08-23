# birthday-card — 每日星座生日賀卡 + 教官公仔素材

每日星座生日賀卡系統的固定資產與工具。賀卡規格見 `規格書_V2.1.md`（含 2026-08-23 起的網頁發佈）。

產線：`birthday-card` skill 一條龍跑（抓運勢 → 生賀卡 → 開檔 → **發佈網頁**），排程 `ClaudeBirthdayCard` 每天 09:00 自動執行。

## 生日賀卡網頁 `publish_bday.py`

https://charliewang0012.github.io/line-image-host/ — 最近 30 張賀卡的手機版畫廊，可直接下載圖片。

```bash
python publish_bday.py            # 發佈最近 30 張並 push
python publish_bday.py --no-push  # 只產檔不 push
```

轉 JPG（1024/360）→ 同步進 `line-image-host` repo 的 `bday/` → 產 `index.html` → push。只留最近 30 張，原始 PNG 永遠在 GDrive `生日賀卡/`。

## 教官公仔（chizu = 千竹）

公仔為 Q 版年輕男性、短黑髮、外冷內熱親切笑容，穿休閒服（**永不**正式制服/軍警制服）。
gpt-image-2 不支援透明背景，所以一律走「**綠幕生圖 → rembg 去背**」兩步。

### 定裝去背檔（`assets/公仔素材/`）
每套服裝有：三表情合一去背檔 + 三張單表情（比讚👍/微笑😊/揮手👋）+ 綠幕原圖。

- **深藍版**：`chizu_公仔定裝去背_透明.png`
- **大地色版**（目前選定的標準公仔，卡其襯衫+深棕褲）：`chizu_公仔定裝去背_大地色_透明.png`
- **橘灰 hoodie 版**：`chizu_公仔定裝去背_橘灰hoodie_透明.png`

## 一鍵自動換裝 `dressup.py`

```bash
python dressup.py "服裝描述" 標籤
# 例: python dressup.py "紅綠配色的聖誕毛衣" 聖誕
```

流程：以大地色綠幕圖為底 → gpt-image-2 換裝 → rembg 去背 → 切三張單表情，全部存進 `assets/公仔素材/`。
對話中直接說「**公仔換成白襯衫**」「**幫公仔穿聖誕毛衣**」即可觸發。

需求：`openai`、`rembg`、`onnxruntime`、`Pillow`；`OPENAI_API_KEY` 取自 `~/.openai.env`。

## 用公仔生賀卡（臉部穩定法）

純文字生圖每次臉會略不同。要臉穩定，生賀卡時用 `draw.py --edit <單表情去背檔>` 以公仔當底圖。
