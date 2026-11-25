"""직접 모은 사진(꽁줍이 비전 데이터 탭에서 내보낸 ZIP, 폰 업로드)을 기존 데이터에 더한다.
수가 적을 때는 모두 학습용으로 쓰고 여러 번 복제해 비중을 키운다(공개 데이터 수천 장에 묻히지 않게).
사용: python training/prepare_extra.py data/extra <출력 경로>
data/extra 아래의 .zip 은 풀고, images/*.jpg + labels/*.txt 짝을 모두 찾아 85:15 로 나눠 넣는다.
"""
import sys, zipfile, hashlib, shutil
from pathlib import Path

src, dst = Path(sys.argv[1]), Path(sys.argv[2])
if not src.exists(): print("data/extra 없음: 건너뜀"); sys.exit(0)
work = Path("/tmp/extra"); work.mkdir(exist_ok=True)
for z in src.rglob("*.zip"):
    with zipfile.ZipFile(z) as f: f.extractall(work / z.stem)
pairs = []
for root in (src, work):
    for img in list(root.rglob("*.jpg")) + list(root.rglob("*.jpeg")) + list(root.rglob("*.png")):
        if img.parent.name != "images": continue
        lab = img.parent.parent / "labels" / (img.stem + ".txt")
        rows = [l for l in (lab.read_text().splitlines() if lab.exists() else []) if len(l.split()) == 5]
        rows = ["0 " + " ".join(l.split()[1:]) for l in rows]
        pairs.append((img, rows))
small = len(pairs) < 60
repeat = 10 if len(pairs) < 60 else 4 if len(pairs) < 300 else 1
n = b = 0
for img, rows in pairs:
    h = int(hashlib.md5(img.name.encode()).hexdigest(), 16)
    split = "train" if small or h % 100 >= 15 else "valid"
    base = "my_" + hashlib.md5(str(img).encode()).hexdigest()[:14]
    for k in range(repeat if split == "train" else 1):
        name = f"{base}_{k}"
        shutil.copy2(img, dst / split / "images" / (name + img.suffix.lower()))
        (dst / split / "labels" / (name + ".txt")).write_text("\n".join(rows) + ("\n" if rows else ""))
    n += 1; b += len(rows)
print(f"직접 모은 사진 {n}장(박스 {b}개), 학습에 {repeat}배로 넣음")
