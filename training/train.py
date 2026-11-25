"""꽁초 감지 모델 학습 + ONNX 내보내기.
사용: python training/train.py <data.yaml> <결과 폴더(public/models)>
"""
import sys, json, shutil, datetime
from pathlib import Path
from ultralytics import YOLO

data, outdir = sys.argv[1], Path(sys.argv[2])
import os
DATASET = "CigWasteNet + TACO" + (" + Roboflow 꽁초 데이터" if os.environ.get("HAS_RF") else "") + (" + 직접 모은 사진" if any(Path("data/extra").rglob("*.zip")) or any(Path("data/extra").rglob("*.jpg")) else "")
IMGSZ = 512
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
outdir.mkdir(parents=True, exist_ok=True)
variants = []
for sz in (IMGSZ, 384):
    f = best.export(format="onnx", imgsz=sz, opset=12, simplify=True, dynamic=False)
    name = f"butt-{sz}.onnx"; shutil.copy2(f, outdir / name)
    variants.append({"file": name, "imgsz": sz})
shutil.copy2(outdir / f"butt-{IMGSZ}.onnx", outdir / "butt.onnx")
if (outdir / "butt-close-416.onnx").exists():
    variants.append({"file": "butt-close-416.onnx", "imgsz": 416, "kind": "close", "note": "CigWasteNet만 학습한 첫 모델. 바닥을 가까이서 내려다볼 때 더 정확"})
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
    },
    "dataset": DATASET,
    "base": "yolo11n",
    "trained_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ"),
}
(outdir / "butt.json").write_text(json.dumps(info, ensure_ascii=False, indent=2))
print(json.dumps(info, ensure_ascii=False, indent=2))
