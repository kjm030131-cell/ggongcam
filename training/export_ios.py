"""아이폰 앱용 CoreML 모델 내보내기.
사용: python training/export_ios.py <가중치.pt> <public/models 경로> [conf] [imgsz]
- NMS까지 들어간 CoreML 모델(.mlpackage)을 만들어 public/models/ios/<버전>/butt.mlpackage/ 에 파일 그대로 풀어 둔다.
- public/models/ios.json 에 버전, 입력 크기, 권장 기준, 받을 파일 목록을 적는다. 앱은 켜질 때 이 파일을 보고 새 모델이면 받아 간다.
- 예전 버전 폴더는 최근 2개만 남긴다.
"""
import sys, json, shutil, datetime
from pathlib import Path
from ultralytics import YOLO

w, outdir = Path(sys.argv[1]), Path(sys.argv[2])
conf = float(sys.argv[3]) if len(sys.argv) > 3 else 0.4
imgsz = int(sys.argv[4]) if len(sys.argv) > 4 else 640
ver = datetime.datetime.utcnow().strftime("%Y%m%d%H%M")

f = Path(YOLO(str(w)).export(format="coreml", imgsz=imgsz, nms=True, half=True))
print("내보냄:", f)
root = outdir / "ios"
dst = root / ver / "butt.mlpackage"
if dst.parent.exists(): shutil.rmtree(dst.parent)
shutil.copytree(f, dst)
files = sorted(str(p.relative_to(dst)) for p in dst.rglob("*") if p.is_file())
info = {"version": ver, "imgsz": imgsz, "conf": conf, "base": f"models/ios/{ver}/butt.mlpackage/", "files": files,
        "names": ["꽁초"], "from": w.name, "made_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ")}
(outdir / "ios.json").write_text(json.dumps(info, ensure_ascii=False, indent=2))
for old in sorted([p for p in root.iterdir() if p.is_dir()], key=lambda p: p.name)[:-2]:
    shutil.rmtree(old)
print(json.dumps(info, ensure_ascii=False, indent=2))
