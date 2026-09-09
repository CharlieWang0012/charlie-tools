#!/usr/bin/env python3
"""連結中心產生器。

把 links.json 產成 index.html，同步進 charliewang0012.github.io repo 並 push。
網址：https://charliewang0012.github.io/

要新增／修改連結：編 links.json，再跑一次這支。

用法：
    python build_hub.py            # 產檔 + push
    python build_hub.py --no-push  # 只產檔（本機預覽）
    python build_hub.py --check    # 順便檢查每個連結是否還活著
"""
import argparse
import html
import json
import subprocess
import sys
import urllib.request
from datetime import datetime
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
except Exception:
    pass

HERE = Path(__file__).parent
LINKS = HERE / "links.json"
REPO = Path("G:/我的雲端硬碟/charliewang0012.github.io")
SITE_URL = "https://charliewang0012.github.io/"


def check(url, timeout=12):
    req = urllib.request.Request(url, headers={"User-Agent": "link-hub-check/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status
    except Exception as e:
        return getattr(e, "code", None) or str(e)[:40]


def render(data):
    sections = []
    for sec in data["sections"]:
        cards = []
        for it in sec["items"]:
            # 顯示網域＋路徑：同網域下的不同頁（如 github.io/line-image-host/）
            # 只印網域會長得跟連結中心自己一模一樣，看起來像連錯地方。
            domain = it["url"].split("//", 1)[-1].rstrip("/")
            cards.append(
                '<a class="card" href="{url}" target="_blank" rel="noopener">'
                '<span class="ico">{icon}</span>'
                '<span class="txt"><b>{name}</b><em>{desc}</em>'
                '<small>{domain}</small></span>'
                '<span class="arrow">›</span></a>'.format(
                    url=html.escape(it["url"]),
                    icon=html.escape(it.get("icon", "🔗")),
                    name=html.escape(it["name"]),
                    desc=html.escape(it.get("desc", "")),
                    domain=html.escape(domain),
                )
            )
        sections.append(
            '<section id="{sid}"><h2>{name}<span class="n">{n}</span></h2>'
            '<div class="cards">{cards}</div></section>'.format(
                sid=html.escape(sec["id"]), name=html.escape(sec["name"]),
                n=len(sec["items"]), cards="".join(cards))
        )
    return (HTML_TMPL
            .replace("__TITLE__", html.escape(data["title"]))
            .replace("__SUBTITLE__", html.escape(data.get("subtitle", "")))
            .replace("__SECTIONS__", "".join(sections))
            .replace("__UPDATED__", datetime.now().strftime("%Y-%m-%d %H:%M")))


def git_sync(push=True):
    def run(*args):
        return subprocess.run(args, cwd=REPO, text=True, capture_output=True)

    run("git", "add", "-A")
    if not run("git", "status", "--porcelain").stdout.strip():
        print("  [=] 沒有變更。")
        return
    r = run("git", "commit", "-m", f"link hub {datetime.now():%Y-%m-%d}")
    if r.returncode != 0 and "nothing to commit" not in r.stdout:
        raise RuntimeError(f"git commit 失敗：{r.stdout}{r.stderr}")
    print("  [ok] 已 commit")
    if push:
        r = run("git", "push")
        if r.returncode != 0 and "no upstream branch" in (r.stdout + r.stderr):
            r = run("git", "push", "-u", "origin", "HEAD")
        if r.returncode != 0:
            raise RuntimeError(f"git push 失敗：{r.stdout}{r.stderr}")
        print("  [ok] 已 push，GitHub Pages 約 1 分鐘後生效")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-push", action="store_true")
    ap.add_argument("--check", action="store_true", help="檢查連結是否還活著")
    args = ap.parse_args()

    data = json.loads(LINKS.read_text(encoding="utf-8"))
    total = sum(len(s["items"]) for s in data["sections"])
    print(f"共 {total} 個連結")

    if args.check:
        for sec in data["sections"]:
            for it in sec["items"]:
                print(f"  {check(it['url'])}\t{it['name']}\t{it['url']}")

    if not (REPO / ".git").is_dir():
        raise SystemExit(f"找不到 repo：{REPO}")
    (REPO / "index.html").write_text(render(data), encoding="utf-8")
    print("  [ok] index.html 已產生")
    git_sync(push=not args.no_push)
    print(f"\n網址：{SITE_URL}")


HTML_TMPL = """<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>__TITLE__</title>
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
  .wrap{max-width:720px;margin:0 auto;padding:26px 16px 48px}
  header{text-align:center;padding:6px 0 22px}
  h1{margin:0;font-size:27px;letter-spacing:2px}
  h1 span{color:var(--orange)}
  .sub{margin:8px 0 0;color:var(--muted);font-size:13px}
  section{margin-bottom:28px}
  h2{display:flex;align-items:center;gap:8px;font-size:14px;color:var(--muted);
     font-weight:600;margin:0 2px 12px;letter-spacing:1px}
  h2 .n{background:rgba(255,255,255,.08);border-radius:999px;padding:1px 8px;font-size:11px}
  .cards{display:flex;flex-direction:column;gap:10px}
  .card{display:flex;align-items:center;gap:13px;text-decoration:none;color:inherit;
        background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 15px;
        transition:.15s;box-shadow:0 6px 18px rgba(0,0,0,.22)}
  .card:hover{border-color:rgba(255,140,26,.55);transform:translateY(-1px)}
  .card:active{transform:scale(.99)}
  .ico{font-size:24px;line-height:1;flex:0 0 auto;width:34px;text-align:center}
  .txt{display:flex;flex-direction:column;gap:3px;min-width:0;flex:1}
  .txt b{font-size:16px;font-weight:700}
  .txt em{font-style:normal;font-size:13px;color:var(--muted);line-height:1.5}
  .txt small{font-size:11px;color:rgba(169,187,224,.6);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .arrow{color:var(--orange);font-size:22px;flex:0 0 auto;line-height:1}
  footer{color:var(--muted);font-size:12px;text-align:center;margin-top:30px;line-height:1.8}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <h1>__TITLE__</h1>
    <p class="sub">__SUBTITLE__</p>
  </header>
  __SECTIONS__
  <footer>更新時間 __UPDATED__<br>要加連結：編 charlie-tools/tools/link-hub/links.json 再跑 build_hub.py</footer>
</div>
</body>
</html>
"""

if __name__ == "__main__":
    main()
