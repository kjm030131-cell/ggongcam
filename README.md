# 꽁캠 (ggongcam)

꽁줍이 졸업작품용 담배꽁초 인식 프로토타입. 웹캠 화면 가운데 판정 영역을 일반 꽁초 / 얇은 꽁초 / 전자담배 스틱 / 배경으로 실시간 분류한다.

- 사이트: **https://ggongcam.pages.dev** (PC 크롬 권장, 카메라 허용 필요)
- 기술: 한 파일 HTML + TensorFlow.js. MobileNet v2로 특징을 뽑고 KNN으로 분류. 학습은 브라우저 안에서 샘플을 모아 바로 끝난다.
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

## 구조

```
public/index.html      페이지 전체 (마크업, 스타일, 인식 로직)
wrangler.jsonc         Pages 프로젝트 ggongcam, 출력 폴더 public/
tools/check.mjs        인라인 스크립트 문법 검사
.github/workflows/     qa (문법 검사)
```

## 사용법

1. 배경 클래스부터 샘플 수집 (바닥, 보도블록, 낙엽, 손). 수집 버튼이나 숫자키 1~4를 누르고 있는 동안 초당 약 10장.
2. 클래스마다 50장 이상, 각도·거리·조명을 바꿔가며 수집.
3. 두 클래스 이상 모이면 실시간 판정. 같은 판정이 정해진 프레임 수만큼 이어지면 감지 기록에 캡처.
4. 샘플은 브라우저 localStorage에 자동 저장. JSON 내보내기/불러오기로 팀원과 공유.

## 한계와 다음 단계

- 판정 영역 안에 무엇이 있는지만 분류한다. 위치(바운딩 박스)는 모른다.
- 실제 수거용으로는 모은 캡처로 데이터셋을 만들어 YOLO 계열 객체 탐지 모델을 학습시키고, 라즈베리파이에서 돌리는 단계로 넘어간다.
- MobileNet v2 로드에 실패하면 v1으로 대체되는데, 이때 v2로 저장한 샘플(1280차원)과 차원이 달라 불러올 수 없다.
