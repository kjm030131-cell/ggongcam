# 꽁캠 (ggongcam)

꽁줍이 졸업작품용 담배꽁초 인식 프로토타입.

- **자동 감지 (기본)**: 학습 없이 카메라 화면 전체에서 꽁초 위치를 박스로 찾는다. 공개 데이터셋으로 학습한 YOLO11n 모델을 브라우저에서 ONNX Runtime으로 돌린다.
- **종류 학습 (선택)**: 감지된 꽁초 박스 안을 샘플로 모아 일반 / 얇은 / 전자담배 스틱으로 나눈다 (MobileNet + KNN).
- **영역 판정**: 예전 방식. 화면 가운데 사각형만 샘플 기반으로 분류.
- 웹캠 없이 `사진으로 테스트` 버튼이나 화면에 사진을 끌어다 놓아도 된다.

- 사이트: **https://ggongcam.pages.dev** (PC 크롬 권장, 카메라 허용 필요)
- 기술: 한 파일 HTML. 감지는 onnxruntime-web + `public/models/butt.onnx`, 종류 분류는 TensorFlow.js MobileNet v2 + KNN.
- 서버 없음. Cloudflare Pages 정적 배포 (GitHub 연결, 빌드 명령 없음, 출력 폴더 `public`).

## 개발 흐름

```bash
node tools/check.mjs   # 문법 검사 (push 전에)
npx wrangler pages dev # 로컬 확인 http://localhost:8788
git push               # main 에 push 하면 Cloudflare Pages 가 자동 배포
```

- 배포는 `main` push 하나뿐. 터미널에서 직접 배포하지 않는다.
- 다른 브랜치에 push 하면 Pages 가 미리보기 주소를 따로 만든다. 확인 후 main 에 merge.
- GitHub Actions 의 qa 는 문법 검사만 한다.

## 감지 모델 학습

- 데이터: [CigWasteNet](https://github.com/KabirAhmad4/Intelligent-Cigarette-Butt-Detection-and-Localization-Using-YOLOv8-Detection) (MIT, 캠퍼스 바닥 꽁초 2,000장). 회전 박스를 일반 박스로 바꿔 꽁초 한 클래스로 학습 (`training/prepare.py`).
- 학습: GitHub Actions `train` 워크플로가 CPU로 YOLO11n을 416px로 학습하고 ONNX로 내보내 `public/models/` 에 커밋한다. 커밋되면 Pages가 자동 배포.
- 다시 학습: Actions 탭에서 train 을 수동 실행하거나 `training/` 을 고쳐 push.
- 성능 수치는 `public/models/butt.json` 의 test 항목과 페이지의 판정 설정 아래에 표시된다.
- 한국 꽁초(에쎄 등 슬림, 아이코스 스틱)는 학습 데이터에 거의 없다. 직접 찍은 사진을 라벨링해 데이터셋에 더하는 것이 다음 단계.
- Ultralytics 로 학습한 모델은 AGPL-3.0 을 따른다 (이 저장소는 공개).

## 구조

```
public/index.html      페이지 전체 (마크업, 스타일, 인식 로직)
public/models/         감지 모델 butt.onnx + butt.json (Actions가 생성)
training/              데이터 변환, 학습 스크립트
wrangler.jsonc         Pages 프로젝트 ggongcam, 출력 폴더 public/
tools/check.mjs        인라인 스크립트 문법 검사
.github/workflows/     qa (문법 검사), train (모델 학습)
```

## 사용법

1. 열면 바로 자동 감지. 꽁초가 보이면 박스와 신뢰도가 뜨고, 정해진 프레임 수만큼 이어지면 감지 기록에 캡처.
2. 종류까지 나누려면 꽁초를 비춘 채 종류 버튼(숫자키 2~4)을 누르고 있기. 종류마다 30장 이상, 각도와 바닥을 바꿔가며.
3. 샘플은 브라우저 localStorage에 자동 저장. JSON 내보내기/불러오기로 팀원과 공유.

## 한계와 다음 단계

- 학습 데이터가 해외 캠퍼스 사진이라 국내 보도블록, 슬림 꽁초, 전자담배 스틱에서는 놓치거나 헛감지가 생길 수 있다.
- 같은 ONNX 모델을 라즈베리파이에서 onnxruntime(Python)으로 그대로 돌릴 수 있다.
- MobileNet v2 로드에 실패하면 v1으로 대체되는데, 이때 v2로 저장한 샘플(1280차원)과 차원이 달라 불러올 수 없다.
