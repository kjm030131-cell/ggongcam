"""꽁초 감지 모델 학습 + ONNX 내보내기.
사용: python training/train.py <data.yaml> <결과 폴더(public/models)>
"""
import sys, json, shutil, datetime
import numpy as np
from pathlib import Path
from ultralytics import YOLO

data, outdir = sys.argv[1], Path(sys.argv[2])
import os
DATASET = "CigWasteNet + TACO + 한국 스틱 합성" + (" + Roboflow 꽁초 데이터" if os.environ.get("HAS_RF") else "") + (" + 직접 모은 사진" if any(Path("data/extra").rglob("*.zip")) or any(Path("data/extra").rglob("*.jpg")) else "")
IMGSZ = 640  # 멀리 있는 작은 꽁초를 위해 512 -> 640
HOURS = float(sys.argv[3]) if len(sys.argv) > 3 else 0.75

# 이전 학습 결과가 있으면 거기서 이어서 학습 (처음부터보다 빨리 좋아진다)
INIT = "training/weights/butt.pt" if Path("training/weights/butt.pt").exists() else "yolo11n.pt"
print("시작 가중치:", INIT)
model = YOLO(INIT)
model.train(
    data=data, imgsz=IMGSZ, epochs=300, time=HOURS, patience=40, warmup_epochs=1 if INIT.endswith("butt.pt") else 3,
    batch=32, workers=4, device="cpu", cache="ram",
    degrees=180, flipud=0.5, fliplr=0.5, scale=0.7, hsv_v=0.5, hsv_s=0.6, mosaic=1.0, close_mosaic=8,
    project=str(Path("runs").resolve()), name="butt", exist_ok=True, plots=False, verbose=False,
)
best_path = Path(model.trainer.best)
print("best:", best_path)
best = YOLO(str(best_path))
m = best.val(data=data, split="val", imgsz=IMGSZ, device="cpu", plots=False)

def best_conf(metrics):
    # 검증셋에서 F1 이 가장 높은 확신도 기준. 사이트는 이 값을 감도 '보통'(50%)에 맞춘다.
    try:
        f1 = np.asarray(metrics.box.f1_curve).mean(0); px = np.asarray(metrics.box.px)
        return round(float(min(0.7, max(0.1, px[int(f1.argmax())]))), 3), round(float(f1.max()), 4)
    except Exception as e:
        print("기준 계산 실패:", e); return 0.5, None

rec, f1_new = best_conf(m)
# 지금 쓰는 모델을 같은 검증셋으로 다시 채점해서, 새 모델이 더 나쁘면 반영하지 않는다.
if INIT.endswith("butt.pt"):
    mo = YOLO(INIT).val(data=data, split="val", imgsz=IMGSZ, device="cpu", plots=False)
    _, f1_old = best_conf(mo)
    print(f"같은 검증셋: 기존 mAP50 {mo.box.map50:.4f} F1 {f1_old}  /  새 모델 mAP50 {m.box.map50:.4f} F1 {f1_new}")
    if m.box.map50 + 0.005 < mo.box.map50:
        Path("/tmp/no_publish").write_text(f"기존 {mo.box.map50:.4f} > 새 {m.box.map50:.4f}")
        print("새 모델이 더 나빠서 반영하지 않음"); sys.exit(0)
# 현장 시험지(data/test, 학습에 안 쓰는 사진)가 있으면 새 모델 / 기존 모델 성적을 따로 남긴다.
field = None
tests = [p for p in Path("data/test").rglob("*.jpg") if p.parent.name == "images"] if Path("data/test").exists() else []
if tests:
    ft = Path("/tmp/fieldtest"); (ft / "images").mkdir(parents=True, exist_ok=True); (ft / "labels").mkdir(parents=True, exist_ok=True)
    for i, p in enumerate(tests):
        shutil.copy2(p, ft / "images" / f"f{i:05d}.jpg")
        lab = p.parent.parent / "labels" / (p.stem + ".txt")
        (ft / "labels" / f"f{i:05d}.txt").write_text(lab.read_text() if lab.exists() else "")
    (ft / "data.yaml").write_text(f"path: {ft}\ntrain: images\nval: images\nnames:\n  0: butt\n")
    fm = best.val(data=str(ft / "data.yaml"), split="val", imgsz=IMGSZ, device="cpu", plots=False)
    field = {"images": len(tests), "precision": round(float(fm.box.mp), 4), "recall": round(float(fm.box.mr), 4), "map50": round(float(fm.box.map50), 4)}
    print("현장 시험지:", field)
outdir.mkdir(parents=True, exist_ok=True)
variants = []
for sz in (IMGSZ, 416):
    f = best.export(format="onnx", imgsz=sz, opset=12, simplify=True, dynamic=False)
    name = f"butt-{sz}.onnx"; shutil.copy2(f, outdir / name)
    variants.append({"file": name, "imgsz": sz, "conf": rec})
shutil.copy2(outdir / f"butt-{IMGSZ}.onnx", outdir / "butt.onnx")
if (outdir / "butt-close-416.onnx").exists():
    variants.append({"file": "butt-close-416.onnx", "imgsz": 416, "conf": 0.35, "kind": "close", "note": "CigWasteNet만 학습한 첫 모델. 바닥을 가까이서 내려다볼 때 더 정확"})
Path("training/weights").mkdir(parents=True, exist_ok=True)
shutil.copy2(best_path, "training/weights/butt.pt")
info = {
    "file": "butt.onnx",
    "imgsz": IMGSZ,
    "variants": variants,
    "names": ["꽁초"],
    "test": {
        "precision": round(float(m.box.mp), 4),
        "recall": round(float(m.box.mr), 4),
        "map50": round(float(m.box.map50), 4),
        "map50_95": round(float(m.box.map), 4),
        "f1": f1_new,
        "conf": rec,
    },
    "field_test": field,
    "dataset": DATASET,
    "base": "yolo11n",
    "trained_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ"),
}
(outdir / "butt.json").write_text(json.dumps(info, ensure_ascii=False, indent=2))
print(json.dumps(info, ensure_ascii=False, indent=2))
