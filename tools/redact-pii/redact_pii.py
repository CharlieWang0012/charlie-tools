# -*- coding: utf-8 -*-
"""
PDF 個資遮蔽工具（保單名冊／團體名單分送用）

核心規則（刻意保守，避免誤遮）：
  1. 只遮「身分證字號」與「出生年月日」兩類欄位。
  2. 民國日期只有在「與某個身分證字號同一列」時才視為出生年月日。
     -> 保險期間、出單日、備查文號那些沒有同列 ID 的日期一律不動。
  3. 用 PDF redaction 真正刪除底層文字，不是畫框蓋住。
  4. 遮蔽處補「****」，並在每頁加頁尾標示「去識別化副本．非正本」。

用法：
  # 先看這份 PDF 偵測到哪些人
  python redact_pii.py in.pdf --password 1234 --list

  # 產生分送版本，每個 --group 產一個檔（保留該組的個資，其餘遮蔽）
  python redact_pii.py in.pdf --password 1234 --outdir 分送 \
      --group "A123456789,B223456789:王大明林小美" \
      --group "A187654321,B287654321:陳志豪張淑芬"

  --no-footer     不加頁尾標示
  --footer "..."  自訂頁尾文字（預設含檔案偵測到的保單號碼欄位需自行帶入）
"""
import argparse, os, re, sys
import fitz

ID_RE = re.compile(r'^[A-Z][A-D1-9]\d{8}$')          # 身分證字號／統一證號
ROC_RE = re.compile(r'^民國\d{1,3}年\d{1,2}月\d{1,2}')  # 民國日期（可能斷行少一個「日」）
MARK = '****'
DEFAULT_FOOTER = '去識別化副本．非正本｜其他當事人之出生年月日及身分證號已遮蔽'


def scan(doc):
    """掃出所有「身分證字號 + 同列出生年月日」的列，回傳 list of dict"""
    rows = []
    for pno, page in enumerate(doc):
        words = [w for w in page.get_text('words')]
        ids   = [w for w in words if ID_RE.match(w[4])]
        dates = [w for w in words if ROC_RE.match(w[4])]
        for iw in ids:
            ir = fitz.Rect(iw[:4])
            bd = None
            for dw in dates:
                dr = fitz.Rect(dw[:4])
                # 垂直有交集 = 同一列
                if dr.y1 > ir.y0 - 2 and dr.y0 < ir.y1 + 2:
                    bd = dr
                    if not dw[4].endswith('日'):      # 併回斷行的「日」
                        for cw in words:
                            cr = fitz.Rect(cw[:4])
                            if (cw[4] in ('日', '日 ') and abs(cr.x0 - dr.x0) < 6
                                    and dr.y1 - 1 <= cr.y0 <= dr.y1 + 8):
                                bd |= cr
                    break
            # 同列最左邊的中文字串，通常是姓名，給 --list 辨識用
            label = ''
            cands = [w for w in words
                     if w[2] < ir.x0 and w[3] > ir.y0 - 2 and w[1] < ir.y1 + 2
                     and not ROC_RE.match(w[4])]
            if cands:
                label = min(cands, key=lambda w: w[0])[4]
            rows.append({'page': pno, 'id': iw[4], 'id_rect': ir,
                         'bd_rect': bd, 'label': label})
    return rows


def mask(page, rect, todo, pad=1.0):
    r = fitz.Rect(rect.x0 - pad, rect.y0 - pad, rect.x1 + pad, rect.y1 + pad)
    page.add_redact_annot(r, fill=(1, 1, 1))
    todo.setdefault(page.number, []).append(r)


def build(src, password, keep, out, footer):
    doc = fitz.open(src)
    if password:
        doc.authenticate(password)
    rows = scan(doc)
    todo = {}
    for row in rows:
        if row['id'] in keep:
            continue
        page = doc[row['page']]
        mask(page, row['id_rect'], todo)
        if row['bd_rect']:
            mask(page, row['bd_rect'], todo)

    for pno, rects in todo.items():
        page = doc[pno]
        page.apply_redactions()
        for r in rects:                                  # 塗白後於原格置中補 ****
            fs = min(9.0, max(6.0, r.height * 0.9))
            box = fitz.Rect(r.x0, r.y0 + (r.height - fs) / 2 - 0.5, r.x1, r.y1 + fs)
            page.insert_textbox(box, MARK, fontname='helv', fontsize=fs,
                                align=fitz.TEXT_ALIGN_CENTER, color=(0.25, 0.25, 0.25))

    if footer:
        font = fitz.Font('china-t')                      # 內建繁體字型，不依賴本機字型
        for page in doc:
            tw = fitz.TextWriter(page.rect)
            tw.append(fitz.Point(28.4, page.rect.height - 8), footer, font=font, fontsize=6.5)
            tw.write_text(page, color=(0.35, 0.35, 0.35))

    doc.save(out, garbage=4, deflate=True, encryption=fitz.PDF_ENCRYPT_NONE)
    doc.close()
    return out, rows


def verify(path, all_ids, keep):
    doc = fitz.open(path)
    txt = ''.join(p.get_text() for p in doc)
    doc.close()
    seen = sorted(i for i in all_ids if i in txt)
    want = sorted(i for i in all_ids if i in keep)
    return seen == want, seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('pdf')
    ap.add_argument('--password', default=None)
    ap.add_argument('--outdir', default='.')
    ap.add_argument('--group', action='append', default=[],
                    help='"ID1,ID2:標籤" 可重複，每組產一個檔')
    ap.add_argument('--list', action='store_true', help='只列出偵測到的人，不產檔')
    ap.add_argument('--footer', default=DEFAULT_FOOTER)
    ap.add_argument('--no-footer', action='store_true')
    a = ap.parse_args()

    doc = fitz.open(a.pdf)
    if a.password:
        doc.authenticate(a.password)
    rows = scan(doc)
    doc.close()
    if not rows:
        sys.exit('沒偵測到身分證字號欄位，請確認 PDF 是文字檔不是掃描圖片')

    if a.list or not a.group:
        print(f'偵測到 {len(rows)} 筆：')
        for r in rows:
            bd = '有' if r['bd_rect'] else '（同列查無生日）'
            print(f"  p{r['page']+1}  {r['id']}  生日{bd}  近旁文字: {r['label']}")
        if a.list:
            return

    all_ids = [r['id'] for r in rows]
    os.makedirs(a.outdir, exist_ok=True)
    footer = None if a.no_footer else a.footer
    base = os.path.splitext(os.path.basename(a.pdf))[0]
    for g in a.group:
        ids, _, tag = g.partition(':')
        keep = {s.strip() for s in ids.split(',') if s.strip()}
        unknown = keep - set(all_ids)
        if unknown:
            sys.exit(f'--group 指定的 ID 不在檔案中: {sorted(unknown)}')
        name = f'{base}_{tag}_去識別化副本_非正本.pdf' if tag else f'{base}_去識別化副本.pdf'
        out = os.path.join(a.outdir, name)
        build(a.pdf, a.password, keep, out, footer)
        ok, seen = verify(out, all_ids, keep)
        print(f'{name}  保留{sorted(keep)}  殘留{seen}  -> {"OK" if ok else "!!! 驗證不符"}')
        if not ok:
            sys.exit(1)


if __name__ == '__main__':
    main()
