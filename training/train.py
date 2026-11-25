"""꽁초 감지 모델 학습 + ONNX 내보내기.
사용: python training/train.py <data.yaml> <결과 폴더(public/models)>
"""
import sys, json, shutil, datetime
from pathlib import Path
from ultralytics import YOLO

data, outdir = sys.argv[1], Path(sys.argv[2])
IMGSZ = 416
HOURS = float(sys.argv[3]) if len(sys.argv) > 3 else 1.25

model = YOLO("yolo11n.pt")
model.train(
    data=data, imgsz=IMGSZ, epochs=80, time=HOURS, patience=20,
    batch=32, workers=4, device="cpu", cache="ram",
    degrees=180, flipud=0.5, fliplr=0.5, scale=0.5, hsv_v=0.5,
    project="runs", name="butt", exist_ok=True, plots=False, verbose=False,
)
best = YOLO("runs/butt/weights/best.pt")
m = best.val(data=data, split="test", imgsz=IMGSZ, device="cpu", plots=False)
onnx = best.export(format="onnx", imgsz=IMGSZ, opset=12, simplify=True, dynamic=False)

outdir.mkdir(parents=True, exist_ok=True)
shutil.copy2(onnx, outdir / "butt.onnx")
info = {
    "file": "butt.onnx",
    "imgsz": IMGSZ,
    "names": ["꽁초"],
    "test": {
        "precision": round(float(m.box.mp), 4),
        "recall": round(float(m.box.mr), 4),
        "map50": round(float(m.box.map50), 4),
        "map50_95": round(float(m.box.map), 4),
    },
    "dataset": "CigWasteNet (MIT) 1508/392/100",
    "base": "yolo11n",
    "trained_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ"),
}
(outdir / "butt.json").write_text(json.dumps(info, ensure_ascii=False, indent=2))
print(json.dumps(info, ensure_ascii=False, indent=2))
