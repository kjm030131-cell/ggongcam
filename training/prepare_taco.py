"""TACO(쓰레기 사진, 담배꽁초 클래스, 저장소 코드 MIT, 사진은 장마다 Flickr CC 또는 OpenLitterMap ODbL) -> 640 타일 YOLO 데이터셋으로 변환해 기존 데이터에 더한다.
사용: python training/prepare_taco.py <TACO 저장소 경로> <출력 경로(prepare.py 결과)>
- 원본 사진을 받아 긴 변 1280으로 줄이고 640x640 타일(겹침 25%)로 자른다.
- 꽁초가 든 타일은 모두, 꽁초 없는 사진은 타일 하나씩 음성 예시로 넣는다(헛감지 줄이기).
- 사진 단위로 train/valid 를 85:15 로 나눈다.
"""
import sys, json, io, hashlib, random, concurrent.futures as cf, urllib.request
from pathlib import Path
from PIL import Image, ImageOps

taco, dst = Path(sys.argv[1]), Path(sys.argv[2])
random.seed(7)
LONG, T, STEP, NEG_MAX = 1280, 640, 480, 500

imgs, anns = {}, {}
for f in ["annotations.json", "annotations_unofficial.json"]:
    d = json.load(open(taco / "data" / f))
    cig = {c["id"] for c in d["categories"] if c["name"].lower().startswith("cigarette")}
    for im in d["images"]:
        key = im["flickr_url"]
        imgs[key] = im; anns.setdefault(key, [])
    byid = {im["id"]: im["flickr_url"] for im in d["images"]}
    for a in d["annotations"]:
        if a["category_id"] in cig:
            anns[byid[a["image_id"]]].append(a["bbox"])

pos = [k for k, v in anns.items() if v]
neg = [k for k, v in anns.items() if not v]
random.shuffle(neg); neg = neg[:NEG_MAX]
print(f"TACO 꽁초 있는 사진 {len(pos)}장, 음성 후보 {len(neg)}장")

def fetch(url):
    for _ in range(3):
        try:
            with urllib.request.urlopen(url, timeout=40) as r: return r.read()
        except Exception: pass
    return None

def tiles(w, h):
    xs = list(range(0, max(1, w - T) + 1, STEP)) or [0]
    ys = list(range(0, max(1, h - T) + 1, STEP)) or [0]
    if xs[-1] + T < w: xs.append(w - T)
    if ys[-1] + T < h: ys.append(h - T)
    return [(max(0, x), max(0, y)) for y in ys for x in xs]

def work(url):
    raw = fetch(url)
    if raw is None: return (url, 0, 0)
    try:
        im = ImageOps.exif_transpose(Image.open(io.BytesIO(raw))).convert("RGB")
    except Exception:
        return (url, 0, 0)
    meta = imgs[url]; W0, H0 = meta["width"], meta["height"]
    # 어노테이션은 원본 해상도 기준. EXIF 회전으로 가로세로가 바뀌었으면 맞춰준다.
    if (im.width > im.height) != (W0 > H0): W0, H0 = H0, W0
    k = LONG / max(im.width, im.height)
    im = im.resize((round(im.width * k), round(im.height * k)))
    sx, sy = im.width / W0, im.height / H0
    boxes = [(x * sx, y * sy, w * sx, h * sy) for x, y, w, h in anns[url]]
    split = "valid" if int(hashlib.md5(url.encode()).hexdigest(), 16) % 100 < 15 else "train"
    stem = "taco_" + hashlib.md5(url.encode()).hexdigest()[:12]
    npos = nt = 0
    cand = tiles(im.width, im.height)
    if not boxes: cand = [random.choice(cand)]
    for i, (tx, ty) in enumerate(cand):
        lab = []
        for x, y, w, h in boxes:
            x0, y0, x1, y1 = max(x, tx), max(y, ty), min(x + w, tx + T), min(y + h, ty + T)
            if x1 <= x0 or y1 <= y0: continue
            if (x1 - x0) * (y1 - y0) < 0.6 * w * h: continue
            lab.append(f"0 {((x0+x1)/2-tx)/T:.6f} {((y0+y1)/2-ty)/T:.6f} {(x1-x0)/T:.6f} {(y1-y0)/T:.6f}")
        if boxes and not lab: continue
        tile = im.crop((tx, ty, tx + T, ty + T))
        name = f"{stem}_{i}"
        tile.save(dst / split / "images" / f"{name}.jpg", quality=90)
        (dst / split / "labels" / f"{name}.txt").write_text("\n".join(lab) + ("\n" if lab else ""))
        nt += 1; npos += len(lab)
    return (url, nt, npos)

ok = tiles_n = boxes_n = 0
with cf.ThreadPoolExecutor(16) as ex:
    for url, nt, npos in ex.map(work, pos + neg):
        if nt: ok += 1
        tiles_n += nt; boxes_n += npos
print(f"TACO 받은 사진 {ok}장 -> 타일 {tiles_n}장, 꽁초 박스 {boxes_n}개")
