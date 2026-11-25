"""꽁줍이 비전 -> 라즈베리파이 WebSocket 수신 예제.
pip install websockets
python ws_server.py            # ws://<파이 IP>:8765
페이지는 https 라서 ws:// 연결이 막힐 수 있다. 이때는 페이지를 파이나 노트북에서
로컬로 열거나(python -m http.server 로 public/ 제공), wss:// 를 쓴다.
"""
import asyncio, json
import websockets

async def handle(ws):
    print("연결됨", ws.remote_address)
    async for msg in ws:
        msg = msg.strip()
        if msg.startswith("{"):
            d = json.loads(msg); t = d.get("tgt")
            if t: print(f"목표 x={t['x']}mm y={t['y']}mm 신뢰도={t['conf']} 영역안={t['in']}")
        elif msg.startswith("T,"):
            _, x, y, conf, inz, n = msg.split(",")
            print(f"목표 x={x}mm y={y}mm 신뢰도={conf} 영역안={inz}")
            if inz == "1":
                await ws.send("PICK")
        else:
            print("받음:", msg)
            await ws.send("OK " + msg)

async def main():
    async with websockets.serve(handle, "0.0.0.0", 8765):
        print("ws://0.0.0.0:8765 대기 중")
        await asyncio.Future()

asyncio.run(main())
