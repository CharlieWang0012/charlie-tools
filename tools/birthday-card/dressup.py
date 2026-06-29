"""公仔一鍵自動換裝：綠幕底圖 -> AI 換裝 -> rembg 去背 -> 切三張單表情。

用法:
  python dressup.py "服裝描述" 標籤
  例: python dressup.py "暖酒紅色針織毛衣" 酒紅
      python dressup.py "紅綠配色的聖誕毛衣" 聖誕

產出(全部存進 assets/公仔素材/):
  chizu_公仔三表情_<標籤>_綠幕_<時間>.png   綠幕原圖(留底)
  chizu_公仔定裝去背_<標籤>_透明.png          三表情合一去背檔
  chizu_公仔_<標籤>_比讚/微笑/揮手_透明.png   三張單表情去背檔

需求: openai, rembg, onnxruntime, Pillow；OPENAI_API_KEY 取自 ~/.openai.env
"""
import os, sys, base64
from pathlib import Path
from datetime import datetime

def load_env_from_file(p):
    if not p.exists(): return
    for line in open(p, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
load_env_from_file(Path.home() / ".openai.env")

from openai import OpenAI
from rembg import remove
from PIL import Image

HERE  = Path(__file__).resolve().parent
ASSET = HERE / "assets" / "公仔素材"
# 預設換裝底圖 = 大地色定裝(目前選定的標準公仔)。換別套當底圖改這行即可。
BASE  = ASSET / "chizu_公仔三表情_大地色_綠幕_20260629_203350.png"

def main():
    if len(sys.argv) < 2:
        print('用法: python dressup.py "服裝描述" 標籤'); sys.exit(1)
    outfit = sys.argv[1]
    tag    = sys.argv[2] if len(sys.argv) > 2 else "新裝"
    stamp  = datetime.now().strftime("%Y%m%d_%H%M%S")

    client = OpenAI()
    prompt = (f"保持畫面中『同一位』Q版教官公仔不變：同樣的臉、髮型、三個姿勢(比讚/微笑/揮手)、"
              f"以及完全純一致的亮綠色綠幕背景(#00B140)都不要改。只把他身上的休閒上衣換成：{outfit}。"
              f"上衣保持素面、不可有任何文字字母數字或標誌；不要小熊或任何動物；身上與頭髮不可有綠色。")
    print(f"AI 換裝中：{outfit}", file=sys.stderr)
    r = client.images.edit(model="gpt-image-2", image=open(BASE, "rb"),
                           prompt=prompt, size="1024x1024", quality="medium", n=1)
    green = ASSET / f"chizu_公仔三表情_{tag}_綠幕_{stamp}.png"
    green.write_bytes(base64.b64decode(r.data[0].b64_json))
    print("  [綠幕]", green)

    img = Image.open(green).convert("RGBA")
    out = remove(img)
    sheet = ASSET / f"chizu_公仔定裝去背_{tag}_透明.png"
    out.save(sheet); print("  [去背]", sheet)

    w, h = out.size; third = w // 3
    for i, nm in enumerate(["比讚", "微笑", "揮手"]):
        box = (i * third, 0, (i + 1) * third if i < 2 else w, h)
        c = out.crop(box); bb = c.getbbox()
        if bb: c = c.crop(bb)
        o = ASSET / f"chizu_公仔_{tag}_{nm}_透明.png"
        c.save(o); print("  [單張]", nm, c.size)
    print("DONE")

if __name__ == "__main__":
    main()
