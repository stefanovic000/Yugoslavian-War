import socket, json, time, sys

HOST, PORT = "127.0.0.1", 7777


class C:
    def __init__(self, name):
        self.name = name
        self.s = socket.create_connection((HOST, PORT), 3)
        self.s.settimeout(0.05)
        self.buf = b""
        self.inbox = []
        self.closed = False

    def send(self, o):
        self.s.sendall((json.dumps(o) + "\n").encode())

    def _read(self):
        try:
            while True:
                d = self.s.recv(65536)
                if not d:
                    break
                self.buf += d
        except (BlockingIOError, socket.timeout):
            pass
        except OSError:
            self.closed = True
        while b"\n" in self.buf:
            line, self.buf = self.buf.split(b"\n", 1)
            if line.strip():
                self.inbox.append(json.loads(line))

    def poll(self):
        self._read()
        out = self.inbox
        self.inbox = []
        return out

    def wait(self, kind, timeout=3):
        end = time.time() + timeout
        while time.time() < end:
            self._read()
            for i, m in enumerate(self.inbox):
                if m.get("type") == kind:
                    return self.inbox.pop(i)
            time.sleep(0.01)
        return None


def check(cond, msg):
    if not cond:
        print("FAIL:", msg)
        sys.exit(1)
    print("PASS:", msg)


host = C("HOST")
target = C("TARGET")
spec = C("SPEC")

for c in (host, target, spec):
    c.send({"type": "hello", "name": c.name})
    welcome = c.wait("welcome")
    check(welcome is not None, c.name + " welcome")
    c.id = welcome["selfId"]

host.send({"type": "create", "name": "SEC TEST"})
joined = host.wait("joined")
check(joined is not None, "room created")
room_id = joined["room"]["id"]

target.send({"type": "join", "room": room_id})
check(target.wait("joined") is not None, "target joined")
check(host.wait("room") is not None, "host room state")

host.send({"type": "start"})
ms = target.wait("match_start")
check(ms is not None, "match started for target")
check(host.wait("match_start") is not None, "match started for host")

spec.send({"type": "join", "room": room_id})
sj = spec.wait("joined")
check(sj is not None and sj.get("spectator") is True, "started room join is spectator")
check(spec.wait("match_start").get("spectator") is True, "spectator receives match start")

host.send({"type": "kick", "target": target.id})
kicked = target.wait("kicked")
check(kicked is not None, "target was kicked")
target.send({"type": "join", "room": room_id})
err = target.wait("error")
check(err is not None and "banned" in err.get("message", "").lower(), "kicked IP is banned from room")

# Flood: the server must close or ignore a client that sends far past the rate.
flood = C("FLOOD")
flood.send({"type": "hello", "name": "FLOOD"})
flood.wait("welcome")
try:
    for _ in range(600):
        flood.send({"type": "ping", "t": 0})
except OSError:
    pass
time.sleep(0.5)
flood_msgs = flood.poll()
check(flood.closed or len(flood_msgs) < 600, "server closed or throttled the flood connection")
print("PASS: flood connection handled, residual messages:", len(flood_msgs))

for c in (host, target, spec, flood):
    try:
        c.s.close()
    except OSError:
        pass
print("SERVER INTEGRATION OK")
