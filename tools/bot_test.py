import socket, json, time, sys

s = socket.create_connection(("127.0.0.1", 7777), 5)
s.settimeout(0.05)
buf = b""
started = False
room_id = None
seq = 0

def send(o):
    s.sendall((json.dumps(o) + "\n").encode())

def drain():
    global buf
    msgs = []
    try:
        while True:
            d = s.recv(65536)
            if not d:
                break
            buf += d
    except (BlockingIOError, socket.timeout):
        pass
    while b"\n" in buf:
        line, buf = buf.split(b"\n", 1)
        if line.strip():
            msgs.append(json.loads(line))
    return msgs

send({"type": "hello", "name": "BOT"})
time.sleep(0.2)
drain()
send({"type": "create", "name": "BOT DUEL"})
time.sleep(0.2)
for m in drain():
    if m.get("type") == "joined":
        room_id = m["room"]["id"]
print("BOT ROOM", room_id, flush=True)

end = time.time() + 25
last_input = 0
while time.time() < end:
    for m in drain():
        if m.get("type") == "room":
            room = m["room"]
            if not started and len(room["players"]) >= 2 and room["status"] == "lobby":
                send({"type": "start"})
                started = True
                print("BOT STARTED", room, flush=True)
        if m.get("type") == "match_start":
            print("BOT MATCH", m, flush=True)
    now = time.time()
    if now - last_input > 1 / 60:
        last_input = now
        seq += 1
        send({"type": "input", "seq": seq, "throttle": 0.8, "pitch": 0.1, "fire": False})
    time.sleep(0.005)
