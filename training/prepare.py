"""CigWasteNet(OBB) -> 일반 YOLO 박스 데이터셋으로 변환.
사용: python training/prepare.py <CigWasteNet.yolov8-obb 경로> <출력 경로>
회전 박스 네 꼭짓점의 최소/최대로 축 정렬 박스를 만든다. 클래스는 꽁초 하나(0)만 쓴다.
"""
import sys, os, shutil
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
stats = {}
for split in ("train", "valid", "test"):
    (dst / split / "images").mkdir(parents=True, exist_ok=True)
    (dst / split / "labels").mkdir(parents=True, exist_ok=True)
    n_img = n_box = 0
    for img in sorted((src / split / "images").iterdir()):
        lab = src / split / "labels" / (img.stem + ".txt")
        out = []
        if lab.exists():
            for line in lab.read_text().splitlines():
                p = line.split()
                if len(p) < 9 or p[0] != "0":
                    continue
                xs = [min(max(float(v), 0.0), 1.0) for v in p[1:9:2]]
                ys = [min(max(float(v), 0.0), 1.0) for v in p[2:9:2]]
                x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
                w, h = x1 - x0, y1 - y0
                if w < 0.004 or h < 0.004:
                    continue
                out.append(f"0 {(x0+x1)/2:.6f} {(y0+y1)/2:.6f} {w:.6f} {h:.6f}")
        shutil.copy2(img, dst / split / "images" / img.name)
        (dst / split / "labels" / (img.stem + ".txt")).write_text("\n".join(out) + ("\n" if out else ""))
        n_img += 1; n_box += len(out)
    stats[split] = (n_img, n_box)

(dst / "data.yaml").write_text(
    f"path: {dst.resolve()}\ntrain: train/images\nval: valid/images\ntest: test/images\nnames:\n  0: butt\n"
)
for k, (i, b) in stats.items():
    print(f"{k}: 이미지 {i}장, 박스 {b}개")
