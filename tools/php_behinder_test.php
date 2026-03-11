<?php
/**
 * 冰蝎 bing.php 加密测试脚本
 * 用法：php tools/php_behinder_test.php
 *
 * 用于验证 Dart 端加密与 PHP 解密是否一致。
 * 将输出的 base64 用 curl 发送到 bing.php 可测试连接。
 */
$key = "e45e329feb5d925b";
$plain = "C|echo 'MATRIX_PHP_PING';";

echo "=== 冰蝎 PHP 加密测试 ===\n";
echo "Key: $key\n";
echo "Plain: $plain\n\n";

// 测试 PHP 支持的 AES 相关 cipher
$ciphers = openssl_get_cipher_methods();
$relevant = array_filter($ciphers, fn($c) => stripos($c, 'aes') !== false && stripos($c, '128') !== false);
echo "可用的 AES-128 算法: " . implode(", ", array_slice($relevant, 0, 10)) . "\n\n";

// 检查 "AES128" 是否存在
if (in_array("AES128", $ciphers)) {
    echo "AES128 存在，尝试加密...\n";
    $enc = openssl_encrypt($plain, "AES128", $key);
    echo "PHP openssl_encrypt(AES128) base64: " . substr($enc, 0, 60) . "...\n";
    $dec = openssl_decrypt($enc, "AES128", $key);
    echo "解密验证: " . ($dec === $plain ? "OK" : "FAIL") . "\n\n";
} else {
    echo "AES128 不存在于当前 OpenSSL\n\n";
}

// 测试 aes-128-ecb
if (in_array("aes-128-ecb", $ciphers)) {
    echo "aes-128-ecb 测试:\n";
    $enc = openssl_encrypt($plain, "aes-128-ecb", $key);
    echo "加密结果(base64): " . substr($enc, 0, 60) . "...\n";
    $dec = openssl_decrypt($enc, "aes-128-ecb", $key);
    echo "解密验证: " . ($dec === $plain ? "OK" : "FAIL") . "\n\n";
}

// 测试 aes-128-cbc + 零 IV
if (in_array("aes-128-cbc", $ciphers)) {
    echo "aes-128-cbc (零IV) 测试:\n";
    $iv = str_repeat("\0", 16);
    $enc = openssl_encrypt($plain, "aes-128-cbc", $key, 0, $iv);
    echo "加密结果(base64): " . substr($enc, 0, 60) . "...\n";
    $dec = openssl_decrypt($enc, "aes-128-cbc", $key, 0, $iv);
    echo "解密验证: " . ($dec === $plain ? "OK" : "FAIL") . "\n\n";
}
