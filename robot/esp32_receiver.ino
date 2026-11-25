// 꽁줍이 비전 -> ESP32/아두이노 시리얼 수신 예제
// 페이지 로봇 탭: 시리얼 연결, 형식 "CSV 한 줄", 속도 115200
// 수신 형식: T,X,Y,conf,in,n  (X: 오른쪽 +mm, Y: 앞 +mm, in: 집기 영역 안 1/0)
//            N,n              (목표 없음)

String line;

void setup() {
  Serial.begin(115200);
  Serial.println("READY");
}

void onTarget(int x, int y, float conf, bool inZone, int n) {
  // 여기서 바퀴, 로봇팔 제어. 지금은 받은 값을 되돌려 보낸다(페이지 콘솔에 < 로 보임).
  if (inZone) {
    Serial.println("PICK");            // 집기 동작 시작
  } else {
    Serial.printf("MOVE %d %d\n", x, y);  // 목표 쪽으로 이동
  }
}

void handle(const String& s) {
  if (s.startsWith("T,")) {
    int x, y, in, n; float conf;
    if (sscanf(s.c_str(), "T,%d,%d,%f,%d,%d", &x, &y, &conf, &in, &n) == 5) onTarget(x, y, conf, in == 1, n);
  } else if (s.startsWith("N,")) {
    // 목표 없음: 탐색 동작
  } else if (s == "HOME") {
    Serial.println("OK HOME");
  }
}

void loop() {
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\n') { line.trim(); if (line.length()) handle(line); line = ""; }
    else if (line.length() < 120) line += c;
  }
}
