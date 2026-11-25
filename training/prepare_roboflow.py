"""Roboflow Universe 의 공개 꽁초 데이터셋을 받아 기존 데이터에 더한다.
ROBOFLOW_API_KEY 환경변수(무료 계정 키)가 없으면 아무것도 하지 않는다.
사용: python training/prepare_roboflow.py <출력 경로(prepare.py 결과)>
꽁초, 전자담배 스틱에 해당하는 클래스만 꽁초(0)로 바꿔 넣고 나머지 클래스 박스는 버린다.
"""
import os, sys, hashlib, shutil, yaml
from pathlib import Path

KEY = os.environ.get("ROBOFLOW_API_KEY", "").strip()
if not KEY:
    print("ROBOFLOW_API_KEY 없음: Roboflow 데이터 건너뜀"); sys.exit(0)
from roboflow import Roboflow

dst = Path(sys.argv[1])
# (워크스페이스, 프로젝트, 모든 클래스를 꽁초로 볼지)
DATASETS = [
    ("material-recognition", "cigarette-butts", True),      # 꽁초 + 전자담배(가열식) 스틱
    ("eyad-amin-ukdly", "cigarettesbutts", True),
    ("butt", "yolo-cigarettes-butts", True),
    ("riumin", "cigarette-butt", True),
    ("work5", "cigarette-butts-rqmue", True),
    ("tiny-ping", "cigarette-butts-1fukc-p2oxb-zogie", True),
    ("leesh-fyfat", "cigarette_butt-xxonx", True),
    ("ihj", "cigarette-detection-usfmk", False),
    ("jeet-work", "cigarette_butt_detection-ha7he", False),
    ("ken-0i3em", "cigarrette-end-detection", True),
]
KEYWORDS = ("butt", "꽁초", "stick", "heets", "tobacco", "end", "bud", "bytt")

rf = Roboflow(api_key=KEY)
total_img = total_box = 0
for ws, proj, allc in DATASETS:
    try:
        p = rf.workspace(ws).project(proj)
        vs = p.versions()
        if not vs: print("버전 없음", ws, proj); continue
        v = max(vs, key=lambda x: int(str(x.version).rstrip("/").split("/")[-1]))
        loc = f"/tmp/rf/{proj}"
        v.download("yolov8", location=loc, overwrite=True)
    except Exception as e:
        print("받기 실패", ws, proj, repr(e)[:200]); continue
    meta = yaml.safe_load(open(Path(loc) / "data.yaml"))
    names = meta.get("names", [])
    if isinstance(names, dict): names = [names[k] for k in sorted(names)]
    keep = {i for i, n in enumerate(names) if allc or any(k in str(n).lower() for k in KEYWORDS)}
    print(f"{ws}/{proj} v{v.version}: 클래스 {names} -> 사용 {sorted(keep)}")
    n_img = n_box = 0
    for split in ("train", "valid", "test"):
        idir = Path(loc) / split / "images"
        if not idir.exists(): continue
        out = "train" if split == "train" else "valid"
        for img in idir.iterdir():
            lab = Path(loc) / split / "labels" / (img.stem + ".txt")
            rows = []
            if lab.exists():
                for line in lab.read_text().splitlines():
                    q = line.split()
                    if len(q) < 5 or int(float(q[0])) not in keep: continue
                    vals = [float(x) for x in q[1:]]
                    if len(vals) == 4:
                        cx, cy, w, h = vals
                    else:  # 다각형/회전 박스 -> 축 정렬 박스
                        xs, ys = vals[0::2], vals[1::2]
                        cx, cy, w, h = (min(xs)+max(xs))/2, (min(ys)+max(ys))/2, max(xs)-min(xs), max(ys)-min(ys)
                    if w <= 0.002 or h <= 0.002: continue
                    rows.append(f"0 {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}")
            name = "rf_" + hashlib.md5(f"{proj}/{img.name}".encode()).hexdigest()[:14]
            shutil.copy2(img, dst / out / "images" / (name + img.suffix.lower()))
            (dst / out / "labels" / (name + ".txt")).write_text("\n".join(rows) + ("\n" if rows else ""))
            n_img += 1; n_box += len(rows)
    print(f"  -> 사진 {n_img}장, 꽁초 박스 {n_box}개")
    total_img += n_img; total_box += n_box
print(f"Roboflow 합계: 사진 {total_img}장, 꽁초 박스 {total_box}개")
