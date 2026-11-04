import socket, json, time, sys

HOST, PORT = "127.0.0.1", 7777


class Bot:
    def __init__(self, name):
        self.name = name
        self.s = socket.create_connection((HOST, PORT), 5)
        self.s.settimeout(0.05)
        self.buf = b""
        self.room = None
        self.seq = 0

    def send(self, o):
        self.s.sendall((json.dumps(o) + "\n").encode())

    def poll(self):
        out = []
        try:
            while True:
                d = self.s.recv(65536)
                if not d:
                    break
                self.buf += d
        except (BlockingIOError, socket.timeout):
            pass
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            if line.strip():
                out.append(json.loads(line))
        return out


host = Bot("HOST")
guest = Bot("GUEST")
for b in (host, guest):
    b.send({"type": "hello", "name": b.name})
time.sleep(0.2)
for b in (host, guest):
    b.poll()

host.send({"type": "create", "name": "SPECTATOR DEMO"})
time.sleep(0.2)
for m in host.poll():
    if m.get("type") == "joined":
        host.room = m["room"]["id"]
guest.send({"type": "join", "room": host.room})
time.sleep(0.2)
guest.poll()
host.poll()
host.send({"type": "start"})
time.sleep(0.3)
for b in (host, guest):
    for m in b.poll():
        if m.get("type") == "match_start":
            print(b.name, "MATCH", flush=True)

end = time.time() + 30
while time.time() < end:
    for b in (host, guest):
        b.seq += 1
        b.send({"type": "input", "seq": b.seq, "throttle": 0.75, "pitch": 0.05, "fire": False})
        b.poll()
    time.sleep(1 / 60)
