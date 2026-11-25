# 꽁줍이 비전 (ggongcam)

꽁줍이(담배꽁초 수거 로봇) 메인 카메라 프로그램 프로토타입. 브라우저에서 돌아간다.

- **감지 모드**: 카메라로 꽁초를 찾고 종류별로 센다. 좌표나 로봇 기능 없이 인식만 확인할 때.
- **로봇팔 모드**: 목표 하나를 골라 집기 기준점 기준 mm 좌표를 계산하고 로봇에 보낸다.

- 사이트: **https://ggongcam.pages.dev** (PC 크롬, 엣지 권장)
- 감지: 공개 데이터셋으로 학습한 YOLO11n을 onnxruntime-web으로 실행 (`public/models/`). WebGPU가 되면 GPU, 아니면 CPU 멀티코어(WASM 스레드, `_headers`의 COOP/COEP로 교차 출처 격리). ORT 파일은 `public/vendor/ort-1.20.1/`에 직접 둔다.
- 감지 범위: 전체 / 가운데 2배 확대 / 정밀(전체 + 4분할 타일). 멀리서 작은 꽁초를 볼 때 확대나 정밀.
- 목표: 화면 속 꽁초 중 하나를 목표로 골라(기준점에 가까운 순, 신뢰도 순, 큰 순) 집기 기준점 기준 X/Y mm 오프셋과 집기 영역 안 여부를 계산.
- 로봇 링크: Web Serial(USB로 ESP32, 아두이노) 또는 WebSocket(라즈베리파이)으로 목표를 주기적으로 송신. 예제는 `robot/`.
- 데이터셋: 프레임을 현재 감지 박스와 함께 YOLO 라벨로 저장, ZIP으로 내보내 국내 데이터로 재학습.
- 종류(선택): 일반, 얇은, 전자담배 스틱을 MobileNet + KNN으로 구분. 목표 박스 안을 샘플로 모은다.
- 추적(락온): 프레임마다 감지 결과를 IoU로 이어 붙여 물체마다 번호(#id)를 주고 박스를 부드럽게 따라간다. 정해진 프레임 수 이상 이어지면 락온(모서리 괄호), 폰은 진동.
- 폰: 큰 저장 버튼, 화면 꺼짐 방지, 후면 카메라 기본. 저장한 사진은 IndexedDB에 남고, 사진을 눌러 박스를 직접 그리거나 지울 수 있다.
- 이벤트: 목표가 정해진 프레임 수만큼 유지되면 캡처와 좌표를 기록, CSV로 내보내기.
- 사진, 영상 파일로도 테스트 가능 (버튼 또는 화면에 끌어다 놓기).

## 개발 흐름

```bash
node tools/check.mjs   # 문법 검사 (push 전에)
npx wrangler pages dev # 로컬 확인 http://localhost:8788
git push               # main 에 push 하면 Cloudflare Pages 가 자동 배포
```

- 배포는 `main` push 하나뿐. 터미널에서 직접 배포하지 않는다.
- 다른 브랜치에 push 하면 Pages 가 미리보기 주소를 따로 만든다. 확인 후 main 에 merge.
- GitHub Actions: qa (문법 검사), train (감지 모델 학습).

## 로봇 송신 형식

| 형식 | 목표 있음 | 목표 없음 |
|---|---|---|
| CSV | `T,X,Y,신뢰도,영역안,개수` 예 `T,32,-15,0.87,0,2` | `N,개수` |
| JSON | `{"t":ms,"n":2,"tgt":{"cls":"butt","conf":0.87,"x":32,"y":-15,"in":false,"px":[812,540],"stable":9}}` | `{"t":ms,"n":0,"tgt":null}` |

- X는 오른쪽 +, Y는 앞(화면 위쪽) +, 단위 mm. 원점은 집기 영역 가운데.
- mm 환산은 로봇 탭의 "화면 가로 실제 폭" 하나로 한다(카메라가 바닥을 수직으로 볼 때 맞다. 비스듬하면 오차가 커진다).
- 좌우 반전은 화면 표시만 바꾸고 좌표는 원본 영상 기준.
- 로봇이 보낸 줄은 콘솔에 `<` 로 표시된다.

## 감지 모델 학습

- 데이터 1: [CigWasteNet](https://github.com/KabirAhmad4/Intelligent-Cigarette-Butt-Detection-and-Localization-Using-YOLOv8-Detection) (MIT). 대학 캠퍼스 바닥의 꽁초를 위에서 가까이 찍은 사진 2,000장(학습 1,508 / 검증 392 / 테스트 100), 사진마다 꽁초 1개. 회전 박스를 일반 박스로 바꿔 꽁초 한 클래스로 학습 (`training/prepare.py`).
- 데이터 2: [TACO](https://github.com/pedropro/TACO) 의 Cigarette 클래스. 길거리 쓰레기를 서서 찍은 사진 중 꽁초가 있는 432장(꽁초 1,158개)과 꽁초 없는 사진 500장. 긴 변 1280으로 줄여 640 조각으로 자르고 꽁초 든 조각과 음성 조각을 더한다 (`training/prepare_taco.py`). 저장소 코드는 MIT, 사진은 장마다 Flickr CC 또는 OpenLitterMap ODbL 이라 상업적으로 쓸 때는 사진별 라이선스를 따로 확인해야 한다.
- 학습은 이전 결과(`training/weights/butt.pt`)에서 이어서 한다.
- 학습: GitHub Actions `train` 워크플로가 CPU로 YOLO11n을 416px로 학습하고 ONNX로 내보내 `public/models/` 에 커밋한다. 커밋되면 Pages가 자동 배포.
- 다시 학습: Actions 탭에서 train 을 수동 실행하거나 `training/` 을 고쳐 push.
- 성능 수치는 `public/models/butt.json` 의 test 항목과 페이지의 판정 설정 아래에 표시된다.
- 한국 꽁초(에쎄 등 슬림, 아이코스 스틱)는 학습 데이터에 거의 없다. 직접 찍은 사진을 라벨링해 데이터셋에 더하는 것이 다음 단계.
- Ultralytics 로 학습한 모델은 AGPL-3.0 을 따른다 (이 저장소는 공개).

## 구조

```
robot/                 ESP32 시리얼 수신, 라즈베리파이 WebSocket 수신 예제
public/index.html      페이지 전체 (마크업, 스타일, 감지, 로봇 링크, 데이터셋)
public/models/         감지 모델 butt.onnx + butt.json (Actions가 생성)
training/              데이터 변환, 학습 스크립트
wrangler.jsonc         Pages 프로젝트 ggongcam, 출력 폴더 public/
tools/check.mjs        인라인 스크립트 문법 검사
.github/workflows/     qa (문법 검사), train (모델 학습)
```

## 사용법

1. 로봇 탭에서 화면 가로 실제 폭(mm)과 집기 영역 위치를 맞춘다.
2. 감지 탭에서 목표 좌표와 이동 방향을 확인한다.
3. 시리얼이나 WebSocket을 연결하고 송신 주기를 고른다.
4. 데이터셋 탭에서 자동 저장을 켜 두고 학교 주변을 돌며 모은 뒤 ZIP으로 내보낸다.

## 한계와 다음 단계

- 학습 데이터가 해외 캠퍼스 사진이라 국내 보도블록, 슬림 꽁초, 전자담배 스틱에서는 놓치거나 헛감지가 생길 수 있다.
- 같은 ONNX 모델을 라즈베리파이에서 onnxruntime(Python)으로 그대로 돌릴 수 있다.
- MobileNet v2 로드에 실패하면 v1으로 대체되는데, 이때 v2로 저장한 샘플(1280차원)과 차원이 달라 불러올 수 없다.
