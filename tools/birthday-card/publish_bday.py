#!/usr/bin/env python3
"""生日賀卡網頁發佈器。

把 GDrive `生日賀卡/` 裡最近 N 張賀卡轉成網頁用 JPG，
同步進 line-image-host repo 並產生 GitHub Pages 畫廊首頁，最後 push。

出差時打開 https://charliewang0012.github.io/line-image-host/ 就能看／下載當天的卡。

用法：
    python publish_bday.py             # 發佈最近 30 張
    python publish_bday.py --keep 45   # 改保留張數
    python publish_bday.py --no-push   # 只產檔不 push（本機預覽）
"""
import argparse
import html
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import yaml
from PIL import Image

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

SRC_DIR = Path("G:/我的雲端硬碟/生日賀卡")
REPO = Path("G:/我的雲端硬碟/line-image-host")
BDAY_DIR = REPO / "bday"
SITE_URL = "https://charliewang0012.github.io/line-image-host/"

FULL_SIZE = 1024   # 網頁大圖邊長
THUMB_SIZE = 360   # 縮圖邊長
FULL_Q = 90
THUMB_Q = 80

# 生日賀卡_處女座_0823_20260823_091455.png / 生日賀卡_獅子_0815_郭學長_20260815_095657.png
NAME_RE = re.compile(r"^生日賀卡_([^_]+?)座?_.*?(\d{8})_(\d{6})\.png$")

def read_md(path):
    """讀 md 文字卡：回傳 frontmatter 欄位，外加 body（frontmatter 底下的原文）。

    格式不對就回 None（呼叫端會印警告跳過）。
    """
    text = path.read_text(encoding="utf-8")
    if not text.lstrip().startswith("---"):
        return None
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None
    meta = yaml.safe_load(parts[1])
    if not isinstance(meta, dict) or not meta.get("date") or not meta.get("zodiac"):
        return None
    meta["day"] = str(meta["date"]).replace("-", "")
    meta["body"] = parts[2].strip()
    return meta


def collect_cards(keep):
    """掃來源資料夾，每天只留一張，回傳最近 keep 張（新→舊）。

    同一天若圖片卡與 md 文字卡都在，**圖片卡優先**（文字卡只是沒生圖時的頂替）。
    """
    by_day = {}
    for p in SRC_DIR.glob("生日賀卡_*.png"):
        m = NAME_RE.match(p.name)
        if not m:
            print(f"  [!] 檔名不符格式，跳過：{p.name}")
            continue
        zodiac, day, hhmmss = m.group(1) + "座", m.group(2), m.group(3)
        cur = by_day.get(day)
        if cur is None or hhmmss > cur["time"]:
            by_day[day] = {"kind": "img", "day": day, "time": hhmmss,
                           "zodiac": zodiac, "path": p}

    for p in sorted(SRC_DIR.glob("生日賀卡_*.md")):
        meta = read_md(p)
        if meta is None:
            print(f"  [!] md frontmatter 讀不到 date/zodiac，跳過：{p.name}")
            continue
        day = meta["day"]
        if by_day.get(day, {}).get("kind") == "img":
            continue  # 當天已有圖片卡，文字卡不蓋掉它
        by_day[day] = {"kind": "md", "day": day, "time": "000000",
                       "zodiac": meta["zodiac"], "path": p, "meta": meta}

    cards = sorted(by_day.values(), key=lambda c: c["day"], reverse=True)
    return cards[:keep]


def build_assets(cards):
    """產出網頁用 JPG（大圖＋縮圖），並清掉輪替出去的舊檔。"""
    BDAY_DIR.mkdir(parents=True, exist_ok=True)
    wanted = set()
    for c in cards:
        if c["kind"] == "md":
            dst = BDAY_DIR / f"bday-{c['day']}.md"
            wanted.add(dst.name)
            c["md"] = dst.name
            dst.write_text(c["path"].read_text(encoding="utf-8"), encoding="utf-8")
            print(f"  [md ] {c['day']} {c['zodiac']} -> {dst.name}（文字卡，未生圖）")
            continue
        full = BDAY_DIR / f"bday-{c['day']}.jpg"
        thumb = BDAY_DIR / f"thumb-{c['day']}.jpg"
        wanted.update({full.name, thumb.name})
        c["full"] = full.name
        c["thumb"] = thumb.name
        if full.exists() and thumb.exists():
            continue
        with Image.open(c["path"]) as im:
            im = im.convert("RGB")
            big = im.copy()
            big.thumbnail((FULL_SIZE, FULL_SIZE), Image.LANCZOS)
            big.save(full, "JPEG", quality=FULL_Q, optimize=True)
            small = im.copy()
            small.thumbnail((THUMB_SIZE, THUMB_SIZE), Image.LANCZOS)
            small.save(thumb, "JPEG", quality=THUMB_Q, optimize=True)
        print(f"  [img] {c['day']} {c['zodiac']} -> {full.name} ({full.stat().st_size // 1024} KB)")
    for pattern in ("*.jpg", "*.md"):
        for old in BDAY_DIR.glob(pattern):
            if old.name not in wanted:
                old.unlink()
                print(f"  [del] 輪替移除 {old.name}")
    return wanted


def fmt_day(day):
    return f"{day[:4]}.{day[4:6]}.{day[6:]}"


def render_html(cards):
    items = []
    for c in cards:
        head = ("{"
                f'day:"{fmt_day(c["day"])}",'
                f'raw:"{c["day"]}",'
                f'z:"{html.escape(c["zodiac"])}",'
                f'kind:"{c["kind"]}",')
        if c["kind"] == "md":
            body = json.dumps(c["meta"]["body"], ensure_ascii=False)
            items.append(head + f'md:"bday/{c["md"]}",text:{body}' + "}")
        else:
            items.append(head + f'full:"bday/{c["full"]}",thumb:"bday/{c["thumb"]}"' + "}")
    data = "[\n" + ",\n".join(items) + "\n]"
    updated = datetime.now().strftime("%Y-%m-%d %H:%M")
    return (HTML_TMPL
            .replace("__CARDS__", data)
            .replace("__UPDATED__", updated)
            .replace("__COUNT__", str(len(cards)))
            .replace("__SITE__", SITE_URL))


def git_sync(push=True):
    def run(*args):
        return subprocess.run(args, cwd=REPO, text=True, capture_output=True)

    run("git", "add", "-A")
    st = run("git", "status", "--porcelain")
    if not st.stdout.strip():
        print("  [=] 沒有變更，不用 commit。")
        return
    stamp = datetime.now().strftime("%Y-%m-%d")
    r = run("git", "commit", "-m", f"birthday card site {stamp}")
    if r.returncode != 0 and "nothing to commit" not in r.stdout:
        raise RuntimeError(f"git commit 失敗：{r.stdout}{r.stderr}")
    print("  [ok] 已 commit")
    if push:
        r = run("git", "push")
        if r.returncode != 0:
            raise RuntimeError(f"git push 失敗：{r.stdout}{r.stderr}")
        print("  [ok] 已 push，GitHub Pages 約 1 分鐘後生效")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", type=int, default=30, help="網頁保留幾張（預設 30）")
    ap.add_argument("--no-push", action="store_true", help="只產檔不 push")
    args = ap.parse_args()

    if not SRC_DIR.is_dir():
        raise SystemExit(f"找不到賀卡資料夾：{SRC_DIR}")
    if not (REPO / ".git").is_dir():
        raise SystemExit(f"找不到 repo：{REPO}")

    cards = collect_cards(args.keep)
    if not cards:
        raise SystemExit("沒有可發佈的賀卡。")
    print(f"共 {len(cards)} 張，最新 {fmt_day(cards[0]['day'])} {cards[0]['zodiac']}")

    build_assets(cards)
    # GitHub Pages 預設會跑 Jekyll，把 .md 當來源檔轉成 HTML、不提供原始檔，
    # 文字卡的 .md 會 404。.nojekyll 關掉這個處理，檔案就原樣送出。
    nojekyll = REPO / ".nojekyll"
    if not nojekyll.exists():
        nojekyll.write_text("", encoding="utf-8")
        print("  [ok] 補上 .nojekyll（否則 .md 會被 Jekyll 吃掉）")
    (REPO / "index.html").write_text(render_html(cards), encoding="utf-8")
    print("  [ok] index.html 已產生")
    git_sync(push=not args.no_push)
    print(f"\n網址：{SITE_URL}")


HTML_TMPL = """<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>千竹 生日賀卡</title>
<style>
  :root{
    --navy:#0f2557; --orange:#ff8c1a; --orange-2:#ffb35c;
    --ink:#f4f7ff; --muted:#a9bbe0; --card:#173268; --line:rgba(255,255,255,.12);
  }
  *{box-sizing:border-box}
  body{
    margin:0; background:linear-gradient(180deg,#0b1c44 0%,var(--navy) 45%,#0b1c44 100%);
    color:var(--ink); font-family:"Noto Sans TC","PingFang TC","Microsoft JhengHei",system-ui,sans-serif;
    -webkit-text-size-adjust:100%; min-height:100vh;
  }
  .wrap{max-width:760px;margin:0 auto;padding:20px 16px 48px}
  header{text-align:center;padding:8px 0 18px}
  h1{margin:0;font-size:26px;letter-spacing:2px}
  h1 span{color:var(--orange)}
  .sub{margin:6px 0 0;color:var(--muted);font-size:13px}
  .hero{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:14px;
        box-shadow:0 12px 32px rgba(0,0,0,.35)}
  .hero img{width:100%;height:auto;display:block;border-radius:12px;background:#0b1c44}
  .hero img[hidden]{display:none}
  /* 文字卡：當天沒生圖時頂替，直接顯示 md 原文 */
  .mdbox[hidden]{display:none}
  .mdbox{margin:0;border-radius:12px;padding:18px 16px;background:#0b1c44;
         border:1px solid var(--line);color:var(--ink);
         font-family:ui-monospace,"SFMono-Regular",Menlo,Consolas,
                     "Noto Sans TC","PingFang TC","Microsoft JhengHei",monospace;
         font-size:13px;line-height:1.9;white-space:pre-wrap;word-break:break-word;
         overflow-x:auto;-webkit-overflow-scrolling:touch}
  .grid .tmd{display:flex;flex-direction:column;align-items:center;justify-content:center;
             aspect-ratio:1;background:#12306e;border:1px solid rgba(255,179,92,.3);
             border-radius:10px;font-size:22px;line-height:1}
  .grid .tmd em{font-style:normal;font-size:11px;color:var(--orange-2);margin-top:5px;
                letter-spacing:1px}
  .meta{display:flex;align-items:baseline;gap:10px;margin:12px 2px 10px;flex-wrap:wrap}
  .date{font-size:22px;font-weight:700}
  .zodiac{background:rgba(255,140,26,.16);color:var(--orange-2);border:1px solid rgba(255,140,26,.4);
          border-radius:999px;padding:3px 12px;font-size:13px}
  .btns{display:flex;gap:10px;flex-wrap:wrap}
  .btn{flex:1 1 140px;text-align:center;text-decoration:none;border-radius:12px;padding:13px 14px;
       font-size:15px;font-weight:600;border:1px solid transparent;cursor:pointer;transition:.15s;
       font-family:inherit}
  .btn-main{background:var(--orange);color:#2a1400}
  .btn-main:active{background:var(--orange-2)}
  .btn-ghost{background:transparent;color:var(--ink);border-color:var(--line)}
  .hint{color:var(--muted);font-size:12px;margin:10px 2px 0;line-height:1.6}
  h2{font-size:15px;color:var(--muted);font-weight:600;margin:30px 2px 12px;letter-spacing:1px}
  .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(88px,1fr));gap:10px}
  .grid button{padding:0;border:2px solid transparent;background:none;border-radius:12px;
               cursor:pointer;line-height:0;position:relative}
  .grid img{width:100%;height:auto;border-radius:10px;display:block}
  .grid .d{position:absolute;left:0;right:0;bottom:0;
           background:linear-gradient(transparent,rgba(0,0,0,.75));color:#fff;font-size:11px;
           line-height:1;padding:14px 4px 5px;border-radius:0 0 10px 10px;text-align:center}
  .grid button[aria-current="true"]{border-color:var(--orange)}
  footer{color:var(--muted);font-size:12px;text-align:center;margin-top:34px;line-height:1.8}
  footer .home{display:inline-block;margin-bottom:6px;color:var(--orange-2);text-decoration:none;
               border:1px solid var(--line);border-radius:999px;padding:6px 14px;font-size:13px}
  .toast{position:fixed;left:50%;bottom:26px;transform:translate(-50%,20px);background:#fff;
         color:#0f2557;padding:10px 18px;border-radius:999px;font-size:14px;font-weight:600;
         opacity:0;pointer-events:none;transition:.25s;box-shadow:0 8px 24px rgba(0,0,0,.3)}
  .toast.on{opacity:1;transform:translate(-50%,0)}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>千竹 <span>生日賀卡</span></h1>
    <p class="sub">每天 09:00 自動更新・最近 __COUNT__ 張</p>
  </header>

  <div class="hero">
    <img id="hero" src="" alt="生日賀卡">
    <pre class="mdbox" id="mdbox" hidden></pre>
    <div class="meta">
      <span class="date" id="d"></span>
      <span class="zodiac" id="z"></span>
    </div>
    <div class="btns">
      <a class="btn btn-main" id="dl" href="" download>下載圖片</a>
      <button class="btn btn-ghost" id="cp">複製圖片網址</button>
    </div>
    <p class="hint" id="hint"></p>
  </div>

  <h2>最近的賀卡</h2>
  <div class="grid" id="grid"></div>

  <footer>
    <a class="home" href="https://charliewang0012.github.io/">← 連結中心</a><br>
    更新時間 __UPDATED__<br>
    只保留最近 __COUNT__ 張，更早的原始檔在本機「我的雲端硬碟／生日賀卡」。
  </footer>
</div>
<div class="toast" id="toast">已複製網址</div>

<script>
const CARDS = __CARDS__;
const SITE = "__SITE__";
const hero = document.getElementById('hero'), dEl = document.getElementById('d'),
      zEl = document.getElementById('z'), dl = document.getElementById('dl'),
      grid = document.getElementById('grid'), toast = document.getElementById('toast'),
      mdbox = document.getElementById('mdbox'), cp = document.getElementById('cp'),
      hint = document.getElementById('hint');
let cur = 0;

const fileOf = c => c.kind === 'md' ? c.md : c.full;

function show(i){
  cur = i;
  const c = CARDS[i];
  const isMd = c.kind === 'md';
  hero.hidden = isMd;
  mdbox.hidden = !isMd;
  if (isMd) {
    mdbox.textContent = c.text;
  } else {
    hero.src = c.full;
    hero.alt = c.day + ' ' + c.z + ' 生日賀卡';
  }
  dEl.textContent = c.day;
  zEl.textContent = c.z;
  dl.href = fileOf(c);
  dl.setAttribute('download', 'birthday-' + c.raw + (isMd ? '.md' : '.jpg'));
  dl.textContent = isMd ? '下載文字檔' : '下載圖片';
  cp.textContent = isMd ? '複製檔案網址' : '複製圖片網址';
  hint.innerHTML = isMd
    ? '這天沒有生圖，直接顯示 md 原文。要整張圖片轉傳的話，補上生圖額度後重跑就會換回來。'
    : '手機若沒跳下載，直接<b>長按圖片</b>→「加入照片」也可以存檔。';
  [...grid.children].forEach((b, k) => b.setAttribute('aria-current', k === i ? 'true' : 'false'));
}

CARDS.forEach((c, i) => {
  const b = document.createElement('button');
  const face = c.kind === 'md'
    ? '<span class="tmd">🎂<em>' + c.z + '</em></span>'
    : '<img loading="lazy" src="' + c.thumb + '" alt="' + c.day + '">';
  b.innerHTML = face + '<span class="d">' + c.day.slice(5) + '</span>';
  b.onclick = () => { show(i); window.scrollTo({top:0, behavior:'smooth'}); };
  grid.appendChild(b);
});

cp.onclick = async () => {
  const url = SITE + fileOf(CARDS[cur]);
  try { await navigator.clipboard.writeText(url); }
  catch (e) {
    const t = document.createElement('textarea');
    t.value = url; document.body.appendChild(t); t.select();
    document.execCommand('copy'); t.remove();
  }
  toast.classList.add('on');
  setTimeout(() => toast.classList.remove('on'), 1500);
};

show(0);
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
