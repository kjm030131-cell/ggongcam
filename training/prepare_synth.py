"""한국 꽁초(가열식 담배 스틱 등) 합성 데이터: 폰 사진에서 오려낸 스틱(data/extra/cutouts/*.png, 배경 투명)을
기존 학습 사진(CigWasteNet, TACO 타일) 위에 무작위로 붙여 새 학습 사진을 만든다.
직접 찍은 사진이 적을 때 같은 스틱을 여러 바닥, 크기, 방향, 밝기로 보여주기 위한 것.
사용: python training/prepare_synth.py data/extra/cutouts <출력 경로(prepare.py 결과)> [만들 장수]
- 붙이는 위치는 기존 꽁초 박스와 겹치지 않게 고른다. 원래 박스는 그대로 유지한다.
- 85:15 로 train/valid 에 나눠 넣어서 검증 점수에도 반영되게 한다.
"""
import sys, random
from pathlib import Path
import numpy as np, cv2

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
N = int(sys.argv[3]) if len(sys.argv) > 3 else 1500
cuts = [cv2.imread(str(p), cv2.IMREAD_UNCHANGED) for p in sorted(src.glob("*.png"))]
cuts = [c for c in cuts if c is not None and c.ndim == 3 and c.shape[2] == 4]
if not cuts: print("오려낸 스틱 없음: 건너뜀"); sys.exit(0)
rng = random.Random(11)
bgs = sorted((dst / "train" / "images").glob("*"))
bgs = [b for b in bgs if not b.name.startswith(("my_", "syn_"))]
rng.shuffle(bgs)

def read_boxes(lbl, W, H):
    out = []
    if lbl.exists():
        for l in lbl.read_text().splitlines():
            p = l.split()
            if len(p) == 5:
                _, x, y, w, h = map(float, p)
                out.append([(x - w / 2) * W, (y - h / 2) * H, (x + w / 2) * W, (y + h / 2) * H])
    return out

def overlaps(b, boxes):
    for o in boxes:
        ix = min(b[2], o[2]) - max(b[0], o[0]); iy = min(b[3], o[3]) - max(b[1], o[1])
        if ix > 0 and iy > 0: return True
    return False

def prep(cut, long_px):
    c = cut.copy()
    if rng.random() < 0.5: c = c[:, ::-1]
    h, w = c.shape[:2]; k = long_px / max(h, w)
    c = cv2.resize(c, (max(2, int(w * k)), max(2, int(h * k))), interpolation=cv2.INTER_AREA)
    ang = rng.uniform(0, 360); h, w = c.shape[:2]
    M = cv2.getRotationMatrix2D((w / 2, h / 2), ang, 1.0)
    cos, sin = abs(M[0, 0]), abs(M[0, 1]); nw, nh = int(h * sin + w * cos) + 2, int(h * cos + w * sin) + 2
    M[0, 2] += nw / 2 - w / 2; M[1, 2] += nh / 2 - h / 2
    c = cv2.warpAffine(c, M, (nw, nh), flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
    ys, xs = np.where(c[:, :, 3] > 40)
    if not len(xs): return None
    if max(xs.max() - xs.min(), ys.max() - ys.min()) < 6: return None
    c = c[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    rgb = c[:, :, :3].astype(np.float32)
    rgb = rgb * rng.uniform(0.8, 1.08) + rng.uniform(-12, 8)           # 밝기
    rgb = rgb * np.array([rng.uniform(0.9, 1.08) for _ in range(3)])   # 색 온도
    if rng.random() < 0.3: rgb = cv2.GaussianBlur(rgb, (3, 3), 0)
    c = np.dstack([np.clip(rgb, 0, 255), c[:, :, 3].astype(np.float32)])
    return c

made = boxes_total = 0
for i in range(N):
    bp = bgs[i % len(bgs)]
    img = cv2.imread(str(bp))
    if img is None: continue
    H, W = img.shape[:2]
    lbl = dst / "train" / "labels" / (bp.stem + ".txt")
    boxes = read_boxes(lbl, W, H)
    new = []
    for _ in range(rng.choice([1, 2, 2, 3, 4, 5])):
        # 절반은 멀리서 찍힌 것처럼 작게(긴 변의 2~6%), 나머지는 가까이(6~22%)
        frac = rng.uniform(0.02, 0.06) if rng.random() < 0.5 else rng.uniform(0.06, 0.22)
        c = prep(rng.choice(cuts), frac * max(W, H))
        if c is None: continue
        h, w = c.shape[:2]
        if w >= W - 4 or h >= H - 4: continue
        for _try in range(12):
            x, y = rng.randint(0, W - w - 1), rng.randint(0, H - h - 1)
            b = [x, y, x + w, y + h]
            if not overlaps(b, boxes + new): break
        else: continue
        a = c[:, :, 3:] / 255.0
        roi = img[y:y + h, x:x + w].astype(np.float32)
        # 그림자: 오른쪽 아래로 살짝 어둡게
        sh = cv2.GaussianBlur(a, (0, 0), max(1, w / 30)); sh = sh[..., None] if sh.ndim == 2 else sh
        dx, dy = max(1, w // 25), max(1, h // 25)
        shadow = np.zeros_like(a); shadow[dy:, dx:] = sh[:h - dy, :w - dx] if sh.ndim == 3 else sh[:h - dy, :w - dx, None]
        roi = roi * (1 - 0.35 * shadow)
        roi = roi * (1 - a) + c[:, :, :3] * a
        img[y:y + h, x:x + w] = np.clip(roi, 0, 255).astype(np.uint8)
        new.append(b)
    if not new: continue
    split = "valid" if i % 100 < 15 else "train"
    name = f"syn_{i:05d}"
    cv2.imwrite(str(dst / split / "images" / (name + ".jpg")), img, [cv2.IMWRITE_JPEG_QUALITY, 90])
    rows = [f"0 {(b[0]+b[2])/2/W:.6f} {(b[1]+b[3])/2/H:.6f} {(b[2]-b[0])/W:.6f} {(b[3]-b[1])/H:.6f}" for b in boxes + new]
    (dst / split / "labels" / (name + ".txt")).write_text("\n".join(rows) + "\n")
    made += 1; boxes_total += len(new)
print(f"합성 사진 {made}장, 붙인 스틱 {boxes_total}개 (오려낸 스틱 {len(cuts)}종)")
